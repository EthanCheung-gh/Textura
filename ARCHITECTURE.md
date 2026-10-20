# Textura · 织理 — 架构说明

本文描述 0.1.0 的实际实现。工程契约（字段、签名、所有权规则）以
[docs/contract.md](docs/contract.md) 为准，本文解释**为什么这样组织**。

## 1. 分层

```
┌───────────────────────────────────────────────────────────────┐
│ 应用外壳  src/app/                                             │
│   AppShell（按 ui.route 分发）· Sidebar · TopBar · ROUTES       │
│   RouteErrorBoundary（视图崩溃兜底，外壳不白屏）                │
└───────────────┬───────────────────────────────────────────────┘
                │  ui.route: 'dashboard' | 'okr' | 'gtd' | 'gantt' | 'sop' | 'settings'
┌───────────────▼───────────────────────────────────────────────┐
│ 视图模块  src/modules/                                         │
│   dashboard/  okr/  gtd/  gantt/  sop/  appshell/              │
│   只读 core；写操作一律调用 store 动作；领域计算一律调 selectors │
└───────────────┬───────────────────────────────────────────────┘
                │  useWorkspace(selector) / getWorkspace()
┌───────────────▼───────────────────────────────────────────────┐
│ 统一任务内核  src/core/                                        │
│   model.ts（唯一实体定义） · selectors.ts（纯函数 + 环检测）    │
│   store.ts（唯一 store：单条/批量写 + 历史 + 串行保存）         │
│   repo.ts（归一化 + 版本/环处理 + 持久化适配）                  │
│   routeState.ts（深链与视图记忆） · fixtures.ts（演示数据）     │
└───────────────┬───────────────────────────────────────────────┘
                │  repo.ts：Tauri 环境 invoke（async 命令），否则 localStorage
┌───────────────▼───────────────────────────────────────────────┐
│ 持久化  src-tauri/src/                                         │
│   commands.rs（8 个命令，spawn_blocking）                       │
│   storage.rs（原子写 / .bak / 30 份轮换 / 版本与环修复副本）    │
│   app_data_dir/workspace.json + backups/textura-*.json         │
└───────────────────────────────────────────────────────────────┘
```

约束：模块之间**不互相 import**。跨视图跳转只通过 `setUi({ route })` + `select(id)`，
跳转规则集中在 `src/modules/appshell/navigation.ts`（`routeForItemKind`）。

术语约定：`Area` 的中文界面名统一为**「领域」**，代码注释、日志、文档与 UI 都使用这一译法。

## 2. 统一任务内核

### 2.1 四类实体

| 实体 | 定义 | 说明 |
| --- | --- | --- |
| `Item` | `src/core/model.ts` | 唯一的任务实体。树结构（`parentId` + `order`）承载 O→KR、项目→行动、SOP→步骤 |
| `Edge` | 同上 | 四类关系：`okr`（objective→keyresult）、`flow`（step→step）、`depends`（from 依赖 to）、`related` |
| `Area` | 同上 | 领域（产品 / 运营 / 个人…），带颜色与排序 |
| `SopRunEntry` | 同上 | 一次步骤运行：`sopId` + `stepId` + `result` + 时间 + 备注 |
| `Workspace` | 同上 | `{ version, items, edges, areas, runs, updatedAt }`，版本号当前为 1 |

四类实体之外没有第五种容器：SOP 是 `kind: 'sop'` 的 Item，步骤是它的子 Item；
甘特条不是独立对象，只是 `item.gantt` 的一段日期区间。

### 2.2 `kind` 语义

| kind | 主要视图 | 数据块 | 备注 |
| --- | --- | --- | --- |
| `objective` | OKR / 今日 | `okr.period`、`okr.confidence`、子 `keyresult` | 进度 = KR 平均 |
| `keyresult` | OKR | `okr.metric`、`okr.krOwner` | 有指标时按指标换算进度 |
| `project` | 甘特 / GTD / 今日 | `gantt.start/end`、子 `action` | 甘特顶层分组 |
| `action` | GTD / 甘特 / 今日 | `gtd.*`、`gantt.*` | 唯一能同时出现在三处的类型 |
| `sop` | SOP / 今日 | 子 `step` + `flow` 边 + `runs` | 进度 = 步骤完成比 |
| `step` | SOP 画布 | `sop.nodeType/canvas/checklist/owner/durationMin` | 不进入 GTD「下一步」 |
| `milestone` | 甘特 | `gantt.*` | 渲染为菱形标记 |
| `note` / `reference` | GTD 收件箱 | `gtd.*` | 默认状态 `inbox` |

