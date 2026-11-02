package textura.views.calendar.logic

import std.unittest.*
import std.unittest.testmacro.*
import std.collection.*

/**
 * 月网格 / 周区间 / 标题文案验收：逐条移植
 * `src/modules/calendar/calendarLogic.test.ts` 的 buildMonthGrid、
 * weekRange / weekDays、monthLabel / weekLabel 断言。
 */
@Test
class GridTest {
    @TestCase
    func octoberGridShape(): Unit {
        let cells = buildMonthGrid(2026, 10)
        @Expect(cells.size, 42)
        @Expect(cells[0].key, "2026-09-28")
        @Expect(cells[0].weekday, 0) // 周一
        @Expect(cells[0].inMonth, false)
        @Expect(cells[41].key, "2026-11-08")
        var inMonth = 0
        for (cell in cells) {
            if (cell.inMonth) {
                inMonth += 1
            }
        }
        @Expect(inMonth, 31)
    }

    @TestCase
    func rowsStartOnMonday(): Unit {
        let cells = buildMonthGrid(2026, 10)
        for (row in 0..6) {
            for (column in 0..7) {
                @Expect(cells[row * 7 + column].weekday, column)
            }
        }
        @Expect(cells[3].key, "2026-10-01")
        @Expect(cells[3].inMonth, true)
        @Expect(weekdayLabel(cells[3].key), "星期四")
    }

    @TestCase
    func weekendColumns(): Unit {
        let cells = buildMonthGrid(2026, 10)
        @Expect(cells[5].weekend, true) // 周六
        @Expect(cells[6].weekend, true) // 周日
        @Expect(cells[4].weekend, false)
    }

    @TestCase
    func gridCrossesYearBoundary(): Unit {
        let cells = buildMonthGrid(2027, 1)
        @Expect(cells[0].key, "2026-12-28")
        @Expect(cells[41].key, "2027-02-07")
        @Expect(shiftMonth(2026, 12, 1), YearMonth(2027, 1))
        @Expect(shiftMonth(2026, 1, -1), YearMonth(2025, 12))
        @Expect(shiftMonth(2026, 10, 3), YearMonth(2027, 1))
        @Expect(shiftMonth(2026, 10, -10), YearMonth(2025, 12))
    }

    @TestCase
    func februaryLeapYear(): Unit {
        @Expect(countInMonth(buildMonthGrid(2024, 2)), 29)
        @Expect(countInMonth(buildMonthGrid(2026, 2)), 28)
    }

    @TestCase
    func twentyEightDayMonthStartsOnMonday(): Unit {
        // 2027-02-01 是周一：整月 28 天正好占满 4 行，其余 14 格为上下月补位
        let cells = buildMonthGrid(2027, 2)
        @Expect(cells.size, 42)
        @Expect(cells[0].key, "2027-02-01")
        @Expect(cells[0].inMonth, true)
        @Expect(cells[27].key, "2027-02-28")
        @Expect(cells[27].inMonth, true)
        @Expect(cells[28].key, "2027-03-01")
        @Expect(cells[28].inMonth, false)
        @Expect(cells[41].key, "2027-03-14")
        @Expect(countInMonth(cells), 28)
    }

    @TestCase
    func thirtyOneDayMonthEndsOnSunday(): Unit {
        // 2026-05-01 是周五，31 天；末格必须越过 6 行
        let cells = buildMonthGrid(2026, 5)
        @Expect(cells[0].key, "2026-04-27")
        @Expect(cells[41].key, "2026-06-07")
        @Expect(countInMonth(cells), 31)
        @Expect(cells[41].weekday, 6)
    }

    @TestCase
    func gridRowsMatchFlatGrid(): Unit {
        let rows = buildMonthGridRows(2026, 10)
        @Expect(rows.size, 6)
        let flat = buildMonthGrid(2026, 10)
        for (row in 0..6) {
            @Expect(rows[row].size, 7)
            for (column in 0..7) {
                @Expect(rows[row][column].key, flat[row * 7 + column].key)
            }
        }
    }

    @TestCase
    func invalidMonthReturnsEmptyGrid(): Unit {
        @Expect(buildMonthGrid(2026, 13).size, 0)
        @Expect(buildMonthGrid(2026, 0).size, 0)
    }

    @TestCase
    func weekRangeOfWednesday(): Unit {
        let range = weekRange("2026-10-21")
        @Expect(range.start.key(), "2026-10-19")
        @Expect(range.end.key(), "2026-10-25")
        @Expect(range.year, 2026)
        @Expect(range.month, 10)
        @Expect(range.monthEnd, 10)
    }

    @TestCase
    func sundayBelongsToSameWeek(): Unit {
        let range = weekRange("2026-10-25")
        @Expect(range.start.key(), "2026-10-19")
        @Expect(range.end.key(), "2026-10-25")
        @Expect(range.monthEnd, 10)
    }

    @TestCase
    func weekCrossesYear(): Unit {
        let range = weekRange("2027-01-01")
        @Expect(range.start.key(), "2026-12-28")
        @Expect(range.end.key(), "2027-01-03")
        @Expect(range.year, 2026)
        @Expect(range.month, 12)
        @Expect(range.monthEnd, 1)
    }

    @TestCase
    func weekDaysAreSevenConsecutive(): Unit {
        let days = weekDays("2026-10-21")
        @Expect(days.size, 7)
        let expected = [
            "2026-10-19",
            "2026-10-20",
            "2026-10-21",
            "2026-10-22",
            "2026-10-23",
            "2026-10-24",
            "2026-10-25"
        ]
        for (index in 0..7) {
            @Expect(days[index].key, expected[index])
            @Expect(days[index].weekday, index)
            @Expect(days[index].inMonth, true)
        }
        @Expect(days[5].weekend, true)
        @Expect(days[6].weekend, true)
        @Expect(days[4].weekend, false)
    }

    @TestCase
    func monthAndWeekLabels(): Unit {
        @Expect(monthLabel(2026, 10), "2026年10月")
        @Expect(weekLabel("2026-10-21"), "10月19日 – 25日")
        @Expect(weekLabel("2026-10-01"), "9月28日 – 10月4日")
        @Expect(weekLabel("2027-01-01"), "2026年12月28日 – 1月3日")
    }

    @TestCase
    func weekdayLabels(): Unit {
        let expected = ["一", "二", "三", "四", "五", "六", "日"]
        for (index in 0..7) {
            @Expect(WEEKDAY_LABELS[index], expected[index])
        }
        @Expect(weekdayLabel("2026-10-19"), "星期一")
        @Expect(weekdayLabel("2026-10-25"), "星期日")
    }

    @TestCase
    func selectorOptions(): Unit {
        let months = monthOptions()
        @Expect(months.size, 12)
        @Expect(months[0].value, "1")
        @Expect(months[0].label, "一月")
        @Expect(months[11].value, "12")
        @Expect(months[11].label, "十二月")

        let years = yearOptions()
        @Expect(years.size, 201)
        @Expect(years[0].value, "1900")
        @Expect(years[0].label, "1900年")
        @Expect(years[200].value, "2100")
        @Expect(years[200].label, "2100年")
    }

    func countInMonth(cells: Array<MonthCell>): Int64 {
        var count = 0
        for (cell in cells) {
            if (cell.inMonth) {
                count += 1
            }
        }
        return count
    }
}
