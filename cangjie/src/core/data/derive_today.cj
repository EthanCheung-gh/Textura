package textura.core.data

import std.collection.*
import std.sort.*

/**
 * "Today" aggregation, ported from `src/modules/dashboard/today.ts`.
 *
 * Domain queries come from `selectors.cj`; this file only merges, de-duplicates
 * and orders them for the dashboard.
 */
public enum FocusBucket {
    | Overdue
    | Today
    | Undated

    public operator func ==(right: FocusBucket): Bool {
        focusBucketWire(this) == focusBucketWire(right)
    }

    public operator func !=(right: FocusBucket): Bool {
        focusBucketWire(this) != focusBucketWire(right)
    }
}

public func focusBucketWire(bucket: FocusBucket): String {
    match (bucket) {
        case FocusBucket.Overdue => "overdue"
        case FocusBucket.Today => "today"
        case FocusBucket.Undated => "undated"
    }
}

func focusBucketWeight(bucket: FocusBucket): Int64 {
    match (bucket) {
        case FocusBucket.Overdue => 0
        case FocusBucket.Today => 1
        case FocusBucket.Undated => 2
    }
}

/** Where a focus row comes from: an SOP flow, an OKR branch, or neither. */
public enum FocusSource {
    | Plain
    | Sop
    | Okr

    public operator func ==(right: FocusSource): Bool {
        focusSourceWire(this) == focusSourceWire(right)
    }

    public operator func !=(right: FocusSource): Bool {
        focusSourceWire(this) != focusSourceWire(right)
    }
}

public func focusSourceWire(source: FocusSource): String {
    match (source) {
        case FocusSource.Plain => "none"
        case FocusSource.Sop => "sop"
        case FocusSource.Okr => "okr"
    }
}

public class FocusEntry {
    public let item: Item
    public let bucket: FocusBucket
    /** Due date key (`gantt.end`). */
    public let due: ?String
    /** Days late; only meaningful for the overdue bucket (>= 1). */
    public let daysLate: Int64
    /** Root -> self titles. */
    public let pathTitles: Array<String>
    public let source: FocusSource

    public init(
        item: Item,
        bucket: FocusBucket,
        due: ?String,
        daysLate: Int64,
        pathTitles: Array<String>,
        source: FocusSource
    ) {
        this.item = item
        this.bucket = bucket
        this.due = due
        this.daysLate = daysLate
        this.pathTitles = pathTitles
        this.source = source
    }
}

func focusSourceOf(item: Item, ancestors: Array<Item>): FocusSource {
    if (item.kind == ItemKind.Sop || item.kind == ItemKind.Step) {
        return FocusSource.Sop
    }
    if (item.kind == ItemKind.Objective || item.kind == ItemKind.KeyResult) {
        return FocusSource.Okr
    }
    for (entry in ancestors) {
        if (entry.kind == ItemKind.Sop) {
            return FocusSource.Sop
        }
    }
    for (entry in ancestors) {
        if (entry.kind == ItemKind.Objective || entry.kind == ItemKind.KeyResult) {
            return FocusSource.Okr
        }
    }
    FocusSource.Plain
}

func daysLateFor(todayKey: String, due: ?String): Int64 {
    match (due) {
        case None => 1
        case Some(dueKey) =>
            let diff = daysBetween(dueKey, todayKey)
            let late = if (diff > 0) {
                diff
            } else {
                1
            }
            late
    }
}

/**
 * Overdue + due-today + undated next actions, de-duplicated by id
 * (overdue > today > undated), then ordered by bucket and its inner rule.
 */
