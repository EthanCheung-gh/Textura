# Textura · 织理 — 工程契约（v0.1.0，Phase A 冻结）

> 本文档是并行开发的唯一对齐依据。**模块 Worker 只允许修改自己的目录**，并必须复用此处定义的
> 模型、store、selectors、UI 原语与设计令牌。任何对 `src/core/*`、`src/app/*`、`src/ui/*` 的
> 字段/签名改动都必须先回到契约层评审，不得在模块内私自扩展。

- 产品：单机优先的结构化执行工作台
- 品牌：Textura / 织理
- 版本：0.1.0
- 技术栈：Tauri v2 + React 18.3.1 + TypeScript strict + Vite 7 + Zustand 5 +
  @xyflow/react 12 + @dagrejs/dagre + date-fns 4 + clsx
- 无 react-router（路由是 store 里的字符串状态）、无 Tailwind、无 UI 组件库
- 强调色：**陶土橙 `#C0663A`**（dark 主题为 `#D97A4C`）
- 视觉基调：暖纸感中性底色 + 墨色文字，1px 边框 + 极轻阴影，克制的 4/8/14px 圆角

---

## 1. 统一任务内核（`src/core/model.ts`）

OKR / GTD / 甘特 / SOP 四个视图共享同一个 `Item` 实体，只是读取不同的数据块：

| kind | 主要视图 | 数据块 |
| --- | --- | --- |
| `objective` | OKR | `okr` |
| `keyresult` | OKR | `okr.metric` |
| `project` | 甘特 / 今日 | `gantt` + 子 `action` |
| `action` | GTD / 甘特 / 今日 | `gtd`、`gantt` |
| `sop` | SOP | `sop` + 子 `step` |
| `step` | SOP 画布 | `sop.nodeType/canvas/checklist` |
| `milestone` | 甘特 | `gantt` |
| `note` / `reference` | GTD 收件箱 | `gtd` |

```ts
export type ItemKind = 'objective' | 'keyresult' | 'project' | 'action' | 'sop' | 'step' | 'milestone' | 'note' | 'reference';
export type ItemStatus = 'inbox' | 'next' | 'active' | 'waiting' | 'scheduled' | 'someday' | 'done' | 'dropped';
export type Energy = 'low' | 'medium' | 'high';
export type SopNodeType = 'start' | 'action' | 'decision' | 'check' | 'end' | 'note';
export type EdgeType = 'okr' | 'flow' | 'depends' | 'related';

export interface ChecklistEntry { id: string; text: string; done: boolean }
export interface OkrData {
  period: string;                      // 'YYYY-Qn'，例如当前季度 '2026-Q4'
  confidence: number;                  // 1..10
  metric?: { start: number; target: number; current: number; unit: string };
  krOwner?: string;
}
export interface SopData {
  nodeType: SopNodeType;
  canvas: { x: number; y: number };    // 画布绝对坐标（px），节点约 200x56
  checklist: ChecklistEntry[];
  owner?: string;
  durationMin?: number;
}
export interface GtdData {
  capturedAt: string;                  // ISO 时间戳
  clarified: boolean;
  context?: string;                    // '电脑' '电话'，不带 @
  energy?: Energy;
  waitingFor?: string;
  twoMinuteCandidate?: boolean;
}
export interface GanttData { start?: string | null; end?: string | null; progress: number } // 'YYYY-MM-DD'
export interface Item {
  id: string; kind: ItemKind; title: string; notes: string;
  parentId: string | null; order: number; status: ItemStatus;
  tags: string[]; areaId: string | null;
  createdAt: string; updatedAt: string; completedAt: string | null;
  okr?: OkrData; sop?: SopData; gtd?: GtdData; gantt?: GanttData;
}
export interface Edge { id: string; from: string; to: string; type: EdgeType; label: string }
export interface Area { id: string; name: string; color: string; order: number }
export interface SopRunEntry { id: string; sopId: string; stepId: string; at: string; result: 'pass' | 'fail' | 'skip'; note: string }
export interface Workspace { version: number; items: Item[]; edges: Edge[]; areas: Area[]; runs: SopRunEntry[]; updatedAt: string }
export const WORKSPACE_VERSION = 1;
```

补充类型（同文件导出）：

```ts
export interface NewItemInput {
  kind: ItemKind; title: string; notes?: string; parentId?: string | null;
  status?: ItemStatus; tags?: string[]; areaId?: string | null; order?: number;
  okr?: Partial<OkrData>; sop?: Partial<SopData>; gtd?: Partial<GtdData>; gantt?: Partial<GanttData>;
}
export type ItemPatch = Partial<Omit<Item, 'id' | 'kind' | 'createdAt' | 'okr' | 'sop' | 'gtd' | 'gantt'>> & {
  okr?: Partial<OkrData>; sop?: Partial<SopData>; gtd?: Partial<GtdData>; gantt?: Partial<GanttData>;
};
```

语义约定：

