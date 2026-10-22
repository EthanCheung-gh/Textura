package textura.views.gtd.logic

/*
 * `src/modules/gtd/gtdLogic.test.ts` 的逐条移植。
 *
 * 差异只在「今天」的来源：TS 用 `currentDateKey()` 读系统时钟，这里用固定
 * 锚点 TEST_TODAY（2026-10-21）。同一个相对偏移在两边得到同一批日期，
 * 因此断言文本与 TS 完全一致。
 */

/* ------------------------------------------------------------------ */
/* groupByContext                                                      */
/* ------------------------------------------------------------------ */

@Test
func groupByContextMergesEmptyContextIntoNoContext(): Unit {
    let phone = mkItem(
        "a",
        GtdKind.Action,
        "打电话",
        capturedAt: Some(isoAt(-1)),
        clarified: true,
        context: Some("电话")
    )
    let none = mkItem("b", GtdKind.Action, "无场景任务")
    let computer = mkItem(
        "c",
        GtdKind.Action,
        "写文档",
        capturedAt: Some(isoAt(-2)),
        clarified: true,
        context: Some("电脑")
    )
    let phone2 = mkItem(
        "d",
        GtdKind.Action,
        "再打一个电话",
        capturedAt: Some(isoAt(-3)),
        clarified: true,
        context: Some("电话")
    )
    let blank = mkItem("e", GtdKind.Action, "空白场景", context: Some("   "))

    let groups = groupByContext([phone, none, computer, phone2, blank])
    // 空组不出现：只有 电脑 / 电话 / 无场景 三组
    @Expect(joinContexts(groups), "电脑,电话,无场景")
    @Expect(contextIds(groups, "电话"), "a,d")
    @Expect(contextIds(groups, NO_CONTEXT), "b,e")
}

@Test
func groupByContextKeepsGroupOrderIndependentOfInput(): Unit {
    let phone = mkItem("a", GtdKind.Action, "电话", capturedAt: Some(isoAt(-1)), clarified: true, context: Some("电话"))
    let computer = mkItem("b", GtdKind.Action, "电脑", capturedAt: Some(isoAt(-1)), clarified: true, context: Some("电脑"))
    let custom = mkItem("c", GtdKind.Action, "通勤", capturedAt: Some(isoAt(-1)), clarified: true, context: Some("通勤"))
    let none = mkItem("d", GtdKind.Action, "无场景")

    let first = groupByContext([phone, computer, custom, none])
    let second = groupByContext([none, custom, computer, phone])
    @Expect(joinContexts(first), "电脑,电话,通勤,无场景")
    @Expect(joinContexts(second), joinContexts(first))
}

/* ------------------------------------------------------------------ */
/* sortNextActions                                                     */
/* ------------------------------------------------------------------ */

@Test
func sortNextActionsOrdersByDueThenEnergyThenCreatedAt(): Unit {
    let later = mkItem(
        "later",
        GtdKind.Action,
        "两天后",
        createdAt: isoAt(-5),
        capturedAt: Some(isoAt(-5)),
        clarified: true,
        energy: Some(Energy.Low),
        dueDate: Some(dayAt(2))
    )
    let overdue = mkItem(
        "overdue",
        GtdKind.Action,
        "昨天到期",
        createdAt: isoAt(-4),
        capturedAt: Some(isoAt(-4)),
        clarified: true,
        energy: Some(Energy.Low),
        dueDate: Some(dayAt(-1))
    )
    let undatedHigh = mkItem(
        "undated-high",
        GtdKind.Action,
        "无日期高能量",
        createdAt: isoAt(-3),
        capturedAt: Some(isoAt(-3)),
        clarified: true,
        energy: Some(Energy.High)
    )
    let undatedLowOld = mkItem(
        "undated-low-old",
        GtdKind.Action,
        "无日期低能量",
        createdAt: isoAt(-6),
        capturedAt: Some(isoAt(-6)),
        clarified: true,
        energy: Some(Energy.Low)
    )
    let undatedLowNew = mkItem(
        "undated-low-new",
        GtdKind.Action,
        "无日期低能量新",
        createdAt: isoAt(-2),
        capturedAt: Some(isoAt(-2)),
        clarified: true,
        energy: Some(Energy.Low)
    )

    let sorted = sortNextActions([undatedLowNew, undatedHigh, later, undatedLowOld, overdue])
    @Expect(joinIds(sorted), "overdue,later,undated-high,undated-low-old,undated-low-new")
}

