package textura.views.gantt.logic

import std.collection.*
import std.sort.*

/**
 * 左侧树 / 分组行模型。语义对齐 TS `buildRows`：
 * - 顶层 project / sop 成为可折叠分组；
 * - 组内条目按 start 升序、无日期在后，再按 order / createdAt；
 * - 根级无分组归属的条目进「未分组」，始终排最后；
 * - `collapsed` 中的分组只输出组头行。
 */
func isHiddenStatus(status: GanttStatus): Bool {
    match (status) {
        case GanttStatus.Inbox | GanttStatus.Someday | GanttStatus.Dropped => true
        case _ => false
    }
}

func isDoneStatus(status: GanttStatus): Bool {
    match (status) {
        case GanttStatus.Done => true
        case _ => false
    }
}

/** 甘特视图里可出现的条目：项目 / 行动 / 里程碑，且不在收件箱、将来、已放弃。 */
public func isGanttable(row: GanttRow): Bool {
    let kindOk = match (row.kind) {
        case GanttKind.Project | GanttKind.Action | GanttKind.Milestone => true
        case _ => false
    }
    kindOk && !isHiddenStatus(row.status)
}

func isGroupRoot(row: GanttRow): Bool {
    if (row.parentId.isSome()) {
        return false
    }
    let kindOk = match (row.kind) {
        case GanttKind.Project | GanttKind.Sop => true
        case _ => false
    }
    kindOk && !isHiddenStatus(row.status)
}

/** 行索引：`byId`、父子邻接表（保持输入顺序，等价于 TS `getWorkspaceIndex`）。 */
class RowIndex {
    let byId: HashMap<String, GanttRow>
    let children: HashMap<String, ArrayList<GanttRow>>
    let rows: Array<GanttRow>

    init(rows: Array<GanttRow>) {
        this.rows = rows
        this.byId = HashMap<String, GanttRow>()
        this.children = HashMap<String, ArrayList<GanttRow>>()
        for (row in rows) {
            this.byId.add(row.id, row)
            match (row.parentId) {
                case Some(parent) => match (this.children.get(parent)) {
                    case Some(list) => list.add(row)
                    case None =>
                        let list = ArrayList<GanttRow>()
                        list.add(row)
                        this.children.add(parent, list)
                }
                case None => ()
            }
        }
    }
}

func appendDescendants(index: RowIndex, parentId: String, visited: HashSet<String>, into: ArrayList<GanttRow>): Unit {
    match (index.children.get(parentId)) {
        case Some(children) => for (child in children) {
            if (visited.contains(child.id)) {
                continue
            }
            visited.add(child.id)
            into.add(child)
            appendDescendants(index, child.id, visited, into)
        }
        case None => ()
    }
}

/** 全部后代（任意深度，深度优先，保持输入顺序）。 */
func descendantsOf(index: RowIndex, id: String): Array<GanttRow> {
    let result = ArrayList<GanttRow>()
    let visited = HashSet<String>()
    visited.add(id)
    appendDescendants(index, id, visited, result)
    result.toArray()
}

/** 祖先链（最近优先），带环保护。 */
func ancestorsOf(index: RowIndex, id: String): Array<GanttRow> {
    let result = ArrayList<GanttRow>()
    let seen = HashSet<String>()
    seen.add(id)
    var current: ?String = match (index.byId.get(id)) {
        case Some(row) => row.parentId
        case None => None
    }
    var more = true
    while (more) {
        match (current) {
            case Some(parentId) =>
                if (seen.contains(parentId)) {
                    more = false
                } else {
                    seen.add(parentId)
                    match (index.byId.get(parentId)) {
                        case Some(parent) =>
                            result.add(parent)
                            current = parent.parentId
                        case None => more = false
                    }
                }
            case None => more = false
        }
    }
    result.toArray()
}

/** 树的绝对深度（根为 0），等价于 TS `treeDepth`。 */
public func rowDepth(rows: Array<GanttRow>, id: String): Int64 {
    let index = RowIndex(rows)
    ancestorsOf(index, id).size
}

