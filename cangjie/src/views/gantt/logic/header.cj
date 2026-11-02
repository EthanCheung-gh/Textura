package textura.views.gantt.logic

import std.collection.*

/**
 * 两级表头与刻度：
 * - day / week → 上层「月」，下层「每日」/「每周」；
 * - month → 上层「季度」，下层「1 / 8 / 15 / 22 / 29」七天段。
 * 语义对齐 TS `buildHeader` / `monthGroups` / `quarterGroups` / `*Columns`。
 */
let WEEKDAY_LABELS: Array<String> = ["日", "一", "二", "三", "四", "五", "六"]

/** 裁剪矩形（内部使用）。 */
struct Rect {
    let x: Float64
    let width: Float64

    init(x: Float64, width: Float64) {
        this.x = x
        this.width = width
    }
}

func dayOr(key: String, fallback: Int64): Int64 {
    match (parseDateKey(key)) {
        case Some(number) => number
        case None => fallback
    }
}

func dayOfMonthOf(number: Int64): Int64 {
    let (_, _, day) = civilFromDayNumber(number)
    day
}

func monthOf(number: Int64): Int64 {
    let (_, month, _) = civilFromDayNumber(number)
    month
}

func yearOf(number: Int64): Int64 {
    let (year, _, _) = civilFromDayNumber(number)
    year
}

func clipRect(range: DateRange, start: String, end: String, pxPerDay: Float64): Rect {
    let from = if (start < range.start) {
        range.start
    } else {
        start
    }
    let to = if (end > range.end) {
        range.end
    } else {
        end
    }
    if (from > to) {
        return Rect(0.0, 0.0)
    }
    Rect(
        Float64(diffDays(range.start, from)) * pxPerDay,
        Float64(diffDays(from, to) + 1) * pxPerDay
    )
}

/** 月分组：每年第一个月与首个分组补年份。 */
func monthGroups(range: DateRange, pxPerDay: Float64): Array<HeaderGroup> {
    let groups = ArrayList<HeaderGroup>()
    let startDay = dayOr(range.start, 0)
    let lastDay = dayOr(range.end, startDay)
    var cursor = dayOr(startOfMonthKey(range.start), startDay)
    let last = dayOr(endOfMonthKey(range.end), lastDay)
    while (cursor <= last) {
        let year = yearOf(cursor)
        let month = monthOf(cursor)
        let monthEnd = dayNumber(year, month, daysInMonth(year, month))
        let rect = clipRect(range, formatDateKey(cursor), formatDateKey(monthEnd), pxPerDay)
        let isFirst = groups.size == 0
        let label = if (month == 1 || isFirst) {
            "${year}年${month}月"
        } else {
            "${month}月"
        }
        groups.add(HeaderGroup("${pad(year, 4)}-${pad(month, 2)}", label, rect.x, rect.width))
        cursor = monthEnd + 1
    }
    groups.toArray()
}

/** 季度分组：`2026 Q2`。 */
func quarterGroups(range: DateRange, pxPerDay: Float64): Array<HeaderGroup> {
    let groups = ArrayList<HeaderGroup>()
    let startDay = dayOr(range.start, 0)
    let lastDay = dayOr(range.end, startDay)
    var cursor = dayOr(startOfQuarterKey(range.start), startDay)
    let last = dayOr(startOfQuarterKey(range.end), lastDay)
    while (cursor <= last) {
        let year = yearOf(cursor)
        let month = monthOf(cursor)
        let lastMonthOfQuarter = month + 2
        let quarterEnd = dayNumber(year, lastMonthOfQuarter, daysInMonth(year, lastMonthOfQuarter))
        let rect = clipRect(range, formatDateKey(cursor), formatDateKey(quarterEnd), pxPerDay)
        let quarter = (month - 1) / 3 + 1
        groups.add(HeaderGroup("${year}-Q${quarter}", "${year} Q${quarter}", rect.x, rect.width))
        cursor = quarterEnd + 1
    }
    groups.toArray()
}

/** 日模式：每天一列，带星期与周末标记。 */
func dayColumns(range: DateRange, pxPerDay: Float64, todayDay: Int64): Array<TimelineColumn> {
    let columns = ArrayList<TimelineColumn>()
    let startDay = dayOr(range.start, 0)
    let lastDay = dayOr(range.end, startDay)
    var cursor = startDay
    while (cursor <= lastDay) {
        let key = formatDateKey(cursor)
        let weekday = weekdayOf(cursor)
        columns.add(
            TimelineColumn(
                key,
                key,
                key,
                Float64(cursor - startDay) * pxPerDay,
                pxPerDay,
                "${dayOfMonthOf(cursor)}",
                sublabel: WEEKDAY_LABELS[weekday],
                weekend: weekday == 0 || weekday == 6,
                past: cursor < todayDay
            )
        )
        cursor += 1
    }
    columns.toArray()
}