- `order` 只用于同级排序；`childrenOf` 按 `order` 升序（相同时按 `createdAt`）。
- `parentId = null` 表示根级。
- `completedAt` 由 store 维护：进入 `done` 写入当前时间，离开 `done` 清空。
- `Edge` 语义：
  - `okr`：objective → keyresult
  - `flow`：SOP step → step，`label` 例如「是 / 否」
  - `depends`：`from` 依赖 `to`（from 是依赖方，to 是前置）
  - `related`：自由关联
- `GtdData.context` 不带 `@`；UI 展示时自行加前缀。
- 日期字段：`gantt.start/end` 为 `YYYY-MM-DD`；其余时间为 ISO 8601。

---

## 2. Store（`src/core/store.ts`）

```ts
export const useWorkspace: UseBoundStore<StoreApi<WorkspaceStore>>;
export function getWorkspace(): WorkspaceStore;   // 返回完整 store state（含动作）
```

> `getWorkspace()` 等价于 `useWorkspace.getState()`，用于命令式/工具函数；React 内请使用
> `useWorkspace(selector)` 订阅。**不要**新建第二个 store。

### 状态

```ts
workspace: Workspace;
status: 'loading' | 'ready' | 'error';
saveState: 'idle' | 'saving' | 'saved' | 'error';
error: string | null;
selectedId: string | null;
ui: UiState;
notices: { id: string; message: string; tone: 'info' | 'success' | 'error'; at: string }[];

interface UiState {
  route: 'dashboard' | 'sop' | 'okr' | 'gtd' | 'gantt' | 'settings';
  theme: 'light' | 'dark';
  okrPeriod: string;
  ganttZoom: 'day' | 'week' | 'month';
  gtdContext: string | null;
  search: string;
  inspectorOpen: boolean;
  paletteOpen: boolean;
  quickCaptureOpen: boolean;
  shortcutsOpen: boolean;
}
```

### 动作（签名固定）

```ts
load(): Promise<void>;
save(): Promise<void>;
reload(): Promise<void>;
replaceWorkspace(next: Workspace, options?: { recordHistory?: boolean }): Promise<void>;

createItem(input: NewItemInput): Item;
updateItem(id: string, patch: ItemPatch): void;
updateItems(patches: Array<{ id: string; patch: ItemPatch }>, options?: { recordHistory?: boolean }): void;
deleteItems(ids: string[]): void;
moveItem(id: string, parentId: string | null, order?: number): void;
toggleDone(id: string): void;
setStatus(id: string, status: ItemStatus): void;

createEdge(input: { from: string; to: string; type: EdgeType; label?: string }): Edge;
updateEdge(id: string, patch: Partial<Omit<Edge, 'id'>>): void;
deleteEdge(id: string): void;

createArea(name: string): Area;
updateArea(id: string, patch: Partial<Omit<Area, 'id'>>): void;
deleteArea(id: string): void;

logRun(input: { sopId: string; stepId: string; result: 'pass' | 'fail' | 'skip'; note?: string }): SopRunEntry;

undo(): void;
redo(): void;
canUndo(): boolean;
canRedo(): boolean;

setUi(patch: Partial<UiState>): void;
select(id: string | null): void;
notify(message: string, tone?: 'info' | 'success' | 'error'): void;
```

行为：

- **历史**：每个写操作先把当前工作区深拷贝压入历史（`replaceWorkspace({ recordHistory: false })`
  例外），上限 80 步；`undo/redo` 会同步更新 `workspace.updatedAt` 并重新触发自动保存。
  `load()` 清空历史。
- **自动保存**：写操作 400ms 防抖调用 `save()`；`saveState` 依次反映 `idle → saving → saved`，
  失败为 `error` 并在 `error` 中给出原因。
- **replaceWorkspace（整份导入 / 重置的唯一入口）**：
  - 先用 `migrateWorkspace(next)` 归一化，版本迁移与字段兜底，并把 `updatedAt` 刷新为当前时间；
  - 默认（`recordHistory: true`）推入一次完整快照，`Ctrl+Z` 可回退整次导入；`recordHistory: false`
    不新增快照，同时清空 redo 栈；
  - 清空 `selectedId`，并按与 `load()` 相同的规则重置 `ui.okrPeriod`（当前季度优先，否则最新季度）；
  - 立即通过 `repo.saveWorkspace` 原子落盘并 `await`，`saveState` 依次为 `saving → saved`；
    失败时为 `error`，调用 `notify(..., 'error')` 并把原错误抛出，不吞异常；
  - **禁止**直接写 `workspacePath`、localStorage 或任何文件来绕过该动作。