### 2.3 `status` 语义

| status | 含义 | 出现在哪里 |
| --- | --- | --- |
| `inbox` | 已收集、未澄清 | GTD 收件箱、今日「收件箱待澄清」计数；甘特隐藏；不进「下一步」 |
| `next` | 可立即执行的下一步 | GTD 下一步（仅 action / project）、今日「无日期」桶、甘特（有日期时） |
| `active` | 进行中 | 甘特、项目健康度；不进「下一步」 |
| `waiting` | 已委派、等待他人 | GTD 等待中（算等待天数，>7 天提醒） |
| `scheduled` | 已排期但未开始 | 甘特 |
| `someday` | 某天 / 搁置 | GTD「某天 / 搁置」；甘特隐藏 |
| `done` | 完成 | 完成统计；甘特进度显示 100%；`completedAt` 由 store 维护 |
| `dropped` | 放弃 | 甘特隐藏；项目健康度把 done 与 dropped 都算「已收尾」，但 `rollupProgress` 只把 done 计入完成比 |

### 2.4 四个视图如何消费同一份数据

| 视图 | 读 | 写 |
| --- | --- | --- |
| 今日 | `overdueItems`、`dueTodayItems`、`nextActions`、`inboxItems`、`objectivesOfPeriod` + `rollupProgress`、`sopGraph`、`completedAt`、`runs` | `toggleDone`、`createItem`（目标 / SOP 快捷创建）、`select`、`setUi` |
| OKR | `objectivesOfPeriod`、`childrenOf`（KR）、`okr.metric/confidence`、`edgeTargetsOf(…, 'okr')` | 目标 / KR 增删改、`okr.metric`、`okr.confidence`、`okr.period`（移动 / 复制季度）、`okr` 边（关联执行项） |
| GTD | `inboxItems`、`nextActions`、`waitingItems`、`somedayItems`、`gtd.capturedAt/context/energy/waitingFor`、`gantt.end` | `updateItem`（标题、标签、场景、能量、截止日期、领域）、`setStatus`、`createItem`（升级为项目 / 转为行动）、`deleteItems` |
| 甘特 | `gantt.start/end`、`status`、`gantt.progress`、`depends` 边、`rollupProgress`（分组汇总） | `gantt.start/end`（拖拽、日期输入）、`gantt.progress`、`status`、`areaId`、`depends` 边、新建行动 |
| SOP | `sop.nodeType/canvas/checklist/owner/durationMin`、`flow` 边、`runs` | 节点增删、`sop.canvas`（拖动结束 / 自动布局）、检查项、连线标签、`logRun` |

同一字段被多个视图写入是**设计目标**而不是耦合：甘特改日期，GTD 的「今天/超期」与今日聚焦立刻变；
GTD 勾完成，甘特条与 OKR 汇总立刻变。

统计口径也共用：今日的「近 7 天完成」与 GTD 周回顾的「本周完成」都用
`differenceInCalendarDays(now, completedAt) ∈ [0, 7)`，按本地日历日计算，两边数字一致
（`src/modules/dashboard/today.ts:130`、`src/modules/gtd/gtdLogic.ts:302`）。

## 3. 数据流与一致性

### 3.1 写入路径

```
用户操作
  ├─ 单条写：createItem / updateItem / setStatus / createEdge / …
  │    → commit(recipe)
  │        1. history.record(cloneWorkspace(current))   // 1 次快照，最多 80 步
  │        2. workspace = recipe(current) + updatedAt   // 1 个新时间戳
  │        3. set({ workspace, saveState: 'idle' })     // 乐观更新，界面立即变
  │        4. scheduleSave()                            // 1 次 400ms 防抖
  │
  └─ 批量写：updateItems([{ id, patch }, …], { recordHistory? })
       → 1 次快照（同一 timestamp 写进所有被改 item 与 workspace.updatedAt）
       → 1 次 set + 1 次防抖

scheduleSave() ──400ms──► save()
  → persistWorkspace() 进入 saveQueue（串行队列）
       → repo.saveWorkspace(workspace)
            → Tauri invoke('save_workspace') / localStorage
               → saveState: 'saving' → 'saved' | 'error'
```

要点：

