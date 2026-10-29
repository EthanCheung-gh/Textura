# OKR 独立编辑页 · 方案与分阶段计划

> 目标读者：接手 P1–P4 的人。本文件是**已批准方案**的落地文本 + P0 的实测基线。
> 相关：`docs/HANDOFF.md` §6（崩溃事实）、`docs/STABILITY.md` §8（三条缓解已证伪）、
> `docs/OKR-VIEW.md`（列表页与 Web 的数值对照）、`docs/CUI-PRIMER.md`（CUI 心智模型）、
> `docs/OKR-P0-BASELINE.md`（P0 计数器与实测数字）。
>
> 范围声明：**本方案不改渲染行为、不改像素、不改列表页交互**（P1 之前）。P0 只加观测。

---

## 1. 结论

**独立编辑页是「降低每帧分配 + 换掉崩溃触发组合」的可用性方案，不是运行时 GC 缺陷的修复。**

- 崩溃根因在 `libcangjie-runtime` 的 CopyCollector forward 阶段（`docs/HANDOFF.md` §6.1），
  应用侧没有栈帧、没有可改的开关；本方案不声称能让缺陷消失。
- 本方案做两件**能做到**的事：
  1. **换掉触发组合**：把 OKR 的文本编辑从「自绘页 + `Ui.inlineEditor` + `Portal` + IME 锚点」
     改成「真控件页（`TextField`/`TextArea`/`Button`）」，编辑期间不再让画布每帧重建上千条
     指令对象（`docs/HANDOFF.md` §6.2 第 3 条、`docs/STABILITY.md` §8.3 的结论：
     「打开 prompt 这个动作本身」就足以把 GC 推到坏落点）。
  2. **降低每帧分配**：编辑页是普通控件树（CUI 自己的 `Label`/`TextField` 只在 dirty 时重排），
     发布态列表页则按 §3 的表逐项削掉每帧分配。目标是分配速率 −50%（§5.4）。
- **不要再试的三条**（都已实现并上真机，全部失败，重做只会浪费时间）：
  | 已证伪的缓解 | 结论 | 证据 |
  |---|---|---|
  | 运行时 GC 参数（`cjRegionSize` / `cjHeapSize` / `cjGCThreshold`，含 NAPI `setenv`、`appEnvironments`） | 真机 HAP 进程里运行时 `getenv` 看不到 ArkTS 侧的环境变量，`Region size` 恒 64KB | `docs/STABILITY.md` §8.1 |
  | 页面级 `RetainedSubtree` 缓存 | prompt 第 1 轮就崩（`toRegion2Idx != INVALID_VALUE` ×2） | `docs/STABILITY.md` §8.2 |
  | 关闭光标闪烁（CUI-P13 `caretBlink: false`） | 10s 内崩；「空闲出帧」不是充分触发条件 | `docs/STABILITY.md` §8.3 |

---

## 2. 现状与证据

### 2.1 CUI 每帧重建整棵树（方案的前提）

`app.run { ... }` 的闭包不是初始化，而是**每帧重新描述界面**（`docs/CUI-PRIMER.md` §0）。
OKR 页因此每帧：新建 `OkrUiState`（`src/views/okr/okr_page.cj:186` `okrUiState()`）→ 新建
`OkrPage`（`okr_page.cj:213` 起）→ 跑 3 次布局（CUI 的「测—布—再布」，P0 实测 1 个窗口帧 =
3 次 `OkrPage.layout`，见 `docs/OKR-P0-BASELINE.md` §2）→ 重填整套绘制指令。

### 2.2 已经做过的三件事（都是「减少重复工作」，不改像素）

| 提交 | 内容 | 实测 | 代码 |
|---|---|---|---|
| `030dff0` | 绘制批跨帧复用（`OkrPaint.clear()`，容器不再每帧 new） | — | `okr_ops.cj:260` `OkrPaint`、`okr_canvas.cj:56` `PageCanvas` |
| `c0bbeeb` | 文字宽度记忆化（`okrTextW` 缓存 `(文字, 字号, 字重, mono)`） | 每帧文字测量 **821 → 149** | `okr_ops.cj:505`、`okr_ops.cj:582` |
| `5107ce2` | 视口裁剪（`clipPaintBounds` + 32px 余量） | 文字绘制 **606 → 169/帧**，绘制 **23.3 → 7.7ms/帧** | `okr_ops.cj:96` `okrPaintBounds`、`okr_ops.cj:110` `okrClipped` |

三项合计把 GC 时间压掉约 28%，但**崩溃仍 3/3**（`docs/HANDOFF.md` §6.1）——这是本方案要换
组合的直接原因：继续在「画布 + 每次点击开一个 IME 会话」这条路上做微调，收益已经用尽。

