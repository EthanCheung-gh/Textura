package textura.views.gtd.logic

/*
 * 固定时区（Asia/Shanghai）的日期换算测试：跨月、跨年、闰日与非法输入。
 *
 * TS 版依赖 date-fns 与运行环境时区；这里锁死 UTC+8，并显式覆盖
 * 「UTC 日期与本地日期不同」的边界（凌晨/深夜）与跨年边界。
 */

@Test
func civilFromDaysRoundTripsAcrossLeapDay(): Unit {
    var days = daysFromCivil(2024, 2, 28)
    @Expect(civilFromDays(days).day, 28)
    days += 1
    @Expect(civilFromDays(days).month, 2)
    @Expect(civilFromDays(days).day, 29)
    days += 1
    @Expect(civilFromDays(days).month, 3)
    @Expect(civilFromDays(days).day, 1)
}

@Test
func civilFromDaysRoundTripsAcrossYearBoundary(): Unit {
    let lastDay = daysFromCivil(2026, 12, 31)
    let next = civilFromDays(lastDay + 1)
    @Expect(next.year, 2027)
    @Expect(next.month, 1)
    @Expect(next.day, 1)
    let previous = civilFromDays(lastDay - 1)
    @Expect(previous.year, 2026)
    @Expect(previous.month, 12)
    @Expect(previous.day, 30)
}

@Test
func dayOffsetCrossesMonthsAndYears(): Unit {
    @Expect(dayOffset(1, "2026-12-31"), "2027-01-01")
    @Expect(dayOffset(-1, "2027-01-01"), "2026-12-31")
    @Expect(dayOffset(-1, "2026-03-01"), "2026-02-28")
    @Expect(dayOffset(1, "2028-02-28"), "2028-02-29")
    @Expect(dayOffset(-6, "2026-10-21"), "2026-10-15")
    @Expect(dayOffset(0, "2026-10-21"), "2026-10-21")
}

@Test
func daysBetweenCountsCalendarDaysAndRejectsInvalid(): Unit {
    @Expect(daysBetween("2026-12-31", "2027-01-01"), 1)
    @Expect(daysBetween("2027-01-01", "2026-12-31"), -1)
    @Expect(daysBetween("2024-02-28", "2024-03-01"), 2)
    @Expect(daysBetween("2026-10-15", "2026-10-21"), 6)
    @Expect(daysBetween("not-a-date", "2026-10-21"), 0)
    @Expect(daysBetween("2026-10-15", ""), 0)
}

@Test
func localDayKeyRespectsYearBoundaryOffset(): Unit {
    // UTC 2026-12-31T16:30Z → 上海 2027-01-01 00:30
    @Expect(localDayKey(Some("2026-12-31T16:30:00Z")), Some("2027-01-01"))
    // UTC 2026-12-31T15:30Z → 上海 2026-12-31 23:30
    @Expect(localDayKey(Some("2026-12-31T15:30:00Z")), Some("2026-12-31"))
    // 不带时区按上海墙钟
    @Expect(localDayKey(Some("2026-12-31T23:59:00")), Some("2026-12-31"))
    // 毫秒与显式偏移
    @Expect(localDayKey(Some("2026-10-21T00:05:00.250+08:00")), Some("2026-10-21"))
    @Expect(localDayKey(Some("2026-10-20T23:59:59Z")), Some("2026-10-21"))
    @Expect(isValidDayKey("2026-02-29"), true)
    @Expect(isValidDayKey("2026-13-01"), false)
}

@Test
func dateKeyTruncatesWithoutValidating(): Unit {
    @Expect(dateKey(Some("2026-10-15T09:00:00Z")), Some("2026-10-15"))
    @Expect(dateKey(Some("  2026-10-15")), Some("2026-10-15"))
    @Expect(dateKey(Some("2026")), Option<String>.None)
    @Expect(dateKey(None), Option<String>.None)
}

@Test
func formatMonthDayAndDateTimeUseShanghaiTime(): Unit {
    @Expect(formatMonthDay(Some("2027-01-05")), "01/05")
    @Expect(formatMonthDay(Some("2026-10-21T09:00:00+08:00")), "10/21")
    @Expect(formatMonthDay(None), "—")
    @Expect(formatDateTime(Some("2026-12-31T16:30:00Z")), "2027-01-01 00:30")
    @Expect(formatDateTime(Some("2026-10-21T09:05:00+08:00")), "2026-10-21 09:05")
    @Expect(formatDateTime(Some("bad")), "—")
}

@Test
func waitingDaysAcrossMonthBoundaryUsesStrictThreshold(): Unit {
    let boundary = mkItem(
        "w-boundary",
        GtdKind.Action,
        "跨月七天",
        status: GtdStatus.Waiting,
        capturedAt: Some("2026-09-28T09:00:00+08:00")
    )
    @Expect(waitingDays(boundary, "2026-10-05"), 7)
    @Expect(isWaitingOverdue(boundary, "2026-10-05"), false)

    let beyond = mkItem(
        "w-beyond",
        GtdKind.Action,
        "跨月八天",
        status: GtdStatus.Waiting,
        capturedAt: Some("2026-09-27T09:00:00+08:00")
    )
    @Expect(waitingDays(beyond, "2026-10-05"), 8)
    @Expect(isWaitingOverdue(beyond, "2026-10-05"), true)
}

@Test
func waitingDaysAcrossYearBoundary(): Unit {
    let item = mkItem(
        "w-year",
        GtdKind.Action,
        "跨年等待",
        status: GtdStatus.Waiting,
        capturedAt: Some("2026-12-28T08:30:00+08:00")
    )
    @Expect(waitingDays(item, "2027-01-05"), 8)
    @Expect(isWaitingOverdue(item, "2027-01-05"), true)
    @Expect(waitingDays(item, "2027-01-04"), 7)
}
