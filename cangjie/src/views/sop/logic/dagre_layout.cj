/**
 * dagre 布局流水线的逐模块移植（@dagrejs/dagre 1.1.8 的默认路径）。
 *
 * 与 Web 版一致地执行：makeSpaceForEdgeLabels → removeSelfEdges → acyclic(dfsFAS)
 * → nestingGraph(根节点) → rank(network-simplex) → removeEmptyRanks → normalizeRanks
 * → normalize(dummy 链) → order(barycenter 4 轮 + 交叉计数择优) → coordinateSystem
 * → position(positionY + Brandes-Köpf positionX) → normalize.undo(移除 dummy)
 * → translateGraph。
 *
 * 本包只服务平面图（无子图）：compound 子图 / 边框节点 / 自环 / 边标签代理等分支
 * 在本仓数据下不可达，因此不移植（见 docs/SOP-LOGIC.md 的说明）。
 */
package textura.views.sop.logic

import std.collection.*
import std.sort.*

/** 与 dagre `util.uniqueId` 等价、但每次布局独立计数的 id 生成器（保证可重复）。 */
class DagreIds {
    var counter: Int64 = 0

    func next(prefix: String): String {
        counter += 1
        return "${prefix}${counter}"
    }
}

// ---------------------------------------------------------------------------
// 基础工具
// ---------------------------------------------------------------------------

func dgPop(values: ArrayList<String>): ?String {
    if (values.size == 0) {
        return None
    }
    return Some(values.remove(at: values.size - 1))
}

func dgSlack(g: DgGraph, edge: DgEdge): Int64 {
    return g.node(edge.to).rank - g.node(edge.from).rank - edge.minlen
}

func dgMaxRank(g: DgGraph): Int64 {
    var maxRank = Int64.Min
    for (id in g.nodes()) {
        let node = g.node(id)
        if (node.hasRank && node.rank > maxRank) {
            maxRank = node.rank
        }
    }
    if (maxRank == Int64.Min) {
        return 0
    }
    return maxRank
}

/** 对应 dagre `util.buildLayerMatrix`：`matrix[rank][order] = node`。 */
func dgBuildLayerMatrix(g: DgGraph): ArrayList<ArrayList<String>> {
    let nodeIds = g.nodes()
    let rankCount = dgMaxRank(g) + 1
    let matrix = ArrayList<ArrayList<String>>()
    for (_ in 0..rankCount) {
        matrix.add(ArrayList<String>())
    }
    // 先按 order 求每层宽度，再填满（避免稀疏数组语义）
    for (id in nodeIds) {
        let node = g.node(id)
        if (!node.hasRank) {
            continue
        }
        let layer = matrix[node.rank]
        while (layer.size <= node.order) {
            layer.add("")
        }
        layer[node.order] = id
    }
    return matrix
}

/** 层矩阵的稠密视图（去掉空串占位），供遍历型算法使用。 */
func dgDenseLayer(layer: ArrayList<String>): ArrayList<String> {
    let result = ArrayList<String>()
    for (id in layer) {
        if (!id.isEmpty()) {
            result.add(id)
        }
    }
    return result
}

// ---------------------------------------------------------------------------
// acyclic：DFS 回边反向（dagre `acyclic.run` 的 dfsFAS 分支）
// ---------------------------------------------------------------------------

func dgAcyclicRun(g: DgGraph, ids: DagreIds): Unit {
    let fas = dgDfsFas(g)
    for (edgeId in fas) {
        let edge = g.edgeById(edgeId).getOrThrow()
        let from = edge.from
        let to = edge.to
        let name = edge.name
        let weight = edge.weight
        let minlen = edge.minlen
        var width = edge.width
        var height = edge.height
        var labeloffset = edge.labeloffset
        var labelpos = edge.labelpos
        let hasLabelRank = edge.hasLabelRank
        let labelRank = edge.labelRank
        g.removeEdge(edgeId)
        let reversedEdge = g.setEdge(to, from, ids.next("rev"), weight, minlen)
        reversedEdge.width = width
        reversedEdge.height = height
        reversedEdge.labeloffset = labeloffset
        reversedEdge.labelpos = labelpos
        reversedEdge.hasLabelRank = hasLabelRank
        reversedEdge.labelRank = labelRank
        reversedEdge.reversed = true
        reversedEdge.forwardName = name
    }
}

func dgDfsFas(g: DgGraph): ArrayList<String> {
    let fas = ArrayList<String>()
    let visited = HashMap<String, Bool>()
    let onStack = HashMap<String, Bool>()
    for (id in g.nodes()) {
        dgDfsFasVisit(g, id, visited, onStack, fas)
    }
    return fas
}

func dgDfsFasVisit(
    g: DgGraph,
    v: String,
    visited: HashMap<String, Bool>,
    onStack: HashMap<String, Bool>,
    fas: ArrayList<String>
): Unit {
    if (visited.contains(v)) {
        return
    }
    visited[v] = true
    onStack[v] = true
    for (edge in g.outEdges(v)) {
        if (onStack.contains(edge.to)) {
            fas.add(edge.id)
        } else {
            dgDfsFasVisit(g, edge.to, visited, onStack, fas)
        }
    }
    onStack.remove(v)
}

// ---------------------------------------------------------------------------
// nestingGraph：为平面图补一个连接所有节点的根（nodeSep = 1）
// ---------------------------------------------------------------------------

func dgNestingRun(g: DgGraph, ids: DagreIds): Unit {
    let root = ids.next("_root")
    g.setNodeSized(root, 0.0, 0.0, "root")
    g.nestingRoot = root
    g.hasNestingRoot = true
    g.nodeRankFactor = 1
    // 平面图：所有节点都是顶层子节点，height = 0 → nodeSep = 1，minlen 不变。
    let children = g.children("")
    for (child in children) {
        if (child == root) {
            continue
        }
        g.setEdge(root, child, "", 0.0, 1)
    }
}

func dgNestingCleanup(g: DgGraph): Unit {
    if (!g.hasNestingRoot) {
        return
    }
    let root = g.nestingRoot
    g.removeNode(root)
    g.hasNestingRoot = false
}

// ---------------------------------------------------------------------------
// rank：network-simplex（simplify → longestPath → feasibleTree → 迭代换边）
// ---------------------------------------------------------------------------

/** 树种节点标签（low/lim/parent）。 */
class DgTreeLabel {
    var low: Int64 = 0
    var lim: Int64 = 0
    var parent: String = ""
    var hasParent: Bool = false
}

class DgTreeEdge {
    let from: String
    let to: String
    var cutvalue: Float64 = 0.0

    init(from: String, to: String) {
        this.from = from
        this.to = to
    }
}