- **乐观更新**：界面不等磁盘。存储状态在侧栏底部显示「自动保存已开启 / 正在保存… / 已保存 / 保存失败」。
- **400ms 防抖**：连续拖拽、连续输入只落盘一次。拖拽类交互进一步把写回推迟到操作结束
  （甘特 `onDragCommit`、SOP `onNodeDragStop`）。
- **批量写入（`updateItems`）**：一次手势或一条命令只产生**一条历史**与**一次保存**。
  SOP 的拖动 / 自动布局（`positions.ts` 把 N 个节点坐标整理成 N 条 patch 后一次提交）与
  OKR 的「移动到其他季度」（目标 + 全部 KR 一次提交）都用它，所以 `Ctrl+Z` 一次整体回退。
  空数组、不存在的 id 会被忽略；`recordHistory: false` 只清 redo 栈。
- **80 步快照历史**：`undo/redo` 直接换回整份 `Workspace` 快照，之后同样触发一次防抖保存，
  所以「撤销」也会落盘。`load()` / `reload()` 清空历史。
- **保存串行化**：所有落盘都经过 `saveQueue`（Promise 链）。`load()`、`reload()`、`replaceWorkspace()`
  在写入前先 `await saveQueue`，避免旧内容晚于新内容 rename 到主文件。
- **输入提交时机**：OKR 指标编辑器是「草稿 + 600ms 防抖提交」，失焦 / Enter 立即提交，
  页面卸载、切换视图、窗口关闭前会先 flush 未提交输入再保存；SOP 检查器与甘特详情是失焦 / 回车提交。
- **同一内容不重复落盘**：Rust 侧对序列化结果做哈希，与上次成功写入一致时直接返回缓存
  `SaveInfo`。

### 3.2 `replaceWorkspace` 是整份替换的唯一入口

导入 JSON、重置为演示数据都必须走 `replaceWorkspace(next, { recordHistory })`：

1. `migrateWorkspaceWithReport(next)` 严格归一化（版本迁移、字段夹紧、环拒绝、`updatedAt` 刷新）；
   导入时先用 `parseWorkspaceText` 预校验，当时的修正摘要会带到这一步合并，避免二次归一化看不到原始非法值；
2. 取消待执行的防抖、`await saveQueue`，再推入一次完整快照 → 一次 `Ctrl+Z` 可回退整次导入 / 重置；
   `recordHistory: false` 不新增快照，但会清空 redo 栈；
3. 清空 `selectedId`，按 `load()` 相同规则重算 `ui.okrPeriod`；
4. 立即 `await repo.saveWorkspace`，`saveState` 走 `saving → saved`；失败时 `notify(error)` 并抛出；
5. 归一化产生修正时，`notify` 一次「已修正 N 处非法数据（详见控制台）」。

**禁止**直接写 `workspacePath`、localStorage 或调用底层文件写入来绕过它——绕过会失去原子写、
轮换备份与历史语义。

### 3.3 落盘与恢复

