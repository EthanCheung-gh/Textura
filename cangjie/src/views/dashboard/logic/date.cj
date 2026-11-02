package textura.views.dashboard.logic

/**
 * 纯日期工具：不读系统时钟、不依赖 std.time 时区库。
 *
 * 项目固定时区 `Asia/Shanghai`（1981 年后无夏令时，恒定 UTC+08:00），因此把「本地时间」
 * 定义为 UTC+8 算术：既能复现 Web 版 `date-fns` 的本地日历语义，也让结果与运行环境无关。
 */
const SHANGHAI_OFFSET_MINUTES: Int64 = 480
const MS_PER_MINUTE: Int64 = 60_000
const MS_PER_DAY: Int64 = 86_400_000

/** 公历日期（`month` 从 1 开始）。 */
struct CivilDate {
    let year: Int64
    let month: Int64
    let day: Int64

    init(year: Int64, month: Int64, day: Int64) {
        this.year = year
        this.month = month
        this.day = day
    }
}

/** 本地（UTC+8）日期时间。 */
struct LocalDateTime {
    let date: CivilDate
    let hour: Int64
    let minute: Int64
    let second: Int64
    let milli: Int64

    init(date: CivilDate, hour: Int64, minute: Int64, second: Int64, milli: Int64) {
        this.date = date
        this.hour = hour
        this.minute = minute
        this.second = second
        this.milli = milli
    }

    /** 当日毫秒偏移。 */
    func timeOfDayMs(): Int64 {
        return hour * 3_600_000 + minute * MS_PER_MINUTE + second * 1000 + milli
    }
}

/**
 * `core/utils.dateKey`：去首尾空白，长度不足 10 个字符返回 `None`，否则取前 10 个字符。
 * 与 Web 版一致：不校验是否为合法日期，非法串也原样返回。
 */
public func dateKeyOf(value: ?String): ?String {
    if (let Some(raw) <- value) {
        let trimmed = trimJs(raw)
        let runes = trimmed.toRuneArray()
        if (runes.size >= 10) {
            return takeRunes(trimmed, 10)
        }
    }
    return None
}

func isDigit(ch: Rune): Bool {
    return ch >= r'0' && ch <= r'9'
}

/** 读取 `[index, index + count)` 的十进制数字；越界或非数字返回 -1。 */
func readDigits(runes: Array<Rune>, index: Int64, count: Int64): Int64 {
    if (index < 0 || index + count > runes.size) {
        return -1
    }
    var value = 0
    var offset = index
    while (offset < index + count) {
        let ch = runes[offset]
        if (!isDigit(ch)) {
            return -1
        }
        value = value * 10 + (Int64(UInt32(ch) - UInt32(r'0')))
        offset += 1
    }
    return value
}

func isLeapYear(year: Int64): Bool {
    return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

func daysInMonth(year: Int64, month: Int64): Int64 {
    match (month) {
        case 1 => 31
        case 2 =>
            if (isLeapYear(year)) {
                29
            } else {
                28
            }
        case 3 => 31
        case 4 => 30
        case 5 => 31
        case 6 => 30
        case 7 => 31
        case 8 => 31
        case 9 => 30
        case 10 => 31
        case 11 => 30
        case 12 => 31
        case _ => 0
    }
}

func isValidCivil(date: CivilDate): Bool {
    if (date.month < 1 || date.month > 12) {
        return false
    }
    if (date.day < 1) {
        return false
    }
    return date.day <= daysInMonth(date.year, date.month)
}

/** 公历 → 1970-01-01 起的天数（Howard Hinnant 的 days_from_civil）。 */
func daysFromCivil(date: CivilDate): Int64 {
    var year = date.year
    if (date.month <= 2) {
        year -= 1
    }
    let era = floorDiv(year, 400)
    let yearOfEra = year - era * 400
    let monthPrime = (date.month + 9) % 12
    let dayOfYear = (153 * monthPrime + 2) / 5 + date.day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146097 + dayOfEra - 719468
}

/** 天数 → 公历（Hinnant 的 civil_from_days）。 */
func civilFromDays(dayNumber: Int64): CivilDate {
    let shifted = dayNumber + 719468
    let era = floorDiv(shifted, 146097)
    let dayOfEra = shifted - era * 146097
    let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146096) / 365
    let yearBase = yearOfEra + era * 400
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let monthPrime = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * monthPrime + 2) / 5 + 1
    let month = if (monthPrime < 10) {
        monthPrime + 3
    } else {
        monthPrime - 9
    }
    let year = if (month <= 2) {
        yearBase + 1
    } else {
        yearBase
    }
    return CivilDate(year, month, day)
}

