package textura.views.gantt

import std.collection.*
import textura.core.data as data
import textura.views.gantt.logic.*

/*
 * `core.data.Item` → `logic.GanttRow` 投影（映射表见 docs/GANTT-LOGIC.md §3）。
 * logic 包不认识 `core.data`，这一层是唯一的转换点；不复制业务事实，只做取值与枚举翻译。
 */

func kindOf(kind: data.ItemKind): GanttKind {
    match (kind) {
        case data.ItemKind.Objective => GanttKind.Objective
        case data.ItemKind.KeyResult => GanttKind.KeyResult
        case data.ItemKind.Project => GanttKind.Project
        case data.ItemKind.Action => GanttKind.Action
        case data.ItemKind.Sop => GanttKind.Sop
        case data.ItemKind.Step => GanttKind.Step
        case data.ItemKind.Milestone => GanttKind.Milestone
        case data.ItemKind.Note => GanttKind.Note
        case data.ItemKind.Reference => GanttKind.Reference
    }
}

func statusOf(status: data.ItemStatus): GanttStatus {
    match (status) {
        case data.ItemStatus.Inbox => GanttStatus.Inbox
        case data.ItemStatus.Next => GanttStatus.Next
        case data.ItemStatus.Active => GanttStatus.Active
        case data.ItemStatus.Waiting => GanttStatus.Waiting
        case data.ItemStatus.Scheduled => GanttStatus.Scheduled
        case data.ItemStatus.Someday => GanttStatus.Someday
        case data.ItemStatus.Done => GanttStatus.Done
        case data.ItemStatus.Dropped => GanttStatus.Dropped
    }
}

/** 领域色：`Area.color` 原样透传（logic 只转交，不解释）。 */
func areaColorOf(workspace: data.Workspace, areaId: ?String): String {
    match (areaId) {
        case Some(id) => match (data.areaById(workspace, id)) {
            case Some(area) => area.color
            case None => ""
        }
        case None => ""
    }
}

func toGanttRow(workspace: data.Workspace, item: data.Item, depth: Int64): GanttRow {
    var start: ?String = None
    var end: ?String = None
    var progress: ?Float64 = None
    match (item.gantt) {
        case Some(gantt) =>
            start = gantt.start
            end = gantt.end
            progress = Some(gantt.progress)
        case None => ()
    }
    GanttRow(
        item.id,
        item.title,
        kind: kindOf(item.kind),
        level: depth,
        startDate: start,
        endDate: end,
        progress: progress,
        status: statusOf(item.status),
        areaColor: areaColorOf(workspace, item.areaId),
        parentId: item.parentId,
        order: item.order,
        createdAt: item.createdAt
    )
}

/** 全部条目的投影（`buildRows` 自己会套用 `isGanttable`，这里不过滤）。 */
func toGanttRows(workspace: data.Workspace): Array<GanttRow> {
    let rows = ArrayList<GanttRow>()
    for (item in workspace.items) {
        rows.add(toGanttRow(workspace, item, data.treeDepth(workspace, item.id)))
    }
    rows.toArray()
}

/** 可排期条目（`isGanttable`）：时间轴范围、计数与依赖连线都基于这一批。 */
func ganttableRows(rows: Array<GanttRow>): Array<GanttRow> {
    let result = ArrayList<GanttRow>()
    for (row in rows) {
        if (isGanttable(row)) {
            result.add(row)
        }
    }
    result.toArray()
}

/** 已排期条目数（`GanttPage.tsx` `scheduledCount`）。 */
func scheduledCount(rows: Array<GanttRow>): Int64 {
    var count = 0
    for (row in rows) {
        if (isGanttable(row) && itemRange(row).isSome()) {
            count += 1
        }
    }
    count
}

/** 最早开始日期（「适配窗口」与首次进入的滚动锚点）。 */
func earliestStart(rows: Array<GanttRow>): ?String {
    var earliest: ?String = None
    for (row in rows) {
        match (itemRange(row)) {
            case Some(range) => match (earliest) {
                case Some(current) =>
                    if (range.start < current) {
                        earliest = Some(range.start)
                    }
                case None => earliest = Some(range.start)
            }
            case None => ()
        }
    }
    earliest
}

/** UI 状态里的缩放 wire 值 → `GanttZoom`（`UiState.ganttZoom`，Web 默认 "week"）。 */
func zoomFromWire(value: String): GanttZoom {
    match (value) {
        case "day" => GanttZoom.Day
        case "month" => GanttZoom.Month
        case _ => GanttZoom.Week
    }
}

func zoomWire(zoom: GanttZoom): String {
    match (zoom) {
        case GanttZoom.Day => "day"
        case GanttZoom.Week => "week"
        case GanttZoom.Month => "month"
    }
}

/** 缩放档位在 Segmented 里的下标（日 / 周 / 月，GanttToolbar.tsx `ZOOM_OPTIONS`）。 */
func zoomIndex(zoom: GanttZoom): Int64 {
    match (zoom) {
        case GanttZoom.Day => 0
        case GanttZoom.Week => 1
        case GanttZoom.Month => 2
    }
}

func zoomOfIndex(index: Int64): GanttZoom {
    match (index) {
        case 0 => GanttZoom.Day
        case 2 => GanttZoom.Month
        case _ => GanttZoom.Week
    }
}

/** 显式空值：Cangjie 在部分上下文无法从字面量 `None` 推断枚举实参类型。 */
func noKey(): ?String {
    None
}

func noItem(): ?data.Item {
    None
}

/** `formatDateKey(key, 'M/d')`（core/utils.ts）。 */
func monthDay(key: ?String): String {
    data.formatDateKey(key, pattern: "M/d")
}

/** `M/d–M/d` 或 `未排期`（GanttTree.tsx 分组/任务条 meta）。 */
func rangeLabelOf(start: ?String, end: ?String): String {
    match (start) {
        case Some(from) => match (end) {
            case Some(to) => "${monthDay(Some(from))}–${monthDay(Some(to))}"
            case None => monthDay(Some(from))
        }
        case None => "未排期"
    }
}
