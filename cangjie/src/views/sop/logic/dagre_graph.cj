/**
 * dagre `Graph`（graphlib）的最小忠实移植：节点/边标签、插入序邻接表、复合父子关系。
 *
 * 为什么要自己实现而不是用 `std.collection.HashMap` 直接跑算法：dagre 的多处平局判定
 * 依赖 **插入顺序**（`nodes()` / `edges()` / `inEdges()` / `outEdges()` / `predecessors()`），
 * 而仓颉 `HashMap` 无序。这里用「有序数组 + 哈希索引」保留 graphlib 的迭代语义，
 * 从而保证相同的节点/边顺序产出相同的坐标（本包只做布局，不需要边的 name 语义，
 * 但多边与反向边仍然按 name 区分）。
 */
package textura.views.sop.logic

import std.collection.*

let DAGRE_ID_SEP: String = "~@~"

/** 节点标签（可变对象，跨图共享引用——dagre 的 simplify/layer graph 依赖这一点）。 */
class DgNode {
    let id: String
    var width: Float64 = 0.0
    var height: Float64 = 0.0
    /** 是否已分配 rank（对应 `Object.hasOwn(node, "rank")`） */
    var hasRank: Bool = false
    var rank: Int64 = 0
    var order: Int64 = 0
    /** "" = 真实节点；"edge" = 跨层边的 dummy；"root"/"border"/"edge-label"/"selfedge" */
    var dummy: String = ""
    var x: Float64 = 0.0
    var y: Float64 = 0.0
    var alive: Bool = true
    /** 复合图的 minRank/maxRank（本包平面图不使用，保留字段以对齐语义） */
    /** 只有 edge-label dummy 才有非空 labelpos；其余节点为空（对应 JS 的 hasOwn 判断）。 */
    var labelpos: String = ""
    var minRank: Int64 = 0
    var maxRank: Int64 = 0
    var hasMinRank: Bool = false

    init(id: String) {
        this.id = id
    }
}

/** 边标签。 */
class DgEdge {
    let id: String
    let from: String
    let to: String
    let name: String
    var weight: Float64 = 1.0
    var minlen: Int64 = 1
    var width: Float64 = 0.0
    var height: Float64 = 0.0
    var labeloffset: Float64 = 10.0
    var labelpos: String = "r"
    var hasLabelRank: Bool = false
    var labelRank: Int64 = 0
    var reversed: Bool = false
    var forwardName: String = ""
    var alive: Bool = true

    init(id: String, from: String, to: String, name: String) {
        this.id = id
        this.from = from
        this.to = to
        this.name = name
    }
}

func dgEdgeId(directed: Bool, from: String, to: String, name: String): String {
    var v = from
    var w = to
    if (!directed && v > w) {
        let swap = v
        v = w
        w = swap
    }
    return "${v}${DAGRE_ID_SEP}${w}${DAGRE_ID_SEP}${name}"
}

/** 有向/无向、简单/多重、平面/复合图（只实现布局用到的能力）。 */
class DgGraph {
    let directed: Bool
    let multigraph: Bool
    let compound: Bool

    // ---- graph label（dagre buildLayoutGraph 里的白名单字段） ----
    var rankdir: String = "tb"
    var nodesep: Float64 = 50.0
    var edgesep: Float64 = 20.0
    var ranksep: Float64 = 50.0
    var marginx: Float64 = 0.0
    var marginy: Float64 = 0.0
    var align: String = ""
    var nodeRankFactor: Int64 = 1
    var graphWidth: Float64 = 0.0
    var graphHeight: Float64 = 0.0
    var nestingRoot: String = ""
    var hasNestingRoot: Bool = false
    /** 层图（order 阶段）的合成根节点 id。 */
    var rootNodeId: String = ""
    /** 新建节点时共享标签的来源图（对应 dagre `setDefaultNodeLabel(v => g.node(v))`）。 */
    var labelSource: ?DgGraph = None
    var dummyChains: ArrayList<String> = ArrayList<String>()

    // ---- 存储 ----
    var nodeOrder: ArrayList<String> = ArrayList<String>()
    var nodeMap: HashMap<String, DgNode> = HashMap<String, DgNode>()
    var edgeOrder: ArrayList<String> = ArrayList<String>()
    var edgeMap: HashMap<String, DgEdge> = HashMap<String, DgEdge>()
    var outAdj: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()
    var inAdj: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()
    var predList: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()
    var prevList: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()
    var parentMap: HashMap<String, String> = HashMap<String, String>()
    var childMap: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()

    init(directed!: Bool = true, multigraph!: Bool = false, compound!: Bool = false) {
        this.directed = directed
        this.multigraph = multigraph
        this.compound = compound
    }

