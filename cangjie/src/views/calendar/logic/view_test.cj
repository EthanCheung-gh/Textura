package textura.views.calendar.logic

import std.unittest.*
import std.unittest.testmacro.*
import std.collection.*

/**
 * 面向渲染的模型验收：6×7 月网格、周视图 7 列、
 * 单元格折叠计数（`overflowCount`）、跨天条目「第 n/m 天」。
 */
@Test
class ViewTest {
    @TestCase
    func monthViewIsSixBySeven(): Unit {
        let rows = buildMonthView(2026, 10, Array<CalItem>(), "2026-10-21", "2026-10-21")
        @Expect(rows.size, 6)
        for (row in 0..6) {
            @Expect(rows[row].size, 7)
        }
        @Expect(rows[0][0].key(), "2026-09-28")
        @Expect(rows[5][6].key(), "2026-11-08")
    }

    @TestCase
    func monthViewMatchesFlatGrid(): Unit {
        let flat = buildMonthViewFlat(2026, 10, Array<CalItem>(), "2026-10-21", "2026-10-21")
        @Expect(flat.size, 42)
        let grid = buildMonthGrid(2026, 10)
        for (index in 0..42) {
            @Expect(flat[index].key(), grid[index].key)
            @Expect(flat[index].inMonth, grid[index].inMonth)
            @Expect(flat[index].weekend, grid[index].weekend)
        }
    }

    @TestCase
    func monthCellFlagsTodayAndSelected(): Unit {
        let flat = buildMonthViewFlat(2026, 10, Array<CalItem>(), "2026-10-21", "2026-10-05")
        let today = findCell(flat, "2026-10-21")
        @Expect(today.isToday, true)
        @Expect(today.isSelected, false)
        let selected = findCell(flat, "2026-10-05")
        @Expect(selected.isToday, false)
        @Expect(selected.isSelected, true)
    }

    @TestCase
    func monthCellLunarText(): Unit {
        let flat = buildMonthViewFlat(2026, 10, Array<CalItem>(), "2026-10-21", "2026-10-21")
        // 初一显示月名
        @Expect(findCell(flat, "2026-10-10").lunarText, "九月")
        @Expect(findCell(flat, "2026-10-21").lunarText, "十二")

        // 2026-09-25 中秋 / 2026-09-23 秋分都在 9 月网格里
        let september = buildMonthViewFlat(2026, 9, Array<CalItem>(), "2026-10-21", "2026-10-21")
        let midAutumn = findCell(september, "2026-09-25")
        @Expect(midAutumn.ymd, Ymd(2026, 9, 25))
        @Expect(midAutumn.lunarText, "中秋")
        @Expect(midAutumn.isFestival, true)
        @Expect(midAutumn.lunarKind, LunarLabelKind.Festival)
        // 2026-09-23 秋分（节气，不是节日）
        let term = findCell(september, "2026-09-23")
        @Expect(term.ymd, Ymd(2026, 9, 23))
        @Expect(term.lunarText, "秋分")
        @Expect(term.isSolarTerm, true)
        @Expect(term.isFestival, false)
        @Expect(term.lunarKind, LunarLabelKind.Term)

        // 超出农历范围（1900-01-31 之前）：空标签
        let ancient = buildMonthViewFlat(1900, 1, Array<CalItem>(), "1900-01-15", "1900-01-15")
        let outside = findCell(ancient, "1900-01-15")
        @Expect(outside.ymd, Ymd(1900, 1, 15))
        @Expect(outside.lunarText, "")
        @Expect(outside.lunarKind, LunarLabelKind.NoLabel)
    }

    @TestCase
    func monthCellOverflowCount(): Unit {
        // 2026-10-06 放 5 个单日条目 → 只显示 3 个，overflow = 2
        let items = Array<CalItem>(5, repeat: emptyTestItem())
        for (index in 0..5) {
            items[index] = CalItem(
                "i${index}",
                "条目${index}",
                "action",
                "next",
                "2026-10-06",
                "2026-10-06",
                "",
                false
            )
        }
        let flat = buildMonthViewFlat(2026, 10, items, "2026-10-21", "2026-10-21")
        let cell = findCell(flat, "2026-10-06")
        @Expect(cell.itemCount, 5)
        @Expect(cell.visibleItems.size, 3)
        @Expect(cell.overflowCount, 2)
        @Expect(cell.items.size, 5)
    }

