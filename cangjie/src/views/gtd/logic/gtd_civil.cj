package textura.views.gtd.logic

import std.unicode.*

/*
 * 固定 Asia/Shanghai（UTC+8，无夏令时）的民用日期换算。
 *
 * TS 版用 date-fns 的 `parseISO` / `format`，依赖运行环境本地时区；仓颉版把
 * 时区钉成产品约定值 Asia/Shanghai，并把「当前时刻」全部改成调用方注入，
 * 因此没有任何系统时钟依赖。算法用 Howard Hinnant 的 civil-from-days，
 * 纯整数运算，跨月/跨年/闰年都由同一公式覆盖。
 */
let SHANGHAI_OFFSET_SECONDS: Int64 = 8 * 3600
let SECONDS_PER_DAY: Int64 = 86400

/** 向负无穷取整（C 风格整除向零取整，这里补齐）。 */
func floorDiv(value: Int64, divisor: Int64): Int64 {
    var quotient = value / divisor
    if (value % divisor != 0 && ((value < 0) != (divisor < 0))) {
        quotient -= 1
    }
    quotient
}

/** 公历日期 → 距 1970-01-01 的天数。 */
func daysFromCivil(year: Int64, month: Int64, day: Int64): Int64 {
    let adjustedYear = if (month <= 2) {
        year - 1
    } else {
        year
    }
    let era = floorDiv(adjustedYear, 400)
    let yearOfEra = adjustedYear - era * 400
    let monthShift = if (month > 2) {
        month - 3
    } else {
        month + 9
    }
    let dayOfYear = (153 * monthShift + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    era * 146097 + dayOfEra - 719468
}

/** 距 1970-01-01 的天数 → 公历日期。 */
func civilFromDays(days: Int64): CivilDate {
    let shifted = days + 719468
    let era = floorDiv(shifted, 146097)
    let dayOfEra = shifted - era * 146097
    let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146096) / 365
    var year = yearOfEra + era * 400
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let monthPrime = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * monthPrime + 2) / 5 + 1
    let month = if (monthPrime < 10) {
        monthPrime + 3
    } else {
        monthPrime - 9
    }
    if (month <= 2) {
        year += 1
    }
    CivilDate(year, month, day)
}

class CivilDate {
    let year: Int64
    let month: Int64
    let day: Int64

    init(year: Int64, month: Int64, day: Int64) {
        this.year = year
        this.month = month
        this.day = day
    }
}

func pad2(value: Int64): String {
    if (value < 0) {
        return value.toString()
    }
    if (value < 10) {
        "0" + value.toString()
    } else {
        value.toString()
    }
}

func pad4(value: Int64): String {
    var text = value.toString()
    while (text.size < 4) {
        text = "0" + text
    }
    text
}

func formatDayKey(date: CivilDate): String {
    pad4(date.year) + "-" + pad2(date.month) + "-" + pad2(date.day)
}

func isDigitRune(rune: Rune): Bool {
    let codePoint = UInt32(rune)
    codePoint >= 48u32 && codePoint <= 57u32
}

func readDigits(runes: Array<Rune>, from: Int64, count: Int64): ?Int64 {
    if (from < 0 || count < 0 || from + count > runes.size) {
        return None
    }
    var value: Int64 = 0
    var index = from
    while (index < from + count) {
        let codePoint = UInt32(runes[index])
        if (codePoint < 48u32 || codePoint > 57u32) {
            return None
        }
        value = value * 10 + Int64(codePoint - 48u32)
        index += 1
    }
    Some(value)
}

/** 一个已解析的时刻：UTC 秒 + 它在 Asia/Shanghai 的日历日与钟点。 */
class Moment {
    let epochSeconds: Int64
    let dayKey: String
    let hour: Int64
    let minute: Int64

    init(epochSeconds: Int64, dayKey: String, hour: Int64, minute: Int64) {
        this.epochSeconds = epochSeconds
        this.dayKey = dayKey
        this.hour = hour
        this.minute = minute
    }
}

