package textura.views.gantt.logic

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * 逐条移植 Web 版 `scale.test.ts` 的 `buildHeader` 断言，并补充跨年、2 月/闰年、
 * 缩放切换后的 today 线位置与刻度压平。
 */
@Test
func buildHeaderDayModeHasOneColumnPerDay() {
    let header = buildHeader(DateRange("2026-06-01", "2026-06-30"), GanttZoom.Day, today: "2026-06-15")
    @Assert(header.columns.size, 30)
    @Assert(header.columns[0].start, "2026-06-01")
    @Assert(header.columns[0].x, 0.0)
    @Assert(header.columns[0].width, 40.0)
    @Assert(header.columns[0].label, "1")
    @Assert(header.columns[0].sublabel, Some("一"))
    // 2026-06-06 / 07 是周六 / 周日
    @Assert(header.columns[5].weekend, true)
    @Assert(header.columns[6].weekend, true)
    @Assert(header.columns[7].weekend, false)
    @Assert(header.columns[13].past, true) // 06-14
    @Assert(header.columns[14].past, false) // 06-15
    @Assert(header.groups.size, 1)
    @Assert(header.groups[0].label, "2026年6月")
    @Assert(header.width, 30.0 * 40.0)
}

@Test
func buildHeaderWeekModeUsesMondayWeeks() {
    let header = buildHeader(DateRange("2026-06-01", "2026-06-28"), GanttZoom.Week, today: "2026-06-15")
    @Assert(header.columns.size, 4)
    @Assert(header.columns[0].start, "2026-06-01")
    @Assert(header.columns[0].end, "2026-06-07")
    @Assert(header.columns[0].width, 196.0)
    @Assert(header.columns[0].label, "6/1")
    @Assert(header.columns[1].label, "6/8")
    @Assert(header.columns[0].sublabel.isNone(), true)
    @Assert(header.columns[0].weekend, false)
}

@Test
func buildHeaderMonthModeSlicesEverySevenDays() {
    let header = buildHeader(DateRange("2026-06-01", "2026-07-31"), GanttZoom.Month, today: "2026-06-15")
    let june = ArrayList<TimelineColumn>()
    for (column in header.columns) {
        if (column.start.startsWith("2026-06")) {
            june.add(column)
        }
    }
    let labels = ArrayList<String>()
    for (column in june) {
        labels.add(column.label)
    }
    @Assert(labels.toArray(), ["1", "8", "15", "22", "29"])
    @Assert(june[0].width, 7.0 * 12.0)
    @Assert(june[4].width, 2.0 * 12.0) // 06-29 / 30

    let groupLabels = ArrayList<String>()
    for (group in header.groups) {
        groupLabels.add(group.label)
    }
    @Assert(groupLabels.toArray(), ["2026 Q2", "2026 Q3"])
}

/* ------------------------------------------------------------------ *
 * 补充：跨年 / 2 月 / 闰年
 * ------------------------------------------------------------------ */
@Test
func buildHeaderCrossesYearInQuarterGroups() {
    let range = DateRange("2025-11-01", "2026-03-31")
    let header = buildHeader(range, GanttZoom.Month, today: "2026-01-15")
    @Assert(header.groups.size, 2)
    @Assert(header.groups[0].key, "2025-Q4")
    @Assert(header.groups[0].label, "2025 Q4")
    @Assert(header.groups[0].x, 0.0)
    @Assert(header.groups[0].width, 61.0 * 12.0)
    @Assert(header.groups[1].key, "2026-Q1")
    @Assert(header.groups[1].x, 61.0 * 12.0)
    @Assert(header.groups[1].width, 90.0 * 12.0)
    @Assert(header.width, 151.0 * 12.0)

    // 跨年分段：12 月末段在 12-31 收口，1 月首段从 01-01 起。
    @Assert(header.columns[9].key, "m-2025-12-29")
    @Assert(header.columns[9].start, "2025-12-29")
    @Assert(header.columns[9].end, "2025-12-31")
    @Assert(header.columns[9].width, 3.0 * 12.0)
    @Assert(header.columns[10].key, "m-2026-1-1")
    @Assert(header.columns[10].start, "2026-01-01")
    @Assert(header.columns[10].past, true) // 01-07 < 01-15
    @Assert(header.columns[12].past, false) // 01-15..01-21
}

