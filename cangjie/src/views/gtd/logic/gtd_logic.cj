package textura.views.gtd.logic

import std.collection.*
import std.unicode.*
import std.deriving.*
import std.sort.*

/*
 * GTD 纯函数层：收件箱排序、场景分组、下一步排序、分页、面包屑索引、
 * 等待天数、停滞项目、周回顾指标与展示辅助。
 *
 * 全部是纯函数：不改输入、不读时钟、不碰 store。语义与
 * `src/modules/gtd/gtdLogic.ts` 一一对应（差异清单见 docs/GTD-LOGIC.md）。
 */

/** 无场景桶的展示名。 */
public let NO_CONTEXT: String = "无场景"
/** 筛选器里表示「无场景」的哨兵值，避免与用户自定义场景重名。 */
public let NO_CONTEXT_FILTER: String = "__none__"
/** 预设场景；分组顺序固定按此顺序。 */
public let PRESET_CONTEXTS: Array<String> = ["电脑", "电话", "外出", "会议", "深度工作"]
/** 等待超过该天数（严格大于）才需要催办。 */
public let WAITING_WARN_DAYS: Int64 = 7
/** 澄清表单里的时长选项（仅用于 2 分钟规则提示）。 */
public let ESTIMATE_OPTIONS: Array<Int64> = [2, 15, 30, 60, 120]
/** 列表首屏渲染条数；超过后由「显示更多」按页追加。 */
public let LIST_PAGE_SIZE: Int64 = 100

/** 能量档位的中文标签。 */
public func energyLabel(energy: Energy): String {
    match (energy) {
        case Energy.Low => "低"
        case Energy.Medium => "中"
        case Energy.High => "高"
    }
}

/* ------------------------------------------------------------------ */
/* 工作区索引（一次构建，多次复用；与 core.selectors 的索引语义一致）   */
/* ------------------------------------------------------------------ */

let ROOT_KEY: String = "\u{0}root"

func compareStrings(left: String, right: String): Int64 {
    if (left < right) {
        -1
    } else if (left > right) {
        1
    } else {
        0
    }
}

/** TS 的 `compareItems`：order 升序，其次 createdAt 升序。 */
func compareTreeRank(left: GtdItem, right: GtdItem): Int64 {
    if (left.order != right.order) {
        return if (left.order < right.order) {
            -1
        } else {
            1
        }
    }
    compareStrings(left.createdAt, right.createdAt)
}

func sortCopy<T>(items: Array<T>, cmp: (T, T) -> Int64): Array<T> {
    let buffer = ArrayList<T>()
    for (item in items) {
        buffer.add(item)
    }
    let output = buffer.toArray()
    sort(output, lessThan: {left, right => cmp(left, right) < 0}, stable: true)
    output
}

func sortByTreeRank(items: Array<GtdItem>): Array<GtdItem> {
    sortCopy(items, compareTreeRank)
}

class WorkspaceIndex {
    let source: GtdWorkspace
    let byId = HashMap<String, GtdItem>()
    let childBuckets = HashMap<String, ArrayList<GtdItem>>()

    init(workspace: GtdWorkspace) {
        this.source = workspace
        for (item in workspace.items) {
            byId[item.id] = item
            let key = match (item.parentId) {
                case Some(parent) => "p:" + parent
                case None => ROOT_KEY
            }
            match (childBuckets.get(key)) {
                case Some(bucket) => bucket.add(item)
                case None =>
                    let bucket = ArrayList<GtdItem>()
                    bucket.add(item)
                    childBuckets[key] = bucket
            }
        }
    }

    func children(parentId: ?String): Array<GtdItem> {
        let key = match (parentId) {
            case Some(parent) => "p:" + parent
            case None => ROOT_KEY
        }
        match (childBuckets.get(key)) {
            case Some(bucket) => sortByTreeRank(bucket.toArray())
            case None => Array<GtdItem>()
        }
    }

    func itemById(id: String): ?GtdItem {
        byId.get(id)
    }

    /** 全部子孙（不含自身），深度优先、按 order；带 visited 保护允许脏数据成环。 */
    func descendants(id: String): Array<GtdItem> {
        let result = ArrayList<GtdItem>()
        let visited = HashMap<String, Bool>()
        visited[id] = true
        var pending = ArrayList<String>()
        pending.add(id)
        while (pending.size > 0) {
            let current = pending[pending.size - 1]
            pending.remove(at: pending.size - 1)
            for (child in children(Some(current))) {
                match (visited.get(child.id)) {
                    case Some(_) => ()
                    case None =>
                        visited[child.id] = true
                        result.add(child)
                        pending.add(child.id)
                }
            }
        }
        result.toArray()
    }

