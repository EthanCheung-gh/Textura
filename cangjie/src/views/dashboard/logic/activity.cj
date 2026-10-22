package textura.views.dashboard.logic

import std.collection.*
import std.deriving.*

/** 活动来源：SOP 运行记录或条目完成。 */
@Derive[Equatable]
public enum ActivityKind {
    | Run
    | Completed
}

/** 「最近活动」一行。`result` 仅运行记录有值。 */
public struct ActivityEntry {
    public let id: String
    public let kind: ActivityKind
    public let at: String
    public let title: String
    public let detail: String
    public let result: ?RunResult

    public init(
        id: String,
        kind: ActivityKind,
        at: String,
        title: String,
        detail: String,
        result: ?RunResult
    ) {
        this.id = id
        this.kind = kind
        this.at = at
        this.title = title
        this.detail = detail
        this.result = result
    }
}

/** 全部 SOP 运行记录，按时间倒序、同刻按 id 升序。 */
public func sortedRuns(runs: Array<SopRun>): Array<SopRun> {
    return stableSortBy<SopRun>(
        runs,
        {
            left, right =>
                let atDiff = compareText(right.at, left.at)
                if (atDiff != 0) {
                    return atDiff
                }
                return compareText(left.id, right.id)
        }
    )
}

/** 最近一次运行；无记录返回 `None`。 */
public func latestRun(runs: Array<SopRun>): ?SopRun {
    let ordered = sortedRuns(runs)
    if (ordered.size == 0) {
        return None
    }
    return Some(ordered[0])
}

/** 某个 SOP 的最近一次运行。 */
public func latestRunFor(runs: Array<SopRun>, sopId: String): ?SopRun {
    for (run in sortedRuns(runs)) {
        if (run.sopId == sopId) {
            return Some(run)
        }
    }
    return None
}

/**
 * 最近活动：runs（最近 `limitPerSource` 条）+ 完成记录（最近 `limitPerSource` 条），按时间倒序。
 *
 * 同一时刻的并列项保持「先 runs、后 completed」的输入顺序（JS 稳定排序语义）。
 */
public func buildActivity(
    items: Array<DashItem>,
    runs: Array<SopRun>,
    limitPerSource!: Int64 = 5
): Array<ActivityEntry> {
    let entries = ArrayList<ActivityEntry>()
    for (run in takeSlice<SopRun>(sortedRuns(runs), limitPerSource)) {
        let resultLabel = runResultLabel(run.result)
        let title = match (run.sopTitle) {
            case Some(text) => text
            case None => "未知 SOP"
        }
        let detail = match (run.stepTitle) {
            case Some(text) => text + " · " + resultLabel
            case None => resultLabel
        }
        entries.add(ActivityEntry("run:" + run.id, ActivityKind.Run, run.at, title, detail, Some(run.result)))
    }

    for (item in recentlyCompleted(items, limit: limitPerSource)) {
        let at = match (completedText(item)) {
            case Some(text) => text
            case None => item.updatedAt
        }
        entries.add(
            ActivityEntry(
                "completed:" + item.id,
                ActivityKind.Completed,
                at,
                item.title,
                kindLabel(item.kind) + " · 已完成",
                None
            )
        )
    }

    return stableSortBy<ActivityEntry>(entries.toArray(), {left, right => return compareText(right.at, left.at)})
}
