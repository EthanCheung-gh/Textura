# 甘特视图（`textura.views.gantt`）实现说明

本文件记录甘特视图**渲染层**的结构、坐标系、交互与已知差异。算法层（刻度、吸附、几何、
虚拟化、分组、依赖折线）见 `docs/GANTT-LOGIC.md`，这里不重复。

移植来源（只读参照）：`src/modules/gantt/{GanttPage,GanttToolbar,GanttTree,GanttTimeline,
GanttBar,GanttDependencies,GanttInspector}.tsx`、`src/modules/gantt/gantt.css`。

## 1. 文件与分层

| 文件 | 行 | 职责 |
|---|---:|---|
| `gantt.cj` | 248 | `render(ctx)`：读 store → 投影 → 派生 → 页头/工具栏/主体/检查器；缩放、平移、今天、适配窗口、新建任务 |
| `metrics.cj` | 86 | 全部盒模型与字号常量（逐条标注 gantt.css 行号；`HEADER_H`/`ROW_H`/`BAR_TOP`/`BAR_H` 由 `logic` 常量派生） |
| `palette.cj` | 102 | `color-mix()` 派生色（`GanttInk`）、`mixColor()`、`tokensFor(theme)` |
| `text_paint.cj` | 172 | 文本基线/左中右对齐/省略号截断/细线/圆点/菱形/三角/`cssBorder`/`cssRing` |
| `rows_map.cj` | 183 | `core.data.Item → logic.GanttRow` 投影、可排期过滤、最早日期、zoom wire 互转、`M/d` 文案 |
| `view_state.cj` | 94 | 折叠集合、拖拽手势（`DragGesture`，预览走 `logic.moveBar/resizeBar`） |
| `page_header.cj` | 48 | 页头（h1 22px/650 + 副标题 13px，总高 57） |
| `toolbar.cj` | 112 | 工具栏（`textura.ui` 控件：Segmented/Button/IconButton） |
| `body.cj` | 425 | 主体自定义 Widget：圆角外角回填、主体/检查器底、树与时间轴调度、滚动与命中测试 |
| `body_tree.cj` | 276 | 左侧两级树（表头、分组行、条目行） |
| `body_timeline.cj` | 520 | 时间轴（两级表头、网格层、汇总条、任务条、依赖折线、今日线、拖拽提示） |
| `inspector.cj` | 258 | 右侧检查器（标题/开始/结束/工期/进度/状态，写回 store） |

依赖方向：`textura.views.gantt` → `cui`、`textura.ui`、`textura.core.data`、
`textura.views.gantt.logic`。不 import `shell`、不 import 其它视图。

## 2. 坐标系

页面盒（1440×900，shell chrome = topbar 56 + `.shell-content` padding 24）：

```
窗口 (0,0) ─ 侧栏 240 ─┬─ topbar 56 ────────────────────────────
                       │  content padding 24
                       │  ┌ page (x 264..1416, y 80..876) ────┐
                       │  │ page-header  57                  │
                       │  │ gap          12                  │
                       │  │ toolbar      48（含 1px 描边）    │
                       │  │ gap          12                  │
                       │  │ body        667（含 1px 描边）    │
                       │  └──────────────────────────────────┘
```

主体内部（去掉 1px 边框后）：左树 272（含右侧 1px 描边，内容 271）｜时间轴 878｜
可选检查器 320（含左侧 1px 描边）。行高 36、两级表头 52（含底部 1px）。

时间轴画布坐标：

- `canvasX(日期) = diffDays(range.start, 日期) × pxPerDay`（`pxPerDay`：日 40 / 周 28 / 月 12）；
- `screenX = 时间轴左边 + canvasX − scrollLeft`；
- `screenY = 表头底 + rowIndex × 36 − scrollTop`（表头吸顶，不随纵向滚动）；
- 今日线 `todayX = diffDays(range.start, today) × px + px/2`（画布坐标，随横向滚动）；
- 过去遮罩覆盖 `[0, todayX)`，与 CSS `.gantt-past` 同义。