/**
 * 解析 ISO-8601 日期或时刻；非法输入返回 `None`（等同 date-fns 的 Invalid Date）。
 *
 * 接受：`YYYY-MM-DD`、`YYYY-MM-DDTHH:MM`、带秒/毫秒、带 `Z` 或 `±HH:MM` 偏移。
 * 不带时区的时间按 Asia/Shanghai 本地时间解释（与浏览器本地时区语义一致）。
 */
func parseMoment(value: String): ?Moment {
    let runes = value.trim().toRuneArray()
    if (runes.size < 10) {
        return None
    }
    if (runes[4] != r'-' || runes[7] != r'-') {
        return None
    }
    let yearValue = readDigits(runes, 0, 4)
    let monthValue = readDigits(runes, 5, 2)
    let dayValue = readDigits(runes, 8, 2)
    if (yearValue.isNone() || monthValue.isNone() || dayValue.isNone()) {
        return None
    }
    let year = yearValue.getOrThrow()
    let month = monthValue.getOrThrow()
    let day = dayValue.getOrThrow()
    if (month < 1 || month > 12 || day < 1 || day > 31) {
        return None
    }
    let baseDays = daysFromCivil(year, month, day)
    let civil = CivilDate(year, month, day)
    if (runes.size == 10) {
        return Moment(baseDays * SECONDS_PER_DAY - SHANGHAI_OFFSET_SECONDS, formatDayKey(civil), 0, 0)
    }
    if (runes[10] != r'T' && runes[10] != r' ') {
        return None
    }
    var index: Int64 = 11
    let hourValue = readDigits(runes, index, 2)
    index += 2
    if (hourValue.isNone() || index >= runes.size || runes[index] != r':') {
        return None
    }
    index += 1
    let minuteValue = readDigits(runes, index, 2)
    index += 2
    if (minuteValue.isNone()) {
        return None
    }
    var second: Int64 = 0
    if (index < runes.size && runes[index] == r':') {
        index += 1
        let secondValue = readDigits(runes, index, 2)
        index += 2
        if (secondValue.isNone()) {
            return None
        }
        second = secondValue.getOrThrow()
    }
    if (index < runes.size && runes[index] == r'.') {
        index += 1
        var fractionDigits: Int64 = 0
        while (index < runes.size && isDigitRune(runes[index])) {
            index += 1
            fractionDigits += 1
        }
        if (fractionDigits == 0) {
            return None
        }
    }
    // 不带时区的时间按本地（Asia/Shanghai）墙钟解释。
    var offsetSeconds = SHANGHAI_OFFSET_SECONDS
    if (index < runes.size) {
        let zone = runes[index]
        if (zone == r'Z' || zone == r'z') {
            offsetSeconds = 0
            index += 1
        } else if (zone == r'+' || zone == r'-') {
            let sign: Int64 = if (zone == r'+') {
                1
            } else {
                -1
            }
            index += 1
            let zoneHourValue = readDigits(runes, index, 2)
            index += 2
            if (zoneHourValue.isNone()) {
                return None
            }
            var zoneMinute: Int64 = 0
            if (index < runes.size && runes[index] == r':') {
                index += 1
            }
            let zoneMinuteValue = readDigits(runes, index, 2)
            if (zoneMinuteValue.isSome()) {
                zoneMinute = zoneMinuteValue.getOrThrow()
                index += 2
            }
            offsetSeconds = sign * (zoneHourValue.getOrThrow() * 3600 + zoneMinute * 60)
        } else {
            return None
        }
    }
    if (index != runes.size) {
        return None
    }
    let hour = hourValue.getOrThrow()
    let minute = minuteValue.getOrThrow()
    if (hour > 23 || minute > 59 || second > 59) {
        return None
    }
    let localSeconds = baseDays * SECONDS_PER_DAY + hour * 3600 + minute * 60 + second
    let epochSeconds = localSeconds - offsetSeconds
    let shanghaiSeconds = epochSeconds + SHANGHAI_OFFSET_SECONDS
    let shanghaiDays = floorDiv(shanghaiSeconds, SECONDS_PER_DAY)
    let remainder = shanghaiSeconds - shanghaiDays * SECONDS_PER_DAY
    Moment(
        epochSeconds,
        formatDayKey(civilFromDays(shanghaiDays)),
        remainder / 3600,
        (remainder % 3600) / 60
    )
}

