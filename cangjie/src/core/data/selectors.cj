package textura.core.data

import std.collection.*
import std.sort.*

/**
 * Pure selectors over `Workspace` — the single place派生逻辑 lives.
 *
 * Performance contract: one index per `Workspace` instance (`Workspace.index()`),
 * so the store must keep building new `Workspace` values instead of mutating.
 * Returned arrays belong to the index: treat them as read-only.
 */
public class WorkspaceIndex {
    public let byId: HashMap<String, Item>
    /** parent id -> children, sorted by order then createdAt. Root items use "". */
    public let children: HashMap<String, Array<Item>>
    /** wire kind name -> items. */
    public let byKind: HashMap<String, Array<Item>>
    public let objectivesByPeriod: HashMap<String, Array<Item>>
    /** wire status name -> items. */
    public let byStatus: HashMap<String, Array<Item>>
    public let edgesFrom: HashMap<String, Array<Edge>>
    public let edgesTo: HashMap<String, Array<Edge>>
    public let areas: HashMap<String, Area>
    public let rollups: HashMap<String, Int64>
    public let paths: HashMap<String, Array<Item>>
    public let descendants: HashMap<String, Array<Item>>
    public let ancestors: HashMap<String, Array<Item>>
    public let okrPeriodsCache: Array<String>
    public var parentCycles: ?Array<Array<String>> = None

    public init(
        byId: HashMap<String, Item>,
        children: HashMap<String, Array<Item>>,
        byKind: HashMap<String, Array<Item>>,
        objectivesByPeriod: HashMap<String, Array<Item>>,
        byStatus: HashMap<String, Array<Item>>,
        edgesFrom: HashMap<String, Array<Edge>>,
        edgesTo: HashMap<String, Array<Edge>>,
        areas: HashMap<String, Area>,
        okrPeriodsCache: Array<String>
    ) {
        this.byId = byId
        this.children = children
        this.byKind = byKind
        this.objectivesByPeriod = objectivesByPeriod
        this.byStatus = byStatus
        this.edgesFrom = edgesFrom
        this.edgesTo = edgesTo
        this.areas = areas
        this.rollups = HashMap<String, Int64>()
        this.paths = HashMap<String, Array<Item>>()
        this.descendants = HashMap<String, Array<Item>>()
        this.ancestors = HashMap<String, Array<Item>>()
        this.okrPeriodsCache = okrPeriodsCache
    }
}

/** Root sentinel for `WorkspaceIndex.children` (the TS code keys by `null`). */
let ROOT_KEY: String = ""

func compareItems(left: Item, right: Item): Int64 {
    if (left.order != right.order) {
        if (left.order < right.order) {
            -1
        } else {
            1
        }
    } else {
        compareText(left.createdAt, right.createdAt)
    }
}

func sortedItems(items: ArrayList<Item>): Array<Item> {
    let result = items.toArray()
    sort<Item>(result, lessThan: {left, right => compareItems(left, right) < 0})
    result
}