### 2.3 崩溃事实（`docs/HANDOFF.md` §6.1，未在 P0 重测）

- 主线程：`F CANGJIE-RUNTIME: Check failed: toRegion2Idx != INVALID_VALUE`（总在
  `Preforward light sync` 之后）→ SIGABRT；GC 线程 `SIGSEGV@0x8`：
  `RegionInfo::VisitLiveObjectsUntilFalse → RegionManager::ForwardRegion → CopyCollector::ForwardFromSpace`。
- 复现：最大化窗口 + 「紧凑」密度 → 点页底 `＋ 新增关键结果…`（`okr_cards.cj:540`
  热区 `okr-add-<objId>`）打开 prompt → 不动任何东西等：**88s / 2s / 17.7s 三次都崩**。
- 环境量：**GC 间隔中位 160ms、峰值 allocated 25.5MB**。
- 触发面比「双击」宽：单击、点 KR 上/下移图标、Esc 关 prompt 都会崩；什么都不点则 2 分钟+ 稳定。

### 2.4 测试里已经把这件事写成前提

`src/views/okr/okr_paint_reuse_test.cj:11-17` 的注释原文就是判据：

> 真机上的后果不是慢，而是**分配速率触发运行时 GC 缺陷**（`libcangjie-runtime` CopyCollector
> forward 阶段断言失败，见 docs/STABILITY.md）。所以这里钉的不是观感，而是分配行为。

同一文件第 3、4 条测试还钉住了「绘制阶段只读」与「缓存的返回值与直接测量逐位相同」——
P0 的计数器（§5.1）沿同一条思路：**把分配变成可断言的数字**。

---

## 3. 每帧分配热点与对策

数字来源：`docs/OKR-P0-BASELINE.md`（演示 workspace：1 个目标 / 3 个 KR，1152 宽，详细密度，
**每次 `layout`** 的口径）。一行 = 一个热点；「预期」是 P3 的目标，不是已实现值。