/** 无向树（对应 graphlib `new Graph({directed: false})`）。 */
class DgTree {
    var nodeOrder: ArrayList<String> = ArrayList<String>()
    var nodeMap: HashMap<String, DgTreeLabel> = HashMap<String, DgTreeLabel>()
    var edgeOrder: ArrayList<String> = ArrayList<String>()
    var edgeMap: HashMap<String, DgTreeEdge> = HashMap<String, DgTreeEdge>()
    var lowAdj: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()
    var highAdj: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()

    func hasNode(id: String): Bool {
        return nodeMap.contains(id)
    }

    func node(id: String): DgTreeLabel {
        return nodeMap[id]
    }

    func setNode(id: String): Unit {
        if (nodeMap.contains(id)) {
            return
        }
        nodeMap[id] = DgTreeLabel()
        nodeOrder.add(id)
        lowAdj[id] = ArrayList<String>()
        highAdj[id] = ArrayList<String>()
    }

    func nodes(): ArrayList<String> {
        return ArrayList<String>(nodeOrder)
    }

    func nodeCount(): Int64 {
        return nodeOrder.size
    }

    func edgeKey(from: String, to: String): String {
        if (from > to) {
            return "${to}${DAGRE_ID_SEP}${from}"
        }
        return "${from}${DAGRE_ID_SEP}${to}"
    }

    func hasEdge(from: String, to: String): Bool {
        return edgeMap.contains(edgeKey(from, to))
    }

    func edge(from: String, to: String): DgTreeEdge {
        return edgeMap[edgeKey(from, to)]
    }

    func setEdge(from: String, to: String): Unit {
        setNode(from)
        setNode(to)
        let key = edgeKey(from, to)
        if (edgeMap.contains(key)) {
            return
        }
        var u = from
        var w = to
        if (u > w) {
            let swap = u
            u = w
            w = swap
        }
        let edge = DgTreeEdge(u, w)
        edgeMap[key] = edge
        edgeOrder.add(key)
        highAdj[u].add(w)
        lowAdj[w].add(u)
    }

    func removeEdge(from: String, to: String): Unit {
        let key = edgeKey(from, to)
        if (!edgeMap.contains(key)) {
            return
        }
        let edge = edgeMap[key]
        edgeMap.remove(key)
        removeString(edgeOrder, key)
        removeString(highAdj[edge.from], edge.to)
        removeString(lowAdj[edge.to], edge.from)
    }

    func edges(): ArrayList<DgTreeEdge> {
        let result = ArrayList<DgTreeEdge>()
        for (key in edgeOrder) {
            result.add(edgeMap[key])
        }
        return result
    }

    /** graphlib 无向图语义：先 predecessors（对方 id 更小的边），再 successors。 */
    func neighbors(id: String): ArrayList<String> {
        let result = ArrayList<String>(lowAdj.get(id) ?? ArrayList<String>())
        for (other in highAdj.get(id) ?? ArrayList<String>()) {
            result.add(other)
        }
        return result
    }

    }

/** 对应 dagre `util.simplify`：合并平行边（权重相加、minlen 取大）。 */
func dgSimplify(g: DgGraph): DgGraph {
    let result = DgGraph()
    for (id in g.nodes()) {
        result.setNodeShared(id, g.node(id))
    }
    for (edgeId in g.edges()) {
        let edge = g.edgeById(edgeId).getOrThrow()
        let existing = result.edgeByName(edge.from, edge.to, "")
        var weight = edge.weight
        var minlen = edge.minlen
        if (existing.isSome()) {
            weight += existing.getOrThrow().weight
            if (existing.getOrThrow().minlen > minlen) {
                minlen = existing.getOrThrow().minlen
            }
        }
        result.setEdge(edge.from, edge.to, "", weight, minlen)
    }
    return result
}

class DgLongestPathState {
    let g: DgGraph
    let visited: HashMap<String, Bool> = HashMap<String, Bool>()

    init(g: DgGraph) {
        this.g = g
    }
}

func dgLongestPath(g: DgGraph): Unit {
    let state = DgLongestPathState(g)
    for (source in g.sources()) {
        dgLongestPathVisit(state, source)
    }
}

func dgLongestPathVisit(state: DgLongestPathState, v: String): Int64 {
    let node = state.g.node(v)
    if (state.visited.contains(v)) {
        return node.rank
    }
    state.visited[v] = true
    var rank = Int64.Max
    for (edge in state.g.outEdges(v)) {
        let candidate = dgLongestPathVisit(state, edge.to) - edge.minlen
        if (candidate < rank) {
            rank = candidate
        }
    }
    if (rank == Int64.Max) {
        rank = 0
    }
    node.rank = rank
    node.hasRank = true
    return rank
}

func dgTightTreeCount(t: DgTree, g: DgGraph): Int64 {
    let snapshot = t.nodes()
    for (id in snapshot) {
        dgTightTreeVisit(t, g, id)
    }
    return t.nodeCount()
}

func dgTightTreeVisit(t: DgTree, g: DgGraph, v: String): Unit {
    for (edge in g.nodeEdges(v)) {
        let other = if (v == edge.from) {
            edge.to
        } else {
            edge.from
        }
        if (!t.hasNode(other) && dgSlack(g, edge) == 0) {
            t.setNode(other)
            t.setEdge(v, other)
            dgTightTreeVisit(t, g, other)
        }
    }
}

func dgFindMinSlackEdge(t: DgTree, g: DgGraph): DgEdge {
    var bestSlack = Float64.Inf
    var best: ?DgEdge = None
    for (edgeId in g.edges()) {
        let edge = g.edgeById(edgeId).getOrThrow()
        var edgeSlack = Float64.Inf
        if (t.hasNode(edge.from) != t.hasNode(edge.to)) {
            edgeSlack = Float64(dgSlack(g, edge))
        }
        if (edgeSlack < bestSlack) {
            bestSlack = edgeSlack
            best = Some(edge)
        }
    }
    return best.getOrThrow()
}

func dgFeasibleTree(g: DgGraph): DgTree {
    let tree = DgTree()
    let nodes = g.nodes()
    tree.setNode(nodes[0])
    let size = g.nodeCount()
    while (dgTightTreeCount(tree, g) < size) {
        let edge = dgFindMinSlackEdge(tree, g)
        let slack = dgSlack(g, edge)
        let delta = if (tree.hasNode(edge.from)) {
            slack
        } else {
            -slack
        }
        for (id in tree.nodes()) {
            let node = g.node(id)
            node.rank += delta
        }
    }
    return tree
}

class DgLimState {
    var nextLim: Int64 = 1
}

func dgInitLowLimValues(tree: DgTree): Unit {
    let root = tree.nodes()[0]
    let state = DgLimState()
    let visited = HashMap<String, Bool>()
    dgAssignLowLim(tree, visited, state, root, "")
}

