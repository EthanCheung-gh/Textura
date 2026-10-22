package textura.views.okr.logic

import std.collection.*

/*
 * 进度汇总：落后判定、信心分档、季度健康度、领域进度滚动（rollupProgress 的移植）。
 */

/** 低于时间进度 10 个点（含）即视为落后。 */
public let BEHIND_MARGIN_POINTS: Float64 = 10.0

/** 信心指数分档。 */
public enum ConfidenceBucket <: Equatable<ConfidenceBucket> {
    | Low
    | Mid
    | High

    public operator func ==(that: ConfidenceBucket): Bool {
        confidenceBucketText(this) == confidenceBucketText(that)
    }

    public operator func !=(that: ConfidenceBucket): Bool {
        !(this == that)
    }
}

public func confidenceBucketText(bucket: ConfidenceBucket): String {
    match (bucket) {
        case ConfidenceBucket.Low => "low"
        case ConfidenceBucket.Mid => "mid"
        case ConfidenceBucket.High => "high"
    }
}

/** 进度落后时间进度达到阈值（10 个点）。非有限输入返回 false（不抛异常）。 */
public func isKrBehind(progress: Float64, elapsedPercent: Float64): Bool {
    if (!isFiniteNumber(progress) || !isFiniteNumber(elapsedPercent)) {
        return false
    }
    elapsedPercent - progress >= BEHIND_MARGIN_POINTS
}

/** 信心指数分档：1–3 低、4–6 中、7–10 高；越界与 NaN 夹紧到 1。 */
public func confidenceBucket(confidence: Float64): ConfidenceBucket {
    var value = if (isFiniteNumber(confidence)) {
        confidence
    } else {
        1.0
    }
    if (value < 1.0) {
        value = 1.0
    }
    if (value > 10.0) {
        value = 10.0
    }
    if (value <= 3.0) {
        return ConfidenceBucket.Low
    }
    if (value <= 6.0) {
        return ConfidenceBucket.Mid
    }
    ConfidenceBucket.High
}

/** 季度健康度快照。`averageProgress` 与 TS 一样是取整后的数值。 */
public struct OkrSummary <: Equatable<OkrSummary> {
    public let objectives: Int64
    public let keyResults: Int64
    public let averageProgress: Float64
    public let behind: Int64
    public let elapsedPercent: Float64
    public let confidenceLow: Int64
    public let confidenceMid: Int64
    public let confidenceHigh: Int64