@Test
func buildHeaderGroupsCrossYearDayRange() {
    let header = buildHeader(DateRange("2026-12-24", "2027-01-14"), GanttZoom.Day, today: "2026-12-31")
    @Assert(header.groups.size, 2)
    @Assert(header.groups[0].key, "2026-12")
    @Assert(header.groups[0].label, "2026年12月")
    @Assert(header.groups[0].width, 8.0 * 40.0)
    @Assert(header.groups[1].key, "2027-01")
    @Assert(header.groups[1].label, "2027年1月") // 首月补年份
    @Assert(header.groups[1].x, 8.0 * 40.0)
    @Assert(header.groups[1].width, 14.0 * 40.0)
    @Assert(header.columns.size, 22)
}

@Test
func buildHeaderHandlesLeapFebruary() {
    let leap = buildHeader(DateRange("2024-02-01", "2024-02-29"), GanttZoom.Month, today: "2024-02-15")
    @Assert(leap.columns.size, 5)
    @Assert(leap.columns[4].label, "29")
    @Assert(leap.columns[4].start, "2024-02-29")
    @Assert(leap.columns[4].end, "2024-02-29")
    @Assert(leap.columns[4].width, 12.0)

    let common = buildHeader(DateRange("2026-02-01", "2026-02-28"), GanttZoom.Month, today: "2026-02-15")
    @Assert(common.columns.size, 4) // 没有 29 号段
    @Assert(common.columns[3].label, "22")
    @Assert(common.columns[3].end, "2026-02-28")
    @Assert(common.columns[3].width, 7.0 * 12.0)

    // 闰日星期：2024-02-29 是周四。
    let leapDay = buildHeader(DateRange("2024-02-29", "2024-02-29"), GanttZoom.Day, today: "2024-03-01")
    @Assert(leapDay.columns[0].sublabel, Some("四"))
    @Assert(leapDay.columns[0].past, true)
}

/* ------------------------------------------------------------------ *
 * 补充：today 线位置（缩放切换）
 * ------------------------------------------------------------------ */
@Test
func todayLinePositionFollowsZoom() {
    let rows = [scheduled("a", "2026-03-02", "2026-03-20")]
    let px = 40.0
    let day = buildRange(rows, GanttZoom.Day, today: "2026-03-10")
    @Assert(day, DateRange("2026-02-23", "2026-04-03"))
    @Assert(dateToX("2026-03-10", day.start, px), 600.0)
    @Assert(totalWidth(day, px), 1600.0)
    let dayHeader = buildHeader(day, GanttZoom.Day, today: "2026-03-10")
    @Assert(dayHeader.columns.size, 40)
    var dayPast = 0
    for (column in dayHeader.columns) {
        if (column.past) {
            dayPast += 1
        }
    }
    @Assert(dayPast, 15)

    let week = buildRange(rows, GanttZoom.Week, today: "2026-03-10")
    @Assert(week, DateRange("2026-02-16", "2026-04-19"))
    @Assert(dateToX("2026-03-10", week.start, 28.0), 616.0)
    @Assert(totalWidth(week, 28.0), 1764.0)
    let weekHeader = buildHeader(week, GanttZoom.Week, today: "2026-03-10")
    @Assert(weekHeader.columns.size, 9)
    var weekPast = 0
    for (column in weekHeader.columns) {
        if (column.past) {
            weekPast += 1
        }
    }
    @Assert(weekPast, 3)

    let month = buildRange(rows, GanttZoom.Month, today: "2026-03-10")
    @Assert(month, DateRange("2026-01-01", "2026-05-31"))
    @Assert(dateToX("2026-03-10", month.start, 12.0), 816.0)
    @Assert(totalWidth(month, 12.0), 1812.0)
    let monthHeader = buildHeader(month, GanttZoom.Month, today: "2026-03-10")
    @Assert(monthHeader.columns.size, 24)
    var monthPast = 0
    for (column in monthHeader.columns) {
        if (column.past) {
            monthPast += 1
        }
    }
    @Assert(monthPast, 10)
}