    @TestCase
    func monthCellNoOverflowUnderLimit(): Unit {
        let items = [
            CalItem("a", "A", "action", "next", "2026-10-06", "2026-10-06", "", false),
            CalItem("b", "B", "action", "next", "2026-10-06", "2026-10-06", "", false)
        ]
        let flat = buildMonthViewFlat(2026, 10, items, "2026-10-21", "2026-10-21")
        let cell = findCell(flat, "2026-10-06")
        @Expect(cell.itemCount, 2)
        @Expect(cell.overflowCount, 0)
        @Expect(cell.visibleItems.size, 2)
    }

    @TestCase
    func monthCellExactLimit(): Unit {
        let items = Array<CalItem>(3, repeat: emptyTestItem())
        for (index in 0..3) {
            items[index] = CalItem(
                "i${index}",
                "条目",
                "action",
                "next",
                "2026-10-06",
                "2026-10-06",
                "",
                false
            )
        }
        let cell = findCell(buildMonthViewFlat(2026, 10, items, "2026-10-21", "2026-10-21"), "2026-10-06")
        @Expect(cell.overflowCount, 0)
        @Expect(cell.visibleItems.size, 3)
    }

    @TestCase
    func monthCellHidesDroppedItems(): Unit {
        let items = [
            CalItem("a", "A", "action", "next", "2026-10-06", "2026-10-06", "", false),
            CalItem("d", "D", "action", "dropped", "2026-10-06", "2026-10-06", "", false)
        ]
        let cell = findCell(buildMonthViewFlat(2026, 10, items, "2026-10-21", "2026-10-21"), "2026-10-06")
        @Expect(cell.itemCount, 1)
        @Expect(cell.items[0].id, "a")
    }

    @TestCase
    func monthCellSpanningItemAppearsOnEveryDay(): Unit {
        let items = [CalItem("s", "跨天", "action", "next", "2026-10-04", "2026-10-07", "", false)]
        let flat = buildMonthViewFlat(2026, 10, items, "2026-10-21", "2026-10-21")
        for (day in 4..=7) {
            let cell = findCell(flat, "2026-10-0${day.toString()}")
            @Expect(cell.itemCount, 1)
        }
        @Expect(findCell(flat, "2026-10-03").itemCount, 0)
        @Expect(findCell(flat, "2026-10-08").itemCount, 0)
    }

