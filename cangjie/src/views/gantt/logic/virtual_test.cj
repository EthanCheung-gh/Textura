package textura.views.gantt.logic

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * 逐条移植 Web 版 `src/modules/gantt/virtual.test.ts`，并补充 0 宽视口与 10k 行窗口。
 */
func uniformWidths(): Array<Float64> {
    let widths = ArrayList<Float64>()
    for (_ in 0..10) {
        widths.add(10.0)
    }
    widths.toArray()
}

@Test
func visibleRowsPadsTopWindowAndClampsAtZero() {
    @Assert(visibleRows(0.0, 100.0, 36.0, 10.0, total: Some(1000)), WindowRange(0, 13))
    @Assert(visibleRows(-50.0, 72.0, 36.0, 2.0, total: Some(1000)), WindowRange(0, 4))
}

@Test
func visibleRowsCoversMiddleWindowWithBuffer() {
    let window = visibleRows(360.0, 100.0, 36.0, 10.0, total: Some(1000))
    @Assert(window, WindowRange(0, 23))
    @Assert(Float64(window.start) * 36.0 <= 360.0, true)
    @Assert(Float64(window.end) * 36.0 >= 360.0 + 100.0, true)
}

@Test
func visibleRowsCoversLastRowWhenHeightDoesNotDivide() {
    let window = visibleRows(10.0, 100.0, 36.0, 0.0, total: Some(1000))
    @Assert(window, WindowRange(0, 4))
    @Assert(Float64(window.end) * 36.0 >= 10.0 + 100.0, true)
}

@Test
func visibleRowsStopsAtTotalCount() {
    @Assert(visibleRows(3600.0, 100.0, 36.0, 10.0, total: Some(100)), WindowRange(90, 100))
    @Assert(visibleRows(999999.0, 100.0, 36.0, 10.0, total: Some(100)), WindowRange(100, 100))
}

@Test
func visibleRowsHandlesEmptyListAndZeroHeight() {
    @Assert(visibleRows(0.0, 100.0, 36.0, 10.0, total: Some(0)), WindowRange(0, 0))
    @Assert(visibleRows(36.0, 0.0, 36.0, 0.0, total: Some(100)), WindowRange(1, 1))
}

@Test
func visibleRowsBufferZeroStaysBounded() {
    let window = visibleRows(50.0, 72.0, 36.0, 0.0, total: Some(100))
    @Assert(window, WindowRange(1, 4))
    @Assert(window.end - window.start <= 2 + 1, true)
}

@Test
func visibleColumnsWalksCumulativeWidths() {
    let window = visibleColumns(25.0, 30.0, uniformWidths(), 2.0)
    @Assert(window, WindowRange(0, 8))
    @Assert(window.start <= 2, true)
    @Assert(window.end >= 6, true)
    @Assert(window.start < window.end, true)
}

@Test
func visibleColumnsIncludesOnlyIntersectingColumnsOnBoundary() {
    @Assert(visibleColumns(20.0, 20.0, uniformWidths(), 0.0), WindowRange(2, 4))
    @Assert(visibleColumns(0.0, 10.0, uniformWidths(), 0.0), WindowRange(0, 1))
}

@Test
func visibleColumnsSupportsVariableWidths() {
    let widths: Array<Float64> = [10.0, 100.0, 10.0, 10.0]
    @Assert(visibleColumns(20.0, 50.0, widths, 0.0), WindowRange(1, 2))
    @Assert(visibleColumns(20.0, 50.0, widths, 1.0), WindowRange(0, 3))
}

@Test
func visibleColumnsHandlesEmptyListAndPastEnd() {
    @Assert(visibleColumns(0.0, 100.0, Array<Float64>(), 2.0), WindowRange(0, 0))
    @Assert(visibleColumns(90.0, 100.0, uniformWidths(), 2.0), WindowRange(7, 10))
}