| # | 热点 | 现状（实测/代码） | 对策（P3） | 预期 | 风险 |
|---|---|---|---|---|---|
| 1 | `OkrUiState()` 每帧新建 | `okr_page.cj:27` 的类持有 30+ `State`，`okr_page.cj:186` 每帧 `OkrUiState()`；只有 `State` 本身被 `rememberState` 复用，**壳对象与 `fields: HashMap` 每帧新建** | 用一个 `remember<OkrUiState>` 的单例壳（把 `fields`/`registeredIds` 挂进去），`rememberState` 只在首次建壳时调用 | −1 类 + −1 `HashMap`/帧 | 中：`rememberState` 只能在 build 阶段调用，跨路由复用需清理 key；`fields` 缓存按目标 id 增长需上限 |
| 2 | `OkrHotspot` + 闭包 | `okr_canvas.cj:44` 每帧 86 个对象 + 86 个**新闭包**（`addHotspot`，`okr_canvas.cj:271`；捕获 store/rect/entry） | hotspots 也挂到跨帧批上（`clear()` + 重填）；把 `action` 换成「opcode + 目标 id」而不是闭包，点击时再分派 | −86 对象 −86 闭包/布局 | 中：`OkrPage.handle` 走 `spot.action()`，改分派要保证 Esc/焦点/子控件顺序不变 |
| 3 | 绘制指令对象 | 302 条/布局：`texts=129 fills=55 strokes=37 rings=47 icons=13 lines=7 chevrons=6 shadows=6 dashes=1 dots=1`（`okr_ops.cj:29-250` 十个 Op 类，每帧 new） | 指令池（Op 字段改 `var` 复用）或用「并列数组」（SoA）代替对象数组；文本 op 在内容不变时只改几何 | −302 对象/布局 | 中高：`OkrPaint.draw` 必须保持只读（`okr_paint_reuse_test.cj:168` 已钉），op 复用后一处漏写就是串帧 |
| 4 | `ellipsize` 切串 | `okr_ops.cj:592`；25 次/布局，1152 宽下 `candidates=0`（不截断）；窄页（≤520）每字一个候选串 | 结果按 `(text, size, weight, mono, maxWidth)` 记忆化，只在文本/宽度变化时重算 | 稳态 0 分配 | 低：缓存键必须含 `maxWidth`（否则窄窗口复用宽结果） |
| 5 | 每帧拼 id | `"okr-title-${id}"` / `"okr-field-${kr}-${field}"` 等 40+ 处；focusable 46 个 id/帧（`okr_page.cj:299-369`） | 把 id 预先算进 `OkrObjEntry` / `OkrKrEntry`（`okr_model.cj`），或在 `OkrMetricIdCache` 里按前缀+id 记忆 | −90 串/布局 | 低：id 是焦点与热区的唯一契约，改名会破 `okr_inline_editor_test.cj`，所以只缓存不换名 |
| 6 | `PageCanvas` + 3 个 `ArrayList` | `okr_canvas.cj:56`：`children` / `childRects` / `hotspots` 每次 `layout` 新建（附带扩容数组） | 与 `OkrPaint` 同款：把三个容器也放进 `remember`，构造时 `clear()` | −4 容器/布局 | 低：`measureOnly` 预演必须不写这些容器（现状已是） |
| 7 | `BadgeView` / `ProgressView` 子控件 | `widgets=9`/布局（`okr_canvas.cj:250` `badge`、`okr_canvas.cj:262` `progress`）；每帧 new + `measure`（`BadgeView.measure` 里还要量一次文字） | 徽章改自绘 op（几何已在 `badgeWidth`/`OKR_BADGE_H` 里算好），或用「徽章宽度记忆」只在字串变化时 `measure` | −9 控件 −9 次测量/布局 | 中：徽章像素必须逐字节不变，改动后必须过 `scripts/diff.sh --theme both` |
| 8 | `focusableIds()` 数组 | `okr_page.cj:371` 每次调用 `registeredIds.toArray()`（46 项，一次数组分配）；P0 基线里 **0 次/帧**（只有焦点遍历才调） | 缓存数组，`registeredIds` 变化时置脏重算 | 每次遍历省 1 数组 | 低：CUI 只读这个数组，但要确认没有调用方会写它 |
| 9 | 关闭态弹窗 | `okr_dialogs.cj:19` 每帧调 7 个 dialog，**每个都在首行早退**（`if (!ui.xOpen.value) { return }`）；成本≈7 次函数调用 + `okrDialogs` 每帧读一次 `store.state.value()` | 保持早退；把 `okrDialogs` 的 `workspace` 读取挪进打开的分支 | 接近 0（已很小） | 低：不要为了「优化」把早退挪走，`Ui.modal` 里有 `Portal` 注册 |
| 10 | `format*` 字符串 | `stringBuilds=13`/布局：`formatMetric` / `formatNumber` / `formatSchedule` / `quarterLabel` / `jsNumberToString` / `pad2`（调用点见 `docs/OKR-P0-BASELINE.md` §2）；每个都是 `ArrayList`/`String` 拼接 | 按 `(函数, 入参)` 记忆化，或把显示串跟着 `OkrObjEntry`/`OkrKrEntry` 一起在 `okr_model.cj` 里算一次 | 稳态 0/布局 | 低：`formatNumber` 是 JS 语义（`logic/numbers.cj:261`），记忆化键必须用原始 `Float64` |

> 顺序建议：**6 → 2 → 3 → 4 → 5 → 10 → 7 → 1**。理由：6/2 是纯容器复用（风险最低、收益立刻可测），
> 3 是最大头但要动 `draw` 的只读契约，1 动状态壳最伤（`rememberState` 的时机约束），放最后。

---

## 4. 独立编辑页设计

### 4.1 入口与状态：`OkrUiState.editId`

| 项 | 设计 | 参照 |
|---|---|---|
| 状态 | `OkrUiState.editId: State<String>`，`rememberState<String>("okr-edit-id") {""}`；`""` = 列表态 | Web：`OkrPage.tsx:52` `const [editingId, setEditingId] = useState<string null>(null)` |
| 入口 | 每张目标卡右上角的**铅笔**：`okr-edit-<objId>`，`IconGlyph.Edit`（`src/ui/icons.cj:50` 已有），26×26，排在现有 `okr-more-<objId>` 左边 | Web：`ObjectiveCard.tsx:196-203` `data-edit-objective` + `onEdit(id)` |
| 点铅笔 | `ui.editId.value = entry.item.id`；`store.select(id)`（侧栏/检查器同步） | Web：`OkrPage.tsx:58-64` `openEditor` |
| 渲染 | `render()`（`src/views/okr/okr.cj:16`）里二选一：`editId` 非空 → `okrEditorPage(ctx, ui)`；否则 → `OkrPage` + `okrDialogs` | Web：`OkrPage.tsx:166-171` |
| 目录 | 新文件 `src/views/okr/okr_editor.cj`（+ `okr_editor_test.cj`），仍属 `textura.views.okr` 包，不新增公共 API | `docs/STRUCTURE.md` 的所有权约定 |

