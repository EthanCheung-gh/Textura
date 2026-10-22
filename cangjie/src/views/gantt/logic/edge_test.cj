package textura.views.gantt.logic

import std.unittest.*
import std.unittest.testmacro.*

/**
 * 边界补充：儒略日整数运算、非法日期键、拖到边界外、零宽度视口相关换算。
 * 期望值与 TS 实现在同一输入下的输出一致（TS 侧由 `Math.round` / date-fns 给出）。
 */
@Test
func dayNumberRoundTripsKnownDates() {
    @Assert(dayNumber(1970, 1, 1), 0)
    @Assert(dayNumber(1969, 12, 31), -1)
    @Assert(dayNumber(2000, 2, 29), 11016)
    @Assert(dayNumber(2024, 2, 29), 19782)

    for (key in ["1970-01-01", "1969-12-31", "2024-02-29", "2025-12-31", "2026-06-10", "2027-03-01"]) {
        let number = parseDateKey(key).getOrThrow()
        @Assert(formatDateKey(number), key)
    }
}

@Test
func calendarDiffsCountDaysNotMilliseconds() {
    @Assert(diffDays("2024-02-28", "2024-03-01"), 2) // 闰年 2 月 29 日
    @Assert(diffDays("2026-02-28", "2026-03-01"), 1)
    @Assert(diffDays("2025-12-31", "2026-01-01"), 1)
    @Assert(diffDays("2026-01-01", "2025-01-01"), -365)
    @Assert(diffDays("2026-06-10", "2026-06-10"), 0)
}

@Test
func weekdayMatchesJavaScriptGetDay() {
    @Assert(weekdayOf(parseDateKey("2026-06-01").getOrThrow()), 1) // 周一
    @Assert(weekdayOf(parseDateKey("2026-06-07").getOrThrow()), 0) // 周日
    @Assert(weekdayOf(parseDateKey("2024-02-29").getOrThrow()), 4) // 周四
    @Assert(weekdayOf(parseDateKey("2026-06-06").getOrThrow()), 6) // 周六
}

@Test
func monthAndQuarterBoundariesAlign() {
    @Assert(startOfWeekKey("2026-06-01"), "2026-06-01") // 已经是周一
    @Assert(startOfWeekKey("2026-06-07"), "2026-06-01") // 周日回退到周一
    @Assert(endOfWeekKey("2026-06-07"), "2026-06-07")
    @Assert(endOfWeekKey("2026-06-01"), "2026-06-07")

    @Assert(startOfMonthKey("2024-02-29"), "2024-02-01")
    @Assert(endOfMonthKey("2024-02-10"), "2024-02-29") // 闰年
    @Assert(endOfMonthKey("2026-02-10"), "2026-02-28")
    @Assert(endOfMonthKey("2026-12-31"), "2026-12-31")

    @Assert(startOfQuarterKey("2026-08-15"), "2026-07-01")
    @Assert(endOfQuarterKey("2026-02-15"), "2026-03-31")
    @Assert(endOfQuarterKey("2026-12-01"), "2026-12-31")
    @Assert(quarterOfKey("2026-08-15"), 3)
    @Assert(quarterOfKey("2026-01-01"), 1)
}

@Test
func invalidDateKeysDegradeInsteadOfThrowing() {
    @Assert(parseDateKey("2026-02-30").isNone(), true) // 2026 年没有 2 月 30 日
    @Assert(parseDateKey("2026-13-01").isNone(), true)
    @Assert(parseDateKey("2026-6-1").isNone(), true) // 未补零
    @Assert(parseDateKey("not-a-date").isNone(), true)
    @Assert(isDateKey("2026-06-10"), true)
    @Assert(isDateKey("2026-06-10T00:00:00Z"), false)

    // itemRange 走 TS dateKey 语义：取前 10 个字符，非法串视为无排期。
    @Assert(
        itemRange(makeItem("a", "A", GanttKind.Action, startDate: Some("2026-06-10T00:00:00.000Z"))),
        Some(BarRange("2026-06-10", "2026-06-10"))
    )
    @Assert(itemRange(makeItem("b", "B", GanttKind.Action, startDate: Some("oops"))).isNone(), true)

    // 无法解析的键不会让几何计算抛错，退化为 0 像素。
    @Assert(dateToX("oops", "2026-06-01", 40.0), 0.0)
    @Assert(xToKey(-500.0, "2026-06-01", 40.0), "2026-05-19")
}

@Test
func roundMatchesTypeScriptHalfUpRule() {
    @Assert(tsRound(0.5), 1.0)
    @Assert(tsRound(-0.5), 0.0) // TS: Math.round(-0.5) === -0
    @Assert(tsRound(2.5), 3.0)
    @Assert(tsRound(-2.5), -2.0)
    @Assert(tsRound(1.4), 1.0)
    @Assert(tsRound(-1.4), -1.0)
}

