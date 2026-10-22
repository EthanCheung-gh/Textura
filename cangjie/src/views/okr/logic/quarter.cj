package textura.views.okr.logic

import std.unicode.*

/*
 * 季度数学。所有函数都是纯函数：`today` 由调用方注入（视图从 ViewContext /
 * workspace 锚点取），不读系统时钟，也不依赖时区数据库。
 */

/** 公历日期（本地日历日），对应 TS 里 `new Date(y, m, d)` 的日历部分。 */
public struct CivilDate <: Equatable<CivilDate> {
    public let year: Int64
    public let month: Int64
    public let day: Int64

    public init(year: Int64, month: Int64, day: Int64) {
        this.year = year
        this.month = month
        this.day = day
    }

    public operator func ==(that: CivilDate): Bool {
        year == that.year && month == that.month && day == that.day
    }

    public operator func !=(that: CivilDate): Bool {
        !(this == that)
    }

    public func toString(): String {
        "${year}-${pad2(month)}-${pad2(day)}"
    }
}

/** 季度区间，`start` / `end` 都是 `YYYY-MM-DD`。 */
public struct QuarterRange <: Equatable<QuarterRange> {
    public let start: String
    public let end: String

    public init(start: String, end: String) {
        this.start = start
        this.end = end
    }

    public operator func ==(that: QuarterRange): Bool {
        start == that.start && end == that.end
    }
}

private func pad2(value: Int64): String {
    if (value < 10) {
        "0" + value.toString()
    } else {
        value.toString()
    }
}

private func isLeapYear(year: Int64): Bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

/** 一个月天数；`month` 越界时返回 0。 */
public func daysInMonth(year: Int64, month: Int64): Int64 {
    match (month) {
        case 1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
        case 4 | 6 | 9 | 11 => 30
        case 2 =>
            if (isLeapYear(year)) {
                29
            } else {
                28
            }
        case _ => 0
    }
}

/** 公历日期合法性（拒绝 2/30、13 月等）。 */
public func isValidCivilDate(date: CivilDate): Bool {
    if (date.month < 1 || date.month > 12) {
        return false
    }
    if (date.day < 1) {
        return false
    }
    date.day <= daysInMonth(date.year, date.month)
}

/** 自 1970-01-01 起的天数（Howard Hinnant 的 days_from_civil，纯整数运算）。 */
public func daysFromCivil(date: CivilDate): Int64 {
    var year = date.year
    if (date.month <= 2) {
        year -= 1
    }
    let era = if (year >= 0) {
        year / 400
    } else {
        (year - 399) / 400
    }
    let yearOfEra = year - era * 400
    let monthPrime = (date.month + 9) % 12
    let dayOfYear = (153 * monthPrime + 2) / 5 + date.day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    era * 146097 + dayOfEra - 719468
}

/** 日历日之差，等价 date-fns `differenceInCalendarDays(to, from)`。 */
public func calendarDaysBetween(from: CivilDate, to: CivilDate): Int64 {
    daysFromCivil(to) - daysFromCivil(from)
}

/**
 * 解析 `YYYY-MM-DD`（date-fns `parseISO` + `dateKey` 的子集：只取前 10 个字符）。
 * 非法日期返回 None。
 */
public func parseCivilDateKey(text: String): ?CivilDate {
    let trimmed = text.trim()
    if (trimmed.size < 10) {
        return None
    }
    let runes = trimmed.toRuneArray()[0..10]
    for (index in 0..10) {
        let rune = runes[index]
        if (index == 4 || index == 7) {
            if (rune != r'-') {
                return None
            }
        } else if (rune < r'0' || rune > r'9') {
            return None
        }
    }
    let year = parseAsciiInt(runes[0..4])
    let month = parseAsciiInt(runes[5..7])
    let day = parseAsciiInt(runes[8..10])
    let date = CivilDate(year, month, day)
    if (!isValidCivilDate(date)) {
        return None
    }
    Some(date)
}

private func parseAsciiInt(runes: Array<Rune>): Int64 {
    var value = 0
    for (rune in runes) {
        value = value * 10 + Int64(UInt32(rune)) - Int64(UInt32(r'0'))
    }
    value
}

