package textura.views.gantt.logic

import std.collection.*

/**
 * 日期层：儒略日整数运算。
 *
 * 表示法：`Int64` 天序号 = 1970-01-01 起算的公历（proleptic Gregorian）天数，
 * 也就是偏移量固定为 2440588 的儒略日（JDN）。刻意不用“毫秒 + 时区”：
 * 日历差、星期、月初/月末全部是整数运算，DST 与时区切换不会造成列宽或拖拽偏移。
 * 输入输出一律 `YYYY-MM-DD` 日期键，不引入任何时钟。
 */
public func isLeapYear(year: Int64): Bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

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

/** `(year, month, day)` → 天序号（Howard Hinnant 的 `days_from_civil`）。 */
public func dayNumber(year: Int64, month: Int64, day: Int64): Int64 {
    var y = year
    if (month <= 2) {
        y -= 1
    }
    let era = if (y >= 0) {
        y / 400
    } else {
        (y - 399) / 400
    }
    let yearOfEra = y - era * 400
    let shiftedMonth = if (month > 2) {
        month - 3
    } else {
        month + 9
    }
    let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    era * 146097 + dayOfEra - 719468
}

/** 天序号 → `(year, month, day)`。 */
public func civilFromDayNumber(number: Int64): (Int64, Int64, Int64) {
    let shifted = number + 719468
    let era = if (shifted >= 0) {
        shifted / 146097
    } else {
        (shifted - 146096) / 146097
    }
    let dayOfEra = shifted - era * 146097
    let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146096) / 365
    var year = yearOfEra + era * 400
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let shiftedMonth = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
    let month = if (shiftedMonth < 10) {
        shiftedMonth + 3
    } else {
        shiftedMonth - 9
    }
    if (month <= 2) {
        year += 1
    }
    (year, month, day)
}

/** 星期几，0 = 周日（与 `Date.prototype.getDay` 一致）。 */
public func weekdayOf(number: Int64): Int64 {
    let raw = (number + 4) % 7
    if (raw < 0) {
        raw + 7
    } else {
        raw
    }
}

/** `%` 的数学取模（结果非负）；仓颉 `%` 与 C 一样跟随被除数符号。 */
public func floorMod(value: Int64, modulus: Int64): Int64 {
    let raw = value % modulus
    if (raw < 0) {
        raw + modulus
    } else {
        raw
    }
}

func digitAt(key: String, index: Int64): ?Int64 {
    let byte = key[index]
    if (byte >= 48 && byte <= 57) {
        Some(Int64(byte) - 48)
    } else {
        None
    }
}

/** 严格解析 `YYYY-MM-DD`（月/日越界、月份长度不符都返回 None）。 */
public func parseDateKey(key: String): ?Int64 {
    if (!looksLikeDateKey(key)) {
        return None
    }
    let digits = ArrayList<Int64>()
    for (index in 0..10) {
        if (index == 4 || index == 7) {
            continue
        }
        match (digitAt(key, index)) {
            case Some(value) => digits.add(value)
            case None => return None
        }
    }
    let year = digits[0] * 1000 + digits[1] * 100 + digits[2] * 10 + digits[3]
    let month = digits[4] * 10 + digits[5]
    let day = digits[6] * 10 + digits[7]
    if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) {
        return None
    }
    Some(dayNumber(year, month, day))
}

/** `YYYY-MM-DD` 形状判断（只看形状，不看月/日是否越界），与 TS 的 `/^\d{4}-\d{2}-\d{2}$/` 同义。 */
public func looksLikeDateKey(key: String): Bool {
    if (key.size != 10 || key[4] != 45 || key[7] != 45) {
        return false
    }
    for (index in 0..10) {
        if (index == 4 || index == 7) {
            continue
        }
        if (digitAt(key, index).isNone()) {
            return false
        }
    }
    true
}

func pad(value: Int64, width: Int64): String {
    var text = "${value}"
    while (text.size < width) {
        text = "0" + text
    }
    text
}

/** 天序号 → `YYYY-MM-DD`（支持 0000..9999 年；其余范围退化为不补零）。 */
public func formatDateKey(number: Int64): String {
    let (year, month, day) = civilFromDayNumber(number)
    "${pad(year, 4)}-${pad(month, 2)}-${pad(day, 2)}"
}