func dgAssignLowLim(
    tree: DgTree,
    visited: HashMap<String, Bool>,
    state: DgLimState,
    v: String,
    parent: String
): Unit {
    let low = state.nextLim
    visited[v] = true
    for (w in tree.neighbors(v)) {
        if (!visited.contains(w)) {
            dgAssignLowLim(tree, visited, state, w, v)
        }
    }
    let label = tree.node(v)
    label.low = low
    label.lim = state.nextLim
    state.nextLim += 1
    if (!parent.isEmpty()) {
        label.parent = parent
        label.hasParent = true
    } else {
        label.parent = ""
        label.hasParent = false
    }
}

func dgInitCutValues(tree: DgTree, g: DgGraph): Unit {
    let order = dgTreePostorder(tree, tree.nodes())
    if (order.size == 0) {
        return
    }
    for (index in 0..(order.size - 1)) {
        dgAssignCutValue(tree, g, order[index])
    }
}

func dgAssignCutValue(tree: DgTree, g: DgGraph, child: String): Unit {
    let parent = tree.node(child).parent
    tree.edge(child, parent).cutvalue = dgCalcCutValue(tree, g, child)
}

func dgCalcCutValue(tree: DgTree, g: DgGraph, child: String): Float64 {
    let parent = tree.node(child).parent
    var childIsTail = true
    var graphEdge = g.edgeByName(child, parent, "")
    var cutValue = 0.0
    if (graphEdge.isNone()) {
        childIsTail = false
        graphEdge = g.edgeByName(parent, child, "")
    }
    cutValue = graphEdge.getOrThrow().weight
    for (edge in g.nodeEdges(child)) {
        let isOutEdge = edge.from == child
        let other = if (isOutEdge) {
            edge.to
        } else {
            edge.from
        }
        if (other != parent) {
            let pointsToHead = isOutEdge == childIsTail
            let otherWeight = edge.weight
            cutValue += if (pointsToHead) {
                otherWeight
            } else {
                -otherWeight
            }
            if (tree.hasEdge(child, other)) {
                let otherCutValue = tree.edge(child, other).cutvalue
                cutValue += if (pointsToHead) {
                    -otherCutValue
                } else {
                    otherCutValue
                }
            }
        }
    }
    return cutValue
}

func dgIsDescendant(vLabel: DgTreeLabel, rootLabel: DgTreeLabel): Bool {
    return rootLabel.low <= vLabel.lim && vLabel.lim <= rootLabel.lim
}

func dgLeaveEdge(tree: DgTree): ?DgTreeEdge {
    for (edge in tree.edges()) {
        if (edge.cutvalue < 0.0) {
            return Some(edge)
        }
    }
    return None
}

func dgEnterEdge(tree: DgTree, g: DgGraph, edge: DgTreeEdge): DgEdge {
    var v = edge.from
    var w = edge.to
    if (!g.hasEdge(v, w)) {
        let swap = v
        v = w
        w = swap
    }
    let vLabel = tree.node(v)
    let wLabel = tree.node(w)
    var tailLabel = vLabel
    var flip = false
    if (vLabel.lim > wLabel.lim) {
        tailLabel = wLabel
        flip = true
    }
    var best: ?DgEdge = None
    var bestSlack = Int64.Max
    for (edgeId in g.edges()) {
        let candidate = g.edgeById(edgeId).getOrThrow()
        let fromDescendant = dgIsDescendant(tree.node(candidate.from), tailLabel)
        let toDescendant = dgIsDescendant(tree.node(candidate.to), tailLabel)
        if (flip != fromDescendant) {
            continue
        }
        if (flip == toDescendant) {
            continue
        }
        let slack = dgSlack(g, candidate)
        if (best.isNone() || slack < bestSlack) {
            best = Some(candidate)
            bestSlack = slack
        }
    }
    return best.getOrThrow()
}

func dgExchangeEdges(tree: DgTree, g: DgGraph, leaving: DgTreeEdge, entering: DgEdge): Unit {
    tree.removeEdge(leaving.from, leaving.to)
    tree.setEdge(entering.from, entering.to)
    dgInitLowLimValues(tree)
    dgInitCutValues(tree, g)
    dgUpdateRanks(tree, g)
}

func dgUpdateRanks(tree: DgTree, g: DgGraph): Unit {
    let root = tree.nodes()[0]
    let order = dgTreePreorder(tree, root)
    for (index in 1..order.size) {
        let v = order[index]
        let parent = tree.node(v).parent
        var edge = g.edgeByName(v, parent, "")
        var flipped = false
        if (edge.isNone()) {
            edge = g.edgeByName(parent, v, "")
            flipped = true
        }
        let minlen = edge.getOrThrow().minlen
        g.node(v).rank = g.node(parent).rank + (if (flipped) {
            minlen
        } else {
            -minlen
        })
        g.node(v).hasRank = true
    }
}

/** graphlib `alg.preorder`：栈内逆序压入邻居。 */
func dgTreePreorder(tree: DgTree, root: String): ArrayList<String> {
    let result = ArrayList<String>()
    let visited = HashMap<String, Bool>()
    let stack = ArrayList<String>()
    stack.add(root)
    while (stack.size > 0) {
        let current = dgPop(stack).getOrThrow()
        if (visited.contains(current)) {
            continue
        }
        visited[current] = true
        result.add(current)
        let neighbors = tree.neighbors(current)
        var index = neighbors.size - 1
        while (index >= 0) {
            stack.add(neighbors[index])
            index -= 1
        }
    }
    return result
}

/** graphlib `alg.postorder`。 */
func dgTreePostorder(tree: DgTree, roots: ArrayList<String>): ArrayList<String> {
    let result = ArrayList<String>()
    let visited = HashMap<String, Bool>()
    for (root in roots) {
        // 栈元素：(节点 id, 是否展开完成)；用两个并行栈模拟。
        let stackId = ArrayList<String>()
        let stackDone = ArrayList<Bool>()
        stackId.add(root)
        stackDone.add(false)
        while (stackId.size > 0) {
            let current = dgPop(stackId).getOrThrow()
            let done = dgPopBool(stackDone).getOrThrow()
            if (done) {
                result.add(current)
                continue
            }
            if (visited.contains(current)) {
                continue
            }
            visited[current] = true
            stackId.add(current)
            stackDone.add(true)
            let neighbors = tree.neighbors(current)
            var index = neighbors.size - 1
            while (index >= 0) {
                stackId.add(neighbors[index])
                stackDone.add(false)
                index -= 1
            }
        }
    }
    return result
}

