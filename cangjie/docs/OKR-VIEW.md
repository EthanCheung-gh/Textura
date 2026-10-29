# OKR 视图：实现与 Web 数值对照

本文件记录 OKR 页（`src/views/okr/`）与 Web 版（`src/modules/okr/`）的逐项数值对照。
§1–§3 是「关联执行项」弹窗（`LinkItemsDialog.tsx` + `okr.css:1283-1404`）的对照——它在真机上曾经
**列表里看不到执行项**，根因与修法见 §2、§3；§6 是 P1+P2 落地的「独立编辑页 + 只读列表」。

- Web 源码是唯一事实来源；实现值全部来自 `okr.css` / `ui.css` / `tokens.css`。
- 颜色/间距只从 `textura.ui` 令牌取；数值常量集中在 `okr_link_list.cj` 顶部。
- 1440×900 的七路由像素门禁不包含弹窗（弹窗需要交互打开），因此弹窗靠主机测试
  （`okr_link_test.cj` / `okr_dialogs_test.cj`）+ 真机截图验收；编辑页同样不在参考图里
  （要点击铅笔才会出现），像素例外见 §6.7。

---

## 1. 「关联执行项」弹窗：CSS → 实现值

| CSS（Web） | 值 | 仓颉实现 |
|---|---|---|
| `.modal` 宽（`LinkItemsDialog.tsx:79` `width={640}`） | 640 | `Ui.modal(..., width: 640.0)`（`okr_dialogs.cj`） |
| `.modal` 最大高 / 位置（ui.css:472） | `max-height: 80vh`，顶部 10vh | `ModalFrame.resolve`（`ui/modal.cj`） |
| `.modal-header` 内边距 / 标题 / 副标题 | `16px 24px`；15/650；12.5 | `Ui.modal` 头部（`tokens.space.s5`、`TextSize.subheading`、`controlSmall`） |
| `.modal-body` 内边距 | 24 | `MODAL_BODY_PAD = 24`（`ui/modal.cj`） |
| `.modal-footer` | `12px 24px`、按钮 gap 8、右对齐 | `MODAL_FOOTER_VPAD = 12`、`HStack(spacing: s2)` |
| `.okr-link-search` | `display:flex; gap:8px` | `HStack(spacing: 8)` + 15px 搜索图标 |
| `.okr-link-search .input` | `flex:1`；`min-height:34px`；13.5px；radius 8；1px 边框 | `linkSearchField`：`TextField.flex()`，高 34，字号 13.5，`SurfaceStyle(surface, border, r=8)`，聚焦换 accent 边框 |
| `.okr-dialog-hint` | `margin-top:8px; 11.5px; line-height:1.5; text-muted` | 搜索行与提示同处 `VStack(spacing: 8)`；`Label` 11.5 / `textMuted` |
| `.okr-link-list` | `gap:2px; max-height:46vh; overflow-y:auto; margin-top:12px` | `OkrLinkList`：`OKR_LINK_ROW_GAP=2`、`maxHeight = 0.46 × viewportHeight`、body `VStack(spacing: 12)`；滚轮/裁切在列表内 |
| `.okr-link-item` | `gap:10px; padding:8px 10px; border:1px transparent; radius:8` | `OKR_LINK_ROW_PAD_X=10`、`OKR_LINK_ROW_GAP_X=10`、`OKR_R_MD=8`；行边框盒高 **55.25**（1+8+19.5+2+15.75+8+1） |
| `.okr-link-item:hover` | `background: surface-2` | 行悬停（`ctx.isHovered`）填 `surface2` |
| `.okr-link-item.is-checked` | `background: accent-soft; border-color: accent/30%` | `accentSoft` + `accent.withAlpha(77)` 描边 |
| `.okr-link-item.is-linked` | `background: surface-2`；标题 `text-muted` | 已关联行优先用 `surface2`（CSS 声明顺序在 is-checked 之后）+ 标题 `textMuted` |
| `.okr-check` | **14×14**，`accent-color`，`flex:none` | `OKR_LINK_CHECK=14`，radius 3；勾选为 accent 填充 + check 图标，未选为 surface + `borderStrong`（`okr.css:773` 是 14px，不是 16px） |
| `.okr-link-main` | `flex:1; min-width:0; column; gap:2px` | 主列宽度 = 行宽 − 1 − 10 − 14 − 10 − 10 − 100 − 1（左右内边距/勾选框/gap/进度区），标题与 meta 间距 2 |
| `.okr-link-title` | `13px; weight 550; line-height:1.5` | `OKR_LINK_TITLE_SIZE=13`、重量 550、行盒 19.5 |
| `.okr-link-meta` | `gap:6px; flex-wrap:wrap; 10.5px; text-muted` | 单行排布（主列宽度足够；窄窗口仍按顺序绘制，超出部分省略），`OKR_LINK_META_GAP=6`、10.5 |
| 徽章（类型/状态/已关联） | `.badge { 11px; padding 2px 7px; 1px; radius }` | `PageCanvas.badge` → `BadgeView`，高 23.6（`OKR_BADGE_H`） |
| `.okr-area` / `.okr-area-dot` | `11.5px; gap:5px`；dot 7px | `OKR_LINK_AREA_SIZE=11.5`、`OKR_LINK_DOT=7`、间隙 5，颜色取 `Area.color` |
| 排期文案 | `formatSchedule(item)`（11.5px mono） | `linkScheduleText` + 10.5px mono（meta 行字号） |
| `.okr-link-progress` | `flex: 0 0 100px; gap:6px; 10.5px` | `OKR_LINK_PROGRESS_W=100`、gap 6；进度条高 5（`ProgressView Sm`）+ 右对齐百分比文字 |
| 空态 | `EmptyState compact`（图标/标题/描述） | `Ui.emptyState(..., compact: true)`：「没有匹配的执行项 / 换个关键词，或先在甘特 / GTD 中创建行动。」 |
| `.okr-link-count` | `margin-right:auto; 12px; text-muted` | 页脚 `Label("已选 N")` 12 + `Spacer()` |
| 页脚按钮 | 取消 ghost；`关联所选` primary，`disabled={selected.size===0}` | `Ui.button("取消", Ghost)`；`Ui.button("关联所选", Primary, enabled: selected+removed > 0)` |