private func asciiDigitValue(rune: Rune): Int64 {
    Int64(UInt32(rune)) - Int64(UInt32(r'0'))
}

/** 严格匹配 `/^(\d{4})-Q([1-4])$/`。 */
private func parseQuarterKey(period: String): ?(Int64, Int64) {
    let runes = period.toRuneArray()
    if (runes.size != 7) {
        return None
    }
    for (index in 0..4) {
        if (runes[index] < r'0' || runes[index] > r'9') {
            return None
        }
    }
    if (runes[4] != r'-' || runes[5] != r'Q') {
        return None
    }
    if (runes[6] < r'1' || runes[6] > r'4') {
        return None
    }
    Some((parseAsciiInt(runes[0..4]), asciiDigitValue(runes[6])))
}

/** 某季度对应的 `[start, end]` 日期键；无法解析时返回 None。 */
public func quarterRange(period: String): ?QuarterRange {
    match (parseQuarterKey(period)) {
        case Some((year, quarter)) =>
            let startMonth = (quarter - 1) * 3 + 1
            let endMonth = startMonth + 2
            let start = CivilDate(year, startMonth, 1)
            let end = CivilDate(year, endMonth, daysInMonth(year, endMonth))
            Some(QuarterRange(start.toString(), end.toString()))
        case None => None
    }
}

/**
 * 季度已过百分比：季度第一天为 0，最后一天为 100，区间外夹紧到 0/100。
 * 无法解析的周期返回 0（与 TS 一致，避免 UI 崩溃）。
 */
public func quarterElapsedPercent(period: String, today: CivilDate): Float64 {
    let rangeOption = quarterRange(period)
    if (rangeOption.isNone()) {
        return 0.0
    }
    let range = rangeOption.getOrThrow()
    let startOption = parseCivilDateKey(range.start)
    let endOption = parseCivilDateKey(range.end)
    if (startOption.isNone() || endOption.isNone()) {
        return 0.0
    }
    let start = startOption.getOrThrow()
    let end = endOption.getOrThrow()
    let totalDays = calendarDaysBetween(start, end)
    let elapsedDays = calendarDaysBetween(start, today)
    if (totalDays <= 0) {
        return if (elapsedDays >= 0) {
            100.0
        } else {
            0.0
        }
    }
    let raw = Float64(elapsedDays) / Float64(totalDays) * 100.0
    let clamped = if (raw > 100.0) {
        100.0
    } else if (raw < 0.0) {
        0.0
    } else {
        raw
    }
    roundTo(clamped, digits: 1)
}

private func floorDiv(value: Int64, divisor: Int64): Int64 {
    var quotient = value / divisor
    if (value % divisor != 0 && ((value < 0) != (divisor < 0))) {
        quotient -= 1
    }
    quotient
}

private func floorMod(value: Int64, divisor: Int64): Int64 {
    value - floorDiv(value, divisor) * divisor
}

/** 季度偏移，例如 2026-Q4 + 1 -> 2027-Q1；无法解析时原样返回。 */
public func shiftQuarter(period: String, delta: Int64): String {
    let parsedOption = parseQuarterKey(period)
    if (parsedOption.isNone()) {
        return period
    }
    let (year, quarter) = parsedOption.getOrThrow()
    let index = year * 4 + (quarter - 1) + delta
    let shiftedYear = floorDiv(index, 4)
    let shiftedQuarter = floorMod(index, 4) + 1
    "${shiftedYear}-Q${shiftedQuarter}"
}

public func nextQuarter(period: String): String {
    shiftQuarter(period, 1)
}

/** '2026-Q4' -> '2026 Q4'；无法解析时原样返回。 */
public func quarterLabel(period: String): String {
    let parsedOption = parseQuarterKey(period)
    if (parsedOption.isNone()) {
        return period
    }
    let (_, quarter) = parsedOption.getOrThrow()
    String(period.toRuneArray()[0..4]) + " Q" + quarter.toString()
}