func dgPopBool(values: ArrayList<Bool>): ?Bool {
    if (values.size == 0) {
        return None
    }
    return Some(values.remove(at: values.size - 1))
}

func dgNetworkSimplex(g: DgGraph): Unit {
    let simplified = dgSimplify(g)
    dgLongestPath(simplified)
    let tree = dgFeasibleTree(simplified)
    dgInitLowLimValues(tree)
    dgInitCutValues(tree, simplified)
    while (true) {
        let leaving = dgLeaveEdge(tree)
        if (leaving.isNone()) {
            break
        }
        let edge = leaving.getOrThrow()
        let entering = dgEnterEdge(tree, simplified, edge)
        dgExchangeEdges(tree, simplified, edge, entering)
    }
}

// ---------------------------------------------------------------------------
// ranks 归一化 / removeEmptyRanks
// ---------------------------------------------------------------------------

func dgNormalizeRanks(g: DgGraph): Unit {
    var minRank = Int64.Max
    for (id in g.nodes()) {
        let node = g.node(id)
        if (node.hasRank && node.rank < minRank) {
            minRank = node.rank
        }
    }
    if (minRank == Int64.Max || minRank == 0) {
        return
    }
    for (id in g.nodes()) {
        let node = g.node(id)
        if (node.hasRank) {
            node.rank -= minRank
        }
    }
}

func dgRemoveEmptyRanks(g: DgGraph): Unit {
    let nodeIds = g.nodes()
    if (nodeIds.size == 0) {
        return
    }
    var offset = Int64.Max
    for (id in nodeIds) {
        let rank = g.node(id).rank
        if (rank < offset) {
            offset = rank
        }
    }
    var maxRank = 0
    for (id in nodeIds) {
        let rank = g.node(id).rank - offset
        if (rank > maxRank) {
            maxRank = rank
        }
    }
    let layers = ArrayList<ArrayList<String>>()
    for (_ in 0..(maxRank + 1)) {
        layers.add(ArrayList<String>())
    }
    for (id in nodeIds) {
        layers[g.node(id).rank - offset].add(id)
    }
    var delta = 0
    let nodeRankFactor = g.nodeRankFactor
    for (index in 0..layers.size) {
        let layer = layers[index]
        if (layer.size == 0 && index % nodeRankFactor != 0) {
            delta -= 1
        } else if (layer.size > 0 && delta != 0) {
            for (id in layer) {
                g.node(id).rank += delta
            }
        }
    }
}

// ---------------------------------------------------------------------------
// normalize：跨层边切成 dummy 链
// ---------------------------------------------------------------------------

func dgNormalizeRun(g: DgGraph, ids: DagreIds): Unit {
    g.dummyChains = ArrayList<String>()
    let edgeIds = g.edges()
    for (edgeId in edgeIds) {
        dgNormalizeEdge(g, edgeId, ids)
    }
}

func dgNormalizeEdge(g: DgGraph, edgeId: String, ids: DagreIds): Unit {
    let edgeOpt = g.edgeById(edgeId)
    if (edgeOpt.isNone()) {
        return
    }
    let edge = edgeOpt.getOrThrow()
    let from = edge.from
    let to = edge.to
    var fromRank = g.node(from).rank
    let toRank = g.node(to).rank
    let name = edge.name
    let weight = edge.weight
    if (toRank == fromRank + 1) {
        return
    }
    g.removeEdge(edgeId)
    var v = from
    var index = 0
    while (fromRank + 1 < toRank) {
        fromRank += 1
        let dummy = ids.next("_d")
        g.setNodeSized(dummy, 0.0, 0.0, "edge")
        g.node(dummy).rank = fromRank
        g.node(dummy).hasRank = true
        g.setEdge(v, dummy, name, weight, 1)
        if (index == 0) {
            g.dummyChains.add(dummy)
        }
        v = dummy
        index += 1
    }
    g.setEdge(v, to, name, weight, 1)
}

// parentDummyChains：平面图里所有节点的父节点都是根，dagre 的循环只会把 dummy 的父节点
// 重新设为根（等价于无操作），因此不移植该遍历。

// ---------------------------------------------------------------------------
// order：initOrder + barycenter 扫描 + 交叉计数择优
// ---------------------------------------------------------------------------

func dgAssignOrder(g: DgGraph, layering: ArrayList<ArrayList<String>>): Unit {
    for (layer in layering) {
        for (index in 0..layer.size) {
            if (!layer[index].isEmpty()) {
                g.node(layer[index]).order = index
            }
        }
    }
}

func dgInitOrder(g: DgGraph): ArrayList<ArrayList<String>> {
    let visited = HashMap<String, Bool>()
    let maxRank = dgMaxRank(g)
    let layers = ArrayList<ArrayList<String>>()
    for (_ in 0..(maxRank + 1)) {
        layers.add(ArrayList<String>())
    }
    let simpleNodes = g.nodes()
    // 稳定排序：按 rank 升序，等秩保持插入顺序（与 JS Array.prototype.sort 一致）。
    let rankOf = HashMap<String, Int64>()
    for (id in simpleNodes) {
        let node = g.node(id)
        rankOf[id] = if (node.hasRank) {
            node.rank
        } else {
            Int64.Max
        }
    }
    sort(
        simpleNodes,
        lessThan: {
            left, right => if (rankOf[left] != rankOf[right]) {
                rankOf[left] < rankOf[right]
            } else {
                false
            }
        },
        stable: true
    )
    for (id in simpleNodes) {
        dgInitOrderVisit(g, id, visited, layers)
    }
    return layers
}

func dgInitOrderVisit(
    g: DgGraph,
    v: String,
    visited: HashMap<String, Bool>,
    layers: ArrayList<ArrayList<String>>
): Unit {
    if (visited.contains(v)) {
        return
    }
    visited[v] = true
    let node = g.node(v)
    layers[node.rank].add(v)
    for (successor in g.successors(v)) {
        dgInitOrderVisit(g, successor, visited, layers)
    }
}

func dgTwoLayerCrossCount(g: DgGraph, north: ArrayList<String>, south: ArrayList<String>): Float64 {
    let southPos = HashMap<String, Int64>()
    for (index in 0..south.size) {
        southPos[south[index]] = index
    }
    // 每条北层节点的出边：(南层位置, 权重)，按位置升序（稳定）。
    let entries = ArrayList<(Int64, Float64)>()
    for (v in north) {
        let local = ArrayList<(Int64, Float64)>()
        for (edge in g.outEdges(v)) {
            let pos = southPos.get(edge.to) ?? 0
            local.add((pos, edge.weight))
        }
        sort(local, lessThan: {left, right => left[0] < right[0]}, stable: true)
        for (entry in local) {
            entries.add(entry)
        }
    }
    var firstIndex = 1
    while (firstIndex < south.size) {
        firstIndex <<= 1
    }
    let treeSize = 2 * firstIndex - 1
    firstIndex -= 1
    let tree = Array<Float64>(treeSize, repeat: 0.0)
    var crossings = 0.0
    for (entry in entries) {
        var index = entry[0] + firstIndex
        tree[index] += entry[1]
        var weightSum = 0.0
        while (index > 0) {
            if (index % 2 == 1) {
                weightSum += tree[index + 1]
            }
            index = (index - 1) >> 1
            tree[index] += entry[1]
        }
        crossings += entry[1] * weightSum
    }
    return crossings
}

