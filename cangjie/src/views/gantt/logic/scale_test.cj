package textura.views.gantt.logic

import std.unittest.*
import std.unittest.testmacro.*

/**
 * 逐条移植 Web 版 `src/modules/gantt/scale.test.ts` 的断言（buildRange / dateToX /
 * snapDate / resizeBar / barGeometry / moveBar / displayProgress / visibleRange /
 * formatRangeLabel）。buildRows 见 rows_test.cj，buildHeader 见 header_test.cj。
 */

/** 测试用条目构造器（其余测试文件复用）。 */
func makeItem(
    id: String,
    title: String,
    kind: GanttKind,
    startDate!: ?String = None,
    endDate!: ?String = None,
    progress!: ?Float64 = None,
    status!: GanttStatus = GanttStatus.Next,
    parentId!: ?String = None,
    order!: Int64 = 0,
    level!: Int64 = 0
): GanttRow {
    GanttRow(
        id,
        title,
        kind: kind,
        level: level,
        startDate: startDate,
        endDate: endDate,
        progress: progress,
        status: status,
        parentId: parentId,
        order: order,
        createdAt: "2026-01-01T00:00:00.000Z"
    )
}

func scheduled(id: String, start: String, end: String, progress!: Float64 = 0.0): GanttRow {
    makeItem(id, id, GanttKind.Action, startDate: Some(start), endDate: Some(end), progress: Some(progress))
}

@Test
func buildRangeDefaultsToTodayPadding() {
    let day = buildRange(Array<GanttRow>(), GanttZoom.Day, today: "2026-06-15")
    @Assert(day, DateRange("2026-06-08", "2026-06-29"))

    let week = buildRange(Array<GanttRow>(), GanttZoom.Week, today: "2026-06-15")
    // 2026-06-01 - 14d = 06-01，对齐周一；06-15 + 28d = 07-13，对齐周日。
    @Assert(week.start, "2026-06-01")
    @Assert(week.end, "2026-07-19")
    @Assert(diffDays(week.start, week.end) > 30, true)

    let month = buildRange(Array<GanttRow>(), GanttZoom.Month, today: "2026-06-15")
    @Assert(month.start, "2026-05-01")
    @Assert(month.end, "2026-08-31")
}

@Test
func buildRangeCoversItemsWithBuffer() {
    let rows = [
        scheduled("a", "2026-06-10", "2026-06-12"),
        scheduled("b", "2026-06-05", "2026-06-20", progress: 50.0)
    ]
    let day = buildRange(rows, GanttZoom.Day, today: "2026-06-15")
    @Assert(day.start < "2026-06-05", true)
    @Assert(day.end > "2026-06-20", true)
    @Assert(day.start <= "2026-06-15" && day.end >= "2026-06-15", true)

    let week = buildRange(rows, GanttZoom.Week, today: "2026-06-15")
    @Assert(week.start <= "2026-06-05", true)
    @Assert(week.end >= "2026-06-20", true)

    let month = buildRange(rows, GanttZoom.Month, today: "2026-06-15")
    @Assert(month.start, "2026-05-01") // 06-05 - 30d = 05-06 → 月初
    @Assert(month.end, "2026-08-31")
}

@Test
func buildRangeCoversCrossYearItems() {
    let rows = [scheduled("a", "2025-12-30", "2026-01-02")]
    let month = buildRange(rows, GanttZoom.Month, today: "2026-01-01")
    @Assert(month.start <= "2025-12-30", true)
    @Assert(month.end >= "2026-01-02", true)
    @Assert(month.start, "2025-11-01")
    @Assert(month.end, "2026-03-31")

    let week = buildRange(rows, GanttZoom.Week, today: "2026-01-01")
    @Assert(week.start <= "2025-12-30", true)
    @Assert(week.end >= "2026-01-02", true)
}

@Test
func dateToXRoundsThroughYearBoundary() {
    let origin = "2025-12-20"
    let px = zoomConfig(GanttZoom.Day).pxPerDay
    var key = origin
    for (index in 0..60) {
        let x = dateToX(key, origin, px)
        @Assert(x, Float64(index) * px)
        @Assert(xToKey(x, origin, px), key)
        key = addDaysKey(key, 1)
    }
}