    @TestCase
    func weekViewHasSevenColumns(): Unit {
        let columns = buildWeekView("2026-10-21", Array<CalItem>(), "2026-10-21", "2026-10-21")
        @Expect(columns.size, 7)
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
            @Expect(columns[index].key(), expected[index])
            @Expect(columns[index].weekday, index)
        }
        @Expect(columns[5].weekend, true)
        @Expect(columns[6].weekend, true)
        @Expect(columns[0].weekend, false)
    }

    @TestCase
    func weekColumnFlagsTodayAndSelected(): Unit {
        let columns = buildWeekView("2026-10-21", Array<CalItem>(), "2026-10-21", "2026-10-23")
        @Expect(columns[2].isToday, true)
        @Expect(columns[2].isSelected, false)
        @Expect(columns[4].isSelected, true)
    }

    @TestCase
    func weekColumnAriaLabel(): Unit {
        let columns = buildWeekView("2026-10-21", Array<CalItem>(), "2026-10-21", "2026-10-21")
        @Expect(columns[2].ariaLabel, "星期三 10月21日")
        @Expect(columns[0].ariaLabel, "星期一 10月19日")
    }

    @TestCase
    func weekColumnLunarText(): Unit {
        let columns = buildWeekView("2026-09-25", Array<CalItem>(), "2026-10-21", "2026-09-25")
        @Expect(columns[4].lunarText, "中秋")
        @Expect(columns[4].lunarKind, LunarLabelKind.Festival)
    }

    @TestCase
    func weekEntriesReportDayIndexAndCount(): Unit {
        // 2026-10-19 ～ 2026-10-21 跨天：三列分别标注第 1/2/3 天
        let items = [CalItem("s", "跨天", "action", "next", "2026-10-18", "2026-10-21", "", false)]
        let columns = buildWeekView("2026-10-21", items, "2026-10-21", "2026-10-21")
        @Expect(columns[0].entries.size, 1)
        let monday = columns[0].entries[0]
        @Expect(monday.dayCount, 4)
        @Expect(monday.dayIndex, 2)
        @Expect(monday.spanText, "第 2/4 天")
        let wednesday = columns[2].entries[0]
        @Expect(wednesday.dayIndex, 4)
        @Expect(wednesday.spanText, "第 4/4 天")
    }

    @TestCase
    func weekEntryForSingleDay(): Unit {
        let items = [CalItem("t", "单日", "action", "done", "2026-10-20", "2026-10-20", "", false)]
        let columns = buildWeekView("2026-10-21", items, "2026-10-21", "2026-10-21")
        let entry = columns[1].entries[0]
        @Expect(entry.dayIndex, 1)
        @Expect(entry.dayCount, 1)
        @Expect(entry.spanText, "")
        @Expect(entry.isDone, true)
    }

    @TestCase
    func weekEntryForDueOnly(): Unit {
        let items = [CalItem("b", "只有截止日", "action", "next", "", "2026-10-21", "", false)]
        let columns = buildWeekView("2026-10-21", items, "2026-10-21", "2026-10-21")
        @Expect(columns[2].entries.size, 1)
        let entry = columns[2].entries[0]
        @Expect(entry.dayCount, 1)
        @Expect(entry.spanText, "截止")
        @Expect(columns[1].entries.size, 0)
    }

    @TestCase
    func weekEntriesSortedAcrossDays(): Unit {
        let items = [
            CalItem("b", "B 单日", "action", "next", "2026-10-21", "2026-10-21", "", false),
            CalItem("a", "A 单日", "action", "next", "2026-10-21", "2026-10-21", "", false),
            CalItem("s", "跨天", "action", "next", "2026-10-20", "2026-10-22", "", false)
        ]
        let columns = buildWeekView("2026-10-21", items, "2026-10-21", "2026-10-21")
        let entries = columns[2].entries
        @Expect(entries.size, 3)
        @Expect(entries[0].item.id, "s")
        @Expect(entries[1].item.id, "a")
        @Expect(entries[2].item.id, "b")
    }

    @TestCase
    func invalidMonthProducesEmptyView(): Unit {
        @Expect(buildMonthView(2026, 13, Array<CalItem>(), "", "").size, 0)
        @Expect(buildMonthViewFlat(2026, 13, Array<CalItem>(), "", "").size, 0)
    }

    @TestCase
    func emptyViewStillRendersLabels(): Unit {
        let rows = buildMonthView(2026, 2, Array<CalItem>(), "2026-02-16", "2026-02-16")
        @Expect(rows.size, 6)
        let flat = buildMonthViewFlat(2026, 2, Array<CalItem>(), "2026-02-16", "2026-02-16")
        // 2026-02-16 除夕
        let eve = findCell(flat, "2026-02-16")
        @Expect(eve.lunarText, "除夕")
        @Expect(eve.isFestival, true)
        @Expect(eve.isToday, true)
        // 2026-02-17 春节
        @Expect(findCell(flat, "2026-02-17").lunarText, "春节")
    }

    func findCell(cells: Array<DayCell>, key: String): DayCell {
        for (cell in cells) {
            if (cell.key() == key) {
                return cell
            }
        }
        return cells[0]
    }

    func emptyTestItem(): CalItem {
        return CalItem("", "", "", "", "", "", "", false)
    }
}