| 环节 | 行为 |
| --- | --- |
| 主文件 | `app_data_dir/workspace.json` |
| 原子写 | `workspace.json.tmp` → `write_all` → `fsync` → `rename` 覆盖 → 目录 `fsync` |
| 单次回滚 | 写前把旧文件复制为 `workspace.json.bak`（每次覆盖） |
| 轮换备份 | `backups/textura-YYYYMMDD-HHmmss.json`，同秒重名追加 `-2`、`-3`，保留最新 **30** 份 |
| 读取回退 | 主文件 → `.bak` → 最新轮换备份 → 空 `Workspace`；任一解析失败自动尝试下一个 |
| 首次安装 | 主文件、`.bak`、轮换备份**都不存在**时 `freshInstall = true`；任一存在（含空文件 / 损坏文件）为 `false` |
| 版本迁移 | 读取后若 `version < WORKSPACE_VERSION` 就升级并刷新 `updatedAt` |
| 未来版本 | `version > WORKSPACE_VERSION` 拒绝加载，先把原文件复制为 `workspace.future-v<N>.json`，主文件不动 |
| 环修复副本 | `workspace.repaired-<YYYYMMDD-HHmmss>[-n].json`，只在加载发现环时生成，不参与轮换、不覆盖主文件 |
| 命令并发 | `load_workspace` / `save_workspace` / `restore_backup` / `save_repaired_workspace` 为 `async` 命令，内部 `spawn_blocking`；整个 save 临界区（`.bak` → tmp → fsync → rename → rotation → 缓存）由 `save_lock` 串行化 |
| 锁中毒 | 所有 Mutex 使用 `unwrap_or_else(|poisoned| poisoned.into_inner())`：锁只保护缓存与串行化，一次 panic 不应让应用永久不可用 |
| 安全 | 备份名必须是 `textura-*.json` 单段文件名，拒绝 `..`、`/`、`\`（路径穿越） |
| 导入 / 导出 | 导出为缩进 2 空格的 JSON；导入只读取文本，由前端归一化后再 `replaceWorkspace` |

### 3.4 父子环：检测与修复策略

`selectors.findParentCycles(ws)` 沿 `parentId` 走链，返回形如 `['a', 'b', 'a']` 的路径数组。

| 路径 | 行为 |
| --- | --- |
| 导入（`migrateWorkspace` / `parseWorkspaceText`） | **拒绝**，抛出「数据中存在父子环：A → B → A，请修复后重试」，由设置页展示错误，不写入任何数据 |
| 加载（`normalizeForLoad`） | **修复**：每个环切断一条 `parentId`（被切断的节点变为根级），保留其余数据；不弹窗、不清库、不白屏 |
| 修复后落盘 | 不自动覆盖主文件；先把修复结果另存为 `workspace.repaired-<时间戳>.json`，并提示「原始文件未被覆盖；下次编辑会写回修复结果」 |
| 日志 | `console.warn` 只记录环路径、被切断的 id 与原 parentId、时间戳，不输出完整工作区 JSON |

取舍：加载路径选择「可用优先」——脏数据不应让应用打不开；导入路径选择「严格」——用户主动喂进来的
文件如果结构有问题，应当明确拒绝而不是悄悄改掉。两条路径共用同一套字段归一化规则。

### 3.5 版本策略

- `WORKSPACE_VERSION` 当前为 `1`，前端与 Rust 两侧各有一份常量。
- **低版本**：读取时升级版本号并补齐字段（v0 → v1 只补集合，无结构变化）。
- **高版本**：拒绝加载。Rust 侧 `read_workspace` 返回 `FutureVersion`，先把原文件复制成
  `workspace.future-v<N>.json`；前端 `WorkspaceVersionError` 让 `store.status = 'error'`，
  界面显示「工作区版本 N 高于当前应用支持的版本 1，请升级 Textura 后再打开」。
- 错误态下 `save()` 直接返回、`commit()` 不再排防抖保存，因此**不会用旧版本覆盖新文件**。
- 升级应用后重新打开即可读到原文件；副本只是保险，正常流程不需要人工处理。

### 3.6 归一化与前后端类型对齐

分工原则：**Rust 负责「写盘前必须合法的强类型」，前端负责「读入时不崩的宽容归一化」**。

| 层 | 职责 | 越界处理 |
| --- | --- | --- |
| Rust `model.rs` | serde 强类型结构体（`#[serde(default)]` 容忍缺字段） | 类型不符 / 数值非法直接反序列化失败，拒绝写入（`rejects_invalid_confidence_and_metric_before_save`） |
| 前端 `repo.ts` | `normalizeWorkspace` 逐字段校验并生成修正摘要 | 数值有限化并夹紧（`confidence` 1–10、`gantt.progress` 0–100、`order` 回落索引）；字符串 / 数组补默认；枚举白名单回落 |

前端归一化的枚举回落规则：

| 字段 | 非法值落点 | 理由 |
| --- | --- | --- |
| `kind` | `note` | 保守落入收件箱 / 笔记，不进入「下一步」 |
| `status` | `next` | 保持可见、可处理 |
| `sop.nodeType` | `action` | 流程里最通用的节点 |
| `gtd.energy` | 省略 | 能量只是筛选维度 |
| `runs[].result` | `skip` | 不把无法识别的结果算成通过 |
| `edge.type` | `related` | 不影响任何流程 / 依赖语义 |

修正摘要为 `{ total, entries }`，`entries` 最多保留 20 条（`itemId` / `field` / `from` / `to`）：
加载或导入后只 `notify` 一次「已修正 N 处非法数据（详见控制台）」，完整摘要 `console.warn` 一次。

取舍：同一套取值域要在 TS 与 Rust 两处维护（契约 `docs/contract.md` 是唯一来源），
换来的是「旧文件能打开」与「新写入一定合法」两个保证；如果只做前端宽松，脏数据会一路写回磁盘。

### 3.7 CSP 与主题预置