@Test
func sortInboxItemsOrdersByCapturedAtDescending(): Unit {
    let oldest = mkItem("oldest", GtdKind.Action, "最早", capturedAt: Some(isoAt(-5)), createdAt: isoAt(-5))
    let newest = mkItem("newest", GtdKind.Action, "最新", capturedAt: Some(isoAt(-1)), createdAt: isoAt(-1))
    let sameCapture = mkItem("same", GtdKind.Action, "同刻", capturedAt: Some(isoAt(-1)), createdAt: isoAt(-3), order: 1)
    let noCapture = mkItem("nocap", GtdKind.Action, "无收集时间", createdAt: isoAt(-2), order: 0)

    @Expect(joinIds(sortInboxItems([oldest, sameCapture, noCapture, newest])), "newest,same,nocap,oldest")
}

/* ------------------------------------------------------------------ */
/* isStuckProject                                                      */
/* ------------------------------------------------------------------ */

func sampleProject(): GtdItem {
    mkItem("p1", GtdKind.Project, "官网改版", status: GtdStatus.Active, dueDate: Some(dayAt(10)))
}

@Test
func stuckProjectWithNextChildIsNotStuck(): Unit {
    let child = mkItem("c1", GtdKind.Action, "写文案", parentId: Some("p1"), status: GtdStatus.Next)
    @Expect(isStuckProject(GtdWorkspace(items: [sampleProject(), child]), "p1"), false)
}

@Test
func stuckProjectWithAllChildrenDoneIsNotStuck(): Unit {
    let child = mkItem("c1", GtdKind.Action, "写文案", parentId: Some("p1"), status: GtdStatus.Done)
    let child2 = mkItem("c2", GtdKind.Action, "上线", parentId: Some("p1"), status: GtdStatus.Done)
    @Expect(isStuckProject(GtdWorkspace(items: [sampleProject(), child, child2]), "p1"), false)
}

@Test
func stuckProjectWithoutChildrenIsStuck(): Unit {
    @Expect(isStuckProject(GtdWorkspace(items: [sampleProject()]), "p1"), true)
}

@Test
func stuckProjectWithOpenChildButNoNextIsStuck(): Unit {
    let child = mkItem("c1", GtdKind.Action, "写文案", parentId: Some("p1"), status: GtdStatus.Active)
    @Expect(isStuckProject(GtdWorkspace(items: [sampleProject(), child]), "p1"), true)
}

@Test
func stuckProjectIgnoresFinishedProjectsAndMissingIds(): Unit {
    let doneProject = mkItem("p2", GtdKind.Project, "完成的项目", status: GtdStatus.Done)
    @Expect(isStuckProject(GtdWorkspace(items: [doneProject]), "p2"), false)
    @Expect(isStuckProject(GtdWorkspace(items: [sampleProject()]), "missing"), false)
}

@Test
func stuckProjectCountsGrandchildren(): Unit {
    let child = mkItem("c1", GtdKind.Project, "子项目", parentId: Some("p1"), status: GtdStatus.Active)
    let grandchild = mkItem("g1", GtdKind.Action, "孙动作", parentId: Some("c1"), status: GtdStatus.Next)
    @Expect(isStuckProject(GtdWorkspace(items: [sampleProject(), child, grandchild]), "p1"), false)
}

/* ------------------------------------------------------------------ */
/* waitingDays / 超 7 天                                               */
/* ------------------------------------------------------------------ */

@Test
func waitingDaysCountsFromCapturedAt(): Unit {
    let item = mkItem(
        "w1",
        GtdKind.Action,
        "等回复",
        status: GtdStatus.Waiting,
        capturedAt: Some(isoAt(-3)),
        clarified: true,
        waitingFor: Some("张律师")
    )
    @Expect(waitingDays(item, TEST_TODAY), 3)
    @Expect(isWaitingOverdue(item, TEST_TODAY), false)
}

