package textura.core.data

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * Derived view selectors (GTD / OKR / gantt / SOP / dashboard).
 * Expected numbers are recomputed by hand from the seed data so a regression
 * shows up as a concrete mismatch.
 */

@Test
func deriveInboxSortsByCaptureTime(): Unit {
    let workspace = testWorkspace([
        testItem("old", ItemKind.Action, "旧", gtd: GtdData("2026-03-10T02:00:00.000Z", false)),
        testItem("new", ItemKind.Action, "新", gtd: GtdData("2026-03-15T02:00:00.000Z", false)),
        testItem("middle", ItemKind.Action, "中", gtd: GtdData("2026-03-12T02:00:00.000Z", false))
    ])
    @Expect(ids(sortInboxItems(workspace.items)), "new,middle,old")
}

@Test
func deriveContextGroupingOrderIsStable(): Unit {
    let workspace = testWorkspace([
        testItem("a", ItemKind.Action, "电脑一", gtd: GtdData(TEST_STAMP, true, context: "电脑")),
        testItem("b", ItemKind.Action, "无场景", gtd: GtdData(TEST_STAMP, true)),
        testItem("c", ItemKind.Action, "自定义", gtd: GtdData(TEST_STAMP, true, context: "咖啡店")),
        testItem("d", ItemKind.Action, "电话", gtd: GtdData(TEST_STAMP, true, context: "电话"))
    ])
    let groups = groupByContext(workspace.items)
    @Expect(groups.size, 4)
    // Preset order first (电脑 before 电话), then custom, then "无场景".
    @Expect(groups[0].context, "电脑")
    @Expect(groups[1].context, "电话")
    @Expect(groups[2].context, "咖啡店")
    @Expect(groups[3].context, NO_CONTEXT)
}

@Test
func deriveNextActionOrderUsesDueThenEnergy(): Unit {
    let workspace = testWorkspace([
        testItem("no-date-high", ItemKind.Action, "无日期高能", order: 0,
            gtd: GtdData(TEST_STAMP, true, energy: Energy.High)),
        testItem("late", ItemKind.Action, "晚到期", order: 1,
            gantt: GanttData(start: "2026-03-10", end: "2026-03-20", progress: 0.0),
            gtd: GtdData(TEST_STAMP, true, energy: Energy.Low)),
        testItem("soon", ItemKind.Action, "早到期", order: 2,
            gantt: GanttData(start: "2026-03-10", end: "2026-03-18", progress: 0.0),
            gtd: GtdData(TEST_STAMP, true, energy: Energy.Low))
    ])
    @Expect(ids(sortNextActions(workspace.items)), "soon,late,no-date-high")
}

@Test
func deriveStuckProjectRules(): Unit {
    let empty = testWorkspace([testItem("p", ItemKind.Project, "空项目")])
    @Expect(isStuckProject(empty, "p"), true)

    let withNext = testWorkspace([
        testItem("p", ItemKind.Project, "有下一步"),
        testItem("a", ItemKind.Action, "行动", parentId: "p")
    ])
    @Expect(isStuckProject(withNext, "p"), false)

    let allDone = testWorkspace([
        testItem("p", ItemKind.Project, "全部完成"),
        testItem("a", ItemKind.Action, "行动", parentId: "p", status: ItemStatus.Done)
    ])
    @Expect(isStuckProject(allDone, "p"), false)

    let stalled = testWorkspace([
        testItem("p", ItemKind.Project, "停滞"),
        testItem("a", ItemKind.Action, "行动", parentId: "p", status: ItemStatus.Waiting)
    ])
    @Expect(isStuckProject(stalled, "p"), true)

    let doneProject = testWorkspace([
        testItem("p", ItemKind.Project, "已完成项目", status: ItemStatus.Done)
    ])
    @Expect(isStuckProject(doneProject, "p"), false)
    @Expect(isStuckProject(empty, "missing"), false)
}