### 4.2 控件页（widget 页）而不是自绘画布

编辑页**故意不共用** `PageCanvas`：

- 用 CUI 原生控件：`VStack` / `HStack` / `Label` / `Ui.field` / `Ui.textInput` /
  `Ui.textArea` / `Ui.button` / `Ui.iconButton` / `Ui.progress` / `SegmentedControl`。
- **不用** `Ui.inlineEditor`（`src/ui/inline_editor.cj`）、**不用** `Portal`、**不用** IME 锚点
  （`src/ui/inline_anchor.cj`）——这三件正是 `docs/HANDOFF.md` §6.2 第 3 条要求拆掉的组合。
  IME 由 `TextField`/`TextArea` 自己在 build 阶段注册，焦点与光标天然可用
  （`docs/DEVICE-NOTES.md` §16 的反面：**只有 build 阶段声明的控件才进焦点图**）。
- 滚动：外层已经有 `shell-content` 的 `ScrollView`（`src/shell/appshell.cj:700`），
  编辑页只声明 `VStack`，**不嵌套第二个滚动容器**（两个滚动容器抢滚轮，
  `docs/DEVICE-NOTES.md` 的滚轮修复就是被这类结构坑过）。若将来要页内独立滚动，
  用 `ScrollView(key: Some("okr-editor-scroll"))` 并同时给外层 `.hug()`。
- 布局栈默认 `flexible = true`，放进 `Panel`/`ScrollView` 的栈记得 `.hug()`
  （`docs/CUI-PRIMER.md` §3）。

### 4.3 页面分区

对齐 Web 的 `src/modules/okr/ObjectiveEditor.tsx`（布局与像素**不**对齐，见 §7）。

| 区域 | 内容 | CUI 组件 | Web 参照 |
|---|---|---|---|
| 顶栏 | 「← 返回目标列表」/ 面包屑 `2026-Q1 · 目标编辑` / 保存状态（`已保存`/`保存中…`/`保存失败`） | `Ui.button(Ghost, IconGlyph.ChevronLeft)` + `Label` + `Label(mono)` | `ObjectiveEditor.tsx:90-113` |
| 目标 | 标题（可编辑）、领域（select）、状态（select）、信心（10 格刻度）、整体进度（progress + `%`）、创建/更新时间 | `Ui.textInput` + 两个自绘 select（复用 `okr_cards.cj:506` `paintSelect` 的样式思路）或 `ComboBox` + `paintConfidenceScale` 的控件版 + `Ui.progress` | `ObjectiveEditor.tsx:302-380` |
| notes | 3 行 `TextArea`，提示「停止输入 600ms 后保存；失焦立即提交」 | `Ui.textArea(theme, draft, height: 92)` | `ObjectiveEditor.tsx:383-392` |
| KR 区 | 标题「关键结果 · N」；每条：序号、标题、指标四格（起点/当前/目标/单位）、负责人、状态、进度、信心、上下移、删除 | `HStack`/`VStack` + `Ui.textInput`（数值）+ `Ui.segmented`（信心）+ `Ui.iconButton`（上/下/删除） | `KrRow.tsx` / `MetricEditor.tsx`（经 `ObjectiveEditor.tsx:400-410`） |
| 新增 KR | 输入框 + 「添加」按钮；Enter 创建（默认信心 5），创建后焦点回到输入框 | `Ui.textInput` + `Ui.button` | `ObjectiveEditor.tsx:412-437` |
| 执行项 | 「关联执行项 N · 已完成 M」+ 明细列表（勾选即完成）+ 「关联执行项」对话框入口 | `Label` + 行内 `VStack` + 复用 `openLinkDialog`（`okr_cards.cj:613`） | `ObjectiveEditor.tsx:403-417` |
| 操作 | 移动到其他季度 / 复制为新季度目标 / 删除目标（危险色） | `Ui.button(Secondary/Danger)` + 复用 `okr_dialogs.cj` 的季度与删除确认对话框 | `ObjectiveEditor.tsx:419-441` |

宿主测试断言（P1 验收用）：`okr_editor_test.cj` 走 `WidgetTestHost`，断言
「标题/notes/四个指标格/负责人/新增 KR 输入框都在语义树里且有正宽高」「Enter 提交后 store 变化」
「返回列表后 `editId` 为空且焦点请求指向 `okr-edit-<id>`」。

### 4.4 保存模型