- **createItem 默认值**：
  - `status`：`note`/`reference` 默认 `inbox`，其余默认 `next`；显式传入优先。
  - `objective`/`keyresult`：`okr = { period: 当前季度, confidence: 5, ...input.okr }`。
  - `sop`/`step`：`sop = { nodeType: 'action', canvas: {x:0,y:0}, checklist: [], ...input.sop }`。
  - `action`/`project`：`gantt = { start: null, end: null, progress: 0, ...input.gantt }`。
  - `action`：额外写入 `gtd = { capturedAt: now, clarified: status !== 'inbox', ...input.gtd }`；
    其他 kind 只有在显式传入 `gtd` 时才补 `capturedAt/clarified`。
  - `order` 未传时追加到同级末尾。
- **updateItem**：顶层字段浅合并（`undefined` 值被忽略）；`okr/sop/gtd/gantt` 按块合并，
  `sop.canvas` 逐字段合并；任何更新都刷新 `updatedAt`。
- **updateItems**：批量局部更新。只压一次历史快照（默认；`recordHistory: false` 时只清 redo），
  所有 item 与 workspace 共用同一个 `updatedAt`，只触发一次 400ms 防抖保存；空数组与不存在的 id 被忽略。
- **deleteItems**：级联删除所有子孙、两端涉及的 `edges`、引用被删 SOP/step 的 `runs`；
  若当前 `selectedId` 被删则置空。
- **moveItem**：拒绝移动到自身或自身子孙下；重排新旧父级的 `order`，按 `order` 插入指定位置。
- **createEdge**：相同 `from + to + type` 已存在时直接返回旧边（不重复写历史）。
- **createArea**：按调色板顺序取色（见 `utils.areaPalette`）。
- **deleteArea**：其下 item 的 `areaId` 置空。
- **setUi**：切换主题时同步 `document.documentElement.dataset.theme` 与
  `localStorage['textura.theme']`。
- **notify**：最多保留 4 条，非 error 提示 3.5s 后自动消失。
- **load 安全性**：`load()`/`reload()` 开头先 `await saveQueue`，不会丢弃在途保存。
  读取 `LoadResult { workspace, freshInstall }`。只有 `freshInstall === true` 且工作区为空时
  才播种演示数据；用户主动导入/清空后的空工作区重启保持为空。
  加载到父子环时，`normalizeForLoad` 切断每个环的一条 `parentId`，保留磁盘原文件，并另存
  `workspace.repaired-<时间戳>.json`；`console.warn` 只记录环路径/被切断 id/原 parentId/时间戳，
  不再输出完整工作区 JSON。`notify` 会说明「下次编辑会写回修复结果」，不白屏、不静默丢数据。
  工作区版本高于当前应用时进入 `status='error'`，错误信息可读，`save()` 与防抖保存均不会执行。
- **修正提示**：加载/导入归一化产生修正时，只 `notify` 一次「已修正 N 处非法数据」；
  完整摘要（最多 20 条，含 itemId/字段/原值/新值）`console.warn` 一次。

---

## 3. Selectors（`src/core/selectors.ts`，全部纯函数）

```ts
itemById(ws, id): Item | undefined
areaById(ws, id): Area | undefined
findParentCycles(ws): string[][]                                  // ['a','b','a']，无环 []
childrenOf(ws, parentId: string | null): Item[]                 // order 升序；null 取根级
descendantsOf(ws, id): Item[]                                  // 全部子孙，DFS
ancestorsOf(ws, id): Item[]                                    // 最近父级 → 根
itemsOfKind(ws, kind): Item[]
objectivesOfPeriod(ws, period): Item[]
okrPeriods(ws): string[]                                       // 倒序
rollupProgress(ws, id): number                                 // 0..100 整数
inboxItems(ws): Item[]
nextActions(ws): Item[]                                        // action/project 且 status=next
waitingItems(ws): Item[]
somedayItems(ws): Item[]
scheduledItemsInRange(ws, fromISO, toISO): Item[]              // 日期区间有交集，含边界
overdueItems(ws, today): Item[]                                // end < today，且非 done/dropped
dueTodayItems(ws, today): Item[]                               // end === today，且非 done/dropped
edgeTargetsOf(ws, id, type): Item[]                            // from = id
edgeSourcesOf(ws, id, type): Item[]                            // to = id
sopGraph(ws, sopId): { nodes: Item[]; edges: Edge[] }          // 仅 step 节点 + flow 边
countByStatus(ws): Record<ItemStatus, number>                  // 所有 status 都有键
treeDepth(ws, id): number                                      // 根级 0
itemPathTitles(ws, id): string[]                               // 根 → 自身
```

`rollupProgress` 规则（与实现对一致）：

| kind | 进度来源 |
| --- | --- |
| `objective` | 其 `keyresult` 子项进度平均；无 KR 时用子项完成比 |
| `keyresult` | 有 `metric` 且 `target !== start`：`(current-start)/(target-start)`；否则 `done?100:子项完成比` |
| `project` / `sop` | 直接子项 `done / 总数` |
| 其他 | `done ? 100 : 0` |

结果统一 `Math.round` 并夹在 0..100。