func pad(value: Int64, width: Int64): String {
    var text = value.toString()
    while (text.size < width) {
        text = "0" + text
    }
    return text
}

func formatCivil(date: CivilDate): String {
    return pad(date.year, 4) + "-" + pad(date.month, 2) + "-" + pad(date.day, 2)
}

/**
 * 解析 `YYYY-MM-DD` 前缀（`date-fns parseISO` 的日期部分）为公历日期。
 * 非法日期返回 `None`，对应 Web 版的 `Invalid Date` 分支。
 */
func parseCivilKey(key: ?String): ?CivilDate {
    if (let Some(text) <- key) {
        let runes = trimJs(text).toRuneArray()
        if (runes.size < 10) {
            return None
        }
        if (runes[4] != r'-' || runes[7] != r'-') {
            return None
        }
        let year = readDigits(runes, 0, 4)
        let month = readDigits(runes, 5, 2)
        let day = readDigits(runes, 8, 2)
        if (year < 0 || month < 0 || day < 0) {
            return None
        }
        let date = CivilDate(year, month, day)
        if (isValidCivil(date)) {
            return date
        }
    }
    return None
}

/** 日期键 → 自 1970-01-01 起的天数。 */
func dayNumberOfKey(key: ?String): ?Int64 {
    if (let Some(date) <- parseCivilKey(key)) {
        return daysFromCivil(date)
    }
    return None
}

/**
 * ISO 时间串 → UTC 毫秒时间戳。
 *
 * 支持 `YYYY-MM-DD`、`YYYY-MM-DD[T ]HH:mm[:ss[.SSS]]`，可选 `Z` 或 `±HH:MM` / `±HHMM` 偏移；
 * 无偏移的串按 `Asia/Shanghai` 墙钟解释（等价 `new Date('...T..:..:..')` 在固定 +08:00 下的语义）。
 */
func parseInstantMs(value: String): ?Int64 {
    let runes = trimJs(value).toRuneArray()
    if (runes.size < 10) {
        return None
    }
    if (runes[4] != r'-' || runes[7] != r'-') {
        return None
    }
    let year = readDigits(runes, 0, 4)
    let month = readDigits(runes, 5, 2)
    let day = readDigits(runes, 8, 2)
    if (year < 0 || month < 0 || day < 0) {
        return None
    }
    let date = CivilDate(year, month, day)
    if (!isValidCivil(date)) {
        return None
    }

    var hour = 0
    var minute = 0
    var second = 0
    var milli = 0
    var index = 10

    if (index < runes.size && (runes[index] == r'T' || runes[index] == r' ')) {
        index += 1
        hour = readDigits(runes, index, 2)
        index += 2
        if (hour < 0 || index >= runes.size || runes[index] != r':') {
            return None
        }
        index += 1
        minute = readDigits(runes, index, 2)
        index += 2
        if (minute < 0) {
            return None
        }
        if (index < runes.size && runes[index] == r':') {
            index += 1
            second = readDigits(runes, index, 2)
            index += 2
            if (second < 0) {
                return None
            }
            if (index < runes.size && runes[index] == r'.') {
                index += 1
                var fraction = 0
                var digits = 0
                while (index < runes.size && isDigit(runes[index]) && digits < 3) {
                    fraction = fraction * 10 + (Int64(UInt32(runes[index]) - UInt32(r'0')))
                    digits += 1
                    index += 1
                }
                if (digits == 0) {
                    return None
                }
                while (index < runes.size && isDigit(runes[index])) {
                    index += 1
                }
                milli = match (digits) {
                    case 1 => fraction * 100
                    case 2 => fraction * 10
                    case _ => fraction
                }
            }
        }
        if (hour > 23 || minute > 59 || second > 59) {
            return None
        }
    } else if (index < runes.size) {
        return None
    }

    var offsetMinutes = SHANGHAI_OFFSET_MINUTES
    if (index < runes.size) {
        let zone = runes[index]
        if (zone == r'Z' || zone == r'z') {
            offsetMinutes = 0
            index += 1
        } else if (zone == r'+' || zone == r'-') {
            let sign = if (zone == r'-') {
                -1
            } else {
                1
            }
            index += 1
            let zoneHour = readDigits(runes, index, 2)
            index += 2
            if (zoneHour < 0) {
                return None
            }
            var zoneMinute = 0
            if (index < runes.size && runes[index] == r':') {
                index += 1
                zoneMinute = readDigits(runes, index, 2)
                index += 2
                if (zoneMinute < 0) {
                    return None
                }
            } else if (index < runes.size) {
                zoneMinute = readDigits(runes, index, 2)
                index += 2
                if (zoneMinute < 0) {
                    return None
                }
            }
            if (zoneHour > 23 || zoneMinute > 59) {
                return None
            }
            offsetMinutes = sign * (zoneHour * 60 + zoneMinute)
        }
    }
    if (index != runes.size) {
        return None
    }

    let wallClockMs = daysFromCivil(date) * MS_PER_DAY + hour * 3_600_000 + minute * MS_PER_MINUTE + second * 1000 +
        milli
    return wallClockMs - offsetMinutes * MS_PER_MINUTE
}

