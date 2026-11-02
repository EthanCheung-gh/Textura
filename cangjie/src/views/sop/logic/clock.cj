/**
 * 时间纯函数：ISO-8601 解析/格式化与 Asia/Shanghai 展示。
 *
 * Web 版直接调用 `new Date(iso)` 与 `date-fns format(...)`；仓颉侧不读系统时钟，
 * `now` 一律由调用方传入（epoch 毫秒或 ISO 字符串），保证 parity 可重复。
 *
 * Asia/Shanghai 自 1991 年起无夏令时，固定 UTC+8，因此无需 tzdata。
 */
package textura.views.sop.logic

let MS_PER_SECOND: Int64 = 1000
let MS_PER_MINUTE: Int64 = 60000
let MS_PER_HOUR: Int64 = 3600000
let MS_PER_DAY: Int64 = 86400000
let SHANGHAI_OFFSET_MS: Int64 = 8 * MS_PER_HOUR

/** 向下取整的整数除法（仓颉整数除法向零截断，与 Hinnant 算法要求不同）。 */
func floorDiv(a: Int64, b: Int64): Int64 {
    var quotient = a / b
    if ((a % b != 0) && ((a < 0) != (b < 0))) {
        quotient -= 1
    }
    return quotient
}

/** 公历年月日 -> 1970-01-01 起的天数（Howard Hinnant civil_from_days 的逆）。 */
func daysFromCivil(year: Int64, month: Int64, day: Int64): Int64 {
    var y = year
    if (month <= 2) {
        y -= 1
    }
    let era = floorDiv(y, 400)
    let yearOfEra = y - era * 400
    var shiftedMonth = month - 3
    if (month <= 2) {
        shiftedMonth = month + 9
    }
    let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146097 + dayOfEra - 719468
}

/** 天数（1970-01-01 起）-> 公历年月日。 */
func civilFromDays(days: Int64): (Int64, Int64, Int64) {
    let z = days + 719468
    let era = floorDiv(z, 146097)
    let dayOfEra = z - era * 146097
    let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146096) / 365
    let yearBase = yearOfEra + era * 400
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let mp = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * mp + 2) / 5 + 1
    var month = mp - 9
    if (mp < 10) {
        month = mp + 3
    }
    var year = yearBase
    if (month <= 2) {
        year += 1
    }
    return (year, month, day)
}

func digitAt(text: String, at: Int64): ?Int64 {
    if (at < 0 || at >= text.size) {
        return None
    }
    let code = Int64(text[at])
    if (code < 48 || code > 57) {
        return None
    }
    return Some(code - 48)
}

/** 读取固定宽度的十进制数字；任一字符非数字返回 None。 */
func readDigits(text: String, start: Int64, width: Int64): ?Int64 {
    var value = 0
    for (offset in 0..width) {
        let digit = digitAt(text, start + offset)
        if (digit.isNone()) {
            return None
        }
        value = value * 10 + digit.getOrThrow()
    }
    return Some(value)
}

/**
 * 解析 ISO-8601：`YYYY-MM-DDTHH:MM:SS[.fff][Z|±HH:MM|±HHMM]`。
 *
 * 与 `new Date(iso).getTime()` 在合法输入上的结果一致；非法输入返回 None
 * （Web 版对应 `Number.isNaN(date.getTime())`）。
 */