@Test
func waitingDaysWarnsOnlyBeyondSevenDays(): Unit {
    let item = mkItem(
        "w2",
        GtdKind.Action,
        "等回复",
        status: GtdStatus.Waiting,
        capturedAt: Some(isoAt(-8)),
        clarified: true,
        waitingFor: Some("张律师")
    )
    @Expect(waitingDays(item, TEST_TODAY), 8)
    @Expect(isWaitingOverdue(item, TEST_TODAY), true)
    @Expect(isWaitingOverdue(item, TEST_TODAY, threshold: 10), false)
}

@Test
func waitingDaysFallsBackToUpdatedAtAndClampsFuture(): Unit {
    let fallback = mkItem("w3", GtdKind.Action, "等回复", status: GtdStatus.Waiting, updatedAt: isoAt(-10))
    @Expect(waitingDays(fallback, TEST_TODAY), 10)
    let future = mkItem("w4", GtdKind.Action, "未来", status: GtdStatus.Waiting, updatedAt: isoAt(2))
    @Expect(waitingDays(future, TEST_TODAY), 0)
}

/* ------------------------------------------------------------------ */
/* 本地日历日 / 7 天窗口                                               */
/* ------------------------------------------------------------------ */

let COMPLETED_ISO: String = "2026-10-14T17:01:00.000Z"

@Test
func localDayKeyUsesShanghaiCalendarDay(): Unit {
    // 本地 2026-10-15 01:01 序列化为 2026-10-14T17:01Z；截取 UTC 串会得到 10-14。
    @Expect(localDayKey(Some(COMPLETED_ISO)), Some("2026-10-15"))
    @Expect(localDayKey(Some("2026-10-15")), Some("2026-10-15"))
    @Expect(localDayKey(Some("2026-10-15T09:00:00+08:00")), Some("2026-10-15"))
    @Expect(localDayKey(Some("2026-10-15T23:30:00+08:00")), Some("2026-10-15"))
    @Expect(localDayKey(Some("2026-10-15T23:30:00-05:00")), Some("2026-10-16"))
    @Expect(localDayKey(None), Option<String>.None)
    @Expect(localDayKey(Some("")), Option<String>.None)
    @Expect(localDayKey(Some("not-a-date")), Option<String>.None)
}

@Test
func waitingDaysDoesNotLoseADayToUtcTruncation(): Unit {
    let item = mkItem(
        "w-local",
        GtdKind.Action,
        "等回复",
        status: GtdStatus.Waiting,
        capturedAt: Some(COMPLETED_ISO),
        clarified: true,
        waitingFor: Some("张律师")
    )
    @Expect(waitingDays(item, TEST_TODAY), 6)
}

@Test
func relativeTimeLabelDoesNotDriftAtLocalMidnight(): Unit {
    let now = isoAt(0, hour: 9)
    @Expect(relativeTimeLabel(Some(isoAt(0, hour: 1)), now), "今天")
    @Expect(relativeTimeLabel(Some(COMPLETED_ISO), now), "6 天前")
    @Expect(relativeTimeLabel(Some(isoAt(-1, hour: 23)), now), "昨天")
    @Expect(relativeTimeLabel(Some(dayAt(-20)), now), "10/01")
    @Expect(relativeTimeLabel(None, now), "—")
}

@Test
func weeklyReviewWindowCoversTodayMinusSixThroughToday(): Unit {
    let items = [
        mkItem(
            "boundary-in",
            GtdKind.Action,
            "窗口第一天凌晨",
            status: GtdStatus.Done,
            completedAt: Some(COMPLETED_ISO)
        ),
        mkItem(
            "boundary-out",
            GtdKind.Action,
            "窗口前一天深夜",
            status: GtdStatus.Done,
            completedAt: Some("2026-10-14T15:59:00.000Z")
        ),
        mkItem(
            "today-done",
            GtdKind.Action,
            "今天完成",
            status: GtdStatus.Done,
            completedAt: Some("2026-10-20T16:30:00.000Z")
        )
    ]
    let stats = weeklyReview(GtdWorkspace(items: items), TEST_TODAY)
    @Expect(stats.windowStart, "2026-10-15")
    @Expect(stats.today, "2026-10-21")
    @Expect(joinIds(stats.completedThisWeek), "today-done,boundary-in")
}