    // ---- 节点 ----

    func node(id: String): DgNode {
        return nodeMap[id]
    }

    func hasNode(id: String): Bool {
        let found = nodeMap.get(id)
        if (found.isNone()) {
            return false
        }
        return found.getOrThrow().alive
    }

    func setNode(id: String): Unit {
        setNodeSized(id, 0.0, 0.0, "")
    }

    func setNodeSized(id: String, width: Float64, height: Float64, dummy: String): Unit {
        let existing = nodeMap.get(id)
        if (existing.isSome()) {
            return
        }
        // 层图里的邻居节点复用基础图标签对象（dagre 默认节点标签语义）。
        if (labelSource.isSome() && labelSource.getOrThrow().hasNode(id)) {
            setNodeShared(id, labelSource.getOrThrow().node(id))
            return
        }
        let node = DgNode(id)
        node.width = width
        node.height = height
        node.dummy = dummy
        nodeMap[id] = node
        nodeOrder.add(id)
        outAdj[id] = ArrayList<String>()
        inAdj[id] = ArrayList<String>()
        predList[id] = ArrayList<String>()
        prevList[id] = ArrayList<String>()
        if (compound) {
            parentMap[id] = ""
            childMap[id] = ArrayList<String>()
            if (!childMap.contains("")) {
                childMap[""] = ArrayList<String>()
            }
            childMap[""].add(id)
        }
    }

    /** 插入一个**共享**标签对象的节点（dagre 层图依赖共享，使 order 写回基础图）。 */
    func setNodeShared(id: String, label: DgNode): Unit {
        if (nodeMap.contains(id)) {
            return
        }
        nodeMap[id] = label
        nodeOrder.add(id)
        outAdj[id] = ArrayList<String>()
        inAdj[id] = ArrayList<String>()
        predList[id] = ArrayList<String>()
        prevList[id] = ArrayList<String>()
        if (compound) {
            parentMap[id] = ""
            childMap[id] = ArrayList<String>()
            if (!childMap.contains("")) {
                childMap[""] = ArrayList<String>()
            }
            childMap[""].add(id)
        }
    }

    func removeNode(id: String): Unit {
        let found = nodeMap.get(id)
        if (found.isNone()) {
            return
        }
        let node = found.getOrThrow()
        if (!node.alive) {
            return
        }
        // 移除关联边（先拷贝边 id 列表，避免遍历中修改）
        let incident = ArrayList<String>(outAdj.get(id) ?? ArrayList<String>())
        for (edgeId in inAdj.get(id) ?? ArrayList<String>()) {
            incident.add(edgeId)
        }
        for (edgeId in incident) {
            removeEdge(edgeId)
        }
        node.alive = false
        if (compound) {
            let parent = parentOf(id)
            let siblings = childMap.get(parent) ?? ArrayList<String>()
            removeString(siblings, id)
            childMap[parent] = siblings
        }
    }

    func nodes(): ArrayList<String> {
        let result = ArrayList<String>()
        for (id in nodeOrder) {
            if (nodeMap[id].alive) {
                result.add(id)
            }
        }
        return result
    }

    func nodeCount(): Int64 {
        var count = 0
        for (id in nodeOrder) {
            if (nodeMap[id].alive) {
                count += 1
            }
        }
        return count
    }

    func sources(): ArrayList<String> {
        let result = ArrayList<String>()
        for (id in nodes()) {
            if (predList[id].size == 0) {
                result.add(id)
            }
        }
        return result
    }

        // ---- 复合 ----

    func parentOf(id: String): String {
        let parent = parentMap.get(id)
        if (parent.isSome()) {
            return parent.getOrThrow()
        }
        return ""
    }

    func setParent(id: String, parent: String): Unit {
        if (!compound) {
            return
        }
        setNode(id)
        if (!parent.isEmpty()) {
            setNode(parent)
        }
        let oldParent = parentOf(id)
        let oldSiblings = childMap.get(oldParent) ?? ArrayList<String>()
        removeString(oldSiblings, id)
        childMap[oldParent] = oldSiblings
        if (!childMap.contains(parent)) {
            childMap[parent] = ArrayList<String>()
        }
        childMap[parent].add(id)
        parentMap[id] = parent
    }

    /** `children("")` = 根节点下的所有节点。 */
    func children(id: String): ArrayList<String> {
        let result = ArrayList<String>()
        if (!compound) {
            if (!id.isEmpty() && hasNode(id)) {
                return result
            }
            return nodes()
        }
        let kids = childMap.get(id) ?? ArrayList<String>()
        for (child in kids) {
            if (nodeMap[child].alive) {
                result.add(child)
            }
        }
        return result
    }

