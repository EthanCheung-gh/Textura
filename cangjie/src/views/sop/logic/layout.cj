/**
 * 分层自动布局（dagre `layoutPositions` 的仓颉等价实现）。
 *
 * Web 版把节点/边交给 `@dagrejs/dagre`（`rankdir=TB`、`nodesep=60`、`ranksep=90`、
 * `marginx/marginy=24`，默认 network-simplex + barycenter + Brandes-Köpf）。
 * 本文件只做三件事：
 *
 * 1. **输入清洗**（与 Web 版逐条一致）：空 id / 重复 id 丢弃（保留首次出现），
 *    未知端点、自环、重复 `(from,to)` 边丢弃；
 * 2. **构建 dagre 布局图**并调用 `dagre_layout.cj` 的完整流水线（含 dummy 节点、
 *    网络单纯形分层、barycenter 排序、Brandes-Köpf 水平对齐）；
 * 3. **导出坐标**：节点左上角锚点（`round(center - size/2)`，`floor(v+0.5)` 取整）、
 *    压缩后的层号与层内次序。
 *
 * 由于流水线逐模块移植 dagre（含插入序语义），相同输入产出与 dagre **逐点一致**的坐标。
 */
package textura.views.sop.logic

import std.collection.*
import std.deriving.*
import std.sort.*

/** 节点视觉尺寸，与 Web 版 `SOP_NODE_WIDTH` / `SOP_NODE_HEIGHT` 一致。 */
public let SOP_NODE_WIDTH: Float64 = 200.0
public let SOP_NODE_HEIGHT: Float64 = 60.0
/** dagre 默认参数。 */
public let SOP_NODE_SEP: Float64 = 60.0
public let SOP_RANK_SEP: Float64 = 90.0
public let SOP_LAYOUT_MARGIN: Float64 = 24.0
/** dagre `graphDefaults.edgesep`（Web 版未覆盖，参与 dummy 与真实节点的间距）。 */
let SOP_EDGE_SEP: Float64 = 20.0

@Derive[Equatable]
public enum RankDir {
    | TopDown
    | LeftRight
}

public struct LayoutOptions {
    public let rankdir: RankDir
    public let nodeWidth: Float64
    public let nodeHeight: Float64
    /** 同层节点间距 */
    public let nodesep: Float64
    /** 层间距 */
    public let ranksep: Float64
    /** 画布内边距（左上角留白） */
    public let margin: Float64

    public init(
        rankdir!: RankDir = RankDir.TopDown,
        nodeWidth!: Float64 = SOP_NODE_WIDTH,
        nodeHeight!: Float64 = SOP_NODE_HEIGHT,
        nodesep!: Float64 = SOP_NODE_SEP,
        ranksep!: Float64 = SOP_RANK_SEP,
        margin!: Float64 = SOP_LAYOUT_MARGIN
    ) {
        this.rankdir = rankdir
        this.nodeWidth = nodeWidth
        this.nodeHeight = nodeHeight
        this.nodesep = nodesep
        this.ranksep = ranksep
        this.margin = margin
    }
}

/** 分层结果中的单个节点（用于绘制连线/调试对照）。 */
public struct RankedNode {
    public let id: String
    /** 压缩后的层号：0 起，连续递增（dagre 内部层号因 minlen 翻倍而间隔 2）。 */
    public let rank: Int64
    public let order: Int64

    public init(id: String, rank: Int64, order: Int64) {
        this.id = id
        this.rank = rank
        this.order = order
    }
}

/** 布局输出（按输入顺序保存）。 */
struct LayoutOutcome {
    let ids: Array<String>
    let positions: HashMap<String, SopPosition>
    let ranks: HashMap<String, Int64>
    let orders: HashMap<String, Int64>

    init(
        ids: Array<String>,
        positions: HashMap<String, SopPosition>,
        ranks: HashMap<String, Int64>,
        orders: HashMap<String, Int64>
    ) {
        this.ids = ids
        this.positions = positions
        this.ranks = ranks
        this.orders = orders
    }
}

/**
 * 计算分层布局坐标（左上角锚点）。
 *
 * - TB（默认）：y 随层级递增，同层 y 相同；
 * - LR：x 随层级递增，同层 x 相同。
 */
public func layoutPositions(
    nodes: Array<SopNode>,
    edges: Array<SopEdge>,
    options!: LayoutOptions = LayoutOptions()
): HashMap<String, SopPosition> {
    let ids = ArrayList<String>()
    for (node in nodes) {
        ids.add(node.id)
    }
    return layoutIds(ids.toArray(), edges, options: options)
}

/** 只有 id 的布局输入（对应 Web 版 `LayoutNodeInput`）。 */
public func layoutIds(
    ids: Array<String>,
    edges: Array<SopEdge>,
    options!: LayoutOptions = LayoutOptions()
): HashMap<String, SopPosition> {
    let outcome = runLayoutEngine(ids, edges, options)
    let positions = HashMap<String, SopPosition>()
    for (id in outcome.ids) {
        positions[id] = outcome.positions[id]
    }
    return positions
}

/** 分层/排序结果，按 (rank, order) 升序；用于连线绘制与对照测试。 */
public func layoutRanks(
    nodes: Array<SopNode>,
    edges: Array<SopEdge>,
    options!: LayoutOptions = LayoutOptions()
): Array<RankedNode> {
    let ids = ArrayList<String>()
    for (node in nodes) {
        ids.add(node.id)
    }
    let outcome = runLayoutEngine(ids.toArray(), edges, options)
    let result = ArrayList<RankedNode>()
    for (id in outcome.ids) {
        result.add(RankedNode(id, outcome.ranks[id], outcome.orders[id]))
    }
    sort(
        result,
        lessThan: {
            left, right => if (left.rank != right.rank) {
                left.rank < right.rank
            } else {
                left.order < right.order
            }
        }
    )
    return result.toArray()
}