    func ofKind(kind: GtdKind): Array<GtdItem> {
        let matched = ArrayList<GtdItem>()
        for (item in source.items) {
            if (item.kind == kind) {
                matched.add(item)
            }
        }
        sortByTreeRank(matched.toArray())
    }

    func ofStatus(status: GtdStatus): Array<GtdItem> {
        let matched = ArrayList<GtdItem>()
        for (item in source.items) {
            if (item.status == status) {
                matched.add(item)
            }
        }
        sortByTreeRank(matched.toArray())
    }
}

/* ------------------------------------------------------------------ */
/* 收件箱 / 下一步                                                     */
/* ------------------------------------------------------------------ */

func capturedOrCreated(item: GtdItem): String {
    match (item.capturedAt) {
        case Some(value) => value
        case None => item.createdAt
    }
}

/** 收件箱：按 `capturedAt` 倒序（缺失时退回 `createdAt`）。 */
public func sortInboxItems(items: Array<GtdItem>): Array<GtdItem> {
    sortCopy(
        items,
        {
            left: GtdItem, right: GtdItem =>
                var result = compareStrings(capturedOrCreated(right), capturedOrCreated(left))
                if (result == 0) {
                    result = compareStrings(right.createdAt, left.createdAt)
                }
                if (result == 0) {
                    result = if (left.order < right.order) {
                        -1
                    } else if (left.order > right.order) {
                        1
                    } else {
                        0
                    }
                }
                result
        }
    )
}

/** 一个场景分组。 */
public class ContextGroup {
    public let context: String
    public let items: Array<GtdItem>

    public init(context: String, items: Array<GtdItem>) {
        this.context = context
        this.items = items
    }
}

/**
 * 按 `context` 分组：null/空串归入「无场景」，空组不出现。
 * 组顺序：预设场景顺序 → 自定义场景按名称 → 无场景最后，
 * 因此同一批条目无论输入顺序如何，组顺序都稳定。
 */
public func groupByContext(items: Array<GtdItem>): Array<ContextGroup> {
    let order = ArrayList<String>()
    let buckets = HashMap<String, ArrayList<GtdItem>>()
    for (item in items) {
        let context = match (contextOf(item)) {
            case Some(value) => value
            case None => NO_CONTEXT
        }
        match (buckets.get(context)) {
            case Some(bucket) => bucket.add(item)
            case None =>
                let bucket = ArrayList<GtdItem>()
                bucket.add(item)
                buckets[context] = bucket
                order.add(context)
        }
    }
    let groups = ArrayList<ContextGroup>()
    for (context in order) {
        groups.add(ContextGroup(context, buckets.get(context).getOrThrow().toArray()))
    }
    let sorted = groups.toArray()
    sort(
        sorted,
        lessThan: {
            left: ContextGroup, right: ContextGroup =>
                let leftOrder = contextOrder(left.context)
                let rightOrder = contextOrder(right.context)
                if (leftOrder != rightOrder) {
                    leftOrder < rightOrder
                } else {
                    left.context < right.context
                }
        },
        stable: true
    )
    sorted
}

/**
 * 下一步排序：有截止日期优先（早→晚），无日期排后；
 * 同日期再按能量高→低；最后按创建时间（早→晚）、order。
 */
public func sortNextActions(items: Array<GtdItem>): Array<GtdItem> {
    sortCopy(
        items,
        {
            left: GtdItem, right: GtdItem =>
                let leftEnd = dateKey(left.dueDate)
                let rightEnd = dateKey(right.dueDate)
                var decided = false
                var result: Int64 = 0
                if (leftEnd.isSome() && rightEnd.isSome()) {
                    let leftKey = leftEnd.getOrThrow()
                    let rightKey = rightEnd.getOrThrow()
                    if (leftKey != rightKey) {
                        result = compareStrings(leftKey, rightKey)
                        decided = true
                    }
                } else if (leftEnd.isSome()) {
                    result = -1
                    decided = true
                } else if (rightEnd.isSome()) {
                    result = 1
                    decided = true
                }
                if (!decided) {
                    let byEnergy = energyRank(right) - energyRank(left)
                    if (byEnergy != 0) {
                        result = if (byEnergy < 0) {
                            -1
                        } else {
                            1
                        }
                        decided = true
                    }
                }
                if (!decided) {
                    result = compareStrings(left.createdAt, right.createdAt)
                    if (result == 0) {
                        result = if (left.order < right.order) {
                            -1
                        } else if (left.order > right.order) {
                            1
                        } else {
                            0
                        }
                    }
                }
                result
        }
    )
}

