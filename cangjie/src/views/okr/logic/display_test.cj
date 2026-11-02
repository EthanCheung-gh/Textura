package textura.views.okr.logic

import std.unittest.*
import std.unittest.testmacro.*

/*
 * 展示映射的逐条断言；期望值全部来自 `okrDisplay.ts` 在 node 下的实际输出
 * （`formatNumber` / `unitSuffix` / `formatMetric` / `formatSchedule` / 两个 tone 映射）。
 */

@Test
func statusToneMapsEveryStatus() {
    @Assert(badgeToneText(statusTone(OkrItemStatus.Inbox)), "neutral")
    @Assert(badgeToneText(statusTone(OkrItemStatus.Next)), "info")
    @Assert(badgeToneText(statusTone(OkrItemStatus.Active)), "accent")
    @Assert(badgeToneText(statusTone(OkrItemStatus.Waiting)), "warn")
    @Assert(badgeToneText(statusTone(OkrItemStatus.Scheduled)), "info")
    @Assert(badgeToneText(statusTone(OkrItemStatus.Someday)), "neutral")
    @Assert(badgeToneText(statusTone(OkrItemStatus.Done)), "ok")
    @Assert(badgeToneText(statusTone(OkrItemStatus.Dropped)), "neutral")
}

@Test
func progressTonePriorities() {
    @Assert(progressToneText(progressTone(0.0, true)), "danger")
    @Assert(progressToneText(progressTone(100.0, false)), "ok")
    @Assert(progressToneText(progressTone(0.0, false)), "info")
    @Assert(progressToneText(progressTone(50.0, false)), "accent")
    @Assert(progressToneText(progressTone(120.0, false)), "ok")
    @Assert(progressToneText(progressTone(-5.0, false)), "info")
    // behind 优先于一切
    @Assert(progressToneText(progressTone(100.0, true)), "danger")
}

@Test
func formatNumberMatchesJsRendering() {
    @Assert(formatNumber(42.0), "42")
    @Assert(formatNumber(2.1), "2.1")
    @Assert(formatNumber(2.345), "2.35")
    @Assert(formatNumber(0.125), "0.13")
    @Assert(formatNumber(2.5), "2.5")
    @Assert(formatNumber(-0.001), "0")
    @Assert(formatNumber(Float64.NaN), "—")
    @Assert(formatNumber(TEST_INF), "—")
    @Assert(formatNumber(1234.5678), "1234.57")
    @Assert(formatNumber(1e21), "1e+21")
    @Assert(formatNumber(1e-7), "0")
    @Assert(formatNumber(-0.0), "0")
    @Assert(formatNumber(-12.345), "-12.35")
}

@Test
func jsNumberToStringMatchesJsShortestRoundTrip() {
    @Assert(jsNumberToString(42.0), "42")
    @Assert(jsNumberToString(2.1), "2.1")
    @Assert(jsNumberToString(-0.0), "0")
    @Assert(jsNumberToString(1.0 / 3.0), "0.3333333333333333")
    @Assert(jsNumberToString(0.1 + 0.2), "0.30000000000000004")
    @Assert(jsNumberToString(1e21), "1e+21")
    @Assert(jsNumberToString(1e20), "100000000000000000000")
    @Assert(jsNumberToString(1e-7), "1e-7")
    @Assert(jsNumberToString(0.000001), "0.000001")
    @Assert(jsNumberToString(123456789012345678.0), "123456789012345680")
    @Assert(jsNumberToString(-1.5), "-1.5")
    @Assert(jsNumberToString(1.0 / 0.0), "Infinity")
    @Assert(jsNumberToString(Float64.NaN), "NaN")
}

@Test
func jsNumberToStringMatchesJsOnHardFloats() {
    // 最短有效数字规则：长整数、指数阈值、次正规数
    @Assert(jsNumberToString(7.0 / 3.0), "2.3333333333333335")
    @Assert(formatNumber(7.0 / 3.0), "2.33")
    @Assert(jsNumberToString(2.9612295934930442e18), "2961229593493044000")
    @Assert(jsNumberToString(1234567890123456789.0), "1234567890123456800")
    @Assert(jsNumberToString(1.5e21), "1.5e+21")
    @Assert(formatNumber(1.5e21), "1.5e+21")
    @Assert(jsNumberToString(1e308), "1e+308")
    @Assert(formatNumber(1e308), "1e+308")
    @Assert(jsNumberToString(5e-324), "5e-324")
    @Assert(jsNumberToString(1e-320), "1e-320")
    @Assert(formatNumber(1e-320), "0")
    @Assert(jsNumberToString(0.1), "0.1")
}

@Test
func unitSuffixFollowsUnitShape() {
    @Assert(unitSuffix("%"), "%")
    @Assert(unitSuffix("分"), " 分")
    @Assert(unitSuffix(""), "")
    @Assert(unitSuffix("ms"), " ms")
}

@Test
func formatMetricRendersStartAndTarget() {
    @Assert(formatMetric(None), "未设指标")
    @Assert(formatMetric(OkrMetric(2.1, 3.0, 2.35, unit: "%")), "2.1 → 3%")
    @Assert(formatMetric(OkrMetric(42.0, 60.0, 47.0, unit: "分")), "42 → 60 分")
    @Assert(formatMetric(OkrMetric(0.0, 100.0, 20.0, unit: "")), "0 → 100")
}

@Test
func formatScheduleRendersDateKeys() {
    @Assert(formatSchedule(None), "未排期")
    @Assert(formatSchedule(OkrSchedule()), "未排期")
    @Assert(
        formatSchedule(OkrSchedule(start: Some("2026-02-01T00:00:00.000Z"), end: Some("2026-03-15"))),
        "02/01 – 03/15"
    )
    @Assert(formatSchedule(OkrSchedule(start: Some("2026-02-01"))), "02/01 – —")
    @Assert(formatSchedule(OkrSchedule(end: Some("2026-03-15"))), "— – 03/15")
    // JS 真值语义：空串等同缺失
    @Assert(formatSchedule(OkrSchedule(start: Some(""), end: Some(""))), "未排期")
    // 非法日期键显示破折号
    @Assert(formatSchedule(OkrSchedule(start: Some("x"), end: Some("2026-03-15"))), "— – 03/15")
    @Assert(formatSchedule(OkrSchedule(start: Some("2026-02-30"), end: Some("2026-03-15"))), "— – 03/15")
}

@Test
func formatDateKeyMmDdHandlesEdges() {
    @Assert(formatDateKeyMmDd(None), "—")
    @Assert(formatDateKeyMmDd(Some("")), "—")
    @Assert(formatDateKeyMmDd(Some("2026-02-01")), "02/01")
    @Assert(formatDateKeyMmDd(Some("2026-12-09T10:00:00+08:00")), "12/09")
    @Assert(formatDateKeyMmDd(Some("2026-2-1")), "—")
}
