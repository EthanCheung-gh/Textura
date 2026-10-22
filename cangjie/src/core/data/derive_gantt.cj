package textura.core.data

import std.collection.*
import std.sort.*

/**
 * Gantt view model, ported from `src/modules/gantt/scale.ts`.
 *
 * Only the data/geometry *model* lives here (ranges, snapping, rows,
 * dependencies). Pixel constants (row height, colors) belong to the view and
 * `textura.ui`, so they are intentionally absent.
 */
public enum GanttZoom {
    | Day
    | Week
    | Month

    public operator func ==(right: GanttZoom): Bool {
        ganttZoomWire(this) == ganttZoomWire(right)
    }

    public operator func !=(right: GanttZoom): Bool {
        ganttZoomWire(this) != ganttZoomWire(right)
    }
}

public func ganttZoomWire(zoom: GanttZoom): String {
    match (zoom) {
        case GanttZoom.Day => "day"
        case GanttZoom.Week => "week"
        case GanttZoom.Month => "month"
    }
}

public func parseGanttZoom(value: String): ?GanttZoom {
    match (value) {
        case "day" => Some(GanttZoom.Day)
        case "week" => Some(GanttZoom.Week)
        case "month" => Some(GanttZoom.Month)
        case _ => None
    }
}

public class ZoomConfig {
    /** Days of padding before the earliest bar when fitting the window. */
    public let paddingBefore: Int64
    public let paddingAfter: Int64
    /** Lower header cell span, in days. */
    public let columnDays: Int64

    public init(paddingBefore: Int64, paddingAfter: Int64, columnDays: Int64) {
        this.paddingBefore = paddingBefore
        this.paddingAfter = paddingAfter
        this.columnDays = columnDays
    }
}

/** Padding mirrors `ZOOM_CONFIG` in the Web build (px widths are view-side). */
public func zoomConfig(zoom: GanttZoom): ZoomConfig {
    match (zoom) {
        case GanttZoom.Day => ZoomConfig(7, 14, 1)
        case GanttZoom.Week => ZoomConfig(14, 28, 7)
        case GanttZoom.Month => ZoomConfig(30, 60, 7)
    }
}

/** Synthetic group holding items that belong to no project/SOP group. */
public let UNGROUPED_ID: String = "__ungrouped"

public class BarRange {
    public let start: String
    public let end: String

    public init(start: String, end: String) {
        this.start = start
        this.end = end
    }
}

public func normalizeBar(start: String, end: String): BarRange {
    if (start <= end) {
        BarRange(start, end)
    } else {
        BarRange(end, start)
    }
}

/** Effective bar of an item; a missing side is treated as the same day. */
public func itemRange(item: Item): ?BarRange {
    let start = item.startKey()
    let end = item.dueKey()
    match (start) {
        case None => match (end) {
            case None => None
            case Some(endKey) => Some(normalizeBar(endKey, endKey))
        }
        case Some(startKey) => match (end) {
            case None => Some(normalizeBar(startKey, startKey))
            case Some(endKey) => Some(normalizeBar(startKey, endKey))
        }
    }
}

/**
 * Bar progress shown by the gantt: `done` always reads 100 (toggleDone does not
 * write `gantt.progress`); otherwise the stored value clamped to 0..100.
 */
public func displayProgress(item: Item): Int64 {
    if (item.status == ItemStatus.Done) {
        return 100
    }
    let raw = match (item.gantt) {
        case Some(gantt) => gantt.progress
        case None => 0.0
    }
    if (raw != raw) {
        return 0
    }
    clampInt(roundHalfUp(raw), 0, 100)
}

/** Inclusive days between two keys (`b - a` in calendar days). */
public func diffDaysKey(fromKey: String, toKey: String): Int64 {
    daysBetween(fromKey, toKey)
}

/**
 * Snaps a key to the zoom granularity.
 *
 * `ZOOM_CONFIG.snapDays` is 1 for every zoom in the Web build, so all three
 * modes snap to a whole day; `zoom` stays in the signature because the contract
 * (and future snapping granularities) need it.
 */
public func snapDateKey(key: String, zoom: GanttZoom): String {
    let snapped = match (parseDateKey(Some(key))) {
        case Some(millis) => localDateKey(millis)
        case None => key
    }
    match (zoom) {
        case GanttZoom.Day => snapped
        case GanttZoom.Week => snapped
        case GanttZoom.Month => snapped
    }
}

/**
 * Timeline window:
 * - no dated items: centre on today with zoom padding;
 * - otherwise cover earliest start -> latest end plus padding, always including
 *   today; week mode aligns to Monday, month mode to month edges.
 */