class DgOrderEntry {
    var v: String = ""
    var hasBarycenter: Bool = false
    var barycenter: Float64 = 0.0
    var weight: Float64 = 0.0
    var index: Int64 = 0
    var vs: ArrayList<String> = ArrayList<String>()
    var merged: Bool = false
}

func dgCrossCount(g: DgGraph, layering: ArrayList<ArrayList<String>>): Float64 {
    var total = 0.0
    for (index in 1..layering.size) {
        total += dgTwoLayerCrossCount(
            g,
            dgDenseLayer(layering[index - 1]),
            dgDenseLayer(layering[index])
        )
    }
    return total
}

/** 对应 dagre `order/build-layer-graph`：每层一张复合图，节点标签与基础图共享。 */
func dgBuildLayerGraph(
    g: DgGraph,
    rank: Int64,
    useInEdges: Bool,
    nodesWithRank: ArrayList<String>,
    ids: DagreIds
): DgGraph {
    let result = DgGraph(compound: true)
    // 邻居节点（相邻层）按需创建，且共享基础图标签（等价 dagre 的
    // `setDefaultNodeLabel(v => g.node(v))`），`order` 才能双向可见。
    result.labelSource = g
    let root = ids.next("_root")
    result.setNodeSized(root, 0.0, 0.0, "root")
    result.rootNodeId = root
    for (v in nodesWithRank) {
        let node = g.node(v)
        // dagre：`node.rank === rank || (minRank <= rank && rank <= maxRank)`
        let inRange = node.rank == rank ||
            (node.hasMinRank && node.minRank <= rank && rank <= node.maxRank)
        if (!inRange) {
            continue
        }
        result.setNodeShared(v, node)
        result.setParent(v, root)
        let incident = if (useInEdges) {
            g.inEdges(v)
        } else {
            g.outEdges(v)
        }
        for (edge in incident) {
            let u = if (edge.from == v) {
                edge.to
            } else {
                edge.from
            }
            var weight = edge.weight
            let existing = result.edgeByName(u, v, "")
            if (existing.isSome()) {
                weight += existing.getOrThrow().weight
            }
            result.setEdge(u, v, "", weight, 1)
        }
    }
    return result
}

func dgBuildLayerGraphs(
    g: DgGraph,
    ranks: ArrayList<Int64>,
    useInEdges: Bool,
    ids: DagreIds
): ArrayList<DgGraph> {
    let nodesByRank = HashMap<Int64, ArrayList<String>>()
    for (id in g.nodes()) {
        let node = g.node(id)
        if (!node.hasRank) {
            continue
        }
        if (!nodesByRank.contains(node.rank)) {
            nodesByRank[node.rank] = ArrayList<String>()
        }
        nodesByRank[node.rank].add(id)
    }
    let result = ArrayList<DgGraph>()
    for (rank in ranks) {
        let nodes = if (nodesByRank.contains(rank)) {
            nodesByRank[rank]
        } else {
            ArrayList<String>()
        }
        result.add(dgBuildLayerGraph(g, rank, useInEdges, nodes, ids))
    }
    return result
}

func dgBarycenter(layerGraph: DgGraph, movable: ArrayList<String>): ArrayList<DgOrderEntry> {
    let result = ArrayList<DgOrderEntry>()
    for (v in movable) {
        let entry = DgOrderEntry()
        entry.v = v
        entry.vs.add(v)
        let incident = layerGraph.inEdges(v)
        if (incident.size == 0) {
            result.add(entry)
            continue
        }
        var sum = 0.0
        var weight = 0.0
        for (edge in incident) {
            let other = edge.from
            sum += edge.weight * Float64(layerGraph.node(other).order)
            weight += edge.weight
        }
        entry.hasBarycenter = true
        entry.barycenter = sum / weight
        entry.weight = weight
        result.add(entry)
    }
    return result
}

/** 对应 dagre `order/resolve-conflicts`（约束图为空时的行为）。 */
func dgResolveConflicts(entries: ArrayList<DgOrderEntry>): ArrayList<DgOrderEntry> {
    for (index in 0..entries.size) {
        entries[index].index = index
        entries[index].vs = ArrayList<String>()
        entries[index].vs.add(entries[index].v)
    }
    let ordered = ArrayList<DgOrderEntry>()
    var index = entries.size - 1
    while (index >= 0) {
        ordered.add(entries[index])
        index -= 1
    }
    return ordered
}

/** 对应 dagre `order/sort`：有 barycenter 的按重心排序，无 barycenter 的按原索引插回。 */
func dgSortOrderEntries(entries: ArrayList<DgOrderEntry>, biasRight: Bool): ArrayList<String> {
    let sortable = ArrayList<DgOrderEntry>()
    let unsortable = ArrayList<DgOrderEntry>()
    for (entry in entries) {
        if (entry.hasBarycenter) {
            sortable.add(entry)
        } else {
            unsortable.add(entry)
        }
    }
    sort(
        sortable,
        lessThan: {
            left, right => if (left.barycenter != right.barycenter) {
                left.barycenter < right.barycenter
            } else if (!biasRight) {
                left.index < right.index
            } else {
                right.index < left.index
            }
        },
        stable: true
    )
    sort(unsortable, lessThan: {left, right => right.index < left.index}, stable: true)

    let vs = ArrayList<ArrayList<String>>()
    var vsIndex = 0
    // consumeUnsortable 初始
    var unsortableIndex = unsortable.size - 1
    while (unsortableIndex >= 0 && unsortable[unsortableIndex].index <= vsIndex) {
        vs.add(unsortable[unsortableIndex].vs)
        unsortableIndex -= 1
        vsIndex += 1
    }
    for (entry in sortable) {
        vsIndex += entry.vs.size
        vs.add(entry.vs)
        while (unsortableIndex >= 0 && unsortable[unsortableIndex].index <= vsIndex) {
            vs.add(unsortable[unsortableIndex].vs)
            unsortableIndex -= 1
            vsIndex += 1
        }
    }
    let result = ArrayList<String>()
    for (group in vs) {
        for (id in group) {
            result.add(id)
        }
    }
    return result
}

