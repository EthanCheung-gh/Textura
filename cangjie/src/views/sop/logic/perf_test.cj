package textura.views.sop.logic

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

// 移植自 src/modules/sop/perf.test.ts 中不依赖 React 引用复用的部分：
// 运行高亮状态优先级、data 结构等价、状态差异集合（视图据此最小重绘）。

func perfSteps(): Array<SopNode> {
    return [
        SopNode("step_0", title: "步骤 0", nodeType: SopNodeType.Start, canvasX: 0.0, canvasY: 0.0),
        SopNode(
            "step_1",
            title: "步骤 1",
            canvasX: 10.0,
            canvasY: 5.0,
            checklist: [ChecklistEntry("chk", text: "检查项", done: false)]
        ),
        SopNode("step_2", title: "步骤 2", canvasX: 20.0, canvasY: 10.0)
    ]
}

@Test
func testNodeStatePriority(): Unit {
    let run = CanvasRunState(currentId: "step_1", visited: ["step_0", "step_1"], failed: ["step_2"])
    @Expect(nodeStateId(nodeStateFor("step_0", run)), "visited")
    @Expect(nodeStateId(nodeStateFor("step_1", run)), "current")
    // current 优先于 failed / visited
    @Expect(nodeStateId(nodeStateFor("step_2", run)), "failed")
    @Expect(nodeStateId(nodeStateFor("step_9", run)), "idle")
    @Expect(nodeStateId(nodeStateFor("step_0", None)), "idle")
}

@Test
func testNodeStateDiffsOnlyRebuildsChangedNodes(): Unit {
    let steps = perfSteps()
    let before = CanvasRunState(currentId: "step_0", visited: ["step_0"])
    let after = CanvasRunState(currentId: "step_1", visited: ["step_0", "step_1"])
    let changed = nodeStateDiffs(steps, before, after)
    @Expect(changed.size, 2)
    @Expect(changed[0], "step_0")
    @Expect(changed[1], "step_1")
    // 无变化时不产生重绘
    @Expect(nodeStateDiffs(steps, None, None).size, 0)
}

@Test
func testSopNodeDataCarriesPrimitiveValues(): Unit {
    let node = SopNode(
        "step_1",
        title: "步骤 1",
        nodeType: SopNodeType.Check,
        owner: "qa",
        durationMin: 15,
        checklist: [ChecklistEntry("a", done: true), ChecklistEntry("b", done: false)]
    )
    let data = sopNodeData(node, Some("#C0663A"), Some(CanvasRunState(currentId: "step_1")))
    @Expect(data.title, "步骤 1")
    @Expect(nodeTypeId(data.nodeType), "check")
    @Expect(data.owner, "qa")
    @Expect(data.durationMin.getOrThrow(), 15)
    @Expect(data.checklistDone, 1)
    @Expect(data.checklistTotal, 2)
    @Expect(data.areaColor.getOrThrow(), "#C0663A")
    @Expect(nodeStateId(data.state), "current")
}

@Test
func testSameNodeData(): Unit {
    let node = SopNode("a", title: "A", durationMin: 5)
    let base = sopNodeData(node, None, None)
    let same = sopNodeData(node, None, None)
    @Expect(sameNodeData(base, same), true)
    let changed = sopNodeData(SopNode("a", title: "A2", durationMin: 5), None, None)
    @Expect(sameNodeData(base, changed), false)
    let stateChanged = sopNodeData(node, None, CanvasRunState(currentId: "a"))
    @Expect(sameNodeData(base, stateChanged), false)
    let colorChanged = sopNodeData(node, Some("#000000"), None)
    @Expect(sameNodeData(base, colorChanged), false)
}

@Test
func testChecklistDoneCount(): Unit {
    let node = SopNode(
        "a",
        checklist: [
            ChecklistEntry("1", done: true),
            ChecklistEntry("2", done: true),
            ChecklistEntry("3", done: false)
        ]
    )
    @Expect(checklistDoneCount(node), 2)
    @Expect(SopNode("b").checklist.size, 0)
}
