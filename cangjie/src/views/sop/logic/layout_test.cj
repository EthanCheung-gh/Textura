package textura.views.sop.logic

import std.collection.*
import std.sort.*
import std.unittest.*
import std.unittest.testmacro.*

func layoutDump(positions: HashMap<String, SopPosition>): String {
    let keys = ArrayList<String>()
    for ((id, _) in positions) {
        keys.add(id)
    }
    sort(keys)
    let builder = StringBuilder()
    for (index in 0..keys.size) {
        let position = positions[keys[index]]
        if (index > 0) {
            builder.append(" ")
        }
        builder.append("${keys[index]}:${Int64(position.x)},${Int64(position.y)}")
    }
    return builder.toString()
}

func layoutSortedKeys(positions: HashMap<String, SopPosition>): String {
    let keys = ArrayList<String>()
    for ((id, _) in positions) {
        keys.add(id)
    }
    sort(keys)
    return layoutDumpJoin(keys)
}

func layoutDumpJoin(keys: ArrayList<String>): String {
    let builder = StringBuilder()
    for (index in 0..keys.size) {
        if (index > 0) {
            builder.append(",")
        }
        builder.append(keys[index])
    }
    return builder.toString()
}

func layoutOverlaps(left: SopPosition, right: SopPosition): Bool {
    left.x < right.x + SOP_NODE_WIDTH && right.x < left.x + SOP_NODE_WIDTH && left.y < right.y + SOP_NODE_HEIGHT &&
        right.y < left.y + SOP_NODE_HEIGHT
}

func layoutAssertNoOverlap(positions: HashMap<String, SopPosition>) {
    let ids = ArrayList<String>()
    for ((id, _) in positions) {
        ids.add(id)
    }
    sort(ids)
    for (i in 0..ids.size) {
        for (j in (i + 1)..ids.size) {
            let left = positions[ids[i]]
            let right = positions[ids[j]]
            @Assert(!layoutOverlaps(left, right))
        }
    }
}

func layoutAbs(value: Float64): Float64 {
    if (value < 0.0) {
        return -value
    }
    return value
}

func layoutNodesOf(ids: Array<String>): Array<SopNode> {
    let nodes = ArrayList<SopNode>()
    for (id in ids) {
        nodes.add(SopNode(id))
    }
    return nodes.toArray()
}

func diamondIds(): Array<String> {
    return ["root", "a", "b", "end"]
}

func diamondEdges(): Array<SopEdge> {
    return [
        SopEdge("root", "a"),
        SopEdge("root", "b"),
        SopEdge("a", "end"),
        SopEdge("b", "end")
    ]
}

// ---------------------------------------------------------------------------
// 移植自 src/modules/sop/layout.test.ts
// ---------------------------------------------------------------------------

@Test
func testLayoutOrdersLayersDownward(): Unit {
    // 按层级向下递增 y，同层节点共享 y 且水平不重叠
    let positions = layoutIds(diamondIds(), diamondEdges())
    @Expect(layoutSortedKeys(positions), "a,b,end,root")
    @Expect(positions["a"].y, positions["b"].y)
    @Assert(positions["root"].y < positions["a"].y)
    @Assert(positions["a"].y < positions["end"].y)
    @Assert(layoutAbs(positions["a"].x - positions["b"].x) >= SOP_NODE_WIDTH)
    layoutAssertNoOverlap(positions)
}

@Test
func testLayoutLongChainGap(): Unit {
    // 长链的 y 单调递增，层间距不小于 ranksep
    let ids = ["n0", "n1", "n2", "n3"]
    let edges = [
        SopEdge("n0", "n1"),
        SopEdge("n1", "n2"),
        SopEdge("n2", "n3")
    ]
    let positions = layoutIds(ids, edges, options: LayoutOptions(nodesep: 60.0, ranksep: 90.0))
    for (index in 1..ids.size) {
        let gap = positions[ids[index]].y - positions[ids[index - 1]].y
        @Assert(gap >= SOP_NODE_HEIGHT + 60.0)
    }
    layoutAssertNoOverlap(positions)
}

@Test
func testLayoutIgnoresDuplicateSelfAndUnknownEdges(): Unit {
    // 忽略重复边、自环与未知节点，支持 LR 方向
    let positions = layoutIds(
        ["a", "b"],
        [
            SopEdge("a", "b"),
            SopEdge("a", "b"),
            SopEdge("a", "a"),
            SopEdge("ghost", "b")
        ],
        options: LayoutOptions(rankdir: RankDir.LeftRight)
    )
    @Assert(positions["a"].x < positions["b"].x)
    @Expect(positions["a"].y, positions["b"].y)
    @Expect(positions.contains("ghost"), false)
    @Expect(layoutSortedKeys(positions), "a,b")
}

@Test
func testLayoutEmptyCanvas(): Unit {
    let positions = layoutIds(Array<String>(), Array<SopEdge>())
    @Expect(positions.size, 0)
}

// ---------------------------------------------------------------------------
// 与 dagre 的逐点对照放在 layout_dagre_test.cj（39 组 fixture × 2 组参数全部逐点一致）。
// 本文件保留与 Web 版 layout.test.ts 对齐的性质断言（层序、间距、去重、稳定性）。
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 补充覆盖：稳定坐标、菱形分叉、环、长链、空 id / 重复 id
// ---------------------------------------------------------------------------