func treeDepth(index: RowIndex, id: String): Int64 {
    ancestorsOf(index, id).size
}

/** 组内排序：有 start 的在前并按升序；无日期在后；再按 order / createdAt。 */
func compareRows(a: GanttRow, b: GanttRow): Int64 {
    let aStart: ?String = match (itemRange(a)) {
        case Some(range) => Some(range.start)
        case None => None
    }
    let bStart: ?String = match (itemRange(b)) {
        case Some(range) => Some(range.start)
        case None => None
    }
    if (aStart.isSome() && bStart.isSome()) {
        let from = aStart.getOrThrow()
        let to = bStart.getOrThrow()
        if (from < to) {
            return -1
        }
        if (from > to) {
            return 1
        }
    } else if (aStart.isSome() && bStart.isNone()) {
        return -1
    } else if (aStart.isNone() && bStart.isSome()) {
        return 1
    }
    if (a.order != b.order) {
        return if (a.order < b.order) {
            -1
        } else {
            1
        }
    }
    if (a.createdAt < b.createdAt) {
        -1
    } else if (a.createdAt > b.createdAt) {
        1
    } else {
        0
    }
}

func sortRows(rows: ArrayList<GanttRow>): Unit {
    sort(rows, lessThan: {a: GanttRow, b: GanttRow => compareRows(a, b) < 0}, stable: true)
}

/** 区间汇总。 */
struct Summary {
    let start: ?String
    let end: ?String

    init(start: ?String, end: ?String) {
        this.start = start
        this.end = end
    }
}

func summarizeOf(primary: ArrayList<GanttRow>): Summary {
    var start: ?String = None
    var end: ?String = None
    for (row in primary) {
        match (itemRange(row)) {
            case Some(range) =>
                match (start) {
                    case Some(current) =>
                        if (range.start < current) {
                            start = Some(range.start)
                        }
                    case None => start = Some(range.start)
                }
                match (end) {
                    case Some(current) =>
                        if (range.end > current) {
                            end = Some(range.end)
                        }
                    case None => end = Some(range.end)
                }
            case None => ()
        }
    }
    Summary(start, end)
}

/** 子项完成比（done / 总数 * 100）；无子项为 0。 */
func completionOf(index: RowIndex, id: String): Float64 {
    let children = match (index.children.get(id)) {
        case Some(list) => list
        case None => ArrayList<GanttRow>()
    }
    if (children.size == 0) {
        return 0.0
    }
    var done = 0
    for (child in children) {
        if (isDoneStatus(child.status)) {
            done += 1
        }
    }
    Float64(done) / Float64(children.size) * 100.0
}

/** 汇总进度 0..100：project / sop 取子项完成比，其余 done?100:0。 */
func rollupProgress(index: RowIndex, row: GanttRow): Int64 {
    let value = match (row.kind) {
        case GanttKind.Project | GanttKind.Sop => completionOf(index, row.id)
        case _ =>
            if (isDoneStatus(row.status)) {
                100.0
            } else {
                0.0
            }
    }
    clampInt(tsRoundInt(value), 0, 100)
}

/** 分组建模的中间结果。 */
class GroupPlan {
    let root: GanttRow
    let members: Array<GanttRow>
    let hasDates: Bool

    init(root: GanttRow, members: Array<GanttRow>, hasDates: Bool) {
        this.root = root
        this.members = members
        this.hasDates = hasDates
    }
}

public func buildRows(rows: Array<GanttRow>): Array<GanttTreeRow> {
    buildRows(rows, HashSet<String>())
}

/**
 * 构建左侧行模型。
 *
 * @param rows 全部候选条目（未过滤；本函数自行套用 `isGanttable`）
 * @param collapsed 折叠中的分组 id（含 `UNGROUPED_ID`）
 */