public func buildTodayFocus(workspace: Workspace, today: String): Array<FocusEntry> {
    let todayKey = match (dateKey(today)) {
        case Some(value) => value
        case None => today
    }
    let entries = ArrayList<FocusEntry>()
    let seen = HashMap<String, Bool>()

    let push = {item: Item, bucket: FocusBucket =>
        match (seen.get(item.id)) {
            case Some(_) => ()
            case None =>
                seen[item.id] = true
                let ancestorsNearestFirst = ancestorsOf(workspace, item.id)
                let path = ArrayList<String>()
                var position = ancestorsNearestFirst.size - 1
                while (position >= 0) {
                    path.add(ancestorsNearestFirst[position].title)
                    position -= 1
                }
                path.add(item.title)
                let due = item.dueKey()
                entries.add(FocusEntry(
                    item,
                    bucket,
                    due,
                    if (bucket == FocusBucket.Overdue) {
                        daysLateFor(todayKey, due)
                    } else {
                        0
                    },
                    path.toArray(),
                    focusSourceOf(item, ancestorsNearestFirst)
                ))
        }
    }

    for (item in overdueItems(workspace, todayKey)) {
        push(item, FocusBucket.Overdue)
    }
    for (item in dueTodayItems(workspace, todayKey)) {
        push(item, FocusBucket.Today)
    }
    for (item in nextActions(workspace)) {
        match (item.dueKey()) {
            case Some(_) => ()
            case None => push(item, FocusBucket.Undated)
        }
    }

    let result = entries.toArray()
    sort<FocusEntry>(
        result,
        lessThan: {left, right =>
            let leftWeight = focusBucketWeight(left.bucket)
            let rightWeight = focusBucketWeight(right.bucket)
            if (leftWeight != rightWeight) {
                return leftWeight < rightWeight
            }
            if (left.bucket == FocusBucket.Overdue) {
                let leftDue = match (left.due) {
                    case Some(value) => value
                    case None => ""
                }
                let rightDue = match (right.due) {
                    case Some(value) => value
                    case None => ""
                }
                if (leftDue != rightDue) {
                    return leftDue < rightDue
                }
            }
            if (left.item.order != right.item.order) {
                return left.item.order < right.item.order
            }
            left.item.createdAt < right.item.createdAt
        }
    )
    result
}

public class FocusCounts {
    public let overdue: Int64
    public let today: Int64
    public let undated: Int64

    public init(overdue: Int64, today: Int64, undated: Int64) {
        this.overdue = overdue
        this.today = today
        this.undated = undated
    }

    public func total(): Int64 {
        overdue + today + undated
    }
}

/** First-screen cap for the dashboard focus list. */
public let FOCUS_PAGE_SIZE: Int64 = 100

public class FocusPage {
    public let items: Array<FocusEntry>
    public let shown: Int64
    public let total: Int64
    public let remaining: Int64
    public let hasMore: Bool

    public init(items: Array<FocusEntry>, shown: Int64, total: Int64, remaining: Int64, hasMore: Bool) {
        this.items = items
        this.shown = shown
        this.total = total
        this.remaining = remaining
        this.hasMore = hasMore
    }
}

/** Takes the first `limit` entries; negative limits behave like 0. */
public func paginateFocus(entries: Array<FocusEntry>, limit: Int64): FocusPage {
    let total = entries.size
    let safeLimit = if (limit < 0) {
        0
    } else {
        limit
    }
    let shown = if (safeLimit < total) {
        safeLimit
    } else {
        total
    }
    let visible = ArrayList<FocusEntry>()
    for (index in 0..shown) {
        visible.add(entries[index])
    }
    FocusPage(visible.toArray(), shown, total, total - shown, shown < total)
}

public func countFocusBuckets(entries: Array<FocusEntry>): FocusCounts {
    var overdue = 0
    var today = 0
    var undated = 0
    for (entry in entries) {
        match (entry.bucket) {
            case FocusBucket.Overdue => overdue += 1
            case FocusBucket.Today => today += 1
            case FocusBucket.Undated => undated += 1
        }
    }
    FocusCounts(overdue, today, undated)
}

/** One-sentence status summary, identical wording to the Web dashboard. */
public func summarizeToday(overdue: Int64, today: Int64, inbox: Int64, next: Int64): String {
    let parts = ArrayList<String>()
    if (overdue > 0) {
        parts.add("${overdue} 项已超期")
    }
    if (today > 0) {
        parts.add("${today} 项今日到期")
    }
    if (inbox > 0) {
        parts.add("收件箱 ${inbox} 条待澄清")
    }
    if (!parts.isEmpty()) {
        let out = StringBuilder()
        for (index in 0..parts.size) {
            if (index > 0) {
                out.append("，")
            }
            out.append(parts[index])
        }
        out.append("。")
        return out.toString()
    }
    if (next > 0) {
        return "今天没有硬性截止，${next} 项下一步可以先推进。"
    }
    "今天没有待办，先收集一点想法，或者去定一个目标。"
}

/**
 * Items completed in the last `days` calendar days (today included),
 * newest completion first — same window as `completedThisWeek`.
 */
