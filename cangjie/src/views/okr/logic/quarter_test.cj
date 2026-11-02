package textura.views.okr.logic

import std.unittest.*
import std.unittest.testmacro.*

/*
 * 对齐 `src/modules/okr/okrMath.test.ts` 的 `quarterElapsedPercent` / `quarter helpers`
 * 两组断言，并补充边界（季度首次日、闰年、跨年、负偏移）。
 */

@Test
func quarterElapsedPercentReturnsZeroOnFirstDay() {
    @Assert(quarterElapsedPercent("2026-Q1", CivilDate(2026, 1, 1)), 0.0)
    @Assert(quarterElapsedPercent("2026-Q2", CivilDate(2026, 4, 1)), 0.0)
}

@Test
func quarterElapsedPercentReturnsHundredOnLastDay() {
    @Assert(quarterElapsedPercent("2026-Q1", CivilDate(2026, 3, 31)), 100.0)
    @Assert(quarterElapsedPercent("2026-Q4", CivilDate(2026, 12, 31)), 100.0)
    @Assert(quarterElapsedPercent("2026-Q2", CivilDate(2026, 6, 30)), 100.0)
}

@Test
func quarterElapsedPercentReportsCalendarProgress() {
    // 2026-Q1: 89 天，2/14 已过 44 天 -> 49.438% -> 49.4
    @Assert(approx(quarterElapsedPercent("2026-Q1", CivilDate(2026, 2, 14)), 49.4, 0.05), true)
    @Assert(approx(quarterElapsedPercent("2026-Q3", CivilDate(2026, 8, 15)), 49.5, 0.05), true)
    // 季度第二天
    @Assert(approx(quarterElapsedPercent("2026-Q1", CivilDate(2026, 1, 2)), 1.1, 0.05), true)
}

@Test
func quarterElapsedPercentClampsOutsideQuarter() {
    @Assert(quarterElapsedPercent("2025-Q1", CivilDate(2026, 2, 14)), 100.0)
    @Assert(quarterElapsedPercent("2026-Q3", CivilDate(2026, 2, 14)), 0.0)
    @Assert(quarterElapsedPercent("2027-Q4", CivilDate(2026, 2, 14)), 0.0)
    @Assert(quarterElapsedPercent("2026-Q1", CivilDate(2025, 12, 31)), 0.0)
    @Assert(quarterElapsedPercent("2026-Q2", CivilDate(2026, 7, 1)), 100.0)
}

@Test
func quarterElapsedPercentReturnsZeroForUnparseablePeriod() {
    @Assert(quarterElapsedPercent("2026-Q9", CivilDate(2026, 2, 14)), 0.0)
    @Assert(quarterElapsedPercent("", CivilDate(2026, 2, 14)), 0.0)
    @Assert(quarterElapsedPercent("2026Q1", CivilDate(2026, 2, 14)), 0.0)
    @Assert(quarterElapsedPercent("2026-Q0", CivilDate(2026, 2, 14)), 0.0)
    @Assert(quarterElapsedPercent("自定义", CivilDate(2026, 2, 14)), 0.0)
}

@Test
func quarterElapsedPercentHandlesLeapYear() {
    // 2024-Q1 共 90 天（闰年），2/29 已过 59 天 -> 65.55% -> 65.6
    @Assert(approx(quarterElapsedPercent("2024-Q1", CivilDate(2024, 2, 29)), 65.6, 0.05), true)
}

@Test
func quarterRangeSpansQuarterBoundaries() {
    let first = quarterRange("2026-Q1")
    @Assert(first.isSome(), true)
    @Assert(first.getOrThrow().start, "2026-01-01")
    @Assert(first.getOrThrow().end, "2026-03-31")

    let leap = quarterRange("2024-Q1")
    @Assert(leap.getOrThrow().end, "2024-03-31")

    let last = quarterRange("2026-Q4")
    @Assert(last.getOrThrow().start, "2026-10-01")
    @Assert(last.getOrThrow().end, "2026-12-31")

    @Assert(quarterRange("2026-Q5").isNone(), true)
    @Assert(quarterRange("2026-1").isNone(), true)
}

@Test
func daysInMonthAndValidationFollowGregorianRules() {
    @Assert(daysInMonth(2026, 1), 31)
    @Assert(daysInMonth(2026, 2), 28)
    @Assert(daysInMonth(2024, 2), 29)
    @Assert(daysInMonth(2000, 2), 29)
    @Assert(daysInMonth(1900, 2), 28)
    @Assert(daysInMonth(2026, 4), 30)
    @Assert(daysInMonth(2026, 13), 0)
    @Assert(isValidCivilDate(CivilDate(2026, 2, 28)), true)
    @Assert(isValidCivilDate(CivilDate(2026, 2, 29)), false)
    @Assert(isValidCivilDate(CivilDate(2026, 13, 1)), false)
}

@Test
func parseCivilDateKeyRejectsInvalidDates() {
    @Assert(parseCivilDateKey("2026-02-01").getOrThrow(), CivilDate(2026, 2, 1))
    @Assert(parseCivilDateKey("2026-02-01T00:00:00.000Z").getOrThrow(), CivilDate(2026, 2, 1))
    @Assert(parseCivilDateKey("2026-02-30").isNone(), true)
    @Assert(parseCivilDateKey("2026-2-1").isNone(), true)
    @Assert(parseCivilDateKey("x").isNone(), true)
    @Assert(parseCivilDateKey("").isNone(), true)
}

@Test
func shiftQuarterCrossesYearBoundaries() {
    @Assert(nextQuarter("2026-Q4"), "2027-Q1")
    @Assert(nextQuarter("2026-Q1"), "2026-Q2")
    @Assert(shiftQuarter("2026-Q1", -1), "2025-Q4")
    @Assert(shiftQuarter("2026-Q3", -5), "2025-Q2")
    @Assert(shiftQuarter("2026-Q1", -4), "2025-Q1")
    @Assert(shiftQuarter("2026-Q1", -5), "2024-Q4")
    @Assert(shiftQuarter("2026-Q1", 1000), "2276-Q1")
    @Assert(shiftQuarter("0000-Q1", -1), "-1-Q4")
}

@Test
func quarterLabelFormatsAndToleratesInvalidInput() {
    @Assert(quarterLabel("2026-Q4"), "2026 Q4")
    @Assert(quarterLabel("自定义"), "自定义")
    @Assert(nextQuarter("自定义"), "自定义")
    @Assert(shiftQuarter("2026Q1", 1), "2026Q1")
    @Assert(quarterLabel("2026-Q0"), "2026-Q0")
}