/** 周模式：自 `range.start` 起每 7 天一列，末列按范围截断。 */
func weekColumns(range: DateRange, pxPerDay: Float64, todayDay: Int64): Array<TimelineColumn> {
    let columns = ArrayList<TimelineColumn>()
    let startDay = dayOr(range.start, 0)
    let lastDay = dayOr(range.end, startDay)
    var cursor = startDay
    while (cursor <= lastDay) {
        let rawEnd = cursor + 6
        let columnEnd = if (rawEnd > lastDay) {
            lastDay
        } else {
            rawEnd
        }
        let startKey = formatDateKey(cursor)
        columns.add(
            TimelineColumn(
                "w-${startKey}",
                startKey,
                formatDateKey(columnEnd),
                Float64(cursor - startDay) * pxPerDay,
                Float64(columnEnd - cursor + 1) * pxPerDay,
                "${monthOf(cursor)}/${dayOfMonthOf(cursor)}",
                weekend: false,
                past: columnEnd < todayDay
            )
        )
        cursor += 7
    }
    columns.toArray()
}

/** 月模式：每月按 1 / 8 / 15 / 22 / 29 切段，与月末对齐。 */
func monthColumns(range: DateRange, pxPerDay: Float64, todayDay: Int64): Array<TimelineColumn> {
    let columns = ArrayList<TimelineColumn>()
    let startDay = dayOr(range.start, 0)
    let lastDay = dayOr(range.end, startDay)
    var monthStart = dayOr(startOfMonthKey(range.start), startDay)
    let lastMonth = dayOr(startOfMonthKey(range.end), lastDay)
    while (monthStart <= lastMonth) {
        let year = yearOf(monthStart)
        let month = monthOf(monthStart)
        let monthLength = daysInMonth(year, month)
        var day = 1
        while (day <= monthLength) {
            let rawStart = dayNumber(year, month, day)
            let rawEnd = dayNumber(year, month, minInt(day + 6, monthLength))
            if (!(rawEnd < startDay) && !(rawStart > lastDay)) {
                let start = if (rawStart < startDay) {
                    startDay
                } else {
                    rawStart
                }
                let end = if (rawEnd > lastDay) {
                    lastDay
                } else {
                    rawEnd
                }
                columns.add(
                    TimelineColumn(
                        "m-${year}-${month}-${day}",
                        formatDateKey(start),
                        formatDateKey(end),
                        Float64(start - startDay) * pxPerDay,
                        Float64(end - start + 1) * pxPerDay,
                        "${day}",
                        weekend: false,
                        past: end < todayDay
                    )
                )
            }
            day += 7
        }
        monthStart = dayNumber(year, month, monthLength) + 1
    }
    columns.toArray()
}

/** 两级表头 + 时间轴总宽。`today` 决定 `past` 标记，必须由调用方给出。 */
public func buildHeader(range: DateRange, zoom: GanttZoom, today!: String): TimelineHeader {
    let config = zoomConfig(zoom)
    let todayDay = dayOr(snapKey(today, zoom), 0)
    let groups = match (zoom) {
        case GanttZoom.Month => quarterGroups(range, config.pxPerDay)
        case _ => monthGroups(range, config.pxPerDay)
    }
    let columns = match (zoom) {
        case GanttZoom.Day => dayColumns(range, config.pxPerDay, todayDay)
        case GanttZoom.Week => weekColumns(range, config.pxPerDay, todayDay)
        case GanttZoom.Month => monthColumns(range, config.pxPerDay, todayDay)
    }
    TimelineHeader(groups, columns, totalWidth(range, config.pxPerDay))
}

/** 表头压平成刻度流：先上层分组，再下层列（宽度/样式细节从 `TimelineHeader` 取）。 */
public func headerTicks(header: TimelineHeader): Array<Tick> {
    let ticks = ArrayList<Tick>()
    for (group in header.groups) {
        ticks.add(Tick(group.x, group.label, TickKind.Group))
    }
    for (column in header.columns) {
        ticks.add(Tick(column.x, column.label, TickKind.Column))
    }
    ticks.toArray()
}

/** 逐列宽度（可直接喂给 `visibleColumns`，与列 x 偏移一致）。 */
public func columnWidths(header: TimelineHeader): Array<Float64> {
    let widths = ArrayList<Float64>()
    for (column in header.columns) {
        widths.add(column.width)
    }
    widths.toArray()
}
