package textura.views.dashboard.logic

import std.collection.*

/**
 * Web 版单测未覆盖、但聚合语义必须钉住的边界：空库、全超期、去重、7 天窗口、
 * 分页末页、排序稳定性、错误日期回退、时区换算与 OKR 平均进度。
 */
@Test
func emptyWorkspaceTest(): Unit {
    let items = Array<DashItem>()
    let runs = Array<SopRun>()
    @Expect(buildTodayFocus(items, TODAY).size, 0)
    @Expect(countFocusBuckets(buildTodayFocus(items, TODAY)), FocusCounts(0, 0, 0))
    @Expect(buildActivity(items, runs, limitPerSource: 5).size, 0)
    @Expect(latestRun(runs).isNone(), true)
    @Expect(latestRunFor(runs, "s").isNone(), true)
    @Expect(recentlyCompleted(items).size, 0)
    @Expect(completedThisWeek(items, "2026-01-05T12:00:00").size, 0)
    @Expect(summarizeToday(TodaySummaryInput(0, 0, 0, 0)), "今天没有待办，先收集一点想法，或者去定一个目标。")
}

@Test
func allOverdueTest(): Unit {
    let items = [
        makeItem("late-5", DashKind.Action, "五日前", order: 3, dueDate: "2025-12-31"),
        makeItem("late-3", DashKind.Action, "三日前", order: 1, dueDate: "2026-01-02"),
        makeItem("late-1", DashKind.Action, "昨日", order: 2, dueDate: "2026-01-04")
    ]
    let entries = buildTodayFocus(items, TODAY)
    @Expect(idsOf(entries), "late-5,late-3,late-1")
    @Expect(bucketsOf(entries), "overdue,overdue,overdue")
    @Expect(countFocusBuckets(entries), FocusCounts(3, 0, 0))
    @Expect(entries[0].daysLate, 5)
    @Expect(entries[1].daysLate, 3)
    @Expect(entries[2].daysLate, 1)
}

@Test
func duplicateRowsCollapseToOneTest(): Unit {
    // 同一 id 出现两次：byId 后者覆盖，因此只有一行，且归入「今天」。
    let items = [
        makeItem("dup", DashKind.Action, "重复条目", order: 0, dueDate: "2026-01-02"),
        makeItem("dup", DashKind.Action, "重复条目", order: 0, dueDate: TODAY)
    ]
    let entries = buildTodayFocus(items, TODAY)
    @Expect(entries.size, 1)
    @Expect(entries[0].bucket, FocusBucket.Today)
    @Expect(orEmpty(entries[0].due), TODAY)

    // 同时命中「今天到期」与「下一步」的项目也只出现一次。
    let project = makeItem("proj", DashKind.Project, "今日交付", order: 0, dueDate: TODAY)
    let step = makeItem("step", DashKind.Step, "无日期步骤", order: 1)
    let mixed = buildTodayFocus([project, step], TODAY)
    @Expect(idsOf(mixed), "proj")
    @Expect(mixed[0].bucket, FocusBucket.Today)

    // 无日期步骤不属于「下一步」，不会进入无日期桶。
    let onlyStep = buildTodayFocus([step], TODAY)
    @Expect(onlyStep.size, 0)
}

@Test
func unstableDatesFallBackToDaysLateOneTest(): Unit {
    // 2025-02-30 不是合法日期：仍按字符串进入超期桶，但天数退回 1。
    let items = [makeItem("bad", DashKind.Action, "非法日期", dueDate: "2025-02-30")]
    let entries = buildTodayFocus(items, TODAY)
    @Expect(entries.size, 1)
    @Expect(entries[0].bucket, FocusBucket.Overdue)
    @Expect(entries[0].daysLate, 1)
}

@Test
func completedWindowBoundaryTest(): Unit {
    let now = "2026-01-05T12:00:00"
    let items = [
        makeItem("day6", DashKind.Action, "第 6 天", status: DashStatus.Done, completedAt: "2025-12-30T23:59:59"),
        makeItem("day7", DashKind.Action, "第 7 天", status: DashStatus.Done, completedAt: "2025-12-29T00:00:00"),
        makeItem("same-day", DashKind.Action, "今天稍晚", status: DashStatus.Done, completedAt: "2026-01-05T13:00:00"),
        makeItem("tomorrow", DashKind.Action, "明天", status: DashStatus.Done, completedAt: "2026-01-06T00:00:00"),
        makeItem("utc-day6", DashKind.Action, "UTC 换算", status: DashStatus.Done, completedAt: "2025-12-29T16:30:00Z"),
        makeItem("blank", DashKind.Action, "空完成时间", status: DashStatus.Done, completedAt: "")
    ]
    let ids = ArrayList<String>()
    for (item in completedThisWeek(items, now)) {
        ids.add(item.id)
    }
    // 第 6 天含入、第 7 天排除；同一天晚些时候仍属 diff 0；明天（diff = -1）排除；空串按未完成处理。
    @Expect(String.join(ids.toArray(), delimiter: ","), "same-day,day6,utc-day6")

    let narrow = ArrayList<String>()
    for (item in completedThisWeek(items, now, days: 3)) {
        narrow.add(item.id)
    }
    @Expect(String.join(narrow.toArray(), delimiter: ","), "same-day")

    let invalidNow = completedThisWeek(items, "not-a-timestamp")
    @Expect(invalidNow.size, 0)
}