public func buildWorkspaceIndex(workspace: Workspace): WorkspaceIndex {
    let byId = HashMap<String, Item>()
    let areas = HashMap<String, Area>()
    let children = HashMap<String, ArrayList<Item>>()
    let byKind = HashMap<String, ArrayList<Item>>()
    let objectivesByPeriod = HashMap<String, ArrayList<Item>>()
    let byStatus = HashMap<String, ArrayList<Item>>()
    let edgesFrom = HashMap<String, ArrayList<Edge>>()
    let edgesTo = HashMap<String, ArrayList<Edge>>()

    for (status in ITEM_STATUSES) {
        byStatus[itemStatusWire(status)] = ArrayList<Item>()
    }

    for (item in workspace.items) {
        byId[item.id] = item
        let parentKey = match (item.parentId) {
            case Some(value) => value
            case None => ROOT_KEY
        }
        appendToGroup(children, parentKey, item)

        let kindKey = itemKindWire(item.kind)
        appendToGroup(byKind, kindKey, item)
        appendToGroup(byStatus, itemStatusWire(item.status), item)

        if (item.kind == ItemKind.Objective) {
            match (item.okr) {
                case Some(okr) => if (!okr.period.isEmpty()) {
                    appendToGroup(objectivesByPeriod, okr.period, item)
                }
                case None => ()
            }
        }
    }

    for (area in workspace.areas) {
        areas[area.id] = area
    }
    for (edge in workspace.edges) {
        appendToGroup(edgesFrom, edge.from, edge)
        appendToGroup(edgesTo, edge.to, edge)
    }

    let sortedChildren = HashMap<String, Array<Item>>()
    for ((key, list) in children) {
        sortedChildren[key] = sortedItems(list)
    }
    let sortedByKind = HashMap<String, Array<Item>>()
    for ((key, list) in byKind) {
        sortedByKind[key] = sortedItems(list)
    }
    let sortedByStatus = HashMap<String, Array<Item>>()
    for ((key, list) in byStatus) {
        sortedByStatus[key] = sortedItems(list)
    }
    let sortedObjectives = HashMap<String, Array<Item>>()
    for ((key, list) in objectivesByPeriod) {
        sortedObjectives[key] = sortedItems(list)
    }
    let frozenEdgesFrom = HashMap<String, Array<Edge>>()
    for ((key, list) in edgesFrom) {
        frozenEdgesFrom[key] = list.toArray()
    }
    let frozenEdgesTo = HashMap<String, Array<Edge>>()
    for ((key, list) in edgesTo) {
        frozenEdgesTo[key] = list.toArray()
    }

    let periods = ArrayList<String>()
    for (key in sortedObjectives.keys()) {
        periods.add(key)
    }
    let periodArray = periods.toArray()
    sort<String>(periodArray, lessThan: {left, right => left > right})

    WorkspaceIndex(
        byId,
        sortedChildren,
        sortedByKind,
        sortedObjectives,
        sortedByStatus,
        frozenEdgesFrom,
        frozenEdgesTo,
        areas,
        periodArray
    )
}

func appendToGroup<T>(groups: HashMap<String, ArrayList<T>>, key: String, value: T): Unit {
    match (groups.get(key)) {
        case Some(list) => list.add(value)
        case None =>
            let list = ArrayList<T>()
            list.add(value)
            groups[key] = list
    }
}

func itemsAt(groups: HashMap<String, Array<Item>>, key: String): Array<Item> {
    match (groups.get(key)) {
        case Some(list) => list
        case None => []
    }
}

public func itemById(workspace: Workspace, id: String): ?Item {
    workspace.index().byId.get(id)
}

public func areaById(workspace: Workspace, areaId: String): ?Area {
    workspace.index().areas.get(areaId)
}

/** Direct children sorted by `order`, then `createdAt`. Pass `None` for roots. */
public func childrenOf(workspace: Workspace, parentId: ?String): Array<Item> {
    let key = match (parentId) {
        case Some(value) => value
        case None => ROOT_KEY
    }
    itemsAt(workspace.index().children, key)
}

public func rootItems(workspace: Workspace): Array<Item> {
    childrenOf(workspace, None)
}

/** All descendants (excluding the node), depth first, order-sorted, cycle safe. */
public func descendantsOf(workspace: Workspace, id: String): Array<Item> {
    let index = workspace.index()
    match (index.descendants.get(id)) {
        case Some(cached) => return cached
        case None => ()
    }
    let result = ArrayList<Item>()
    let visited = HashMap<String, Bool>()
    visited[id] = true
    collectDescendants(index, id, result, visited)
    let frozen = result.toArray()
    index.descendants[id] = frozen
    frozen
}

func collectDescendants(
    index: WorkspaceIndex,
    parentId: String,
    result: ArrayList<Item>,
    visited: HashMap<String, Bool>
): Unit {
    for (child in itemsAt(index.children, parentId)) {
        match (visited.get(child.id)) {
            case Some(_) => continue
            case None => ()
        }
        visited[child.id] = true
        result.add(child)
        collectDescendants(index, child.id, result, visited)
    }
}

