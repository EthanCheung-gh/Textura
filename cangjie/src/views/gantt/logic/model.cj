package textura.views.gantt.logic

import std.deriving.*

/**
 * 输入记录与输出几何类型。
 *
 * 本包不依赖 `textura.core.data`：调用方把 `Item` 映射成 `GanttRow`（映射表见
 * docs/GANTT-LOGIC.md），把 `Workspace.items` 映射成 `Array<GanttRow>`，即可使用全部算法。
 * 输出记录不带颜色、字号等表现层信息，只给坐标与文本，直接喂给 Canvas 自绘。
 */

/** 缩放档位（与 TS `GanttZoom` 一致）。 */
@Derive[Equatable]
public enum GanttZoom {
    | Day
    | Week
    | Month
}

/** 缩放的换算参数：每天像素、下层表头列跨度、吸附粒度、适配留白。 */
public struct ZoomConfig {
    public let pxPerDay: Float64
    public let columnDays: Int64
    public let snapDays: Int64
    public let paddingBefore: Int64
    public let paddingAfter: Int64

    public init(
        pxPerDay: Float64,
        columnDays: Int64,
        snapDays: Int64,
        paddingBefore: Int64,
        paddingAfter: Int64
    ) {
        this.pxPerDay = pxPerDay
        this.columnDays = columnDays
        this.snapDays = snapDays
        this.paddingBefore = paddingBefore
        this.paddingAfter = paddingAfter
    }
}

/** TS `ZOOM_CONFIG`：day 40px/天、week 28px/天、month 12px/天，吸附粒度都是 1 天。 */
public func zoomConfig(zoom: GanttZoom): ZoomConfig {
    match (zoom) {
        case GanttZoom.Day => ZoomConfig(40.0, 1, 1, 7, 14)
        case GanttZoom.Week => ZoomConfig(28.0, 7, 1, 14, 28)
        case GanttZoom.Month => ZoomConfig(12.0, 7, 1, 30, 60)
    }
}

/** 拖拽边缘。 */
@Derive[Equatable]
public enum BarEdge {
    | Start
    | End
}

/** 条目种类（镜像 `ItemKind`，本包不依赖 core.data）。 */
@Derive[Equatable]
public enum GanttKind {
    | Objective
    | KeyResult
    | Project
    | Action
    | Sop
    | Step
    | Milestone
    | Note
    | Reference
}

/** 条目状态（镜像 `ItemStatus`）。 */
@Derive[Equatable]
public enum GanttStatus {
    | Inbox
    | Next
    | Active
    | Waiting
    | Scheduled
    | Someday
    | Done
    | Dropped
}

/**
 * 甘特视图的输入行：一条可渲染条目。
 *
 * 字段映射（详见 docs/GANTT-LOGIC.md）：
 * - `id` / `title` ← `Item.id` / `Item.title`
 * - `level` ← `treeDepth(ws, id)`（树的绝对深度，渲染缩进用）
 * - `kind` / `status` ← `Item.kind` / `Item.status`
 * - `startDate` / `endDate` ← `Item.gantt.start` / `Item.gantt.end`（缺 `gantt` 块时为 None）
 * - `progress` ← `Item.gantt.progress`（缺省或非法为 None）
 * - `areaColor` ← 所属 `Area.color` 解析后的色值，本包只透传不解释
 * - `parentId` / `order` / `createdAt` ← 同名 `Item` 字段，用于分组、兄弟排序与稳定次序
 */
public struct GanttRow {
    public let id: String
    public let title: String
    public let kind: GanttKind
    public let level: Int64
    public let startDate: ?String
    public let endDate: ?String
    public let progress: ?Float64
    public let status: GanttStatus
    public let areaColor: String
    public let parentId: ?String
    public let order: Int64
    public let createdAt: String

    public init(
        id: String,
        title: String,
        kind!: GanttKind = GanttKind.Action,
        level!: Int64 = 0,
        startDate!: ?String = None,
        endDate!: ?String = None,
        progress!: ?Float64 = None,
        status!: GanttStatus = GanttStatus.Next,
        areaColor!: String = "",
        parentId!: ?String = None,
        order!: Int64 = 0,
        createdAt!: String = ""
    ) {
        this.id = id
        this.title = title
        this.kind = kind
        this.level = level
        this.startDate = startDate
        this.endDate = endDate
        this.progress = progress
        this.status = status
        this.areaColor = areaColor
        this.parentId = parentId
        this.order = order
        this.createdAt = createdAt
    }
}

/** 含首尾的日期区间（日期键）。 */
@Derive[Equatable]
public struct DateRange {
    public let start: String
    public let end: String

    public init(start: String, end: String) {
        this.start = start
        this.end = end
    }
}

/** 任务条区间（已归一化，`start <= end`）。 */
@Derive[Equatable]
public struct BarRange {
    public let start: String
    public let end: String

    public init(start: String, end: String) {
        this.start = start
        this.end = end
    }
}

/** 任务条的像素几何：`x` 相对时间轴左边界，`width` 至少一天。 */
public struct BarGeometry {
    public let start: String
    public let end: String
    public let x: Float64
    public let width: Float64
    /** 含首尾的天数，最小 1。 */
    public let days: Int64

    public init(start: String, end: String, x: Float64, width: Float64, days: Int64) {
        this.start = start
        this.end = end
        this.x = x
        this.width = width
        this.days = days
    }
}

