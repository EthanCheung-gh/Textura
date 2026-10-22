package textura.views.sop.logic

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

// 移植自 src/modules/sop/runLogic.test.ts，并补充运行状态机（SopPage.runResult 等）断言。

func runEdges(): Array<SopEdge> {
    return [
        SopEdge("start", "collect", id: "e1"),
        SopEdge("collect", "decision", id: "e2"),
        SopEdge("decision", "check", label: "是", id: "e3"),
        SopEdge("decision", "remind", label: "否", id: "e4"),
        SopEdge("remind", "collect", label: "补充", id: "e5"),
        SopEdge("check", "end", label: "通过", id: "e6")
    ]
}

func runSteps(): Array<SopNode> {
    return [
        SopNode("start", nodeType: SopNodeType.Start),
        SopNode("collect"),
        SopNode("decision", nodeType: SopNodeType.Decision),
        SopNode("check", nodeType: SopNodeType.Check),
        SopNode("remind"),
        SopNode("end", nodeType: SopNodeType.End)
    ]
}

func advancedSession(outcome: RunOutcome): ?RunSession {
    return match (outcome) {
        case RunOutcome.Advanced(session, _, _, _) => Some(session)
        case _ => None
    }
}

func advancedEdge(outcome: RunOutcome): ?String {
    return match (outcome) {
        case RunOutcome.Advanced(_, _, _, viaEdgeId) => Some(viaEdgeId)
        case _ => None
    }
}

func branchOptions(outcome: RunOutcome): ?Array<BranchOption> {
    return match (outcome) {
        case RunOutcome.Branching(_, _, options) => Some(options)
        case _ => None
    }
}

func advanceBranchOptions(outcome: AdvanceResult): ?Array<BranchOption> {
    return match (outcome) {
        case AdvanceResult.Branch(options) => Some(options)
        case _ => None
    }
}

func branchingSession(outcome: RunOutcome): ?RunSession {
    return match (outcome) {
        case RunOutcome.Branching(session, _, _) => Some(session)
        case _ => None
    }
}

func finishedStats(outcome: RunOutcome): ?RunStats {
    return match (outcome) {
        case RunOutcome.Finished(_, _, stats, _) => Some(stats)
        case _ => None
    }
}

func finishedElapsed(outcome: RunOutcome): ?Int64 {
    return match (outcome) {
        case RunOutcome.Finished(_, _, _, elapsedMin) => Some(elapsedMin)
        case _ => None
    }
}

func entryOf(outcome: RunOutcome): ?SopRunEntry {
    return match (outcome) {
        case RunOutcome.Advanced(_, entry, _, _) => Some(entry)
        case RunOutcome.Branching(_, entry, _) => Some(entry)
        case RunOutcome.Finished(_, entry, _, _) => Some(entry)
    }
}

// ---------------------------------------------------------------------------
// nextCandidates / startStepId / advance / summarizeResults / elapsedMinutes
// ---------------------------------------------------------------------------

@Test
func testNextCandidatesKeepsEdgeOrder(): Unit {
    let edges = runEdges()
    let decisionEdges = nextCandidates("decision", edges)
    @Expect(decisionEdges.size, 2)
    @Expect(edgeId(decisionEdges[0]), "e3")
    @Expect(edgeId(decisionEdges[1]), "e4")
    @Expect(nextCandidates("end", edges).size, 0)
}

@Test
func testStartStepPrefersStartNode(): Unit {
    let steps = [SopNode("collect"), SopNode("start", nodeType: SopNodeType.Start)]
    @Expect(startStepId(steps, runEdges()).getOrThrow(), "start")
}

@Test
func testStartStepFallsBackToRoot(): Unit {
    let steps = [SopNode("collect"), SopNode("remind")]
    @Expect(startStepId(steps, runEdges()).getOrThrow(), "collect")
}

@Test
func testStartStepEmptyGraph(): Unit {
    @Expect(startStepId(Array<SopNode>(), Array<SopEdge>()).isNone(), true)
}

@Test
func testAdvanceSingleEdge(): Unit {
    let outcome = advance("start", runEdges())
    match (outcome) {
        case AdvanceResult.Next(stepId, viaEdgeId) =>
            @Expect(stepId, "collect")
            @Expect(viaEdgeId, "e1")
        case _ => @Expect(false, true)
    }
}

@Test
func testAdvanceMultipleEdgesReturnsBranchOptions(): Unit {
    let outcome = advance("decision", runEdges())
    match (outcome) {
        case AdvanceResult.Branch(options) =>
            @Expect(options.size, 2)
            @Expect(options[0].edgeId, "e3")
            @Expect(options[0].to, "check")
            @Expect(options[0].label, "是")
            @Expect(options[1].edgeId, "e4")
            @Expect(options[1].to, "remind")
            @Expect(options[1].label, "否")
        case _ => @Expect(false, true)
    }
}