public func buildRange(items: Array<Item>, zoom: GanttZoom, today: String): BarRange {
    let config = zoomConfig(zoom)
    let todayKey = snapDateKey(today, zoom)
    var minimum = todayKey
    var maximum = todayKey
    for (item in items) {
        match (itemRange(item)) {
            case None => ()
            case Some(range) =>
                if (range.start < minimum) {
                    minimum = range.start
                }
                if (range.end > maximum) {
                    maximum = range.end
                }
        }
    }
    var start = addDaysToKey(minimum, -config.paddingBefore)
    var end = addDaysToKey(maximum, config.paddingAfter)
    match (zoom) {
        case GanttZoom.Week =>
            start = startOfWeekKey(start)
            end = endOfWeekKey(end)
        case GanttZoom.Month =>
            start = startOfMonthKey(start)
            end = endOfMonthKey(end)
        case GanttZoom.Day => ()
    }
    BarRange(start, end)
}

/** Kinds the gantt can show. */
public let GANTTABLE_KINDS: Array<ItemKind> = [ItemKind.Project, ItemKind.Action, ItemKind.Milestone]

func isHiddenStatus(status: ItemStatus): Bool {
    status == ItemStatus.Inbox || status == ItemStatus.Someday || status == ItemStatus.Dropped
}

func isGanttableKind(kind: ItemKind): Bool {
    for (candidate in GANTTABLE_KINDS) {
        if (candidate == kind) {
            return true
        }
    }
    false
}

/** Shown in the gantt: project/action/milestone, not inbox/someday/dropped. */
public func isGanttableItem(item: Item): Bool {
    if (!isGanttableKind(item.kind)) {
        return false
    }
    !isHiddenStatus(item.status)
}

func isGroupRoot(item: Item): Bool {
    match (item.parentId) {
        case Some(_) => false
        case None =>
            (item.kind == ItemKind.Project || item.kind == ItemKind.Sop) && !isHiddenStatus(item.status)
    }
}

/** In-group order: dated first by start, undated last, then order/createdAt. */
func compareGanttItems(left: Item, right: Item): Int64 {
    let leftStart: ?String = match (itemRange(left)) {
        case Some(range) => Some(range.start)
        case None => None
    }
    let rightStart: ?String = match (itemRange(right)) {
        case Some(range) => Some(range.start)
        case None => None
    }
    match (leftStart) {
        case Some(leftKey) => match (rightStart) {
            case Some(rightKey) => if (leftKey != rightKey) {
                if (leftKey < rightKey) {
                    return -1
                }
                return 1
            }
            case None => return -1
        }
        case None => match (rightStart) {
            case Some(_) => return 1
            case None => ()
        }
    }
    if (left.order != right.order) {
        if (left.order < right.order) {
            return -1
        }
        return 1
    }
    compareText(left.createdAt, right.createdAt)
}

class RangeSummary {
    let start: ?String
    let end: ?String

    init(start: ?String, end: ?String) {
        this.start = start
        this.end = end
    }
}

func summarizeRanges(items: Array<Item>): RangeSummary {
    var start: ?String = None
    var end: ?String = None
    for (item in items) {
        match (itemRange(item)) {
            case None => ()
            case Some(range) =>
                start = match (start) {
                    case Some(current) => if (range.start < current) {
                        Some(range.start)
                    } else {
                        Some(current)
                    }
                    case None => Some(range.start)
                }
                end = match (end) {
                    case Some(current) => if (range.end > current) {
                        Some(range.end)
                    } else {
                        Some(current)
                    }
                    case None => Some(range.end)
                }
        }
    }
    RangeSummary(start, end)
}

public enum GanttRowKind {
    | Group
    | Item

    public operator func ==(right: GanttRowKind): Bool {
        ganttRowKindWire(this) == ganttRowKindWire(right)
    }

    public operator func !=(right: GanttRowKind): Bool {
        ganttRowKindWire(this) != ganttRowKindWire(right)
    }
}

public func ganttRowKindWire(kind: GanttRowKind): String {
    match (kind) {
        case GanttRowKind.Group => "group"
        case GanttRowKind.Item => "item"
    }
}

/** One row of the left tree. Group rows use `count`; item rows use `depth`. */
public class GanttRow {
    public let kind: GanttRowKind
    public let id: String
    public let title: String
    public let item: ?Item
    public let depth: Int64
    public let groupId: String
    public let count: Int64
    public let start: ?String
    public let end: ?String
    public let progress: Int64
    public let collapsed: Bool

    public init(
        kind: GanttRowKind,
        id: String,
        title: String,
        item: ?Item,
        depth: Int64,
        groupId: String,
        count: Int64,
        start: ?String,
        end: ?String,
        progress: Int64,
        collapsed: Bool
    ) {
        this.kind = kind
        this.id = id
        this.title = title
        this.item = item
        this.depth = depth
        this.groupId = groupId
        this.count = count
        this.start = start
        this.end = end
        this.progress = progress
        this.collapsed = collapsed
    }

    public func isGroup(): Bool {
        kind == GanttRowKind.Group
    }
}

class GanttGroupSeed {
    let root: Item
    let members: Array<Item>
    let hasDates: Bool

    init(root: Item, members: Array<Item>, hasDates: Bool) {
        this.root = root
        this.members = members
        this.hasDates = hasDates
    }
}

/**
 * Left-side row model:
 * - top-level projects/SOPs become collapsible groups;
 * - members are start-sorted with undated last;
 * - root items outside any group land in "未分组" (always last);
 * - collapsed groups emit only the group row.
 */