生产构建启用 CSP（`src-tauri/tauri.conf.json` 的 `app.security.csp`）：

```text
default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline';
img-src 'self' asset: http://asset.localhost data:; font-src 'self' data:;
connect-src ipc: http://ipc.localhost; frame-ancestors 'none';
base-uri 'self'; form-action 'none'
```

- `script-src 'self'`：主题预置从内联脚本改为外置文件 `public/theme-init.js`（构建到 `/theme-init.js`），
  在首帧前应用 `localStorage['textura.theme']`，避免深色主题闪白；
- `style-src` 保留 `'unsafe-inline'`：React 与 `@xyflow/react` 使用内联 `style` 属性；
- `connect-src ipc: http://ipc.localhost`：Tauri v2 IPC；
- `devCsp` 额外放行 Vite HMR（`http://localhost:1420`、`ws://`）与 `'unsafe-eval'`。

### 3.8 渲染错误边界

`src/app/RouteErrorBoundary.tsx` 包住 `<RouteView>`，以 `route` 作为 `resetKey`（切视图自动清除错误）：

- 捕获渲染异常后显示可读兜底页，侧栏 / 顶栏 / 命令面板仍可用，不再整窗白屏；
- 三个动作：**返回今日**（清错误并切路由）、**保存并重新加载工作区**（先 `save()`，若
  `saveState = 'error'` 则取消重新加载并提示，避免丢掉刚提交的编辑）、**查看数据目录**
  （读取 `storageInfo().dataDir` 并尝试写入剪贴板）。

## 4. 模块边界与所有权

| 路径 | 所有者 | 说明 |
| --- | --- | --- |
| `src/core/*`、`src/app/*`、`src/styles/*`、`src/ui/*` | Phase A（冻结） | 模块 Worker 只读 |
| `src/main.tsx`、根配置、`docs/contract.md` | Phase A（冻结） | 只读 |
| `src/modules/sop/**` | sop Worker | 画布、检查器、运行、布局 |
| `src/modules/okr/**` | okr Worker | 季度、卡片 / 表格 / 对齐、指标与执行项 |
| `src/modules/gtd/**` | gtd Worker | 收件箱、澄清、下一步、等待、周回顾 |
| `src/modules/gantt/**` | gantt Worker | 时间轴、树、任务条、依赖、详情 |
| `src/modules/dashboard/**` | appshell Worker | 今日聚合视图 |
| `src/modules/appshell/**` | appshell Worker | 命令面板、快速收集、设置页、快捷键 |
| `src-tauri/**` | Phase A（冻结） | 模块不得修改 Rust 持久化 |

为什么模块只读 core：

- **单一事实来源**。进度汇总（`rollupProgress`）、树遍历（`childrenOf` / `ancestorsOf` / `descendantsOf`）、
  排期查询（`scheduledItemsInRange` / `overdueItems`）只有一份实现，四个视图不可能对「什么是完成」
  或「什么算超期」给出不同答案。
- **迁移可控**。字段变更只需改 `model.ts` + `repo.migrateWorkspace` + Rust `model.rs`，
  阅读代码时不必搜遍六个模块找同名字段的手写拷贝。
- **并行开发不冲突**。每个模块独占目录，公共改动必须回到契约层评审，避免两个 Worker 同时改
  `store.ts` 互相踩。

## 5. 关键设计决策与权衡

### 5.1 单文档原子写，而不是 SQLite

**选择**：整份 `Workspace` 序列化成一个 JSON，临时文件 + `fsync` + `rename` 覆盖，另有 `.bak` 与 30 份轮换备份。

**理由**：数据规模是「一个人的工作区」（千级条目），全量写一次几毫秒；单文件让备份、导出、
导入、跨设备手工搬移都是同一件事；`rename` 天然原子，不需要事务与迁移框架；Rust 侧只有几百行、
`cargo test` 能完整覆盖。

**代价**：写入是 O(整个工作区)，没有部分更新与并发写入；两个进程同时打开会互相覆盖（后写赢）。
突破到万级条目时需要换存储（见 §6）。

### 5.2 不用 react-router

**选择**：`ui.route` 是 store 里的字符串，`src/core/routeState.ts` 负责 `?route=` / `?item=` 深链与
`localStorage['textura.route']` 记忆。