@Test
func weeklyReviewCountsDemoResearchItemAsCompletedThisWeek(): Unit {
    let item = mkItem(
        "act_research",
        GtdKind.Action,
        "需求梳理与竞品盘点",
        status: GtdStatus.Done,
        completedAt: Some(COMPLETED_ISO)
    )
    let stats = weeklyReview(GtdWorkspace(items: [item]), TEST_TODAY)
    @Expect(stats.completedCount, 1)
    @Expect(joinIds(stats.completedThisWeek), "act_research")
}

/* ------------------------------------------------------------------ */
/* weeklyReview                                                        */
/* ------------------------------------------------------------------ */

@Test
func weeklyReviewCountsAllMetrics(): Unit {
    let project = mkItem(
        "p1",
        GtdKind.Project,
        "官网改版",
        status: GtdStatus.Active,
        startDate: Some(dayAt(-5)),
        dueDate: Some(dayAt(8))
    )
    let items = [
        mkItem("inbox1", GtdKind.Action, "待澄清", status: GtdStatus.Inbox, capturedAt: Some(isoAt(-1))),
        mkItem(
            "done-this-week",
            GtdKind.Action,
            "本周完成",
            status: GtdStatus.Done,
            completedAt: Some(isoAt(-2)),
            capturedAt: Some(isoAt(-5)),
            clarified: true
        ),
        mkItem(
            "done-old",
            GtdKind.Action,
            "很久以前完成",
            status: GtdStatus.Done,
            completedAt: Some(isoAt(-10))
        ),
        mkItem("overdue", GtdKind.Action, "超期", status: GtdStatus.Next, dueDate: Some(dayAt(-2))),
        mkItem("due-today", GtdKind.Action, "今天到期", status: GtdStatus.Next, dueDate: Some(dayAt(0))),
        mkItem("undated", GtdKind.Action, "无日期", status: GtdStatus.Next),
        mkItem(
            "waiting-old",
            GtdKind.Action,
            "等待很久",
            status: GtdStatus.Waiting,
            capturedAt: Some(isoAt(-9)),
            clarified: true,
            waitingFor: Some("法务")
        ),
        mkItem(
            "cleared",
            GtdKind.Action,
            "本周已澄清",
            status: GtdStatus.Next,
            dueDate: Some(dayAt(3)),
            capturedAt: Some(isoAt(-2)),
            clarified: true
        ),
        project
    ]
    let stats = weeklyReview(GtdWorkspace(items: items), TEST_TODAY)

    @Expect(stats.inboxCount, 1)
    @Expect(stats.inboxClearedCount, 2)
    @Expect(stats.inboxProgress, 67)
    @Expect(stats.completedCount, 1)
    @Expect(joinIds(stats.completedThisWeek), "done-this-week")
    @Expect(stats.overdueCount, 1)
    @Expect(joinIds(stats.overdue), "overdue")
    @Expect(stats.undatedCount, 1)
    @Expect(joinIds(stats.undatedTasks), "undated")
    @Expect(stats.waitingOverdueCount, 1)
    @Expect(stats.stuckProjectCount, 1)
    @Expect(stats.staleAreas.size, 0)
}

@Test
func weeklyReviewGivesEmptyWorkspaceFullInboxProgress(): Unit {
    let stats = weeklyReview(GtdWorkspace(items: []), TEST_TODAY)
    @Expect(stats.inboxProgress, 100)
    @Expect(stats.inboxCount, 0)
    @Expect(stats.completedCount, 0)
    @Expect(stats.windowStart, dayAt(-6))
}