/** Ancestors from the direct parent up to the root (nearest first). */
public func ancestorsOf(workspace: Workspace, id: String): Array<Item> {
    let index = workspace.index()
    match (index.ancestors.get(id)) {
        case Some(cached) => return cached
        case None => ()
    }
    let result = ArrayList<Item>()
    let seen = HashMap<String, Bool>()
    seen[id] = true
    var current: ?String = match (index.byId.get(id)) {
        case Some(item) => item.parentId
        case None => None
    }
    while (true) {
        match (current) {
            case None => break
            case Some(parentId) => match (seen.get(parentId)) {
                case Some(_) => break
                case None =>
                    match (index.byId.get(parentId)) {
                        case None => break
                        case Some(parent) =>
                            result.add(parent)
                            seen[parentId] = true
                            current = parent.parentId
                    }
            }
        }
    }
    let frozen = result.toArray()
    index.ancestors[id] = frozen
    frozen
}

/**
 * All parent cycles as id paths (`['a','b','a']`, self loop `['a','a']`).
 * Mirrors `findParentCycles` in `src/core/selectors.ts`.
 */
public func findParentCycles(workspace: Workspace): Array<Array<String>> {
    let index = workspace.index()
    match (index.parentCycles) {
        case Some(cached) => return cached
        case None => ()
    }
    let finished = HashMap<String, Bool>()
    let cycles = ArrayList<Array<String>>()
    for (item in index.byId.values()) {
        match (finished.get(item.id)) {
            case Some(_) => continue
            case None => ()
        }
        let path = ArrayList<String>()
        let seenInPath = HashMap<String, Int64>()
        var current: ?String = Some(item.id)
        while (true) {
            match (current) {
                case None => break
                case Some(nodeId) =>
                    match (finished.get(nodeId)) {
                        case Some(_) => break
                        case None => ()
                    }
                    match (seenInPath.get(nodeId)) {
                        case Some(previous) =>
                            let cycle = ArrayList<String>()
                            var position = previous
                            while (position < path.size) {
                                cycle.add(path[position])
                                position += 1
                            }
                            cycle.add(nodeId)
                            cycles.add(cycle.toArray())
                            break
                        case None => ()
                    }
                    match (index.byId.get(nodeId)) {
                        case None => break
                        case Some(node) =>
                            seenInPath[nodeId] = path.size
                            path.add(nodeId)
                            current = node.parentId
                    }
            }
        }
        for (pathId in path) {
            finished[pathId] = true
        }
    }
    let frozen = cycles.toArray()
    index.parentCycles = frozen
    frozen
}

public func itemsOfKind(workspace: Workspace, kind: ItemKind): Array<Item> {
    itemsAt(workspace.index().byKind, itemKindWire(kind))
}

public func objectivesOfPeriod(workspace: Workspace, period: String): Array<Item> {
    itemsAt(workspace.index().objectivesByPeriod, period)
}

/** Objective periods, newest first. */
public func okrPeriods(workspace: Workspace): Array<String> {
    workspace.index().okrPeriodsCache
}

func completionRatio(children: Array<Item>): Float64 {
    if (children.isEmpty()) {
        return 0.0
    }
    var done = 0
    for (child in children) {
        if (child.isDone()) {
            done += 1
        }
    }
    Float64(done) * 100.0 / Float64(children.size)
}

/**
 * Roll-up progress 0..100:
 * - objective: mean of its KR progress, else child completion;
 * - keyresult: metric conversion when the metric spans a range, else 100/child completion;
 * - project / sop: child completion;
 * - everything else: done ? 100 : 0.
 */
public func rollupProgress(workspace: Workspace, id: String): Int64 {
    let index = workspace.index()
    match (index.rollups.get(id)) {
        case Some(cached) => return cached
        case None => ()
    }
    match (index.byId.get(id)) {
        case None => return 0
        case Some(_) => ()
    }
    let visiting = HashMap<String, Bool>()
    computeRollup(index, id, visiting)
}