public func buildGanttRows(workspace: Workspace, collapsed: HashMap<String, Bool>): Array<GanttRow> {
    let seeds = ArrayList<GanttGroupSeed>()
    for (item in workspace.items) {
        if (!isGroupRoot(item)) {
            continue
        }
        let members = ArrayList<Item>()
        for (descendant in descendantsOf(workspace, item.id)) {
            if (isGanttableItem(descendant)) {
                members.add(descendant)
            }
        }
        var hasDates = itemRange(item).isSome()
        for (member in members) {
            if (itemRange(member).isSome()) {
                hasDates = true
            }
        }
        if (!members.isEmpty() || itemRange(item).isSome()) {
            seeds.add(GanttGroupSeed(item, members.toArray(), hasDates))
        }
    }
    let ordered = seeds.toArray()
    sort<GanttGroupSeed>(
        ordered,
        lessThan: {left, right =>
            if (left.hasDates != right.hasDates) {
                return left.hasDates
            }
            if (left.root.order != right.root.order) {
                return left.root.order < right.root.order
            }
            left.root.createdAt < right.root.createdAt
        }
    )

    let rows = ArrayList<GanttRow>()
    let covered = HashMap<String, Bool>()
    for (seed in ordered) {
        covered[seed.root.id] = true
        for (member in seed.members) {
            covered[member.id] = true
        }
        let isCollapsed = collapsed.get(seed.root.id).isSome()
        let combined = ArrayList<Item>()
        combined.add(seed.root)
        for (member in seed.members) {
            combined.add(member)
        }
        let summary = summarizeRanges(combined.toArray())
        rows.add(GanttRow(
            GanttRowKind.Group,
            seed.root.id,
            seed.root.title,
            Some(seed.root),
            0,
            seed.root.id,
            seed.members.size,
            summary.start,
            summary.end,
            rollupProgress(workspace, seed.root.id),
            isCollapsed
        ))
        if (isCollapsed) {
            continue
        }
        let rootDepth = treeDepth(workspace, seed.root.id)
        let members = ArrayList<Item>()
        for (member in seed.members) {
            members.add(member)
        }
        let sortedMembers = members.toArray()
        sort<Item>(sortedMembers, lessThan: {left, right => compareGanttItems(left, right) < 0})
        for (member in sortedMembers) {
            let memberDepth = treeDepth(workspace, member.id) - rootDepth
            rows.add(GanttRow(
                GanttRowKind.Item,
                member.id,
                member.title,
                Some(member),
                if (memberDepth < 1) {
                    1
                } else {
                    memberDepth
                },
                seed.root.id,
                0,
                None,
                None,
                displayProgress(member),
                false
            ))
        }
    }

    let groupIds = HashMap<String, Bool>()
    for (seed in ordered) {
        groupIds[seed.root.id] = true
    }
    let ungrouped = ArrayList<Item>()
    for (item in workspace.items) {
        if (!isGanttableItem(item)) {
            continue
        }
        match (covered.get(item.id)) {
            case Some(_) => continue
            case None => ()
        }
        var belongsToGroup = false
        for (ancestor in ancestorsOf(workspace, item.id)) {
            match (groupIds.get(ancestor.id)) {
                case Some(_) =>
                    belongsToGroup = true
                    break
                case None => ()
            }
        }
        if (!belongsToGroup) {
            ungrouped.add(item)
        }
    }
    let ungroupedArray = ungrouped.toArray()
    sort<Item>(ungroupedArray, lessThan: {left, right => compareGanttItems(left, right) < 0})
    if (!ungroupedArray.isEmpty()) {
        let summary = summarizeRanges(ungroupedArray)
        var progressSum = 0
        for (item in ungroupedArray) {
            progressSum += displayProgress(item)
        }
        let progress = roundHalfUp(Float64(progressSum) / Float64(ungroupedArray.size))
        let ungroupedCollapsed = collapsed.get(UNGROUPED_ID).isSome()
        rows.add(GanttRow(
            GanttRowKind.Group,
            UNGROUPED_ID,
            "未分组",
            None,
            0,
            UNGROUPED_ID,
            ungroupedArray.size,
            summary.start,
            summary.end,
            progress,
            ungroupedCollapsed
        ))
        if (!ungroupedCollapsed) {
            for (item in ungroupedArray) {
                let depth = treeDepth(workspace, item.id)
                rows.add(GanttRow(
                    GanttRowKind.Item,
                    item.id,
                    item.title,
                    Some(item),
                    if (depth < 1) {
                        1
                    } else {
                        depth
                    },
                    UNGROUPED_ID,
                    0,
                    None,
                    None,
                    displayProgress(item),
                    false
                ))
            }
        }
    }
    rows.toArray()
}

/** Every `depends` edge (the gantt draws one arrow per entry). */
public func dependencyEdges(workspace: Workspace): Array<Edge> {
    let result = ArrayList<Edge>()
    for (edge in workspace.edges) {
        if (edge.edgeType == EdgeType.Depends) {
            result.add(edge)
        }
    }
    result.toArray()
}
