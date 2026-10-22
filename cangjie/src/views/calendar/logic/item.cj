package textura.views.calendar.logic

import std.collection.*
import std.sort.*

/**
 * 日历条目层：输入记录、日期区间、按日分桶、当日排序、展示映射。
 * 移植自 `src/modules/calendar/calendarLogic.ts` 与 `itemDisplay.ts`。
 *
 * 本包不依赖 `textura.core.data`，只接受下面这个最小输入记录；
 * 「core.data Item → CalItem」字段映射见 `docs/CALENDAR-LOGIC.md`。
 */

/** 日历条目（纯数据，值类型）。 */
public struct CalItem <: Equatable<CalItem> {
    public let id: String
    public let title: String
    /** `objective` / `keyresult` / `project` / `action` / `sop` / `step` / `milestone` / `reference` / `note`。 */
    public let kind: String
    /** `inbox` / `next` / `active` / `waiting` / `scheduled` / `someday` / `done` / `dropped`。 */
    public let status: String
    /** 起始日 `YYYY-MM-DD`；空串表示没有起始日。 */
    public let startDate: String
    /** 结束日 `YYYY-MM-DD`；空串表示没有结束日。 */
    public let endDate: String
    /** 领域色（原样搬运 `Area.color`）；空串表示无领域。 */
    public let areaColor: String
    /** 是否里程碑（等价于 `kind == "milestone"`）。 */
    public let isMilestone: Bool

    public init(
        id: String,
        title: String,
        kind: String,
        status: String,
        startDate: String,
        endDate: String,
        areaColor: String,
        isMilestone: Bool
    ) {
        this.id = id
        this.title = title
        this.kind = kind
        this.status = status
        this.startDate = startDate
        this.endDate = endDate
        this.areaColor = areaColor
        this.isMilestone = isMilestone
    }

    public operator func ==(other: CalItem): Bool {
        return id == other.id
    }

    public operator func !=(other: CalItem): Bool {
        return id != other.id
    }

    public func toString(): String {
        return "${id}:${title}"
    }
}

/** 条目占用的日期区间。 */
public struct DayItemSpan <: Equatable<DayItemSpan> {
    public let start: Ymd
    public let end: Ymd
    /** 覆盖天数（含首尾）。 */
    public let days: Int64

    public init(start: Ymd, end: Ymd, days: Int64) {
        this.start = start
        this.end = end
        this.days = days
    }

    public operator func ==(other: DayItemSpan): Bool {
        return start == other.start && end == other.end && days == other.days
    }

    public operator func !=(other: DayItemSpan): Bool {
        return !(this == other)
    }
}

/**
 * 日期串归一化（等价 TS `core/utils.ts` 的 `dateKey`）：
 * 去首尾空白，长度 ≥ 10 时取前 10 个字符，否则返回空串。
 */
public func dateKeyOf(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.size >= 10) {
        return trimmed[0..10]
    }
    return ""
}

/**
 * 条目占用的日期区间；只有 end（GTD 截止日）时收敛为单日，反向区间自动归一化。
 * 没有可用日期时返回 `None`。
 */
public func itemSpan(item: CalItem): ?DayItemSpan {
    let rawStart = dateKeyOf(item.startDate)
    let rawEnd = dateKeyOf(item.endDate)
    let startKey = if (rawStart.size > 0) {
        rawStart
    } else {
        rawEnd
    }
    let endKey = if (rawEnd.size > 0) {
        rawEnd
    } else {
        rawStart
    }
    if (startKey.size == 0 || endKey.size == 0) {
        return None
    }
    let startDate = parseKey(startKey)
    let endDate = parseKey(endKey)
    if (startDate.isNone() || endDate.isNone()) {
        return None
    }
    let start = startDate.getOrThrow()
    let end = endDate.getOrThrow()
    if (end < start) {
        return DayItemSpan(end, start, start.dayNumber() - end.dayNumber() + 1)
    }
    return DayItemSpan(start, end, end.dayNumber() - start.dayNumber() + 1)
}

/** 第 n 天（1 起）；不在区间内返回 0。 */
public func spanDayIndex(item: CalItem, key: String): Int64 {
    let span = itemSpan(item)
    if (span.isNone()) {
        return 0
    }
    let parsed = parseKey(key)
    if (parsed.isNone()) {
        return 0
    }
    let range = span.getOrThrow()
    let index = parsed.getOrThrow().dayNumber() - range.start.dayNumber() + 1
    if (index >= 1 && index <= range.days) {
        return index
    }
    return 0
}

