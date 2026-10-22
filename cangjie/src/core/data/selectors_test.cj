package textura.core.data

import std.unittest.*
import std.unittest.testmacro.*

/**
 * Selector tests. Assertions mirror `src/core/selectors.test.ts` so behaviour
 * differences show up as test failures, not as view bugs.
 */

@Test
func selectorsRollupAveragesKrMetrics(): Unit {
    let workspace = testWorkspace([
        testItem("obj", ItemKind.Objective, "目标"),
        testItem(
            "kr1",
            ItemKind.KeyResult,
            "KR1",
            parentId: "obj",
            order: 0,
            okr: OkrData("2026-Q1", 5, metric: Metric(0.0, 100.0, 50.0, "%"))
        ),
        testItem(
            "kr2",
            ItemKind.KeyResult,
            "KR2",
            parentId: "obj",
            order: 1,
            okr: OkrData("2026-Q1", 5, metric: Metric(40.0, 60.0, 50.0, "%"))
        )
    ])
    @Expect(rollupProgress(workspace, "obj"), 50)
    @Expect(rollupProgress(workspace, "kr1"), 50)
    @Expect(rollupProgress(workspace, "kr2"), 50)
}

@Test
func selectorsRollupFallsBackToChildCompletion(): Unit {
    let workspace = testWorkspace([
        testItem("obj2", ItemKind.Objective, "目标二"),
        testItem("kr3", ItemKind.KeyResult, "KR3", parentId: "obj2", okr: OkrData("2026-Q1", 5)),
        testItem("child-a", ItemKind.Action, "A", parentId: "kr3", order: 0, status: ItemStatus.Done),
        testItem("child-b", ItemKind.Action, "B", parentId: "kr3", order: 1)
    ])
    @Expect(rollupProgress(workspace, "kr3"), 50)
    @Expect(rollupProgress(workspace, "obj2"), 50)
}

@Test
func selectorsRollupCoversProjectsSopsAndLeaves(): Unit {
    let workspace = testWorkspace([
        testItem("proj", ItemKind.Project, "项目"),
        testItem("p1", ItemKind.Action, "P1", parentId: "proj", order: 0, status: ItemStatus.Done),
        testItem("p2", ItemKind.Action, "P2", parentId: "proj", order: 1),
        testItem("p3", ItemKind.Action, "P3", parentId: "proj", order: 2),
        testItem("sop", ItemKind.Sop, "SOP"),
        testItem("s1", ItemKind.Step, "S1", parentId: "sop", status: ItemStatus.Done),
        testItem("done-action", ItemKind.Action, "完成", status: ItemStatus.Done),
        testItem("open-action", ItemKind.Action, "未完成")
    ])
    @Expect(rollupProgress(workspace, "proj"), 33)
    @Expect(rollupProgress(workspace, "sop"), 100)
    @Expect(rollupProgress(workspace, "done-action"), 100)
    @Expect(rollupProgress(workspace, "open-action"), 0)
    @Expect(rollupProgress(workspace, "missing"), 0)
}

@Test
func selectorsRollupClampsMetricProgress(): Unit {
    let workspace = testWorkspace([
        testItem(
            "over",
            ItemKind.KeyResult,
            "超额",
            okr: OkrData("2026-Q1", 5, metric: Metric(0.0, 10.0, 25.0, "个"))
        ),
        testItem(
            "under",
            ItemKind.KeyResult,
            "落后",
            okr: OkrData("2026-Q1", 5, metric: Metric(10.0, 20.0, 2.0, "个"))
        )
    ])
    @Expect(rollupProgress(workspace, "over"), 100)
    @Expect(rollupProgress(workspace, "under"), 0)
}

@Test
func selectorsScheduledRangeIsBoundaryInclusive(): Unit {
    let workspace = testWorkspace([
        testItem("a", ItemKind.Action, "A", gantt: GanttData(start: "2026-01-01", end: "2026-01-05", progress: 0.0)),
        testItem("b", ItemKind.Action, "B", gantt: GanttData(start: None, end: "2026-01-03", progress: 0.0)),
        testItem("c", ItemKind.Action, "C", gantt: GanttData(start: "2026-01-10", end: "2026-01-12", progress: 0.0)),
        testItem("unscheduled", ItemKind.Action, "无日期")
    ])
    @Expect(ids(scheduledItemsInRange(workspace, "2026-01-04", "2026-01-06")), "a")
    @Expect(ids(scheduledItemsInRange(workspace, "2026-01-03", "2026-01-03")), "a,b")
    @Expect(ids(scheduledItemsInRange(workspace, "2026-01-06", "2026-01-09")), "")
    @Expect(
        ids(scheduledItemsInRange(workspace, "2026-01-10T08:00:00.000Z", "2026-01-01T09:30:00.000Z")),
        "a,b,c"
    )
}

