package textura.core.data

import std.collection.*
import std.sort.*

/**
 * GTD view logic, ported from `src/modules/gtd/gtdLogic.ts`.
 * Pure functions only: components (and later the Cangjie views) call these,
 * mutations go through `AppStore`.
 */
public let NO_CONTEXT: String = "无场景"
/** Filter sentinel for "no context"; never collides with a user context. */
public let NO_CONTEXT_FILTER: String = "__none__"
public let PRESET_CONTEXTS: Array<String> = ["电脑", "电话", "外出", "会议", "深度工作"]
public let WAITING_WARN_DAYS: Int64 = 7
public let LIST_PAGE_SIZE: Int64 = 100

public func currentDateKey(clock: Clock): String {
    localDateKey(clock.nowMillis())
}

/**
 * Full ISO timestamp -> local calendar day key (`YYYY-MM-DD`).
 *
 * `dateKey()` only slices the first 10 characters, which yields the UTC day for
 * `2026-10-14T17:01Z`; this parses first and formats in the pinned +08:00 zone.
 */
public func localDayKey(value: String): ?String {
    match (parseIsoMillis(value)) {
        case Some(millis) => Some(localDateKey(millis))
        case None => None
    }
}

public func contextOf(item: Item): ?String {
    match (item.gtd) {
        case Some(gtd) => match (gtd.context) {
            case Some(context) => if (context.trimAscii().isEmpty()) {
                None
            } else {
                Some(context.trimAscii())
            }
            case None => None
        }
        case None => None
    }
}

/** low = 1, medium = 2, high = 3, unset = 0 (used for ordering). */
public func energyRank(item: Item): Int64 {
    match (item.gtd) {
        case Some(gtd) => match (gtd.energy) {
            case Some(Energy.High) => 3
            case Some(Energy.Medium) => 2
            case Some(Energy.Low) => 1
            case None => 0
        }
        case None => 0
    }
}

/** Inbox order: newest `gtd.capturedAt` first, falling back to `createdAt`. */
public func sortInboxItems(items: Array<Item>): Array<Item> {
    let array = ArrayList<Item>()
    for (item in items) {
        array.add(item)
    }
    let result = array.toArray()
    sort<Item>(
        result,
        lessThan: {left, right =>
            let leftAt = match (left.gtd) {
                case Some(gtd) => gtd.capturedAt
                case None => left.createdAt
            }
            let rightAt = match (right.gtd) {
                case Some(gtd) => gtd.capturedAt
                case None => right.createdAt
            }
            if (leftAt != rightAt) {
                return leftAt > rightAt
            }
            if (left.createdAt != right.createdAt) {
                return left.createdAt > right.createdAt
            }
            left.order < right.order
        }
    )
    result
}

public class ContextGroup {
    public let context: String
    public let items: Array<Item>

    public init(context: String, items: Array<Item>) {
        this.context = context
        this.items = items
    }
}

func contextOrder(context: String): Int64 {
    if (context == NO_CONTEXT) {
        return 999
    }
    for (index in 0..PRESET_CONTEXTS.size) {
        if (PRESET_CONTEXTS[index] == context) {
            return index
        }
    }
    100
}

/**
 * Groups by `gtd.context`; empty contexts go to "无场景" and empty groups are
 * dropped. Group order: presets, then custom names alphabetically, then the
 * no-context bucket — stable regardless of input order.
 */