@Test
func weeklyReviewFlagsStaleAreas(): Unit {
    let areas = [GtdArea("area_a", "产品"), GtdArea("area_b", "增长")]
    let items = [
        mkItem(
            "stale-1",
            GtdKind.Action,
            "老任务一",
            status: GtdStatus.Next,
            areaId: Some("area_a"),
            updatedAt: dayAt(-20)
        ),
        mkItem(
            "stale-2",
            GtdKind.Project,
            "老项目二",
            status: GtdStatus.Active,
            areaId: Some("area_a"),
            updatedAt: dayAt(-30)
        ),
        mkItem(
            "fresh",
            GtdKind.Action,
            "刚碰过",
            status: GtdStatus.Next,
            areaId: Some("area_b"),
            updatedAt: dayAt(-1)
        )
    ]
    let stats = weeklyReview(GtdWorkspace(items: items, areas: areas), TEST_TODAY)
    @Expect(stats.staleAreas.size, 1)
    @Expect(stats.staleAreas[0].area.id, "area_a")
    @Expect(stats.staleAreas[0].openCount, 2)
    @Expect(stats.staleAreas[0].lastTouched, Some(dayAt(-20)))
}

@Test
func weeklyReviewRejectsInvalidToday(): Unit {
    var thrown = false
    try {
        weeklyReview(GtdWorkspace(items: []), "not-a-date")
    } catch (error: IllegalArgumentException) {
        thrown = true
    }
    @Expect(thrown, true)
}

/* ------------------------------------------------------------------ */
/* filterNextActions                                                   */
/* ------------------------------------------------------------------ */

func filterFixture(): Array<GtdItem> {
    [
        mkItem(
            "a",
            GtdKind.Action,
            "写官网文案",
            tags: ["官网"],
            dueDate: Some(dayAt(-1)),
            capturedAt: Some(isoAt(-2)),
            clarified: true,
            context: Some("电脑")
        ),
        mkItem(
            "b",
            GtdKind.Action,
            "打电话",
            dueDate: Some(dayAt(3)),
            capturedAt: Some(isoAt(-1)),
            clarified: true,
            context: Some("电话")
        ),
        mkItem("c", GtdKind.Action, "无场景任务")
    ]
}

@Test
func filterNextActionsByContextSentinelDueAndSearch(): Unit {
    let items = filterFixture()
    @Expect(
        joinIds(filterNextActions(items, NextFilter(context: Some("电脑"), today: TEST_TODAY))),
        "a"
    )
    @Expect(
        joinIds(filterNextActions(items, NextFilter(context: Some(NO_CONTEXT_FILTER), today: TEST_TODAY))),
        "c"
    )
    @Expect(
        joinIds(filterNextActions(items, NextFilter(dueSoonOnly: true, today: TEST_TODAY))),
        "a"
    )
    @Expect(
        joinIds(filterNextActions(items, NextFilter(search: "文案", today: TEST_TODAY))),
        "a"
    )
    @Expect(joinIds(filterNextActions(items, NextFilter(today: TEST_TODAY))), "a,b,c")
    @Expect(
        joinIds(filterNextActions(items, NextFilter(search: "无场景", today: TEST_TODAY))),
        "c"
    )
}

/* ------------------------------------------------------------------ */
/* 澄清表单 → patch                                                    */
/* ------------------------------------------------------------------ */

func baseForm(): ClarifyFormState {
    ClarifyFormState(
        clarifyType: ClarifyType.Next,
        title: "  给财务回电  ",
        notes: "确认发票抬头",
        tags: "#杂事, 财务，杂事",
        areaId: "area_product",
        context: "__custom__",
        customContext: "飞机上",
        energy: Energy.High,
        estimateMin: Some(2),
        dueDate: "2026-01-02"
    )
}

@Test
func clarifyPatchMapsTitleTagsAreaDateAndGtdFields(): Unit {
    let patch = buildClarifyPatch(baseForm())
    @Expect(patch.title, "给财务回电")
    @Expect(joinTags(patch.tags), "杂事,财务")
    @Expect(patch.areaId, Some("area_product"))
    @Expect(patch.dueDate, Some("2026-01-02"))
    @Expect(patch.context, "飞机上")
    @Expect(patch.energy, Energy.High)
    @Expect(patch.waitingFor, "")
    @Expect(patch.twoMinuteCandidate, true)
    @Expect(patch.clarified, true)
    @Expect(clarifyTargetStatus(baseForm()), GtdStatus.Next)
}