/* ------------------------------------------------------------------ */
/* 长列表分页（纯函数，组件只负责保存 limit）                          */
/* ------------------------------------------------------------------ */

/** 当前页要渲染的条目与计数。 */
public class PageSlice<T> {
    public let items: Array<T>
    public let shown: Int64
    public let total: Int64
    public let remaining: Int64
    public let hasMore: Bool

    public init(items: Array<T>, shown: Int64, total: Int64, remaining: Int64, hasMore: Bool) {
        this.items = items
        this.shown = shown
        this.total = total
        this.remaining = remaining
        this.hasMore = hasMore
    }
}

/** 取前 limit 条；limit 小于 0 时按 0 处理，超过总数时返回全部。 */
public func paginateItems<T>(items: Array<T>, limit: Int64): PageSlice<T> {
    let total = items.size
    let safeLimit = if (limit < 0) {
        0
    } else {
        limit
    }
    let shown = if (safeLimit < total) {
        safeLimit
    } else {
        total
    }
    let visible = ArrayList<T>()
    var index: Int64 = 0
    while (index < shown) {
        visible.add(items[index])
        index += 1
    }
    PageSlice(visible.toArray(), shown, total, total - shown, shown < total)
}

/** 分页状态带 key：key 变化（筛选 / 分组 / 搜索）时自动回到第一页。 */
public class PaginationState {
    public let key: String
    public let limit: Int64

    public init(key: String, limit: Int64) {
        this.key = key
        this.limit = limit
    }
}

/** 当前生效的 limit；state.key 与当前 key 不一致时重置为 pageSize。 */
public func resolvePageLimit(state: PaginationState, key: String, pageSize!: Int64 = LIST_PAGE_SIZE): Int64 {
    if (state.key != key) {
        return pageSize
    }
    if (state.limit < pageSize) {
        pageSize
    } else {
        state.limit
    }
}

/** 点击「显示更多」后的分页状态：基于当前生效的 limit 再追加一页。 */
public func nextPage(state: PaginationState, key: String, pageSize!: Int64 = LIST_PAGE_SIZE): PaginationState {
    PaginationState(key, resolvePageLimit(state, key, pageSize: pageSize) + pageSize)
}

/* ------------------------------------------------------------------ */
/* 面包屑路径索引（列表级一次构建，行内 O(1) 取值）                     */
/* ------------------------------------------------------------------ */

public class PathTitleIndex {
    /** id → 根 → 自身的标题路径。 */
    public let paths: HashMap<String, Array<String>>
    /** id → 根 → 父级的标题路径（面包屑，不含自身）。 */
    public let parents: HashMap<String, Array<String>>
    /** id → 父级路径的展示文本；空路径为 ''。 */
    public let parentText: HashMap<String, String>

    public init(
        paths!: HashMap<String, Array<String>> = HashMap<String, Array<String>>(),
        parents!: HashMap<String, Array<String>> = HashMap<String, Array<String>>(),
        parentText!: HashMap<String, String> = HashMap<String, String>()
    ) {
        this.paths = paths
        this.parents = parents
        this.parentText = parentText
    }

    /** 根 → 自身的标题路径；缺失条目返回空数组。 */
    public func pathOf(id: String): Array<String> {
        match (paths.get(id)) {
            case Some(path) => path
            case None => Array<String>()
        }
    }

    /** 父级路径文本；根级条目返回 ''。 */
    public func parentTextOf(id: String): String {
        match (parentText.get(id)) {
            case Some(text) => text
            case None => ""
        }
    }
}

func pathTitles(index: WorkspaceIndex, id: String): Array<String> {
    let ancestors = ArrayList<GtdItem>()
    let seen = HashMap<String, Bool>()
    seen[id] = true
    match (index.itemById(id)) {
        case None => return Array<String>()
        case Some(item) =>
            var current = item.parentId
            while (true) {
                match (current) {
                    case None => break
                    case Some(parentId) => match (seen.get(parentId)) {
                        case Some(_) => break
                        case None =>
                            seen[parentId] = true
                            match (index.itemById(parentId)) {
                                case None => break
                                case Some(parent) =>
                                    ancestors.add(parent)
                                    current = parent.parentId
                            }
                    }
                }
            }
            ancestors.add(item)
    }
    let titles = ArrayList<String>()
    // ancestors 是「父级 → 根」顺序：末位是自身，前面的需要反向输出成「根 → 父级」。
    var position = ancestors.size - 2
    while (position >= 0) {
        titles.add(ancestors[position].title)
        position -= 1
    }
    titles.add(ancestors[ancestors.size - 1].title)
    titles.toArray()
}