@Test
func selectorsNextActionsFilterKinds(): Unit {
    let workspace = testWorkspace([
        testItem("action", ItemKind.Action, "行动", order: 2),
        testItem("project", ItemKind.Project, "项目", order: 1),
        testItem("step", ItemKind.Step, "步骤", order: 0),
        testItem("note", ItemKind.Note, "笔记", order: 0),
        testItem("done", ItemKind.Action, "完成", status: ItemStatus.Done),
        testItem("inbox", ItemKind.Action, "收件箱", status: ItemStatus.Inbox)
    ])
    // SOP steps belong to the flow view, not to GTD next actions.
    @Expect(ids(nextActions(workspace)), "project,action")
}

@Test
func selectorsChildrenSortedByOrder(): Unit {
    let workspace = testWorkspace([
        testItem("parent", ItemKind.Project, "父"),
        testItem("later", ItemKind.Action, "后", parentId: "parent", order: 5),
        testItem("earlier", ItemKind.Action, "前", parentId: "parent", order: 1)
    ])
    @Expect(ids(childrenOf(workspace, Some("parent"))), "earlier,later")
    @Expect(ids(rootItems(workspace)), "parent")
}

@Test
func selectorsSurviveSelfLoop(): Unit {
    let workspace = testWorkspace([
        testItem("a", ItemKind.Action, "A", parentId: "a")
    ])
    @Expect(ids(descendantsOf(workspace, "a")), "")
    @Expect(cycleText(findParentCycles(workspace)), "a>a")
    @Expect(treeDepth(workspace, "a"), 0)
}

@Test
func selectorsHandleTwoNodeCycle(): Unit {
    let workspace = testWorkspace([
        testItem("a", ItemKind.Action, "A", parentId: "b", order: 0),
        testItem("b", ItemKind.Action, "B", parentId: "a", order: 1),
        testItem("c", ItemKind.Action, "C", parentId: "b", order: 2),
        testItem("d", ItemKind.Action, "D", parentId: "c", order: 3)
    ])
    @Expect(ids(descendantsOf(workspace, "a")), "b,c,d")
    @Expect(cycleText(findParentCycles(workspace)), "a>b>a")
}

@Test
func selectorsReportDisjointCycles(): Unit {
    let twoCycles = testWorkspace([
        testItem("a", ItemKind.Action, "A", parentId: "b", order: 0),
        testItem("b", ItemKind.Action, "B", parentId: "a", order: 1),
        testItem("x", ItemKind.Action, "X", parentId: "y", order: 2),
        testItem("y", ItemKind.Action, "Y", parentId: "x", order: 3)
    ])
    @Expect(cycleText(findParentCycles(twoCycles)), "a>b>a|x>y>x")

    let healthy = testWorkspace([
        testItem("root", ItemKind.Project, "根", order: 0),
        testItem("child", ItemKind.Action, "子", parentId: "root", order: 0)
    ])
    @Expect(findParentCycles(healthy).size, 0)
}

@Test
func selectorsTreePathsAndDepth(): Unit {
    let workspace = testWorkspace([
        testItem("obj", ItemKind.Objective, "目标"),
        testItem("proj", ItemKind.Project, "项目", parentId: "obj"),
        testItem("act", ItemKind.Action, "行动", parentId: "proj")
    ])
    @Expect(treeDepth(workspace, "obj"), 0)
    @Expect(treeDepth(workspace, "proj"), 1)
    @Expect(treeDepth(workspace, "act"), 2)
    @Expect(itemPathTitles(workspace, "act").size, 3)
    @Expect(parentPathText(workspace, "act"), "目标 / 项目")
    @Expect(ids(ancestorsOf(workspace, "act")), "proj,obj")
}

@Test
func selectorsInboxAndStatusCounts(): Unit {
    let workspace = testWorkspace([
        testItem("i1", ItemKind.Action, "收件", status: ItemStatus.Inbox),
        testItem("w1", ItemKind.Action, "等待", status: ItemStatus.Waiting),
        testItem("s1", ItemKind.Action, "将来", status: ItemStatus.Someday),
        testItem("d1", ItemKind.Action, "完成", status: ItemStatus.Done)
    ])
    @Expect(inboxItems(workspace).size, 1)
    @Expect(waitingItems(workspace).size, 1)
    @Expect(somedayItems(workspace).size, 1)
    let counts = countByStatus(workspace)
    @Expect(counts.get("inbox") ?? 0, 1)
    @Expect(counts.get("done") ?? 0, 1)
    @Expect(counts.get("next") ?? 0, 0)
}

@Test
func selectorsOverdueAndDueTodayIgnoreClosedItems(): Unit {
    let workspace = testWorkspace([
        testItem("late", ItemKind.Action, "超期", gantt: GanttData(start: "2026-03-10", end: "2026-03-14", progress: 0.0)),
        testItem("today", ItemKind.Action, "今天", gantt: GanttData(start: "2026-03-14", end: "2026-03-16", progress: 0.0)),
        testItem(
            "late-done",
            ItemKind.Action,
            "已完成超期",
            status: ItemStatus.Done,
            gantt: GanttData(start: "2026-03-10", end: "2026-03-12", progress: 100.0)
        ),
        testItem("future", ItemKind.Action, "未来", gantt: GanttData(start: "2026-03-20", end: "2026-03-25", progress: 0.0))
    ])
    @Expect(ids(overdueItems(workspace, TEST_TODAY)), "late")
    @Expect(ids(dueTodayItems(workspace, TEST_TODAY)), "today")
}