@Test
func testAdvanceWithChoice(): Unit {
    let outcome = advance("decision", runEdges(), choice: "e4")
    match (outcome) {
        case AdvanceResult.Next(stepId, viaEdgeId) =>
            @Expect(stepId, "remind")
            @Expect(viaEdgeId, "e4")
        case _ => @Expect(false, true)
    }
}

@Test
func testAdvanceInvalidChoiceFallsBackToBranch(): Unit {
    let outcome = advance("decision", runEdges(), choice: "nope")
    @Expect(advanceBranchOptions(outcome).isSome(), true)
}

@Test
func testAdvanceWithoutOutgoingEdgesEnds(): Unit {
    match (advance("end", runEdges())) {
        case AdvanceResult.End => @Expect(true, true)
        case _ => @Expect(false, true)
    }
}

@Test
func testAdvanceSkipStillMovesForward(): Unit {
    let outcome = advance("collect", runEdges())
    match (outcome) {
        case AdvanceResult.Next(stepId, viaEdgeId) =>
            @Expect(stepId, "decision")
            @Expect(viaEdgeId, "e2")
        case _ => @Expect(false, true)
    }
}

@Test
func testAdvanceVisitedBranchesGoLast(): Unit {
    let outcome = advance("decision", runEdges(), visited: ["check"])
    let options = advanceBranchOptions(outcome).getOrThrow()
    @Expect(options.size, 2)
    @Expect(options[0].edgeId, "e4")
    @Expect(options[1].edgeId, "e3")
}

@Test
func testSummarizeResults(): Unit {
    let stats = summarizeResults([RunResult.Pass, RunResult.Pass, RunResult.Fail, RunResult.Skip])
    @Expect(stats.pass, 2)
    @Expect(stats.fail, 1)
    @Expect(stats.skip, 1)
    @Expect(stats.total, 4)
    let empty = summarizeResults(Array<RunResult>())
    @Expect(empty.pass, 0)
    @Expect(empty.fail, 0)
    @Expect(empty.skip, 0)
    @Expect(empty.total, 0)
}

@Test
func testElapsedMinutes(): Unit {
    @Expect(elapsedMinutes("2026-01-01T00:00:00.000Z", "2026-01-01T00:02:20.000Z"), 2)
    @Expect(elapsedMinutes("bad", "2026-01-01T00:02:20.000Z"), 0)
    @Expect(elapsedMinutes("2026-01-01T00:05:00.000Z", "2026-01-01T00:00:00.000Z"), 0)
}

// ---------------------------------------------------------------------------
// 运行状态机（SopPage：startSession / recordResult / moveTo / finishRun）
// ---------------------------------------------------------------------------

@Test
func testStartSession(): Unit {
    let session = startSession(runSteps(), runEdges(), "2026-01-01T00:00:00.000Z").getOrThrow()
    @Expect(session.currentId, "start")
    @Expect(session.visited.size, 1)
    @Expect(session.visited[0], "start")
    @Expect(session.failed.size, 0)
    @Expect(session.results.size, 0)
    @Expect(session.startedAt, "2026-01-01T00:00:00.000Z")
    @Expect(startSession(Array<SopNode>(), Array<SopEdge>(), "2026-01-01T00:00:00.000Z").isNone(), true)
}

@Test
func testRecordResultWritesHistoryEntryAndAdvances(): Unit {
    let session = startSession(runSteps(), runEdges(), "2026-01-01T00:00:00.000Z").getOrThrow()
    let outcome = recordResult(
        session,
        runEdges(),
        RunResult.Pass,
        "sop_1",
        "2026-01-01T00:01:00.000Z",
        entryIdSequence: 1
    )
    let next = advancedSession(outcome).getOrThrow()
    @Expect(next.currentId, "collect")
    @Expect(advancedEdge(outcome).getOrThrow(), "e1")
    @Expect(next.results.size, 1)
    @Expect(next.visited.size, 2)
    @Expect(next.visited[1], "collect")
    let entry = entryOf(outcome).getOrThrow()
    @Expect(entry.id, "run_1")
    @Expect(entry.sopId, "sop_1")
    @Expect(entry.stepId, "start")
    @Expect(entry.at, "2026-01-01T00:01:00.000Z")
    @Expect(runResultId(entry.result), "pass")
    @Expect(entry.note, "")
}