参数说明：`scheduledItemsInRange` 接受 ISO 时间或 `YYYY-MM-DD`（内部截取前 10 位），
区间反向会自动交换；`today` 同样接受两种格式。`nextActions` 只返回 `action` / `project`，不含 `step`（SOP 步骤由流程视图负责）以及
`note/reference/objective/keyresult`。

---

## 4. 持久化

### 4.1 前端适配层（`src/core/repo.ts`）

```ts
isTauri(): boolean
emptyWorkspace(): Workspace
migrateWorkspace(input: unknown): Workspace        // 严格归一化；环/未来版本抛错
migrateWorkspaceWithReport(input): { workspace, corrections }
parseWorkspaceText(text: string): Workspace        // 导入时校验，并暂存修正摘要
WorkspaceVersionError                             // version > WORKSPACE_VERSION
saveRepairedWorkspace(workspace): Promise<string>  // 另存 workspace.repaired-*.json

loadWorkspace(): Promise<LoadedWorkspace>          // { workspace, freshInstall, parentCycles, corrections }
saveWorkspace(workspace: Workspace): Promise<SaveInfo>
storageInfo(): Promise<StorageInfo>
listBackups(): Promise<BackupInfo[]>
restoreBackup(name: string): Promise<Workspace>
exportWorkspace(json: string, path: string): Promise<void>
importWorkspace(path: string): Promise<string>

interface SaveInfo { savedAt: string; bytes: number }
interface StorageInfo { dataDir: string; workspacePath: string; backupCount: number; revision: number }
interface BackupInfo { name: string; size: number; createdAt: string }
interface LoadResult { workspace: Workspace; freshInstall: boolean }
interface NormalizationCorrection { itemId: string | null; field: string; from: unknown; to: unknown }
interface CorrectionSummary { total: number; entries: NormalizationCorrection[] } // entries <= 20
interface LoadedWorkspace extends LoadResult { parentCycles: string[][]; corrections: CorrectionSummary }
```

Tauri 环境（`window.__TAURI_INTERNALS__ !== undefined`）走 `invoke`；否则自动降级 localStorage。

### 4.2 Rust 侧（`src-tauri/src/`）

- 文件：`main.rs`、`lib.rs`、`model.rs`、`storage.rs`、`commands.rs`
- 路径：`app_data_dir/workspace.json`
- 写入：`workspace.json.tmp` → `fsync` → `rename` 覆盖；写前把旧文件复制为
  `workspace.json.bak`（单次回滚）。
- 轮换备份：`app_data_dir/backups/textura-YYYYMMDD-HHmmss.json`，保留最新 30 份
  （同一秒多次保存会追加 `-2`、`-3` 后缀）。
- 读取顺序：`workspace.json` → `workspace.json.bak` → 最新轮换备份 → 空 Workspace；
  解析失败自动尝试下一个候选。读取后若 `version < WORKSPACE_VERSION` 执行迁移。
- `freshInstall`：主文件、`.bak`、轮换备份均不存在时为 `true`；任一存在（包括空/损坏文件）为 `false`。
- `load_workspace` / `save_workspace` / `restore_backup` 为 `async` 命令，内部用
  `spawn_blocking` 执行存储工作，避免 10k items 的 fsync/双拷贝阻塞 IPC 线程。
- 所有 Mutex 使用 `unwrap_or_else(|poisoned| poisoned.into_inner())`：锁只保护缓存/串行化，
  中毒不代表数据损坏；继续使用可避免一次 panic 后永久不可用。
- `version > WORKSPACE_VERSION`：**拒绝加载**（不回退、不覆盖主文件），先把原文件复制为
  `workspace.future-v<N>.json`，再返回可读错误；前端进入错误态并禁止自动保存。
- 整个 save 临界区（`.bak`、tmp、fsync、rename、rotation、缓存更新）由 `save_lock` 串行化；
  并发 save 不允许交错写主文件。
- 相同内容（JSON 哈希一致）重复保存直接返回缓存 `SaveInfo`，不重复落盘。

命令（结构体 `serde(rename_all = "camelCase")`）：

```ts
load_workspace(): Promise<LoadResult>               // { workspace, freshInstall }
save_workspace(workspace): Promise<SaveInfo>        // { savedAt, bytes }
storage_info(): Promise<StorageInfo>
list_backups(): Promise<BackupInfo[]>
restore_backup(name): Promise<Workspace>            // 读取备份 -> 原子写回 -> 返回工作区
save_repaired_workspace(workspace): Promise<string> // 另存 workspace.repaired-*.json，不动主文件
export_workspace(json, path): Promise<void>         // 缩进 2 空格
import_workspace(path): Promise<string>             // 返回文件文本，前端校验版本
```

能力文件 `src-tauri/capabilities/default.json` 已包含 `core:default` 与 `dialog:default`。

`cargo test` 覆盖：round-trip + `.bak`、损坏文件回退、空库回退、30 份备份轮换、
版本迁移、路径穿越拒绝、导出/导入、freshInstall 判定、未来版本拒绝与副本、并发 save 串行化、
非法 confidence/metric 的反序列化拒绝。

