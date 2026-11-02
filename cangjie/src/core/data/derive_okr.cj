package textura.core.data

import std.collection.*
import std.convert.*

/**
 * OKR view math, ported from `src/modules/okr/okrMath.ts`.
 * Domain roll-ups come from `selectors.cj`; this file adds quarter timing,
 * lagging detection, confidence buckets and execution-item linking.
 */
public let BEHIND_MARGIN_POINTS: Float64 = 10.0
public let METRIC_RANGE_EPSILON: Float64 = 1e-9

public func roundTo(value: Float64, digits: Int64): Float64 {
    if (value != value) {
        return 0.0
    }
    var factor = 1.0
    var index = 0
    while (index < digits) {
        factor = factor * 10.0
        index += 1
    }
    Float64(roundHalfUp(value * factor)) / factor
}

/**
 * Quarter elapsed percentage: first day is 0, last day 100, clamped outside.
 * Unparsable periods return 0 so a bad value never breaks the view.
 */
public func quarterElapsedPercent(period: String, todayMillis: Int64): Float64 {
    let range = match (quarterRange(period)) {
        case Some(value) => value
        case None => return 0.0
    }
    let startMillis = match (parseDateKey(Some(range.start))) {
        case Some(value) => value
        case None => return 0.0
    }
    let endMillis = match (parseDateKey(Some(range.end))) {
        case Some(value) => value
        case None => return 0.0
    }
    let totalDays = dayIndex(endMillis) - dayIndex(startMillis)
    let elapsedDays = dayIndex(todayMillis) - dayIndex(startMillis)
    if (totalDays <= 0) {
        return if (elapsedDays >= 0) {
            100.0
        } else {
            0.0
        }
    }
    roundTo(clampFloat(Float64(elapsedDays) / Float64(totalDays) * 100.0, 0.0, 100.0), 1)
}

/** A KR is behind when it lags the elapsed quarter by `BEHIND_MARGIN_POINTS`. */
public func isKrBehind(progress: Float64, elapsedPercent: Float64): Bool {
    if (progress != progress || elapsedPercent != elapsedPercent) {
        return false
    }
    elapsedPercent - progress >= BEHIND_MARGIN_POINTS
}

public func confidenceBucketWire(bucket: ConfidenceBucket): String {
    match (bucket) {
        case ConfidenceBucket.Low => "low"
        case ConfidenceBucket.Mid => "mid"
        case ConfidenceBucket.High => "high"
    }
}

public enum ConfidenceBucket {
    | Low
    | Mid
    | High

    public operator func ==(right: ConfidenceBucket): Bool {
        confidenceBucketWire(this) == confidenceBucketWire(right)
    }

    public operator func !=(right: ConfidenceBucket): Bool {
        confidenceBucketWire(this) != confidenceBucketWire(right)
    }
}

/** 1–3 low, 4–6 mid, 7–10 high. */
public func confidenceBucket(confidence: Int64): ConfidenceBucket {
    let value = clampInt(confidence, 1, 10)
    if (value <= 3) {
        ConfidenceBucket.Low
    } else if (value <= 6) {
        ConfidenceBucket.Mid
    } else {
        ConfidenceBucket.High
    }
}

/** True when start and target differ enough to convert a metric into progress. */
public func hasMetricRange(metric: ?Metric): Bool {
    match (metric) {
        case None => false
        case Some(value) =>
            let span = value.target - value.start
            let magnitude = if (span < 0.0) {
                -span
            } else {
                span
            }
            magnitude >= METRIC_RANGE_EPSILON
    }
}

public enum MetricProgressState {
    | Unset
    | Invalid
    | Flat
    | Under
    | InRange
    | Over

    public operator func ==(right: MetricProgressState): Bool {
        metricProgressStateWire(this) == metricProgressStateWire(right)
    }

    public operator func !=(right: MetricProgressState): Bool {
        metricProgressStateWire(this) != metricProgressStateWire(right)
    }
}

public func metricProgressStateWire(state: MetricProgressState): String {
    match (state) {
        case MetricProgressState.Unset => "unset"
        case MetricProgressState.Invalid => "invalid"
        case MetricProgressState.Flat => "flat"
        case MetricProgressState.Under => "under"
        case MetricProgressState.InRange => "in-range"
        case MetricProgressState.Over => "over"
    }
}

public class MetricProgressInfo {
    public let state: MetricProgressState
    /** Clamped 0..100; None for unset/flat/invalid. */
    public let percent: ?Float64
    /** True when clamping happened (under / over). */
    public let clamped: Bool

    public init(state: MetricProgressState, percent: ?Float64, clamped: Bool) {
        this.state = state
        this.percent = percent
        this.clamped = clamped
    }
}