@Test
func clarifyTargetStatusMapsDelegatedSomedayAndArchive(): Unit {
    @Expect(clarifyTargetStatus(baseForm().patched(delegated: Some(true), waitingFor: Some("张律师"))), GtdStatus.Waiting)
    @Expect(clarifyTargetStatus(baseForm().patched(someday: Some(true))), GtdStatus.Someday)
    @Expect(clarifyTargetStatus(baseForm().patched(clarifyType: Some(ClarifyType.Reference))), GtdStatus.Done)
    @Expect(clarifyTargetStatus(baseForm().patched(clarifyType: Some(ClarifyType.Note))), GtdStatus.Done)
}

@Test
func clarifyValidationRequiresTitleWaitingForAndExclusiveStatus(): Unit {
    @Expect(validateClarifyForm(baseForm().patched(title: Some("   "))).title.isSome(), true)
    @Expect(
        validateClarifyForm(baseForm().patched(delegated: Some(true), waitingFor: Some("  "))).waitingFor.isSome(),
        true
    )
    @Expect(
        validateClarifyForm(
            baseForm().patched(delegated: Some(true), waitingFor: Some("张律师"), someday: Some(true))
        ).status.isSome(),
        true
    )
    @Expect(validateClarifyForm(baseForm()).isEmpty(), true)
    // 归档类型不受委派/某天约束
    @Expect(
        validateClarifyForm(
            baseForm().patched(clarifyType: Some(ClarifyType.Reference), delegated: Some(true))
        ).isEmpty(),
        true
    )
}

@Test
func clarifyNewItemCarriesStatusAndSourceCapturedAt(): Unit {
    let source = mkItem(
        "inbox1",
        GtdKind.Action,
        "旧标题",
        capturedAt: Some(isoAt(-4)),
        context: Some("电话")
    )
    let action = buildClarifyNewItem(baseForm(), source, GtdStatus.Next, "act_new", isoAt(0))
    @Expect(kindText(action.kind), "action")
    @Expect(statusText(action.status), "next")
    @Expect(action.capturedAt, source.capturedAt)
    @Expect(action.startDate, Option<String>.None)

    let project = buildClarifyNewItem(
        baseForm().patched(clarifyType: Some(ClarifyType.Project)),
        source,
        GtdStatus.Next,
        "prj_new",
        isoAt(0)
    )
    @Expect(kindText(project.kind), "project")

    let orphan = mkItem("inbox2", GtdKind.Action, "无收集时间")
    let created = buildClarifyNewItem(baseForm(), orphan, "act_new2", isoAt(0))
    @Expect(created.capturedAt, Some(isoAt(0)))
    @Expect(statusText(created.status), "next")
}

@Test
func createClarifyFormSendsCustomContextToCustomInput(): Unit {
    let item = mkItem(
        "x",
        GtdKind.Reference,
        "竞品截图",
        tags: ["竞品", "定价"],
        areaId: Some("area_product"),
        status: GtdStatus.Inbox,
        capturedAt: Some(isoAt(-1)),
        context: Some("通勤"),
        energy: Some(Energy.Medium),
        twoMinuteCandidate: true,
        dueDate: Some(dayAt(4))
    )
    let form = createClarifyForm(item)
    @Expect(form.clarifyType, ClarifyType.Reference)
    @Expect(form.context, "__custom__")
    @Expect(form.customContext, "通勤")
    @Expect(form.estimateMin, Some(2))
    @Expect(form.dueDate, dayAt(4))
    @Expect(form.tags, "竞品 定价")
    @Expect(form.areaId, "area_product")
    @Expect(form.delegated, false)
}

@Test
func createClarifyFormKeepsPresetContextsInline(): Unit {
    let item = mkItem("y", GtdKind.Action, "打电话", status: GtdStatus.Waiting, context: Some(" 电话 "), waitingFor: Some("张律师"))
    let form = createClarifyForm(item)
    @Expect(form.clarifyType, ClarifyType.Next)
    @Expect(form.context, "电话")
    @Expect(form.customContext, "")
    @Expect(form.delegated, true)
    @Expect(form.waitingFor, "张律师")
    @Expect(form.energy, Energy.Medium)
    @Expect(form.estimateMin, Option<Int64>.None)
}