### 4.3 导入/加载归一化（H1）

导入路径 `migrateWorkspace` 严格归一化并拒绝父子环；加载路径 `normalizeForLoad` 使用同一套
字段规则后切断环。规则：

- `version` 强制整数；`> WORKSPACE_VERSION` → `WorkspaceVersionError`。
- 数值强制 `Number` 且有限：`confidence` 夹紧为 1–10 整数；`gantt.progress` 夹紧 0–100；
  `metric.start/target/current` 非有限值回落 0；`order` 非有限值回落索引。
- 字符串非字符串回落默认；`tags`/`checklist`/`edges`/`areas`/`runs` 保证数组。
- 枚举白名单：`kind` 非法→`note`（保守落入收件箱/笔记，不进入 GTD 下一步）；`status` 非法→`next`；`nodeType` 非法→`action`；
  `energy` 非法→省略；`result` 非法→`skip`；`edge.type` 非法→`related`。
- `notes/tags/areaId/createdAt/updatedAt/completedAt` 缺失补默认（时间戳为当前 ISO）。
- 父子环：导入拒绝并提示「数据中存在父子环：A → B → A，请修复后重试」；
  加载时切断环、记录原 parentId、通知用户，不自动覆盖原文件；同时另存
  `workspace.repaired-<时间戳>.json`（不触碰主文件）。
- 修正摘要：归一化产生差异时收集 `{ itemId, field, from, to }`，最多 20 条；加载/导入后只
  `notify` 一次「已修正 N 处非法数据」，完整摘要（≤20 条）`console.warn` 一次。

### 4.4 生产 CSP（Tauri v2）

`src-tauri/tauri.conf.json` 的 `app.security`：

```text
csp:    default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' asset: http://asset.localhost data:; font-src 'self' data:; connect-src ipc: http://ipc.localhost; frame-ancestors 'none'; base-uri 'self'; form-action 'none'
devCsp: default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' asset: http://asset.localhost data:; font-src 'self' data:; connect-src ipc: http://ipc.localhost http://localhost:1420 ws://localhost:1420; frame-ancestors 'none'; base-uri 'self'; form-action 'none'
```

- 主题预置已外置为 `public/theme-init.js`（构建到 `/theme-init.js`），生产 CSP 不再需要
  `script-src 'unsafe-inline'`；
- `style-src 'unsafe-inline'`：React / @xyflow 的内联 style 属性；
- `connect-src ipc: http://ipc.localhost`：Tauri v2 IPC；
- `devCsp` 额外放行 Vite HMR 与 `'unsafe-eval'`。

端到端冒烟：`bash scripts/tauri-smoke.sh`（Xvfb + 截图 + workspace.json 断言 + stderr 检查）。
deb 的 Maintainer 来自 `Cargo.toml [package].authors` / `bundle.publisher`：
`Textura <dev@textura.app>`。

---

## 5. UI 原语（`src/ui/*`）

所有原语只使用 `src/styles/tokens.css` 中的变量；可点击元素均键盘可达并有可见 focus ring。

```ts
// Button.tsx
<Button variant="primary | secondary | ghost | danger"   // 默认 secondary
        size="sm | md"                                    // 默认 md
        iconLeft? iconRight? block? />                    // 其余同原生 button

// IconButton.tsx —— label 必填（aria-label + title）
<IconButton label="删除" variant="ghost | secondary | danger" size="sm | md">…</IconButton>

// Modal.tsx —— Esc 关闭、基础焦点陷阱、body 滚动锁定、关闭后恢复焦点
<Modal open onClose title? description? footer? width? initialFocusRef?>…</Modal>

// Field.tsx
<Field label? hint? error? required? htmlFor? className?>…</Field>
<Label required? htmlFor?>…</Label>
<TextInput /> <TextArea rows? /> <Select options={[{ value, label }]} />

// Badge.tsx
<Badge tone="neutral | accent | ok | warn | danger | info" dot?>…</Badge>

// Progress.tsx
<Progress value={0..100} tone="accent | ok | warn | danger | info" size="sm | md"
          showLabel? ariaLabel? />

// EmptyState.tsx
<EmptyState icon? title description? action? compact? />

// Segmented.tsx
<Segmented options={[{ value, label, icon?, title? }]} value onChange size="sm | md" ariaLabel? />
```

图标（`src/ui/icons.tsx`）：

```tsx
<Icon name={IconName} size={18} />
```

`IconName`：`folder | target | inbox | timeline | workflow | search | plus | chevron-left |
chevron-right | chevron-down | close | settings | sun | moon | check | x | play | grip |
zoom-in | zoom-out | link | calendar | tag | flag | clock | trash | edit | more`

---

## 6. 设计令牌（`src/styles/tokens.css`）

light 定义在 `:root`，dark 通过 `html[data-theme="dark"]` 覆盖；主题持久化在
`localStorage['textura.theme']`。