@Test
func moveBarSurvivesFarOffsets() {
    // 拖到边界外很远仍然可计算（不夹取，由调用方决定是否限制）。
    @Assert(moveBar(BarRange("2026-01-01", "2026-01-03"), -100000.0), BarRange("1752-03-18", "1752-03-20"))
    @Assert(moveBar(BarRange("2026-06-10", "2026-06-14"), 2.5), BarRange("2026-06-13", "2026-06-17"))
    @Assert(moveBar(BarRange("2026-06-10", "2026-06-14"), -2.5), BarRange("2026-06-08", "2026-06-12"))
}

@Test
func resizeBarClampsAtEitherBoundary() {
    let bar = BarRange("2026-06-10", "2026-06-14")
    @Assert(resizeBar(bar, BarEdge.Start, 99999.0), BarRange("2026-06-14", "2026-06-14"))
    @Assert(resizeBar(bar, BarEdge.End, -99999.0), BarRange("2026-06-10", "2026-06-10"))
    @Assert(resizeBar(bar, BarEdge.Start, -400.0), BarRange("2025-05-06", "2026-06-14"))
    @Assert(resizeBar(bar, BarEdge.End, 2.5), BarRange("2026-06-10", "2026-06-17"))
    @Assert(resizeBar(bar, BarEdge.Start, -1.5), BarRange("2026-06-09", "2026-06-14"))
    // 反向区间先归一化，再按边缘调整。
    @Assert(resizeBar(BarRange("2026-06-14", "2026-06-10"), BarEdge.Start, 1.0), BarRange("2026-06-11", "2026-06-14"))
}

@Test
func geometrySurvivesZeroWidthInputs() {
    let range = DateRange("2026-06-01", "2026-06-30")
    @Assert(totalWidth(range, 40.0), 30.0 * 40.0)
    @Assert(totalWidth(DateRange("2026-06-01", "2026-06-01"), 40.0), 40.0)
    // 视口宽度 0：仍返回至少一天，不产生空区间。
    @Assert(visibleRange(range, 0.0, 0.0, 40.0), DateRange("2026-06-01", "2026-06-01"))
    @Assert(visibleRange(DateRange("2026-06-01", "2026-08-31"), 600.0, 480.0, 12.0), DateRange("2026-07-21", "2026-08-29"))

    let reversed = barGeometry(BarRange("2026-06-14", "2026-06-10"), "2026-06-12", 40.0)
    @Assert(reversed.start, "2026-06-10")
    @Assert(reversed.end, "2026-06-14")
    @Assert(reversed.x, -80.0)
    @Assert(reversed.width, 200.0)
    @Assert(reversed.days, 5)

    let single = barGeometry(BarRange("2026-06-12", "2026-06-12"), "2026-06-12", 40.0)
    @Assert(single.x, 0.0)
    @Assert(single.width, 40.0)
    @Assert(single.days, 1)
}

@Test
func buildRangeAtYearEndSpillsIntoNextYear() {
    let day = buildRange(Array<GanttRow>(), GanttZoom.Day, today: "2026-12-31")
    @Assert(day, DateRange("2026-12-24", "2027-01-14"))
    let week = buildRange(Array<GanttRow>(), GanttZoom.Week, today: "2026-12-31")
    @Assert(week, DateRange("2026-12-14", "2027-01-31"))
    let month = buildRange(Array<GanttRow>(), GanttZoom.Month, today: "2026-12-31")
    @Assert(month, DateRange("2026-12-01", "2027-03-31"))
}

@Test
func zoomConfigMatchesTypeScript() {
    let day = zoomConfig(GanttZoom.Day)
    @Assert(day.pxPerDay, 40.0)
    @Assert(day.columnDays, 1)
    @Assert(day.snapDays, 1)
    @Assert(day.paddingBefore, 7)
    @Assert(day.paddingAfter, 14)

    let week = zoomConfig(GanttZoom.Week)
    @Assert(week.pxPerDay, 28.0)
    @Assert(week.columnDays, 7)
    @Assert(week.paddingBefore, 14)
    @Assert(week.paddingAfter, 28)

    let month = zoomConfig(GanttZoom.Month)
    @Assert(month.pxPerDay, 12.0)
    @Assert(month.columnDays, 7)
    @Assert(month.paddingBefore, 30)
    @Assert(month.paddingAfter, 60)

    @Assert(ROW_HEIGHT, 36.0)
    @Assert(HEADER_HEIGHT, 52.0)
    @Assert(BAR_HEIGHT, 22.0)
    @Assert(BAR_TOP_OFFSET, 7.0)
    @Assert(UNGROUPED_ID, "__ungrouped")
}