/**
 * 周视图条目的跨天副标题（等价 `WeekView.tsx` 的 `spanText`）：
 * 跨天 → `第 n/m 天`；只有截止日 → `截止`；否则空串。
 */
public func spanText(item: CalItem, key: String): String {
    let span = itemSpan(item)
    if (span.isNone()) {
        return ""
    }
    let range = span.getOrThrow()
    if (range.days > 1) {
        let index = spanDayIndex(item, key)
        return if (index > 0) {
            "第 ${index.toString()}/${range.days.toString()} 天"
        } else {
            ""
        }
    }
    let onlyDue = item.startDate.size == 0 && item.endDate.size > 0
    return if (onlyDue) {
        "截止"
    } else {
        ""
    }
}

/**
 * 按日分桶：跨天条目落在每个覆盖日，仅 end 的条目落在当天，边界日包含。
 * 超出 `[from, to]` 的部分被裁剪；`from > to` 自动交换。
 */
public func bucketItemsByDay(
    items: Array<CalItem>,
    from: String,
    to: String
): HashMap<String, Array<CalItem>> {
    let buckets = HashMap<String, Array<CalItem>>()
    let rawStart = dateKeyOf(from)
    let rawEnd = dateKeyOf(to)
    if (rawStart.size == 0 || rawEnd.size == 0) {
        return buckets
    }
    var startKey = rawStart
    var endKey = rawEnd
    if (startKey > endKey) {
        let swap = startKey
        startKey = endKey
        endKey = swap
    }
    let lower = parseKey(startKey)
    let upper = parseKey(endKey)
    if (lower.isNone() || upper.isNone()) {
        return buckets
    }
    let lowerYmd = lower.getOrThrow()
    let upperYmd = upper.getOrThrow()

    let grouped = HashMap<String, ArrayList<CalItem>>()
    for (item in items) {
        let span = itemSpan(item)
        if (span.isNone()) {
            continue
        }
        let range = span.getOrThrow()
        let visibleStart = if (range.start < lowerYmd) {
            lowerYmd
        } else {
            range.start
        }
        let visibleEnd = if (range.end > upperYmd) {
            upperYmd
        } else {
            range.end
        }
        if (visibleEnd < visibleStart) {
            continue
        }
        let firstNumber = visibleStart.dayNumber()
        let lastNumber = visibleEnd.dayNumber()
        for (dayNumber in firstNumber..=lastNumber) {
            let dayKey = keyOfDayNumber(dayNumber)
            match (grouped.get(dayKey)) {
                case Some(list) => list.add(item)
                case None =>
                    let created = ArrayList<CalItem>()
                    created.add(item)
                    grouped[dayKey] = created
            }
        }
    }

    for ((dayKey, list) in grouped) {
        buckets[dayKey] = sortDayItems(list.toArray())
    }
    return buckets
}

/**
 * 当日条目排序：全天 / 跨天优先 → 开始日期 → 标题。
 *
 * 同一天内单日条目按标题排序（模型没有时刻字段）。排序稳定：
 * 完全相同时保持输入顺序（与 JS `Array.prototype.sort` 的稳定性一致）。
 * 标题比较使用码点序；TS 版本用 `localeCompare('zh-Hans-CN')`（拼音序），
 * 两者仅在纯中文标题的相对顺序上可能不同 —— 见 `docs/CALENDAR-LOGIC.md`。
 */
public func sortDayItems(items: Array<CalItem>): Array<CalItem> {
    if (items.size == 0) {
        return Array<CalItem>()
    }
    let decorated = ArrayList<(Int64, CalItem)>()
    for (index in 0..items.size) {
        decorated.add((index, items[index]))
    }
    let pairs = decorated.toArray()
    sort<(Int64, CalItem)>(
        pairs,
        lessThan: {
            left, right =>
                let leftRank = sortRank(left[1])
                let rightRank = sortRank(right[1])
                if (leftRank != rightRank) {
                    return leftRank < rightRank
                }
                let leftStart = startKeyOf(left[1])
                let rightStart = startKeyOf(right[1])
                if (leftStart != rightStart) {
                    return leftStart < rightStart
                }
                if (left[1].title != right[1].title) {
                    return left[1].title < right[1].title
                }
                return left[0] < right[0]
        }
    )
    let sorted = Array<CalItem>(pairs.size, repeat: items[0])
    for (index in 0..pairs.size) {
        sorted[index] = pairs[index][1]
    }
    return sorted
}