func dgSortSubgraph(layerGraph: DgGraph, root: String, biasRight: Bool): ArrayList<String> {
    let movable = layerGraph.children(root)
    let barycenters = dgBarycenter(layerGraph, movable)
    let entries = dgResolveConflicts(barycenters)
    return dgSortOrderEntries(entries, biasRight)
}

func dgSweepLayerGraphs(layerGraphs: ArrayList<DgGraph>, biasRight: Bool): Unit {
    for (layerGraph in layerGraphs) {
        let root = layerGraph.rootNodeId
        let sorted = dgSortSubgraph(layerGraph, root, biasRight)
        for (index in 0..sorted.size) {
            layerGraph.node(sorted[index]).order = index
        }
    }
}

func dgOrderRun(g: DgGraph, ids: DagreIds): Unit {
    let maxRank = dgMaxRank(g)
    let downRanks = ArrayList<Int64>()
    for (rank in 1..(maxRank + 1)) {
        downRanks.add(rank)
    }
    let upRanks = ArrayList<Int64>()
    var rank = maxRank - 1
    while (rank >= 0) {
        upRanks.add(rank)
        rank -= 1
    }
    let downLayerGraphs = dgBuildLayerGraphs(g, downRanks, true, ids)
    let upLayerGraphs = dgBuildLayerGraphs(g, upRanks, false, ids)

    var layering = dgInitOrder(g)
    dgAssignOrder(g, layering)

    var bestCrossings = Float64.Inf
    var best = ArrayList<ArrayList<String>>()
    var iteration = 0
    var lastBest = 0
    while (lastBest < 4) {
        let biasRight = iteration % 4 >= 2
        if (iteration % 2 != 0) {
            dgSweepLayerGraphs(downLayerGraphs, biasRight)
        } else {
            dgSweepLayerGraphs(upLayerGraphs, biasRight)
        }
        layering = dgBuildLayerMatrix(g)
        let crossings = dgCrossCount(g, layering)
        if (crossings < bestCrossings) {
            lastBest = 0
            best = dgCopyLayering(layering)
            bestCrossings = crossings
        }
        iteration += 1
        lastBest += 1
    }
    dgAssignOrder(g, best)
}

func dgCopyLayering(layering: ArrayList<ArrayList<String>>): ArrayList<ArrayList<String>> {
    let result = ArrayList<ArrayList<String>>()
    for (layer in layering) {
        result.add(ArrayList<String>(layer))
    }
    return result
}

// ---------------------------------------------------------------------------
// position：positionY + Brandes-Köpf positionX
// ---------------------------------------------------------------------------

func dgPositionY(g: DgGraph): Unit {
    let layering = dgBuildLayerMatrix(g)
    let rankSep = g.ranksep
    var prevY = 0.0
    for (layer in layering) {
        let ids = dgDenseLayer(layer)
        var maxHeight = 0.0
        for (id in ids) {
            let height = g.node(id).height
            if (height > maxHeight) {
                maxHeight = height
            }
        }
        for (id in ids) {
            g.node(id).y = prevY + maxHeight / 2.0
        }
        prevY += maxHeight + rankSep
    }
}

/** 冲突集合：`conflicts[v][w] = true`（v、w 按字符串序归一）。 */
class DgConflicts {
    var map: HashMap<String, HashMap<String, Bool>> = HashMap<String, HashMap<String, Bool>>()

    func add(v: String, w: String): Unit {
        var left = v
        var right = w
        if (left > right) {
            let swap = left
            left = right
            right = swap
        }
        if (!map.contains(left)) {
            map[left] = HashMap<String, Bool>()
        }
        map[left][right] = true
    }

    func has(v: String, w: String): Bool {
        var left = v
        var right = w
        if (left > right) {
            let swap = left
            left = right
            right = swap
        }
        if (!map.contains(left)) {
            return false
        }
        return map[left].contains(right)
    }
}

func dgFindType1Conflicts(g: DgGraph, layering: ArrayList<ArrayList<String>>): DgConflicts {
    let conflicts = DgConflicts()
    let layers = ArrayList<ArrayList<String>>()
    for (layer in layering) {
        layers.add(dgDenseLayer(layer))
    }
    for (index in 1..layers.size) {
        dgVisitType1Layer(g, layers[index - 1], layers[index], conflicts)
    }
    return conflicts
}

func dgVisitType1Layer(
    g: DgGraph,
    prevLayer: ArrayList<String>,
    layer: ArrayList<String>,
    conflicts: DgConflicts
): Unit {
    var k0 = 0
    var scanPos = 0
    let prevLayerLength = prevLayer.size
    if (layer.size == 0) {
        return
    }
    let lastNode = layer[layer.size - 1]
    for (index in 0..layer.size) {
        let v = layer[index]
        let innerOpt = dgFindOtherInnerSegmentNode(g, v)
        var k1 = if (innerOpt.isSome()) {
            g.node(innerOpt.getOrThrow()).order
        } else {
            prevLayerLength
        }
        if (innerOpt.isSome() || v == lastNode) {
            for (scanIndex in scanPos..(index + 1)) {
                let scanNode = layer[scanIndex]
                for (u in g.predecessors(scanNode)) {
                    let uLabel = g.node(u)
                    let uPos = uLabel.order
                    if ((uPos < k0 || k1 < uPos) && !(!uLabel.dummy.isEmpty() && !g.node(scanNode).dummy.isEmpty())) {
                        conflicts.add(u, scanNode)
                    }
                }
            }
            scanPos = index + 1
            k0 = k1
        }
    }
}

func dgFindOtherInnerSegmentNode(g: DgGraph, v: String): ?String {
    if (g.node(v).dummy.isEmpty()) {
        return None
    }
    for (u in g.predecessors(v)) {
        if (!g.node(u).dummy.isEmpty()) {
            return Some(u)
        }
    }
    return None
}

class DgAlignment {
    var root: HashMap<String, String> = HashMap<String, String>()
    var align: HashMap<String, String> = HashMap<String, String>()
}

