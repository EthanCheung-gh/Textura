package textura.views.okr.logic

import std.collection.*
import std.convert.*
import std.unicode.*

/*
 * 指标草稿与提交决策，对应 `src/modules/okr/metricDraft.ts`。
 *
 * 组件负责 timer / focus / 历史快照；本模块只回答「当前草稿里哪些字段需要提交，
 * 合并后的 metric 是什么」，因此卸载 flush 可以脱离 UI 状态单独测试。
 */

/** 指标字段。 */
public enum MetricField <: Equatable<MetricField> {
    | Start
    | Current
    | Target
    | UnitField

    public operator func ==(that: MetricField): Bool {
        metricFieldText(this) == metricFieldText(that)
    }

    public operator func !=(that: MetricField): Bool {
        !(this == that)
    }
}

public func metricFieldText(field: MetricField): String {
    match (field) {
        case MetricField.Start => "start"
        case MetricField.Current => "current"
        case MetricField.Target => "target"
        case MetricField.UnitField => "unit"
    }
}

public func metricFieldFromText(text: String): ?MetricField {
    match (text) {
        case "start" => Some(MetricField.Start)
        case "current" => Some(MetricField.Current)
        case "target" => Some(MetricField.Target)
        case "unit" => Some(MetricField.UnitField)
        case _ => None
    }
}

/** 提交顺序与 TS 一致：start、current、target、unit。 */
public let METRIC_FIELDS: Array<MetricField> = [
    MetricField.Start,
    MetricField.Current,
    MetricField.Target,
    MetricField.UnitField
]
public let METRIC_NUMBER_FIELDS: Array<MetricField> = [
    MetricField.Start,
    MetricField.Current,
    MetricField.Target
]

/** 没有历史指标时的默认值。 */
public let EMPTY_METRIC: OkrMetric = OkrMetric(0.0, 100.0, 0.0, unit: "")

/** 指标编辑草稿：全部是文本。 */
public struct MetricDraft <: Equatable<MetricDraft> {
    public let start: String
    public let current: String
    public let target: String
    public let unit: String

    public init(
        start!: String = "",
        current!: String = "",
        target!: String = "",
        unit!: String = ""
    ) {
        this.start = start
        this.current = current
        this.target = target
        this.unit = unit
    }

    public operator func ==(that: MetricDraft): Bool {
        start == that.start && current == that.current && target == that.target && unit == that.unit
    }

    public operator func !=(that: MetricDraft): Bool {
        !(this == that)
    }

    public func textOf(field: MetricField): String {
        match (field) {
            case MetricField.Start => start
            case MetricField.Current => current
            case MetricField.Target => target
            case MetricField.UnitField => unit
        }
    }
}

/** JS `String(number)`；非有限值给空串。 */
public func metricToText(value: Float64): String {
    if (!isFiniteNumber(value)) {
        return ""
    }
    jsNumberToString(value)
}

/** 单字段的文本形式（单位原样返回）。 */
public func metricFieldValueText(metric: OkrMetric, field: MetricField): String {
    match (field) {
        case MetricField.Start => metricToText(metric.start)
        case MetricField.Current => metricToText(metric.current)
        case MetricField.Target => metricToText(metric.target)
        case MetricField.UnitField => metric.unit
    }
}

public func metricToDraft(metric: OkrMetric): MetricDraft {
    MetricDraft(
        start: metricToText(metric.start),
        current: metricToText(metric.current),
        target: metricToText(metric.target),
        unit: metric.unit
    )
}

private func numberFieldValue(metric: OkrMetric, field: MetricField): Float64 {
    match (field) {
        case MetricField.Start => metric.start
        case MetricField.Current => metric.current
        case MetricField.Target => metric.target
        case MetricField.UnitField => 0.0
    }
}

private func digitFor(rune: Rune, radix: Int64): Int64 {
    let code = Int64(UInt32(rune))
    let lowerDigit = Int64(UInt32(r'0'))
    let lowerAlpha = Int64(UInt32(r'a'))
    let upperAlpha = Int64(UInt32(r'A'))
    var value = -1
    if (code >= lowerDigit && code <= lowerDigit + 9) {
        value = code - lowerDigit
    } else if (code >= lowerAlpha && code <= lowerAlpha + 25) {
        value = code - lowerAlpha + 10
    } else if (code >= upperAlpha && code <= upperAlpha + 25) {
        value = code - upperAlpha + 10
    }
    if (value < 0 || value >= radix) {
        return -1
    }
    value
}