public func groupByContext(items: Array<Item>): Array<ContextGroup> {
    // Buckets are visited in first-seen order (an explicit list), never by
    // HashMap iteration order, so the pre-sort order is stable across runtimes
    // and matches `views/gtd/logic`'s implementation.
    let order = ArrayList<String>()
    let buckets = HashMap<String, ArrayList<Item>>()
    for (item in items) {
        let context = match (contextOf(item)) {
            case Some(value) => value
            case None => NO_CONTEXT
        }
        match (buckets.get(context)) {
            case Some(bucket) => bucket.add(item)
            case None =>
                let bucket = ArrayList<Item>()
                bucket.add(item)
                buckets[context] = bucket
                order.add(context)
        }
    }
    let result = ArrayList<ContextGroup>()
    for (context in order) {
        match (buckets.get(context)) {
            case Some(bucket) => result.add(ContextGroup(context, bucket.toArray()))
            case None => ()
        }
    }
    // Stable sort: equal keys keep first-seen order (deterministic by construction).
    let array = result.toArray()
    sort<ContextGroup>(
        array,
        lessThan: {left, right =>
            let leftOrder = contextOrder(left.context)
            let rightOrder = contextOrder(right.context)
            if (leftOrder != rightOrder) {
                return leftOrder < rightOrder
            }
            left.context < right.context
        },
        stable: true
    )
    array
}

/** Due date first (earliest first), then energy high→low, then creation order. */
public func sortNextActions(items: Array<Item>): Array<Item> {
    let array = ArrayList<Item>()
    for (item in items) {
        array.add(item)
    }
    let result = array.toArray()
    sort<Item>(
        result,
        lessThan: {left, right =>
            let leftEnd = left.dueKey()
            let rightEnd = right.dueKey()
            match (leftEnd) {
                case Some(leftKey) => match (rightEnd) {
                    case Some(rightKey) => if (leftKey != rightKey) {
                        return leftKey < rightKey
                    }
                    case None => return true
                }
                case None => match (rightEnd) {
                    case Some(_) => return false
                    case None => ()
                }
            }
            let byEnergy = energyRank(right) - energyRank(left)
            if (byEnergy != 0) {
                return byEnergy > 0
            }
            if (left.createdAt != right.createdAt) {
                return left.createdAt < right.createdAt
            }
            left.order < right.order
        }
    )
    result
}

/* ------------------------------------------------------------------ */
/* Pagination (pure; the component only stores the limit)              */
/* ------------------------------------------------------------------ */

public class PageSlice<T> {
    public let items: Array<T>
    public let shown: Int64
    public let total: Int64
    public let remaining: Int64
    public let hasMore: Bool

    public init(items: Array<T>, shown: Int64, total: Int64, remaining: Int64, hasMore: Bool) {
        this.items = items
        this.shown = shown
        this.total = total
        this.remaining = remaining
        this.hasMore = hasMore
    }
}

public func paginateItems<T>(items: Array<T>, limit: Int64): PageSlice<T> {
    let total = items.size
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
    let visible = ArrayList<T>()
    for (index in 0..shown) {
        visible.add(items[index])
    }
    PageSlice(visible.toArray(), shown, total, total - shown, shown < total)
}

public class PaginationState {
    public let key: String
    public let limit: Int64

    public init(key: String, limit: Int64) {
        this.key = key
        this.limit = limit
    }
}

/** A new filter key resets paging without an extra effect in the view. */
public func resolvePageLimit(state: PaginationState, key: String, pageSize!: Int64 = LIST_PAGE_SIZE): Int64 {
    if (state.key != key) {
        return pageSize
    }
    if (state.limit < pageSize) {
        pageSize
    } else {
        state.limit
    }
}

public func nextPage(state: PaginationState, key: String, pageSize!: Int64 = LIST_PAGE_SIZE): PaginationState {
    PaginationState(key, resolvePageLimit(state, key, pageSize: pageSize) + pageSize)
}

/* ------------------------------------------------------------------ */
/* Filters / health                                                    */
/* ------------------------------------------------------------------ */

public class NextFilter {
    /** None = all, `NO_CONTEXT_FILTER` = no context, otherwise an exact context. */
    public let context: ?String
    public let dueSoonOnly: Bool
    public let areaId: ?String
    public let search: String
    public let today: String

    public init(
        context!: ?String = None,
        dueSoonOnly!: Bool = false,
        areaId!: ?String = None,
        search!: String = "",
        today!: String = ""
    ) {
        this.context = context
        this.dueSoonOnly = dueSoonOnly
        this.areaId = areaId
        this.search = search
        this.today = today
    }
}

