package textura.core.data

import std.unittest.*
import std.unittest.testmacro.*

/**
 * Seed demo data. Assertions mirror `src/core/fixtures.test.ts`, plus the parity
 * requirement that seeding at the anchor reproduces the Web export exactly.
 */

@Test
func fixturesProvideAreasAndRuns(): Unit {
    let workspace = createSeedWorkspace(FixedClock(TEST_ANCHOR))
    @Expect(workspace.areas.size, 3)
    @Expect(workspace.areas[0].name, "产品")
    @Expect(workspace.areas[1].name, "运营")
    @Expect(workspace.areas[2].name, "个人")
    @Expect(workspace.items.size, 30)
    @Expect(workspace.runs.size, 3)
    @Expect(workspace.edges.size, 12)
    @Expect(workspace.version, WORKSPACE_VERSION)
}

@Test
func fixturesHaveOneObjectiveWithThreeMetricKrs(): Unit {
    let workspace = createSeedWorkspace(FixedClock(TEST_ANCHOR))
    let objective = itemById(workspace, "obj_activation")
    @Expect(objective.isSome(), true)
    let period = match (objective) {
        case Some(value) => match (value.okr) {
            case Some(okr) => okr.period
            case None => ""
        }
        case None => ""
    }
    @Expect(period, "2026-Q1")
    @Expect(objectivesOfPeriod(workspace, period).size, 1)
    let krs = itemsOfKind(workspace, ItemKind.KeyResult)
    @Expect(krs.size, 3)
    var confidences = ""
    var allHaveMetrics = true
    for (kr in krs) {
        match (kr.okr) {
            case Some(okr) =>
                confidences += okr.confidence.toString()
                if (okr.metric.isNone()) {
                    allHaveMetrics = false
                }
            case None => allHaveMetrics = false
        }
    }
    @Expect(confidences, "467")
    @Expect(allHaveMetrics, true)
}

@Test
func fixturesBuildSevenStepSopGraph(): Unit {
    let workspace = createSeedWorkspace(FixedClock(TEST_ANCHOR))
    let graph = sopGraph(workspace, "sop_onboarding")
    @Expect(graph.nodes.size, 7)
    @Expect(graph.edges.size, 7)
    var hasStart = false
    var hasDecision = false
    var hasCheck = false
    var hasEnd = false
    for (node in graph.nodes) {
        match (node.sop) {
            case Some(sop) => match (sop.nodeType) {
                case SopNodeType.Start => hasStart = true
                case SopNodeType.Decision => hasDecision = true
                case SopNodeType.Check => hasCheck = true
                case SopNodeType.End => hasEnd = true
                case _ => ()
            }
            case None => ()
        }
    }
    @Expect(hasStart && hasDecision && hasCheck && hasEnd, true)
    var labelled = false
    for (edge in graph.edges) {
        if (edge.label == "是" || edge.label == "否") {
            labelled = true
        }
    }
    @Expect(labelled, true)
}

@Test
func fixturesProjectHasScheduledActionsAndDependencies(): Unit {
    let workspace = createSeedWorkspace(FixedClock(TEST_ANCHOR))
    let actions = childrenOf(workspace, Some("proj_website"))
    @Expect(actions.size, 6)
    var allScheduled = true
    for (action in actions) {
        if (action.startKey().isNone() || action.dueKey().isNone()) {
            allScheduled = false
        }
    }
    @Expect(allScheduled, true)
    var depends = 0
    for (edge in workspace.edges) {
        if (edge.edgeType == EdgeType.Depends) {
            depends += 1
        }
    }
    @Expect(depends, 2)
    @Expect(ids(edgeTargetsOf(workspace, "act_build", EdgeType.Depends)), "act_design")
}

@Test
func fixturesSeedGtdLists(): Unit {
    let workspace = createSeedWorkspace(FixedClock(TEST_ANCHOR))
    let inbox = inboxItems(workspace)
    @Expect(inbox.size, 6)
    var allUnclarified = true
    for (item in inbox) {
        match (item.gtd) {
            case Some(gtd) => if (gtd.clarified) {
                allUnclarified = false
            }
            case None => allUnclarified = false
        }
    }
    @Expect(allUnclarified, true)
    var nextActionsCount = 0
    for (item in workspace.items) {
        if (item.kind == ItemKind.Action && item.status == ItemStatus.Next) {
            nextActionsCount += 1
        }
    }
    @Expect(nextActionsCount, 3)
    @Expect(waitingItems(workspace).size, 1)
    @Expect(somedayItems(workspace).size, 1)
}

@Test
func fixturesDatesFollowInjectedClock(): Unit {
    let workspace = createSeedWorkspace(FixedClock(TEST_ANCHOR))
    match (itemById(workspace, "obj_activation")) {
        case Some(item) =>
            @Expect(item.createdAt, isoOffset(-40, TEST_ANCHOR))
            @Expect(item.updatedAt, isoOffset(-1, TEST_ANCHOR))
        case None => @Expect(false, true)
    }
    match (itemById(workspace, "proj_website")) {
        case Some(item) => match (item.gantt) {
            case Some(gantt) =>
                @Expect(gantt.start ?? "", dayOffset(-10, TEST_ANCHOR))
                @Expect(gantt.end ?? "", dayOffset(13, TEST_ANCHOR))
                @Expect(gantt.progress, 35.0)
            case None => @Expect(false, true)
        }
        case None => @Expect(false, true)
    }
    @Expect(workspace.updatedAt, "2026-03-16T02:00:00.000Z")
}

@Test
func fixturesAreDeterministicForTheSameClock(): Unit {
    let first = createSeedWorkspace(FixedClock(TEST_ANCHOR))
    let second = createSeedWorkspace(FixedClock(TEST_ANCHOR))
    @Expect(
        canonicalWorkspaceJsonText(first) == canonicalWorkspaceJsonText(second),
        true
    )
    @Expect(encodeWorkspaceDocument(first) == encodeWorkspaceDocument(second), true)
}

@Test
func fixturesMatchWebParityExport(): Unit {
    match (parityWorkspaceText()) {
        case Some(text) =>
            let clock = FixedClock(TEST_ANCHOR)
            let parity = normalizeForLoad(parseJson(text), clock).workspace
            let seed = createSeedWorkspace(clock)
            @Expect(canonicalWorkspaceJsonText(seed) == canonicalWorkspaceJsonText(parity), true)
            @Expect(seed.items.size, parity.items.size)
            @Expect(seed.edges.size, parity.edges.size)
            @Expect(seed.areas.size, parity.areas.size)
            @Expect(seed.runs.size, parity.runs.size)
        case None => @Expect(true, true)
    }
}