@Test
func visibleColumnsWindowIsBoundedAndCoversVisibleColumns() {
    let widths: Array<Float64> = [40.0, 70.0, 30.0, 50.0, 20.0, 60.0, 40.0]
    let scrollLeft = 50.0
    let viewportW = 100.0
    let buffer = 2.0
    let window = visibleColumns(scrollLeft, viewportW, widths, buffer)
    @Assert(window.start < window.end, true)

    var firstVisible: Int64 = -1
    var lastVisibleExclusive: Int64 = 0
    var offset = 0.0
    for (index in 0..widths.size) {
        let next = offset + widths[index]
        if (firstVisible < 0 && next > scrollLeft) {
            firstVisible = index
        }
        if (offset < scrollLeft + viewportW) {
            lastVisibleExclusive = index + 1
        }
        offset = next
    }
    @Assert(window.start <= firstVisible, true)
    @Assert(window.end >= lastVisibleExclusive, true)
    @Assert(window.end - window.start <= lastVisibleExclusive - firstVisible + 2 * 2, true)
}

/* ------------------------------------------------------------------ *
 * 补充：0 宽视口 / 10k 行
 * ------------------------------------------------------------------ */
@Test
func zeroViewportRowsKeepAtLeastTheAnchorRow() {
    // 视口高度为 0：窗口退化为 “首个可见行 + buffer”，不会退化成空窗口。
    @Assert(visibleRows(36.0, 0.0, 36.0, 0.0, total: Some(100)), WindowRange(1, 1))
    @Assert(visibleRows(36.0, 0.0, 36.0, 4.0, total: Some(100)), WindowRange(0, 5))
    @Assert(visibleRows(0.0, 0.0, 36.0, 0.0, total: Some(100)), WindowRange(0, 0))
}

@Test
func zeroViewportColumnsFallBackToBufferOnly() {
    let widths: Array<Float64> = [10.0, 10.0, 10.0]
    @Assert(visibleColumns(0.0, 0.0, widths, 0.0), WindowRange(0, 0))
    @Assert(visibleColumns(10.0, 0.0, widths, 2.0), WindowRange(0, 3))
    @Assert(visibleColumns(20.0, 0.0, widths, 1.0), WindowRange(1, 3))
}

@Test
func tenThousandRowsStayBounded() {
    let viewport = 900.0 - HEADER_HEIGHT
    let top = visibleRows(0.0, viewport, ROW_HEIGHT, 4.0, total: Some(10000))
    @Assert(top, WindowRange(0, 28))

    let middle = visibleRows(36000.0, viewport, ROW_HEIGHT, 4.0, total: Some(10000))
    @Assert(middle, WindowRange(996, 1028))

    let bottom = visibleRows(359999.0, viewport, ROW_HEIGHT, 4.0, total: Some(10000))
    @Assert(bottom, WindowRange(9995, 10000))

    let past = visibleRows(999999.0, viewport, ROW_HEIGHT, 4.0, total: Some(10000))
    @Assert(past, WindowRange(10000, 10000))

    // 窗口与总行数无关：任何滚动位置的窗口跨度都不超过可视行数 + 2*buffer。
    let maxSpan = tsCeilInt(viewport / ROW_HEIGHT) + 8
    for (offset in [0.0, 1234.5, 18000.0, 359999.0]) {
        let window = visibleRows(offset, viewport, ROW_HEIGHT, 4.0, total: Some(10000))
        @Assert(window.end - window.start <= maxSpan, true)
        @Assert(window.start >= 0 && window.end <= 10000, true)
    }
}

@Test
func rowWindowExposesCanvasOffset() {
    let window = rowWindow(360.0, 100.0, 36.0, 10.0, total: Some(1000))
    @Assert(window.first, 0)
    @Assert(window.last, 23)
    @Assert(window.offsetY, 0.0)

    let scrolled = rowWindow(3600.0, 100.0, 36.0, 0.0, total: Some(1000))
    @Assert(scrolled.first, 100)
    @Assert(scrolled.offsetY, 100.0 * 36.0)
}

@Test
func visibleRowsTreatsUnknownTotalAsUnbounded() {
    @Assert(visibleRows(3600.0, 100.0, 36.0, 0.0), WindowRange(100, 103))
}