/**
 * 为一批条目一次性构建标题路径索引。
 *
 * 行组件只做 `parentTextOf(id)`，不再逐条回溯父级；
 * 同一 id 重复出现时只计算一次（按首次出现顺序）。
 */
public func buildPathTitleIndex(workspace: GtdWorkspace, items: Array<GtdItem>): PathTitleIndex {
    let index = WorkspaceIndex(workspace)
    let paths = HashMap<String, Array<String>>()
    let parents = HashMap<String, Array<String>>()
    let texts = HashMap<String, String>()
    for (item in items) {
        if (paths.contains(item.id)) {
            continue
        }
        let path = pathTitles(index, item.id)
        paths[item.id] = path
        let parent = ArrayList<String>()
        var position: Int64 = 0
        while (position + 1 < path.size) {
            parent.add(path[position])
            position += 1
        }
        let parentPath = parent.toArray()
        parents[item.id] = parentPath
        texts[item.id] = String.join(parentPath, delimiter: " / ")
    }
    PathTitleIndex(paths: paths, parents: parents, parentText: texts)
}

/* ------------------------------------------------------------------ */
/* 等待中列表的预计算                                                   */
/* ------------------------------------------------------------------ */

public class WaitingRow {
    public let item: GtdItem
    public let days: Int64
    public let overdue: Bool

    public init(item: GtdItem, days: Int64, overdue: Bool) {
        this.item = item
        this.days = days
        this.overdue = overdue
    }
}

/** 按等待天数倒序；天数与超期标记只计算一次。 */
public func buildWaitingRows(items: Array<GtdItem>, today: String): Array<WaitingRow> {
    let rows = ArrayList<WaitingRow>()
    for (item in items) {
        let days = waitingDays(item, today)
        rows.add(WaitingRow(item, days, days > WAITING_WARN_DAYS))
    }
    let sorted = rows.toArray()
    sort(
        sorted,
        lessThan: {
            left: WaitingRow, right: WaitingRow => if (left.days != right.days) {
                left.days > right.days
            } else {
                left.item.order < right.item.order
            }
        },
        stable: true
    )
    sorted
}

/* ------------------------------------------------------------------ */
/* 筛选                                                                */
/* ------------------------------------------------------------------ */

public class NextFilter {
    /** `None` = 全部；`NO_CONTEXT_FILTER` = 无场景；其它为具体场景。 */
    public let context: ?String
    public let dueSoonOnly: Bool
    public let areaId: ?String
    public let search: String
    public let today: String

    public init(
        context!: ?String = None,
        dueSoonOnly!: Bool = false,
        areaId!: ?String = None,
        search!: String = "",
        today!: String
    ) {
        this.context = context
        this.dueSoonOnly = dueSoonOnly
        this.areaId = areaId
        this.search = search
        this.today = today
    }
}

public func matchesSearch(item: GtdItem, search: String): Bool {
    let needle = search.trim().toLower()
    if (needle.isEmpty()) {
        return true
    }
    let parts = ArrayList<String>()
    parts.add(item.title)
    parts.add(item.notes)
    parts.add(match (item.context) {
        case Some(value) => value
        case None => ""
    })
    parts.add(match (item.waitingFor) {
        case Some(value) => value
        case None => ""
    })
    for (tag in item.tags) {
        parts.add(tag)
    }
    let haystack = String.join(parts.toArray(), delimiter: " ").toLower()
    haystack.contains(needle)
}

public func filterNextActions(items: Array<GtdItem>, filter: NextFilter): Array<GtdItem> {
    let todayKey = match (localDayKey(filter.today)) {
        case Some(key) => key
        case None => filter.today
    }
    let matched = ArrayList<GtdItem>()
    for (item in items) {
        let context = contextOf(item)
        match (filter.context) {
            case Some(selected) =>
                if (selected == NO_CONTEXT_FILTER) {
                    if (context.isSome()) {
                        continue
                    }
                } else if (!context.isSome() || context.getOrThrow() != selected) {
                    continue
                }
            case None => ()
        }
        if (filter.dueSoonOnly) {
            let end = dateKey(item.dueDate)
            if (end.isNone() || end.getOrThrow() > todayKey) {
                continue
            }
        }
        if (let Some(area) <- filter.areaId) {
            match (item.areaId) {
                case Some(own) =>
                    if (own != area) {
                        continue
                    }
                case None => continue
            }
        }
        if (!matchesSearch(item, filter.search)) {
            continue
        }
        matched.add(item)
    }
    matched.toArray()
}