/** JS `Number()` 额外接受的 0x / 0o / 0b 整数字面量（不允许符号）。 */
private func parseRadixLiteral(text: String): ?Float64 {
    let lower = text.toAsciiLower()
    var radix: Int64 = 0
    if (lower.startsWith("0x")) {
        radix = 16
    } else if (lower.startsWith("0o")) {
        radix = 8
    } else if (lower.startsWith("0b")) {
        radix = 2
    } else {
        return None
    }
    let digits = lower.toRuneArray()[2..lower.toRuneArray().size]
    if (digits.size == 0) {
        return None
    }
    var value = 0.0
    for (rune in digits) {
        let digit = digitFor(rune, radix)
        if (digit < 0) {
            return None
        }
        value = value * Float64(radix) + Float64(digit)
    }
    if (!isFiniteNumber(value)) {
        return None
    }
    Some(value)
}

/** 空串与非数字返回 None（与 TS `parseMetricNumber` 一致）。 */
public func parseMetricNumber(raw: String): ?Float64 {
    let trimmed = raw.trim()
    if (trimmed.isEmpty()) {
        return None
    }
    let radixValue = parseRadixLiteral(trimmed)
    if (radixValue.isSome()) {
        return radixValue
    }
    match (Float64.tryParse(trimmed)) {
        case Some(value) =>
            if (isFiniteNumber(value)) {
                Some(value)
            } else {
                None
            }
        case None => None
    }
}

/** 一次 flush 的结果：合并后的 metric、实际写入字段、规范化后的完整草稿。 */
public struct MetricFlushDecision {
    public let metric: OkrMetric
    public let fields: Array<MetricField>
    public let normalized: MetricDraft

    public init(metric: OkrMetric, fields: Array<MetricField>, normalized: MetricDraft) {
        this.metric = metric
        this.fields = fields
        this.normalized = normalized
    }
}

/**
 * 计算待提交 patch。
 * - 数值字段为空/非法：跳过（保留 store 里的旧值）；
 * - draft 已与 lastCommitted 或 store 当前值相同：跳过（避免重复历史）；
 * - 单位是文本字段，允许清空，提交时 trim；
 * - 多字段同时待提交时合并成一个 metric，供一次 updateItem 使用。
 */
public func pendingMetricPatch(
    latest: ?OkrMetric,
    draft: MetricDraft,
    lastCommitted: MetricDraft
): ?MetricFlushDecision {
    let base = match (latest) {
        case Some(value) => value
        case None => EMPTY_METRIC
    }
    let baseDraft = metricToDraft(base)
    var metricStart = base.start
    var metricCurrent = base.current
    var metricTarget = base.target
    var metricUnit = base.unit
    var normalizedStart = baseDraft.start
    var normalizedCurrent = baseDraft.current
    var normalizedTarget = baseDraft.target
    var normalizedUnit = baseDraft.unit
    let fields = ArrayList<MetricField>()

    for (field in METRIC_FIELDS) {
        let raw = draft.textOf(field)
        if (field == MetricField.UnitField) {
            let unit = raw.trim()
            if (unit == lastCommitted.unit || unit == base.unit) {
                continue
            }
            metricUnit = unit
            normalizedUnit = unit
            fields.add(field)
            continue
        }
        let parsedOption = parseMetricNumber(raw)
        if (parsedOption.isNone()) {
            continue
        }
        let parsed = parsedOption.getOrThrow()
        let text = metricToText(parsed)
        if (text == lastCommitted.textOf(field) || text == metricToText(numberFieldValue(base, field))) {
            continue
        }
        match (field) {
            case MetricField.Start =>
                metricStart = parsed
                normalizedStart = text
            case MetricField.Current =>
                metricCurrent = parsed
                normalizedCurrent = text
            case MetricField.Target =>
                metricTarget = parsed
                normalizedTarget = text
            case MetricField.UnitField => ()
        }
        fields.add(field)
    }

    if (fields.size == 0) {
        return None
    }
    Some(
        MetricFlushDecision(
            OkrMetric(metricStart, metricTarget, metricCurrent, unit: metricUnit),
            fields.toArray(),
            MetricDraft(
                start: normalizedStart,
                current: normalizedCurrent,
                target: normalizedTarget,
                unit: normalizedUnit
            )
        )
    )
}

/**
 * 卸载 / 失焦兜底：把当前草稿里所有待提交字段合并成一次 update。
 * 返回 decision 以便调用方（组件）同步 lastCommitted；没有待提交字段时返回 None。
 */
public func flushMetricDrafts(
    latest: ?OkrMetric,
    draft: MetricDraft,
    lastCommitted: MetricDraft,
    update: (OkrMetric) -> Unit
): ?MetricFlushDecision {
    let decision = pendingMetricPatch(latest, draft, lastCommitted)
    if (decision.isNone()) {
        return None
    }
    let value = decision.getOrThrow()
    update(value.metric)
    Some(value)
}