func dgVerticalAlignment(
    g: DgGraph,
    layering: ArrayList<ArrayList<String>>,
    conflicts: DgConflicts,
    usePredecessors: Bool
): DgAlignment {
    let alignment = DgAlignment()
    let pos = HashMap<String, Int64>()
    for (layer in layering) {
        for (index in 0..layer.size) {
            let v = layer[index]
            alignment.root[v] = v
            alignment.align[v] = v
            pos[v] = index
        }
    }
    for (layer in layering) {
        var prevIdx = -1
        for (v in layer) {
            var neighbors = if (usePredecessors) {
                g.predecessors(v)
            } else {
                g.successors(v)
            }
            if (neighbors.size == 0) {
                continue
            }
            let positions = pos
            sort(neighbors, lessThan: {left, right => positions[left] < positions[right]}, stable: true)
            let mp = Float64(neighbors.size - 1) / 2.0
            let lowIndex = Int64(mp)
            let highIndex = Int64(ceilFloat(mp))
            var index = lowIndex
            while (index <= highIndex) {
                let w = neighbors[index]
                if (alignment.align[v] == v && prevIdx < pos[w] && !conflicts.has(v, w)) {
                    alignment.align[w] = v
                    alignment.root[v] = alignment.root[w]
                    alignment.align[v] = alignment.root[w]
                    prevIdx = pos[w]
                }
                index += 1
            }
        }
    }
    return alignment
}

func ceilFloat(value: Float64): Float64 {
    let truncated = Float64(Int64(value))
    if (truncated < value) {
        return truncated + 1.0
    }
    return truncated
}

/** 块图：块（root）之间的最小间距。 */
func dgBuildBlockGraph(
    g: DgGraph,
    layering: ArrayList<ArrayList<String>>,
    roots: HashMap<String, String>,
    reverseSep: Bool
): DgGraph {
    let blockGraph = DgGraph()
    for (layer in layering) {
        var previous = ""
        for (v in layer) {
            let vRoot = roots[v]
            blockGraph.setNode(vRoot)
            if (!previous.isEmpty()) {
                let uRoot = roots[previous]
                let separation = dgSep(g, v, previous, reverseSep)
                var prevMax = 0.0
                let existing = blockGraph.edgeByName(uRoot, vRoot, "")
                if (existing.isSome()) {
                    prevMax = existing.getOrThrow().weight
                }
                let value = if (separation > prevMax) {
                    separation
                } else {
                    prevMax
                }
                blockGraph.setEdge(uRoot, vRoot, "", value, 1)
            }
            previous = v
        }
    }
    return blockGraph
}

/** 对应 dagre `bk.sep`：相邻两节点中心的最小距离。 */
func dgSep(g: DgGraph, v: String, w: String, reverseSep: Bool): Float64 {
    let vLabel = g.node(v)
    let wLabel = g.node(w)
    var sum = 0.0
    var delta = 0.0
    sum += vLabel.width / 2.0
    if (!vLabel.labelpos.isEmpty()) {
        if (vLabel.labelpos == "l") {
            delta = -vLabel.width / 2.0
        } else if (vLabel.labelpos == "r") {
            delta = vLabel.width / 2.0
        }
    }
    if (delta != 0.0) {
        sum += if (reverseSep) {
            delta
        } else {
            -delta
        }
    }
    delta = 0.0
    sum += (if (!vLabel.dummy.isEmpty()) {
        g.edgesep
    } else {
        g.nodesep
    }) / 2.0
    sum += (if (!wLabel.dummy.isEmpty()) {
        g.edgesep
    } else {
        g.nodesep
    }) / 2.0
    sum += wLabel.width / 2.0
    if (!wLabel.labelpos.isEmpty()) {
        if (wLabel.labelpos == "l") {
            delta = wLabel.width / 2.0
        } else if (wLabel.labelpos == "r") {
            delta = -wLabel.width / 2.0
        }
    }
    if (delta != 0.0) {
        sum += if (reverseSep) {
            delta
        } else {
            -delta
        }
    }
    return sum
}

func dgHorizontalCompaction(
    g: DgGraph,
    layering: ArrayList<ArrayList<String>>,
    roots: HashMap<String, String>,
    align: HashMap<String, String>,
    reverseSep: Bool
): HashMap<String, Float64> {
    let xs = HashMap<String, Float64>()
    let blockGraph = dgBuildBlockGraph(g, layering, roots, reverseSep)
    // dagre 的 borderType 分支只对复合图的边框节点生效；本包无边框节点，恒走通用分支。
    dgCompactionPass(blockGraph, xs, false)
    dgCompactionPass(blockGraph, xs, true)

    for (v in align.keys()) {
        xs[v] = xs[roots[v]]
    }
    return xs
}

func dgCompactionPass(blockGraph: DgGraph, xs: HashMap<String, Float64>, secondPass: Bool): Unit {
    let stack = blockGraph.nodes()
    let visited = HashMap<String, Bool>()
    while (stack.size > 0) {
        let elem = dgPop(stack).getOrThrow()
        if (visited.contains(elem)) {
            if (secondPass) {
                var minValue = Float64.Inf
                for (edge in blockGraph.outEdges(elem)) {
                    let candidate = xs[edge.to] - edge.weight
                    if (candidate < minValue) {
                        minValue = candidate
                    }
                }
                if (minValue != Float64.Inf) {
                    let current = xs.get(elem) ?? 0.0
                    xs[elem] = if (current > minValue) {
                        current
                    } else {
                        minValue
                    }
                }
            } else {
                var value = 0.0
                for (edge in blockGraph.inEdges(elem)) {
                    let candidate = (xs.get(edge.from) ?? 0.0) + edge.weight
                    if (candidate > value) {
                        value = candidate
                    }
                }
                xs[elem] = value
            }
        } else {
            visited[elem] = true
            stack.add(elem)
            let next = if (secondPass) {
                blockGraph.successors(elem)
            } else {
                blockGraph.predecessors(elem)
            }
            for (id in next) {
                stack.add(id)
            }
        }
    }
}

func dgFindSmallestWidthAlignment(
    g: DgGraph,
    alignments: ArrayList<HashMap<String, Float64>>
): Int64 {
    var bestIndex = 0
    var bestWidth = Float64.Inf
    for (index in 0..alignments.size) {
        var maxValue = (-Float64.Inf)
        var minValue = Float64.Inf
        let xs = alignments[index]
        for ((v, x) in xs) {
            let halfWidth = g.node(v).width / 2.0
            if (x + halfWidth > maxValue) {
                maxValue = x + halfWidth
            }
            if (x - halfWidth < minValue) {
                minValue = x - halfWidth
            }
        }
        let width = maxValue - minValue
        if (width < bestWidth) {
            bestWidth = width
            bestIndex = index
        }
    }
    return bestIndex
}

