package textura.views.okr.logic

import std.collection.*
import std.sort.*

/*
 * 工作区索引（包内私有）。
 *
 * 对应 `core.data` 的 `WorkspaceIndex` 子集，语义与 `src/core/selectors.ts` 一致：
 * - `byId`：同 id 后者覆盖（与 Map 写入一致）；
 * - `children`：按 `order` 升序、再按 `createdAt` 字典序（`localeCompare`）；
 * - `objectivesByPeriod`：kind === objective 且 period 非空，同样排序；
 * - `edgesFrom`：保持 `edges` 数组顺序（不排序）。
 *
 * 没有 WeakMap 缓存：本包是纯函数包，索引按调用构建（视图可在自己那层做记忆化）。
 */
private func compareItems(a: OkrItem, b: OkrItem): Bool {
    if (a.order != b.order) {
        return a.order < b.order
    }
    a.createdAt < b.createdAt
}

class OkrIndex {
    let byId: HashMap<String, OkrItem>
    let children: HashMap<String, Array<OkrItem>>
    let edgesFrom: HashMap<String, Array<OkrEdge>>
    let areas: HashMap<String, OkrArea>
    let objectivesByPeriod: HashMap<String, Array<OkrItem>>

    init(workspace: OkrWorkspace) {
        this.byId = HashMap<String, OkrItem>()
        this.areas = HashMap<String, OkrArea>()
        this.children = HashMap<String, Array<OkrItem>>()
        this.edgesFrom = HashMap<String, Array<OkrEdge>>()
        this.objectivesByPeriod = HashMap<String, Array<OkrItem>>()

        let childLists = HashMap<String, ArrayList<OkrItem>>()
        let edgeLists = HashMap<String, ArrayList<OkrEdge>>()
        let objectiveLists = HashMap<String, ArrayList<OkrItem>>()

        for (item in workspace.items) {
            this.byId[item.id] = item
            match (item.parentId) {
                case Some(parentId) =>
                    if (!childLists.contains(parentId)) {
                        childLists[parentId] = ArrayList<OkrItem>()
                    }
                    childLists[parentId].add(item)
                case None => ()
            }
            match (item.okr) {
                case Some(okr) =>
                    if (item.kind == OkrItemKind.Objective && !okr.period.isEmpty()) {
                        if (!objectiveLists.contains(okr.period)) {
                            objectiveLists[okr.period] = ArrayList<OkrItem>()
                        }
                        objectiveLists[okr.period].add(item)
                    }
                case None => ()
            }
        }

        for (area in workspace.areas) {
            this.areas[area.id] = area
        }
        for (edge in workspace.edges) {
            if (!edgeLists.contains(edge.fromId)) {
                edgeLists[edge.fromId] = ArrayList<OkrEdge>()
            }
            edgeLists[edge.fromId].add(edge)
        }

        for ((parentId, list) in childLists) {
            this.children[parentId] = sortedItems(list)
        }
        for ((period, list) in objectiveLists) {
            this.objectivesByPeriod[period] = sortedItems(list)
        }
        for ((fromId, list) in edgeLists) {
            this.edgesFrom[fromId] = list.toArray()
        }
    }

    func itemById(id: String): ?OkrItem {
        byId.get(id)
    }

    func childrenOf(parentId: String): Array<OkrItem> {
        match (children.get(parentId)) {
            case Some(list) => list
            case None => Array<OkrItem>()
        }
    }

    func edgesFromOf(id: String): Array<OkrEdge> {
        match (edgesFrom.get(id)) {
            case Some(list) => list
            case None => Array<OkrEdge>()
        }
    }

    func areaName(areaId: String): String {
        match (areas.get(areaId)) {
            case Some(area) => area.name
            case None => ""
        }
    }

    func objectivesOf(period: String): Array<OkrItem> {
        match (objectivesByPeriod.get(period)) {
            case Some(list) => list
            case None => Array<OkrItem>()
        }
    }
}

private func sortedItems(list: ArrayList<OkrItem>): Array<OkrItem> {
    let items = list.toArray()
    sort(items, lessThan: {a, b => compareItems(a, b)})
    items
}

/** 直接子项，按 `order` 升序、再按 `createdAt`；无子项返回空数组。 */
public func childrenOf(workspace: OkrWorkspace, parentId: String): Array<OkrItem> {
    OkrIndex(workspace).childrenOf(parentId)
}

/** 某季度的目标（`kind === objective && okr.period === period`），已排序。 */
public func objectivesOfPeriod(workspace: OkrWorkspace, period: String): Array<OkrItem> {
    OkrIndex(workspace).objectivesOf(period)
}