| 类别 | 令牌 |
| --- | --- |
| 背景/表面 | `--bg`、`--bg-subtle`、`--surface`、`--surface-2` |
| 边框 | `--border`、`--border-strong` |
| 文字 | `--text`、`--text-muted`、`--text-faint` |
| 强调/语义 | `--accent`、`--accent-soft`、`--ok`、`--warn`、`--danger`、`--info` |
| 实心强调底 | `--accent-strong`、`--accent-strong-hover`、`--accent-strong-active`、`--accent-strong-disabled`、`--danger-strong*`、`--text-on-strong` |
| 语义文字（tint 底） | `--accent-ink`、`--ok-ink`、`--warn-ink`、`--danger-ink`、`--info-ink` |
| 圆角 | `--radius-sm`(4) `--radius-md`(8) `--radius-lg`(14) |
| 阴影 | `--shadow-1`、`--shadow-2` |
| 间距 | `--space-1`(4) `--space-2`(8) `--space-3`(12) `--space-4`(16) `--space-5`(24) `--space-6`(32) |
| 字体 | `--font-ui`（system-ui 栈）、`--font-mono` |
| 布局/焦点 | `--sidebar-width`(240px)、`--topbar-height`(56px)、`--focus-ring` |

全局样式入口只有：`tokens.css`、`base.css`（reset/基础排版）、`shell.css`（外壳布局）、
`ui/ui.css`（原语，由 `main.tsx` 引入）。`src/app/RouteErrorBoundary.css` 是错误边界专属的
组件级样式，仅由该组件 import。**模块不得新增全局 CSS 文件或修改这些文件。**

对比度守护：

- `scripts/contrast-audit.mjs` 解析本文件令牌并输出逐组合 WCAG 对比度表，可单独运行。
- `src/core/tokens.test.ts` 在 `npm test` 中断言关键组合：正文 ≥ 4.5:1、图标/进度/焦点 ≥ 3:1。
- `--accent`（品牌色）继续用于描边、图标、焦点环与链接；实心强调底一律使用
  `--accent-strong*` + `--text-on-strong`，tint 底上的语义文字使用 `--*-ink`。

---

## 7. 路由与布局

- 路由是 `ui.route` 字符串，不使用 react-router。
- 侧栏 240px：品牌（Textura / 织理）、视图导航（今日 / OKR / GTD / 甘特 / SOP / 设置）、
  Area 列表、底部存储状态。
- 顶栏 56px：视图标题与副标题、搜索输入（`ui.search`）、快速收集（打开 `ui.quickCaptureOpen`）、
  主题切换。
- 内容区自适应；窗口 1440×900，最小 1024×720。
- `AppShell` 全局挂载 `CommandPalette`、`QuickCapture`、`ShortcutsDialog`，受对应 `ui.*Open` 控制；
  `route === 'settings'` 渲染 `SettingsPage`。
- `RouteView` 由 `RouteErrorBoundary`（类组件，`getDerivedStateFromError`）包裹。任一模块渲染崩溃时
  侧栏/顶栏保留，fallback 提供「返回今日」「重新加载工作区」「查看数据目录」三个动作。
  「重新加载工作区」先 `await save()` 落盘，再 `reload()`；期间按钮显示「正在保存并重新加载…」。

路由元数据（`src/app/routes.ts`）：

| route | label | icon |
| --- | --- | --- |
| `dashboard` | 今日 | `calendar` |
| `okr` | OKR | `target` |
| `gtd` | GTD | `inbox` |
| `gantt` | 甘特 | `timeline` |
| `sop` | SOP | `workflow` |
| `settings` | 设置 | `settings` |

### 深链与视图记忆

`src/core/routeState.ts` 是唯一实现（纯函数 + 浏览器同步）：

```ts
ROUTE_STORAGE_KEY = 'textura.route'
ROUTE_IDS: Route[]
isRoute(value): boolean
routeFromSearch(search): Route | null
itemIdFromSearch(search): string | null
routeFromStored(value): Route | null
resolveInitialRoute(search, stored): Route
routeWithSearch(search, route): string
readRouteMemory(): string | null
syncBrowserRoute(route): void
```

行为：

- 启动时 `load()` 在任何 `await` 之前读取 `window.location.search`：
  - `?route=okr|gtd|gantt|sop|dashboard|settings` 合法时作为初始视图，**优先级高于**记忆；
  - 否则恢复 `localStorage['textura.route']`；再否则 `dashboard`；
  - `?item=<id>` 且该条目存在时写入 `selectedId`（`select(id)` 的等价效果），无效 id 忽略。
- 视图切换（`setUi({ route })`）与初始化成功后调用 `syncBrowserRoute(route)`：
  - `window.history.replaceState(...)` 同步 `?route=`，**不新增历史记录**；`item` 等其它查询参数保留；
  - 写入 `localStorage['textura.route']`；
  - 同步 `document.documentElement.dataset.route = route`，便于无头截图与自动化断言。