public func matchesSearch(item: Item, search: String): Bool {
    let needle = search.trimAscii().toAsciiLower()
    if (needle.isEmpty()) {
        return true
    }
    let haystack = StringBuilder()
    haystack.append(item.title)
    haystack.append(" ")
    haystack.append(item.notes)
    haystack.append(" ")
    match (contextOf(item)) {
        case Some(context) => haystack.append(context)
        case None => ()
    }
    haystack.append(" ")
    match (item.gtd) {
        case Some(gtd) => match (gtd.waitingFor) {
            case Some(waitingFor) => haystack.append(waitingFor)
            case None => ()
        }
        case None => ()
    }
    for (tag in item.tags) {
        haystack.append(" ")
        haystack.append(tag)
    }
    haystack.toString().toAsciiLower().contains(needle)
}

public func filterNextActions(items: Array<Item>, filter: NextFilter): Array<Item> {
    let todayKey = match (localDayKey(filter.today)) {
        case Some(value) => value
        case None => filter.today
    }
    let result = ArrayList<Item>()
    for (item in items) {
        let context = contextOf(item)
        match (filter.context) {
            case Some(value) => if (value == NO_CONTEXT_FILTER) {
                match (context) {
                    case Some(_) => continue
                    case None => ()
                }
            } else if (!value.isEmpty()) {
                match (context) {
                    case Some(actual) => if (actual != value) {
                        continue
                    }
                    case None => continue
                }
            }
            case None => ()
        }
        if (filter.dueSoonOnly) {
            match (item.dueKey()) {
                case Some(end) => if (end > todayKey) {
                    continue
                }
                case None => continue
            }
        }
        match (filter.areaId) {
            case Some(areaId) => match (item.areaId) {
                case Some(actual) => if (actual != areaId) {
                    continue
                }
                case None => continue
            }
            case None => ()
        }
        if (!matchesSearch(item, filter.search)) {
            continue
        }
        result.add(item)
    }
    result.toArray()
}

/**
 * Stuck project:
 * - no child actions -> stuck;
 * - any child with status `next` -> not stuck;
 * - all children done/dropped -> not stuck (finished work is not stuck);
 * - otherwise -> stuck.
 */
public func isStuckProject(workspace: Workspace, projectId: String): Bool {
    let project = match (itemById(workspace, projectId)) {
        case Some(value) => value
        case None => return false
    }
    if (project.kind != ItemKind.Project) {
        return false
    }
    if (project.status == ItemStatus.Done || project.status == ItemStatus.Dropped) {
        return false
    }
    var related = 0
    var nextCount = 0
    var openCount = 0
    for (child in descendantsOf(workspace, projectId)) {
        let relevant = child.kind == ItemKind.Action || child.kind == ItemKind.Project ||
            child.kind == ItemKind.Milestone
        if (!relevant) {
            continue
        }
        related += 1
        if (child.status == ItemStatus.Next) {
            nextCount += 1
        }
        if (child.status != ItemStatus.Done && child.status != ItemStatus.Dropped) {
            openCount += 1
        }
    }
    if (related == 0) {
        return true
    }
    if (nextCount > 0) {
        return false
    }
    if (openCount == 0) {
        return false
    }
    true
}

public class ProjectHealth {
    public let project: Item
    public let total: Int64
    public let done: Int64
    public let open: Int64
    public let next: Int64
    public let progress: Int64
    public let stuck: Bool

    public init(
        project: Item,
        total: Int64,
        done: Int64,
        open: Int64,
        next: Int64,
        progress: Int64,
        stuck: Bool
    ) {
        this.project = project
        this.total = total
        this.done = done
        this.open = open
        this.next = next
        this.progress = progress
        this.stuck = stuck
    }
}

