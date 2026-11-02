package textura.views.okr.logic

import std.collection.*
import std.unicode.*

/*
 * 对齐与列表派生：执行项合并、搜索过滤、表格分页、执行项父路径文本。
 */

/** 执行项与 KR 的关联路径。 */
public enum ExecutionVia <: Equatable<ExecutionVia> {
    | Edge
    | Child

    public operator func ==(that: ExecutionVia): Bool {
        executionViaText(this) == executionViaText(that)
    }

    public operator func !=(that: ExecutionVia): Bool {
        !(this == that)
    }
}

public func executionViaText(via: ExecutionVia): String {
    match (via) {
        case ExecutionVia.Edge => "edge"
        case ExecutionVia.Child => "child"
    }
}

/** 一条执行项及其关联来源。 */
public struct ExecutionItemRef {
    public let item: OkrItem
    public let via: ExecutionVia
    public let edgeId: ?String

    public init(item: OkrItem, via: ExecutionVia, edgeId: ?String) {
        this.item = item
        this.via = via
        this.edgeId = edgeId
    }
}

/** 目标 + 过滤后的 KR。 */
public struct ObjectiveView {
    public let objective: OkrItem
    public let keyResults: Array<OkrItem>
    /** 目标本身命中搜索时为 true；仅 KR 命中时为 false。 */
    public let objectiveMatched: Bool

    public init(objective: OkrItem, keyResults: Array<OkrItem>, objectiveMatched: Bool) {
        this.objective = objective
        this.keyResults = keyResults
        this.objectiveMatched = objectiveMatched
    }
}

private func isExecutionItem(item: OkrItem): Bool {
    item.kind == OkrItemKind.Project || item.kind == OkrItemKind.Action
}

/**
 * 一条 KR 的全部执行项。两条路径都要展示：
 * 1) `okr` 边（from = KR, to = 执行项）
 * 2) parentId 直接挂在 KR 下的 project / action
 * 同一执行项同时命中两条路径时以 edge 为准（可解除关联）。
 *
 * 顺序与 TS 一致：先 edges 数组顺序命中的边关联项，再按 `order` 排序的子项。
 * 本包不做缓存（纯函数），视图可在自己那层按 workspace 签名记忆化。
 */
public func executionItemsOf(workspace: OkrWorkspace, krId: String): Array<ExecutionItemRef> {
    let index = OkrIndex(workspace)
    let result = ArrayList<ExecutionItemRef>()
    let seen = HashSet<String>()

    for (edge in index.edgesFromOf(krId)) {
        if (edge.edgeType != OkrEdgeType.Okr || seen.contains(edge.toId)) {
            continue
        }
        let targetOption = index.itemById(edge.toId)
        if (targetOption.isNone()) {
            continue
        }
        let target = targetOption.getOrThrow()
        if (!isExecutionItem(target)) {
            continue
        }
        seen.add(target.id)
        result.add(ExecutionItemRef(target, ExecutionVia.Edge, Some(edge.id)))
    }

    for (child in index.childrenOf(krId)) {
        if (seen.contains(child.id) || !isExecutionItem(child)) {
            continue
        }
        seen.add(child.id)
        result.add(ExecutionItemRef(child, ExecutionVia.Child, None))
    }
    result.toArray()
}

private func searchableText(index: OkrIndex, item: OkrItem): String {
    let areaName = match (item.areaId) {
        case Some(areaId) => index.areaName(areaId)
        case None => ""
    }
    let owner = match (item.okr) {
        case Some(okr) => match (okr.krOwner) {
            case Some(value) => value
            case None => ""
        }
        case None => ""
    }
    var text = item.title + " " + item.notes + " " + areaName + " " + owner
    for (tag in item.tags) {
        text = text + " " + tag
    }
    text.toLower()
}

private func normalizeQuery(query: String): String {
    query.trim().toLower()
}

/** 搜索命中：标题、备注、领域名、KR 负责人、标签；空查询命中一切。 */
public func matchesQuery(workspace: OkrWorkspace, item: OkrItem, query: String): Bool {
    let needle = normalizeQuery(query)
    if (needle.isEmpty()) {
        return true
    }
    searchableText(OkrIndex(workspace), item).contains(needle)
}

private func matchesQueryIn(index: OkrIndex, item: OkrItem, needle: String): Bool {
    if (needle.isEmpty()) {
        return true
    }
    searchableText(index, item).contains(needle)
}

/** 目标 + 过滤后的 KR；目标命中时保留全部 KR，仅 KR 命中时只保留命中的 KR。 */
public func filterObjectives(
    workspace: OkrWorkspace,
    period: String,
    query: String
): Array<ObjectiveView> {
    let index = OkrIndex(workspace)
    let needle = normalizeQuery(query)
    let result = ArrayList<ObjectiveView>()

    for (objective in index.objectivesOf(period)) {
        let keyResults = ArrayList<OkrItem>()
        for (child in index.childrenOf(objective.id)) {
            if (child.kind == OkrItemKind.KeyResult) {
                keyResults.add(child)
            }
        }
        let krs = keyResults.toArray()
        if (needle.isEmpty()) {
            result.add(ObjectiveView(objective, krs, true))
            continue
        }
        if (matchesQueryIn(index, objective, needle)) {
            result.add(ObjectiveView(objective, krs, true))
            continue
        }
        let matched = ArrayList<OkrItem>()
        for (kr in krs) {
            if (matchesQueryIn(index, kr, needle)) {
                matched.add(kr)
            }
        }
        if (matched.size > 0) {
            result.add(ObjectiveView(objective, matched.toArray(), false))
        }
    }
    result.toArray()
}