| 字段 | 何时写 store | 依据 |
|---|---|---|
| 标题 / 领域 / 状态 / 信心 / 指标四格 / 负责人 | **失焦或 Enter 立即写**（`commitOnFocusLoss`），不做防抖 | Web：`EditableTitle` / `MetricEditor` 的 `onCommit` 都是即时写 |
| notes | **停止输入 600ms 后写**；失焦、返回列表、切换到别页时 **flush** | Web：`ObjectiveEditor.tsx:21-24` `NOTES_COMMIT_DELAY_MS = 600`，`flushNotes` |
| 新增 KR | 提交即 `createItem`，然后清空输入框、焦点留在输入框 | Web：`ObjectiveEditor.tsx:290-303` |

两个实现约束（**不要用视图里读时钟的办法**，`AGENTS.md` §6 禁止视图读系统时钟）：

1. 防抖的计时来自帧回调：`FrameHandler(onFrame: {info => ...})` 的 `info.elapsedMs`
   （`third_party/cangjie-sdl/src/events.cj:61` `FrameInfo`；shell 已有同款用法
   `src/shell/appshell.cj:730`）。编辑页记住「最后输入时刻 + pending 文本」，在 tick 里比较
   `elapsedMs - lastInput >= 600` 就 flush。
2. 外部改动（撤销 / 导入 / 其它视图）不得打断输入：只有 **store 的值 ≠ 自己最后提交的值** 时
   才覆盖草稿（Web 的 `notesCommittedRef` 做法）。OKR 侧 store 写入会经
   `OkrStoreBridge`（`okr_page.cj:202`）触发下一帧重建，所以「草稿 vs 已提交值」的对账每帧都要做。

### 4.5 列表页只读化范围

P2 之后，**列表页不再承载文本编辑**。改动范围（一行 = 一个热区）：

| 热区 | 现在 | P2 之后 |
|---|---|---|
| `okr-title-<id>`（目标/KR 标题） | 打开 `Ui.inlineEditor` prompt（`okr_cards.cj:124`、`okr_cards.cj:208`） | 改为**打开编辑页**（目标）／聚焦到编辑页对应 KR（KR 需要 `editId` + `focusKr`） |
| `okr-field-<kr>-<field>`（指标四格） | 打开 prompt（`okr_cards.cj:339`） | 删除热区，只显示数值（只读文本），编辑去编辑页 |
| `okr-owner-<kr>`（负责人） | 打开 prompt（`okr_cards.cj:391`） | 同上 |
| `okr-addkr-<id>` + `okr-add-<id>`（新增 KR） | 打开 prompt（`okr_cards.cj:550`、`okr_cards.cj:552`） | 「新增 KR」改为打开编辑页并聚焦新增输入框 |
| `okr-conf-<id>`（信心刻度）、`okr-up/-down`、`okr-del`、`okr-link`、`okr-exec-` | 直接改 store / 开对话框 | **保留**（这些都是即时动作，不进 IME，也不是崩溃的组合） |
| `okr_prompt.cj` 整套（`OKR_PROMPT_INPUT`、`promptAnchor`、`armPrompt`） | `Ui.inlineEditor` + Portal | 停用：`okr.cj:25` 的 `FocusOnceView(promptFocus)` 与 `okr_dialogs.cj:31` 的 `okrPromptDialog` 一起删；`OkrUiState` 的 `prompt*` 字段随之删除（**一次性提交，避免两套编辑入口并存**） |

`docs/OKR-VIEW.md` 记录的弹窗数值对照与本节不冲突：那些弹窗（新建目标/季度/关联执行项/状态/删除确认）
**保留**，它们不是文本编辑，也不需要画布矩形。

### 4.6 Esc 与焦点归还

- 编辑页里 Esc = **返回列表**，但输入控件内的 Esc 先归控件（CUI 的 `TextField` 会消费），
  与 Web 的实现一致（`ObjectiveEditor.tsx:76-88` 显式跳过 `INPUT`/`TEXTAREA`/`dialog`）。
- 返回后把焦点还给**进入时的铅笔**：`ui.editId.value = ""` + 一个一次性的
  `FocusRequest.request("okr-edit-<id>")`，由 `FocusOnceView`
  （`src/views/okr/okr.cj:25`；实现见 `src/ui/focus.cj`）在下一帧落地——
  与现在 `closeOkrPrompt` 的还原方式相同（`okr_prompt.cj:82`），这条路已验证可用。
- 目标在编辑期间被删除（撤销/别处删除）时：编辑页显示空态「目标不存在或已被删除」+ 返回按钮，
  不白屏（Web：`ObjectiveEditor.tsx:115-127`）。

---

## 5. 度量与门禁

### 5.1 计数器清单（P0 已实现，`src/views/okr/okr_metrics.cj`）