func dgAlignCoordinates(alignments: ArrayList<HashMap<String, Float64>>, alignToIndex: Int64): Unit {
    var alignToMin = Float64.Inf
    var alignToMax = (-Float64.Inf)
    for ((_, value) in alignments[alignToIndex]) {
        if (value < alignToMin) {
            alignToMin = value
        }
        if (value > alignToMax) {
            alignToMax = value
        }
    }
    // 顺序：ul(0) ur(1) dl(2) dr(3)；horiz == "l" 对齐最小值，否则对齐最大值。
    for (index in 0..alignments.size) {
        if (index == alignToIndex) {
            continue
        }
        let isLeft = index % 2 == 0
        var minValue = Float64.Inf
        var maxValue = (-Float64.Inf)
        for ((_, value) in alignments[index]) {
            if (value < minValue) {
                minValue = value
            }
            if (value > maxValue) {
                maxValue = value
            }
        }
        var delta = alignToMin - minValue
        if (!isLeft) {
            delta = alignToMax - maxValue
        }
        if (delta != 0.0) {
            let updated = HashMap<String, Float64>()
            for ((v, value) in alignments[index]) {
                updated[v] = value + delta
            }
            alignments[index] = updated
        }
    }
}

func dgBalance(alignments: ArrayList<HashMap<String, Float64>>): HashMap<String, Float64> {
    let result = HashMap<String, Float64>()
    for ((v, _) in alignments[0]) {
        let values = ArrayList<Float64>()
        for (alignment in alignments) {
            values.add(alignment.get(v) ?? 0.0)
        }
        sort(values)
        result[v] = (values[1] + values[2]) / 2.0
    }
    return result
}

func dgPositionX(g: DgGraph): HashMap<String, Float64> {
    let layering = dgBuildLayerMatrix(g)
    let dense = ArrayList<ArrayList<String>>()
    for (layer in layering) {
        dense.add(dgDenseLayer(layer))
    }
    let conflicts = dgFindType1Conflicts(g, layering)

    let alignments = ArrayList<HashMap<String, Float64>>()
    // 顺序与 dagre 一致：u→l, u→r, d→l, d→r（影响 findSmallestWidthAlignment 的平局）。
    for (vertical in 0..2) {
        let isUp = vertical == 0
        let baseLayering = ArrayList<ArrayList<String>>()
        if (isUp) {
            for (layer in dense) {
                baseLayering.add(layer)
            }
        } else {
            var index = dense.size - 1
            while (index >= 0) {
                baseLayering.add(dense[index])
                index -= 1
            }
        }
        for (horizontal in 0..2) {
            let isReverse = horizontal == 1
            let adjusted = ArrayList<ArrayList<String>>()
            for (layer in baseLayering) {
                if (isReverse) {
                    let reversed = ArrayList<String>()
                    var index = layer.size - 1
                    while (index >= 0) {
                        reversed.add(layer[index])
                        index -= 1
                    }
                    adjusted.add(reversed)
                } else {
                    adjusted.add(layer)
                }
            }
            let alignment = dgVerticalAlignment(g, adjusted, conflicts, isUp)
            var xs = dgHorizontalCompaction(g, adjusted, alignment.root, alignment.align, isReverse)
            if (isReverse) {
                let negated = HashMap<String, Float64>()
                for ((v, value) in xs) {
                    negated[v] = -value
                }
                xs = negated
            }
            alignments.add(xs)
        }
    }

    let smallestIndex = dgFindSmallestWidthAlignment(g, alignments)
    dgAlignCoordinates(alignments, smallestIndex)
    return dgBalance(alignments)
}

func dgPositionRun(g: DgGraph): Unit {
    dgPositionY(g)
    let xs = dgPositionX(g)
    for ((v, x) in xs) {
        g.node(v).x = x
    }
}

// ---------------------------------------------------------------------------
// coordinateSystem / translate
// ---------------------------------------------------------------------------

func dgSwapWidthHeight(g: DgGraph): Unit {
    for (id in g.nodes()) {
        let node = g.node(id)
        let width = node.width
        node.width = node.height
        node.height = width
    }
}

func dgCoordinateAdjust(g: DgGraph): Unit {
    if (g.rankdir == "lr" || g.rankdir == "rl") {
        dgSwapWidthHeight(g)
    }
}

func dgCoordinateUndo(g: DgGraph): Unit {
    if (g.rankdir == "bt" || g.rankdir == "rl") {
        for (id in g.nodes()) {
            g.node(id).y = -g.node(id).y
        }
    }
    if (g.rankdir == "lr" || g.rankdir == "rl") {
        for (id in g.nodes()) {
            let node = g.node(id)
            let x = node.x
            node.x = node.y
            node.y = x
        }
        dgSwapWidthHeight(g)
    }
}

/** normalize.undo 的等价（只影响坐标）：移除所有 dummy 节点。 */
func dgRemoveDummyNodes(g: DgGraph): Unit {
    let nodeIds = g.nodes()
    for (id in nodeIds) {
        if (!g.node(id).dummy.isEmpty()) {
            g.removeNode(id)
        }
    }
}

func dgTranslateGraph(g: DgGraph): Unit {
    var minX = Float64.Inf
    var maxX = 0.0
    var minY = Float64.Inf
    var maxY = 0.0
    for (id in g.nodes()) {
        let node = g.node(id)
        let left = node.x - node.width / 2.0
        let right = node.x + node.width / 2.0
        let top = node.y - node.height / 2.0
        let bottom = node.y + node.height / 2.0
        if (left < minX) {
            minX = left
        }
        if (right > maxX) {
            maxX = right
        }
        if (top < minY) {
            minY = top
        }
        if (bottom > maxY) {
            maxY = bottom
        }
    }
    if (minX == Float64.Inf) {
        return
    }
    minX -= g.marginx
    minY -= g.marginy
    for (id in g.nodes()) {
        let node = g.node(id)
        node.x -= minX
        node.y -= minY
    }
    g.graphWidth = maxX - minX + g.marginx
    g.graphHeight = maxY - minY + g.marginy
}

// ---------------------------------------------------------------------------
// 完整流水线
// ---------------------------------------------------------------------------

func dgRunLayout(g: DgGraph): Unit {
    let ids = DagreIds()
    // makeSpaceForEdgeLabels：ranksep 减半、minlen 翻倍、边宽加 labeloffset
    g.ranksep /= 2.0
    for (edgeId in g.edges()) {
        let edge = g.edgeById(edgeId).getOrThrow()
        edge.minlen *= 2
        if (edge.labelpos != "c") {
            if (g.rankdir == "tb" || g.rankdir == "bt") {
                edge.width += edge.labeloffset
            } else {
                edge.height += edge.labeloffset
            }
        }
    }
    dgAcyclicRun(g, ids)
    dgNestingRun(g, ids)
    dgNetworkSimplex(g)
    dgRemoveEmptyRanks(g)
    dgNestingCleanup(g)
    dgNormalizeRanks(g)
    dgNormalizeRun(g, ids)
    dgOrderRun(g, ids)
    dgCoordinateAdjust(g)
    dgPositionRun(g)
    dgRemoveDummyNodes(g)
    dgCoordinateUndo(g)
    dgTranslateGraph(g)
}
