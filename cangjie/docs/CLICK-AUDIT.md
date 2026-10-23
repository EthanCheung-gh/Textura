# 可点击性审计（全控件，含输入框）

> 范围：`cangjie/src/**` 里所有吃指针事件的控件。目的有两个：把「每个控件靠哪段代码响应点击」
> 变成可复查的清单，以及把「按钮码 / 抬手事件 / 命中矩形」这三类系统性风险一次堵死。
>
> 相关：`docs/DEVICE-NOTES.md` §16（焦点只在 build 期登记）、§17（本轮加固与真机矩阵）。

## 0. 判定口径

| 记号 | 含义 |
|---|---|
| **[原生]** | CUI 内建控件（`TextField` / `TextArea` / `Button` / `SegmentedControl` / `ComboBox`），事件协议在 `third_party/CUI` 内 |
| **[自绘]** | Textura 自己绘制 + 自己命中（`src/ui` 的 `ButtonView`/`IconButtonView`/`SegmentedView`，或各视图的 canvas/hotspot） |
| **主键判定** | 一律 `textura.ui.isPrimaryPointerButton(button)`（`Left` / `RawCode(0)` / `RawCode(1)`），由源码门禁 `src/shell/pointer_gate_test.cj` 强制 |
| **抬手** | 统一匹配 `MouseUp(_, x, y)`（不校验 button），配合按下时记录的 `ctx.press(id)` 触发 |

扫描方法（可复跑）：

```bash
cd cangjie
# 按下 / 抬手的直接匹配（门禁测试也做同一件事，排除 *_test.cj）
grep -rn "MouseDown(MouseButton\.\|MouseUp(MouseButton\." src | grep -v "_test.cj"
# 自绘命中区
grep -rn "addHotspot(" src/views
# 共享控件
grep -rn "ButtonView(\|IconButtonView(\|SegmentedView(" src
```

## 1. 侧栏（`src/shell/sidebar.cj`）

| 控件 | 类型 | 命中代码 | 观测变化 |
|---|---|---|---|
| 7 个路由行 | [自绘] | `src/shell/sidebar.cj:276` `SidebarView.handle` → `ctx.focus("shell-nav-<route>")` | `store.ui.route` |
| 领域（Area）行 | [自绘] | 同上（`sidebar.cj` 的 area 行分支） | `store.setSearch` / 路由过滤 |
| 保存状态页脚 | 文本 | —（仅展示） | — |

回归：`src/shell/sidebar_click_test.cj`（行内按压→路由；行外按压不变）。

## 2. 顶栏（`src/shell/topbar.cj`）

| 控件 | 类型 | 命中代码 | 观测变化 |
|---|---|---|---|
| 搜索框 | [原生] | `topbar.cj:96` `TextField(key: "shell-search")` | 输入 → `store.setSearch`，路由列表过滤 |
| 主题切换按钮 | [自绘] | `topbar.cj` `IconButtonView` → `host.toggleTheme()` | `store.ui.theme` 与提示条 |

回归：`src/shell/input_focus_test.cj`（`shell-search` 逐帧枚举点击）。

## 3. 命令面板 / 快速收集（`src/shell/palette.cj`、`src/shell/capture.cj`）

| 控件 | 类型 | 命中代码 | 观测变化 |
|---|---|---|---|
| 命令面板搜索框 | [原生] | `palette.cj:590` `TextField(key: "palette-search")` | `palette-query` → 结果重算 |
| 命令面板结果行 | [自绘] | `palette.cj:159` / `:204` / `:253`（`PaletteRowView` 等） | `runPaletteRow`（路由 / 主题 / 新建） |
| 面板页脚提示芯片 | 文本 | —（仅提示） | — |
| 快速收集输入框 | [原生] | `capture.cj` `TextField(key: "capture-input")` | 输入 → 解析预览；Enter 进收件箱 |
| 收集 / 收集并关闭 / 关闭 | [自绘] | `capture.cj` `Ui.button` | `store.createItem` / 关闭弹层 |
| 撤销最后一条 | [自绘] | `capture.cj` `IconButtonView` | 删除刚收集的条目 |

回归：`input_focus_test.cj`（`palette-search`、`capture-input`）、`keys_test.cj`（Ctrl+K/Esc）、
`press_test.cj`（弹层页脚按钮经 overlayer 派发）。

## 4. GTD（`src/views/gtd/`）