| 计数器 | 语义 | 埋点 |
|---|---|---|
| `frames` | 累计 `OkrPage.layout` 调用次数（高度预演不计） | `okr_page.cj:433` |
| `ops` | 最近一帧绘制指令条数 | 同上（`cv.paint.opCount()`） |
| `hotspots` | 最近一帧命中区个数 | 同上（`cv.hotspots.size`） |
| `widgets` | 最近一帧子控件个数 | 同上（`cv.children.size`） |
| `textMeasureCalls` | 累计 `okrTextW` 调用次数 | `okr_ops.cj:584` |
| `textMeasureMisses` | 累计缓存未命中（真正测量）次数 | `okr_ops.cj:545` |
| `ellipsizeCalls` | 累计 `ellipsize` 调用次数 | `okr_ops.cj:594` |
| `ellipsizeCandidates` | 累计构造的候选串个数 | `okr_ops.cj:601` |
| `stringBuilds` | 累计 `format*` 类格式化调用次数 | `okr_ops.cj:685`（`pad2`）与 §5.2 的调用点 |
| `focusableIdCalls` | 累计 `focusableIds()` 调用次数 | `okr_page.cj:373` |
| `frameMs` | **不在视图里**（视图不读时钟）：由测试侧 `MonoTime` 计时 | `okr_metrics_test.cj`（`frameUs`） |

环境变量 `TEXTURA_OKR_METRICS=1` 时每 60 帧打印一行 `[okr-metrics] ...`（默认关闭；
环境变量只读一次，避免把 `getenv` 的分配算进「被观测量」）。

### 5.2 `stringBuilds` 的调用点（P0 覆盖范围）

| 格式化函数 | 调用点 |
|---|---|
| `pad2` | `okr_ops.cj:683`（KR 序号，实现内计数） |
| `formatMetric` | `okr_cards.cj:346`、`okr_cards.cj:421`、`okr_views.cj:122`、`okr_views.cj:289` |
| `formatNumber` | `okr_cards.cj:223`（紧凑密度的「当前/目标」） |
| `formatSchedule` | `okr_cards.cj:476`、`okr_views.cj:326` |
| `quarterLabel` | `okr_page.cj:559`（页头副标题）、`okr_page.cj:593`（季度 chip）、`okr_views.cj:461` |
| `jsNumberToString` | `okr_page.cj:557`、`okr_page.cj:743` |

**不统计**裸 `${}` 插值（`"${kr.progress}%"` 之类）——那会把埋点埋进每一处模板串，收益却是零。
`logic` 包（`formatMetric`/`formatNumber`/… 的实现，`src/views/okr/logic/display.cj`）**没有**加计数器：
`textura.views.okr.logic` 是独立包，计数器放进去会造成「logic → views」的反向依赖。

### 5.3 门禁

| 层 | 命令 | 现状 |
|---|---|---|
| 主机单测 | `cd cangjie && source scripts/env.sh && cjpm test` | **713/713**（P0 前 710，新增 3 个计数器用例），`docs/OKR-P0-BASELINE.md` §4 |
| CUI 包 | `cd third_party/CUI && cjpm test` | 967 通过 + 1 个既有夹具 ERROR（`docs/HANDOFF.md` §2） |
| 像素 | `scripts/parity.sh --theme both` + `scripts/diff.sh --theme both` | **14/14 PASS**（P0 改动后重跑，`docs/OKR-P0-BASELINE.md` §4） |
| 预算（P3 新增） | `okr_metrics_test.cj` 里断言 `ops ≤ 350`、`textMeasure ≤ 250`/布局、`misses == 0`（第二帧）、`candidates == 0`（1152 宽） | P3 落地时按 P0 基线收紧 |
| 稳定性浸泡 | `scripts/harmony/device_stability.sh 180`（真机，需设备） | 本轮**无设备**，未跑（`docs/OKR-P0-BASELINE.md` §1） |

### 5.4 真机 A/B 矩阵（P1 之后必须做，主机不能替代）

每一项 **5 次**，或**持续 10 分钟**（以先到者为准）；`hilog -r` → 动作 → 立刻 dump
（D 级日志会在数秒内冲掉环形缓冲，`docs/HANDOFF.md` §8）。