主体高度 = `ctx.height − topbarHeight − 2×space-5 − 57 − 2×12 − 48`（1440×900 → 667）。
必须显式给高度：shell 用 `ScrollView` 包裹路由内容（`.shell-content { overflow: auto }`），
父级可用高度是无界的，跟随父级会让 2000 行时画布铺满整条内容、虚拟化失效（实测从
5.4ms 涨到 254ms/帧）。

## 3. 自绘结构

主体是一个自定义 `Widget`（协议与 `CanvasWidget` 相同，但自行控制背景与裁剪：
`CanvasWidget` 会强制铺一层 themed 背景并把裁剪内缩 1px，会吃掉主体边框那一像素）。
文本仍走 `Renderer.text`——与 `Label` 同一条 SDL_ttf 栅格化路径，清晰度不变。

文本定位（`text_paint.cj`）：

- 垂直：CSS 把行盒（`line-height: normal` ≈ 1.448em、ascent 1.16em）居中在行内，基线落在
  `centerY + 0.436em`；`Renderer.text` 以行盒顶为原点，故 `y = 基线 − ascent`；
- 再减去按字号分段的经验补偿 `nudgeFor`：≥18px（页头 h1）取 0，其余取 0.6px
  （`Renderer.text` 会把原点吸附到整像素，浏览器保留小数基线）；
- 1px 描边一律走 `cssBorder`（描边中心在 `rect.inset(0.5)`，与 CSS 把边框画在 border-box
  内侧一致）与 `cssRing`（`box-shadow: 0 0 0 1px`，中心在外 0.5px），否则会糊成两行半覆盖；
- 圆角矩形的四个“弧外区域”按行回填页面底色 `--bg`（CUI 只有矩形裁剪）。

绘制顺序（对应 CSS z-index）：行底/分隔线 → `--bg-subtle` 过去遮罩（45%）→ 周末底纹（62%）
→ 列网格线（`border` 55%）→ 月/季分隔线（`border-strong`）→ 分组汇总条（8px 药丸）→
任务条（22px，含进度填充与手形）→ 依赖折线 + 箭头（`text-muted` 1.3，选中/悬停
`accent-ink` 2.2 + 端点圆点）→ 今日线（1px `accent`）→ 拖拽提示。

## 4. 手势与吸附

- **滚动**：滚轮纵向（dy）写 `scrollTop`，`dx` 写 `scrollLeft`；都夹在
  `[0, maxScroll]`，`maxScrollTop = rows×36 − (主体高 − 52)`，
  `maxScrollLeft = totalWidth(range) − 时间轴宽`。左树与时间轴共用同一个 `scrollTop`。
- **拖动改期**：`MouseDown` 在任务条上开始手势。左右各 7px 判定为 `Start`/`End`（
  `.gantt-bar-handle` 宽 7），其余为 `Move`；里程碑只能整体移动。
  `MouseMove` 里 `deltaDays = tsRound((x − startX) / pxPerDay)`——**严格复用**
  `logic.tsRound`（`Math.round` 半值向 +∞）与 `logic.moveBar` / `logic.resizeBar`
  （含最小 1 天、左右夹取），视图层不另写取整。
  `MouseUp` 时若区间有变化则 `store.updateItem(id, ItemPatch().withGanttRange(...))`。
  拖动预览直接参与绘制（条与拖拽提示都按预览区间算）。
- **折叠**：分组行箭头 18×18 热区，写 `GanttViewState.collapsed` 后递增 `rev` 触发重建；
  `buildRows` 重算行模型。
- **选中**：点树行 / 点条 / 点空白（`""` → `None`）都走 `store.select`；检查器与依赖高亮跟随。
- 跨帧状态：滚动位置与折叠集合是 `State`；手势、悬停行、视口尺寸放 `remember` 保留的
  `GanttViewState`，改动后递增 `rev`。绘制阶段只读状态。

## 5. 虚拟化

- 行：`visibleRows(max(0, scrollTop − 52), 主体高 − 52, 36, buffer 4, total)`，
  只画窗口内的行（树与时间轴各自算，参数相同故严格对齐）。