@Test
func parseTagsSplitsOnBothCommasAndWhitespace(): Unit {
    @Expect(joinTags(parseTags("#杂事, 财务，杂事")), "杂事,财务")
    @Expect(joinTags(parseTags("  #a   b  ")), "a,b")
    @Expect(joinTags(parseTags("")), "")
    @Expect(joinTags(parseTags("##x,y#z")), "x,y#z")
}

/* ------------------------------------------------------------------ */
/* 展示辅助                                                            */
/* ------------------------------------------------------------------ */

@Test
func deadlineInfoTonesFollowDueDistance(): Unit {
    let overdue = deadlineInfo(mkItem("d1", GtdKind.Action, "超期", dueDate: Some(dayAt(-2))), TEST_TODAY)
    @Expect(overdue.label, "逾期 2 天")
    @Expect(overdue.tone, DeadlineTone.Danger)
    @Expect(overdue.date, Some(dayAt(-2)))

    let dueToday = deadlineInfo(mkItem("d2", GtdKind.Action, "今天", dueDate: Some(dayAt(0))), TEST_TODAY)
    @Expect(dueToday.label, "今天到期")
    @Expect(dueToday.tone, DeadlineTone.Accent)

    let future = deadlineInfo(mkItem("d3", GtdKind.Action, "以后", dueDate: Some(dayAt(5))), TEST_TODAY)
    @Expect(future.label, "10/26")
    @Expect(future.tone, DeadlineTone.Muted)

    let undated = deadlineInfo(mkItem("d4", GtdKind.Action, "无期"), TEST_TODAY)
    @Expect(undated.label, "未设截止")
    @Expect(undated.tone, DeadlineTone.Muted)
    @Expect(undated.date, Option<String>.None)
}

@Test
func appendTimestampedNoteKeepsExistingNotes(): Unit {
    @Expect(
        appendTimestampedNote("已有记录", "催办：已提醒 张律师", "2026-10-21T09:05:00+08:00"),
        "已有记录\n[2026-10-21 09:05] 催办：已提醒 张律师"
    )
    @Expect(
        appendTimestampedNote("", "澄清：归档为笔记。", "2026-10-21T09:05:00+08:00"),
        "[2026-10-21 09:05] 澄清：归档为笔记。"
    )
}

/* ------------------------------------------------------------------ */
/* 项目健康度                                                          */
/* ------------------------------------------------------------------ */

@Test
func projectHealthCountsChildrenAndFlagsStuck(): Unit {
    let project = mkItem("p1", GtdKind.Project, "官网改版", status: GtdStatus.Active, dueDate: Some(dayAt(10)))
    let stuck = mkItem("p2", GtdKind.Project, "停滞项目", status: GtdStatus.Active)
    let doneChild = mkItem("c1", GtdKind.Action, "已完成", parentId: Some("p1"), status: GtdStatus.Done)
    let nextChild = mkItem("c2", GtdKind.Action, "进行中", parentId: Some("p1"), status: GtdStatus.Next)
    let health = projectHealth(GtdWorkspace(items: [project, stuck, doneChild, nextChild]))
    @Expect(health.size, 2)
    @Expect(health[0].project.id, "p1")
    @Expect(health[0].total, 2)
    @Expect(health[0].done, 1)
    @Expect(health[0].open, 1)
    @Expect(health[0].next, 1)
    @Expect(health[0].progress, 50)
    @Expect(health[0].stuck, false)
    @Expect(health[1].stuck, true)
    @Expect(health[1].progress, 0)
}

@Test
func rollupProgressAveragesKeyResults(): Unit {
    let objective = mkItem("o1", GtdKind.Objective, "目标")
    let kr1 = mkItem("kr1", GtdKind.KeyResult, "KR1", parentId: Some("o1"), metric: Some(GtdMetric(0.0, 100.0, current: 40.0)))
    let kr2 = mkItem("kr2", GtdKind.KeyResult, "KR2", parentId: Some("o1"), status: GtdStatus.Done)
    let workspace = GtdWorkspace(items: [objective, kr1, kr2])
    @Expect(rollupProgress(workspace, "o1"), 70)
    @Expect(rollupProgress(workspace, "kr1"), 40)
    @Expect(rollupProgress(workspace, "missing"), 0)
}