### 1.1 与 Web 版有意不同的两处

1. **已关联项可取消**：Web 把已关联行的 checkbox 设为 `disabled`；按本轮用户要求，已关联行
   仍默认勾选，但可取消，确认时对取消项执行 `store.deleteEdge`（`linkRemoved` 独立记录）。
   页脚计数仍只显示「已选 N」（待关联数），通知里会区分「已关联 N，解除 M」。
2. **按钮文案保留「关联所选」**（Web 原文），未改成「确认关联」。

---

## 2. 真机「列表看不到执行项」的根因（已修复）

旧实现的一行是：

```text
HStack { 选择按钮; VStack { 标题 / 徽章行 }.hug().flex(); ProgressView }
```

`ProgressView.measure` 返回 `Size(available.w, …)`（进度条要占满轨道）。它在 HStack 里是
**非 flex 子项**，在固定测量阶段先被量成整行宽度，`remaining` 变成 0；随后 flex 主列
（标题/徽章）只分到 **0 宽**。控件确实存在、也进了语义树，但文字盒子宽度为 0，所以屏幕上
一片空白。

主机探针（修复前）输出：`row '官网改版' rect=291.25,271,0.00,28` —— `w == 0`。

---

## 3. 修法：`OkrLinkList`（自绘 + 语义）

- 新增 `okr_link_list.cj`：用本页既有的 `PageCanvas` 逐像素布局（行高/内边距/字号全部由
  §1 的常量推导），不再依赖栈的剩余宽度分配；每行宽度 = 列表宽度，标题/徽章/进度各有
  明确矩形。
