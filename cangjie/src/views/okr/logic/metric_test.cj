package textura.views.okr.logic

import std.unittest.*
import std.unittest.testmacro.*

/*
 * 对齐 `src/modules/okr/okrMath.test.ts` 的 `metricPercent` /
 * `metricProgress / hasMetricRange` 两组断言，并补充 0 目标、负目标、
 * NaN 保护、超 100%、current 越界等边界。
 */

@Test
func metricPercentConvertsLinearly() {
    @Assert(metricPercent(OkrMetric(42.0, 60.0, 47.0, unit: "分")).getOrThrow(), 28.0)
    @Assert(metricPercent(OkrMetric(2.1, 3.0, 2.35, unit: "%")).getOrThrow(), 28.0)
    @Assert(metricPercent(OkrMetric(0.0, 100.0, 50.0, unit: "%")).getOrThrow(), 50.0)
}

@Test
func metricPercentClampsOvershootAndUndershoot() {
    @Assert(metricPercent(OkrMetric(42.0, 60.0, 70.0, unit: "分")).getOrThrow(), 100.0)
    @Assert(metricPercent(OkrMetric(42.0, 60.0, 30.0, unit: "分")).getOrThrow(), 0.0)
    // 略微越界也要夹紧
    @Assert(metricPercent(OkrMetric(0.0, 100.0, 100.4)).getOrThrow(), 100.0)
    @Assert(metricPercent(OkrMetric(0.0, 100.0, -0.1)).getOrThrow(), 0.0)
}

@Test
func metricPercentReturnsNoneWithoutConvertibleRange() {
    @Assert(metricPercent(OkrMetric(5.0, 5.0, 5.0)).isNone(), true)
    @Assert(metricPercent(None).isNone(), true)
    @Assert(metricPercent(OkrMetric(Float64.NaN, 10.0, 5.0)).isNone(), true)
    // 0 目标 + 0 起点：无法换算
    @Assert(metricPercent(OkrMetric(0.0, 0.0, 0.0)).isNone(), true)
}

@Test
func metricPercentSupportsNegativeMetrics() {
    // target < start（负增长目标）
    @Assert(metricPercent(OkrMetric(5.0, 2.0, 3.5, unit: "%")).getOrThrow(), 50.0)
    @Assert(metricPercent(OkrMetric(5.0, 2.0, 10.0, unit: "%")).getOrThrow(), 0.0)
    @Assert(metricPercent(OkrMetric(5.0, 2.0, 1.0, unit: "%")).getOrThrow(), 100.0)
}

@Test
func metricProgressMarksFlatRange() {
    let info = metricProgress(OkrMetric(5.0, 5.0, 5.0))
    @Assert(metricProgressStateText(info.state), "flat")
    @Assert(info.percent.isNone(), true)
    @Assert(info.clamped, false)
    @Assert(hasMetricRange(OkrMetric(5.0, 5.0, 5.0)), false)
}

@Test
func metricProgressTreatsSubEpsilonRangeAsFlat() {
    @Assert(hasMetricRange(OkrMetric(5.0, 5.0 + 5e-10, 5.0)), false)
    @Assert(hasMetricRange(OkrMetric(5.0, 5.0 + 1e-6, 5.0)), true)
    @Assert(metricProgressStateText(metricProgress(OkrMetric(5.0, 5.0 + 5e-10, 5.0)).state), "flat")
}

@Test
func metricProgressMarksOvershootAndUndershoot() {
    let over = metricProgress(OkrMetric(42.0, 60.0, 70.0, unit: "分"))
    @Assert(metricProgressStateText(over.state), "over")
    @Assert(over.percent.getOrThrow(), 100.0)
    @Assert(over.clamped, true)

    let under = metricProgress(OkrMetric(42.0, 60.0, 30.0, unit: "分"))
    @Assert(metricProgressStateText(under.state), "under")
    @Assert(under.percent.getOrThrow(), 0.0)
    @Assert(under.clamped, true)

    let atTarget = metricProgress(OkrMetric(42.0, 60.0, 60.0, unit: "分"))
    @Assert(metricProgressStateText(atTarget.state), "in-range")
    @Assert(atTarget.percent.getOrThrow(), 100.0)
    @Assert(atTarget.clamped, false)

    let atStart = metricProgress(OkrMetric(42.0, 60.0, 42.0, unit: "分"))
    @Assert(metricProgressStateText(atStart.state), "in-range")
    @Assert(atStart.percent.getOrThrow(), 0.0)
    @Assert(atStart.clamped, false)
}

@Test
func metricProgressIsDirectionAwareForNegativeMetrics() {
    let inRange = metricProgress(OkrMetric(5.0, 2.0, 3.5, unit: "%"))
    @Assert(metricProgressStateText(inRange.state), "in-range")
    @Assert(inRange.percent.getOrThrow(), 50.0)
    @Assert(inRange.clamped, false)

    // 负向指标：current 低于 target 才算越过目标
    let over = metricProgress(OkrMetric(5.0, 2.0, 1.0, unit: "%"))
    @Assert(metricProgressStateText(over.state), "over")
    @Assert(over.percent.getOrThrow(), 100.0)
    @Assert(over.clamped, true)

    // 负向指标：current 高于 start 属于低于起点
    let under = metricProgress(OkrMetric(5.0, 2.0, 10.0, unit: "%"))
    @Assert(metricProgressStateText(under.state), "under")
    @Assert(under.percent.getOrThrow(), 0.0)
    @Assert(under.clamped, true)
}

@Test
func metricProgressDistinguishesUnsetAndInvalid() {
    let unset = metricProgress(None)
    @Assert(metricProgressStateText(unset.state), "unset")
    @Assert(unset.percent.isNone(), true)
    @Assert(unset.clamped, false)

    let invalid = metricProgress(OkrMetric(Float64.NaN, 10.0, 5.0))
    @Assert(metricProgressStateText(invalid.state), "invalid")
    @Assert(invalid.percent.isNone(), true)
    @Assert(invalid.clamped, false)

    // current 非有限同样算 invalid
    @Assert(
        metricProgressStateText(metricProgress(OkrMetric(0.0, 100.0, TEST_INF)).state),
        "invalid"
    )
    // start/target 有限时 hasMetricRange 只看区间，不看 current
    @Assert(hasMetricRange(OkrMetric(0.0, 100.0, Float64.NaN)), true)
}

@Test
func metricProgressRoundsToWholePercent() {
    // 1/3 -> 33.333 -> 33
    @Assert(metricProgress(OkrMetric(0.0, 3.0, 1.0)).percent.getOrThrow(), 33.0)
    // 2/3 -> 66.666 -> 67
    @Assert(metricProgress(OkrMetric(0.0, 3.0, 2.0)).percent.getOrThrow(), 67.0)
    // 起始为负的区间
    @Assert(metricProgress(OkrMetric(-10.0, 10.0, 0.0)).percent.getOrThrow(), 50.0)
    // 目标大于 100 的正常区间
    @Assert(metricProgress(OkrMetric(0.0, 150.0, 1.0)).percent.getOrThrow(), 1.0)
}