@Test
func deriveProjectHealthCounts(): Unit {
    let workspace = testWorkspace([
        testItem("p", ItemKind.Project, "项目"),
        testItem("a", ItemKind.Action, "完成", parentId: "p", order: 0, status: ItemStatus.Done),
        testItem("b", ItemKind.Action, "下一步", parentId: "p", order: 1),
        testItem("c", ItemKind.Action, "等待", parentId: "p", order: 2, status: ItemStatus.Waiting)
    ])
    let health = projectHealth(workspace)
    @Expect(health.size, 1)
    @Expect(health[0].total, 3)
    @Expect(health[0].done, 1)
    @Expect(health[0].open, 2)
    @Expect(health[0].next, 1)
    @Expect(health[0].progress, 33)
    @Expect(health[0].stuck, false)
}

@Test
func deriveWaitingDaysAndOverdue(): Unit {
    let item = testItem(
        "w",
        ItemKind.Action,
        "等待",
        status: ItemStatus.Waiting,
        gtd: GtdData("2026-03-05T02:00:00.000Z", true, waitingFor: "法务")
    )
    @Expect(waitingDays(item, TEST_TODAY), 11)
    @Expect(isWaitingOverdue(item, TEST_TODAY), true)
    @Expect(isWaitingOverdue(item, TEST_TODAY, threshold: 20), false)

    let recent = testItem(
        "r",
        ItemKind.Action,
        "刚等待",
        status: ItemStatus.Waiting,
        gtd: GtdData("2026-03-14T02:00:00.000Z", true)
    )
    @Expect(waitingDays(recent, TEST_TODAY), 2)
    @Expect(isWaitingOverdue(recent, TEST_TODAY), false)
}

@Test
func deriveDeadlineLabels(): Unit {
    let overdue = testItem("o", ItemKind.Action, "超期",
        gantt: GanttData(start: "2026-03-10", end: "2026-03-13", progress: 0.0))
    @Expect(deadlineInfo(overdue, TEST_TODAY).label, "逾期 3 天")
    @Expect(deadlineInfo(overdue, TEST_TODAY).tone == DeadlineTone.Danger, true)

    let today = testItem("t", ItemKind.Action, "今天",
        gantt: GanttData(start: "2026-03-10", end: "2026-03-16", progress: 0.0))
    @Expect(deadlineInfo(today, TEST_TODAY).label, "今天到期")

    let future = testItem("f", ItemKind.Action, "未来",
        gantt: GanttData(start: "2026-03-10", end: "2026-03-20", progress: 0.0))
    @Expect(deadlineInfo(future, TEST_TODAY).label, "03/20")

    let undated = testItem("u", ItemKind.Action, "无日期")
    @Expect(deadlineInfo(undated, TEST_TODAY).label, "未设截止")
    @Expect(deadlineInfo(undated, TEST_TODAY).tone == DeadlineTone.Muted, true)
}

@Test
func deriveWeeklyReviewTotals(): Unit {
    let workspace = testWorkspace(
        [
            testItem("i1", ItemKind.Action, "收件一", status: ItemStatus.Inbox,
                gtd: GtdData("2026-03-16T02:00:00.000Z", false)),
            testItem("i2", ItemKind.Action, "收件二", status: ItemStatus.Inbox,
                gtd: GtdData("2026-03-15T02:00:00.000Z", false)),
            testItem("cleared", ItemKind.Action, "已澄清", status: ItemStatus.Next,
                gtd: GtdData("2026-03-14T02:00:00.000Z", true)),
            testItem("done", ItemKind.Action, "本周完成", status: ItemStatus.Done,
                completedAt: "2026-03-15T02:00:00.000Z"),
            testItem("overdue", ItemKind.Action, "超期",
                gantt: GanttData(start: "2026-03-10", end: "2026-03-12", progress: 0.0)),
            testItem("stuck", ItemKind.Project, "停滞项目"),
            testItem("waiting", ItemKind.Action, "等待超期", status: ItemStatus.Waiting,
                gtd: GtdData("2026-03-01T02:00:00.000Z", true)),
            testItem("undated", ItemKind.Action, "无日期行动", areaId: "area1")
        ],
        areas: [Area("area1", "领域一", "#C0663A", order: 0)]
    )
    let review = weeklyReview(workspace, TEST_TODAY)
    @Expect(review.today, "2026-03-16")
    @Expect(review.windowStart, "2026-03-10")
    @Expect(review.inboxCount(), 2)
    @Expect(review.inboxClearedCount(), 1)
    @Expect(review.inboxProgress, 33)
    @Expect(review.completedCount(), 1)
    @Expect(review.overdueCount(), 1)
    @Expect(review.stuckProjectCount(), 1)
    @Expect(review.waitingOverdueCount(), 1)
    @Expect(review.undatedCount() >= 1, true)
    @Expect(review.staleAreas.size, 1)
    @Expect(review.staleAreas[0].area.id, "area1")
}