    // ---- 边 ----

    func edgeByName(from: String, to: String, name: String): ?DgEdge {
        let found = edgeMap.get(dgEdgeId(directed, from, to, name))
        if (found.isNone()) {
            return None
        }
        let edge = found.getOrThrow()
        if (!edge.alive) {
            return None
        }
        return Some(edge)
    }

    func hasEdge(from: String, to: String): Bool {
        return edgeByName(from, to, "").isSome()
    }

    func edgeById(id: String): ?DgEdge {
        let found = edgeMap.get(id)
        if (found.isNone() || !found.getOrThrow().alive) {
            return None
        }
        return found
    }

    /** 对应 graphlib `setEdge(v, w, label, name)`（同 id 时更新标签）。 */
    func setEdge(from: String, to: String, name: String, weight: Float64, minlen: Int64): DgEdge {
        setNode(from)
        setNode(to)
        let id = dgEdgeId(directed, from, to, name)
        let existing = edgeMap.get(id)
        if (existing.isSome()) {
            let edge = existing.getOrThrow()
            edge.weight = weight
            edge.minlen = minlen
            return edge
        }
        var v = from
        var w = to
        if (!directed && v > w) {
            let swap = v
            v = w
            w = swap
        }
        let edge = DgEdge(id, v, w, name)
        edge.weight = weight
        edge.minlen = minlen
        edgeMap[id] = edge
        edgeOrder.add(id)
        outAdj[v].add(id)
        inAdj[w].add(id)
        addNeighbor(predList, w, v)
        addNeighbor(prevList, v, w)
        return edge
    }

    func removeEdge(id: String): Unit {
        let found = edgeMap.get(id)
        if (found.isNone()) {
            return
        }
        let edge = found.getOrThrow()
        if (!edge.alive) {
            return
        }
        edge.alive = false
        removeString(outAdj[edge.from], id)
        removeString(inAdj[edge.to], id)
        removeNeighbor(predList, edge.to, edge.from)
        removeNeighbor(prevList, edge.from, edge.to)
    }

    func edges(): ArrayList<String> {
        let result = ArrayList<String>()
        for (id in edgeOrder) {
            if (edgeMap[id].alive) {
                result.add(id)
            }
        }
        return result
    }

        func outEdges(v: String): ArrayList<DgEdge> {
        let result = ArrayList<DgEdge>()
        for (id in outAdj.get(v) ?? ArrayList<String>()) {
            let edge = edgeMap[id]
            if (edge.alive) {
                result.add(edge)
            }
        }
        return result
    }

    func inEdges(v: String): ArrayList<DgEdge> {
        let result = ArrayList<DgEdge>()
        for (id in inAdj.get(v) ?? ArrayList<String>()) {
            let edge = edgeMap[id]
            if (edge.alive) {
                result.add(edge)
            }
        }
        return result
    }

    /** graphlib 语义：inEdges 在前，outEdges 在后。 */
    func nodeEdges(v: String): ArrayList<DgEdge> {
        let result = inEdges(v)
        for (edge in outEdges(v)) {
            result.add(edge)
        }
        return result
    }

    func predecessors(v: String): ArrayList<String> {
        return neighborsOf(predList, v)
    }

    func successors(v: String): ArrayList<String> {
        return neighborsOf(prevList, v)
    }

    /** 无向图用：preds ∪ sucs（preds 在前，去重）。 */
        func neighborsOf(list: HashMap<String, ArrayList<String>>, v: String): ArrayList<String> {
        let result = ArrayList<String>()
        for (id in list.get(v) ?? ArrayList<String>()) {
            let found = nodeMap.get(id)
            if (found.isSome() && found.getOrThrow().alive) {
                result.add(id)
            }
        }
        return result
    }
}

func addNeighbor(list: HashMap<String, ArrayList<String>>, owner: String, neighbor: String): Unit {
    if (!list.contains(owner)) {
        list[owner] = ArrayList<String>()
    }
    let existing = list[owner]
    if (!dgContains(existing, neighbor)) {
        existing.add(neighbor)
    }
}

func removeNeighbor(list: HashMap<String, ArrayList<String>>, owner: String, neighbor: String): Unit {
    if (!list.contains(owner)) {
        return
    }
    let existing = list[owner]
    removeString(existing, neighbor)
}

func dgContains(values: ArrayList<String>, target: String): Bool {
    for (value in values) {
        if (value == target) {
            return true
        }
    }
    return false
}

func removeString(values: ArrayList<String>, target: String): Bool {
    for (index in 0..values.size) {
        if (values[index] == target) {
            values.remove(at: index)
            return true
        }
    }
    return false
}