@Test
func dateToXIgnoresDstShifts() {
    // 2026-03-08 是北美 DST 切换日；日历差必须是 2 天而不是 47/48 小时。
    let px = 10.0
    @Assert(dateToX("2026-03-09", "2026-03-07", px), 2.0 * px)
    @Assert(dateToX("2026-03-10", "2026-03-07", px), 3.0 * px)
    @Assert(xToKey(2.0 * px, "2026-03-07", px), "2026-03-09")
    @Assert(xToKey(2.0 * px + 3.0, "2026-03-07", px), "2026-03-09")
    @Assert(xToKey(0.0, "2026-03-07", px), "2026-03-07")
}

@Test
func dateToXAcceptsKeysAndNegativeX() {
    @Assert(dateToX("2026-01-05", "2026-01-01", 20.0), 80.0)
    @Assert(xToKey(-1.0, "2026-01-05", 20.0), "2026-01-04")
    @Assert(xToKey(-25.0, "2026-01-05", 20.0), "2026-01-03")
}

@Test
func snapKeyDropsTimeForEveryZoom() {
    for (zoom in [GanttZoom.Day, GanttZoom.Week, GanttZoom.Month]) {
        @Assert(snapKey("2026-03-08T23:45:12.000Z", zoom), "2026-03-08")
        @Assert(snapKey("2026-03-08", zoom), "2026-03-08")
    }
}

@Test
func snapKeyIsIdempotent() {
    @Assert(snapKey("2026-10-20", GanttZoom.Week), "2026-10-20")
    @Assert(snapKey(snapKey("2026-10-20", GanttZoom.Day), GanttZoom.Month), "2026-10-20")
}

@Test
func resizeBarStartEdgeKeepsOrder() {
    let bar = BarRange("2026-06-10", "2026-06-14")
    @Assert(resizeBar(bar, BarEdge.Start, 2.0), BarRange("2026-06-12", "2026-06-14"))
    @Assert(resizeBar(bar, BarEdge.Start, 3.0), BarRange("2026-06-13", "2026-06-14"))
    @Assert(resizeBar(bar, BarEdge.Start, 10.0), BarRange("2026-06-14", "2026-06-14"))
}

@Test
func resizeBarEndEdgeKeepsOrder() {
    let bar = BarRange("2026-06-10", "2026-06-14")
    @Assert(resizeBar(bar, BarEdge.End, -2.0), BarRange("2026-06-10", "2026-06-12"))
    @Assert(resizeBar(bar, BarEdge.End, -10.0), BarRange("2026-06-10", "2026-06-10"))
}

@Test
func resizeBarRoundsHalfTowardsPositiveInfinity() {
    let bar = BarRange("2026-06-10", "2026-06-14")
    @Assert(resizeBar(bar, BarEdge.Start, -2.4), BarRange("2026-06-08", "2026-06-14"))
    @Assert(resizeBar(bar, BarEdge.End, 1.6), BarRange("2026-06-10", "2026-06-16"))
}

@Test
func resizeBarCrossesMonthAndYear() {
    let crossing = BarRange("2025-12-31", "2026-01-02")
    @Assert(resizeBar(crossing, BarEdge.End, 1.0), BarRange("2025-12-31", "2026-01-03"))
    @Assert(resizeBar(crossing, BarEdge.Start, 2.0), BarRange("2026-01-02", "2026-01-02"))
}

@Test
func itemRangeFillsMissingEnd() {
    let onlyStart = makeItem(
        "a",
        "A",
        GanttKind.Action,
        startDate: Some("2026-06-10"),
        endDate: None,
        progress: Some(0.0)
    )
    @Assert(itemRange(onlyStart), Some(BarRange("2026-06-10", "2026-06-10")))
    let onlyEnd = makeItem(
        "b",
        "B",
        GanttKind.Action,
        startDate: None,
        endDate: Some("2026-06-12"),
        progress: Some(0.0)
    )
    @Assert(itemRange(onlyEnd), Some(BarRange("2026-06-12", "2026-06-12")))
    let geometry = barGeometry(itemRange(onlyStart).getOrThrow(), "2026-06-01", 40.0)
    @Assert(geometry.x, 9.0 * 40.0)
    @Assert(geometry.width, 40.0)
    @Assert(geometry.days, 1)
}