/** 下层表头列（日 / 周 / 月模式的 7 天段）。 */
public struct TimelineColumn {
    public let key: String
    public let start: String
    public let end: String
    public let x: Float64
    public let width: Float64
    public let label: String
    /** 仅日模式有：星期几（日/一/…）。 */
    public let sublabel: ?String
    public let weekend: Bool
    /** 该列整段早于今天。 */
    public let past: Bool

    public init(
        key: String,
        start: String,
        end: String,
        x: Float64,
        width: Float64,
        label: String,
        sublabel!: ?String = None,
        weekend!: Bool = false,
        past!: Bool = false
    ) {
        this.key = key
        this.start = start
        this.end = end
        this.x = x
        this.width = width
        this.label = label
        this.sublabel = sublabel
        this.weekend = weekend
        this.past = past
    }
}

/** 上层表头分组（月 / 季度），已裁剪到时间轴范围内。 */
public struct HeaderGroup {
    public let key: String
    public let label: String
    public let x: Float64
    public let width: Float64

    public init(key: String, label: String, x: Float64, width: Float64) {
        this.key = key
        this.label = label
        this.x = x
        this.width = width
    }
}

/** 两级表头：`width` 是时间轴总宽（非视口宽）。 */
public struct TimelineHeader {
    public let groups: Array<HeaderGroup>
    public let columns: Array<TimelineColumn>
    public let width: Float64

    public init(groups: Array<HeaderGroup>, columns: Array<TimelineColumn>, width: Float64) {
        this.groups = groups
        this.columns = columns
        this.width = width
    }
}

/** 刻度层级。 */
@Derive[Equatable]
public enum TickKind {
    | Group
    | Column
}

/** 扁平刻度：Canvas 逐 tick 画标签，宽度/星期/是否过去从 `TimelineHeader` 取。 */
public struct Tick {
    public let x: Float64
    public let label: String
    public let kind: TickKind

    public init(x: Float64, label: String, kind: TickKind) {
        this.x = x
        this.label = label
        this.kind = kind
    }
}

/** 折线顶点（设备无关逻辑像素）。 */
@Derive[Equatable]
public struct Point {
    public let x: Float64
    public let y: Float64

    public init(x: Float64, y: Float64) {
        this.x = x
        this.y = y
    }
}

/** 依赖连线的端点矩形：左边缘、右边缘、行中心线。 */
@Derive[Equatable]
public struct DepRect {
    public let x1: Float64
    public let x2: Float64
    public let cy: Float64

    public init(x1: Float64, x2: Float64, cy: Float64) {
        this.x1 = x1
        this.x2 = x2
        this.cy = cy
    }
}

/** 任务条矩形（Canvas 直接 fillRect）。 */
@Derive[Equatable]
public struct BarRect {
    public let x: Float64
    public let y: Float64
    public let w: Float64
    public let h: Float64

    public init(x: Float64, y: Float64, w: Float64, h: Float64) {
        this.x = x
        this.y = y
        this.w = w
        this.h = h
    }
}

/** 半开窗口 `[start, end)`，可直接用于 `slice(start, end)`。 */
@Derive[Equatable]
public struct WindowRange {
    public let start: Int64
    public let end: Int64

    public init(start: Int64, end: Int64) {
        this.start = start
        this.end = end
    }
}

/** 行窗口：`last` 为排他上界，`offsetY` 是第一条可见行相对视口顶部的偏移。 */
@Derive[Equatable]
public struct RowWindow {
    public let first: Int64
    public let last: Int64
    public let offsetY: Float64

    public init(first: Int64, last: Int64, offsetY: Float64) {
        this.first = first
        this.last = last
        this.offsetY = offsetY
    }
}

/** 左侧树的分组行（project / sop / 未分组）。 */
public struct GanttGroupRow {
    public let id: String
    public let title: String
    /** 组内可显示条目数（不含组本身）。 */
    public let count: Int64
    public let start: ?String
    public let end: ?String
    public let progress: Int64
    public let collapsed: Bool
    /** 未分组的合成组没有对应条目。 */
    public let item: ?GanttRow

    public init(
        id: String,
        title: String,
        count: Int64,
        start: ?String,
        end: ?String,
        progress: Int64,
        collapsed: Bool,
        item: ?GanttRow
    ) {
        this.id = id
        this.title = title
        this.count = count
        this.start = start
        this.end = end
        this.progress = progress
        this.collapsed = collapsed
        this.item = item
    }
}

/** 左侧树的条目行。 */
public struct GanttItemRow {
    public let id: String
    public let row: GanttRow
    /** 相对分组的层级（组内直接子项为 1）。 */
    public let depth: Int64
    public let groupId: String

    public init(id: String, row: GanttRow, depth: Int64, groupId: String) {
        this.id = id
        this.row = row
        this.depth = depth
        this.groupId = groupId
    }
}

/** 左侧树的行模型（分组或条目）。 */
public enum GanttTreeRow {
    | Group(GanttGroupRow)
    | Item(GanttItemRow)
}

/** 行 id（分组 id 或条目 id）。 */
public func treeRowId(row: GanttTreeRow): String {
    match (row) {
        case Group(group) => group.id
        case Item(item) => item.id
    }
}

public func isGroupRow(row: GanttTreeRow): Bool {
    match (row) {
        case Group(_) => true
        case Item(_) => false
    }
}

public func groupRowOf(row: GanttTreeRow): ?GanttGroupRow {
    match (row) {
        case Group(group) => Some(group)
        case Item(_) => None
    }
}

public func itemRowOf(row: GanttTreeRow): ?GanttItemRow {
    match (row) {
        case Group(_) => None
        case Item(item) => Some(item)
    }
}