public func buildRows(rows: Array<GanttRow>, collapsed: HashSet<String>): Array<GanttTreeRow> {
    let index = RowIndex(rows)
    let plans = ArrayList<GroupPlan>()

    for (root in rows) {
        if (!isGroupRoot(root)) {
            continue
        }
        let members = ArrayList<GanttRow>()
        for (candidate in descendantsOf(index, root.id)) {
            if (isGanttable(candidate)) {
                members.add(candidate)
            }
        }
        let memberArray = members.toArray()
        let withDates = ArrayList<GanttRow>()
        withDates.add(root)
        for (member in memberArray) {
            withDates.add(member)
        }
        var hasDates = false
        for (candidate in withDates) {
            if (itemRange(candidate).isSome()) {
                hasDates = true
                break
            }
        }
        let kept = memberArray.size > 0 || itemRange(root).isSome()
        if (kept) {
            plans.add(GroupPlan(root, memberArray, hasDates))
        }
    }

    sort(
        plans,
        lessThan: {
            a: GroupPlan, b: GroupPlan => if (a.hasDates != b.hasDates) {
                a.hasDates
            } else if (a.root.order != b.root.order) {
                a.root.order < b.root.order
            } else {
                a.root.createdAt < b.root.createdAt
            }
        },
        stable: true
    )

    let result = ArrayList<GanttTreeRow>()
    let covered = HashSet<String>()

    for (plan in plans) {
        covered.add(plan.root.id)
        for (member in plan.members) {
            covered.add(member.id)
        }

        let isCollapsed = collapsed.contains(plan.root.id)
        let summaryRows = ArrayList<GanttRow>()
        summaryRows.add(plan.root)
        for (member in plan.members) {
            summaryRows.add(member)
        }
        let summary = summarizeOf(summaryRows)
        result.add(
            GanttTreeRow.Group(
                GanttGroupRow(
                    plan.root.id,
                    plan.root.title,
                    plan.members.size,
                    summary.start,
                    summary.end,
                    rollupProgress(index, plan.root),
                    isCollapsed,
                    Some(plan.root)
                )
            )
        )

        if (isCollapsed) {
            continue
        }
        let rootDepth = treeDepth(index, plan.root.id)
        let sortedMembers = ArrayList<GanttRow>(plan.members)
        sortRows(sortedMembers)
        for (member in sortedMembers) {
            result.add(
                GanttTreeRow.Item(
                    GanttItemRow(
                        member.id,
                        member,
                        maxInt(1, treeDepth(index, member.id) - rootDepth),
                        plan.root.id
                    )
                )
            )
        }
    }

    // 未分组：不属于任何已展示分组的可排期条目（例如直接挂在 OKR 下的行动）。
    let groupIds = HashSet<String>()
    for (plan in plans) {
        groupIds.add(plan.root.id)
    }
    let ungrouped = ArrayList<GanttRow>()
    for (row in rows) {
        if (!isGanttable(row) || covered.contains(row.id)) {
            continue
        }
        var belongsToGroup = false
        for (ancestor in ancestorsOf(index, row.id)) {
            if (groupIds.contains(ancestor.id)) {
                belongsToGroup = true
                break
            }
        }
        if (!belongsToGroup) {
            ungrouped.add(row)
        }
    }
    sortRows(ungrouped)

    if (ungrouped.size > 0) {
        let summary = summarizeOf(ungrouped)
        var total = 0.0
        for (row in ungrouped) {
            total += Float64(displayProgress(row))
        }
        let progress = tsRoundInt(total / Float64(ungrouped.size))
        let ungroupedCollapsed = collapsed.contains(UNGROUPED_ID)
        result.add(
            GanttTreeRow.Group(
                GanttGroupRow(
                    UNGROUPED_ID,
                    "未分组",
                    ungrouped.size,
                    summary.start,
                    summary.end,
                    progress,
                    ungroupedCollapsed,
                    None
                )
            )
        )
        if (!ungroupedCollapsed) {
            for (row in ungrouped) {
                result.add(GanttTreeRow.Item(GanttItemRow(row.id, row, maxInt(1, treeDepth(index, row.id)), UNGROUPED_ID)))
            }
        }
    }

    result.toArray()
}