public func completedThisWeek(workspace: Workspace, nowMillis: Int64, days!: Int64 = 7): Array<Item> {
    let nowDay = dayIndex(nowMillis)
    let result = ArrayList<Item>()
    for (item in workspace.items) {
        let completedAt = match (item.completedAt) {
            case Some(value) => value
            case None => continue
        }
        let completedMillis = match (parseIsoMillis(completedAt)) {
            case Some(value) => value
            case None => continue
        }
        let diff = nowDay - dayIndex(completedMillis)
        if (diff >= 0 && diff < days) {
            result.add(item)
        }
    }
    let array = result.toArray()
    sort<Item>(
        array,
        lessThan: {left, right =>
            let leftAt = match (left.completedAt) {
                case Some(value) => value
                case None => ""
            }
            let rightAt = match (right.completedAt) {
                case Some(value) => value
                case None => ""
            }
            leftAt > rightAt
        }
    )
    array
}

/** Most recently completed items, no time window. */
public func recentlyCompleted(workspace: Workspace, limit!: Int64 = 5): Array<Item> {
    let result = ArrayList<Item>()
    for (item in workspace.items) {
        match (item.completedAt) {
            case Some(_) => result.add(item)
            case None => ()
        }
    }
    let array = result.toArray()
    sort<Item>(
        array,
        lessThan: {left, right =>
            let leftAt = match (left.completedAt) {
                case Some(value) => value
                case None => ""
            }
            let rightAt = match (right.completedAt) {
                case Some(value) => value
                case None => ""
            }
            leftAt > rightAt
        }
    )
    let page = ArrayList<Item>()
    for (index in 0..array.size) {
        if (index >= limit) {
            break
        }
        page.add(array[index])
    }
    page.toArray()
}

/** All SOP runs, newest first (ties broken by id for determinism). */
public func sortedRuns(workspace: Workspace): Array<SopRunEntry> {
    let runs = ArrayList<SopRunEntry>()
    for (run in workspace.runs) {
        runs.add(run)
    }
    let array = runs.toArray()
    sort<SopRunEntry>(
        array,
        lessThan: {left, right =>
            if (left.at != right.at) {
                left.at > right.at
            } else {
                left.id < right.id
            }
        }
    )
    array
}

public func latestRun(workspace: Workspace): ?SopRunEntry {
    let runs = sortedRuns(workspace)
    if (runs.isEmpty()) {
        None
    } else {
        Some(runs[0])
    }
}

public func latestRunFor(workspace: Workspace, sopId: String): ?SopRunEntry {
    for (run in sortedRuns(workspace)) {
        if (run.sopId == sopId) {
            return Some(run)
        }
    }
    None
}

public func activityKindWire(kind: ActivityKind): String {
    match (kind) {
        case ActivityKind.Run => "run"
        case ActivityKind.Completed => "completed"
    }
}

public enum ActivityKind {
    | Run
    | Completed

    public operator func ==(right: ActivityKind): Bool {
        activityKindWire(this) == activityKindWire(right)
    }

    public operator func !=(right: ActivityKind): Bool {
        activityKindWire(this) != activityKindWire(right)
    }
}

/** One line of the "recent activity" feed. */
public class ActivityEntry {
    public let id: String
    public let kind: ActivityKind
    public let at: String
    public let title: String
    public let detail: String
    public let result: ?RunResult

    public init(id: String, kind: ActivityKind, at: String, title: String, detail: String, result: ?RunResult) {
        this.id = id
        this.kind = kind
        this.at = at
        this.title = title
        this.detail = detail
        this.result = result
    }
}

/** Latest runs + latest completions, merged newest first. */
public func buildActivity(workspace: Workspace, limitPerSource!: Int64 = 5): Array<ActivityEntry> {
    let entries = ArrayList<ActivityEntry>()
    let runs = sortedRuns(workspace)
    var index = 0
    while (index < runs.size && index < limitPerSource) {
        let run = runs[index]
        let sopTitle = match (itemById(workspace, run.sopId)) {
            case Some(item) => item.title
            case None => "未知 SOP"
        }
        let resultText = runResultLabel(run.result)
        let detail = match (itemById(workspace, run.stepId)) {
            case Some(step) => "${step.title} · ${resultText}"
            case None => resultText
        }
        entries.add(ActivityEntry("run:${run.id}", ActivityKind.Run, run.at, sopTitle, detail, Some(run.result)))
        index += 1
    }
    for (item in recentlyCompleted(workspace, limit: limitPerSource)) {
        let at = match (item.completedAt) {
            case Some(value) => value
            case None => item.updatedAt
        }
        entries.add(ActivityEntry(
            "completed:${item.id}",
            ActivityKind.Completed,
            at,
            item.title,
            "${itemKindLabel(item.kind)} · 已完成",
            None
        ))
    }
    let array = entries.toArray()
    sort<ActivityEntry>(array, lessThan: {left, right => left.at > right.at})
    array
}