/* ------------------------------------------------------------------ */
/* 停滞项目 / 项目健康度                                                */
/* ------------------------------------------------------------------ */

func isStructuralChild(item: GtdItem): Bool {
    item.kind == GtdKind.Action || item.kind == GtdKind.Project || item.kind == GtdKind.Milestone
}

/**
 * 停滞项目：
 * - 无子动作 → true
 * - 有 status=next 的子动作 → false
 * - 所有子动作都完成/放弃 → false（已完成的项目不算停滞）
 * - 其余（有未完成但没有任何 next）→ true
 */
func stuckProjectIn(index: WorkspaceIndex, projectId: String): Bool {
    let project = match (index.itemById(projectId)) {
        case Some(value) => value
        case None => return false
    }
    if (project.kind != GtdKind.Project) {
        return false
    }
    if (project.status == GtdStatus.Done || project.status == GtdStatus.Dropped) {
        return false
    }
    let related = ArrayList<GtdItem>()
    for (child in index.descendants(projectId)) {
        if (isStructuralChild(child)) {
            related.add(child)
        }
    }
    if (related.size == 0) {
        return true
    }
    for (child in related) {
        if (child.status == GtdStatus.Next) {
            return false
        }
    }
    for (child in related) {
        if (!isClosed(child)) {
            return true
        }
    }
    false
}

/** 停滞项目判定（对外入口，内建一次索引）。 */
public func isStuckProject(workspace: GtdWorkspace, projectId: String): Bool {
    stuckProjectIn(WorkspaceIndex(workspace), projectId)
}

public class ProjectHealth {
    public let project: GtdItem
    public let total: Int64
    public let done: Int64
    public let open: Int64
    public let next: Int64
    public let progress: Int64
    public let stuck: Bool

    public init(
        project: GtdItem,
        total: Int64,
        done: Int64,
        open: Int64,
        next: Int64,
        progress: Int64,
        stuck: Bool
    ) {
        this.project = project
        this.total = total
        this.done = done
        this.open = open
        this.next = next
        this.progress = progress
        this.stuck = stuck
    }
}

/** 项目健康度（对外入口，内建一次索引）。 */
public func projectHealth(workspace: GtdWorkspace): Array<ProjectHealth> {
    projectHealthIn(WorkspaceIndex(workspace))
}

/** 项目健康度：直接子动作的数量、完成比与停滞状态。 */
func projectHealthIn(index: WorkspaceIndex): Array<ProjectHealth> {
    let result = ArrayList<ProjectHealth>()
    for (project in index.ofKind(GtdKind.Project)) {
        var total: Int64 = 0
        var done: Int64 = 0
        var next: Int64 = 0
        for (child in index.children(Some(project.id))) {
            if (!isStructuralChild(child)) {
                continue
            }
            total += 1
            if (isClosed(child)) {
                done += 1
            }
            if (child.status == GtdStatus.Next) {
                next += 1
            }
        }
        result.add(
            ProjectHealth(
                project,
                total,
                done,
                total - done,
                next,
                rollupProgressIn(index, project.id),
                stuckProjectIn(index, project.id)
            )
        )
    }
    result.toArray()
}

func roundHalfUp(value: Float64): Int64 {
    let truncated = Int64(value)
    let fraction = value - Float64(truncated)
    if (fraction >= 0.5) {
        truncated + 1
    } else if (fraction <= -0.5) {
        truncated - 1
    } else {
        truncated
    }
}

func clampProgress(value: Int64): Int64 {
    if (value < 0) {
        0
    } else if (value > 100) {
        100
    } else {
        value
    }
}

func completionRatio(children: Array<GtdItem>): Float64 {
    if (children.size == 0) {
        return 0.0
    }
    var doneCount: Int64 = 0
    for (child in children) {
        if (child.status == GtdStatus.Done) {
            doneCount += 1
        }
    }
    Float64(doneCount) / Float64(children.size) * 100.0
}