**理由**：桌面应用只有六个平级视图，没有嵌套路由、没有 URL 参数驱动的数据加载；路由状态与
`okrPeriod`、`selectedId`、`inspectorOpen` 属于同一类 UI 状态，放在同一个 store 里可以一起断言、
一起持久化、一起被命令面板改写。深链只用于「从外部打开某个视图 / 某条记录」，用
`history.replaceState` 同步即可，不需要路由库。

**代价**：没有自动的代码分割与路由级懒加载；视图切换是同步渲染整个页面（当前页面组件量级下无感）。
将来若要加「浏览器前进后退」，需要自己实现 popstate 映射。

### 5.3 不用 UI 组件库

**选择**：`src/ui/*` 手写九个原语（Button / IconButton / Modal / Field / Badge / Progress / EmptyState /
Segmented / Icon），颜色、间距、圆角、阴影全部来自 `src/styles/tokens.css`。

**理由**：产品需要「暖纸感」的克制视觉与中文排版，组件库的默认密度和交互（弹层、焦点陷阱、
密集表格）几乎都要覆盖重写；九个原语的组件代码约 600 行，能保证键盘可达与 `aria-*` 一致，
并让六个模块共用同一套 focus ring 与间距节奏。

**代价**：没有现成的虚拟列表、日期选择器、可访问树控件；复杂交互（甘特拖拽、画布）仍需自行实现并
自行保证可访问性（例如任务条用 `role="button"` + 键盘选中）。

### 5.4 SOP 用 React Flow，甘特自己写

**选择**：SOP 画布用 `@xyflow/react` 12 + `@dagrejs/dagre`；甘特完全手写
（`gantt/scale.ts` 纯函数 + 绝对定位任务条 + 一段 SVG 依赖线）。

**理由**：SOP 需要的是通用节点编辑器能力——拖拽、连线、缩放平移、自定义节点、视口 API，
React Flow 已经把这些做对，自己写会花掉大部分工期。甘特需要的恰好相反：行高固定 36px、
日期到像素是纯线性映射、拖拽只有三种模式（整体 / 左边缘 / 右边缘）、依赖线要按「是否挡住通道」
绕行。用通用图库反而要对抗它的坐标系与交互模型，而 `scale.ts` 的纯函数可以直接被 26 个单测覆盖。

**代价**：两个视图的技术栈不一致，需要分别理解；React Flow 的默认署名水印必须保留（商业授权才能移除）。

### 5.5 统一内核，而不是四个子系统

**选择**：一个 `Item`、一个 store、一份历史、一份持久化。

**理由**：四个视图回答的是同一个问题「现在该做什么」，只是视角不同。分开建模就得写四套同步逻辑，
而同步逻辑一定会漂移。统一之后，「OKR 的 KR 关联甘特的行动」这种跨视图关系只是加一条 `okr` 边。

**代价**：`Item` 是宽表，字段按 `kind` 可选（`okr?` / `gtd?` / `gantt?` / `sop?`），类型上无法保证
「action 一定有 gantt」；为此 store 在 `createItem` 里补默认值、`repo.migrateWorkspace` 做兜底，
模块侧仍需判空。将来字段继续增加时应考虑按 `kind` 收窄为可辨识联合。

### 5.6 SOP 初始视口给「可读下限」，而不是一味 fit

**选择**：`sop/fit.ts` 的 `computeReadableViewport` 设置 zoom 下限 0.7（手动缩放仍可到 0.25），
低于下限时放弃「一屏看全」，改为从左上角 margin 开始，保证流程起点可见；宽而扁的旧坐标会先用
dagre 生成一份只影响显示的纵向预览。

**理由**：演示与真实流程往往有 7–10 个节点，硬塞进视口会把 13px 标题压到 5px，等于打开就是空白噪声。
先保证「能读」，再让用户自己缩放，比「能看全但看不清」更有用。

**代价**：首次打开可能看不到流程尾部；预览布局与已保存坐标不一致，第一次拖动时需要把预览坐标
一次性落盘（一次 `updateItems`，一次 `Ctrl+Z` 回退，见 §5.8 与 README 的已知限制）。

### 5.7 甘特进度「done 恒为 100%，但不写回」

**选择**：`displayProgress(item)`：`status === 'done'` 返回 100，否则取 `gantt.progress`；
详情面板在已完成时禁用进度滑杆，不修改底层数值。

**理由**：`status` 是完成与否的唯一事实来源，`gantt.progress` 是「做了多少」的手工估计。若勾完成时
把 100 写进 `progress`，取消完成就再也回不到原来的 70%。展示层做一次映射，两个字段各自保持语义。

