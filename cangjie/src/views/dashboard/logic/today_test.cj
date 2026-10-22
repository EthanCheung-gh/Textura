package textura.views.dashboard.logic

import std.collection.*

/**
 * `src/modules/dashboard/today.test.ts` 的逐条移植。
 *
 * 断言真值直接取自 Web 版单测，输入字段一一对应：`gantt.end` → `dueDate`，
 * `completedAt` 原样传递，`itemById(run.sopId/stepId).title` → `sopTitle`/`stepTitle`。
 */
const TODAY = "2026-01-05"
const ITEM_CREATED = "2026-01-01T00:00:00.000Z"

func makeItem(
    id: String,
    kind: DashKind,
    title: String,
    status!: DashStatus = DashStatus.Next,
    parentId!: ?String = None,
    order!: Int64 = 0,
    dueDate!: ?String = None,
    completedAt!: ?String = None,
    okrProgress!: ?Int64 = None
): DashItem {
    return DashItem(
        id,
        title,
        kind: kind,
        status: status,
        dueDate: dueDate,
        completedAt: completedAt,
        updatedAt: ITEM_CREATED,
        createdAt: ITEM_CREATED,
        parentId: parentId,
        order: order,
        okrProgress: okrProgress
    )
}

func idsOf(entries: Array<FocusEntry>): String {
    let parts = ArrayList<String>()
    for (entry in entries) {
        parts.add(entry.item.id)
    }
    return String.join(parts.toArray(), delimiter: ",")
}

func bucketName(bucket: FocusBucket): String {
    match (bucket) {
        case Overdue => "overdue"
        case Today => "today"
        case Undated => "undated"
    }
}

func bucketsOf(entries: Array<FocusEntry>): String {
    let parts = ArrayList<String>()
    for (entry in entries) {
        parts.add(bucketName(entry.bucket))
    }
    return String.join(parts.toArray(), delimiter: ",")
}

func entryById(entries: Array<FocusEntry>, id: String): ?FocusEntry {
    for (entry in entries) {
        if (entry.item.id == id) {
            return Some(entry)
        }
    }
    return None
}

/** `focusWorkspace()`：与 Web 版单测同一份夹具。 */
func focusWorkspaceItems(): Array<DashItem> {
    return [
        makeItem("p", DashKind.Project, "官网改版", status: DashStatus.Active),
        makeItem("a", DashKind.Action, "超期任务", parentId: "p", order: 0, dueDate: "2026-01-02"),
        makeItem("b", DashKind.Action, "今天到期", parentId: "p", order: 0, dueDate: TODAY),
        makeItem("c", DashKind.Action, "无日期下一步", order: 3),
        makeItem("future", DashKind.Action, "未来排期", order: 4, dueDate: "2026-01-10"),
        makeItem(
            "d",
            DashKind.Action,
            "已完成但逾期",
            status: DashStatus.Done,
            order: 1,
            dueDate: "2026-01-01",
            completedAt: "2026-01-04T00:00:00.000Z"
        ),
        makeItem("s", DashKind.Sop, "新手引导 SOP", status: DashStatus.Active),
        makeItem("st", DashKind.Step, "发送欢迎邮件", parentId: "s", order: 1, dueDate: TODAY),
        makeItem("o", DashKind.Objective, "提升激活", status: DashStatus.Active),
        makeItem("kr", DashKind.KeyResult, "NPS 提升", parentId: "o"),
        makeItem("ak", DashKind.Action, "整理用户访谈", parentId: "kr", order: 2, dueDate: TODAY)
    ]
}

@Test
func buildTodayFocusMergesBucketsTest(): Unit {
    let entries = buildTodayFocus(focusWorkspaceItems(), TODAY)
    @Expect(idsOf(entries), "a,b,st,ak,c")
    @Expect(bucketsOf(entries), "overdue,today,today,today,undated")
    @Expect(countFocusBuckets(entries), FocusCounts(1, 3, 1))
}

@Test
func buildTodayFocusKeepsFutureOutOfUndatedTest(): Unit {
    let entries = buildTodayFocus(focusWorkspaceItems(), TODAY)
    var hasFuture = false
    let undatedIds = ArrayList<String>()
    var undatedAllWithoutDue = true
    for (entry in entries) {
        if (entry.item.id == "future") {
            hasFuture = true
        }
        if (entry.bucket == FocusBucket.Undated) {
            undatedIds.add(entry.item.id)
            if (entry.due.isSome()) {
                undatedAllWithoutDue = false
            }
        }
    }
    @Expect(hasFuture, false)
    @Expect(String.join(undatedIds.toArray(), delimiter: ","), "c")
    @Expect(undatedAllWithoutDue, true)
}

@Test
func buildTodayFocusDeduplicatesTodayAndNextTest(): Unit {
    let entries = buildTodayFocus(focusWorkspaceItems(), TODAY)
    var count = 0
    var bucket = FocusBucket.Undated
    for (entry in entries) {
        if (entry.item.id == "b") {
            count += 1
            bucket = entry.bucket
        }
    }
    @Expect(count, 1)
    @Expect(bucket, FocusBucket.Today)
}