func computeRollup(index: WorkspaceIndex, item: GtdItem, visiting: HashMap<String, Bool>): Float64 {
    match (visiting.get(item.id)) {
        case Some(_) => return 0.0
        case None => visiting[item.id] = true
    }
    let children = index.children(Some(item.id))
    var value: Float64 = 0.0
    match (item.kind) {
        case GtdKind.Objective =>
            let keyResults = ArrayList<GtdItem>()
            for (child in children) {
                if (child.kind == GtdKind.KeyResult) {
                    keyResults.add(child)
                }
            }
            if (keyResults.size > 0) {
                var sum: Float64 = 0.0
                for (child in keyResults) {
                    sum += computeRollup(index, child, visiting)
                }
                value = sum / Float64(keyResults.size)
            } else {
                value = completionRatio(children)
            }
        case GtdKind.KeyResult => match (item.metric) {
            case Some(metric) =>
                if (metric.target != metric.start) {
                    value = (metric.current - metric.start) / (metric.target - metric.start) * 100.0
                } else if (item.status == GtdStatus.Done) {
                    value = 100.0
                } else {
                    value = completionRatio(children)
                }
            case None =>
                if (item.status == GtdStatus.Done) {
                    value = 100.0
                } else {
                    value = completionRatio(children)
                }
        }
        case GtdKind.Project => value = completionRatio(children)
        case GtdKind.Sop => value = completionRatio(children)
        case _ => value = if (item.status == GtdStatus.Done) {
            100.0
        } else {
            0.0
        }
    }
    visiting.remove(item.id)
    Float64(clampProgress(roundHalfUp(value)))
}

/**
 * 汇总进度 0..100 的整数：
 * - objective：其 KR 的平均；无 KR 时退回子项完成比
 * - keyresult：有 metric 用 (current-start)/(target-start)；否则 done?100:子项完成比
 * - project / sop：子项完成比
 * - 其余：done?100:0
 */
public func rollupProgress(workspace: GtdWorkspace, id: String): Int64 {
    rollupProgressIn(WorkspaceIndex(workspace), id)
}

func rollupProgressIn(index: WorkspaceIndex, id: String): Int64 {
    let target = match (index.itemById(id)) {
        case Some(value) => value
        case None => return 0
    }
    let visiting = HashMap<String, Bool>()
    clampProgress(roundHalfUp(computeRollup(index, target, visiting)))
}

/* ------------------------------------------------------------------ */
/* 等待项                                                              */
/* ------------------------------------------------------------------ */

/** 等待基线：`capturedAt` 优先，其次 `updatedAt`，最后 `createdAt`。 */
public func waitingSince(item: GtdItem): String {
    match (item.capturedAt) {
        case Some(value) => value
        case None =>
            if (item.updatedAt.isEmpty()) {
                item.createdAt
            } else {
                item.updatedAt
            }
    }
}

/**
 * 已等待天数：从等待基线到 today 的本地日历天数，负数归零。
 *
 * `today` 非法时 TS 会退回系统时钟；这里沿用 `daysBetween` 的 0 语义，
 * 保证纯函数不读时钟。
 */
public func waitingDays(item: GtdItem, today: String): Int64 {
    let todayKey = match (localDayKey(today)) {
        case Some(key) => key
        case None => today
    }
    let sinceKey = localDayKey(waitingSince(item))
    match (sinceKey) {
        case Some(key) =>
            let days = daysBetween(key, todayKey)
            if (days < 0) {
                0
            } else {
                days
            }
        case None => 0
    }
}

/** 超过阈值（严格大于）视为需要催办。 */
public func isWaitingOverdue(
    item: GtdItem,
    today: String,
    threshold!: Int64 = WAITING_WARN_DAYS
): Bool {
    waitingDays(item, today) > threshold
}

/* ------------------------------------------------------------------ */
/* 周回顾                                                              */
/* ------------------------------------------------------------------ */

public class StaleArea {
    public let area: GtdArea
    public let openCount: Int64
    public let lastTouched: ?String

    public init(area: GtdArea, openCount: Int64, lastTouched: ?String) {
        this.area = area
        this.openCount = openCount
        this.lastTouched = lastTouched
    }
}

public class WeeklyReviewStats {
    public let today: String
    public let windowStart: String
    public let inbox: Array<GtdItem>
    public let inboxCount: Int64
    public let inboxCleared: Array<GtdItem>
    public let inboxClearedCount: Int64
    public let inboxProgress: Int64
    public let completedThisWeek: Array<GtdItem>
    public let completedCount: Int64
    public let overdue: Array<GtdItem>
    public let overdueCount: Int64
    public let stuckProjects: Array<GtdItem>
    public let stuckProjectCount: Int64
    public let waitingOverdue: Array<GtdItem>
    public let waitingOverdueCount: Int64
    public let undatedTasks: Array<GtdItem>
    public let undatedCount: Int64
    public let staleAreas: Array<StaleArea>

