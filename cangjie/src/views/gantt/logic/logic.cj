package textura.views.gantt.logic

/**
 * 甘特纯函数层：日期 ↔ 像素、刻度/表头、虚拟化窗口、任务条几何、依赖折线。
 *
 * 本包是 `textura.views.gantt` 的子包，只做几何与刻度计算：
 * - 不 import `cui`，不 import `textura.core.data`（输入是自定义记录 `GanttRow`）；
 * - 所有函数都是纯函数，输出可直接喂给 Canvas 自绘；
 * - 语义对齐 Web 版 `src/modules/gantt/scale.ts` / `virtual.ts`（见 docs/GANTT-LOGIC.md）。
 */

/** 几何契约版本；输出字段形状改变时自增。 */
public let GANTT_LOGIC_VERSION: Int64 = 1

/** 行高（左侧树与右侧条区共用）：`ROW_HEIGHT`。 */
public let ROW_HEIGHT: Float64 = 36.0

/** 两级表头总高度：`HEADER_HEIGHT`。 */
public let HEADER_HEIGHT: Float64 = 52.0

/** 任务条高度（gantt.css `.gantt-bar`）。 */
public let BAR_HEIGHT: Float64 = 22.0

/** 任务条相对行顶的偏移（GanttTimeline 的 `rowIndex * ROW_HEIGHT + 7`）。 */
public let BAR_TOP_OFFSET: Float64 = 7.0

/** 里程碑菱形的宽度（GanttBar 的 `isMilestone ? 16 : geometry.width`）。 */
public let MILESTONE_WIDTH: Float64 = 16.0

/** 无父级、且不属于任何 project/sop 分组的条目所用的合成分组 id。 */
public let UNGROUPED_ID: String = "__ungrouped"