@Test
func itemRangeHandlesEmptyAndReversed() {
    let empty = makeItem("a", "A", GanttKind.Action, progress: Some(0.0))
    @Assert(itemRange(empty).isNone(), true)
    let reversed = makeItem(
        "b",
        "B",
        GanttKind.Action,
        startDate: Some("2026-06-14"),
        endDate: Some("2026-06-10"),
        progress: Some(0.0)
    )
    @Assert(itemRange(reversed), Some(BarRange("2026-06-10", "2026-06-14")))
}

@Test
func moveBarKeepsSpan() {
    @Assert(moveBar(BarRange("2026-06-10", "2026-06-14"), 3.0), BarRange("2026-06-13", "2026-06-17"))
    @Assert(moveBar(BarRange("2026-01-01", "2026-01-01"), -1.0), BarRange("2025-12-31", "2025-12-31"))
}

@Test
func displayProgressIsAlwaysFullForDoneItems() {
    let doneWithZero = makeItem(
        "done",
        "已完成",
        GanttKind.Action,
        startDate: Some("2026-06-01"),
        endDate: Some("2026-06-02"),
        progress: Some(0.0),
        status: GanttStatus.Done
    )
    @Assert(displayProgress(doneWithZero), 100)

    let doneWithoutGantt = makeItem("done-2", "已完成但未排期", GanttKind.Action, status: GanttStatus.Done)
    @Assert(displayProgress(doneWithoutGantt), 100)

    let doneWithPartial = makeItem(
        "done-3",
        "完成前进度 37",
        GanttKind.Action,
        progress: Some(37.0),
        status: GanttStatus.Done
    )
    @Assert(displayProgress(doneWithPartial), 100)
}

@Test
func displayProgressRoundsOngoingProgress() {
    let item = makeItem(
        "a",
        "进行中",
        GanttKind.Action,
        startDate: Some("2026-06-01"),
        endDate: Some("2026-06-02"),
        progress: Some(42.6),
        status: GanttStatus.Active
    )
    @Assert(displayProgress(item), 43)

    let low: GanttRow = makeItem(
        "b",
        "低进度",
        GanttKind.Action,
        progress: Some(42.4),
        status: GanttStatus.Next
    )
    @Assert(displayProgress(low), 42)
}

@Test
func displayProgressFallsBackToZero() {
    @Assert(displayProgress(makeItem("no-gantt", "无排期", GanttKind.Action)), 0)
    let missing = makeItem(
        "missing",
        "缺进度",
        GanttKind.Action,
        startDate: Some("2026-06-01"),
        endDate: Some("2026-06-02"),
        progress: Some(0.0)
    )
    @Assert(displayProgress(missing), 0)

    let notANumber = makeItem(
        "nan",
        "NaN",
        GanttKind.Action,
        progress: Some(Float64.NaN)
    )
    @Assert(displayProgress(notANumber), 0)
}

@Test
func displayProgressClampsWithoutMutating() {
    let over = makeItem(
        "over",
        "超范围",
        GanttKind.Action,
        startDate: Some("2026-06-01"),
        endDate: Some("2026-06-02"),
        progress: Some(150.0),
        status: GanttStatus.Active
    )
    @Assert(displayProgress(over), 100)

    let under = makeItem(
        "under",
        "负进度",
        GanttKind.Action,
        startDate: Some("2026-06-01"),
        endDate: Some("2026-06-02"),
        progress: Some(-20.0),
        status: GanttStatus.Active
    )
    @Assert(displayProgress(under), 0)
    @Assert(under.progress, Some(-20.0))
}

@Test
func visibleRangeClampsToTotalRange() {
    let range = DateRange("2026-06-01", "2026-06-30")
    @Assert(visibleRange(range, 0.0, 400.0, 40.0), DateRange("2026-06-01", "2026-06-10"))
    @Assert(visibleRange(range, -100.0, 200.0, 40.0), DateRange("2026-06-01", "2026-06-03"))
    @Assert(visibleRange(range, 1200.0, 400.0, 40.0), DateRange("2026-06-30", "2026-06-30"))
}

@Test
func formatRangeLabelStaysReadableAcrossYears() {
    @Assert(formatRangeLabel("2026-10-20", "2026-11-16"), "10月 20 – 11月 16")
    @Assert(formatRangeLabel("2025-12-29", "2026-01-11"), "2025年12月 29 – 2026年1月 11")
}