func civilFromDayKey(key: String): ?CivilDate {
    let runes = key.trim().toRuneArray()
    if (runes.size != 10 || runes[4] != r'-' || runes[7] != r'-') {
        return None
    }
    let yearValue = readDigits(runes, 0, 4)
    let monthValue = readDigits(runes, 5, 2)
    let dayValue = readDigits(runes, 8, 2)
    if (yearValue.isNone() || monthValue.isNone() || dayValue.isNone()) {
        return None
    }
    let year = yearValue.getOrThrow()
    let month = monthValue.getOrThrow()
    let day = dayValue.getOrThrow()
    if (month < 1 || month > 12 || day < 1 || day > 31) {
        return None
    }
    Some(CivilDate(year, month, day))
}

/** `YYYY-MM-DD` 合法且月/日在范围内。 */
public func isValidDayKey(key: String): Bool {
    civilFromDayKey(key).isSome()
}

/**
 * ISO 时间戳或日期键 → Asia/Shanghai 本地日历日键。
 *
 * 不能用「截取前 10 位」的 `dateKey`：`2026-10-14T17:01Z` 截断得到 10-14，
 * 而上海本地是 10-15。非法输入返回 `None`。
 */
public func localDayKey(value: ?String): ?String {
    match (value) {
        case Some(raw) => match (parseMoment(raw)) {
            case Some(moment) => Some(moment.dayKey)
            case None => None
        }
        case None => None
    }
}

/** 把 ISO 时间或日期串统一成 `YYYY-MM-DD`（只截断，不校验，与 TS 同）。 */
public func dateKey(value: ?String): ?String {
    match (value) {
        case Some(raw) =>
            let trimmed = raw.trim()
            if (trimmed.size >= 10) {
                Some(trimmed[0..10])
            } else {
                None
            }
        case None => None
    }
}

/**
 * 相对某个日期键偏移若干天，返回日期键。
 *
 * `fromKey` 必须是合法日期键：TS 版的 `from` 是 `Date`，非法值不可能出现；
 * 这里显式抛异常而不是退回系统时钟。
 */
public func dayOffset(days: Int64, fromKey: String): String {
    match (civilFromDayKey(fromKey)) {
        case Some(civil) => formatDayKey(civilFromDays(daysFromCivil(civil.year, civil.month, civil.day) + days))
        case None => throw IllegalArgumentException("dayOffset: 非法日期键 " + fromKey)
    }
}

/** 两个日期键之间的本地日历天数（to - from）；任一非法返回 0。 */
public func daysBetween(fromKey: String, toKey: String): Int64 {
    let from = civilFromDayKey(fromKey)
    let to = civilFromDayKey(toKey)
    if (from.isNone() || to.isNone()) {
        return 0
    }
    let start = from.getOrThrow()
    let end = to.getOrThrow()
    daysFromCivil(end.year, end.month, end.day) - daysFromCivil(start.year, start.month, start.day)
}

/** 日期键 → `MM/dd`；非法返回 `—`。 */
public func formatMonthDay(value: ?String): String {
    let key = dateKey(value)
    match (key) {
        case Some(raw) => match (civilFromDayKey(raw)) {
            case Some(civil) => pad2(civil.month) + "/" + pad2(civil.day)
            case None => "—"
        }
        case None => "—"
    }
}

/** ISO 时刻 → Asia/Shanghai 的 `yyyy-MM-dd HH:mm`；非法返回 `—`。 */
public func formatDateTime(value: ?String): String {
    match (value) {
        case Some(raw) => match (parseMoment(raw)) {
            case Some(moment) => moment.dayKey + " " + pad2(moment.hour) + ":" + pad2(moment.minute)
            case None => "—"
        }
        case None => "—"
    }
}