/**
 * Direction-aware metric conversion:
 * - flat: no range (|target-start| < 1e-9), percent is None;
 * - under / over: clamped to 0 / 100;
 * - in-range: 0..100 inclusive, rounded.
 */
public func metricProgressInfo(metric: ?Metric): MetricProgressInfo {
    let value = match (metric) {
        case Some(metricValue) => metricValue
        case None => return MetricProgressInfo(MetricProgressState.Unset, None, false)
    }
    if (value.start != value.start || value.target != value.target || value.current != value.current) {
        return MetricProgressInfo(MetricProgressState.Invalid, None, false)
    }
    if (!hasMetricRange(Some(value))) {
        return MetricProgressInfo(MetricProgressState.Flat, None, false)
    }
    let ratio = (value.current - value.start) / (value.target - value.start)
    if (ratio < 0.0) {
        return MetricProgressInfo(MetricProgressState.Under, Some(0.0), true)
    }
    if (ratio > 1.0) {
        return MetricProgressInfo(MetricProgressState.Over, Some(100.0), true)
    }
    MetricProgressInfo(MetricProgressState.InRange, Some(roundTo(ratio * 100.0, 0)), false)
}

public func metricPercent(metric: ?Metric): ?Float64 {
    match (metricProgressInfo(metric).percent) {
        case Some(value) => Some(value)
        case None => None
    }
}

public class OkrSummary {
    public let objectives: Int64
    public let keyResults: Int64
    public let averageProgress: Int64
    public let behind: Int64
    public let elapsedPercent: Float64
    public let confidenceLow: Int64
    public let confidenceMid: Int64
    public let confidenceHigh: Int64

    public init(
        objectives: Int64,
        keyResults: Int64,
        averageProgress: Int64,
        behind: Int64,
        elapsedPercent: Float64,
        confidenceLow: Int64,
        confidenceMid: Int64,
        confidenceHigh: Int64
    ) {
        this.objectives = objectives
        this.keyResults = keyResults
        this.averageProgress = averageProgress
        this.behind = behind
        this.elapsedPercent = elapsedPercent
        this.confidenceLow = confidenceLow
        this.confidenceMid = confidenceMid
        this.confidenceHigh = confidenceHigh
    }
}

/** Quarter health: counts, average objective progress, confidence mix, lagging KRs. */
public func summarizeOkr(workspace: Workspace, period: String, todayMillis: Int64): OkrSummary {
    let objectives = objectivesOfPeriod(workspace, period)
    let elapsedPercent = quarterElapsedPercent(period, todayMillis)
    var low = 0
    var mid = 0
    var high = 0
    var keyResults = 0
    var behind = 0
    var progressSum = 0
    for (objective in objectives) {
        progressSum += rollupProgress(workspace, objective.id)
        for (child in childrenOf(workspace, Some(objective.id))) {
            if (child.kind != ItemKind.KeyResult) {
                continue
            }
            keyResults += 1
            let confidence = match (child.okr) {
                case Some(okr) => okr.confidence
                case None => 5
            }
            match (confidenceBucket(confidence)) {
                case ConfidenceBucket.Low => low += 1
                case ConfidenceBucket.Mid => mid += 1
                case ConfidenceBucket.High => high += 1
            }
            if (isKrBehind(Float64(rollupProgress(workspace, child.id)), elapsedPercent)) {
                behind += 1
            }
        }
    }
    let average = if (objectives.isEmpty()) {
        0
    } else {
        roundHalfUp(Float64(progressSum) / Float64(objectives.size))
    }
    OkrSummary(objectives.size, keyResults, average, behind, elapsedPercent, low, mid, high)
}

/** How an execution item is attached to a KR. */
public enum ExecutionLink {
    /** Linked through an `okr` edge (can be unlinked). */
    | Edge
    /** Hangs under the KR via `parentId`. */
    | Child
}

public class ExecutionItemRef {
    public let item: Item
    public let via: ExecutionLink
    public let edgeId: ?String

    public init(item: Item, via: ExecutionLink, edgeId: ?String) {
        this.item = item
        this.via = via
        this.edgeId = edgeId
    }
}

/**
 * Every execution item of one KR, from both the `okr` edge and `parentId`.
 * An item hit by both paths keeps the edge link (it can be unlinked).
 */