- 无效的 `?route=` 会被忽略并回退到记忆值；初始化后 URL 会被规范化为合法的 `?route=`。
- 不使用路由库；`AppShell` 的导出与模块挂载方式不变，视图仍由 `ui.route` 驱动。

---

## 8. 文件所有权

| 路径 | 所有者 | 说明 |
| --- | --- | --- |
| `src/core/*`、`src/app/*`、`src/styles/*`、`src/ui/*` | Phase A（冻结） | 模块 Worker 只读 |
| `src/main.tsx`、根配置、`public/theme-init.js`、`docs/contract.md` | Phase A（冻结） | 只读 |
| `src/modules/sop/**` | sop Worker | 当前占位 `SopPage.tsx` |
| `src/modules/okr/**` | okr Worker | 当前占位 `OkrPage.tsx` |
| `src/modules/gtd/**` | gtd Worker | 当前占位 `GtdPage.tsx` |
| `src/modules/gantt/**` | gantt Worker | 当前占位 `GanttPage.tsx` |
| `src/modules/dashboard/**` | appshell Worker | 当前占位 `DashboardPage.tsx` |
| `src/modules/appshell/**` | appshell Worker | 占位 `CommandPalette.tsx`、`QuickCapture.tsx`、`SettingsPage.tsx`、`ShortcutsDialog.tsx` |
| `src-tauri/**` | Phase A（冻结） | 模块不得修改 Rust 持久化 |

占位文件均包含 `// TODO(module)` 标记；每个页面导出与文件名同名的组件，且**不得改动导出名**，
否则 `AppShell` 会编译失败。模块内部可以自由拆分子组件/子目录，但只放在自己的目录下。

---

## 9. 演示数据（`src/core/fixtures.ts`）

```ts
createSeedWorkspace(): Workspace      // 当前等同于 buildDemoWorkspace()
buildDemoWorkspace(): Workspace
```

内容：

- 3 个 Area：产品 / 运营 / 个人
- 1 个 Objective（周期 = **当前季度**，动态）+ 3 个 KR：
  - NPS 42 → 60（confidence 4，current 47）
  - 周活跃 1200 → 2000（confidence 6，current 1450）
  - 付费转化 2.1% → 3.0%（confidence 7，current 2.35）
- 1 个「新用户 onboarding」SOP：7 个 step（start / action×4 / decision / check / end），
  7 条 flow 边（含「是 / 否 / 补充 / 通过」标签），canvas 坐标手工布好（240×160 网格）
- 1 个「官网改版」project + 6 个 action（均带起止日期），2 条 `depends` 边
- 6 条 inbox（`clarified: false`，部分带 `context`、`twoMinuteCandidate`）、3 条 next、
  1 条 waiting、1 条 someday
- 3 条 SOP run 记录（pass / pass / fail）
- 所有日期用 date-fns 相对「今天」生成

> **实现说明（与初始需求的偏差）**：Objective 的 period 使用「当前季度」而非硬编码
> `2026-Q1`，以保证任意时间打开 OKR 视图都有内容；当系统时间处于 2026-Q1 时两者等价。
> 该选择已冻结，`ui.okrPeriod` 初始值同样取当前季度（若工作区无该季度则取最新季度）。

播种规则：只有 `freshInstall === true`（主文件、`.bak`、轮换备份均不存在）且 `items/areas/runs`
全为空时，才写入种子数据并立即保存一次。文件存在但内容为空的工作区不会自动播种。
若想重新播种，删除整个工作区文件/备份（见下一节）。

---

## 10. 无 Tauri 环境下调试

```bash
npm install          # 已由 Phase A 完成，后续 Worker 禁止再装依赖
npm run dev          # http://localhost:1420
npm run preview      # 预览 dist（先 npm run build）
npm test             # vitest
```

浏览器模式下 `window.__TAURI_INTERNALS__` 不存在，`repo` 自动使用：

- 工作区：`localStorage['textura.workspace.v1']`
- 主题：`localStorage['textura.theme']`
- 备份/按路径导入导出不可用（设置页显示「浏览器调试模式」；导出会走浏览器下载，导入抛错）

重新播种：DevTools 执行
`localStorage.removeItem('textura.workspace.v1')` 后刷新页面。

桌面模式验证：

```bash
cargo test --manifest-path src-tauri/Cargo.toml
npm run tauri:build          # 产出 deb
```

> 当前环境无显示器，不启动 GUI；通过 `cargo test`、`tsc`、`vitest`、`vite build`、
> `tauri build` 验证。

在 mock 数据上验证模块：

1. 浏览器打开应用，确认侧栏显示 3 个 Area、GTD 收件箱计数为 6。
2. OKR 页应能取到 `objectivesOfPeriod(ws, ui.okrPeriod)` 非空。
3. GTD 页三列分别 6 / 3 / 1。
4. 甘特页应有 6 条带日期的 action + 1 个 project，`edgeSourcesOf(ws, 'act_build', 'depends')`
   返回「视觉稿评审」。