func computeRollup(index: WorkspaceIndex, id: String, visiting: HashMap<String, Bool>): Int64 {
    match (index.rollups.get(id)) {
        case Some(cached) => return cached
        case None => ()
    }
    match (visiting.get(id)) {
        case Some(_) => return 0
        case None => ()
    }
    visiting[id] = true

    let item = match (index.byId.get(id)) {
        case Some(value) => value
        case None =>
            visiting.remove(id)
            return 0
    }
    let children = itemsAt(index.children, item.id)
    var value = 0.0
    match (item.kind) {
        case ItemKind.Objective =>
            let keyResults = ArrayList<Item>()
            for (child in children) {
                if (child.kind == ItemKind.KeyResult) {
                    keyResults.add(child)
                }
            }
            if (!keyResults.isEmpty()) {
                var sum = 0
                for (child in keyResults) {
                    sum += computeRollup(index, child.id, visiting)
                }
                value = Float64(sum) / Float64(keyResults.size)
            } else {
                value = completionRatio(children)
            }
        case ItemKind.KeyResult =>
            var fromMetric = false
            match (item.okr) {
                case Some(okr) => match (okr.metric) {
                    case Some(metric) => if (metric.target != metric.start) {
                        value = ((metric.current - metric.start) / (metric.target - metric.start)) * 100.0
                        fromMetric = true
                    }
                    case None => ()
                }
                case None => ()
            }
            if (!fromMetric) {
                if (item.isDone()) {
                    value = 100.0
                } else {
                    value = completionRatio(children)
                }
            }
        case ItemKind.Project => value = completionRatio(children)
        case ItemKind.Sop => value = completionRatio(children)
        case _ => value = if (item.isDone()) {
            100.0
        } else {
            0.0
        }
    }

    let result = clampInt(roundHalfUp(value), 0, 100)
    index.rollups[id] = result
    visiting.remove(id)
    result
}

public func inboxItems(workspace: Workspace): Array<Item> {
    itemsAt(workspace.index().byStatus, "inbox")
}

/** Actionable next steps: `action` / `project` with status `next`. */
public func nextActions(workspace: Workspace): Array<Item> {
    let result = ArrayList<Item>()
    for (item in itemsAt(workspace.index().byStatus, "next")) {
        if (item.kind == ItemKind.Action || item.kind == ItemKind.Project) {
            result.add(item)
        }
    }
    result.toArray()
}

public func waitingItems(workspace: Workspace): Array<Item> {
    itemsAt(workspace.index().byStatus, "waiting")
}

public func somedayItems(workspace: Workspace): Array<Item> {
    itemsAt(workspace.index().byStatus, "someday")
}

/** A dated item with `start`/`end` normalized to date keys. */
public class ScheduledRow {
    public let item: Item
    public let start: String
    public let end: String

    public init(item: Item, start: String, end: String) {
        this.item = item
        this.start = start
        this.end = end
    }
}

/** Every item with at least one gantt date, sorted by start then order. */
public func scheduledRows(workspace: Workspace): Array<ScheduledRow> {
    let rows = ArrayList<ScheduledRow>()
    for (item in workspace.index().byId.values()) {
        match (item.gantt) {
            case None => continue
            case Some(gantt) => ()
        }
        let gantt = match (item.gantt) {
            case Some(value) => value
            case None => continue
        }
        let start = match (dateKey(gantt.start)) {
            case Some(value) => Some(value)
            case None => dateKey(gantt.end)
        }
        let end = match (dateKey(gantt.end)) {
            case Some(value) => Some(value)
            case None => dateKey(gantt.start)
        }
        match (start) {
            case None => continue
            case Some(startKey) => match (end) {
                case None => continue
                case Some(endKey) => rows.add(ScheduledRow(item, startKey, endKey))
            }
        }
    }
    let result = rows.toArray()
    sort<ScheduledRow>(
        result,
        lessThan: {left, right =>
            if (left.start != right.start) {
                left.start < right.start
            } else {
                left.item.order < right.item.order
            }
        }
    )
    result
}