- 交互：整行点击切换勾选；悬停 `surface-2`；滚轮滚动（内容高于 46vh 时，窗口跟随并裁切）；
  `MouseMove` 用 `claimHoverIfInside` 声明指针形状。
- 每行注册一个 `Checkbox` 语义节点（标题 + `checked` + `Activate`），主机测试可断言
  「首屏 ≥5 行、行宽 > 0、勾选/取消、确认写边、空态」。
- 候选池（`okrLinkCandidates`）：全部 `project` + `action`；**排除 `dropped`**；按
  「父路径（`parentPathText`）→ 标题」稳定排序；再按查询过滤（标题/标签/负责人/备注/领域名，
  复用 `matchesQuery`）。
- 打开时查询初值取 `store.ui.search`（与 Web `useEffect` 一致），搜索框自动聚焦
  （`FocusRequest` + `Ui.modal` 的 `focus`）。

---

## 4. 主机回归

| 文件 | 覆盖 |
|---|---|
| `okr_link_test.cj` | 候选非空/排除 dropped/排序；首屏 ≥5 行且行宽 >0；勾选+确认写 `okr` 边；已关联取消+确认删边；无匹配时显示空态 |
| `okr_dialogs_test.cj` | 新建目标 / 季度选择 / 目标菜单 / KR 状态 / 删除确认：关键文案与页脚按钮都进入语义树且有正宽高 |
| `okr_page_test.cj` | `measure` 在首次 layout 前就能给出内容高度（DEVICE-NOTES §12） |
| `okr_editor_test.cj` | 独立编辑页（§6）：字段可见、点铅笔出现输入、单编辑态、Enter/失焦写库、notes 600ms 防抖与返回 flush、Esc 两段、返回后焦点请求回铅笔、目标不存在空态 |
| `okr_inline_editor_test.cj` | 列表页只读化：热区白名单/黑名单、焦点环无文本项、铅笔进编辑页、页底新增入口带 `add-kr`、执行项勾选仍即时生效、信心只读 |

---

## 5. 待补

- 真机截图：弹窗打开显示多行候选、勾选一行、确认后 KR 行出现该执行项。本轮 HAP 已重编并安装成功
  （`STATUS: installable`），但设备锁屏需要指纹/密码，`aa start` 被系统拒绝
  （`10106102 The device screen is locked`），因此截图待解锁后补；复跑命令见
  `docs/DEVICE-NOTES.md` §18.7。
- Web 版窄窗口（≤1180）下弹窗的行为未单独对拍；弹窗宽度固定 640，在 1024 视口里
  `Ui.modal` 会夹到 `min(640, viewport-48)`，行内主列按剩余宽度省略标题。
- 编辑页（§6）的**真机**验收与**像素**对齐都还没做，见 §6.7。

---

## 6. 独立编辑页与只读列表（P1+P2，已实现·主机）

方案与分阶段计划见 `docs/OKR-EDIT-PLAN.md`；本节记录**落地后**的事实（入口、只读范围、保存模型、
Esc 语义、像素与待办）。

### 6.1 两个页面二选一

`okr.cj` 的 `render()` 只做一件事：把状态壳交给 `okrView(ctx, ui)`，由它按 `ui.editId` 二选一。

| `ui.editId` | 渲染 | 说明 |
|---|---|---|
| `""` | `OkrPage`（自绘画布，**只读**）+ `okrDialogs` + `FocusOnceView(ui.editorFocus)` | 列表态；逐像素布局照旧 |
| 非空 | `okrEditorPage`（原生控件树）+ `okrDialogs` | 编辑态；同一帧里列表画布**不再构建**（两套热区不会抢同一次点击） |