@Test
func recentlyCompletedLimitTest(): Unit {
    let items = [
        makeItem("c3", DashKind.Action, "第三", status: DashStatus.Done, completedAt: "2026-01-03T10:00:00"),
        makeItem("c1", DashKind.Action, "第一", status: DashStatus.Done, completedAt: "2026-01-01T10:00:00"),
        makeItem("c2", DashKind.Action, "第二", status: DashStatus.Done, completedAt: "2026-01-02T10:00:00")
    ]
    let ids = ArrayList<String>()
    for (item in recentlyCompleted(items, limit: 2)) {
        ids.add(item.id)
    }
    @Expect(String.join(ids.toArray(), delimiter: ","), "c3,c2")
    // JS `slice(0, -1)`：去掉最后一条。
    let tail = ArrayList<String>()
    for (item in recentlyCompleted(items, limit: -1)) {
        tail.add(item.id)
    }
    @Expect(String.join(tail.toArray(), delimiter: ","), "c3,c2")
}

@Test
func focusSortIsStableOnTiesTest(): Unit {
    let items = [
        makeItem("s1", DashKind.Action, "同键一", order: 0),
        makeItem("s2", DashKind.Action, "同键二", order: 0),
        makeItem("s3", DashKind.Action, "同键三", order: 0)
    ]
    @Expect(idsOf(buildTodayFocus(items, TODAY)), "s1,s2,s3")
}

@Test
func paginateLastPartialPageTest(): Unit {
    let entries = pagingEntries(150)
    let first = paginateFocus(entries, FOCUS_PAGE_SIZE)
    @Expect(first.shown, 100)
    @Expect(first.remaining, 50)
    @Expect(first.hasMore, true)

    let last = paginateFocus(entries, 150)
    @Expect(last.shown, 150)
    @Expect(last.remaining, 0)
    @Expect(last.hasMore, false)
    @Expect(last.items[149].item.id, "a149")

    let oversized = paginateFocus(entries, 200)
    @Expect(oversized.shown, 150)
    @Expect(oversized.remaining, 0)
    @Expect(oversized.hasMore, false)
}

@Test
func okrAverageProgressTest(): Unit {
    @Expect(okrAverageProgress(Array<DashItem>()), 0)
    @Expect(averageProgress(Array<Int64>()), 0)
    @Expect(okrAverageProgress([makeItem("o1", DashKind.Objective, "一", okrProgress: 100)]), 100)
    @Expect(
        okrAverageProgress([
            makeItem("o1", DashKind.Objective, "一", okrProgress: 100),
            makeItem("o2", DashKind.Objective, "二", okrProgress: 50)
        ]),
        75
    )
    // Math.round(66.5) = 67
    @Expect(
        okrAverageProgress([
            makeItem("o1", DashKind.Objective, "一", okrProgress: 100),
            makeItem("o2", DashKind.Objective, "二", okrProgress: 33)
        ]),
        67
    )
    // 缺失进度按 0 计
    @Expect(
        okrAverageProgress([
            makeItem("o1", DashKind.Objective, "一", okrProgress: 100),
            makeItem("o2", DashKind.Objective, "二")
        ]),
        50
    )
}

@Test
func summarizeTodayInboxOnlyTest(): Unit {
    @Expect(summarizeToday(TodaySummaryInput(0, 0, 2, 5)), "收件箱 2 条待澄清。")
}

@Test
func sortedRunsTieBreakTest(): Unit {
    let runs = [
        SopRun("r-b", "s1", "2026-01-05T09:00:00", sopTitle: "一"),
        SopRun("r-a", "s2", "2026-01-05T09:00:00", sopTitle: "二"),
        SopRun("r-c", "s1", "2026-01-06T09:00:00", sopTitle: "一")
    ]
    let ordered = sortedRuns(runs)
    @Expect(ordered[0].id, "r-c")
    @Expect(ordered[1].id, "r-a")
    @Expect(ordered[2].id, "r-b")
    @Expect(latestRunFor(runs, "s1").getOrThrow().id, "r-c")
    @Expect(latestRunFor(runs, "missing").isNone(), true)
}

@Test
func dateKeyAndTimeZoneTest(): Unit {
    @Expect(dateKeyOf(Some("  2026-01-05T10:00:00  ")).getOrThrow(), "2026-01-05")
    @Expect(dateKeyOf(Some("\u{3000}2026-01-05")).getOrThrow(), "2026-01-05")
    @Expect(dateKeyOf(Some("2026-1-5")).isNone(), true)
    @Expect(dateKeyOf(None).isNone(), true)

    @Expect(localDateKeyOf("2026-01-02T20:00:00Z").getOrThrow(), "2026-01-03")
    @Expect(localDateKeyOf("2026-01-03T02:00:00+08:00").getOrThrow(), "2026-01-03")
    @Expect(localDateKeyOf("2026-01-03T20:00:00-05:00").getOrThrow(), "2026-01-04")
    @Expect(localDateKeyOf("2026-01-05").getOrThrow(), "2026-01-05")
    @Expect(localDateKeyOf("oops").isNone(), true)
}