@Test
func deriveQuarterElapsedAndLag(): Unit {
    // 2026-Q1 spans 2026-01-01..2026-03-31 (89 days); 2026-02-15 is day 45.
    let mid = match (parseIsoMillis("2026-02-15T00:00:00+08:00")) {
        case Some(millis) => millis
        case None => 0
    }
    @Expect(isoFromMillis(mid), "2026-02-14T16:00:00.000Z")
    @Expect(quarterElapsedPercent("2026-Q1", mid), 50.6)
    @Expect(quarterElapsedPercent("2026-Q1", TEST_ANCHOR), 83.1)
    @Expect(quarterElapsedPercent("nope", mid), 0.0)
    @Expect(isKrBehind(40.0, 50.0), true)
    @Expect(isKrBehind(41.0, 50.0), false)
    @Expect(confidenceBucket(1) == ConfidenceBucket.Low, true)
    @Expect(confidenceBucket(5) == ConfidenceBucket.Mid, true)
    @Expect(confidenceBucket(9) == ConfidenceBucket.High, true)
}

@Test
func deriveMetricProgressStates(): Unit {
    @Expect(metricProgressStateWire(metricProgressInfo(None).state), "unset")
    @Expect(metricProgressStateWire(metricProgressInfo(Some(Metric(5.0, 5.0, 5.0, "x"))).state), "flat")
    @Expect(metricProgressStateWire(metricProgressInfo(Some(Metric(0.0, 100.0, 50.0, "%"))).state), "in-range")
    @Expect(metricProgressStateWire(metricProgressInfo(Some(Metric(10.0, 20.0, 2.0, "x"))).state), "under")
    @Expect(metricProgressStateWire(metricProgressInfo(Some(Metric(0.0, 10.0, 25.0, "x"))).state), "over")
    match (metricPercent(Some(Metric(40.0, 60.0, 50.0, "%")))) {
        case Some(value) => @Expect(value, 50.0)
        case None => @Expect(false, true)
    }
    @Expect(hasMetricRange(None), false)
    @Expect(hasMetricRange(Some(Metric(3.0, 3.0, 3.0, "x"))), false)
    @Expect(hasMetricRange(Some(Metric(1.0, 2.0, 1.5, "x"))), true)
}

@Test
func deriveOkrSummaryOnSeed(): Unit {
    let workspace = createSeedWorkspace(FixedClock(TEST_ANCHOR))
    let summary = summarizeOkr(workspace, "2026-Q1", TEST_ANCHOR)
    @Expect(summary.objectives, 1)
    @Expect(summary.keyResults, 3)
    @Expect(summary.averageProgress, 29)
    @Expect(summary.behind, 3)
    @Expect(summary.elapsedPercent, 83.1)
    // Seed confidences are 4, 6, 7 -> mid, mid, high.
    @Expect(summary.confidenceLow, 0)
    @Expect(summary.confidenceMid, 2)
    @Expect(summary.confidenceHigh, 1)
}

