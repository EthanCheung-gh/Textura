package textura.views.calendar.logic

/**
 * 公历日期核心：`Ymd` 值类型 + 儒略日式“日序号”换算。
 *
 * 与 `src/modules/calendar/lunar.ts` 保持一致：
 * - 日序号以 1970-01-01 = 0 为基准（与 `Date.UTC(...) / 86400000` 相同）；
 * - 日期键固定 `YYYY-MM-DD`，不做时区换算（调用方传入的已是北京时间日历日）；
 * - 不读系统时钟，也不依赖进程时区。
 *
 * 算法为 Howard Hinnant 的 days_from_civil / civil_from_days，纯整数运算，
 * 在 [0001-01-01, 9999-12-31] 上与 `Date.UTC` 逐日一致。
 */

/** 公历日期值类型。`month` / `day` 从 1 开始。 */
public struct Ymd <: Equatable<Ymd> {
    public let year: Int64
    public let month: Int64
    public let day: Int64

    public init(year: Int64, month: Int64, day: Int64) {
        this.year = year
        this.month = month
        this.day = day
    }

    /** `YYYY-MM-DD`。字段不做补位归一化（与 TS `makeKey` 一致）。 */
    public func key(): String {
        return keyOf(year, month, day)
    }

    /** 1970-01-01 = 0 的日序号。 */
    public func dayNumber(): Int64 {
        return dayNumberOf(year, month, day)
    }

    /** 0 = 周一 … 6 = 周日。 */
    public func weekday(): Int64 {
        return weekdayIndexMonday(dayNumber())
    }

    public func isWeekend(): Bool {
        return weekday() >= 5
    }

    /** 加天数（跨月 / 跨年安全）。 */
    public func addingDays(days: Int64): Ymd {
        return ymdOf(dayNumber() + days)
    }

    /** 所在周的周一。 */
    public func monday(): Ymd {
        return ymdOf(dayNumber() - weekday())
    }

    public func toString(): String {
        return key()
    }

    public operator func ==(other: Ymd): Bool {
        return year == other.year && month == other.month && day == other.day
    }

    public operator func !=(other: Ymd): Bool {
        return !(this == other)
    }

    public operator func <(other: Ymd): Bool {
        return compareTo(other) < 0
    }

    public operator func <=(other: Ymd): Bool {
        return compareTo(other) <= 0
    }

    public operator func >(other: Ymd): Bool {
        return compareTo(other) > 0
    }

    public operator func >=(other: Ymd): Bool {
        return compareTo(other) >= 0
    }

    /** 日期序：先年、再月、再日。 */
    public func compareTo(other: Ymd): Int64 {
        if (year != other.year) {
            return year - other.year
        }
        if (month != other.month) {
            return month - other.month
        }
        return day - other.day
    }

    public func hashCode(): Int64 {
        return dayNumber()
    }
}