    public init(
        today: String,
        windowStart: String,
        inbox: Array<GtdItem>,
        inboxCleared: Array<GtdItem>,
        inboxProgress: Int64,
        completedThisWeek: Array<GtdItem>,
        overdue: Array<GtdItem>,
        stuckProjects: Array<GtdItem>,
        waitingOverdue: Array<GtdItem>,
        undatedTasks: Array<GtdItem>,
        staleAreas: Array<StaleArea>
    ) {
        this.today = today
        this.windowStart = windowStart
        this.inbox = inbox
        this.inboxCount = inbox.size
        this.inboxCleared = inboxCleared
        this.inboxClearedCount = inboxCleared.size
        this.inboxProgress = inboxProgress
        this.completedThisWeek = completedThisWeek
        this.completedCount = completedThisWeek.size
        this.overdue = overdue
        this.overdueCount = overdue.size
        this.stuckProjects = stuckProjects
        this.stuckProjectCount = stuckProjects.size
        this.waitingOverdue = waitingOverdue
        this.waitingOverdueCount = waitingOverdue.size
        this.undatedTasks = undatedTasks
        this.undatedCount = undatedTasks.size
        this.staleAreas = staleAreas
    }
}

func overdueItems(index: WorkspaceIndex, todayKey: String): Array<GtdItem> {
    let matched = ArrayList<GtdItem>()
    for (item in index.source.items) {
        let end = dateKey(item.dueDate)
        match (end) {
            case Some(key) =>
                if (key < todayKey && isOpen(item)) {
                    matched.add(item)
                }
            case None => ()
        }
    }
    let rows = matched.toArray()
    sort(
        rows,
        lessThan: {
            left: GtdItem, right: GtdItem =>
                let leftKey = match (dateKey(left.dueDate)) {
                    case Some(value) => value
                    case None => ""
                }
                let rightKey = match (dateKey(right.dueDate)) {
                    case Some(value) => value
                    case None => ""
                }
                leftKey < rightKey
        },
        stable: true
    )
    rows
}

func completedAtDescending(items: Array<GtdItem>): Array<GtdItem> {
    let rows = sortCopy(
        items,
        {
            left: GtdItem, right: GtdItem =>
                let leftAt = match (left.completedAt) {
                    case Some(value) => value
                    case None => ""
                }
                let rightAt = match (right.completedAt) {
                    case Some(value) => value
                    case None => ""
                }
                compareStrings(rightAt, leftAt)
        }
    )
    rows
}

func dayKeyWithinLastWeek(value: ?String, todayKey: String): Bool {
    match (localDayKey(value)) {
        case Some(key) =>
            let diff = daysBetween(key, todayKey)
            diff >= 0 && diff < 7
        case None => false
    }
}

/**
 * 周回顾统计（最近 7 天，含今天）：
 * - 本周完成：completedAt 落在窗口内
 * - 超期：dueDate < today 且未完成/未放弃
 * - 无日期任务：status 为 next/active 的 action/project 且没有 start/end
 * - 等待超 7 天、停滞项目、收件箱清零进度
 *
 * `today` 必须是合法日期键；TS 在非法输入时会退回系统时钟，这里抛异常。
 */