- 列：`visibleColumns(scrollLeft, 时间轴宽, columnWidths, buffer 2)`；分组用同样的函数按分组宽。
- 周末底纹逐日遍历可见列区间（上限 400 天），不按总日期数遍历。
- 实测（`--profile`，60 帧均值，1440×900、OpenGL 2x 超采样、Xvfb 软件 GL）：

| 数据 | 绘树 | 构建 | 布局 | 每帧文本绘制 | 总帧时 | P50 / P95 |
|---|---:|---:|---:|---:|---:|---:|
| 30 条（13 行） | 5.39ms | 0.09ms | 0.23ms | 90 | 28.8ms | 27.4 / 37.2ms |
| 2000 条（2001 行） | 5.58ms | 1.22ms | 0.32ms | 116 | 33.7ms | 30.3 / 43.6ms |

行数从 13 涨到 2001，绘制耗时基本不变（文本绘制 90 → 116 次），即虚拟化生效。
总帧时的其余部分是 shell 与超采样合成（`降采样 10.3ms + 呈现 16.2ms`），
同样容器的 `settings` 路由 `降采样 17.2 + 呈现 28.9ms` 即为该环境地板。

## 6. 已知差异

| 项 | 说明 |
|---|---|
| 工具栏文本基线 | 工具栏用 `textura.ui` 控件，其内部 `textLeading` 比浏览器低约 1.3px；改它属于 `textura.ui` 契约变更，未动。这是工具栏区块 6.5~7.1% 超差的主因。 |
| 字重合并 | CSS 550/600/620/650 是可变字重；`Textura UI`/parity 字体只有 Regular/Bold，600 以上落 Bold，视觉上分组标题略粗于参考图。 |
| 依赖新增/删除 | 检查器未提供「添加依赖」「删除依赖」表单（Web 版有）；依赖边按 store 现有数据渲染。 |
| 双击就地改名 | 未实现树内联输入框；改名走右侧检查器（`Enter` 或「保存标题」写回 store）。 |
| 拖拽取消 | 未接 `Escape` 取消手势（Web 版支持）；松手即提交。 |
| 滚动条 | 未绘制（parity 截图关闭滚动条）；滚动只靠滚轮，无拖拽条。 |
| 分组汇总条点击 | 汇总条不参与命中测试（点击落到该行 → 选中分组），Web 版点条本身也选中分组，行为等价但少了指针反馈。 |
| 图标 | 树里的折叠箭头/文件夹图标复用 `textura.ui.paintSpec`（同一套 SVG 几何），笔画随尺寸缩放；与浏览器亚像素抗锯齿仍有 1px 级差异。 |
| 文本栅格化 | `Renderer.text` 吸附到整像素而浏览器保留小数基线，字形边缘有 1px 级灰阶差；这是自绘文本无法消除的固有差异（见 `nudgeFor` 的补偿）。 |

## 7. 验收数据（1440×900，`--route gantt`，today=2026-03-16）

| 主题 | 原始 SSIM | 1px 模糊 SSIM | ΔRGB≤32 占比 | mean ΔRGB |
|---|---:|---:|---:|---:|
| light | 0.9668 | 0.9825 | 98.39% | 2.23 |
| dark | 0.9678 | 0.9847 | 98.46% | 2.06 |

两次独立运行 sha256 一致（light `94ab3cd5…`, dark `52ae55a3…`）。

逐区块超差占比（light / dark）：

| 区块 | light | dark |
|---|---:|---:|
| 页头 | 2.17% | 2.15% |
| 工具栏 | 7.07% | 6.54% |
| 树表头 | 1.78% | 1.51% |
| 树行区 | 5.07% | 4.76% |
| 时间轴表头 | 1.82% | 1.74% |
| 时间轴行区 | 0.76% | 0.77% |
| 树/时间轴空白区 | 0.00% | 0.00% |
| 内容区合计 | 1.59% | 1.51% |
| 侧栏（shell） | 1.63% | 1.57% |
| 顶栏（shell） | 1.84% | 1.74% |