public func isLeapYear(year: Int64): Bool {
    return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

/**
 * 某月天数。月份按 `year*12 + month - 1` 归一化，因此 `month = 0`
 * 表示上一年 12 月、`month = 13` 表示次年 1 月 —— 与 TS
 * `new Date(Date.UTC(year, month, 0)).getUTCDate()` 的行为一致。
 */
public func daysInMonth(year: Int64, month: Int64): Int64 {
    let zeroBased = year * 12 + (month - 1)
    let realYear = floorDiv(zeroBased, 12)
    let realMonth = zeroBased - realYear * 12 + 1
    return match (realMonth) {
        case 1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
        case 4 | 6 | 9 | 11 => 30
        case _ =>
            if (isLeapYear(realYear)) {
                29
            } else {
                28
            }
    }
}

/** 向下取整的整数除法（C 语义的 `/` 向零截断，这里补齐负数分支）。 */
public func floorDiv(a: Int64, b: Int64): Int64 {
    let q = a / b
    if ((a % b != 0) && ((a < 0) != (b < 0))) {
        return q - 1
    }
    return q
}

/** 公历年月日 → 日序号（1970-01-01 = 0）。 */
public func dayNumberOf(year: Int64, month: Int64, day: Int64): Int64 {
    let y = if (month <= 2) {
        year - 1
    } else {
        year
    }
    let era = if (y >= 0) {
        y / 400
    } else {
        (y - 399) / 400
    }
    let yoe = y - era * 400
    let mp = if (month > 2) {
        month - 3
    } else {
        month + 9
    }
    let doy = (153 * mp + 2) / 5 + day - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146097 + doe - 719468
}

/** 日序号 → 公历年月日。 */
public func ymdOf(dayNumber: Int64): Ymd {
    let z = dayNumber + 719468
    let era = if (z >= 0) {
        z / 146097
    } else {
        (z - 146096) / 146097
    }
    let doe = z - era * 146097
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
    let yearOfEra = yoe + era * 400
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let day = doy - (153 * mp + 2) / 5 + 1
    let month = if (mp < 10) {
        mp + 3
    } else {
        mp - 9
    }
    let year = if (month <= 2) {
        yearOfEra + 1
    } else {
        yearOfEra
    }
    return Ymd(year, month, day)
}

/** 两位补零。 */
public func pad2(value: Int64): String {
    return value.toString().padStart(2, padding: "0")
}

/** `YYYY-MM-DD`，字段不做范围校验（与 TS `makeKey` 一致）。 */
public func keyOf(year: Int64, month: Int64, day: Int64): String {
    return "${year.toString()}-${pad2(month)}-${pad2(day)}"
}

/**
 * `YYYY-MM-DD` → `Ymd`；格式或取值非法返回 `None`。
 *
 * 与 TS `dayNumberFromKey` 等价：严格 4-2-2 位数字，`month` 1..12，
 * `day` 1..31 且不超过当月天数；另外年份 0000–0099 同样返回 `None`
 * （JS `Date.UTC` 会把 0..99 解释为 19xx，回读校验必然失败）。
 */
public func parseKey(key: String): ?Ymd {
    if (!isDateKeyShape(key)) {
        return None
    }
    let year = digitsOf(key, 0, 4)
    let month = digitsOf(key, 5, 2)
    let day = digitsOf(key, 8, 2)
    if (year < 100) {
        return None
    }
    if (month < 1 || month > 12) {
        return None
    }
    if (day < 1 || day > daysInMonth(year, month)) {
        return None
    }
    return Ymd(year, month, day)
}

/** 从 `key` 的 `start` 位置起读 `length` 个 ASCII 数字（调用方已完成形状校验）。 */
func digitsOf(key: String, start: Int64, length: Int64): Int64 {
    let bytes = key.toArray()
    var value: Int64 = 0
    for (index in start..(start + length)) {
        value = value * 10 + Int64(bytes[index] - 48)
    }
    return value
}

/** 严格 `^\d{4}-\d{2}-\d{2}$`。 */
public func isDateKeyShape(key: String): Bool {
    if (key.size != 10) {
        return false
    }
    let bytes = key.toArray()
    for (index in 0..10) {
        let byte = bytes[index]
        if (index == 4 || index == 7) {
            if (byte != 45) {
                return false
            }
            continue
        }
        if (byte < 48 || byte > 57) {
            return false
        }
    }
    return true
}

/** `YYYY-MM-DD` → 日序号；非法返回 `None`。 */
public func dayNumberOfKey(key: String): ?Int64 {
    return parseKey(key)?.dayNumber()
}

/** 日序号 → `YYYY-MM-DD`。 */
public func keyOfDayNumber(dayNumber: Int64): String {
    return ymdOf(dayNumber).key()
}

/** 日期键加 n 天（跨月 / 跨年安全）；非法输入原样返回。 */
public func addDaysToKey(key: String, days: Int64): String {
    match (dayNumberOfKey(key)) {
        case Some(dayNumber) => return keyOfDayNumber(dayNumber + days)
        case None => return key
    }
}

/** 周一为 0 的星期序号（1970-01-01 是星期四）。 */
public func weekdayIndexMonday(dayNumber: Int64): Int64 {
    return ((dayNumber + 3) % 7 + 7) % 7
}

/** 日期键的星期序号；非法输入按 TS 返回 0。 */
public func weekdayOfKey(key: String): Int64 {
    match (dayNumberOfKey(key)) {
        case Some(dayNumber) => return weekdayIndexMonday(dayNumber)
        case None => return 0
    }
}