public func executionItemsOf(workspace: Workspace, krId: String): Array<ExecutionItemRef> {
    let result = ArrayList<ExecutionItemRef>()
    let seen = HashMap<String, Bool>()
    for (edge in edgeTargetsWithId(workspace, krId, EdgeType.Okr)) {
        let target = match (itemById(workspace, edge.to)) {
            case Some(value) => value
            case None => continue
        }
        if (target.kind != ItemKind.Project && target.kind != ItemKind.Action) {
            continue
        }
        match (seen.get(target.id)) {
            case Some(_) => continue
            case None =>
                seen[target.id] = true
                result.add(ExecutionItemRef(target, ExecutionLink.Edge, Some(edge.id)))
        }
    }
    for (child in childrenOf(workspace, Some(krId))) {
        if (child.kind != ItemKind.Project && child.kind != ItemKind.Action) {
            continue
        }
        match (seen.get(child.id)) {
            case Some(_) => continue
            case None =>
                seen[child.id] = true
                result.add(ExecutionItemRef(child, ExecutionLink.Child, None))
        }
    }
    result.toArray()
}

func edgeTargetsWithId(workspace: Workspace, id: String, edgeType: EdgeType): Array<Edge> {
    let result = ArrayList<Edge>()
    for (edge in workspace.edges) {
        if (edge.from == id && edge.edgeType == edgeType) {
            result.add(edge)
        }
    }
    result.toArray()
}

public class ObjectiveView {
    public let objective: Item
    /** Key results after search filtering. */
    public let keyResults: Array<Item>
    /** True when the objective itself matched; false when only KRs matched. */
    public let objectiveMatched: Bool

    public init(objective: Item, keyResults: Array<Item>, objectiveMatched: Bool) {
        this.objective = objective
        this.keyResults = keyResults
        this.objectiveMatched = objectiveMatched
    }
}

func okrSearchableText(workspace: Workspace, item: Item): String {
    let out = StringBuilder()
    out.append(item.title)
    out.append(" ")
    out.append(item.notes)
    out.append(" ")
    match (item.areaId) {
        case Some(areaId) => match (areaById(workspace, areaId)) {
            case Some(area) => out.append(area.name)
            case None => ()
        }
        case None => ()
    }
    out.append(" ")
    match (item.okr) {
        case Some(okr) => match (okr.krOwner) {
            case Some(owner) => out.append(owner)
            case None => ()
        }
        case None => ()
    }
    for (tag in item.tags) {
        out.append(" ")
        out.append(tag)
    }
    out.toString().toAsciiLower()
}

public func matchesOkrQuery(workspace: Workspace, item: Item, query: String): Bool {
    let needle = query.trimAscii().toAsciiLower()
    if (needle.isEmpty()) {
        return true
    }
    okrSearchableText(workspace, item).contains(needle)
}

/** Objective + filtered KRs: a matched objective keeps all KRs. */
public func filterObjectives(workspace: Workspace, period: String, query: String): Array<ObjectiveView> {
    let needle = query.trimAscii().toAsciiLower()
    let result = ArrayList<ObjectiveView>()
    for (objective in objectivesOfPeriod(workspace, period)) {
        let keyResults = ArrayList<Item>()
        for (child in childrenOf(workspace, Some(objective.id))) {
            if (child.kind == ItemKind.KeyResult) {
                keyResults.add(child)
            }
        }
        if (needle.isEmpty()) {
            result.add(ObjectiveView(objective, keyResults.toArray(), true))
            continue
        }
        if (matchesOkrQuery(workspace, objective, needle)) {
            result.add(ObjectiveView(objective, keyResults.toArray(), true))
            continue
        }
        let matched = ArrayList<Item>()
        for (kr in keyResults) {
            if (matchesOkrQuery(workspace, kr, needle)) {
                matched.add(kr)
            }
        }
        if (!matched.isEmpty()) {
            result.add(ObjectiveView(objective, matched.toArray(), false))
        }
    }
    result.toArray()
}

/** Quarter shift, e.g. 2026-Q4 + 1 -> 2027-Q1. */
public func shiftQuarter(period: String, delta: Int64): String {
    if (period.size != 7 || period[4] != UInt8(45) || period[5] != UInt8(81)) {
        return period
    }
    let year = match (Int64.tryParse(period[0..4])) {
        case Some(value) => value
        case None => return period
    }
    let quarter = Int64(period[6]) - 48
    if (quarter < 1 || quarter > 4) {
        return period
    }
    let index = year * 4 + (quarter - 1) + delta
    let nextYear = floorDiv(index, 4)
    let nextQuarterIndex = floorMod(index, 4) + 1
    "${nextYear}-Q${nextQuarterIndex}"
}

public func nextQuarter(period: String): String {
    shiftQuarter(period, 1)
}

/** `2026-Q4` -> `2026 Q4`; unparsable input is returned unchanged. */
public func quarterLabel(period: String): String {
    if (period.size != 7 || period[4] != UInt8(45) || period[5] != UInt8(81)) {
        return period
    }
    "${period[0..4]} Q${period[6..7]}"
}