@Test
func todayLineShiftsWhenSwitchingZoom() {
    // 同一个 today：各缩放下时间轴起点不同，today 线的像素位置也不同。
    let day = buildRange(Array<GanttRow>(), GanttZoom.Day, today: "2026-06-15")
    @Assert(day, DateRange("2026-06-08", "2026-06-29"))
    @Assert(dateToX("2026-06-15", day.start, zoomConfig(GanttZoom.Day).pxPerDay), 280.0)

    let week = buildRange(Array<GanttRow>(), GanttZoom.Week, today: "2026-06-15")
    @Assert(week, DateRange("2026-06-01", "2026-07-19"))
    @Assert(dateToX("2026-06-15", week.start, zoomConfig(GanttZoom.Week).pxPerDay), 392.0)

    let month = buildRange(Array<GanttRow>(), GanttZoom.Month, today: "2026-06-15")
    @Assert(month, DateRange("2026-05-01", "2026-08-31"))
    @Assert(dateToX("2026-06-15", month.start, zoomConfig(GanttZoom.Month).pxPerDay), 540.0)
}

/* ------------------------------------------------------------------ *
 * 补充：周/月模式的截断列与刻度压平
 * ------------------------------------------------------------------ */
@Test
func weekColumnsTruncateLastPartialWeek() {
    let header = buildHeader(DateRange("2026-06-03", "2026-06-20"), GanttZoom.Week, today: "2026-06-10")
    @Assert(header.columns.size, 3)
    @Assert(header.columns[0].key, "w-2026-06-03")
    @Assert(header.columns[0].start, "2026-06-03")
    @Assert(header.columns[0].end, "2026-06-09")
    @Assert(header.columns[0].past, true)
    @Assert(header.columns[1].past, false)
    @Assert(header.columns[2].start, "2026-06-17")
    @Assert(header.columns[2].end, "2026-06-20")
    @Assert(header.columns[2].width, 4.0 * 28.0)
}

@Test
func monthColumnsClipToRangeBounds() {
    let header = buildHeader(DateRange("2026-07-01", "2026-07-31"), GanttZoom.Month, today: "2026-07-10")
    @Assert(header.columns.size, 5)
    @Assert(header.columns[0].past, true)
    @Assert(header.columns[1].past, false)
    @Assert(header.columns[4].start, "2026-07-29")
    @Assert(header.columns[4].end, "2026-07-31")
    @Assert(header.columns[4].width, 3.0 * 12.0)
}

@Test
func dayColumnsTrackWeekdayAcrossMonthBoundary() {
    let header = buildHeader(DateRange("2026-06-29", "2026-07-02"), GanttZoom.Day, today: "2026-06-30")
    @Assert(header.columns.size, 4)
    @Assert(header.columns[0].key, "2026-06-29")
    @Assert(header.columns[0].sublabel, Some("一"))
    @Assert(header.columns[1].sublabel, Some("二"))
    @Assert(header.columns[2].key, "2026-07-01")
    @Assert(header.columns[2].sublabel, Some("三"))
    @Assert(header.columns[3].sublabel, Some("四"))
    @Assert(header.columns[0].past, true)
    @Assert(header.columns[1].past, false)
    @Assert(header.columns[2].x, 2.0 * 40.0)
}

@Test
func headerTicksFlattenGroupsThenColumns() {
    let header = buildHeader(DateRange("2026-06-01", "2026-07-31"), GanttZoom.Month, today: "2026-06-15")
    let ticks = headerTicks(header)
    @Assert(ticks.size, header.groups.size + header.columns.size)
    @Assert(ticks[0].kind, TickKind.Group)
    @Assert(ticks[0].label, "2026 Q2")
    @Assert(ticks[0].x, 0.0)
    @Assert(ticks[2].kind, TickKind.Column)
    @Assert(ticks[2].label, "1")
    @Assert(ticks[2].x, 0.0)

    let widths = columnWidths(header)
    @Assert(widths.size, header.columns.size)
    var total = 0.0
    for (width in widths) {
        total += width
    }
    @Assert(total, header.width)
}