public func parseIsoMillis(iso: String): ?Int64 {
    if (iso.size < 19) {
        return None
    }
    if (iso[4..5] != "-" || iso[7..8] != "-") {
        return None
    }
    if (iso[10..11] != "T" && iso[10..11] != " ") {
        return None
    }
    if (iso[13..14] != ":" || iso[16..17] != ":") {
        return None
    }
    let yearOpt = readDigits(iso, 0, 4)
    let monthOpt = readDigits(iso, 5, 2)
    let dayOpt = readDigits(iso, 8, 2)
    let hourOpt = readDigits(iso, 11, 2)
    let minuteOpt = readDigits(iso, 14, 2)
    let secondOpt = readDigits(iso, 17, 2)
    if (yearOpt.isNone() || monthOpt.isNone() || dayOpt.isNone()) {
        return None
    }
    if (hourOpt.isNone() || minuteOpt.isNone() || secondOpt.isNone()) {
        return None
    }
    let year = yearOpt.getOrThrow()
    let month = monthOpt.getOrThrow()
    let day = dayOpt.getOrThrow()
    let hour = hourOpt.getOrThrow()
    let minute = minuteOpt.getOrThrow()
    let second = secondOpt.getOrThrow()
    if (month < 1 || month > 12 || day < 1 || day > 31) {
        return None
    }
    if (hour > 23 || minute > 59 || second > 59) {
        return None
    }

    var cursor = 19
    var millis = 0
    if (cursor < iso.size && iso[cursor..cursor + 1] == ".") {
        var scale = 100
        cursor += 1
        while (cursor < iso.size && scale > 0) {
            let digit = digitAt(iso, cursor)
            if (digit.isNone()) {
                return None
            }
            millis += digit.getOrThrow() * scale
            scale /= 10
            cursor += 1
        }
    }

    var offsetMinutes = 0
    if (cursor >= iso.size) {
        // 无时区后缀：Web 版会按本地时区解析；本包固定按 UTC 处理。
        offsetMinutes = 0
    } else if (iso[cursor..cursor + 1] == "Z" || iso[cursor..cursor + 1] == "z") {
        cursor += 1
    } else if (iso[cursor..cursor + 1] == "+" || iso[cursor..cursor + 1] == "-") {
        let sign = if (iso[cursor..cursor + 1] == "-") {
            -1
        } else {
            1
        }
        cursor += 1
        let offsetHourOpt = readDigits(iso, cursor, 2)
        if (offsetHourOpt.isNone()) {
            return None
        }
        cursor += 2
        if (cursor < iso.size && iso[cursor..cursor + 1] == ":") {
            cursor += 1
        }
        var offsetMinute = 0
        if (cursor + 1 < iso.size) {
            let offsetMinuteOpt = readDigits(iso, cursor, 2)
            if (offsetMinuteOpt.isNone()) {
                return None
            }
            offsetMinute = offsetMinuteOpt.getOrThrow()
            cursor += 2
        }
        offsetMinutes = sign * (offsetHourOpt.getOrThrow() * 60 + offsetMinute)
    } else {
        return None
    }
    if (cursor != iso.size) {
        return None
    }

    let days = daysFromCivil(year, month, day)
    let seconds = days * 86400 + hour * 3600 + minute * 60 + second
    return Some(seconds * MS_PER_SECOND + millis - offsetMinutes * MS_PER_MINUTE)
}

func pad2(value: Int64): String {
    if (value < 10) {
        return "0${value}"
    }
    return "${value}"
}

func pad3(value: Int64): String {
    if (value < 10) {
        return "00${value}"
    }
    if (value < 100) {
        return "0${value}"
    }
    return "${value}"
}

/** epoch 毫秒 -> `YYYY-MM-DDTHH:MM:SS.mmmZ`（等价 `new Date(ms).toISOString()`）。 */
public func isoFromMillis(millis: Int64): String {
    let days = floorDiv(millis, MS_PER_DAY)
    let remainder = millis - days * MS_PER_DAY
    let (year, month, day) = civilFromDays(days)
    let hour = remainder / MS_PER_HOUR
    let minute = (remainder % MS_PER_HOUR) / MS_PER_MINUTE
    let second = (remainder % MS_PER_MINUTE) / MS_PER_SECOND
    let milli = remainder % MS_PER_SECOND
    return "${year}-${pad2(month)}-${pad2(day)}T${pad2(hour)}:${pad2(minute)}:${pad2(second)}.${pad3(milli)}Z"
}

/** epoch 毫秒 -> Asia/Shanghai 本地 `YYYY-MM-DD HH:MM`（等价 `formatDateTime`）。 */
public func formatShanghaiDateTime(millis: Int64): String {
    let local = millis + SHANGHAI_OFFSET_MS
    let days = floorDiv(local, MS_PER_DAY)
    let remainder = local - days * MS_PER_DAY
    let (year, month, day) = civilFromDays(days)
    let hour = remainder / MS_PER_HOUR
    let minute = (remainder % MS_PER_HOUR) / MS_PER_MINUTE
    return "${year}-${pad2(month)}-${pad2(day)} ${pad2(hour)}:${pad2(minute)}"
}

/** ISO 字符串 -> Asia/Shanghai 展示串；非法输入返回 `—`（与 Web 版 `formatDateTime` 一致）。 */
public func formatShanghaiDateTimeIso(iso: String): String {
    let millisOpt = parseIsoMillis(iso)
    if (millisOpt.isNone()) {
        return "—"
    }
    return formatShanghaiDateTime(millisOpt.getOrThrow())
}
