package textura.views.dashboard.logic

import std.collection.*

/** `summarizeToday` 的输入（来自计数，不重新扫描工作区）。 */
public struct TodaySummaryInput {
    public let overdue: Int64
    public let today: Int64
    public let inbox: Int64
    public let next: Int64

    public init(overdue: Int64, today: Int64, inbox: Int64, next: Int64) {
        this.overdue = overdue
        this.today = today
        this.inbox = inbox
        this.next = next
    }
}

/**
 * 一句话状态摘要：优先报超期 / 今日到期 / 收件箱，其次报下一步，最后是空状态。
 */
public func summarizeToday(input: TodaySummaryInput): String {
    let parts = ArrayList<String>()
    if (input.overdue > 0) {
        parts.add(input.overdue.toString() + " 项已超期")
    }
    if (input.today > 0) {
        parts.add(input.today.toString() + " 项今日到期")
    }
    if (input.inbox > 0) {
        parts.add("收件箱 " + input.inbox.toString() + " 条待澄清")
    }
    if (parts.size > 0) {
        return String.join(parts.toArray(), delimiter: "，") + "。"
    }
    if (input.next > 0) {
        return "今天没有硬性截止，" + input.next.toString() + " 项下一步可以先推进。"
    }
    return "今天没有待办，先收集一点想法，或者去定一个目标。"
}

/** 非空完成时间；空串与 `None` 一样视为「未完成」（等价 JS 的假值判断）。 */
func completedText(item: DashItem): ?String {
    if (isNonEmpty(item.completedAt)) {
        return item.completedAt
    }
    return None
}

/**
 * 最近 `days` 天完成的条目（按完成时间倒序）。
 *
 * 窗口按本地日历日计算：`0 <= 今天 - 完成日 < days`，即日历日差 0..days-1 计入，
 * `days` 天及更早排除；完成时间晚于「今天」的记录（差为负）也不计入。
 */
public func completedThisWeek(items: Array<DashItem>, nowIso: String, days!: Int64 = 7): Array<DashItem> {
    let nowDay = match (parseInstantMs(nowIso)) {
        case Some(epochMs) => localDayNumberOfInstant(epochMs)
        case None => return Array<DashItem>()
    }
    let matched = ArrayList<DashItem>()
    for (item in items) {
        if (let Some(text) <- completedText(item)) {
            if (let Some(epochMs) <- parseInstantMs(text)) {
                let diff = nowDay - localDayNumberOfInstant(epochMs)
                if (diff >= 0 && diff < days) {
                    matched.add(item)
                }
            }
        }
    }
    return stableSortBy<DashItem>(
        matched.toArray(),
        {left, right => return compareText(orEmpty(right.completedAt), orEmpty(left.completedAt))}
    )
}

/** 最近完成的条目（不限时间窗口），按完成时间倒序，最多 `limit` 条。 */
public func recentlyCompleted(items: Array<DashItem>, limit!: Int64 = 5): Array<DashItem> {
    let matched = ArrayList<DashItem>()
    for (item in items) {
        if (isNonEmpty(item.completedAt)) {
            matched.add(item)
        }
    }
    let ordered = stableSortBy<DashItem>(
        matched.toArray(),
        {left, right => return compareText(orEmpty(right.completedAt), orEmpty(left.completedAt))}
    )
    return takeSlice<DashItem>(ordered, limit)
}

/** `Math.round(mean(values))`；空数组为 0。 */
public func averageProgress(values: Array<Int64>): Int64 {
    if (values.size == 0) {
        return 0
    }
    var sum = 0
    for (value in values) {
        sum += value
    }
    return roundHalfUp(sum, values.size)
}

/**
 * 当前季度 OKR 平均进度。
 *
 * 调用方先用 `objectivesOfPeriod(workspace, okrPeriod)` 取当期目标，并把 `rollupProgress`
 * 写进 `okrProgress`；缺失进度按 0 计（与 Web 版 `objectives` 数组恒有进度值等价）。
 */
public func okrAverageProgress(objectives: Array<DashItem>): Int64 {
    let values = ArrayList<Int64>()
    for (objective in objectives) {
        values.add(match (objective.okrProgress) {
            case Some(progress) => progress
            case None => 0
        })
    }
    return averageProgress(values.toArray())
}