/* ------------------------------------------------------------------ */
/* 表格长列表分页                                                       */
/* ------------------------------------------------------------------ */

/** 表格一次渲染的 KR 行数上限。 */
public let OKR_KR_PAGE_SIZE: Int64 = 200

/** 一页表格数据；`entries` 里每个目标的 keyResults 已切到本页范围。 */
public struct ObjectiveTablePage {
    public let entries: Array<ObjectiveView>
    public let shownKeyResults: Int64
    public let totalKeyResults: Int64
    public let remaining: Int64
    public let hasMore: Bool

    public init(
        entries: Array<ObjectiveView>,
        shownKeyResults: Int64,
        totalKeyResults: Int64,
        remaining: Int64,
        hasMore: Bool
    ) {
        this.entries = entries
        this.shownKeyResults = shownKeyResults
        this.totalKeyResults = totalKeyResults
        this.remaining = remaining
        this.hasMore = hasMore
    }
}

/**
 * 按 KR 行数分页（不是按目标数）：跨目标顺序保持不变，
 * 一个目标只有在前面的 KR 进入本页时才出现，避免空目标块。
 * 没有 KR 的目标在还有预算时照常显示（保留「缺少 KR」提示）。
 */
public func paginateObjectiveKrs(entries: Array<ObjectiveView>, limit: Int64): ObjectiveTablePage {
    var totalKeyResults = 0
    for (entry in entries) {
        totalKeyResults += entry.keyResults.size
    }
    let safeLimit = if (limit < 0) {
        0
    } else {
        limit
    }
    var budget = safeLimit
    var shownKeyResults = 0
    let page = ArrayList<ObjectiveView>()

    for (entry in entries) {
        if (budget <= 0) {
            break
        }
        if (entry.keyResults.size == 0) {
            page.add(ObjectiveView(entry.objective, Array<OkrItem>(), entry.objectiveMatched))
            continue
        }
        let visibleCount = if (entry.keyResults.size < budget) {
            entry.keyResults.size
        } else {
            budget
        }
        let visible = entry.keyResults[0..visibleCount]
        budget -= visibleCount
        shownKeyResults += visibleCount
        page.add(ObjectiveView(entry.objective, visible, entry.objectiveMatched))
    }

    ObjectiveTablePage(
        page.toArray(),
        shownKeyResults,
        totalKeyResults,
        totalKeyResults - shownKeyResults,
        shownKeyResults < totalKeyResults
    )
}

/** 分页状态：key（季度 + 搜索词）与当前上限。 */
public struct OkrPaginationState <: Equatable<OkrPaginationState> {
    public let key: String
    public let limit: Int64

    public init(key: String, limit: Int64) {
        this.key = key
        this.limit = limit
    }

    public operator func ==(that: OkrPaginationState): Bool {
        key == that.key && limit == that.limit
    }
}

/** 分页 key（季度 + 搜索词）变化时自动回到第一页。 */
public func resolveOkrPageLimit(
    state: OkrPaginationState,
    key: String,
    pageSize!: Int64 = OKR_KR_PAGE_SIZE
): Int64 {
    if (state.key != key) {
        return pageSize
    }
    if (state.limit < pageSize) {
        pageSize
    } else {
        state.limit
    }
}

public func nextOkrPage(
    state: OkrPaginationState,
    key: String,
    pageSize!: Int64 = OKR_KR_PAGE_SIZE
): OkrPaginationState {
    OkrPaginationState(key, resolveOkrPageLimit(state, key, pageSize: pageSize) + pageSize)
}

/* ------------------------------------------------------------------ */
/* 执行项路径索引（列表级一次构建，行内 O(1)）                          */
/* ------------------------------------------------------------------ */

/** 祖先链（最近优先）与自身的标题，根在最先。 */
private func itemPathTitles(index: OkrIndex, id: String): Array<String> {
    let itemOption = index.itemById(id)
    if (itemOption.isNone()) {
        return Array<String>()
    }
    let item = itemOption.getOrThrow()
    let ancestors = ArrayList<OkrItem>()
    let seen = HashSet<String>()
    seen.add(id)
    var current = item.parentId
    while (true) {
        match (current) {
            case Some(parentId) =>
                if (seen.contains(parentId)) {
                    break
                }
                let parentOption = index.itemById(parentId)
                if (parentOption.isNone()) {
                    break
                }
                let parent = parentOption.getOrThrow()
                ancestors.add(parent)
                seen.add(parentId)
                current = parent.parentId
            case None => break
        }
    }
    let titles = ArrayList<String>()
    for (offset in 0..ancestors.size) {
        titles.add(ancestors[ancestors.size - 1 - offset].title)
    }
    titles.add(item.title)
    titles.toArray()
}

/**
 * 为一批执行项构建「根 → 父级」的路径文本。
 * 行内只做 HashMap.get，不再逐条重算祖先链。
 */
public func buildParentPathText(
    workspace: OkrWorkspace,
    items: Array<OkrItem>
): HashMap<String, String> {
    let index = OkrIndex(workspace)
    let map = HashMap<String, String>()
    for (item in items) {
        if (map.contains(item.id)) {
            continue
        }
        let titles = itemPathTitles(index, item.id)
        let parents = if (titles.size > 0) {
            titles[0..(titles.size - 1)]
        } else {
            Array<String>()
        }
        map[item.id] = String.join(parents, delimiter: " / ")
    }
    map
}
