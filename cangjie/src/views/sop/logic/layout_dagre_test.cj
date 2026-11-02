package textura.views.sop.logic

import std.collection.*
import std.sort.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * 与 dagre 的逐点回归对照。
 *
 * 期望值由真实 `@dagrejs/dagre` 1.1.8（本仓 node_modules）在相同参数下生成后**写死**：
 * - 默认参数：rankdir=TB、nodesep=60、ranksep=90、margin=24；
 * - `PREVIEW_LAYOUT`：nodesep=44、ranksep=60、margin=0；
 * - 节点尺寸 200×60，坐标为节点左上角 `round(center - size/2)`。
 *
 * 覆盖：parity fixture（7 步 + 8 节点含孤立节点，含回边 step_remind→step_collect）、
 * 24 组确定性随机 DAG（4–8 节点）、13 组结构化图形（链/菱形/扇出/森林/LR/共享子节点/
 * 跳层边/环/长链）。全部要求**逐点一致**。
 */
func dagreFixtureDump(positions: HashMap<String, SopPosition>): String {
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

func assertDagreLayout(
    name: String,
    ids: Array<String>,
    edges: Array<SopEdge>,
    expected: String,
    options!: LayoutOptions = LayoutOptions()
) {
    let actual = dagreFixtureDump(layoutIds(ids, edges, options: options))
    @Expect("${name} => ${actual}", "${name} => ${expected}")
}

@Test
func testDagreParityFixtures(): Unit {
    let parity7Ids: Array<String> = ["step_start", "step_welcome", "step_collect", "step_decision", "step_check",
        "step_remind", "step_end"]
    let parity7Edges: Array<SopEdge> = [SopEdge("step_start", "step_welcome"), SopEdge("step_welcome", "step_collect"),
        SopEdge("step_collect", "step_decision"), SopEdge("step_decision", "step_check"),
        SopEdge("step_decision", "step_remind"), SopEdge("step_remind", "step_collect"),
        SopEdge("step_check", "step_end")]
    assertDagreLayout("parity7", parity7Ids, parity7Edges,
        "step_check:24,624 step_collect:154,324 step_decision:34,474 step_end:24,774 step_remind:284,624 step_start:154,24 step_welcome:154,174")
    assertDagreLayout("parity7__preview", parity7Ids, parity7Edges,
        "step_check:0,480 step_collect:122,240 step_decision:10,360 step_end:0,600 step_remind:244,480 step_start:122,0 step_welcome:122,120",
        options: PREVIEW_LAYOUT)
    let parity8Ids: Array<String> = ["step_extra", "step_start", "step_welcome", "step_collect", "step_decision",
        "step_check", "step_remind", "step_end"]
    let parity8Edges: Array<SopEdge> = [SopEdge("step_start", "step_welcome"), SopEdge("step_welcome", "step_collect"),
        SopEdge("step_collect", "step_decision"), SopEdge("step_decision", "step_check"),
        SopEdge("step_decision", "step_remind"), SopEdge("step_remind", "step_collect"),
        SopEdge("step_check", "step_end")]
    assertDagreLayout("parity8", parity8Ids, parity8Edges,
        "step_check:154,624 step_collect:284,324 step_decision:164,474 step_end:154,774 step_extra:24,24 step_remind:414,624 step_start:284,24 step_welcome:284,174")
    assertDagreLayout("parity8__preview", parity8Ids, parity8Edges,
        "step_check:122,480 step_collect:244,240 step_decision:132,360 step_end:122,600 step_extra:0,0 step_remind:366,480 step_start:244,0 step_welcome:244,120",
        options: PREVIEW_LAYOUT)
}

@Test
func testDagreRandomDagFixtures(): Unit {
    let rand00Ids: Array<String> = ["n0", "n1", "n2", "n3"]
    let rand00Edges: Array<SopEdge> = [SopEdge("n3", "n2"), SopEdge("n1", "n0")]
    assertDagreLayout("rand00", rand00Ids, rand00Edges, "n0:24,174 n1:24,24 n2:284,174 n3:284,24")
    assertDagreLayout("rand00__preview", rand00Ids, rand00Edges, "n0:0,120 n1:0,0 n2:244,120 n3:244,0",
        options: PREVIEW_LAYOUT)
    let rand01Ids: Array<String> = ["n0", "n1", "n2", "n3", "n4"]
    let rand01Edges: Array<SopEdge> = [SopEdge("n2", "n1"), SopEdge("n2", "n4")]
    assertDagreLayout("rand01", rand01Ids, rand01Edges, "n0:24,24 n1:154,174 n2:284,24 n3:544,24 n4:414,174")
    assertDagreLayout("rand01__preview", rand01Ids, rand01Edges, "n0:0,0 n1:122,120 n2:244,0 n3:488,0 n4:366,120",
        options: PREVIEW_LAYOUT)
    let rand02Ids: Array<String> = ["n0", "n1", "n2", "n3", "n4", "n5"]
    let rand02Edges: Array<SopEdge> = [SopEdge("n3", "n5"), SopEdge("n3", "n1"), SopEdge("n3", "n0"), SopEdge("n2", "n0"),
        SopEdge("n5", "n4"), SopEdge("n1", "n4")]
    assertDagreLayout("rand02", rand02Ids, rand02Edges, "n0:34,174 n1:294,174 n2:24,24 n3:294,24 n4:434,324 n5:554,174")
    assertDagreLayout("rand02__preview", rand02Ids, rand02Edges,
        "n0:10,120 n1:254,120 n2:0,0 n3:254,0 n4:386,240 n5:498,120", options: PREVIEW_LAYOUT)
    let rand03Ids: Array<String> = ["n0", "n1", "n2", "n3", "n4", "n5", "n6"]
    let rand03Edges: Array<SopEdge> = [SopEdge("n2", "n0"), SopEdge("n1", "n3"), SopEdge("n1", "n6"), SopEdge("n1", "n4"),
        SopEdge("n1", "n0"), SopEdge("n3", "n4"), SopEdge("n6", "n4"), SopEdge("n6", "n0"), SopEdge("n5", "n0")]
    assertDagreLayout("rand03", rand03Ids, rand03Edges,
        "n0:234,324 n1:514,24 n2:24,174 n3:844,174 n4:704,324 n5:304,174 n6:584,174")
    assertDagreLayout("rand03__preview", rand03Ids, rand03Edges,
        "n0:198,240 n1:462,0 n2:0,120 n3:772,120 n4:640,240 n5:264,120 n6:528,120", options: PREVIEW_LAYOUT)
    let rand04Ids: Array<String> = ["n0", "n1", "n2", "n3", "n4", "n5", "n6", "n7"]
    let rand04Edges: Array<SopEdge> = [SopEdge("n0", "n2"), SopEdge("n0", "n6"), SopEdge("n0", "n1"), SopEdge("n2", "n5"),
        SopEdge("n6", "n4"), SopEdge("n1", "n4"), SopEdge("n4", "n5"), SopEdge("n4", "n3"), SopEdge("n5", "n7")]
    assertDagreLayout("rand04", rand04Ids, rand04Edges,
        "n0:224,24 n1:484,174 n2:24,324 n3:364,474 n4:354,324 n5:34,474 n6:224,174 n7:34,624")
    assertDagreLayout("rand04__preview", rand04Ids, rand04Edges,
        "n0:188,0 n1:432,120 n2:0,240 n3:320,360 n4:310,240 n5:10,360 n6:188,120 n7:10,480", options: PREVIEW_LAYOUT)
    let rand05Ids: Array<String> = ["n0", "n1", "n2", "n3"]
    let rand05Edges: Array<SopEdge> = Array<SopEdge>()
    assertDagreLayout("rand05", rand05Ids, rand05Edges, "n0:24,24 n1:284,24 n2:544,24 n3:804,24")
    assertDagreLayout("rand05__preview", rand05Ids, rand05Edges, "n0:0,0 n1:244,0 n2:488,0 n3:732,0",
        options: PREVIEW_LAYOUT)
    let rand06Ids: Array<String> = ["n0", "n1", "n2", "n3", "n4"]
    let rand06Edges: Array<SopEdge> = [SopEdge("n0", "n4"), SopEdge("n0", "n1"), SopEdge("n0", "n3"), SopEdge("n0", "n2"),
        SopEdge("n4", "n1"), SopEdge("n4", "n2")]
    assertDagreLayout("rand06", rand06Ids, rand06Edges, "n0:234,24 n1:234,324 n2:504,324 n3:24,174 n4:304,174")
    assertDagreLayout("rand06__preview", rand06Ids, rand06Edges, "n0:198,0 n1:198,240 n2:452,240 n3:0,120 n4:264,120",
        options: PREVIEW_LAYOUT)
    let rand07Ids: Array<String> = ["n0", "n1", "n2", "n3", "n4", "n5"]
    let rand07Edges: Array<SopEdge> = [SopEdge("n5", "n2"), SopEdge("n5", "n1"), SopEdge("n4", "n2"), SopEdge("n4", "n1"),
        SopEdge("n2", "n3"), SopEdge("n1", "n0"), SopEdge("n3", "n0")]
    assertDagreLayout("rand07", rand07Ids, rand07Edges, "n0:164,474 n1:24,174 n2:304,174 n3:304,324 n4:294,24 n5:34,24")
    assertDagreLayout("rand07__preview", rand07Ids, rand07Edges,
        "n0:132,360 n1:0,120 n2:264,120 n3:264,240 n4:254,0 n5:10,0", options: PREVIEW_LAYOUT)
    let rand08Ids: Array<String> = ["n0", "n1", "n2", "n3", "n4", "n5", "n6"]
    let rand08Edges: Array<SopEdge> = [SopEdge("n3", "n6"), SopEdge("n5", "n4"), SopEdge("n5", "n1"), SopEdge("n4", "n6"),
        SopEdge("n4", "n0"), SopEdge("n4", "n2"), SopEdge("n0", "n1")]
    assertDagreLayout("rand08", rand08Ids, rand08Edges,
        "n0:294,324 n1:504,474 n2:554,324 n3:24,174 n4:294,174 n5:494,24 n6:34,324")
    assertDagreLayout("rand08__preview", rand08Ids, rand08Edges,
        "n0:254,240 n1:452,360 n2:498,240 n3:0,120 n4:254,120 n5:442,0 n6:10,240", options: PREVIEW_LAYOUT)
    let rand09Ids: Array<String> = ["n0", "n1", "n2", "n3", "n4", "n5", "n6", "n7"]
    let rand09Edges: Array<SopEdge> = [SopEdge("n2", "n0"), SopEdge("n6", "n1"), SopEdge("n3", "n0"), SopEdge("n3", "n5"),
        SopEdge("n0", "n4"), SopEdge("n7", "n1")]
    assertDagreLayout("rand09", rand09Ids, rand09Edges,
        "n0:34,174 n1:424,174 n2:24,24 n3:554,24 n4:34,324 n5:684,174 n6:284,24 n7:814,24")
    assertDagreLayout("rand09__preview", rand09Ids, rand09Edges,
        "n0:10,120 n1:376,120 n2:0,0 n3:498,0 n4:10,240 n5:620,120 n6:244,0 n7:742,0", options: PREVIEW_LAYOUT)
    let rand10Ids: Array<String> = ["n0", "n1", "n2", "n3"]
    let rand10Edges: Array<SopEdge> = [SopEdge("n3", "n0")]
    assertDagreLayout("rand10", rand10Ids, rand10Edges, "n0:544,174 n1:24,24 n2:284,24 n3:544,24")
    assertDagreLayout("rand10__preview", rand10Ids, rand10Edges, "n0:488,120 n1:0,0 n2:244,0 n3:488,0",
        options: PREVIEW_LAYOUT)
    let rand11Ids: Array<String> = ["n0", "n1", "n2", "n3", "n4"]
    let rand11Edges: Array<SopEdge> = [SopEdge("n0", "n2"), SopEdge("n0", "n1"), SopEdge("n3", "n1")]
    assertDagreLayout("rand11", rand11Ids, rand11Edges, "n0:34,24 n1:294,174 n2:24,174 n3:304,24 n4:564,24")
    assertDagreLayout("rand11__preview", rand11Ids, rand11Edges, "n0:10,0 n1:254,120 n2:0,120 n3:264,0 n4:508,0",
        options: PREVIEW_LAYOUT)
    let rand12Ids: Array<String> = ["n0", "n1", "n2", "n3", "n4", "n5"]
    let rand12Edges: Array<SopEdge> = [SopEdge("n2", "n3")]
    assertDagreLayout("rand12", rand12Ids, rand12Edges, "n0:24,24 n1:284,24 n2:544,24 n3:544,174 n4:804,24 n5:1064,24")
    assertDagreLayout("rand12__preview", rand12Ids, rand12Edges, "n0:0,0 n1:244,0 n2:488,0 n3:488,120 n4:732,0 n5:976,0",
        options: PREVIEW_LAYOUT)
    let rand13Ids: Array<String> = ["n0", "n1", "n2", "n3", "n4", "n5", "n6"]
    let rand13Edges: Array<SopEdge> = [SopEdge("n1", "n4"), SopEdge("n3", "n0")]
    assertDagreLayout("rand13", rand13Ids, rand13Edges,
        "n0:544,174 n1:24,24 n2:284,24 n3:544,24 n4:24,174 n5:804,24 n6:1064,24")
    assertDagreLayout("rand13__preview", rand13Ids, rand13Edges,
        "n0:488,120 n1:0,0 n2:244,0 n3:488,0 n4:0,120 n5:732,0 n6:976,0", options: PREVIEW_LAYOUT)
    let rand14Ids: Array<String> = ["n0", "n1", "n2", "n3", "n4", "n5", "n6", "n7"]
    let rand14Edges: Array<SopEdge> = [SopEdge("n3", "n4"), SopEdge("n3", "n0"), SopEdge("n4", "n5"), SopEdge("n4", "n0"),
        SopEdge("n4", "n7"), SopEdge("n5", "n7"), SopEdge("n0", "n7"), SopEdge("n0", "n6")]
    assertDagreLayout("rand14", rand14Ids, rand14Edges,
        "n0:684,324 n1:24,24 n2:284,24 n3:544,24 n4:424,174 n5:424,324 n6:694,474 n7:354,474")
    assertDagreLayout("rand14__preview", rand14Ids, rand14Edges,
        "n0:620,240 n1:0,0 n2:244,0 n3:488,0 n4:376,120 n5:376,240 n6:630,360 n7:310,360", options: PREVIEW_LAYOUT)
    let rand15Ids: Array<String> = ["n0", "n1", "n2", "n3"]
    let rand15Edges: Array<SopEdge> = Array<SopEdge>()
    assertDagreLayout("rand15", rand15Ids, rand15Edges, "n0:24,24 n1:284,24 n2:544,24 n3:804,24")
    assertDagreLayout("rand15__preview", rand15Ids, rand15Edges, "n0:0,0 n1:244,0 n2:488,0 n3:732,0",
        options: PREVIEW_LAYOUT)
    let rand16Ids: Array<String> = ["n0", "n1", "n2", "n3", "n4"]
    let rand16Edges: Array<SopEdge> = [SopEdge("n1", "n3"), SopEdge("n3", "n2"), SopEdge("n3", "n0"), SopEdge("n2", "n4"),
        SopEdge("n4", "n0")]
    assertDagreLayout("rand16", rand16Ids, rand16Edges, "n0:24,624 n1:24,24 n2:94,324 n3:24,174 n4:94,474")
    assertDagreLayout("rand16__preview", rand16Ids, rand16Edges, "n0:0,480 n1:0,0 n2:66,240 n3:0,120 n4:66,360",
        options: PREVIEW_LAYOUT)
    let rand17Ids: Array<String> = ["n0", "n1", "n2", "n3", "n4", "n5"]
    let rand17Edges: Array<SopEdge> = [SopEdge("n1", "n5"), SopEdge("n1", "n0"), SopEdge("n2", "n4"), SopEdge("n2", "n3"),
        SopEdge("n4", "n3"), SopEdge("n4", "n5"), SopEdge("n4", "n0")]
    assertDagreLayout("rand17", rand17Ids, rand17Edges,
        "n0:584,324 n1:224,174 n2:174,24 n3:24,324 n4:484,174 n5:314,324")
    assertDagreLayout("rand17__preview", rand17Ids, rand17Edges,
        "n0:528,240 n1:188,120 n2:142,0 n3:0,240 n4:432,120 n5:274,240", options: PREVIEW_LAYOUT)
    let rand18Ids: Array<String> = ["n0", "n1", "n2", "n3", "n4", "n5", "n6"]
    let rand18Edges: Array<SopEdge> = [SopEdge("n0", "n2"), SopEdge("n0", "n4"), SopEdge("n3", "n5"), SopEdge("n1", "n2"),
        SopEdge("n1", "n5"), SopEdge("n6", "n2"), SopEdge("n6", "n4")]
    assertDagreLayout("rand18", rand18Ids, rand18Edges,
        "n0:24,24 n1:564,24 n2:164,174 n3:824,24 n4:424,174 n5:814,174 n6:294,24")
    assertDagreLayout("rand18__preview", rand18Ids, rand18Edges,
        "n0:0,0 n1:508,0 n2:132,120 n3:752,0 n4:376,120 n5:742,120 n6:254,0", options: PREVIEW_LAYOUT)
    let rand19Ids: Array<String> = ["n0", "n1", "n2", "n3", "n4", "n5", "n6", "n7"]
    let rand19Edges: Array<SopEdge> = [SopEdge("n2", "n6"), SopEdge("n2", "n5"), SopEdge("n2", "n7"), SopEdge("n3", "n0"),
        SopEdge("n3", "n7"), SopEdge("n6", "n4"), SopEdge("n0", "n7")]
    assertDagreLayout("rand19", rand19Ids, rand19Edges,
        "n0:624,174 n1:304,24 n2:234,174 n3:564,24 n4:284,474 n5:24,324 n6:284,324 n7:544,324")
    assertDagreLayout("rand19__preview", rand19Ids, rand19Edges,
        "n0:564,120 n1:264,0 n2:198,120 n3:508,0 n4:244,360 n5:0,240 n6:244,240 n7:488,240", options: PREVIEW_LAYOUT)
    let rand20Ids: Array<String> = ["n0", "n1", "n2", "n3"]
    let rand20Edges: Array<SopEdge> = [SopEdge("n2", "n3"), SopEdge("n3", "n1")]
    assertDagreLayout("rand20", rand20Ids, rand20Edges, "n0:24,24 n1:284,324 n2:284,24 n3:284,174")
    assertDagreLayout("rand20__preview", rand20Ids, rand20Edges, "n0:0,0 n1:244,240 n2:244,0 n3:244,120",
        options: PREVIEW_LAYOUT)
    let rand21Ids: Array<String> = ["n0", "n1", "n2", "n3", "n4"]
    let rand21Edges: Array<SopEdge> = [SopEdge("n4", "n1"), SopEdge("n0", "n3")]
    assertDagreLayout("rand21", rand21Ids, rand21Edges, "n0:24,24 n1:544,174 n2:284,24 n3:24,174 n4:544,24")
    assertDagreLayout("rand21__preview", rand21Ids, rand21Edges, "n0:0,0 n1:488,120 n2:244,0 n3:0,120 n4:488,0",
        options: PREVIEW_LAYOUT)
    let rand22Ids: Array<String> = ["n0", "n1", "n2", "n3", "n4", "n5"]
    let rand22Edges: Array<SopEdge> = [SopEdge("n5", "n1"), SopEdge("n5", "n4"), SopEdge("n5", "n0"), SopEdge("n1", "n3")]
    assertDagreLayout("rand22", rand22Ids, rand22Edges, "n0:24,174 n1:284,174 n2:24,24 n3:284,324 n4:544,174 n5:284,24")
    assertDagreLayout("rand22__preview", rand22Ids, rand22Edges,
        "n0:0,120 n1:244,120 n2:0,0 n3:244,240 n4:488,120 n5:244,0", options: PREVIEW_LAYOUT)
    let rand23Ids: Array<String> = ["n0", "n1", "n2", "n3", "n4", "n5", "n6"]
    let rand23Edges: Array<SopEdge> = [SopEdge("n4", "n6"), SopEdge("n4", "n0"), SopEdge("n5", "n6"), SopEdge("n5", "n3"),
        SopEdge("n6", "n2"), SopEdge("n6", "n0"), SopEdge("n3", "n2"), SopEdge("n2", "n1"), SopEdge("n1", "n0")]
    assertDagreLayout("rand23", rand23Ids, rand23Edges,
        "n0:94,624 n1:404,474 n2:404,324 n3:414,174 n4:24,24 n5:404,24 n6:154,174")
    assertDagreLayout("rand23__preview", rand23Ids, rand23Edges,
        "n0:66,480 n1:356,360 n2:356,240 n3:366,120 n4:0,0 n5:356,0 n6:122,120", options: PREVIEW_LAYOUT)
}

@Test
func testDagreStructuredFixtures(): Unit {
    let singleIds: Array<String> = ["solo"]
    let singleEdges: Array<SopEdge> = Array<SopEdge>()
    assertDagreLayout("single", singleIds, singleEdges, "solo:24,24")
    assertDagreLayout("single__preview", singleIds, singleEdges, "solo:0,0", options: PREVIEW_LAYOUT)
    let chain4Ids: Array<String> = ["n0", "n1", "n2", "n3"]
    let chain4Edges: Array<SopEdge> = [SopEdge("n0", "n1"), SopEdge("n1", "n2"), SopEdge("n2", "n3")]
    assertDagreLayout("chain4", chain4Ids, chain4Edges, "n0:24,24 n1:24,174 n2:24,324 n3:24,474")
    assertDagreLayout("chain4__preview", chain4Ids, chain4Edges, "n0:0,0 n1:0,120 n2:0,240 n3:0,360",
        options: PREVIEW_LAYOUT)
    let diamondIds: Array<String> = ["root", "a", "b", "end"]
    let diamondEdges: Array<SopEdge> = [SopEdge("root", "a"), SopEdge("root", "b"), SopEdge("a", "end"),
        SopEdge("b", "end")]
    assertDagreLayout("diamond", diamondIds, diamondEdges, "a:24,174 b:284,174 end:154,324 root:154,24")
    assertDagreLayout("diamond__preview", diamondIds, diamondEdges, "a:0,120 b:244,120 end:122,240 root:122,0",
        options: PREVIEW_LAYOUT)
    let fanOut3Ids: Array<String> = ["root", "a", "b", "c", "end"]
    let fanOut3Edges: Array<SopEdge> = [SopEdge("root", "a"), SopEdge("root", "b"), SopEdge("root", "c"),
        SopEdge("a", "end"), SopEdge("b", "end"), SopEdge("c", "end")]
    assertDagreLayout("fanOut3", fanOut3Ids, fanOut3Edges, "a:24,174 b:284,174 c:544,174 end:284,324 root:284,24")
    assertDagreLayout("fanOut3__preview", fanOut3Ids, fanOut3Edges, "a:0,120 b:244,120 c:488,120 end:244,240 root:244,0",
        options: PREVIEW_LAYOUT)
    let fanOut5Ids: Array<String> = ["root", "a", "b", "c", "d", "e"]
    let fanOut5Edges: Array<SopEdge> = [SopEdge("root", "a"), SopEdge("root", "b"), SopEdge("root", "c"),
        SopEdge("root", "d"), SopEdge("root", "e")]
    assertDagreLayout("fanOut5", fanOut5Ids, fanOut5Edges,
        "a:24,174 b:284,174 c:544,174 d:804,174 e:1064,174 root:544,24")
    assertDagreLayout("fanOut5__preview", fanOut5Ids, fanOut5Edges,
        "a:0,120 b:244,120 c:488,120 d:732,120 e:976,120 root:488,0", options: PREVIEW_LAYOUT)
    let forestIds: Array<String> = ["r1", "r2", "x", "y"]
    let forestEdges: Array<SopEdge> = [SopEdge("r1", "x"), SopEdge("r2", "y")]
    assertDagreLayout("forest", forestIds, forestEdges, "r1:24,24 r2:284,24 x:24,174 y:284,174")
    assertDagreLayout("forest__preview", forestIds, forestEdges, "r1:0,0 r2:244,0 x:0,120 y:244,120",
        options: PREVIEW_LAYOUT)
    let lrChainIds: Array<String> = ["a", "b", "c"]
    let lrChainEdges: Array<SopEdge> = [SopEdge("a", "b"), SopEdge("b", "c")]
    assertDagreLayout("lrChain", lrChainIds, lrChainEdges, "a:24,24 b:24,174 c:24,324")
    assertDagreLayout("lrChain__preview", lrChainIds, lrChainEdges, "a:0,0 b:0,120 c:0,240", options: PREVIEW_LAYOUT)
    let sharedChildIds: Array<String> = ["root", "a", "b", "c", "d"]
    let sharedChildEdges: Array<SopEdge> = [SopEdge("root", "a"), SopEdge("root", "b"), SopEdge("a", "c"),
        SopEdge("b", "c"), SopEdge("c", "d")]
    assertDagreLayout("sharedChild", sharedChildIds, sharedChildEdges,
        "a:24,174 b:284,174 c:154,324 d:154,474 root:154,24")
    assertDagreLayout("sharedChild__preview", sharedChildIds, sharedChildEdges,
        "a:0,120 b:244,120 c:122,240 d:122,360 root:122,0", options: PREVIEW_LAYOUT)
    let skipEdgeIds: Array<String> = ["root", "a", "b", "d", "e"]
    let skipEdgeEdges: Array<SopEdge> = [SopEdge("root", "a"), SopEdge("root", "b"), SopEdge("a", "d"), SopEdge("b", "e"),
        SopEdge("d", "e")]
    assertDagreLayout("skipEdge", skipEdgeIds, skipEdgeEdges, "a:284,174 b:24,324 d:284,324 e:154,474 root:154,24")
    assertDagreLayout("skipEdge__preview", skipEdgeIds, skipEdgeEdges,
        "a:244,120 b:0,240 d:244,240 e:122,360 root:122,0", options: PREVIEW_LAYOUT)
    let cycle2Ids: Array<String> = ["a", "b"]
    let cycle2Edges: Array<SopEdge> = [SopEdge("a", "b"), SopEdge("b", "a")]
    assertDagreLayout("cycle2", cycle2Ids, cycle2Edges, "a:24,24 b:24,174")
    assertDagreLayout("cycle2__preview", cycle2Ids, cycle2Edges, "a:0,0 b:0,120", options: PREVIEW_LAYOUT)
    let cycle3Ids: Array<String> = ["a", "b", "c"]
    let cycle3Edges: Array<SopEdge> = [SopEdge("a", "b"), SopEdge("b", "c"), SopEdge("c", "a")]
    assertDagreLayout("cycle3", cycle3Ids, cycle3Edges, "a:94,24 b:24,174 c:94,324")
    assertDagreLayout("cycle3__preview", cycle3Ids, cycle3Edges, "a:66,0 b:0,120 c:66,240", options: PREVIEW_LAYOUT)
    let cycleWithTailIds: Array<String> = ["a", "b", "c", "d"]
    let cycleWithTailEdges: Array<SopEdge> = [SopEdge("a", "b"), SopEdge("b", "c"), SopEdge("c", "a"), SopEdge("c", "d")]
    assertDagreLayout("cycleWithTail", cycleWithTailIds, cycleWithTailEdges, "a:94,24 b:24,174 c:94,324 d:94,474")
    assertDagreLayout("cycleWithTail__preview", cycleWithTailIds, cycleWithTailEdges, "a:66,0 b:0,120 c:66,240 d:66,360",
        options: PREVIEW_LAYOUT)
    let longChain10Ids: Array<String> = ["n0", "n1", "n2", "n3", "n4", "n5", "n6", "n7", "n8", "n9"]
    let longChain10Edges: Array<SopEdge> = [SopEdge("n0", "n1"), SopEdge("n1", "n2"), SopEdge("n2", "n3"),
        SopEdge("n3", "n4"), SopEdge("n4", "n5"), SopEdge("n5", "n6"), SopEdge("n6", "n7"), SopEdge("n7", "n8"),
        SopEdge("n8", "n9")]
    assertDagreLayout("longChain10", longChain10Ids, longChain10Edges,
        "n0:24,24 n1:24,174 n2:24,324 n3:24,474 n4:24,624 n5:24,774 n6:24,924 n7:24,1074 n8:24,1224 n9:24,1374")
    assertDagreLayout("longChain10__preview", longChain10Ids, longChain10Edges,
        "n0:0,0 n1:0,120 n2:0,240 n3:0,360 n4:0,480 n5:0,600 n6:0,720 n7:0,840 n8:0,960 n9:0,1080",
        options: PREVIEW_LAYOUT)
}

@Test
func testDagreParityLeftRight(): Unit {
    let ids: Array<String> = ["a", "b", "c"]
    let edges: Array<SopEdge> = [SopEdge("a", "b"), SopEdge("b", "c")]
    assertDagreLayout("lrChain__lr", ids, edges, "a:24,24 b:314,24 c:604,24",
        options: LayoutOptions(rankdir: RankDir.LeftRight))
}