- 入口：每张目标卡右上角的铅笔 `okr-edit-<objId>`（26×26、`IconGlyph.Edit`，排在 `okr-more-<objId>` 左侧）。
  点击 → `ui.editId = id`、`ui.editTarget = ""`、`store.select(id)`（侧栏/检查器同步）、
  焦点请求指向编辑页的第一支铅笔。
- 页底「新增关键结果」入口 → `openOkrEditor(..., "add-kr")`：直接展开新增输入框并聚焦。
- 目标不存在 / 被删除：编辑页渲染空态「目标不存在或已被删除」+ 返回按钮，不白屏。

### 6.2 列表页只读范围（P2）

| 元素 | P2 之后 |
|---|---|
| 目标标题 / 备注 / KR 标题 | 纯文本（`ellipsize` 截断），**不再有** `okr-title-` 热区与输入框外观 |
| 指标四格（起点/当前/目标/单位） | 「标签 + 值」纯文本 + `formatMetric` 摘要 + `换算 N%`；**不再有** `okr-field-` 热区 |
| 负责人 / 状态 | 纯文本「负责人 X · 状态 Y」；**不再有** `okr-owner-` / `okr-status-` 热区 |
| 信心刻度 | **只读**：`paintConfidenceScale(onChange: None)` 不注册 `okr-conf-` 热区、不画悬停与焦点环 |
| KR 上移/下移/删除/关联执行项 | 移出列表（只在编辑页） |
| 页底「新增关键结果」 | 整条虚线框是**一个**入口 `okr-add-<objId>` → 编辑页 `add-kr` |
| 目标铅笔 / 更多菜单 | 保留（`okr-edit-<objId>` / `okr-more-<objId>`） |
| 执行项勾选 | 保留（`okr-exec-<itemId>`，不进 IME、不开浮层） |

保留的列表热区白名单见 `okr_inline_editor_test.cj`（`OKR_LIST_ALLOWED_PREFIXES`），黑名单是旧
prompt 路径的全部入口（`okr-title-` / `okr-field-` / `okr-owner-` / `okr-addkr-` / `okr-conf-` /
`okr-status-` / `okr-up-` / `okr-down-` / `okr-del-` / `okr-link-`）。

### 6.3 停用 `Ui.inlineEditor` 与 prompt（整套删除）

`src/views/okr/okr_prompt.cj` **已删除**，OKR 包内不再有：

- `OKR_PROMPT_INPUT` / `promptAnchor` / `armPrompt` / `closeOkrPrompt` / `okrPromptFocusTarget`；
- `OkrUiState.promptOpen/promptText/promptKind/promptTarget/promptField/promptError/promptFocus/promptAnchor`；
- `okr_dialogs.cj` 的 `okrPromptDialog`、`okr_cards.cj` 的 `okrFieldEditing` / `trackOkrPrompt` / `paintOkrField` / `paintSelect`；
- `okr.cj` 的 `FocusOnceView(promptFocus)`。

编辑页的输入框是普通 `TextField` / `TextArea`（构建期声明），**不用** `Ui.inlineEditor`、**不用**
`Portal`、**不用** IME 锚点 —— 这三件正是 `docs/HANDOFF.md` §6.2 第 3 条要求拆掉的组合。

### 6.4 渐进式单编辑态

`ui.editTarget` 是唯一的编辑目标，取值：

`""`（纯展示）| `title` | `notes` | `area` | `status` | `confidence` | `kr:<id>` | `add-kr`

- 每个可编辑位置有一支小铅笔（`OkrEditorIconButton`，26×26，带稳定 id 与语义标签）；点开才出现输入，
  同一处再点一次 = 收起。
- 切换目标时**先提交上一处**再展开新的（`okrEditorSetTarget` → `okrEditorCommitTarget`）。
- KR 行展开（`kr:<id>`）后一次性给出该行的全部字段：标题、指标四格、负责人、状态、信心、关联执行项、
  执行项勾选/解绑、标记完成 —— 同级最多一个 KR 处于展开态。