@Test
func deriveExecutionItemsUseEdgeThenParent(): Unit {
    let workspace = testWorkspace(
        [
            testItem("kr", ItemKind.KeyResult, "KR"),
            testItem("via-edge", ItemKind.Action, "边关联"),
            testItem("via-parent", ItemKind.Action, "父关联", parentId: "kr"),
            testItem("both", ItemKind.Action, "两条都命中", parentId: "kr"),
            testItem("note", ItemKind.Note, "笔记", parentId: "kr")
        ],
        edges: [
            Edge("e1", "kr", "via-edge", EdgeType.Okr),
            Edge("e2", "kr", "both", EdgeType.Okr)
        ]
    )
    let refs = executionItemsOf(workspace, "kr")
    @Expect(idList(refs), "via-edge,both,via-parent")
    @Expect(refs[0].edgeId ?? "", "e1")
    @Expect(refs[2].edgeId.isNone(), true)
}

@Test
func deriveObjectiveFilteringKeepsMatchedKrs(): Unit {
    let workspace = createSeedWorkspace(FixedClock(TEST_ANCHOR))
    let all = filterObjectives(workspace, "2026-Q1", "")
    @Expect(all.size, 1)
    @Expect(all[0].keyResults.size, 3)
    let filtered = filterObjectives(workspace, "2026-Q1", "NPS")
    @Expect(filtered.size, 1)
    @Expect(filtered[0].objectiveMatched, false)
    @Expect(filtered[0].keyResults.size, 1)
    @Expect(filtered[0].keyResults[0].id, "kr_nps")
    let byKr = filterObjectives(workspace, "2026-Q1", "周活跃")
    @Expect(byKr.size, 1)
    @Expect(byKr[0].objectiveMatched, false)
    @Expect(byKr[0].keyResults.size, 1)
    @Expect(byKr[0].keyResults[0].id, "kr_wau")
}

@Test
func deriveQuarterShifts(): Unit {
    @Expect(shiftQuarter("2026-Q4", 1), "2027-Q1")
    @Expect(shiftQuarter("2026-Q1", -1), "2025-Q4")
    @Expect(nextQuarter("2026-Q2"), "2026-Q3")
    @Expect(shiftQuarter("bad", 1), "bad")
    @Expect(quarterLabel("2026-Q4"), "2026 Q4")
    @Expect(quarterLabel("bad"), "bad")
}

@Test
func deriveGanttRangesAndProgress(): Unit {
    let item = testItem("a", ItemKind.Action, "A",
        gantt: GanttData(start: "2026-03-20", end: "2026-03-10", progress: 40.0))
    match (itemRange(item)) {
        case Some(range) =>
            @Expect(range.start, "2026-03-10")
            @Expect(range.end, "2026-03-20")
        case None => @Expect(false, true)
    }
    @Expect(displayProgress(item), 40)
    let done = testItem("d", ItemKind.Action, "D", status: ItemStatus.Done,
        gantt: GanttData(start: "2026-03-10", end: "2026-03-20", progress: 20.0))
    @Expect(displayProgress(done), 100)
    @Expect(itemRange(testItem("n", ItemKind.Action, "N")).isNone(), true)
}

@Test
func deriveGanttRangeCoversBarsAndToday(): Unit {
    let workspace = createSeedWorkspace(FixedClock(TEST_ANCHOR))
    let range = buildRange(workspace.items, GanttZoom.Week, TEST_TODAY)
    @Expect(range.start <= "2026-03-05", true)
    @Expect(range.end >= "2026-03-30", true)
    @Expect(range.start <= TEST_TODAY, true)
    @Expect(range.end >= TEST_TODAY, true)
    // Week zoom aligns to Monday..Sunday.
    @Expect(startOfWeekKey(range.start), range.start)
    @Expect(endOfWeekKey(range.end), range.end)
    let monthRange = buildRange(workspace.items, GanttZoom.Month, TEST_TODAY)
    @Expect(startOfMonthKey(monthRange.start), monthRange.start)
    @Expect(endOfMonthKey(monthRange.end), monthRange.end)
}

