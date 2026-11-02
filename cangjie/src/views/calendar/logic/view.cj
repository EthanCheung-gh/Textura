package textura.views.calendar.logic

import std.collection.*

/**
 * 面向渲染的日历模型：月网格 6×7 的 `DayCell`、周视图 7 列的 `DayColumn`。
 *
 * 所有函数都是纯函数：输入条目集合 + `today` + `selected`（都是 `YYYY-MM-DD`），
 * 输出可直接喂给 CUI 渲染层；不读系统时钟。
 */

/** 月网格单元格最多显示几个条目圆点（其余折叠为 `+n`）。 */
public let MONTH_VISIBLE_ITEMS: Int64 = 3

/** 月网格的一格（已含农历标签、条目与折叠计数）。 */
public struct DayCell <: Equatable<DayCell> {
    public let ymd: Ymd
    /** 是否属于当前展示月。 */
    public let inMonth: Bool
    /** 是否周末（周六 / 周日）。 */
    public let weekend: Bool
    /** 0 = 周一 … 6 = 周日。 */
    public let weekday: Int64
    /** 农历标签文本（节日 / 节气 / 农历日 / 初一显示月名；超出范围为空串）。 */
    public let lunarText: String
    public let lunarKind: LunarLabelKind
    /** 当日是否传统节日（含除夕、清明）。 */
    public let isFestival: Bool
    /** 当日是否节气。 */
    public let isSolarTerm: Bool
    public let isToday: Bool
    public let isSelected: Bool
    /** 当日全部条目（已排序）。 */
    public let items: Array<CalItem>
    /** 前 `MONTH_VISIBLE_ITEMS` 个条目（渲染圆点用）。 */
    public let visibleItems: Array<CalItem>
    public let itemCount: Int64
    /** 折叠计数：`max(0, itemCount - MONTH_VISIBLE_ITEMS)`。 */
    public let overflowCount: Int64
    /** 无障碍名称。 */
    public let ariaLabel: String

    public init(
        ymd: Ymd,
        inMonth: Bool,
        weekend: Bool,
        weekday: Int64,
        lunarText: String,
        lunarKind: LunarLabelKind,
        isFestival: Bool,
        isSolarTerm: Bool,
        isToday: Bool,
        isSelected: Bool,
        items: Array<CalItem>,
        visibleItems: Array<CalItem>,
        itemCount: Int64,
        overflowCount: Int64,
        ariaLabel: String
    ) {
        this.ymd = ymd
        this.inMonth = inMonth
        this.weekend = weekend
        this.weekday = weekday
        this.lunarText = lunarText
        this.lunarKind = lunarKind
        this.isFestival = isFestival
        this.isSolarTerm = isSolarTerm
        this.isToday = isToday
        this.isSelected = isSelected
        this.items = items
        this.visibleItems = visibleItems
        this.itemCount = itemCount
        this.overflowCount = overflowCount
        this.ariaLabel = ariaLabel
    }

    public func key(): String {
        return ymd.key()
    }

    public operator func ==(other: DayCell): Bool {
        return ymd == other.ymd && itemCount == other.itemCount
    }

    public operator func !=(other: DayCell): Bool {
        return !(this == other)
    }
}

/** 周视图里的一列（一天）。 */
public struct DayColumn <: Equatable<DayColumn> {
    public let ymd: Ymd
    /** 0 = 周一 … 6 = 周日。 */
    public let weekday: Int64
    public let weekend: Bool
    public let lunarText: String
    public let lunarKind: LunarLabelKind
    public let isToday: Bool
    public let isSelected: Bool
    /** 无障碍名称：`星期三 10月21日`。 */
    public let ariaLabel: String
    /** 当日条目卡片（已排序）。 */
    public let entries: Array<DayEntry>

    public init(
        ymd: Ymd,
        weekday: Int64,
        weekend: Bool,
        lunarText: String,
        lunarKind: LunarLabelKind,
        isToday: Bool,
        isSelected: Bool,
        ariaLabel: String,
        entries: Array<DayEntry>
    ) {
        this.ymd = ymd
        this.weekday = weekday
        this.weekend = weekend
        this.lunarText = lunarText
        this.lunarKind = lunarKind
        this.isToday = isToday
        this.isSelected = isSelected
        this.ariaLabel = ariaLabel
        this.entries = entries
    }

    public func key(): String {
        return ymd.key()
    }

    public operator func ==(other: DayColumn): Bool {
        return ymd == other.ymd && entries.size == other.entries.size
    }

    public operator func !=(other: DayColumn): Bool {
        return !(this == other)
    }
}

/** 周视图里的一张条目卡片。 */
public struct DayEntry <: Equatable<DayEntry> {
    public let item: CalItem
    /** 跨天条目的第几天（1 起）；不在区间内为 0。 */
    public let dayIndex: Int64
    /** 跨天条目总天数（单日为 1）。 */
    public let dayCount: Int64
    /** `第 n/m 天` / `截止` / 空串。 */
    public let spanText: String
    public let isDone: Bool

    public init(item: CalItem, dayIndex: Int64, dayCount: Int64, spanText: String, isDone: Bool) {
        this.item = item
        this.dayIndex = dayIndex
        this.dayCount = dayCount
        this.spanText = spanText
        this.isDone = isDone
    }

    public operator func ==(other: DayEntry): Bool {
        return item.id == other.item.id && dayIndex == other.dayIndex
    }

    public operator func !=(other: DayEntry): Bool {
        return !(this == other)
    }
}