| 控件 | 类型 | 命中代码 | 观测变化 |
|---|---|---|---|
| 收件箱行选择 | [自绘] | `gtd_parts.cj:313` / `:382` | `selectedId` |
| 勾选圆（完成/未完成） | [自绘] | `gtd_parts.cj:442` / `:532`… | `store.toggleDone` |
| 2 分钟按钮 / 转为下一步 | [自绘] | `gtd_parts.cj:607` / `:663` | `store.updateItem`（status） |
| 分页 / 筛选 / 侧栏 | [自绘] | `gtd_parts.cj`、`gtd_side.cj` | 视图状态 State |
| 快速收集按钮 | [自绘] | `gtd_inbox.cj` / `gtd_next.cj` `Ui.button` | `store.ui.quickCaptureOpen` |
| 澄清弹层输入（标题/备注/场景/日期/标签） | [原生] | `gtd_clarify.cj:280` 等 `Ui.textInput`/`Ui.textArea` | 表单 State → `submitClarify` |
| 澄清弹层按钮 / 分段 / 选择器 | [自绘]/[原生] | `gtd_clarify.cj:484` / `:619`（选择器弹层） | 表单 State |

回归：`input_focus_test.cj`（澄清弹层的 `gtd-clarify-*` 字段在枚举内）。

## 5. OKR（`src/views/okr/`）

| 控件 | 类型 | 命中代码 | 观测变化 |
|---|---|---|---|
| 季度 chip / 新建季度 | [自绘] | `okr_page.cj:385` `OkrPage.handle` → `addHotspot` | `store.setOkrPeriod` / 弹层 |
| 目标卡标题 / KR 标题 | [自绘] | `okr_cards.cj` `addHotspot` → `openOkrTitlePrompt` | 浮层保存 → `updateItem(title)` |
| 指标（起点/当前/目标/单位） | [自绘] | `okr_cards.cj` `paintOkrField` → `openOkrMetricPrompt` | 浮层保存 → `setMetric` |
| 负责人 | [自绘] | `okr_cards.cj` `paintOkrField` → `openOkrOwnerPrompt` | `OkrPatch.krOwner` |
| 新增 KR | [自绘] | `okr_cards.cj` `layoutAddKeyResult` | 浮层保存 → `addKeyResult` |
| 信心刻度 | [自绘] | `okr_page.cj` `paintConfidenceScale` | `store.setConfidence` |
| 展开/折叠、上移/下移、关联、删除 | [自绘] | `okr_cards.cj` / `okr_views.cj` `addHotspot` | State / `moveItem` / `deleteItems` |
| 新建目标、关联、状态、删除确认弹层 | [原生]+[自绘] | `okr_dialogs.cj:39` 等 `Ui.modal` + `Ui.textInput` | 表单 State → store |

回归：`input_focus_test.cj`（`okr-dlg-*` 弹层字段）、`src/views/okr/okr_page_test.cj`、
`src/ui/prompt_test.cj`（浮层 Enter/Esc/校验）。

## 6. 日历（`src/views/calendar/`）

| 控件 | 类型 | 命中代码 | 观测变化 |
|---|---|---|---|
| 上/下月、今天 | [自绘] | `calendar.cj` `calNavTray` → `Ui.button`/`Ui.iconButton` | 月份 State |
| 月/周分段 | [自绘] | `calendar.cj` `SegmentedView` | `mode` State |
| 月格 / 周列 | [自绘] | `month_grid.cj:313`、`week_view.cj:313` | `selected` 日期 |
| 右面板勾选圆 | [自绘] | `day_panel.cj:367` | `store.toggleDone` |
| 右面板行选择 | [自绘] | `day_panel.cj:367` | `currentSelectedId` |
| 快速添加输入框 | [原生] | `calendar.cj` `quickField` `TextField(key: "calendar-quick-input")` | Enter → `store.createItem` |
| 添加按钮 / 在甘特中查看 | [自绘] | `calendar.cj` `Ui.button` | 创建条目 / 切换路由 |

回归：`input_focus_test.cj`（`calendar-quick-input` 必在枚举内）。

## 7. 甘特（`src/views/gantt/`）

| 控件 | 类型 | 命中代码 | 观测变化 |
|---|---|---|---|
| 缩放分段 / 工具按钮 | [自绘] | `toolbar.cj:111` | 缩放 State / 新建 / 切换检查器 |
| 分组折叠 / 行选择 | [自绘] | `body.cj:224` `handleDown` | `collapsed` / `store.select` |
| 任务条拖拽 | [自绘] | `body.cj:224`/`:282` | `commitBar` → `setGanttRange` |
| 检查器标题 / 开始 / 结束 / 保存 | [原生] | `inspector.cj:83`/`:166` `Ui.textInput` | Enter 或按钮 → `updateItem` |
| 进度 ±5% / 标记完成 / 清除日期 | [自绘] | `inspector.cj:137` 等 `Ui.button` | `setProgress` / `toggleDone` |