func localDateTimeOf(epochMs: Int64): LocalDateTime {
    let local = epochMs + SHANGHAI_OFFSET_MINUTES * MS_PER_MINUTE
    let dayNumber = floorDiv(local, MS_PER_DAY)
    let remainder = local - dayNumber * MS_PER_DAY
    let hour = remainder / 3_600_000
    let minute = (remainder % 3_600_000) / MS_PER_MINUTE
    let second = (remainder % MS_PER_MINUTE) / 1000
    let milli = remainder % 1000
    return LocalDateTime(civilFromDays(dayNumber), hour, minute, second, milli)
}

func localEpochMsOf(date: CivilDate, timeOfDayMs: Int64): Int64 {
    return daysFromCivil(date) * MS_PER_DAY + timeOfDayMs - SHANGHAI_OFFSET_MINUTES * MS_PER_MINUTE
}

/**
 * 本地时间按月偏移，复现 JS `Date.setMonth` 的溢出规则：月内日期超出目标月长度时
 * 顺延到下个月（例如 1 月 31 日减一个月 → 12 月 31 日，3 月 31 日减一个月 → 3 月 3 日）。
 */
func addLocalMonths(epochMs: Int64, monthDelta: Int64): Int64 {
    let current = localDateTimeOf(epochMs)
    let totalMonths = current.date.year * 12 + (current.date.month - 1) + monthDelta
    let year = floorDiv(totalMonths, 12)
    let month = totalMonths - year * 12 + 1
    let dayNumber = daysFromCivil(CivilDate(year, month, 1)) + (current.date.day - 1)
    return localEpochMsOf(civilFromDays(dayNumber), current.timeOfDayMs())
}

/** 把本地日期的「日」改成 `day`（可溢出到下个月），保留当日时间。 */
func withLocalDay(epochMs: Int64, day: Int64): Int64 {
    let current = localDateTimeOf(epochMs)
    let dayNumber = daysFromCivil(CivilDate(current.date.year, current.date.month, 1)) + (day - 1)
    return localEpochMsOf(civilFromDays(dayNumber), current.timeOfDayMs())
}

/** 本地时间是否落在月末最后一天。 */
func isLastDayOfMonth(epochMs: Int64): Bool {
    let current = localDateTimeOf(epochMs)
    return current.date.day == daysInMonth(current.date.year, current.date.month)
}

/** 本地日历日序号（忽略当日时间）。 */
func localDayNumberOfInstant(epochMs: Int64): Int64 {
    let local = epochMs + SHANGHAI_OFFSET_MINUTES * MS_PER_MINUTE
    return floorDiv(local, MS_PER_DAY)
}

/** ISO 时间串 → 本地日期键（`YYYY-MM-DD`）。 */
public func localDateKeyOf(value: String): ?String {
    if (let Some(epochMs) <- parseInstantMs(value)) {
        return formatCivil(civilFromDays(localDayNumberOfInstant(epochMs)))
    }
    return None
}

/**
 * `today.daysLateFor`：超期天数，至少 1；`today` 或 `due` 不是合法日期键时也退回 1。
 */
func daysLateFor(todayKey: String, due: ?String): Int64 {
    let dueDay = match (dayNumberOfKey(due)) {
        case Some(number) => number
        case None => return 1
    }
    let todayDay = match (dayNumberOfKey(todayKey)) {
        case Some(number) => number
        case None => return 1
    }
    let late = todayDay - dueDay
    return if (late < 1) {
        1
    } else {
        late
    }
}