/** Items whose [start, end] window intersects [fromISO, toISO]. */
public func scheduledItemsInRange(workspace: Workspace, fromISO: String, toISO: String): Array<Item> {
    let fromValue = match (dateKey(fromISO)) {
        case Some(value) => value
        case None => return []
    }
    let toValue = match (dateKey(toISO)) {
        case Some(value) => value
        case None => return []
    }
    let lower = if (fromValue <= toValue) {
        fromValue
    } else {
        toValue
    }
    let upper = if (fromValue <= toValue) {
        toValue
    } else {
        fromValue
    }
    let rows = scheduledRows(workspace)
    let result = ArrayList<Item>()
    for (row in rows) {
        if (row.start > upper) {
            break
        }
        if (row.end >= lower) {
            result.add(row.item)
        }
    }
    result.toArray()
}

/** Overdue, still-open items (gantt.end < today), earliest end first. */
public func overdueItems(workspace: Workspace, today: String): Array<Item> {
    let todayKey = match (dateKey(today)) {
        case Some(value) => value
        case None => return []
    }
    let result = ArrayList<Item>()
    for (item in workspace.index().byId.values()) {
        let end = item.dueKey()
        match (end) {
            case None => continue
            case Some(endKey) =>
                if (endKey < todayKey && item.isOpen()) {
                    result.add(item)
                }
        }
    }
    let array = result.toArray()
    sort<Item>(
        array,
        lessThan: {left, right =>
            let leftEnd = match (left.dueKey()) {
                case Some(value) => value
                case None => ""
            }
            let rightEnd = match (right.dueKey()) {
                case Some(value) => value
                case None => ""
            }
            leftEnd < rightEnd
        }
    )
    array
}

/** Items due today and still open. */
public func dueTodayItems(workspace: Workspace, today: String): Array<Item> {
    let todayKey = match (dateKey(today)) {
        case Some(value) => value
        case None => return []
    }
    let result = ArrayList<Item>()
    for (item in workspace.index().byId.values()) {
        match (item.dueKey()) {
            case Some(endKey) => if (endKey == todayKey && item.isOpen()) {
                result.add(item)
            }
            case None => ()
        }
    }
    result.toArray()
}

/** Distinct edge targets of `id` for one edge type. */
public func edgeTargetsOf(workspace: Workspace, id: String, edgeType: EdgeType): Array<Item> {
    let index = workspace.index()
    let seen = HashMap<String, Bool>()
    let result = ArrayList<Item>()
    for (edge in itemsAtEdges(index.edgesFrom, id)) {
        if (edge.edgeType != edgeType) {
            continue
        }
        match (index.byId.get(edge.to)) {
            case Some(target) => match (seen.get(target.id)) {
                case Some(_) => ()
                case None =>
                    seen[target.id] = true
                    result.add(target)
            }
            case None => ()
        }
    }
    result.toArray()
}

/** Distinct edge sources of `id` for one edge type. */
public func edgeSourcesOf(workspace: Workspace, id: String, edgeType: EdgeType): Array<Item> {
    let index = workspace.index()
    let seen = HashMap<String, Bool>()
    let result = ArrayList<Item>()
    for (edge in itemsAtEdges(index.edgesTo, id)) {
        if (edge.edgeType != edgeType) {
            continue
        }
        match (index.byId.get(edge.from)) {
            case Some(source) => match (seen.get(source.id)) {
                case Some(_) => ()
                case None =>
                    seen[source.id] = true
                    result.add(source)
            }
            case None => ()
        }
    }
    result.toArray()
}

func itemsAtEdges(groups: HashMap<String, Array<Edge>>, key: String): Array<Edge> {
    match (groups.get(key)) {
        case Some(list) => list
        case None => []
    }
}

