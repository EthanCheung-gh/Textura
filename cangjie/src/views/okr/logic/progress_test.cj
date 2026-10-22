package textura.views.okr.logic

import std.unittest.*
import std.unittest.testmacro.*

/*
 * 对齐 `src/modules/okr/okrMath.test.ts` 的 `isKrBehind` / `confidenceBucket` / `summarize`
 * 三组断言，并补充 `rollupProgress` 的边界（越界夹紧、NaN 传播、完成比取整）。
 */

@Test
func isKrBehindFlagsWhenProgressLagsTenPoints() {
    @Assert(isKrBehind(0.0, 10.0), true)
    @Assert(isKrBehind(20.0, 49.4), true)
    @Assert(isKrBehind(51.0, 61.0), true)
}

@Test
func isKrBehindIgnoresInsideTolerance() {
    @Assert(isKrBehind(52.0, 61.0), false)
    @Assert(isKrBehind(60.0, 60.0), false)
    @Assert(isKrBehind(80.0, 40.0), false)
    @Assert(isKrBehind(0.0, 0.0), false)
    // 恰好 10 个点算落后
    @Assert(isKrBehind(10.0, 20.0), true)
    @Assert(approx(BEHIND_MARGIN_POINTS + 0.0, 10.0, 0.0), true)
}

@Test
func isKrBehindReturnsFalseForNonFiniteInput() {
    @Assert(isKrBehind(Float64.NaN, 50.0), false)
    @Assert(isKrBehind(10.0, TEST_INF), false)
    @Assert(isKrBehind(TEST_INF, 50.0), false)
}

@Test
func confidenceBucketMapsRanges() {
    @Assert(confidenceBucketText(confidenceBucket(1.0)), "low")
    @Assert(confidenceBucketText(confidenceBucket(2.0)), "low")
    @Assert(confidenceBucketText(confidenceBucket(3.0)), "low")
    @Assert(confidenceBucketText(confidenceBucket(4.0)), "mid")
    @Assert(confidenceBucketText(confidenceBucket(5.0)), "mid")
    @Assert(confidenceBucketText(confidenceBucket(6.0)), "mid")
    @Assert(confidenceBucketText(confidenceBucket(7.0)), "high")
    @Assert(confidenceBucketText(confidenceBucket(8.0)), "high")
    @Assert(confidenceBucketText(confidenceBucket(9.0)), "high")
    @Assert(confidenceBucketText(confidenceBucket(10.0)), "high")
}

@Test
func confidenceBucketClampsOutOfRangeValues() {
    @Assert(confidenceBucketText(confidenceBucket(0.0)), "low")
    @Assert(confidenceBucketText(confidenceBucket(-3.0)), "low")
    @Assert(confidenceBucketText(confidenceBucket(11.0)), "high")
    @Assert(confidenceBucketText(confidenceBucket(Float64.NaN)), "low")
    // 非整数与无穷
    @Assert(confidenceBucketText(confidenceBucket(3.4)), "mid")
    @Assert(confidenceBucketText(confidenceBucket(6.5)), "high")
    @Assert(confidenceBucketText(confidenceBucket(TEST_INF)), "low")
    @Assert(confidenceBucketText(confidenceBucket(-TEST_INF)), "low")
}

private func summarizeWorkspace(): OkrWorkspace {
    makeWorkspace(
        items: [
            makeItem(
                "obj_a",
                OkrItemKind.Objective,
                "A",
                order: 0,
                okr: Some(OkrData("2026-Q1", 6.0))
            ),
            makeItem(
                "kr_1",
                OkrItemKind.KeyResult,
                "KR 1",
                parentId: Some("obj_a"),
                order: 0,
                okr: Some(
                    OkrData(
                        "2026-Q1",
                        5.0,
                        metric: Some(OkrMetric(0.0, 100.0, 20.0, unit: "%"))
                    )
                )
            ),
            makeItem(
                "kr_2",
                OkrItemKind.KeyResult,
                "KR 2",
                parentId: Some("obj_a"),
                order: 1,
                okr: Some(OkrData("2026-Q1", 9.0))
            ),
            makeItem(
                "act_1",
                OkrItemKind.Action,
                "已完成行动",
                parentId: Some("kr_2"),
                order: 0,
                status: OkrItemStatus.Done
            ),
            makeItem(
                "obj_b",
                OkrItemKind.Objective,
                "B",
                order: 1,
                okr: Some(OkrData("2026-Q1", 2.0))
            ),
            makeItem(
                "obj_c",
                OkrItemKind.Objective,
                "上一季度",
                order: 2,
                okr: Some(OkrData("2025-Q4", 8.0))
            ),
            makeItem(
                "kr_c",
                OkrItemKind.KeyResult,
                "不属于本季度",
                parentId: Some("obj_c"),
                okr: Some(OkrData("2025-Q4", 10.0))
            )
        ]
    )
}