/** Direct child counts plus roll-up progress and stuck state, per project. */
public func projectHealth(workspace: Workspace): Array<ProjectHealth> {
    let result = ArrayList<ProjectHealth>()
    for (project in itemsOfKind(workspace, ItemKind.Project)) {
        var total = 0
        var done = 0
        var next = 0
        for (child in childrenOf(workspace, Some(project.id))) {
            let relevant = child.kind == ItemKind.Action || child.kind == ItemKind.Milestone ||
                child.kind == ItemKind.Project
            if (!relevant) {
                continue
            }
            total += 1
            if (child.status == ItemStatus.Done || child.status == ItemStatus.Dropped) {
                done += 1
            }
            if (child.status == ItemStatus.Next) {
                next += 1
            }
        }
        result.add(ProjectHealth(
            project,
            total,
            done,
            total - done,
            next,
            rollupProgress(workspace, project.id),
            isStuckProject(workspace, project.id)
        ))
    }
    result.toArray()
}

/** Waiting baseline: `gtd.capturedAt`, else `updatedAt`, else `createdAt`. */
public func waitingSince(item: Item): String {
    match (item.gtd) {
        case Some(gtd) => gtd.capturedAt
        case None => item.updatedAt
    }
}

/** Calendar days waited (local), clamped at 0. */
public func waitingDays(item: Item, today: String): Int64 {
    let todayKey = match (localDayKey(today)) {
        case Some(value) => value
        case None => match (dateKey(today)) {
            case Some(value) => value
            case None => today
        }
    }
    let sinceKey = match (localDayKey(waitingSince(item))) {
        case Some(value) => value
        case None => return 0
    }
    let diff = daysBetween(sinceKey, todayKey)
    if (diff < 0) {
        0
    } else {
        diff
    }
}

/** Strictly more than `threshold` days is "needs chasing". */
public func isWaitingOverdue(item: Item, today: String, threshold!: Int64 = WAITING_WARN_DAYS): Bool {
    waitingDays(item, today) > threshold
}

public class StaleArea {
    public let area: Area
    public let openCount: Int64
    public let lastTouched: ?String

    public init(area: Area, openCount: Int64, lastTouched: ?String) {
        this.area = area
        this.openCount = openCount
        this.lastTouched = lastTouched
    }
}

public class WeeklyReviewStats {
    public let today: String
    public let windowStart: String
    public let inbox: Array<Item>
    public let inboxCleared: Array<Item>
    public let inboxProgress: Int64
    public let completedThisWeek: Array<Item>
    public let overdue: Array<Item>
    public let stuckProjects: Array<Item>
    public let waitingOverdue: Array<Item>
    public let undatedTasks: Array<Item>
    public let staleAreas: Array<StaleArea>

    public init(
        today: String,
        windowStart: String,
        inbox: Array<Item>,
        inboxCleared: Array<Item>,
        inboxProgress: Int64,
        completedThisWeek: Array<Item>,
        overdue: Array<Item>,
        stuckProjects: Array<Item>,
        waitingOverdue: Array<Item>,
        undatedTasks: Array<Item>,
        staleAreas: Array<StaleArea>
    ) {
        this.today = today
        this.windowStart = windowStart
        this.inbox = inbox
        this.inboxCleared = inboxCleared
        this.inboxProgress = inboxProgress
        this.completedThisWeek = completedThisWeek
        this.overdue = overdue
        this.stuckProjects = stuckProjects
        this.waitingOverdue = waitingOverdue
        this.undatedTasks = undatedTasks
        this.staleAreas = staleAreas
    }

    public func inboxCount(): Int64 {
        inbox.size
    }

    public func inboxClearedCount(): Int64 {
        inboxCleared.size
    }

    public func completedCount(): Int64 {
        completedThisWeek.size
    }

    public func overdueCount(): Int64 {
        overdue.size
    }

    public func stuckProjectCount(): Int64 {
        stuckProjects.size
    }

    public func waitingOverdueCount(): Int64 {
        waitingOverdue.size
    }

    public func undatedCount(): Int64 {
        undatedTasks.size
    }
}