/**
 * 月视图：先按 6×7 网格算出 42 天，再用条目填充每格。
 *
 * `items` 会被内部裁到网格区间并过滤 `dropped`，等价 TS 的
 * `visibleItems(scheduledItemsInRange(...))` + `bucketItemsByDay(...)`。
 */
public func buildMonthView(
    year: Int64,
    month: Int64,
    items: Array<CalItem>,
    today: String,
    selected: String
): Array<Array<DayCell>> {
    let grid = buildMonthGrid(year, month)
    if (grid.size == 0) {
        return Array<Array<DayCell>>()
    }
    let buckets = bucketItemsByDay(
        calendarItemsInRange(items, grid[0].key, grid[grid.size - 1].key),
        grid[0].key,
        grid[grid.size - 1].key
    )
    let rows = Array<Array<DayCell>>(6, repeat: Array<DayCell>())
    for (row in 0..6) {
        let columns = Array<DayCell>(7, repeat: emptyCell())
        for (column in 0..7) {
            let cell = grid[row * 7 + column]
            columns[column] = makeDayCell(cell, buckets, today, selected)
        }
        rows[row] = columns
    }
    return rows
}

/** 月视图（扁平 42 格版本，便于键盘导航按下标取格）。 */
public func buildMonthViewFlat(
    year: Int64,
    month: Int64,
    items: Array<CalItem>,
    today: String,
    selected: String
): Array<DayCell> {
    let rows = buildMonthView(year, month, items, today, selected)
    if (rows.size == 0) {
        return Array<DayCell>()
    }
    let flat = Array<DayCell>(42, repeat: rows[0][0])
    for (row in 0..6) {
        for (column in 0..7) {
            flat[row * 7 + column] = rows[row][column]
        }
    }
    return flat
}

/** 周视图：以 `anchorKey` 所在周的周一为首列，共 7 列。 */
public func buildWeekView(
    anchorKey: String,
    items: Array<CalItem>,
    today: String,
    selected: String
): Array<DayColumn> {
    let days = weekDays(anchorKey)
    if (days.size == 0) {
        return Array<DayColumn>()
    }
    let buckets = bucketItemsByDay(
        calendarItemsInRange(items, days[0].key, days[days.size - 1].key),
        days[0].key,
        days[days.size - 1].key
    )
    let columns = Array<DayColumn>(7, repeat: emptyColumn())
    for (index in 0..7) {
        let day = days[index]
        let dayItems = bucketOf(buckets, day.key)
        let label = lunarLabelInfo(day.key)
        let entries = Array<DayEntry>(dayItems.size, repeat: emptyEntry())
        for (position in 0..dayItems.size) {
            let item = dayItems[position]
            let span = itemSpan(item)
            let dayCount = if (span.isSome()) {
                span.getOrThrow().days
            } else {
                1
            }
            entries[position] = DayEntry(
                item,
                spanDayIndex(item, day.key),
                dayCount,
                spanText(item, day.key),
                isDoneItem(item)
            )
        }
        columns[index] = DayColumn(
            Ymd(day.year, day.month, day.day),
            index,
            index >= 5,
            label.text,
            label.kind,
            day.key == today,
            day.key == selected,
            "${weekdayLabel(day.key)} ${day.month.toString()}月${day.day.toString()}日",
            entries
        )
    }
    return columns
}

func makeDayCell(
    cell: MonthCell,
    buckets: HashMap<String, Array<CalItem>>,
    today: String,
    selected: String
): DayCell {
    let dayItems = bucketOf(buckets, cell.key)
    let lunar = lunarOf(cell.key)
    let label = lunarLabelOf(lunar)
    let isFestival = if (lunar.isSome()) {
        lunar.getOrThrow().festival.isSome()
    } else {
        false
    }
    let isSolarTerm = if (lunar.isSome()) {
        lunar.getOrThrow().solarTerm.isSome()
    } else {
        false
    }
    let visibleCount = if (dayItems.size < MONTH_VISIBLE_ITEMS) {
        dayItems.size
    } else {
        MONTH_VISIBLE_ITEMS
    }
    let visible = Array<CalItem>(visibleCount, repeat: emptyItem())
    for (index in 0..visibleCount) {
        visible[index] = dayItems[index]
    }
    return DayCell(
        Ymd(cell.year, cell.month, cell.day),
        cell.inMonth,
        cell.weekend,
        cell.weekday,
        label.text,
        label.kind,
        isFestival,
        isSolarTerm,
        cell.key == today,
        cell.key == selected,
        dayItems,
        visible,
        dayItems.size,
        dayItems.size - visibleCount,
        cellAriaLabelOf(cell.key, lunar, today)
    )
}

func bucketOf(buckets: HashMap<String, Array<CalItem>>, key: String): Array<CalItem> {
    match (buckets.get(key)) {
        case Some(list) => return list
        case None => return Array<CalItem>()
    }
}

func emptyItem(): CalItem {
    return CalItem("", "", "", "", "", "", "", false)
}

func emptyEntry(): DayEntry {
    return DayEntry(emptyItem(), 0, 1, "", false)
}

func emptyCell(): DayCell {
    return DayCell(
        Ymd(0, 0, 0),
        false,
        false,
        0,
        "",
        LunarLabelKind.NoLabel,
        false,
        false,
        false,
        false,
        Array<CalItem>(),
        Array<CalItem>(),
        0,
        0,
        ""
    )
}

func emptyColumn(): DayColumn {
    return DayColumn(
        Ymd(0, 0, 0),
        0,
        false,
        "",
        LunarLabelKind.NoLabel,
        false,
        false,
        "",
        Array<DayEntry>()
    )
}