@Test
func deriveGanttRowsOnSeed(): Unit {
    let workspace = createSeedWorkspace(FixedClock(TEST_ANCHOR))
    let collapsed = HashMap<String, Bool>()
    let rows = buildGanttRows(workspace, collapsed)
    @Expect(rows[0].kind == GanttRowKind.Group, true)
    @Expect(rows[0].id, "proj_website")
    @Expect(rows[0].count, 6)
    // Project progress is child completion: 1 of 6 actions done.
    @Expect(rows[0].progress, 17)
    var itemRows = 0
    var sopGroup = false
    var ungrouped = false
    for (row in rows) {
        if (row.kind == GanttRowKind.Item) {
            itemRows += 1
        }
        if (row.kind == GanttRowKind.Group && row.id == "sop_onboarding") {
            sopGroup = true
        }
        if (row.kind == GanttRowKind.Group && row.id == UNGROUPED_ID) {
            ungrouped = true
            @Expect(row.title, "未分组")
        }
    }
    @Expect(sopGroup, true)
    @Expect(ungrouped, true)
    @Expect(itemRows, 6 + 1 + 3)

    let collapsedRows = buildGanttRows(workspace, ganttCollapsed(["proj_website"]))
    var projectItems = 0
    for (row in collapsedRows) {
        if (row.kind == GanttRowKind.Item && row.groupId == "proj_website") {
            projectItems += 1
        }
    }
    @Expect(projectItems, 0)
}

func ganttCollapsed(keys: Array<String>): HashMap<String, Bool> {
    let map = HashMap<String, Bool>()
    for (key in keys) {
        map[key] = true
    }
    map
}

@Test
func deriveGanttDependencies(): Unit {
    let workspace = createSeedWorkspace(FixedClock(TEST_ANCHOR))
    let edges = dependencyEdges(workspace)
    @Expect(edges.size, 2)
    @Expect(edges[0].from, "act_build")
    @Expect(edges[0].to, "act_design")
    let targets = edgeTargetsOf(workspace, "act_build", EdgeType.Depends)
    @Expect(ids(targets), "act_design")
}

@Test
func deriveSopListAndRuns(): Unit {
    let workspace = createSeedWorkspace(FixedClock(TEST_ANCHOR))
    let summaries = sopList(workspace)
    @Expect(summaries.size, 1)
    @Expect(summaries[0].sop.id, "sop_onboarding")
    @Expect(summaries[0].stepCount, 7)
    @Expect(summaries[0].runCount, 3)
    @Expect(summaries[0].completion, 0)
    match (summaries[0].latestRun) {
        case Some(run) => @Expect(run.id, "run_3")
        case None => @Expect(false, true)
    }
    let tally = sopRunTally(workspace, "sop_onboarding")
    @Expect(tally.pass, 2)
    @Expect(tally.fail, 1)
    @Expect(tally.skip, 0)
    @Expect(tally.total(), 3)
    let recent = recentRunsFor(workspace, "sop_onboarding", limit: 2)
    @Expect(recent.size, 2)
    @Expect(recent[0].id, "run_3")
    @Expect(recent[1].id, "run_1")
    @Expect(sopSteps(workspace, "sop_onboarding").size, 7)
}

@Test
func deriveDashboardCompletionAndActivity(): Unit {
    let workspace = createSeedWorkspace(FixedClock(TEST_ANCHOR))
    let week = completedThisWeek(workspace, TEST_ANCHOR)
    @Expect(ids(week), "act_research")
    let recent = recentlyCompleted(workspace, limit: 3)
    @Expect(ids(recent), "act_research")
    let activity = buildActivity(workspace, limitPerSource: 5)
    @Expect(activity.size, 4)
    @Expect(activity[0].id, "run:run_3")
    @Expect(activity[0].kind == ActivityKind.Run, true)
    @Expect(activity[0].detail, "信息是否完整？ · 失败")
    @Expect(activity[3].id, "completed:act_research")
    @Expect(activity[3].detail, "行动 · 已完成")
}
