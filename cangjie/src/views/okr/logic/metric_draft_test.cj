package textura.views.okr.logic

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

/*
 * 对齐 `src/modules/okr/metricDraft.test.ts` 的 6 条断言，并补充解析/归一化边界。
 */

private let BASE = OkrMetric(42.0, 60.0, 47.0, unit: "分")

private func updates(): ArrayList<OkrMetric> {
    ArrayList<OkrMetric>()
}

@Test
func flushPendingFieldExactlyOnce() {
    let lastCommitted = metricToDraft(BASE)
    let draft = MetricDraft(
        start: lastCommitted.start,
        current: "60",
        target: lastCommitted.target,
        unit: lastCommitted.unit
    )
    let called = updates()
    let decision = flushMetricDrafts(Some(BASE), draft, lastCommitted, {metric => called.add(metric)})
    @Assert(called.size, 1)
    @Assert(called[0], OkrMetric(42.0, 60.0, 60.0, unit: "分"))
    @Assert(joinedFields(decision.getOrThrow().fields), "[[current]]")
    @Assert(decision.getOrThrow().normalized.current, "60")
}

@Test
func flushMergesMultipleFieldsIntoOneUpdate() {
    let lastCommitted = metricToDraft(BASE)
    let draft = MetricDraft(start: "40.0", current: "65", target: "80", unit: " % ")
    let called = updates()
    let decision = flushMetricDrafts(Some(BASE), draft, lastCommitted, {metric => called.add(metric)})
    @Assert(called.size, 1)
    @Assert(called[0], OkrMetric(40.0, 80.0, 65.0, unit: "%"))
    @Assert(joinedFields(decision.getOrThrow().fields), "[[start,current,target,unit]]")
    @Assert(
        decision.getOrThrow().normalized,
        MetricDraft(start: "40", current: "65", target: "80", unit: "%")
    )
}

@Test
func flushIgnoresEmptyAndInvalidNumbers() {
    let lastCommitted = metricToDraft(BASE)
    let invalidOnly = MetricDraft(
        start: "",
        current: "abc",
        target: "",
        unit: lastCommitted.unit
    )
    let notCalled = updates()
    @Assert(
        flushMetricDrafts(Some(BASE), invalidOnly, lastCommitted, {metric => notCalled.add(metric)})
            .isNone(),
        true
    )
    @Assert(notCalled.size, 0)

    let mixed = MetricDraft(
        start: lastCommitted.start,
        current: "70",
        target: "",
        unit: lastCommitted.unit
    )
    let called = updates()
    let decision = flushMetricDrafts(Some(BASE), mixed, lastCommitted, {metric => called.add(metric)})
    @Assert(called.size, 1)
    @Assert(called[0], OkrMetric(42.0, 60.0, 70.0, unit: "分"))
    @Assert(joinedFields(decision.getOrThrow().fields), "[[current]]")
}

@Test
func flushDoesNotOverwriteExternalStoreChange() {
    // lastCommitted 已经追平草稿 -> 草稿是陈旧的，不能再写一次
    let draft = MetricDraft(start: "42", current: "50", target: "60", unit: "分")
    let lastCommitted = MetricDraft(start: "42", current: "50", target: "60", unit: "分")
    @Assert(pendingMetricPatch(Some(BASE), draft, lastCommitted).isNone(), true)
    let notCalled = updates()
    @Assert(
        flushMetricDrafts(Some(BASE), draft, lastCommitted, {metric => notCalled.add(metric)}).isNone(),
        true
    )
    @Assert(notCalled.size, 0)
}

@Test
func flushAllowsClearingUnitAndSkipsUnchanged() {
    let lastCommitted = metricToDraft(BASE)
    let cleared = MetricDraft(
        start: lastCommitted.start,
        current: lastCommitted.current,
        target: lastCommitted.target,
        unit: "  "
    )
    let called = updates()
    let decision = flushMetricDrafts(Some(BASE), cleared, lastCommitted, {metric => called.add(metric)})
    @Assert(called.size, 1)
    @Assert(called[0], OkrMetric(42.0, 60.0, 47.0, unit: ""))
    @Assert(joinedFields(decision.getOrThrow().fields), "[[unit]]")

    let same = MetricDraft(
        start: lastCommitted.start,
        current: lastCommitted.current,
        target: lastCommitted.target,
        unit: "分"
    )
    let notCalled = updates()
    flushMetricDrafts(Some(BASE), same, lastCommitted, {metric => notCalled.add(metric)})
    @Assert(notCalled.size, 0)
}

@Test
func flushAcceptsFlatRangeTargetEdit() {
    let lastCommitted = metricToDraft(BASE)
    let draft = MetricDraft(
        start: lastCommitted.start,
        current: lastCommitted.current,
        target: "42",
        unit: lastCommitted.unit
    )
    let called = updates()
    let decision = flushMetricDrafts(Some(BASE), draft, lastCommitted, {metric => called.add(metric)})
    @Assert(called.size, 1)
    @Assert(called[0], OkrMetric(42.0, 42.0, 47.0, unit: "分"))
    @Assert(joinedFields(decision.getOrThrow().fields), "[[target]]")
}