@Test
func testLayoutIsStableAcrossRuns(): Unit {
    let first = layoutDump(layoutIds(diamondIds(), diamondEdges()))
    let second = layoutDump(layoutIds(diamondIds(), diamondEdges()))
    @Expect(first, second)
}

@Test
func testLayoutDiamondBranchSharesRank(): Unit {
    let ranks = layoutRanks(layoutNodesOf(diamondIds()), diamondEdges())
    @Expect(ranks.size, 4)
    @Expect("${ranks[0].id}:${ranks[0].rank}", "root:0")
    @Expect(ranks[1].rank, ranks[2].rank)
    @Expect("${ranks[1].id}:${ranks[1].rank}", "a:1")
    @Expect("${ranks[2].id}:${ranks[2].rank}", "b:1")
    @Expect("${ranks[3].id}:${ranks[3].rank}", "end:2")
}

@Test
func testLayoutDetectsCycles(): Unit {
    let cycleNodes = [SopNode("a"), SopNode("b")]
    @Expect(hasCycle(cycleNodes, [SopEdge("a", "b"), SopEdge("b", "a")]), true)
    @Expect(hasCycle(cycleNodes, [SopEdge("a", "b")]), false)
    @Expect(hasCycle([SopNode("a")], [SopEdge("a", "a")]), true)
    @Expect(hasCycle(layoutNodesOf(diamondIds()), diamondEdges()), false)
}

@Test
func testLayoutLongChainFiftyNodes(): Unit {
    let ids = ArrayList<String>()
    let edges = ArrayList<SopEdge>()
    for (index in 0..50) {
        ids.add("n${index}")
        if (index > 0) {
            edges.add(SopEdge("n${index - 1}", "n${index}"))
        }
    }
    let positions = layoutIds(ids.toArray(), edges.toArray())
    @Expect(positions.size, 50)
    @Expect(positions["n0"].x, 24.0)
    @Expect(positions["n0"].y, 24.0)
    @Expect(positions["n49"].y, 24.0 + 49.0 * (SOP_NODE_HEIGHT + SOP_RANK_SEP))
    layoutAssertNoOverlap(positions)
}

@Test
func testLayoutLargeGraphStaysBounded(): Unit {
    // 回归：层图只按需创建邻居节点（曾因每层图复制全部节点导致 200 节点 OOM）。
    let ids = ArrayList<String>()
    let edges = ArrayList<SopEdge>()
    for (index in 0..120) {
        ids.add("n${index}")
    }
    for (index in 0..120) {
        if (index + 1 < 120 && index % 3 != 2) {
            edges.add(SopEdge("n${index}", "n${index + 1}"))
        }
        if (index + 5 < 120) {
            edges.add(SopEdge("n${index}", "n${index + 5}"))
        }
    }
    let positions = layoutIds(ids.toArray(), edges.toArray())
    @Expect(positions.size, 120)
    let again = layoutIds(ids.toArray(), edges.toArray())
    @Expect("${Int64(positions["n0"].x)},${Int64(positions["n0"].y)}", "${Int64(again["n0"].x)},${Int64(again["n0"].y)}")
}

@Test
func testLayoutIgnoresEmptyAndDuplicateNodeIds(): Unit {
    let positions = layoutIds(["a", "", "a", "b"], [SopEdge("a", "b")])
    @Expect(layoutSortedKeys(positions), "a,b")
}

// ---------------------------------------------------------------------------
// canvasPositionsToPatch（移植自 layout.test.ts）
// ---------------------------------------------------------------------------

@Test
func testCanvasPositionsToPatchRoundsDedupesAndFilters(): Unit {
    let before = HashMap<String, SopPosition>()
    before["b"] = SopPosition(100.0, 200.0)
    before["c"] = SopPosition(0.0, 0.0)
    let patches = canvasPositionsToPatch(
        [
            CanvasPosition("a", 10.4, 20.6),
            CanvasPosition("a", 11.2, 21.8),
            CanvasPosition("b", 100.0, 200.0),
            CanvasPosition("c", 300.0, 400.0)
        ],
        current: before
    )
    @Expect(patches.size, 2)
    @Expect("${patches[0].id}:${Int64(patches[0].x)},${Int64(patches[0].y)}", "a:11,22")
    @Expect("${patches[1].id}:${Int64(patches[1].x)},${Int64(patches[1].y)}", "c:300,400")
}

@Test
func testCanvasPositionsToPatchWithoutCurrentKeepsOrder(): Unit {
    let patches = canvasPositionsToPatch(
        [
            CanvasPosition("b", 1.6, 2.4),
            CanvasPosition("a", 3.5, -0.5)
        ]
    )
    @Expect(patches.size, 2)
    @Expect("${patches[0].id}:${Int64(patches[0].x)},${Int64(patches[0].y)}", "b:2,2")
    @Expect("${patches[1].id}:${Int64(patches[1].x)},${Int64(patches[1].y)}", "a:4,0")
}

@Test
func testJsRoundMatchesJsMathRound(): Unit {
    @Expect(jsRound(10.4), 10)
    @Expect(jsRound(10.5), 11)
    @Expect(jsRound(-0.5), 0)
    @Expect(jsRound(-1.5), -1)
    @Expect(jsRound(-1.6), -2)
}