- 展开后焦点自动进入新出现的输入框（`FocusOnceView` + `FocusRequest`）；标题类字段**打开即全选**
  （`ui.editSession` + `OkrEditorSelection` 保证一次会话只选一次，同 React `EditableTitle.select()`）。

### 6.5 保存模型

| 字段 | 何时写 store |
|---|---|
| 标题 / KR 标题 | Enter（提交并收起）或失焦 |
| 指标四格 / 负责人 | Enter 或失焦（`pendingMetricPatch` 只合并真的变了且能解析的字段） |
| 领域 / 状态 / 信心 | 点选即写（一排选择按钮，选完自动收起） |
| notes | 停止输入 **600ms** 后写；失焦、返回列表时立刻 flush |
| 新增 KR | Enter / 「添加」即 `createItem`（信心 5），随后清空输入并收起 |

两条实现约束：

1. **视图不读系统时钟**：notes 防抖用 `FrameHandler(info.elapsedMs)`（`ui.notesTick` 记最后一次
   草稿变化的时刻）。代价见 §6.7。
2. **外部改动不打断草稿**：只有 `store 的值 ≠ 自己最后提交的值` 时才覆盖草稿（`okrEditorSyncDrafts`
   跳过当前正在编辑的那一处；notes 用 `ui.notesCommitted` 做基准，同 Web 的 `notesCommittedRef`）。

### 6.6 Esc 两段语义与焦点归还

- 字段内 Esc：取消当前编辑（草稿回退到 store 的值、**不写库**），仍在编辑页。
- 再按一次 Esc：「返回目标列表」——先 flush notes，再 `editId = ""`，并
  `FocusRequest.request("okr-edit-<id>")` 把焦点还给进入时的那支铅笔。
- 实现位置：编辑页根上的 `EventHandler`（先于子控件看到按键；`TextField` 不消费 Esc）。
  浮层（季度对话框 / 删除确认）是 overlay，按 CUI 的派发顺序先于整棵树收到事件，所以对话框里的
  Esc 仍然是「关对话框」。

### 6.7 像素、出帧代价与待办

**本轮不做像素对齐（与用户约定，后续会话处理）**。列表加铅笔 + 只读化后，`okr-light/dark` 与
`tools/parity/ref` 必然不一致，`tools/parity/ref` **没有**被修改：

| 对 | diff% | meanΔ | raw≤32% | blurSSIM | edge ref/out | 结论 |
|---|---|---|---|---|---|---|
| `okr-light` | 11.22 | 5.34 | 95.30 | 0.9182 | 75.87 / 84.47 | 有意变更（铅笔 + 只读）→ 待后续会话对齐 |
| `okr-dark` | 11.25 | 4.53 | 95.89 | 0.9293 | 75.09 / 85.04 | 同上 |

其余 12 张（`dashboard/calendar/gtd/gantt/sop/settings` × 2 主题）在本轮改动后 **12/12 PASS**
（`scripts/diff.sh --route dashboard,calendar,gtd,gantt,sop,settings`）。

出帧代价：编辑页整页包一层 `FrameHandler`（notes 防抖需要 `elapsedMs`），**编辑页打开期间持续出帧**
（每帧重建这棵小控件树）；关闭编辑页即停止，列表画布不受影响。

待办（后续会话）：

1. `okr-light/dark` 的像素对齐（改铅笔位置/只读排版，或按 `docs/PARITY.md` 走参考图更新流程）。
2. 真机 A/B（`docs/OKR-EDIT-PLAN.md` §5.4 的矩阵）：编辑页 idle / 输入 / 新增 KR 各 5 次或 10 分钟，
   判据是「进程存活 + 无 `Check failed` / `onProcessDied`」。本轮无设备（`hdc list targets` 为空）。
3. 编辑页宽窗口排版复核（>1080 时最大宽度 1080 居中）。