    public init(
        objectives: Int64,
        keyResults: Int64,
        averageProgress: Float64,
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

    public operator func ==(that: OkrSummary): Bool {
        objectives == that.objectives && keyResults == that.keyResults && averageProgress == that.averageProgress &&
            behind == that.behind && elapsedPercent == that.elapsedPercent && confidenceLow == that.confidenceLow &&
            confidenceMid == that.confidenceMid && confidenceHigh == that.confidenceHigh
    }

    /** 某档信心指数对应的计数，等价 TS `summary.confidence[bucket]`。 */
    public func confidenceOf(bucket: ConfidenceBucket): Int64 {
        match (bucket) {
            case ConfidenceBucket.Low => confidenceLow
            case ConfidenceBucket.Mid => confidenceMid
            case ConfidenceBucket.High => confidenceHigh
        }
    }
}

private func isDone(item: OkrItem): Bool {
    item.status == OkrItemStatus.Done
}

/** 子项完成比（done / 总数）×100；无子项返回 0。 */
private func completion(children: Array<OkrItem>): Float64 {
    if (children.size == 0) {
        return 0.0
    }
    var done = 0
    for (child in children) {
        if (isDone(child)) {
            done += 1
        }
    }
    Float64(done) / Float64(children.size) * 100.0
}

/** JS `min(100, max(0, value))`：NaN 会原样传播（与 TS 一致）。 */
private func clampProgress(value: Float64): Float64 {
    if (value > 100.0) {
        return 100.0
    }
    if (value < 0.0) {
        return 0.0
    }
    value
}

private func computeRollup(
    index: OkrIndex,
    item: OkrItem,
    visiting: HashSet<String>
): Float64 {
    if (visiting.contains(item.id)) {
        return 0.0
    }
    visiting.add(item.id)
    let children = index.childrenOf(item.id)
    var value = 0.0
    match (item.kind) {
        case OkrItemKind.Objective =>
            let keyResults = ArrayList<OkrItem>()
            for (child in children) {
                if (child.kind == OkrItemKind.KeyResult) {
                    keyResults.add(child)
                }
            }
            if (keyResults.size > 0) {
                var sum = 0.0
                for (kr in keyResults) {
                    sum += computeRollup(index, kr, visiting)
                }
                value = sum / Float64(keyResults.size)
            } else {
                value = completion(children)
            }
        case OkrItemKind.KeyResult =>
            let metric = match (item.okr) {
                case Some(okr) => okr.metric
                case None => Option<OkrMetric>.None
            }
            let hasConvertibleMetric = match (metric) {
                case Some(entry) => entry.target != entry.start
                case None => false
            }
            if (hasConvertibleMetric) {
                let entry = metric.getOrThrow()
                value = (entry.current - entry.start) / (entry.target - entry.start) * 100.0
            } else if (isDone(item)) {
                value = 100.0
            } else {
                value = completion(children)
            }
        case OkrItemKind.Project | OkrItemKind.Sop => value = completion(children)
        case _ => value = if (isDone(item)) {
            100.0
        } else {
            0.0
        }
    }
    visiting.remove(item.id)
    clampProgress(jsRound(value))
}

/**
 * 汇总进度 0..100 的整数：
 * - objective：其 KR 的平均；无 KR 时退回子项完成比
 * - keyresult：有 metric 用 (current-start)/(target-start)；否则 done?100:子项完成比
 * - project / sop：子项完成比
 * - 其余：done?100:0
 */
public func rollupProgress(workspace: OkrWorkspace, id: String): Float64 {
    let index = OkrIndex(workspace)
    let itemOption = index.itemById(id)
    if (itemOption.isNone()) {
        return 0.0
    }
    computeRollup(index, itemOption.getOrThrow(), HashSet<String>())
}

/** 季度健康度：目标/KR 数、目标平均进度、信心分布、落后 KR 数。 */
public func summarize(workspace: OkrWorkspace, period: String, today: CivilDate): OkrSummary {
    let index = OkrIndex(workspace)
    let objectives = index.objectivesOf(period)
    let elapsedPercent = quarterElapsedPercent(period, today)
    var confidenceLow = 0
    var confidenceMid = 0
    var confidenceHigh = 0
    var keyResults = 0
    var behind = 0
    var progressSum = 0.0

    for (objective in objectives) {
        progressSum += computeRollup(index, objective, HashSet<String>())
        for (kr in index.childrenOf(objective.id)) {
            if (kr.kind != OkrItemKind.KeyResult) {
                continue
            }
            keyResults += 1
            let confidence = match (kr.okr) {
                case Some(okr) => okr.confidence
                case None => 5.0
            }
            match (confidenceBucket(confidence)) {
                case ConfidenceBucket.Low => confidenceLow += 1
                case ConfidenceBucket.Mid => confidenceMid += 1
                case ConfidenceBucket.High => confidenceHigh += 1
            }
            if (isKrBehind(computeRollup(index, kr, HashSet<String>()), elapsedPercent)) {
                behind += 1
            }
        }
    }

    let averageProgress = if (objectives.size > 0) {
        jsRound(progressSum / Float64(objectives.size))
    } else {
        0.0
    }
    OkrSummary(
        objectives.size,
        keyResults,
        averageProgress,
        behind,
        elapsedPercent,
        confidenceLow,
        confidenceMid,
        confidenceHigh
    )
}