5. SOP 页 `sopGraph(ws, 'sop_onboarding')` 返回 7 个节点、7 条 flow 边。
6. 修改任意条目后 400ms 看底部存储状态变为「已保存」，刷新后数据仍在。

---

## 11. 给模块开发者的 6 条硬性规则

1. **只改自己的目录**：`src/modules/<你的模块>/**`。不要修改 `src/core/*`、`src/app/*`、
   `src/ui/*`、`src/styles/*`、`src/main.tsx`、根配置或 `src-tauri/*`；需要新能力先在
   交付说明里提出，不得私自扩展契约。
2. **不安装任何依赖**：全部依赖已在 Phase A 一次性安装（`@xyflow/react`、`@dagrejs/dagre`、
   `date-fns`、`clsx` 等均已就绪）。不得执行 `npm install` 或引入新的第三方包/字体。
3. **只用令牌色**：颜色、圆角、阴影、间距一律使用 `var(--…)`。禁止硬编码 hex/rgb、
   禁止渐变滥用、禁止内联色值（必要的动态颜色只能来自 `Area.color` 或语义令牌）。
4. **不新增全局 CSS**：样式写在模块目录内的 CSS Module 或局部 class，并在模块内 import；
   不得新建/修改 `src/styles/*` 或 `src/ui/ui.css`，不得覆盖全局元素选择器。
5. **复用 selectors 与 store**：所有领域计算调用 `src/core/selectors.ts`，所有读写走
   `useWorkspace` / `getWorkspace()`；不得在模块里复制 rollup / 排期 / 树遍历逻辑，
   不得直接改 `workspace` 对象（必须通过 store 动作）。一次手势更新多条 item 时必须使用
   `updateItems([...])`，不要循环调用 `updateItem` 制造 N 条历史。
6. **整份导入 / 重置只走 `replaceWorkspace`**：必须调用
   `await replaceWorkspace(next, { recordHistory: true })`（默认即 true），不得直接写
   `storageInfo().workspacePath`、localStorage 或自行调用底层文件写入；只有走该动作才能保证
   原子写、轮换备份、历史回退与 `saveState` 语义一致。

附加约定（软性但强烈建议）：

- 图标统一用 `<Icon name="…" />`；纯图标按钮使用 `IconButton` 强制提供 `label`。
- 页面根节点使用 `.page`、`.page-header`、`.page-actions`，保持与外壳一致的留白。
- 跨模块跳转用 `setUi({ route: 'okr', okrPeriod })`，不要引入路由库。
- 需要「撤销/重做」的交互直接调用 `undo/redo`，不要自己维护第二套历史。

---

## 12. 冻结的实现细节（避免误解）

- `ancestorsOf` 顺序：**最近父级 → 根**；`itemPathTitles` 返回 **根 → 自身**。
- `descendantsOf` 带 visited 集合，自环/互环/环+子树都不会无限递归；`findParentCycles` 返回
  形如 `['a','b','a']` 的环路径。
- `RouteView` 外包 `RouteErrorBoundary`，模块渲染错误不会导致整窗白屏。
- `sopGraph` 只返回 `kind === 'step'` 的节点，不包含 SOP 容器本身；边只取 `flow` 且两端在
  节点集中。
- `scheduledItemsInRange` 返回所有与区间有交集的条目（**包含已完成**），按开始日期升序。
- `overdueItems` / `dueTodayItems` 只按 `gantt.end` 判断，并排除 `done/dropped`。
- `nextActions` 只含 `action/project`（SOP `step` 不进入 GTD 下一步）。
- `createItem` 对 `action` 额外补 `gtd` 默认值（`capturedAt=now`，`clarified = status !== 'inbox'`）。
- `updateItem` 在 status 离开 `done` 时清空 `completedAt`。
- `moveItem` 的 `order` 是目标父级下的目标下标（从 0 开始）；父级不变时也可以用它排序。
- `getWorkspace()` 返回完整 store state（`getWorkspace().workspace` 才是数据）。
- `replaceWorkspace` 默认记录一次整份快照；`recordHistory: false` 只清空 redo 栈、不新增快照。
- `updateItems` 一次手势只产生一条历史、一个 `updatedAt`、一次防抖保存；模块批量更新必须使用它。
- `load` 只在 `freshInstall === true` 且空库时播种；未来版本进入错误态且不自动保存；
  父子环在加载时切断并 warn，导入时拒绝。
- 视图深链与记忆：URL `?route=` > `localStorage['textura.route']` > `dashboard`；
  `?item=` 只设置选中项；`document.documentElement.dataset.route` 始终与 `ui.route` 同步。
- 演示数据的 OKR 周期取当前季度（见第 9 节说明）。

任何与本文档不一致的代码都视为 bug，应先对齐文档再改代码。