**代价**：甘特条的 100% 与 `gantt.progress` 可能不一致（数据里是 70，条形是满的），需要在详情面板
用一行说明「已完成条目进度按 100% 显示」。

### 5.8 批量写入（`updateItems`），而不是 N 次 `updateItem`

**选择**：`updateItems(patches, { recordHistory })` 只压一次历史、写一个 `updatedAt`、排一次防抖保存；
SOP 的拖动 / 自动布局与 OKR 的跨季度移动都改用它。

**理由**：一次拖动会同时改变多个节点坐标，如果逐条 `updateItem`，用户要按 7 次 `Ctrl+Z` 才能退回
拖动前，中间态还会各触发一次保存（写放大）。「一次手势 = 一步撤销」才是符合直觉的粒度。

**代价**：批量写入绕过了 `commit()` 的统一入口，需要自己保证「一次快照 + 一个时间戳 + 一次调度」
这三件事（`store.test.ts` 有专门断言）；调用方必须把语义上属于同一动作的修改合并成一批，
否则一次拖动又会被拆成多步。

### 5.9 Rust 强类型校验 + 前端宽容归一化

**选择**：写盘前由 serde 强类型兜底（非法数值直接拒绝保存），读入时由前端做字段夹紧与枚举回落，
并生成修正摘要。

**理由**：两端的失败模式不同。写盘失败必须显式（宁可不写，也不把 `confidence: 200` 落进文件）；
而读取失败会让用户打不开自己的数据，所以读取路径必须「尽最大努力恢复 + 明确告知改了什么」。
环的处理正好体现这条分界：导入拒绝、加载修复。

**代价**：同一套取值域在 TS 与 Rust 各维护一份（契约是唯一来源），加字段时要同步两边；
前端归一化会掩盖上游写入的 bug，只能靠「已修正 N 处非法数据」的提示与控制台摘要暴露。

## 6. 性能与规模假设

当前设计的前提是「一个人的工作区」：

| 维度 | 现状 | 合理上限 | 超限后需要改什么 |
| --- | --- | --- | --- |
| 条目数 | 演示数据 30 条 | **舒适的 2,000–5,000 条；约 1 万条开始明显退化** | 拆分存储（按领域 / 季度分文件）或换 SQLite + 增量写 |
| 单次保存 | 全量序列化 + 哈希 + 原子写 | 3MB 以内（约 5,000 条带日期条目） | 保存改为增量 / 后台线程（Rust 侧已在 `spawn_blocking`） |
| 磁盘占用 | 主文件 + `.bak` + 30 份轮换 | 32 × 单文件大小（5,000 条约 100MB；1 万条约 200MB+） | 降低轮换份数或改为按天保留 |
| 渲染 | 每个页面订阅整个 `workspace` | 千级条目、单视图百级节点 | 引入细粒度 selector / 分页 / 虚拟列表 |
| 甘特 | 时间轴只渲染可视行（±400px 预取），**左侧树未虚拟化**，表头按整个区间生成 | 日视图跨度 1 年 ≈ 365 列 | 表头虚拟化 + 左侧树虚拟化 |
| SOP 画布 | React Flow 渲染全部节点与边 | 数百节点 | 折叠子流程 / 分页画布 / 只渲染视口内节点 |
| 历史 | 80 份整份快照（结构化克隆） | 5,000 条 × 80 步 ≈ 数百 MB 内存 | 改为写操作日志或增量补丁 |
| 前端产物 | 单个主 chunk 约 650 KiB 未压缩 | 桌面端本地加载，无网络成本 | 需要首屏更快时再拆分路由 chunk |

具体说明：

- **甘特虚拟化**：`GanttTimeline` 按 `viewport.scrollTop/height` 计算可视行窗口，只为可见行生成任务条与
  依赖矩形；拖动中的那一行永远保留渲染。左侧树（`GanttTree`）当前仍会为全部行生成 DOM。
- **SOP 拖拽只在结束时写回**：拖动过程只更新本地 `drafts`（`onNodesChange`），
  `onNodeDragStop` 才通过一次 `updateItems` 写回；自动布局与「物化预览」同样是一次批量写回。
- **全量订阅的代价**：页面普遍用 `useWorkspace((s) => s.workspace)`，任何写操作都会让当前页面重渲染。
  在千级条目下配合 `useMemo` 尚可接受；这是最容易被规模突破点击穿的地方。