| 场景 | 操作 | 观察 | 通过判据 |
|---|---|---|---|
| 列表 idle | 停在 OKR 列表 10 分钟 | 进程存活、`Check failed` / `Cpp Crash` / `onProcessDied` = 0 | 5/5 存活 |
| 列表滚动 | 实体鼠标滚轮连滚 3 秒 ×5 | 同上 + 画面跟随 | 5/5 存活且连续更新 |
| 编辑页 idle | 打开编辑页 10 分钟 | 同上 + `Region size` / GC 间隔日志 | 5/5 存活 |
| 编辑页输入 | 在 notes 连续输入 60s（含中文 IME 组合） | 同上 + 文字不丢、光标不跳 | 5/5 存活且输入正确 |
| 新增 KR | 编辑页新增 5 个 KR 再删除 | 同上 | 5/5 存活 |
| 旧 prompt 对照 | 旧包（`e2bb4f28…`）同一动作 | 88s/2s/17.7s 崩 | 记录崩溃时刻，作为「换组合有效」的对照 |

> 判据必须写「存活 + 无 fail 行」，不能只写「主观不卡」；真机的点击注入见
> `docs/HANDOFF.md` §8（`uitest uiInput click` 只发抬手）。

### 5.5 GC 指标目标

| 指标 | P0 基线（真机，`docs/HANDOFF.md` §6.1） | P1+P2 目标 | P3 目标 |
|---|---|---|---|
| 分配速率 | 峰值 allocated 25.5MB / GC 中位间隔 160ms | 编辑期间≤ 列表 idle 的 1.2× | **−50%**（对比 P0 同场景） |
| 崩溃次数（A/B 矩阵） | 5/5 崩（prompt） | 编辑页 0/5 崩 | 0/5 崩 |
| `ops`/布局 | 302 | 编辑页不计（控件树） | ≤ 350（列表页，含新增的铅笔） |

> 「分配速率 −50%」的测量口径：同一台设备、同一 workspace、同一动作序列，用
> `scripts/harmony/device_stability.sh` 的 `allocated` 采样 + GC 行时间戳；
> 主机只能测相对量（`frameUs`、计数器），**不能**当作分配速率证据。

---

## 6. 分阶段计划（P0–P4）

| 阶段 | 产出 | 验收 | 估时 |
|---|---|---|---|
| **P0（本提交）** | `okr_metrics.cj` + `okr_metrics_test.cj` + `docs/OKR-P0-BASELINE.md`；埋点 19 处 | `cjpm test` **713/713**；parity/diff **14/14**；基线表填好 | 已完成 |
| **P1 编辑页骨架** | `OkrUiState.editId` + 卡片铅笔 `okr-edit-<id>` + `okr_editor.cj`（顶栏/目标/notes/操作）+ `okr_editor_test.cj`；列表页仍可编辑（旧 prompt 路径暂留） | 主机：编辑页控件都有正宽高、标题/领域/状态/信心/notes 写 store、返回后 `editId=""` 且焦点回铅笔；parity 14/14（列表页像素不变，铅笔是**新增**元素 → 需要更新参考图或把铅笔放进 `okr-more` 的溢出菜单，见 §8） | 1.5 天 |
| **P2 KR 迁移 + 列表只读化** | 编辑页 KR 区（指标四格/负责人/状态/信心/上下移/删除）、新增 KR、执行项概览；列表页按 §4.5 只读化；删除 `okr_prompt.cj` 整条路径 | 主机：`okr_inline_editor_test.cj` 相应用例改写或删除（**要在同一提交里说明**）；真机 A/B 矩阵「编辑页 idle / 输入 / 新增 KR」5/5 存活 | 2 天 |
| **P3 分配优化** | §3 表的前 6 项（6 → 2 → 3 → 4 → 5 → 10）；预算测试 | 计数器：`ops` 不增、`textMeasure`/`stringBuilds` 稳态下降、`misses == 0`；parity 14/14 逐字节；真机分配速率 −50% | 2.5 天 |
| **P4 决策与文档** | `docs/OKR-VIEW.md` 增「编辑页」章节、`docs/DEVICE-NOTES.md` 记 A/B 结果、`docs/HANDOFF.md` §6/§9 更新（本方案是**可用性**措施，缺陷仍待运行时修）、`docs/STABILITY.md` §8 追加「第四条路线：换组合」的结论 | 文档里能查到：改了什么、真机矩阵结果、GC 指标前后值、还剩什么风险 | 0.5 天 |

依赖：P1 依赖 P0 的基线（否则无法判断 P3 是否真的降了分配）；P2 依赖 P1（编辑页要能编辑 KR 才能
关掉旧入口）；P3 依赖 P1/P2（否则测的是要被删掉的代码）。**P0 必须先做**，见 §8。

---

## 7. 不做什么