回归：`input_focus_test.cj`（`gantt-title`/`gantt-start`/`gantt-end`）。

## 8. SOP（`src/views/sop/`）

| 控件 | 类型 | 命中代码 | 观测变化 |
|---|---|---|---|
| 流程列表项 | [自绘] | `sop_list.cj:234` | `selectedSopId` |
| 画布节点 / 连线 / 圆点连线 | [自绘] | `sop_canvas.cj:888` | 选中 / 连线 / 拖拽位置 |
| 工具栏（新建步骤/运行/布局/缩放） | [自绘] | `sop_canvas.cj:1147` | `store.createItem` / `RunSession` |
| 运行条（通过/驳回/下一步） | [自绘] | `sop_runbar.cj:271` | `RunSession` → `store.recordRun` |
| 检查器标题/说明/负责人/时长/检查项 | [自绘] | `sop_inspector.cj` `handleInspector` → `Ui.prompt` | `updateItem`（SopPatch） |
| 检查器类型 chip / 复制 / 删除 / 分支预设 / 删除连线 | [自绘] | `sop_inspector.cj:686` 等 | `SopPatch` / `deleteEdge` |

回归：`src/views/sop/sop_prompt_test.cj`（浮层写回与校验）。

## 9. 设置（`src/views/settings/`）与仪表盘（`src/views/dashboard/`）

| 控件 | 类型 | 命中代码 | 观测变化 |
|---|---|---|---|
| 主题/密度分段、导入、导出、重置、清空 | [原生]+[自绘] | `settings.cj:623` 等 `Ui.modal` + `Ui.button`/`SegmentedView` | `store.ui` / 工作区写回 |
| 仪表盘卡片点击（焦点卡/OKR/SOP/活动） | [自绘] | `focus_card.cj`、`okr_card.cj`、`sop_card.cj`、`stats.cj` | 路由切换 / 弹层 |

## 10. 本轮加固（防复发）

1. **按钮码**：`third_party/CUI` 新增 `TEXTURA-CUI-P08`（`src/core/pointer_buttons.cj` +
   `event_sequence.cj`）：主键事件在进入框架时把 `RawCode(0|1)` 归一成 `Left`，所有内建控件
   （按钮、分段、输入框、下拉）与自绘控件共用同一套判定；中间键/右键不变。
   应用层同时保留 `textura.ui.isPrimaryPointerButton`，两处任意一处失效都不会静默。
2. **源码门禁**：`src/shell/pointer_gate_test.cj` 扫描生产源码，出现
   `MouseDown(MouseButton.` / `MouseUp(MouseButton.` 直接匹配即失败，并附上文件:行号。
3. **抬手**：全部改为 `MouseUp(_, x, y)`；控件用「按下时 `ctx.press(id)` + 抬手命中矩形」触发，
   不再依赖抬手事件的 button 字段。
4. **命中矩形时效**：自绘控件的命中矩形全部在 `layout`（或 `draw` 同帧）计算并保存到控件实例，
   事件在下一帧重建前到达时仍然有效；画布类（OKR `PageCanvas`、甘特 `GanttBody`、SOP `SopFrame`）
   的矩形随每次 layout 刷新，`OkrPage`/`SopPageWidget` 的 `measure` 只做高度预演，不写回矩形。

回归覆盖（主机）：`src/shell/press_test.cj`（按钮三种按钮码、分段、弹层页脚按钮）、
`src/shell/sidebar_click_test.cj`（行选择）、`src/shell/input_focus_test.cj`（输入框逐帧枚举）、
`src/ui/prompt_test.cj`（浮层保存/取消）。

## 11. 仍不可点击 / 有条件的控件

| 控件 | 状态 | 原因 |
|---|---|---|
| 各画布内的滚动条拖拽 | 不可点 | 画布类视图（OKR/SOP/甘特画布）没有滚动条，只有滚轮；不是本轮引入 |
| `TextField` 只读态 | 可聚焦不可编辑 | `editable: false` 有意退出 Tab 序列（CUI 契约） |
| 弹层遮罩外点击 | 可点，语义是「关闭」 | 与 Web `Modal.tsx` 一致 |
| 自绘控件的无障碍语义 | 缺 | 只有原生控件注册 `SemanticsNode`；自绘热点尚未登记语义（无障碍/自动化可用性缺口，与本轮点击问题无关） |