@Test
func pendingPatchWithoutStoredMetricFallsBackToEmptyMetric() {
    let empty = MetricDraft()
    let decision = pendingMetricPatch(None, MetricDraft(unit: " % "), empty)
    @Assert(decision.getOrThrow().metric, OkrMetric(0.0, 100.0, 0.0, unit: "%"))
    @Assert(joinedFields(decision.getOrThrow().fields), "[[unit]]")
    @Assert(
        decision.getOrThrow().normalized,
        MetricDraft(start: "0", current: "0", target: "100", unit: "%")
    )
}

@Test
func pendingPatchSkipsValuesEqualToStoredOrCommitted() {
    let lastCommitted = metricToDraft(BASE)
    @Assert(pendingMetricPatch(Some(BASE), lastCommitted, lastCommitted).isNone(), true)
    // "42.0" 规范化后与 store 的 "42" 相同 -> 跳过
    let reformatted = MetricDraft(
        start: "42.0",
        current: lastCommitted.current,
        target: lastCommitted.target,
        unit: lastCommitted.unit
    )
    @Assert(pendingMetricPatch(Some(BASE), reformatted, lastCommitted).isNone(), true)
    // 单位前后空格 trim 后相同 -> 跳过
    let spacedUnit = MetricDraft(
        start: lastCommitted.start,
        current: lastCommitted.current,
        target: lastCommitted.target,
        unit: " 分 "
    )
    @Assert(pendingMetricPatch(Some(BASE), spacedUnit, lastCommitted).isNone(), true)
}

@Test
func pendingPatchNormalizesLongDecimals() {
    let lastCommitted = metricToDraft(BASE)
    let draft = MetricDraft(
        start: lastCommitted.start,
        current: "0.3333333333333333",
        target: lastCommitted.target,
        unit: lastCommitted.unit
    )
    let decision = pendingMetricPatch(Some(BASE), draft, lastCommitted).getOrThrow()
    @Assert(decision.metric.current, 0.3333333333333333)
    @Assert(decision.normalized.current, "0.3333333333333333")
}

@Test
func metricToTextMatchesJsString() {
    @Assert(metricToText(42.0), "42")
    @Assert(metricToText(2.1), "2.1")
    @Assert(metricToText(Float64.NaN), "")
    @Assert(metricToText(TEST_INF), "")
    @Assert(metricToText(1.0 / 3.0), "0.3333333333333333")
    @Assert(metricToText(0.1 + 0.2), "0.30000000000000004")
    @Assert(metricToText(1e21), "1e+21")
    @Assert(metricToText(1e-7), "1e-7")
    @Assert(metricToText(-0.0), "0")
}

@Test
func metricToDraftAndFieldText() {
    let draft = metricToDraft(BASE)
    @Assert(draft, MetricDraft(start: "42", current: "47", target: "60", unit: "分"))
    @Assert(metricFieldValueText(BASE, MetricField.Start), "42")
    @Assert(metricFieldValueText(BASE, MetricField.Current), "47")
    @Assert(metricFieldValueText(BASE, MetricField.Target), "60")
    @Assert(metricFieldValueText(BASE, MetricField.UnitField), "分")
    @Assert(metricFieldText(MetricField.UnitField), "unit")
    @Assert(metricFieldFromText("unit").getOrThrow(), MetricField.UnitField)
    @Assert(metricFieldFromText("nope").isNone(), true)
}

@Test
func parseMetricNumberFollowsJsNumber() {
    @Assert(parseMetricNumber("60").getOrThrow(), 60.0)
    @Assert(parseMetricNumber(" 60.0 ").getOrThrow(), 60.0)
    @Assert(parseMetricNumber("1e3").getOrThrow(), 1000.0)
    @Assert(parseMetricNumber(".5").getOrThrow(), 0.5)
    @Assert(parseMetricNumber("5.").getOrThrow(), 5.0)
    @Assert(parseMetricNumber("+5").getOrThrow(), 5.0)
    @Assert(parseMetricNumber("-0").getOrThrow(), 0.0)
    // JS Number 额外接受 0x / 0o / 0b
    @Assert(parseMetricNumber("0x10").getOrThrow(), 16.0)
    @Assert(parseMetricNumber(" 0x10 ").getOrThrow(), 16.0)
    @Assert(parseMetricNumber("0b101").getOrThrow(), 5.0)
    @Assert(parseMetricNumber("0o17").getOrThrow(), 15.0)
    // 非法输入
    @Assert(parseMetricNumber("").isNone(), true)
    @Assert(parseMetricNumber("   ").isNone(), true)
    @Assert(parseMetricNumber("abc").isNone(), true)
    @Assert(parseMetricNumber("1,5").isNone(), true)
    @Assert(parseMetricNumber("1_0").isNone(), true)
    @Assert(parseMetricNumber("Infinity").isNone(), true)
    @Assert(parseMetricNumber("1e999").isNone(), true)
    @Assert(parseMetricNumber("0x").isNone(), true)
    @Assert(parseMetricNumber("0xzz").isNone(), true)
}