/** Weekly review (last 7 days including today), mirroring `weeklyReview`. */
public func weeklyReview(workspace: Workspace, today: String): WeeklyReviewStats {
    let todayKey = match (localDayKey(today)) {
        case Some(value) => value
        case None => match (dateKey(today)) {
            case Some(value) => value
            case None => today
        }
    }
    let windowStart = addDaysToKey(todayKey, -6)
    let staleBefore = addDaysToKey(todayKey, -14)

    let inbox = inboxItems(workspace)

    let completed = ArrayList<Item>()
    for (item in workspace.items) {
        let completedAt = match (item.completedAt) {
            case Some(value) => value
            case None => continue
        }
        let key = match (localDayKey(completedAt)) {
            case Some(value) => value
            case None => continue
        }
        let diff = daysBetween(key, todayKey)
        if (diff >= 0 && diff < 7) {
            completed.add(item)
        }
    }
    let completedArray = completed.toArray()
    sort<Item>(
        completedArray,
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

    let cleared = ArrayList<Item>()
    for (item in workspace.items) {
        let gtd = match (item.gtd) {
            case Some(value) => value
            case None => continue
        }
        if (!gtd.clarified || item.status == ItemStatus.Inbox) {
            continue
        }
        let key = match (localDayKey(gtd.capturedAt)) {
            case Some(value) => value
            case None => continue
        }
        let diff = daysBetween(key, todayKey)
        if (diff >= 0 && diff < 7) {
            cleared.add(item)
        }
    }
    let clearedArray = cleared.toArray()

    let total = inbox.size + clearedArray.size
    let inboxProgress = if (total == 0) {
        100
    } else {
        roundHalfUp(Float64(clearedArray.size) * 100.0 / Float64(total))
    }

    let stuckProjects = ArrayList<Item>()
    for (entry in projectHealth(workspace)) {
        if (entry.stuck) {
            stuckProjects.add(entry.project)
        }
    }

    let waitingOverdue = ArrayList<Item>()
    for (item in waitingItems(workspace)) {
        if (isWaitingOverdue(item, todayKey)) {
            waitingOverdue.add(item)
        }
    }

    let undatedTasks = ArrayList<Item>()
    for (item in workspace.items) {
        if (item.kind != ItemKind.Action && item.kind != ItemKind.Project) {
            continue
        }
        if (!item.isOpen() || (item.status != ItemStatus.Next && item.status != ItemStatus.Active)) {
            continue
        }
        if (item.startKey().isSome() || item.dueKey().isSome()) {
            continue
        }
        undatedTasks.add(item)
    }

    let staleAreas = ArrayList<StaleArea>()
    for (area in workspace.areas) {
        var openCount = 0
        var lastTouched: ?String = None
        for (item in workspace.items) {
            let inArea = match (item.areaId) {
                case Some(areaId) => areaId == area.id
                case None => false
            }
            if (!inArea || !item.isOpen()) {
                continue
            }
            if (item.kind != ItemKind.Action && item.kind != ItemKind.Project) {
                continue
            }
            openCount += 1
            match (lastTouched) {
                case Some(current) => if (item.updatedAt > current) {
                    lastTouched = Some(item.updatedAt)
                }
                case None => lastTouched = Some(item.updatedAt)
            }
        }
        if (openCount == 0) {
            continue
        }
        let lastKey: ?String = match (lastTouched) {
            case Some(value) => localDayKey(value)
            case None => None
        }
        match (lastKey) {
            case Some(key) => if (key >= staleBefore) {
                continue
            }
            case None => ()
        }
        staleAreas.add(StaleArea(area, openCount, lastTouched))
    }

    WeeklyReviewStats(
        todayKey,
        windowStart,
        inbox,
        clearedArray,
        inboxProgress,
        completedArray,
        overdueItems(workspace, todayKey),
        stuckProjects.toArray(),
        waitingOverdue.toArray(),
        undatedTasks.toArray(),
        staleAreas.toArray()
    )
}

/* ------------------------------------------------------------------ */
/* Display helpers                                                     */
/* ------------------------------------------------------------------ */

public func deadlineToneWire(tone: DeadlineTone): String {
    match (tone) {
        case DeadlineTone.Danger => "danger"
        case DeadlineTone.Accent => "accent"
        case DeadlineTone.Muted => "muted"
    }
}

public enum DeadlineTone {
    | Danger
    | Accent
    | Muted

    public operator func ==(right: DeadlineTone): Bool {
        deadlineToneWire(this) == deadlineToneWire(right)
    }

    public operator func !=(right: DeadlineTone): Bool {
        deadlineToneWire(this) != deadlineToneWire(right)
    }
}

public class DeadlineInfo {
    public let label: String
    public let tone: DeadlineTone
    public let date: ?String

    public init(label: String, tone: DeadlineTone, date: ?String) {
        this.label = label
        this.tone = tone
        this.date = date
    }
}

/** Due-date label: overdue -> danger, today -> accent, else MM/dd. */
public func deadlineInfo(item: Item, today: String): DeadlineInfo {
    let end = match (item.dueKey()) {
        case Some(value) => value
        case None => return DeadlineInfo("未设截止", DeadlineTone.Muted, None)
    }
    let todayKey = match (localDayKey(today)) {
        case Some(value) => value
        case None => match (dateKey(today)) {
            case Some(value) => value
            case None => today
        }
    }
    let diff = daysBetween(end, todayKey)
    if (diff > 0) {
        DeadlineInfo("逾期 ${diff} 天", DeadlineTone.Danger, Some(end))
    } else if (diff == 0) {
        DeadlineInfo("今天到期", DeadlineTone.Accent, Some(end))
    } else {
        DeadlineInfo(formatWithPattern(parseDateKey(Some(end)) ?? 0, "MM/dd"), DeadlineTone.Muted, Some(end))
    }
}

/** Appends a timestamped line to notes. */
public func appendTimestampedNote(notes: String, message: String, atMillis: Int64): String {
    let line = "[${formatWithPattern(atMillis, "yyyy-MM-dd HH:mm")}] ${message}"
    let base = notes.trimAsciiEnd()
    if (base.isEmpty()) {
        line
    } else {
        "${base}\n${line}"
    }
}

/* ------------------------------------------------------------------ */
/* Clarification form                                                  */
/* ------------------------------------------------------------------ */

public enum ClarifyType {
    | Next
    | Project
    | Reference
    | Note

    public operator func ==(right: ClarifyType): Bool {
        clarifyTypeWire(this) == clarifyTypeWire(right)
    }

    public operator func !=(right: ClarifyType): Bool {
        clarifyTypeWire(this) != clarifyTypeWire(right)
    }
}

public func clarifyTypeWire(value: ClarifyType): String {
    match (value) {
        case ClarifyType.Next => "next"
        case ClarifyType.Project => "project"
        case ClarifyType.Reference => "reference"
        case ClarifyType.Note => "note"
    }
}

public class ClarifyFormState {
    public var clarifyType: ClarifyType = ClarifyType.Next
    public var title: String = ""
    public var notes: String = ""
    /** Space/comma separated, `#` prefix allowed. */
    public var tags: String = ""
    /** "" means no area. */
    public var areaId: String = ""
    /** Preset context, "" (unset), or "__custom__". */
    public var context: String = ""
    public var customContext: String = ""
    public var energy: Energy = Energy.Medium
    /** UI helper for the two-minute rule; the model has no duration field. */
    public var estimateMin: ?Int64 = None
    /** `YYYY-MM-DD`; "" clears the due date. */
    public var dueDate: String = ""
    public var delegated: Bool = false
    public var waitingFor: String = ""
    public var someday: Bool = false
    public var twoMinuteCandidate: Bool = false

    public init() {}
}

public class ClarifyErrors {
    public let title: ?String
    public let waitingFor: ?String
    public let status: ?String

    public init(title!: ?String = None, waitingFor!: ?String = None, status!: ?String = None) {
        this.title = title
        this.waitingFor = waitingFor
        this.status = status
    }

    public func hasError(): Bool {
        title.isSome() || waitingFor.isSome() || status.isSome()
    }
}

public func resolveFormContext(form: ClarifyFormState): String {
    let raw = if (form.context == "__custom__") {
        form.customContext
    } else {
        form.context
    }
    raw.trimAscii()
}

public func desiredKind(clarifyType: ClarifyType): ItemKind {
    match (clarifyType) {
        case ClarifyType.Project => ItemKind.Project
        case ClarifyType.Reference => ItemKind.Reference
        case ClarifyType.Note => ItemKind.Note
        case ClarifyType.Next => ItemKind.Action
    }
}

public func isArchiveType(clarifyType: ClarifyType): Bool {
    clarifyType == ClarifyType.Reference || clarifyType == ClarifyType.Note
}

/** Archive types become `done`; delegated -> waiting; someday -> someday. */
public func clarifyTargetStatus(form: ClarifyFormState): ItemStatus {
    if (isArchiveType(form.clarifyType)) {
        return ItemStatus.Done
    }
    if (form.delegated) {
        return ItemStatus.Waiting
    }
    if (form.someday) {
        return ItemStatus.Someday
    }
    ItemStatus.Next
}

public func validateClarifyForm(form: ClarifyFormState): ClarifyErrors {
    var titleError: ?String = None
    var waitingError: ?String = None
    var statusError: ?String = None
    if (form.title.trimAscii().isEmpty()) {
        titleError = Some("标题不能为空")
    }
    let actsOnStatus = !isArchiveType(form.clarifyType)
    if (form.delegated && actsOnStatus && form.waitingFor.trimAscii().isEmpty()) {
        waitingError = Some("委派给他人时必须填写等待对象")
    }
    if (form.delegated && form.someday && actsOnStatus) {
        statusError = Some("「委派等待」与「某天/搁置」只能选一个")
    }
    ClarifyErrors(title: titleError, waitingFor: waitingError, status: statusError)
}

/** Seeds a form from an existing item (used by the clarifier UI). */
public func createClarifyForm(item: Item): ClarifyFormState {
    let form = ClarifyFormState()
    let rawContext = match (contextOf(item)) {
        case Some(value) => value
        case None => ""
    }
    var isPreset = false
    for (preset in PRESET_CONTEXTS) {
        if (preset == rawContext) {
            isPreset = true
        }
    }
    form.clarifyType = match (item.kind) {
        case ItemKind.Project => ClarifyType.Project
        case ItemKind.Reference => ClarifyType.Reference
        case ItemKind.Note => ClarifyType.Note
        case _ => ClarifyType.Next
    }
    let twoMinute = match (item.gtd) {
        case Some(gtd) => match (gtd.twoMinuteCandidate) {
            case Some(flag) => flag
            case None => false
        }
        case None => false
    }
    form.title = item.title
    form.notes = item.notes
    form.tags = joinTags(item.tags)
    form.areaId = match (item.areaId) {
        case Some(value) => value
        case None => ""
    }
    form.context = if (rawContext.isEmpty()) {
        ""
    } else if (isPreset) {
        rawContext
    } else {
        "__custom__"
    }
    form.customContext = if (rawContext.isEmpty() || isPreset) {
        ""
    } else {
        rawContext
    }
    form.energy = match (item.gtd) {
        case Some(gtd) => match (gtd.energy) {
            case Some(value) => value
            case None => Energy.Medium
        }
        case None => Energy.Medium
    }
    form.estimateMin = if (twoMinute) {
        Some(2)
    } else {
        None
    }
    form.dueDate = match (item.dueKey()) {
        case Some(value) => value
        case None => ""
    }
    form.delegated = item.status == ItemStatus.Waiting
    form.waitingFor = match (item.gtd) {
        case Some(gtd) => match (gtd.waitingFor) {
            case Some(value) => value
            case None => ""
        }
        case None => ""
    }
    form.someday = item.status == ItemStatus.Someday
    form.twoMinuteCandidate = twoMinute
    form
}