/**
 * 复刻 Web 版 `dateKey`：去空白后取前 10 个字符（不校验合法性）。
 * 空串 / 不足 10 字符返回 None。
 */
public func dateKeyOf(raw: String): ?String {
    let trimmed = raw.trimAscii()
    if (trimmed.size >= 10) {
        Some(trimmed[0..10].toString())
    } else {
        None
    }
}

/** 原始串（日期键或 ISO 时间戳）→ 天序号。 */
public func dayNumberOf(raw: String): ?Int64 {
    match (dateKeyOf(raw)) {
        case Some(key) => parseDateKey(key)
        case None => None
    }
}

/** `value` 是否是可被本包识别的日期键。 */
public func isDateKey(value: String): Bool {
    match (parseDateKey(value)) {
        case Some(_) => true
        case None => false
    }
}

/** 复刻 `toKey`：已是 `YYYY-MM-DD` 形状原样返回，否则规范化；无法解析返回空串。 */
public func toKey(value: String): String {
    if (looksLikeDateKey(value)) {
        return value
    }
    match (dayNumberOf(value)) {
        case Some(number) => formatDateKey(number)
        case None => ""
    }
}

/** `key` 加/减天数。 */
public func addDaysKey(key: String, days: Int64): String {
    match (parseDateKey(key)) {
        case Some(number) => formatDateKey(number + days)
        case None => ""
    }
}

/** `b - a`，按日历天。 */
public func diffDays(a: String, b: String): Int64 {
    match (parseDateKey(a)) {
        case Some(from) => match (parseDateKey(b)) {
            case Some(to) => to - from
            case None => 0
        }
        case None => 0
    }
}

public func yearOfKey(key: String): Int64 {
    match (parseDateKey(key)) {
        case Some(number) =>
            let (year, _, _) = civilFromDayNumber(number)
            year
        case None => 0
    }
}

public func monthOfKey(key: String): Int64 {
    match (parseDateKey(key)) {
        case Some(number) =>
            let (_, month, _) = civilFromDayNumber(number)
            month
        case None => 0
    }
}

public func dayOfMonthOfKey(key: String): Int64 {
    match (parseDateKey(key)) {
        case Some(number) =>
            let (_, _, day) = civilFromDayNumber(number)
            day
        case None => 0
    }
}

/** 所在周的周一（`weekStartsOn: 1`）。 */
public func startOfWeekKey(key: String): String {
    match (parseDateKey(key)) {
        case Some(number) => formatDateKey(number - floorMod(weekdayOf(number) + 6, 7))
        case None => ""
    }
}

/** 所在周的周日。 */
public func endOfWeekKey(key: String): String {
    match (parseDateKey(startOfWeekKey(key))) {
        case Some(number) => formatDateKey(number + 6)
        case None => ""
    }
}

public func startOfMonthKey(key: String): String {
    match (parseDateKey(key)) {
        case Some(number) =>
            let (_, _, day) = civilFromDayNumber(number)
            formatDateKey(number - (day - 1))
        case None => ""
    }
}

public func endOfMonthKey(key: String): String {
    match (parseDateKey(key)) {
        case Some(number) =>
            let (year, month, day) = civilFromDayNumber(number)
            formatDateKey(number + (daysInMonth(year, month) - day))
        case None => ""
    }
}

/** 季度首日（1/4/7/10 月 1 日）。 */
public func startOfQuarterKey(key: String): String {
    match (parseDateKey(key)) {
        case Some(number) =>
            let (year, month, _) = civilFromDayNumber(number)
            let quarterMonth = (month - 1) / 3 * 3 + 1
            formatDateKey(dayNumber(year, quarterMonth, 1))
        case None => ""
    }
}

/** 季度末日。 */
public func endOfQuarterKey(key: String): String {
    match (parseDateKey(startOfQuarterKey(key))) {
        case Some(number) =>
            let (year, month, _) = civilFromDayNumber(number)
            let lastQuarterMonth = month + 2
            formatDateKey(dayNumber(year, lastQuarterMonth, daysInMonth(year, lastQuarterMonth)))
        case None => ""
    }
}

/** 季度序号 1..4。 */
public func quarterOfKey(key: String): Int64 {
    (monthOfKey(key) - 1) / 3 + 1
}