@Test
func testRepeatPassKeepsResultsAndVisitedUnique(): Unit {
    // collect -> decision -> remind -> collect（回边）后再 pass 一次：可重复 pass
    var session = startSession(runSteps(), runEdges(), "2026-01-01T00:00:00.000Z").getOrThrow()
    session = advancedSession(recordResult(session, runEdges(), RunResult.Pass, "sop_1", "2026-01-01T00:01:00.000Z"))
        .getOrThrow()
    session = advancedSession(recordResult(session, runEdges(), RunResult.Pass, "sop_1", "2026-01-01T00:02:00.000Z"))
        .getOrThrow()
    let branch = recordResult(session, runEdges(), RunResult.Pass, "sop_1", "2026-01-01T00:03:00.000Z")
    let options = branchOptions(branch).getOrThrow()
    let chosen = chooseBranch(options, "e4").getOrThrow()
    @Expect(chosen.to, "remind")
    session = moveTo(branchingSession(branch).getOrThrow(), chosen.to)
    session = advancedSession(recordResult(session, runEdges(), RunResult.Pass, "sop_1", "2026-01-01T00:04:00.000Z"))
        .getOrThrow()
    @Expect(session.currentId, "collect")
    @Expect(session.visited.size, 4)
    @Expect(session.results.size, 4)
    // 再经过 collect 一次：visited 不重复
    let again = recordResult(session, runEdges(), RunResult.Pass, "sop_1", "2026-01-01T00:05:00.000Z")
    @Expect(advancedSession(again).getOrThrow().visited.size, 4)
    @Expect(advancedSession(again).getOrThrow().results.size, 5)
}

@Test
func testBranchChoiceCanBeInvalid(): Unit {
    let options = [
        BranchOption("e3", "check", label: "是"),
        BranchOption("e4", "remind", label: "否")
    ]
    @Expect(chooseBranch(options, "e4").getOrThrow().to, "remind")
    @Expect(chooseBranch(options, "nope").isNone(), true)
    @Expect(chooseBranch(options, "").isNone(), true)
}

@Test
func testFailIsRecordedButFlowContinues(): Unit {
    // 未通过不阻断流程：记录到 failed 后仍然按出边前进
    var session = startSession(runSteps(), runEdges(), "2026-01-01T00:00:00.000Z").getOrThrow()
    let outcome = recordResult(session, runEdges(), RunResult.Fail, "sop_1", "2026-01-01T00:01:00.000Z")
    let next = advancedSession(outcome).getOrThrow()
    @Expect(next.currentId, "collect")
    @Expect(next.failed.size, 1)
    @Expect(next.failed[0], "start")
    @Expect(next.results.size, 1)
    // 同一步骤再次失败会再追加一条（与 Web 版数组语义一致）
    session = moveTo(next, "start")
    let again = recordResult(session, runEdges(), RunResult.Fail, "sop_1", "2026-01-01T00:02:00.000Z")
    @Expect(advancedSession(again).getOrThrow().failed.size, 2)
}

@Test
func testRunFinishesAtTerminalStep(): Unit {
    var session = startSession(runSteps(), runEdges(), "2026-01-01T00:00:00.000Z").getOrThrow()
    session = moveTo(session, "end")
    let outcome = recordResult(session, runEdges(), RunResult.Pass, "sop_1", "2026-01-01T00:10:00.000Z",
        entryIdSequence: 7)
    let stats = finishedStats(outcome).getOrThrow()
    @Expect(stats.total, 1)
    @Expect(stats.pass, 1)
    @Expect(finishedElapsed(outcome).getOrThrow(), 10)
    let entry = entryOf(outcome).getOrThrow()
    @Expect(entry.id, "run_7")
    @Expect(entry.stepId, "end")
    @Expect(runEndMessage(stats, finishedElapsed(outcome).getOrThrow()),
        "流程结束：通过 1 / 未通过 0 / 跳过 0，耗时 10 分钟")
}

@Test
func testSkipAdvancesWithoutFailing(): Unit {
    let session = startSession(runSteps(), runEdges(), "2026-01-01T00:00:00.000Z").getOrThrow()
    let outcome = recordResult(session, runEdges(), RunResult.Skip, "sop_1", "2026-01-01T00:01:00.000Z")
    let next = advancedSession(outcome).getOrThrow()
    @Expect(next.currentId, "collect")
    @Expect(next.failed.size, 0)
    @Expect(runResultId(next.results[0]), "skip")
}

@Test
func testStaleSessionDetection(): Unit {
    let session = startSession(runSteps(), runEdges(), "2026-01-01T00:00:00.000Z").getOrThrow()
    @Expect(isStaleSession(session, runSteps()), false)
    @Expect(isStaleSession(moveTo(session, "ghost"), runSteps()), true)
}