- **写放大**：每次保存都是整份序列化 + `.bak` 复制 + 轮换副本写入，约 1 万条时单次保存的文件 IO
  会达到数 MB 量级；Rust 侧用 `spawn_blocking` 把这段工作移出 IPC 线程，但磁盘写入量本身无法避免。

## 7. 扩展指南

### 7.1 新增一个视图

按顺序改动（前四项属于 `src/core` / `src/app`，需要契约层评审）：

1. `src/core/store.ts`：`Route` 联合类型加成员（`UiState.route` 同步）。
2. `src/core/routeState.ts`：`ROUTE_IDS` 加成员，深链 `?route=` 才认。
3. `src/app/routes.ts`：`ROUTES` 加一条 `{ id, label, title, subtitle, icon }`（侧栏、顶栏、命令面板
   「前往…」自动生效）。
4. `src/ui/icons.tsx`：若需要新图标，在 `IconName` 与图标表里补；否则复用现有图标。
5. `src/app/AppShell.tsx`：`RouteView` 的 `switch` 加分支。
6. `src/modules/<view>/`：新建目录与入口组件，导出名与文件名一致；
   样式写在模块自己的 CSS 文件里并 `import`。
7. 如需从其他视图跳过来：扩展 `src/modules/appshell/navigation.ts` 的 `routeForItemKind`，
   或在调用处 `setUi({ route: '<view>' })`。

必须遵守：

- 领域计算只调用 `src/core/selectors.ts`；树遍历、进度汇总、排期查询、环检测不要在模块内重写。
- 所有读写走 store 动作，不直接改 `workspace` 对象；撤销用 `undo/redo`，不要维护第二套历史。
- **一次手势 / 一条命令只写一次**：同一动作涉及多个条目时用 `updateItems` 合并成一批，
  而不是循环 `updateItem`，否则 `Ctrl+Z` 会退很多步。
- 颜色 / 圆角 / 阴影 / 间距只使用 `src/styles/tokens.css` 的变量，不硬编码色值；
  实心强调底用 `--accent-strong*` + `--text-on-strong`，tint 底上的语义文字用 `--*-ink`。
- 页面根节点沿用 `.page`、`.page-header`、`.page-actions` 的留白节奏。
- 视图内的渲染异常应能在 `RouteErrorBoundary` 下恢复，不要在模块内 `throw` 到外壳之外。
- 新增纯函数逻辑时同时加 `*.test.ts`（vitest 覆盖 `src/**/*.test.ts`）。

### 7.2 新增一个顶层字段

例如给 `Item` 加 `recurrence?: { rule: string }`。改动顺序固定，避免落盘后丢数据：

1. **模型**：`src/core/model.ts` 的 `Item`（及 `NewItemInput` / `ItemPatch` 如需要）。
2. **归一化**：`src/core/repo.ts` 的 `normalizeItem` 补默认值并对非法值做夹紧 / 枚举回落，
   同时在 `collectCorrections` 里登记差异（这样旧文件被修正时会提示「已修正 N 处非法数据」）；
   若结构不兼容，提升 `WORKSPACE_VERSION` 并在 `migrateWorkspaceWithReport` 写迁移分支。
3. **写入默认值**：`src/core/store.ts` 的 `createItem`（按 kind 决定默认值）与 `applyItemPatch`
   （按块浅合并，`undefined` 忽略）；批量场景加到 `updateItems` 的调用方。
4. **查询**：需要的派生逻辑加到 `src/core/selectors.ts`，保持纯函数。
5. **Rust 侧**：`src-tauri/src/model.rs` 对应结构体加字段，务必带 `#[serde(default)]`
   （该文件里所有结构体都已用 `default`，新增字段要保持同一风格），否则旧文件反序列化失败；
   若字段有取值域（如 1–10），要同时决定 Rust 是「拒绝」还是「前端夹紧」。
6. **演示数据**：`src/core/fixtures.ts`，让新字段在四个视图里立刻可见。
7. **测试**：`src/core/store.test.ts`（createItem 默认值与补丁合并）、`repo.test.ts`（归一化与修正摘要）、
   `selectors.test.ts`、必要时 `fixtures.test.ts`；Rust 侧在 `storage.rs` 的测试里补一条 round-trip。

一致性检查清单：`migrateWorkspace` 能读旧文件；`save → load` 后字段还在；撤销后字段回到旧值；
`replaceWorkspace` 导入旧版本文件不报错；含非法值的新字段能在导入后提示修正条数。