/** 建立布局图：节点带尺寸，边带 dagre 默认标签，图标签为调用方参数。 */
func buildLayoutGraph(ids: ArrayList<String>, edges: Array<SopEdge>, options: LayoutOptions): (DgGraph, HashMap<String,
    Int64>) {
    let graph = DgGraph(multigraph: true, compound: true)
    graph.rankdir = if (options.rankdir == RankDir.TopDown) {
        "tb"
    } else {
        "lr"
    }
    graph.nodesep = options.nodesep
    graph.edgesep = SOP_EDGE_SEP
    graph.ranksep = options.ranksep
    graph.marginx = options.margin
    graph.marginy = options.margin
    graph.align = ""

    let index = HashMap<String, Int64>()
    for (id in ids) {
        index[id] = ids.size
        graph.setNodeSized(id, options.nodeWidth, options.nodeHeight, "")
    }

    let seenEdge = HashMap<String, Bool>()
    for (edge in edges) {
        if (!index.contains(edge.from) || !index.contains(edge.to)) {
            continue
        }
        if (edge.from == edge.to) {
            continue
        }
        let key = "${edge.from}->${edge.to}"
        if (seenEdge.contains(key)) {
            continue
        }
        seenEdge[key] = true
        // dagre `edgeDefaults`：minlen=1、weight=1、width/height=0、labeloffset=10、labelpos="r"
        let created = graph.setEdge(edge.from, edge.to, "", 1.0, 1)
        created.labeloffset = 10.0
        created.labelpos = "r"
        created.width = 0.0
        created.height = 0.0
    }
    return (graph, index)
}

func runLayoutEngine(inputIds: Array<String>, inputEdges: Array<SopEdge>, options: LayoutOptions): LayoutOutcome {
    // 1. 节点去重（保留首次出现顺序），空 id 丢弃。
    let ids = ArrayList<String>()
    let index = HashMap<String, Int64>()
    for (id in inputIds) {
        if (id.isEmpty() || index.contains(id)) {
            continue
        }
        index[id] = ids.size
        ids.add(id)
    }
    let positions = HashMap<String, SopPosition>()
    let ranks = HashMap<String, Int64>()
    let orders = HashMap<String, Int64>()
    if (ids.size == 0) {
        return LayoutOutcome(Array<String>(), positions, ranks, orders)
    }

    let (graph, _) = buildLayoutGraph(ids, inputEdges, options)
    dgRunLayout(graph)

    // 层号压缩：dagre 内部因 minlen 翻倍而使用 0,2,4…，这里映射为 0,1,2… 供视图使用。
    let rawRanks = ArrayList<Int64>()
    for (id in ids) {
        let rank = graph.node(id).rank
        if (!containsRank(rawRanks, rank)) {
            rawRanks.add(rank)
        }
    }
    sort(rawRanks)

    for (id in ids) {
        let node = graph.node(id)
        positions[id] = SopPosition(
            Float64(jsRound(node.x - options.nodeWidth / 2.0)),
            Float64(jsRound(node.y - options.nodeHeight / 2.0))
        )
        ranks[id] = indexOfRank(rawRanks, node.rank)
        orders[id] = node.order
    }
    return LayoutOutcome(ids.toArray(), positions, ranks, orders)
}

func containsRank(values: ArrayList<Int64>, target: Int64): Bool {
    for (value in values) {
        if (value == target) {
            return true
        }
    }
    return false
}

func indexOfRank(values: ArrayList<Int64>, target: Int64): Int64 {
    for (index in 0..values.size) {
        if (values[index] == target) {
            return index
        }
    }
    return 0
}

/**
 * 图里是否存在环（含自环）。布局本身会反向回边，此函数供 UI 提示使用。
 */
public func hasCycle(nodes: Array<SopNode>, edges: Array<SopEdge>): Bool {
    let ids = ArrayList<String>()
    let index = HashMap<String, Int64>()
    for (node in nodes) {
        if (node.id.isEmpty() || index.contains(node.id)) {
            continue
        }
        index[node.id] = ids.size
        ids.add(node.id)
    }
    let graph = DgGraph()
    for (id in ids) {
        graph.setNode(id)
    }
    for (edge in edges) {
        if (!index.contains(edge.from) || !index.contains(edge.to)) {
            continue
        }
        if (edge.from == edge.to) {
            return true
        }
        graph.setEdge(edge.from, edge.to, "", 1.0, 1)
    }
    return dgDfsFas(graph).size > 0
}

/**
 * 把画布坐标整理成 store 可用的补丁：取整、去重（同 id 取最后一次）、
 * 可选地只保留与现有坐标不同的项。
 */
public func canvasPositionsToPatch(
    positions: Array<CanvasPosition>,
    current!: ?HashMap<String, SopPosition> = None
): Array<CanvasPosition> {
    let latest = HashMap<String, CanvasPosition>()
    let order = ArrayList<String>()
    for (entry in positions) {
        if (entry.id.isEmpty()) {
            continue
        }
        let rounded = CanvasPosition(entry.id, Float64(jsRound(entry.x)), Float64(jsRound(entry.y)))
        if (!latest.contains(entry.id)) {
            order.add(entry.id)
        }
        latest[entry.id] = rounded
    }
    let result = ArrayList<CanvasPosition>()
    for (id in order) {
        let entry = latest[id]
        if (current.isSome()) {
            let beforeOpt = current.getOrThrow().get(id)
            if (beforeOpt.isSome()) {
                let before = beforeOpt.getOrThrow()
                if (before.x == entry.x && before.y == entry.y) {
                    continue
                }
            }
        }
        result.add(entry)
    }
    return result.toArray()
}