@Test
func summarizeAggregatesQuarterHealth() {
    let summary = summarize(summarizeWorkspace(), "2026-Q1", CivilDate(2026, 2, 14))
    @Assert(summary.objectives, 2)
    @Assert(summary.keyResults, 2)
    // obj_a: (20 + 100) / 2 = 60；obj_b: 无 KR -> 0；平均 (60 + 0) / 2 = 30
    @Assert(summary.averageProgress, 30.0)
    @Assert(summary.behind, 1)
    @Assert(summary.confidenceOf(ConfidenceBucket.Low), 0)
    @Assert(summary.confidenceOf(ConfidenceBucket.Mid), 1)
    @Assert(summary.confidenceOf(ConfidenceBucket.High), 1)
    @Assert(approx(summary.elapsedPercent, 49.4, 0.05), true)
}

@Test
func summarizeReturnsZerosForQuarterWithoutObjectives() {
    let summary = summarize(summarizeWorkspace(), "2026-Q4", CivilDate(2026, 11, 1))
    @Assert(summary.objectives, 0)
    @Assert(summary.keyResults, 0)
    @Assert(summary.averageProgress, 0.0)
    @Assert(summary.behind, 0)
    @Assert(summary.confidenceOf(ConfidenceBucket.Low), 0)
    @Assert(summary.confidenceOf(ConfidenceBucket.Mid), 0)
    @Assert(summary.confidenceOf(ConfidenceBucket.High), 0)
}

@Test
func summarizeFallsBackToMidConfidenceWithoutOkrData() {
    let workspace = makeWorkspace(
        items: [
            makeItem("obj", OkrItemKind.Objective, "O", okr: Some(OkrData("2026-Q1", 5.0))),
            makeItem("kr", OkrItemKind.KeyResult, "KR", parentId: Some("obj"))
        ]
    )
    let summary = summarize(workspace, "2026-Q1", CivilDate(2026, 2, 14))
    @Assert(summary.keyResults, 1)
    @Assert(summary.confidenceOf(ConfidenceBucket.Mid), 1)
    @Assert(summary.confidenceOf(ConfidenceBucket.Low), 0)
}

@Test
func rollupProgressClampsMetricOvershootAndUndershoot() {
    let workspace = makeWorkspace(
        items: [
            makeItem(
                "kr_over",
                OkrItemKind.KeyResult,
                "超目标",
                okr: Some(OkrData("2026-Q1", 5.0, metric: Some(OkrMetric(0.0, 100.0, 250.0))))
            ),
            makeItem(
                "kr_under",
                OkrItemKind.KeyResult,
                "负进度",
                okr: Some(OkrData("2026-Q1", 5.0, metric: Some(OkrMetric(0.0, 100.0, -40.0))))
            ),
            makeItem(
                "kr_flat",
                OkrItemKind.KeyResult,
                "无区间",
                status: OkrItemStatus.Done,
                okr: Some(OkrData("2026-Q1", 5.0, metric: Some(OkrMetric(5.0, 5.0, 5.0))))
            )
        ]
    )
    @Assert(rollupProgress(workspace, "kr_over"), 100.0)
    @Assert(rollupProgress(workspace, "kr_under"), 0.0)
    // target === start 时回退到完成状态
    @Assert(rollupProgress(workspace, "kr_flat"), 100.0)
}

@Test
func rollupProgressRoundsChildCompletion() {
    let workspace = makeWorkspace(
        items: [
            makeItem("proj", OkrItemKind.Project, "P"),
            makeItem("a1", OkrItemKind.Action, "A1", parentId: Some("proj"), order: 0, status: OkrItemStatus.Done),
            makeItem("a2", OkrItemKind.Action, "A2", parentId: Some("proj"), order: 1),
            makeItem("a3", OkrItemKind.Action, "A3", parentId: Some("proj"), order: 2)
        ]
    )
    // 1/3 -> 33.333 -> Math.round -> 33
    @Assert(rollupProgress(workspace, "proj"), 33.0)
    @Assert(rollupProgress(workspace, "missing"), 0.0)
}

@Test
func rollupProgressPropagatesNaNLikeTs() {
    let workspace = makeWorkspace(
        items: [
            makeItem(
                "kr_nan",
                OkrItemKind.KeyResult,
                "NaN 指标",
                okr: Some(OkrData("2026-Q1", 5.0, metric: Some(OkrMetric(Float64.NaN, 10.0, 5.0))))
            )
        ]
    )
    @Assert(rollupProgress(workspace, "kr_nan").isNaN(), true)
}

@Test
func rollupProgressGuardsParentCycles() {
    let workspace = makeWorkspace(
        items: [
            makeItem("obj", OkrItemKind.Objective, "O", parentId: Some("kr"), okr: Some(OkrData("2026-Q1", 5.0))),
            makeItem("kr", OkrItemKind.KeyResult, "KR", parentId: Some("obj"), okr: Some(OkrData("2026-Q1", 5.0)))
        ]
    )
    // 环内不会无限递归；不崩溃且落在 0..100
    let value = rollupProgress(workspace, "obj")
    @Assert(value >= 0.0, true)
    @Assert(value <= 100.0, true)
}
