package textura.views.okr.logic

/*
 * 指标（metric）换算。
 *
 * 领域层的 `rollupProgress` 对 target === start 的 KR 会回退到完成状态 / 子项完成比，
 * 所以视图层必须单独识别「无法换算」的情况，不能显示凭空的 100%。
 */

/** 起点与目标之间被视为「有区间」的最小差值；容忍浮点噪声。 */
public let METRIC_RANGE_EPSILON: Float64 = 1e-9

/** 指标换算状态（方向感知）。 */
public enum MetricProgressState <: Equatable<MetricProgressState> {
    | Unset
    | Invalid
    | Flat
    | Under
    | InRange
    | Over

    public operator func ==(that: MetricProgressState): Bool {
        metricProgressStateText(this) == metricProgressStateText(that)
    }

    public operator func !=(that: MetricProgressState): Bool {
        !(this == that)
    }
}

/** TS 的字符串字面量形式，便于对照文档与 TS 测试。 */
public func metricProgressStateText(state: MetricProgressState): String {
    match (state) {
        case MetricProgressState.Unset => "unset"
        case MetricProgressState.Invalid => "invalid"
        case MetricProgressState.Flat => "flat"
        case MetricProgressState.Under => "under"
        case MetricProgressState.InRange => "in-range"
        case MetricProgressState.Over => "over"
    }
}

/** 等价于 TS `MetricProgressInfo`；`percent` 为 None 表示无法换算。 */
public struct MetricProgressInfo <: Equatable<MetricProgressInfo> {
    public let state: MetricProgressState
    public let percent: ?Float64
    public let clamped: Bool

    public init(state: MetricProgressState, percent: ?Float64, clamped: Bool) {
        this.state = state
        this.percent = percent
        this.clamped = clamped
    }

    public operator func ==(that: MetricProgressInfo): Bool {
        state == that.state && percent == that.percent && clamped == that.clamped
    }
}

private func absolute(value: Float64): Float64 {
    if (value < 0.0) {
        -value
    } else {
        value
    }
}

/** 起点与目标之间是否存在可换算区间（容忍 1e-9 以内的浮点噪声）。 */
public func hasMetricRange(metric: ?OkrMetric): Bool {
    match (metric) {
        case Some(value) => isFiniteNumber(value.start) && isFiniteNumber(value.target) &&
            absolute(value.target - value.start) >= METRIC_RANGE_EPSILON
        case None => false
    }
}

/**
 * 指标换算状态（方向感知）：
 * - Flat：|target - start| < 1e-9，无法换算，percent 为 None；
 * - Under：current 未达到起点（正向低于 start / 负向高于 start），夹紧到 0；
 * - Over：current 已越过目标（正向高于 target / 负向低于 target），夹紧到 100；
 * - InRange：包含 current === start 与 current === target，不算超额/低于起点。
 */
public func metricProgress(metric: ?OkrMetric): MetricProgressInfo {
    if (metric.isNone()) {
        return MetricProgressInfo(MetricProgressState.Unset, None, false)
    }
    let value = metric.getOrThrow()
    if (!isFiniteNumber(value.start) || !isFiniteNumber(value.target) || !isFiniteNumber(value.current)) {
        return MetricProgressInfo(MetricProgressState.Invalid, None, false)
    }
    if (!hasMetricRange(value)) {
        return MetricProgressInfo(MetricProgressState.Flat, None, false)
    }
    let ratio = (value.current - value.start) / (value.target - value.start)
    if (ratio < 0.0) {
        return MetricProgressInfo(MetricProgressState.Under, Some(0.0), true)
    }
    if (ratio > 1.0) {
        return MetricProgressInfo(MetricProgressState.Over, Some(100.0), true)
    }
    MetricProgressInfo(MetricProgressState.InRange, Some(roundTo(ratio * 100.0, digits: 0)), false)
}

/** 纯换算值（0..100），没有可换算区间时返回 None。 */
public func metricPercent(metric: ?OkrMetric): ?Float64 {
    metricProgress(metric).percent
}
