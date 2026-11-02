package textura.views.gantt

import textura.views.gantt.logic.*

/*
 * 甘特视图的布局与字号常量。数值全部来自 Web 版（只读参照）：
 * - `src/modules/gantt/gantt.css` 的盒模型与 font-size；
 * - `src/modules/gantt` 下的各 `.tsx` 里的内联尺寸（如 `rowIndex * ROW_HEIGHT + 7`）。
 * 行高/表头/条高等与 algorithm 层共享的量直接取 `logic` 包常量（logic.cj）。
 */

/** `logic.HEADER_HEIGHT`（52）的 Float32 视图：自绘坐标一律 Float32。 */
let HEADER_H: Float32 = Float32(HEADER_HEIGHT)

/** `logic.ROW_HEIGHT`（36）的 Float32 视图。 */
let ROW_H: Float32 = Float32(ROW_HEIGHT)

/** `logic.BAR_TOP_OFFSET`（7）的 Float32 视图。 */
let BAR_TOP: Float32 = Float32(BAR_TOP_OFFSET)

/** `logic.BAR_HEIGHT`（22）的 Float32 视图。 */
let BAR_H: Float32 = Float32(BAR_HEIGHT)

/** `.page.gantt-page { gap: var(--space-3) }`（gantt.css:11）。 */
let PAGE_GAP: Float32 = 12.0

/** 页头高度：h1 行盒 33（22px × 1.5）+ gap 4 + p 行盒 19.5（13px × 1.5）≈ 57（实测 y80..136）。 */
let PAGE_HEADER_HEIGHT: Float32 = 57.0
let PAGE_TITLE_SIZE: Float32 = 22.0
let PAGE_TITLE_LINE_HEIGHT: Float32 = 33.0
let PAGE_HEADER_GAP: Float32 = 4.0
let PAGE_SUBTITLE_SIZE: Float32 = 13.0
let PAGE_SUBTITLE_LINE_HEIGHT: Float32 = 19.5

/** `.gantt-toolbar`：8 + 30 + 8 + 2×1 = 48（gantt.css:15-27）。 */
let TOOLBAR_HEIGHT: Float32 = 48.0
let TOOLBAR_BORDER: Float32 = 1.0
let TOOLBAR_RANGE_SIZE: Float32 = 12.5
let TOOLBAR_COUNT_SIZE: Float32 = 11.5

/** `.gantt-body { border-radius: var(--radius-lg) }`（gantt.css:59-68）。 */
let BODY_RADIUS: Float32 = 14.0

/** `.gantt-tree { width: 272px }`（gantt.css:71-79），含右侧 1px 描边。 */
let TREE_WIDTH: Float32 = 272.0

/** `.gantt-inspector { width: 320px }`（gantt.css:807-815），含左侧 1px 描边。 */
let INSPECTOR_WIDTH: Float32 = 320.0

/** `.gantt-tree-head { font-size: 11px; font-weight: 600 }`（gantt.css:81-98）。 */
let TREE_HEAD_SIZE: Float32 = 11.0

/** `.gantt-group-title { 12.5px; 620 }` / `.gantt-group-meta { 10.5px }`（gantt.css:186-218）。 */
let GROUP_TITLE_SIZE: Float32 = 12.5
let GROUP_META_SIZE: Float32 = 10.5
let GROUP_COUNT_SIZE: Float32 = 10.0

/**
 * 分组两行文本的行盒中心（相对行顶）：
 * `.gantt-group-main { padding-top: 3px; padding-bottom: 4px; line-height: 1.15 }`
 * → 内容高 12.5×1.15 + 10.5×1.15 = 26.45，整体在 36 行里居中（起点 4.77），
 * 标题行盒中心 4.77+3+7.19 = 11.46，meta 行盒中心 4.77+3+14.375+6.04 = 24.7。
 */
let GROUP_TITLE_CENTER: Float32 = 11.46
let GROUP_META_CENTER: Float32 = 24.7

/** `.gantt-tree-row { font-size: 13px }` / `.gantt-item-progress { 10.5px }`（gantt.css:123-284）。 */
let TREE_ITEM_SIZE: Float32 = 13.0
let ITEM_TITLE_SIZE: Float32 = 13.0
let ITEM_PROGRESS_SIZE: Float32 = 10.5
let ITEM_OVERDUE_SIZE: Float32 = 10.0
let ITEM_SCHEDULE_SIZE: Float32 = 10.5

/** `.gantt-bar { height: 22px; border-radius: 5px }`（gantt.css:530-545）。 */
let BAR_RADIUS: Float32 = 5.0

/** `.gantt-bar-handle { width: 7px }`（gantt.css:612-619）——左右边缘的拖拽热区。 */
let BAR_HANDLE_WIDTH: Float32 = 7.0

/** `.gantt-bar-label { font-size: 11.5px }`（gantt.css:596-606）。 */
let BAR_LABEL_SIZE: Float32 = 11.5

/** `.gantt-header-group { font-size: 11.5px; 600 }`（gantt.css:380-393）。 */
let HEADER_GROUP_SIZE: Float32 = 11.5

/** `.gantt-header-col { font-size: 10.5px }` / `-sub { 9.5px }`（gantt.css:406-433）。 */
let HEADER_COLUMN_SIZE: Float32 = 10.5
let HEADER_SUBLABEL_SIZE: Float32 = 9.5

/** `.gantt-today-pill { font-size: 9.5px; 600 }`（gantt.css:446-458）。 */
let TODAY_PILL_SIZE: Float32 = 9.5

/** `.gantt-drag-tip { font-size: 11px }`（gantt.css:765-779）。 */
let DRAG_TIP_SIZE: Float32 = 11.0