| 不做 | 原因 |
|---|---|
| 把 `RetainedSubtree` 当崩溃修复 | 已证伪（`docs/STABILITY.md` §8.2）：缓存不改变触发面 |
| 再试 GC 环境变量（`cjRegionSize`/`cjHeapSize`/`cjGCThreshold`，含 NAPI `setenv`、`appEnvironments`） | 已证伪（§8.1）：真机 HAP 进程里运行时 `getenv` 看不到 ArkTS 侧设置 |
| 关光标闪烁（CUI-P13）当修复 | 已证伪（§8.3）：10s 内崩，「空闲出帧」不是充分条件 |
| 编辑页也自绘画布（复用 `PageCanvas`） | 就回到了「控件在 layout 阶段构造 → 拿不到焦点」的老路（`docs/DEVICE-NOTES.md` §16），并且保留「自绘页 + IME」这个要拆掉的组合 |
| 编辑页像素对齐 Web（`src/modules/okr/okr.css` 的 `.okr-editor-*`） | 编辑页是原生控件页，排版由 CUI 决定；parity 的 14 张参考图里没有编辑页（它要交互才能打开），逐像素对齐既没有门禁也没有收益。**只要求**：浅/深主题下不出现缺字方框、不重叠、不溢出 |
| 顺便重写列表页为控件树 | 列表页的 302 条指令/布局是「精确几何 + 视口裁剪」换来的；重写会同时动摇 parity 14/14 与 `docs/OKR-VIEW.md` 的数值对照 |

---

## 8. 待拍板

### 8.1 已确认（本轮按此执行）

| # | 决定 | 状态 | 依据 |
|---|---|---|---|
| 1 | **列表页只读**：文本编辑全部迁到独立编辑页，列表页只保留即时动作（信心、上下移、删除、关联、勾选） | **已确认** | 已批准方案；§4.5 的范围表 |
| 2 | **保存模型**：标题/数值/负责人失焦或 Enter 即时写；notes 600ms 防抖 + 返回 flush | **已确认** | 已批准方案；与 Web `ObjectiveEditor.tsx:21-24` 一致 |
| 3 | **原生控件**：编辑页用 `VStack` + `TextField`/`TextArea`/`Button`，不用 `Ui.inlineEditor`/Portal/IME 锚点 | **已确认** | 已批准方案；`docs/HANDOFF.md` §6.2 第 3 条 |
| 4 | **P0 先行**：先落计数器与基线，再动 P1 | **已确认** | 已批准方案；P0 已随本文件交付 |

### 8.2 仍需拍板（会改变像素或交互，需 owner 同意）

| # | 问题 | 建议 | 影响 |
|---|---|---|---|
| 1 | 铅笔放在卡片右上角（新增 26×26 按钮）还是塞进 `okr-more` 菜单 | **放卡片右上角**（Web 就是这样，发现性最好） | 会改动 `okr-light/dark` 参考图 → 必须同一次提交里更新 `tools/parity/ref/okr-*.png` 并在提交说明逐项解释（`AGENTS.md` §4 第 5 条不允许「放宽容差」） |
| 2 | KR 行标题点击在只读化之后的行为 | **打开编辑页并聚焦该 KR 的标题格**（不是什么都不做） | 用户肌肉记忆是「点标题就能改」，直接变死区会被当成 bug |
| 3 | notes 防抖的 600ms 是否也用于指标/标题 | **不**：即时写，只有 notes 防抖 | 指标是「槽位」语义（`okr_prompt.cj:178` 的注释），延迟写会让连续输入产生中间态历史 |
| 4 | 旧 prompt 路径什么时候删 | **P2 同一提交删干净**（`okr_prompt.cj`、`okrPromptDialog`、`OkrUiState.prompt*`、`FocusOnceView(promptFocus)`） | 两套入口并存会让「分配速率」基线失真，也会让 A/B 无法归因 |

---

## 9. P0 基线（实测）

完整表格、命令输出与真机引用见 **`docs/OKR-P0-BASELINE.md`**。摘要：

| 每**次 layout**（演示数据，1152 宽，详细密度） | 值 |
|---|---|
| `ops` | 302（`texts=129 fills=55 strokes=37 rings=47 icons=13 lines=7 chevrons=6 shadows=6 dashes=1 dots=1`） |
| `hotspots` | 86 |
| `widgets` | 9 |
| `textMeasure` | 224（第二帧 `misses=0`，宽度缓存全命中） |
| `ellipsize` / `candidates` | 25 / 0（1152 宽不截断；520 宽时 `candidates > 0`） |
| `stringBuilds` | 13 |
| `focusableIds` | 0（只在焦点遍历时调用；一次返回 46 个 id） |
| 帧耗时 | 主机 `WidgetTestHost` 一帧 ≈ 0.8–1.8ms（含 build+measure+layout+draw），**不等于**真机 7.7ms/帧 的口径 |
