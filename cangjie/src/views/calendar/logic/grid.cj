package textura.views.calendar.logic

/**
 * 月网格与周区间，移植自 `src/modules/calendar/calendarLogic.ts`。
 *
 * 月网格固定 42 格（6 行 × 7 列），周一为每行首日，含上下月补位；
 * 周视图固定 7 列（周一 → 周日）。
 */

/** 月网格的一格。 */
public struct MonthCell <: Equatable<MonthCell> {
    /** `YYYY-MM-DD`。 */
    public let key: String
    public let year: Int64
    public let month: Int64
    public let day: Int64
    /** 0 = 周一 … 6 = 周日。 */
    public let weekday: Int64
    /** 是否属于当前展示月。 */
    public let inMonth: Bool
    /** 是否周末（周六 / 周日）。 */
    public let weekend: Bool

    public init(
        key: String,
        year: Int64,
        month: Int64,
        day: Int64,
        weekday: Int64,
        inMonth: Bool,
        weekend: Bool
    ) {
        this.key = key
        this.year = year
        this.month = month
        this.day = day
        this.weekday = weekday
        this.inMonth = inMonth
        this.weekend = weekend
    }

    public operator func ==(other: MonthCell): Bool {
        return key == other.key && weekday == other.weekday && inMonth == other.inMonth && weekend == other.weekend
    }

    public operator func !=(other: MonthCell): Bool {
        return !(this == other)
    }

    public func toString(): String {
        return key
    }
}

/** 所在周的周一～周日。 */
public struct WeekInfo {
    public let start: Ymd
    public let end: Ymd
    /** `start` 的年份。 */
    public let year: Int64
    /** `start` 的月份。 */
    public let month: Int64
    /** `end` 的月份（跨月判断用）。 */
    public let monthEnd: Int64

    public init(start: Ymd, end: Ymd) {
        this.start = start
        this.end = end
        this.year = start.year
        this.month = start.month
        this.monthEnd = end.month
    }
}

/** 年月（不含日）。 */
public struct YearMonth <: Equatable<YearMonth> {
    public let year: Int64
    /** 1..12 */
    public let month: Int64

    public init(year: Int64, month: Int64) {
        this.year = year
        this.month = month
    }

    public operator func ==(other: YearMonth): Bool {
        return year == other.year && month == other.month
    }

    public operator func !=(other: YearMonth): Bool {
        return !(this == other)
    }

    public func toString(): String {
        return "${year.toString()}年${month.toString()}月"
    }
}

/** 年月偏移（月份 1..12）。 */
public func shiftMonth(year: Int64, month: Int64, delta: Int64): YearMonth {
    let zeroBased = year * 12 + (month - 1) + delta
    let shiftedYear = floorDiv(zeroBased, 12)
    let shiftedMonth = zeroBased - shiftedYear * 12 + 1
    return YearMonth(shiftedYear, shiftedMonth)
}

/**
 * 固定 6×7 = 42 格的月网格（扁平数组），周一为首列，含上下月补位。
 * 月份非法时返回空数组。
 */
public func buildMonthGrid(year: Int64, month: Int64): Array<MonthCell> {
    let firstKey = keyOf(year, month, 1)
    let first = dayNumberOfKey(firstKey)
    if (first.isNone()) {
        return Array<MonthCell>()
    }
    let start = first.getOrThrow() - weekdayIndexMonday(first.getOrThrow())
    let cells = Array<MonthCell>(42, repeat: MonthCell("", 0, 0, 0, 0, false, false))
    for (index in 0..42) {
        let date = ymdOf(start + index)
        let weekday = index % 7
        cells[index] = MonthCell(
            date.key(),
            date.year,
            date.month,
            date.day,
            weekday,
            date.year == year && date.month == month,
            weekday >= 5
        )
    }
    return cells
}

/** 固定 6×7 = 42 格的月网格，按周分行（面向渲染）。 */
public func buildMonthGridRows(year: Int64, month: Int64): Array<Array<MonthCell>> {
    let cells = buildMonthGrid(year, month)
    if (cells.size == 0) {
        return Array<Array<MonthCell>>()
    }
    let rows = Array<Array<MonthCell>>(6, repeat: Array<MonthCell>())
    for (row in 0..6) {
        let week = Array<MonthCell>(7, repeat: cells[0])
        for (column in 0..7) {
            week[column] = cells[row * 7 + column]
        }
        rows[row] = week
    }
    return rows
}

/** 所在周的周一～周日；非法日期键返回自身。 */
public func weekRange(key: String): WeekInfo {
    let dayNumber = dayNumberOfKey(key)
    if (dayNumber.isNone()) {
        let fallback = Ymd(0, 0, 0)
        return WeekInfo(fallback, fallback)
    }
    let start = dayNumber.getOrThrow() - weekdayIndexMonday(dayNumber.getOrThrow())
    return WeekInfo(ymdOf(start), ymdOf(start + 6))
}

/** 周视图 7 天（周一 → 周日）。 */
public func weekDays(key: String): Array<MonthCell> {
    let range = weekRange(key)
    let cells = Array<MonthCell>(7, repeat: MonthCell("", 0, 0, 0, 0, true, false))
    let startNumber = range.start.dayNumber()
    for (index in 0..7) {
        let date = ymdOf(startNumber + index)
        cells[index] = MonthCell(date.key(), date.year, date.month, date.day, index, true, index >= 5)
    }
    return cells
}