func sortRank(item: CalItem): Int64 {
    let span = itemSpan(item)
    if (span.isSome() && span.getOrThrow().days > 1) {
        return 0
    }
    return 1
}

func startKeyOf(item: CalItem): String {
    match (itemSpan(item)) {
        case Some(span) => return span.start.key()
        case None => return ""
    }
}

/** 过滤已放弃条目（done 保留）。 */
public func visibleItems(items: Array<CalItem>): Array<CalItem> {
    let kept = ArrayList<CalItem>()
    for (item in items) {
        if (item.status != "dropped") {
            kept.add(item)
        }
    }
    return kept.toArray()
}

/**
 * 日历页使用的条目集合：已排期（有起止日）且未放弃，并裁剪到 `[from, to]`。
 * 等价 `visibleItems(scheduledItemsInRange(workspace, from, to))`。
 */
public func calendarItemsInRange(
    items: Array<CalItem>,
    from: String,
    to: String
): Array<CalItem> {
    let lower = dateKeyOf(from)
    let upper = dateKeyOf(to)
    if (lower.size == 0 || upper.size == 0) {
        return Array<CalItem>()
    }
    let low = if (lower < upper) {
        lower
    } else {
        upper
    }
    let high = if (lower < upper) {
        upper
    } else {
        lower
    }
    let lowDay = parseKey(low)
    let highDay = parseKey(high)
    if (lowDay.isNone() || highDay.isNone()) {
        return Array<CalItem>()
    }
    let lowNumber = lowDay.getOrThrow().dayNumber()
    let highNumber = highDay.getOrThrow().dayNumber()
    let kept = ArrayList<CalItem>()
    for (item in items) {
        if (item.status == "dropped") {
            continue
        }
        let span = itemSpan(item)
        if (span.isNone()) {
            continue
        }
        let range = span.getOrThrow()
        if (range.start.dayNumber() <= highNumber && range.end.dayNumber() >= lowNumber) {
            kept.add(item)
        }
    }
    return kept.toArray()
}

public func isDoneItem(item: CalItem): Bool {
    return item.status == "done"
}

/** 状态中文标签；未知状态返回空串（等价 TS 取到 `undefined`）。 */
public func statusLabel(status: String): String {
    return match (status) {
        case "inbox" => "收件箱"
        case "next" => "下一步"
        case "active" => "进行中"
        case "waiting" => "等待中"
        case "scheduled" => "已排期"
        case "someday" => "将来"
        case "done" => "已完成"
        case "dropped" => "已放弃"
        case _ => ""
    }
}

/**
 * 状态语义色调：`ok` / `warn` / `danger` / `info` / `accent` / `neutral`。
 *
 * TS 版本 `statusColor` 返回 CSS 变量名（`var(--ok)` 等），语义与这里的色调一一对应；
 * 仓颉侧由渲染层把色调映射到 `textura.ui` 的设计令牌，不使用 CSS 变量。
 */
public func statusTone(status: String): String {
    return match (status) {
        case "done" => "ok"
        case "waiting" => "warn"
        case "dropped" => "danger"
        case "scheduled" => "info"
        case "active" => "accent"
        case _ => "neutral"
    }
}

/** 状态点颜色令牌名（`ok` / `warn` / …；无状态时 `text-faint`）。 */
public func statusColorToken(status: String): String {
    return match (status) {
        case "done" => "ok"
        case "waiting" => "warn"
        case "dropped" => "danger"
        case "scheduled" => "info"
        case "active" => "accent"
        case _ => "text-faint"
    }
}

/** 条目类型的图标名（`target` / `folder` / `clock` / `workflow` / `flag` / `link` / `edit`）。 */
public func kindIcon(kind: String): String {
    return match (kind) {
        case "objective" | "keyresult" => "target"
        case "project" => "folder"
        case "action" => "clock"
        case "sop" | "step" => "workflow"
        case "milestone" => "flag"
        case "reference" => "link"
        case _ => "edit"
    }
}

/** 条目类型点击后应跳转的路由（`gantt` / `sop` / `okr` / `gtd`）。 */
public func routeForKind(kind: String): String {
    return match (kind) {
        case "project" | "action" | "milestone" => "gantt"
        case "sop" | "step" => "sop"
        case "objective" | "keyresult" => "okr"
        case _ => "gtd"
    }
}

/** 领域色：无领域时返回空串，由渲染层回退到 `text-faint` 令牌。 */
public func areaColorOf(item: CalItem): String {
    return item.areaColor
}
