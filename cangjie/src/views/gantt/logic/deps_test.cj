package textura.views.gantt.logic

import std.unittest.*
import std.unittest.testmacro.*

/**
 * 依赖折线几何。期望值是 TS `GanttDependencies.dependencyPath` 在同一组输入下的
 * 路径点（`M/L` 序列），逐点比对。
 */
@Test
func dependencyPathRoutesThroughHalfGapChannel() {
    // dependent 在前置右侧且留出 ≥8px 空隙：走 startX + gap/2 的竖直通道。
    let points = dependencyPath(
        DepRect(300.0, 400.0, 100.0),
        DepRect(100.0, 200.0, 40.0),
        Array<DepRect>(),
        1200.0
    )
    @Assert(
        points,
        [
            Point(200.0, 40.0),
            Point(250.0, 40.0),
            Point(250.0, 100.0),
            Point(300.0, 100.0)
        ]
    )
}

@Test
func dependencyPathConnectsAdjacentBarsVertically() {
    let points = dependencyPath(
        DepRect(200.0, 300.0, 100.0),
        DepRect(100.0, 200.0, 40.0),
        Array<DepRect>(),
        1200.0
    )
    @Assert(points, [Point(200.0, 40.0), Point(200.0, 100.0)])
}

@Test
func dependencyPathDetoursWhenPrerequisiteIsRightOfDependent() {
    // 依赖方起点在前置终点左侧（gap < 0）：绕行到 gutter。
    let points = dependencyPath(
        DepRect(120.0, 220.0, 100.0),
        DepRect(100.0, 200.0, 40.0),
        Array<DepRect>(),
        1200.0
    )
    @Assert(
        points,
        [
            Point(200.0, 40.0),
            Point(200.0, 58.0),
            Point(112.0, 58.0),
            Point(112.0, 82.0),
            Point(120.0, 82.0),
            Point(120.0, 100.0)
        ]
    )
}

@Test
func dependencyPathAvoidsBlockingBar() {
    // 中间行有任务条挡住中点通道 → 退到 startX + 6。
    let points = dependencyPath(
        DepRect(300.0, 400.0, 180.0),
        DepRect(100.0, 200.0, 40.0),
        [DepRect(230.0, 330.0, 100.0)],
        1200.0
    )
    @Assert(
        points,
        [
            Point(200.0, 40.0),
            Point(206.0, 40.0),
            Point(206.0, 180.0),
            Point(300.0, 180.0)
        ]
    )
}

@Test
func dependencyPathSupportsUpwardLinks() {
    let points = dependencyPath(
        DepRect(300.0, 400.0, 40.0),
        DepRect(100.0, 200.0, 140.0),
        Array<DepRect>(),
        1200.0
    )
    @Assert(
        points,
        [
            Point(200.0, 140.0),
            Point(250.0, 140.0),
            Point(250.0, 40.0),
            Point(300.0, 40.0)
        ]
    )
}

@Test
func dependencyPathKeepsChannelInsideWidth() {
    let points = dependencyPath(
        DepRect(1000.0, 1100.0, 100.0),
        DepRect(700.0, 800.0, 40.0),
        Array<DepRect>(),
        900.0
    )
    @Assert(
        points,
        [
            Point(800.0, 40.0),
            Point(900.0, 40.0),
            Point(900.0, 100.0),
            Point(1000.0, 100.0)
        ]
    )
}

@Test
func dependencyPathUsesBlockerEdgesAsChannels() {
    // 三个常规候选全被挡：改用中间条边缘 ±10 的通道（196 = 206 - 10）。
    let points = dependencyPath(
        DepRect(300.0, 400.0, 180.0),
        DepRect(100.0, 200.0, 40.0),
        [DepRect(206.0, 294.0, 100.0)],
        1200.0
    )
    @Assert(
        points,
        [
            Point(200.0, 40.0),
            Point(200.0, 58.0),
            Point(196.0, 58.0),
            Point(196.0, 162.0),
            Point(300.0, 162.0),
            Point(300.0, 180.0)
        ]
    )
}

@Test
func dependencyPathFallsBackToFixedChannel() {
    // 视口过窄（30px）时所有候选都不合法 → 退化到 max(4, endX - 8)。
    let points = dependencyPath(
        DepRect(10.0, 110.0, 100.0),
        DepRect(100.0, 200.0, 40.0),
        Array<DepRect>(),
        30.0
    )
    @Assert(
        points,
        [
            Point(200.0, 40.0),
            Point(200.0, 58.0),
            Point(4.0, 58.0),
            Point(4.0, 82.0),
            Point(10.0, 82.0),
            Point(10.0, 100.0)
        ]
    )
}

@Test
func dependencyPathIgnoresSameRowBlockers() {
    // 与两端同行的条不属于「中间行」，不会触发绕行（与 TS 的 betweenRows 一致）。
    let points = dependencyPath(
        DepRect(300.0, 400.0, 40.0),
        DepRect(100.0, 200.0, 40.0),
        [DepRect(220.0, 260.0, 40.0)],
        1200.0
    )
    @Assert(
        points,
        [
            Point(200.0, 40.0),
            Point(250.0, 40.0),
            Point(250.0, 40.0),
            Point(300.0, 40.0)
        ]
    )
}

@Test
func depRectMatchesBarGeometry() {
    let geometry = barGeometry(BarRange("2026-06-10", "2026-06-14"), "2026-06-10", 40.0)
    let rect = depRect(geometry, 1)
    @Assert(rect.x1, 0.0)
    @Assert(rect.x2, 200.0)
    @Assert(rect.cy, ROW_HEIGHT + ROW_HEIGHT / 2.0)
}

@Test
func barRectMatchesRendererContract() {
    let geometry = barGeometry(BarRange("2026-06-10", "2026-06-14"), "2026-06-10", 40.0)
    @Assert(barRect(geometry, 0), BarRect(0.0, BAR_TOP_OFFSET, 200.0, BAR_HEIGHT))
    @Assert(barRect(geometry, 2), BarRect(0.0, 2.0 * ROW_HEIGHT + BAR_TOP_OFFSET, 200.0, BAR_HEIGHT))
    // 里程碑固定 16 宽，位置与普通条一致。
    @Assert(barRect(geometry, 0, milestone: true).w, MILESTONE_WIDTH)
    @Assert(barRect(geometry, 0, milestone: true).x, 0.0)
}