@Test
func selectorsTodayFocusMergesAndDeduplicates(): Unit {
    let workspace = testWorkspace([
        testItem(
            "late",
            ItemKind.Action,
            "超期",
            order: 1,
            gantt: GanttData(start: "2026-03-10", end: "2026-03-13", progress: 0.0)
        ),
        testItem(
            "today",
            ItemKind.Action,
            "今天",
            order: 2,
            gantt: GanttData(start: "2026-03-10", end: "2026-03-16", progress: 0.0)
        ),
        testItem("undated", ItemKind.Action, "无日期", order: 0),
        testItem(
            "dated-next",
            ItemKind.Action,
            "未来下一步",
            order: 3,
            gantt: GanttData(start: "2026-03-20", end: "2026-03-22", progress: 0.0)
        )
    ])
    let focus = buildTodayFocus(workspace, TEST_TODAY)
    // overdue first, then today, then undated; the future-dated next action is
    // excluded from the undated bucket.
    @Expect(focus.size, 3)
    @Expect(focus[0].item.id, "late")
    @Expect(focus[0].daysLate, 3)
    @Expect(focusSourceWire(focus[0].source), "none")
    @Expect(focus[1].item.id, "today")
    @Expect(focus[2].item.id, "undated")
    let counts = countFocusBuckets(focus)
    @Expect(counts.overdue, 1)
    @Expect(counts.today, 1)
    @Expect(counts.undated, 1)
    let page = paginateFocus(focus, 2)
    @Expect(page.shown, 2)
    @Expect(page.remaining, 1)
    @Expect(page.hasMore, true)
}

@Test
func selectorsTodayFocusMarksSopAndOkrSources(): Unit {
    let workspace = testWorkspace([
        testItem("obj", ItemKind.Objective, "目标"),
        testItem("kr", ItemKind.KeyResult, "KR", parentId: "obj"),
        testItem("act", ItemKind.Action, "挂在 KR 下", parentId: "kr"),
        testItem("sop", ItemKind.Sop, "流程"),
        testItem("step", ItemKind.Step, "步骤", parentId: "sop", gantt: GanttData(start: "2026-03-14", end: "2026-03-16", progress: 0.0))
    ])
    let focus = buildTodayFocus(workspace, TEST_TODAY)
    var okrSource = false
    var sopSource = false
    for (entry in focus) {
        if (entry.item.id == "act") {
            okrSource = focusSourceWire(entry.source) == "okr"
        }
        if (entry.item.id == "step") {
            sopSource = focusSourceWire(entry.source) == "sop"
        }
    }
    @Expect(okrSource, true)
    @Expect(sopSource, true)
}

@Test
func selectorsSopGraphAndEdges(): Unit {
    let workspace = testWorkspace(
        [
            testItem("sop", ItemKind.Sop, "流程"),
            testItem("s1", ItemKind.Step, "步骤一", parentId: "sop", order: 0),
            testItem("s2", ItemKind.Step, "步骤二", parentId: "sop", order: 1),
            testItem("other", ItemKind.Step, "别的步骤", order: 2)
        ],
        edges: [
            Edge("e1", "s1", "s2", EdgeType.Flow),
            Edge("e2", "s2", "other", EdgeType.Flow),
            Edge("e3", "sop", "s1", EdgeType.Okr)
        ]
    )
    let graph = sopGraph(workspace, "sop")
    @Expect(ids(graph.nodes), "s1,s2")
    @Expect(graph.edges.size, 1)
    @Expect(edgeTargetsOf(workspace, "s1", EdgeType.Flow).size, 1)
    @Expect(edgeSourcesOf(workspace, "s2", EdgeType.Flow).size, 1)
}

@Test
func selectorsSummarizeTodayWording(): Unit {
    @Expect(summarizeToday(2, 1, 3, 4), "2 项已超期，1 项今日到期，收件箱 3 条待澄清。")
    @Expect(summarizeToday(0, 0, 0, 4), "今天没有硬性截止，4 项下一步可以先推进。")
    @Expect(summarizeToday(0, 0, 0, 0), "今天没有待办，先收集一点想法，或者去定一个目标。")
}

@Test
func selectorsOkrPeriodsAreNewestFirst(): Unit {
    let workspace = testWorkspace([
        testItem("o1", ItemKind.Objective, "旧目标", okr: OkrData("2025-Q4", 5)),
        testItem("o2", ItemKind.Objective, "新目标", okr: OkrData("2026-Q1", 5))
    ])
    @Expect(okrPeriods(workspace).size, 2)
    @Expect(okrPeriods(workspace)[0], "2026-Q1")
    @Expect(objectivesOfPeriod(workspace, "2026-Q1").size, 1)
}