@Test
func buildTodayFocusExcludesCompletedAndComputesLatenessTest(): Unit {
    let entries = buildTodayFocus(focusWorkspaceItems(), TODAY)
    var hasDone = false
    for (entry in entries) {
        if (entry.item.id == "d") {
            hasDone = true
        }
    }
    @Expect(hasDone, false)
    let overdue = entryById(entries, "a").getOrThrow()
    @Expect(overdue.daysLate, 3)
    @Expect(orEmpty(overdue.due), "2026-01-02")
}

@Test
func buildTodayFocusRecordsPathsAndSourcesTest(): Unit {
    let entries = buildTodayFocus(focusWorkspaceItems(), TODAY)
    let overdue = entryById(entries, "a").getOrThrow()
    @Expect(String.join(overdue.pathTitles, delimiter: "|"), "官网改版|超期任务")
    @Expect(entryById(entries, "st").getOrThrow().source, Some(FocusSource.SourceSop))
    @Expect(entryById(entries, "ak").getOrThrow().source, Some(FocusSource.SourceOkr))
    @Expect(entryById(entries, "c").getOrThrow().source.isNone(), true)
}

@Test
func buildTodayFocusEmptyWorkspaceTest(): Unit {
    let items = [makeItem("done", DashKind.Action, "完成", status: DashStatus.Done)]
    @Expect(buildTodayFocus(items, TODAY).size, 0)
}

@Test
func summarizeTodayTest(): Unit {
    @Expect(
        summarizeToday(TodaySummaryInput(2, 1, 6, 0)),
        "2 项已超期，1 项今日到期，收件箱 6 条待澄清。"
    )
    @Expect(
        summarizeToday(TodaySummaryInput(0, 0, 0, 3)),
        "今天没有硬性截止，3 项下一步可以先推进。"
    )
    @Expect(summarizeToday(TodaySummaryInput(0, 0, 0, 0)), "今天没有待办，先收集一点想法，或者去定一个目标。")
}

@Test
func completedThisWeekTest(): Unit {
    let items = [
        makeItem(
            "recent",
            DashKind.Action,
            "最近完成",
            status: DashStatus.Done,
            completedAt: "2026-01-03T10:00:00"
        ),
        makeItem(
            "older",
            DashKind.Action,
            "早些完成",
            status: DashStatus.Done,
            completedAt: "2026-01-01T10:00:00"
        ),
        makeItem(
            "stale",
            DashKind.Action,
            "很久以前",
            status: DashStatus.Done,
            completedAt: "2025-12-01T10:00:00"
        ),
        makeItem("open", DashKind.Action, "未完成")
    ]
    let completed = completedThisWeek(items, "2026-01-05T12:00:00")
    let ids = ArrayList<String>()
    for (item in completed) {
        ids.add(item.id)
    }
    @Expect(String.join(ids.toArray(), delimiter: ","), "recent,older")
}

@Test
func buildActivityAndLatestRunTest(): Unit {
    let items = [
        makeItem("s", DashKind.Sop, "新手引导 SOP", status: DashStatus.Active),
        makeItem("st", DashKind.Step, "发送欢迎邮件", parentId: "s"),
        makeItem(
            "done",
            DashKind.Action,
            "需求梳理",
            status: DashStatus.Done,
            completedAt: "2026-01-04T08:00:00"
        ),
        makeItem("s2", DashKind.Sop, "周复盘 SOP", status: DashStatus.Active),
        makeItem(
            "old-done",
            DashKind.Note,
            "很久以前完成",
            status: DashStatus.Done,
            completedAt: "2025-12-01T08:00:00"
        )
    ]
    let runs = [
        SopRun(
            "r1",
            "s",
            "2026-01-05T09:00:00",
            result: RunResult.Pass,
            sopTitle: "新手引导 SOP",
            stepTitle: "发送欢迎邮件"
        ),
        SopRun("r2", "s2", "2026-01-03T09:00:00", result: RunResult.Fail, sopTitle: "周复盘 SOP")
    ]
    let activity = buildActivity(items, runs, limitPerSource: 5)
    let ids = ArrayList<String>()
    for (entry in activity) {
        ids.add(entry.id)
    }
    @Expect(String.join(ids.toArray(), delimiter: ","), "run:r1,completed:done,run:r2,completed:old-done")
    @Expect(activity[0].title, "新手引导 SOP")
    @Expect(activity[0].detail, "发送欢迎邮件 · 通过")
    @Expect(activity[1].detail, "行动 · 已完成")
    @Expect(activity[2].detail, "失败")
    @Expect(activity[3].title, "很久以前完成")

    match (latestRun(runs)) {
        case Some(run) => @Expect(run.id, "r1")
        case None => @Expect(true, false)
    }
    @Expect(latestRun(Array<SopRun>()).isNone(), true)
}