public func weeklyReview(workspace: GtdWorkspace, today: String): WeeklyReviewStats {
    let todayKey = match (localDayKey(today)) {
        case Some(key) => key
        case None => throw IllegalArgumentException("weeklyReview: 非法日期键 " + today)
    }
    let windowStart = dayOffset(-6, todayKey)
    let staleBefore = dayOffset(-14, todayKey)
    let index = WorkspaceIndex(workspace)

    let inbox = index.ofStatus(GtdStatus.Inbox)

    let completedRaw = ArrayList<GtdItem>()
    for (item in workspace.items) {
        if (item.completedAt.isNone()) {
            continue
        }
        if (dayKeyWithinLastWeek(item.completedAt, todayKey)) {
            completedRaw.add(item)
        }
    }
    let completedThisWeek = completedAtDescending(completedRaw.toArray())

    let cleared = ArrayList<GtdItem>()
    for (item in workspace.items) {
        if (!item.clarified || item.status == GtdStatus.Inbox) {
            continue
        }
        if (dayKeyWithinLastWeek(item.capturedAt, todayKey)) {
            cleared.add(item)
        }
    }
    let inboxCleared = cleared.toArray()

    let inboxTotal = inbox.size + inboxCleared.size
    let inboxProgress = if (inboxTotal == 0) {
        100
    } else {
        roundHalfUp(Float64(inboxCleared.size) / Float64(inboxTotal) * 100.0)
    }

    let overdue = overdueItems(index, todayKey)

    let stuck = ArrayList<GtdItem>()
    for (entry in projectHealthIn(index)) {
        if (entry.stuck) {
            stuck.add(entry.project)
        }
    }
    let stuckProjects = stuck.toArray()

    let overdueWaiting = ArrayList<GtdItem>()
    for (item in index.ofStatus(GtdStatus.Waiting)) {
        if (isWaitingOverdue(item, todayKey)) {
            overdueWaiting.add(item)
        }
    }
    let waitingOverdue = overdueWaiting.toArray()

    let undated = ArrayList<GtdItem>()
    for (item in workspace.items) {
        if (item.kind != GtdKind.Action && item.kind != GtdKind.Project) {
            continue
        }
        if (!isOpen(item)) {
            continue
        }
        if (item.status != GtdStatus.Next && item.status != GtdStatus.Active) {
            continue
        }
        if (dateKey(item.startDate).isSome() || dateKey(item.dueDate).isSome()) {
            continue
        }
        undated.add(item)
    }
    let undatedTasks = undated.toArray()

    let stale = ArrayList<StaleArea>()
    for (area in workspace.areas) {
        let areaItems = ArrayList<GtdItem>()
        for (item in workspace.items) {
            match (item.areaId) {
                case Some(own) =>
                    if (own == area.id && isOpen(item) && (item.kind == GtdKind.Action || item.kind == GtdKind.Project)) {
                        areaItems.add(item)
                    }
                case None => ()
            }
        }
        if (areaItems.size == 0) {
            continue
        }
        var lastTouched: ?String = None
        for (item in areaItems) {
            match (lastTouched) {
                case Some(current) =>
                    if (item.updatedAt > current) {
                        lastTouched = Some(item.updatedAt)
                    }
                case None => lastTouched = Some(item.updatedAt)
            }
        }
        var staleArea = true
        match (localDayKey(lastTouched)) {
            case Some(key) =>
                if (key >= staleBefore) {
                    staleArea = false
                }
            case None => ()
        }
        if (staleArea) {
            stale.add(StaleArea(area, areaItems.size, lastTouched))
        }
    }

    WeeklyReviewStats(
        todayKey,
        windowStart,
        inbox,
        inboxCleared,
        inboxProgress,
        completedThisWeek,
        overdue,
        stuckProjects,
        waitingOverdue,
        undatedTasks,
        stale.toArray()
    )
}

/* ------------------------------------------------------------------ */
/* 展示辅助                                                            */
/* ------------------------------------------------------------------ */

/** 收集时间：今天 / 昨天 / n 天前，超过两周用 MM/dd。 */
public func relativeTimeLabel(value: ?String, now: String): String {
    let key = match (localDayKey(value)) {
        case Some(day) => day
        case None => return "—"
    }
    let todayKey = match (localDayKey(now)) {
        case Some(day) => day
        case None => now
    }
    let diff = daysBetween(key, todayKey)
    if (diff <= 0) {
        return "今天"
    }
    if (diff == 1) {
        return "昨天"
    }
    if (diff < 14) {
        return diff.toString() + " 天前"
    }
    formatMonthDay(key)
}

@Derive[Equatable]
public enum DeadlineTone {
    | Danger
    | Accent
    | Muted
}

public class DeadlineInfo {
    public let label: String
    public let tone: DeadlineTone
    public let date: ?String

    public init(label: String, tone: DeadlineTone, date: ?String) {
        this.label = label
        this.tone = tone
        this.date = date
    }
}

/** 截止日期展示：超期标 danger，今天标 accent，其余 MM/dd。 */
public func deadlineInfo(item: GtdItem, today: String): DeadlineInfo {
    let end = dateKey(item.dueDate)
    if (end.isNone()) {
        return DeadlineInfo("未设截止", DeadlineTone.Muted, None)
    }
    let endKey = end.getOrThrow()
    let todayKey = match (localDayKey(today)) {
        case Some(key) => key
        case None => today
    }
    let diff = daysBetween(endKey, todayKey)
    if (diff > 0) {
        return DeadlineInfo("逾期 " + diff.toString() + " 天", DeadlineTone.Danger, Some(endKey))
    }
    if (diff == 0) {
        return DeadlineInfo("今天到期", DeadlineTone.Accent, Some(endKey))
    }
    DeadlineInfo(formatMonthDay(endKey), DeadlineTone.Muted, Some(endKey))
}

/** 在 notes 末尾追加一条带时间戳的记录（时刻由调用方注入）。 */
public func appendTimestampedNote(notes: String, message: String, at: String): String {
    let line = "[" + formatDateTime(at) + "] " + message
    let base = notes.trimEnd()
    if (base.isEmpty()) {
        line
    } else {
        base + "\n" + line
    }
}