public class SopGraph {
    public let nodes: Array<Item>
    public let edges: Array<Edge>

    public init(nodes: Array<Item>, edges: Array<Edge>) {
        this.nodes = nodes
        this.edges = edges
    }
}

/** Steps of one SOP (direct children or deeper descendants) plus their flow edges. */
public func sopGraph(workspace: Workspace, sopId: String): SopGraph {
    let index = workspace.index()
    let nodes = ArrayList<Item>()
    for (item in itemsAt(index.byKind, "step")) {
        var belongs = false
        match (item.parentId) {
            case Some(parentId) => if (parentId == sopId) {
                belongs = true
            }
            case None => ()
        }
        if (!belongs) {
            for (ancestor in ancestorsOf(workspace, item.id)) {
                if (ancestor.id == sopId) {
                    belongs = true
                    break
                }
            }
        }
        if (belongs) {
            nodes.add(item)
        }
    }
    let ids = HashMap<String, Bool>()
    for (node in nodes) {
        ids[node.id] = true
    }
    let edges = ArrayList<Edge>()
    for (edge in workspace.edges) {
        var bothEnds = match (ids.get(edge.from)) {
            case Some(_) => true
            case None => false
        }
        if (bothEnds) {
            bothEnds = match (ids.get(edge.to)) {
                case Some(_) => true
                case None => false
            }
        }
        if (edge.edgeType == EdgeType.Flow && bothEnds) {
            edges.add(edge)
        }
    }
    SopGraph(nodes.toArray(), edges.toArray())
}

/** Item counts per status, keyed by wire name (in `ITEM_STATUSES` order). */
public func countByStatus(workspace: Workspace): HashMap<String, Int64> {
    let counts = HashMap<String, Int64>()
    let index = workspace.index()
    for (status in ITEM_STATUSES) {
        let key = itemStatusWire(status)
        counts[key] = itemsAt(index.byStatus, key).size
    }
    counts
}

/** Root -> self path including the item itself; empty when `id` is unknown. */
func pathOf(index: WorkspaceIndex, id: String): Array<Item> {
    match (index.paths.get(id)) {
        case Some(cached) => return cached
        case None => ()
    }
    let item = match (index.byId.get(id)) {
        case Some(value) => value
        case None => return []
    }
    let ancestors = ArrayList<Item>()
    let seen = HashMap<String, Bool>()
    seen[id] = true
    var current = item.parentId
    while (true) {
        match (current) {
            case None => break
            case Some(parentId) => match (seen.get(parentId)) {
                case Some(_) => break
                case None => match (index.byId.get(parentId)) {
                    case None => break
                    case Some(parent) =>
                        ancestors.add(parent)
                        seen[parentId] = true
                        current = parent.parentId
                }
            }
        }
    }
    let path = ArrayList<Item>()
    var position = ancestors.size - 1
    while (position >= 0) {
        path.add(ancestors[position])
        position -= 1
    }
    path.add(item)
    let frozen = path.toArray()
    index.paths[id] = frozen
    frozen
}

/** Depth in the tree: roots are 0. */
public func treeDepth(workspace: Workspace, id: String): Int64 {
    let path = pathOf(workspace.index(), id)
    if (path.isEmpty()) {
        0
    } else {
        path.size - 1
    }
}

/** Root -> self titles. */
public func itemPathTitles(workspace: Workspace, id: String): Array<String> {
    let titles = ArrayList<String>()
    for (item in pathOf(workspace.index(), id)) {
        titles.add(item.title)
    }
    titles.toArray()
}

/** Parent titles joined by ` / ` (breadcrumb text), "" for roots. */
public func parentPathText(workspace: Workspace, id: String): String {
    let path = pathOf(workspace.index(), id)
    let out = StringBuilder()
    var index = 0
    while (index < path.size - 1) {
        if (index > 0) {
            out.append(" / ")
        }
        out.append(path[index].title)
        index += 1
    }
    out.toString()
}
