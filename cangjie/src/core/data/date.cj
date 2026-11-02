package textura.core.data

import std.convert.*
import std.time.*

/**
 * Date/time helpers with the exact semantics the Web build gets from `date-fns`
 * under the fixed parity timezone.
 *
 * Design rules:
 * - all instants are Int64 epoch milliseconds (UTC), exactly what
 *   `Date.prototype.getTime()` returns in the browser;
 * - the display timezone is pinned to `Asia/Shanghai` (+08:00, no DST), so a
 *   snapshot never depends on the host `TZ`;
 * - nothing reads the wall clock unless a caller passes the system clock in
 *   through `Clock`, which keeps parity runs reproducible.
 */
public let LOCAL_OFFSET_MINUTES: Int64 = 480
public let MILLIS_PER_DAY: Int64 = 86400000
public let MILLIS_PER_MINUTE: Int64 = 60000

/** Injectable time source: views/store use it so tests can freeze "now". */
public interface Clock {
    func nowMillis(): Int64
}

public class SystemClock <: Clock {
    public init() {}

    public func nowMillis(): Int64 {
        systemNowMillis()
    }
}

public class FixedClock <: Clock {
    public let at: Int64

    public init(at: Int64) {
        this.at = at
    }

    public func nowMillis(): Int64 {
        at
    }
}

public func systemNowMillis(): Int64 {
    DateTime.now(timeZone: TimeZone.UTC).toUnixTimeStamp().toMilliseconds()
}

/* ------------------------------------------------------------------ */
/* Civil calendar arithmetic (proleptic Gregorian, UTC-based)           */
/* ------------------------------------------------------------------ */

/** Days since 1970-01-01 for a civil date. */
func daysFromCivil(year: Int64, month: Int64, day: Int64): Int64 {
    let adjustedYear = if (month <= 2) {
        year - 1
    } else {
        year
    }
    let era = if (adjustedYear >= 0) {
        adjustedYear / 400
    } else {
        (adjustedYear - 399) / 400
    }
    let yearOfEra = adjustedYear - era * 400
    let shiftedMonth = if (month > 2) {
        month - 3
    } else {
        month + 9
    }
    let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    era * 146097 + dayOfEra - 719468
}

/** Civil date for a day count since 1970-01-01; returns (year, month, day). */
func civilFromDays(days: Int64): (Int64, Int64, Int64) {
    let shifted = days + 719468
    let era = if (shifted >= 0) {
        shifted / 146097
    } else {
        (shifted - 146096) / 146097
    }
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
    (year, month, day)
}

/** Euclidean division: `floorDiv(-1, 2) == -1`, unlike C-style truncation. */
func floorDiv(value: Int64, divisor: Int64): Int64 {
    var quotient = value / divisor
    if ((value % divisor != 0) && ((value < 0) != (divisor < 0))) {
        quotient -= 1
    }
    quotient
}

func floorMod(value: Int64, divisor: Int64): Int64 {
    value - floorDiv(value, divisor) * divisor
}

/** Local wall-clock milliseconds for an instant (Asia/Shanghai is a fixed +8). */
func localMillis(epochMillis: Int64): Int64 {
    epochMillis + LOCAL_OFFSET_MINUTES * MILLIS_PER_MINUTE
}

public func dayIndex(epochMillis: Int64): Int64 {
    floorDiv(localMillis(epochMillis), MILLIS_PER_DAY)
}

public func millisOfDay(epochMillis: Int64): Int64 {
    floorMod(localMillis(epochMillis), MILLIS_PER_DAY)
}

/* ------------------------------------------------------------------ */
/* Formatting                                                          */
/* ------------------------------------------------------------------ */

func pad2(value: Int64): String {
    if (value < 10 && value >= 0) {
        "0${value}"
    } else {
        "${value}"
    }
}

func pad3(value: Int64): String {
    if (value < 10 && value >= 0) {
        "00${value}"
    } else if (value < 100 && value >= 0) {
        "0${value}"
    } else {
        "${value}"
    }
}

/** `Date.prototype.toISOString()`: `2026-03-16T02:00:00.000Z`. */
public func isoFromMillis(epochMillis: Int64): String {
    let days = floorDiv(epochMillis, MILLIS_PER_DAY)
    let (year, month, day) = civilFromDays(days)
    let millisOfDayUtc = floorMod(epochMillis, MILLIS_PER_DAY)
    let hour = millisOfDayUtc / 3600000
    let minute = (millisOfDayUtc / MILLIS_PER_MINUTE) % 60
    let second = (millisOfDayUtc / 1000) % 60
    let millis = millisOfDayUtc % 1000
    "${year}-${pad2(month)}-${pad2(day)}T${pad2(hour)}:${pad2(minute)}:${pad2(second)}.${pad3(millis)}Z"
}

/** Local `YYYY-MM-DD` for an instant. */
public func localDateKey(epochMillis: Int64): String {
    let (year, month, day) = civilFromDays(dayIndex(epochMillis))
    "${year}-${pad2(month)}-${pad2(day)}"
}

/** Local `YYYY-MM-DD HH:mm` for an instant. */
public func localDateTimeKey(epochMillis: Int64): String {
    let (year, month, day) = civilFromDays(dayIndex(epochMillis))
    let ofDay = millisOfDay(epochMillis)
    "${year}-${pad2(month)}-${pad2(day)} ${pad2(ofDay / 3600000)}:${pad2((ofDay / MILLIS_PER_MINUTE) % 60)}"
}

/* ------------------------------------------------------------------ */
/* Parsing                                                             */
/* ------------------------------------------------------------------ */

func twoDigits(text: String, start: Int64): Int64 {
    Int64(text[start]) * 10 + Int64(text[start + 1]) - 528
}

func fourDigits(text: String, start: Int64): Int64 {
    ((Int64(text[start]) - 48) * 1000 + (Int64(text[start + 1]) - 48) * 100 +
        (Int64(text[start + 2]) - 48) * 10 + (Int64(text[start + 3]) - 48))
}

/**
 * Parses `YYYY-MM-DD`, `YYYY-MM-DD HH:mm`, `YYYY-MM-DDTHH:mm:ss(.SSS)?` and the
 * same forms with a `Z` or `±HH:MM` offset. A missing zone is interpreted as the
 * pinned +08:00 timezone, matching `date-fns` `parseISO` on the parity host.
 * Returns None for anything else (callers fall back to null/em-dash).
 */
public func parseIsoMillis(value: String): ?Int64 {
    let text = value.trimAscii()
    if (text.size < 10) {
        return None
    }
    if (text[4] != UInt8(45) || text[7] != UInt8(45)) {
        return None
    }
    let year = fourDigits(text, 0)
    let month = twoDigits(text, 5)
    let day = twoDigits(text, 8)
    if (month < 1 || month > 12 || day < 1 || day > 31) {
        return None
    }
    var hour = 0
    var minute = 0
    var second = 0
    var millis = 0
    var offsetMinutes = LOCAL_OFFSET_MINUTES
    if (text.size > 10) {
        var cursor = 10
        let separator = text[cursor]
        if (separator != UInt8(84) && separator != UInt8(116) && separator != UInt8(32)) {
            return None
        }
        cursor += 1
        if (text.size < cursor + 5 || text[cursor + 2] != UInt8(58)) {
            return None
        }
        hour = twoDigits(text, cursor)
        minute = twoDigits(text, cursor + 3)
        cursor += 5
        if (cursor + 2 < text.size && text[cursor] == UInt8(58)) {
            second = twoDigits(text, cursor + 1)
            cursor += 3
            if (cursor < text.size && text[cursor] == UInt8(46)) {
                cursor += 1
                var scale = 100
                while (cursor < text.size && text[cursor] >= UInt8(48) && text[cursor] <= UInt8(57)) {
                    if (scale > 0) {
                        millis += (Int64(text[cursor]) - 48) * scale
                        scale /= 10
                    }
                    cursor += 1
                }
            }
        }
        if (cursor < text.size) {
            let zone = text[cursor]
            if (zone == UInt8(90) || zone == UInt8(122)) {
                offsetMinutes = 0
                cursor += 1
            } else if (zone == UInt8(43) || zone == UInt8(45)) {
                if (text.size < cursor + 6) {
                    return None
                }
                let zoneHour = twoDigits(text, cursor + 1)
                let zoneMinute = twoDigits(text, cursor + 4)
                offsetMinutes = zoneHour * 60 + zoneMinute
                if (zone == UInt8(45)) {
                    offsetMinutes = -offsetMinutes
                }
                cursor += 6
            }
        }
        if (cursor != text.size) {
            return None
        }
    }
    if (hour > 23 || minute > 59 || second > 59) {
        return None
    }
    let days = daysFromCivil(year, month, day)
    let wallMillis = days * MILLIS_PER_DAY + hour * 3600000 + minute * MILLIS_PER_MINUTE + second * 1000 + millis
    Some(wallMillis - offsetMinutes * MILLIS_PER_MINUTE)
}

/** Java/date-fns style subset formatter: yyyy, yy, MM, M, dd, d, HH, H, mm, ss, SSS. */
public func formatWithPattern(epochMillis: Int64, pattern: String): String {
    let (year, month, day) = civilFromDays(dayIndex(epochMillis))
    let ofDay = millisOfDay(epochMillis)
    let hour = ofDay / 3600000
    let minute = (ofDay / MILLIS_PER_MINUTE) % 60
    let second = (ofDay / 1000) % 60
    let millis = ofDay % 1000
    let out = StringBuilder()
    var cursor = 0
    while (cursor < pattern.size) {
        if (patternHasToken(pattern, cursor, "yyyy")) {
            out.append(year.toString())
            cursor += 4
        } else if (patternHasToken(pattern, cursor, "SSS")) {
            out.append(pad3(millis))
            cursor += 4
        } else if (patternHasToken(pattern, cursor, "yy")) {
            out.append(pad2(floorMod(year, 100)))
            cursor += 2
        } else if (patternHasToken(pattern, cursor, "MM")) {
            out.append(pad2(month))
            cursor += 2
        } else if (patternHasToken(pattern, cursor, "dd")) {
            out.append(pad2(day))
            cursor += 2
        } else if (patternHasToken(pattern, cursor, "HH")) {
            out.append(pad2(hour))
            cursor += 2
        } else if (patternHasToken(pattern, cursor, "mm")) {
            out.append(pad2(minute))
            cursor += 2
        } else if (patternHasToken(pattern, cursor, "ss")) {
            out.append(pad2(second))
            cursor += 2
        } else {
            let token = pattern[cursor]
            if (token == UInt8(77)) {
                out.append(month.toString())
                cursor += 1
            } else if (token == UInt8(100)) {
                out.append(day.toString())
                cursor += 1
            } else if (token == UInt8(72)) {
                out.append(hour.toString())
                cursor += 1
            } else {
                // Copy one whole UTF-8 character; slicing a single byte would
                // split a multi-byte sequence and throw.
                let width = utf8Width(token)
                let limit = if (cursor + width < pattern.size) {
                    cursor + width
                } else {
                    pattern.size
                }
                out.append(pattern[cursor..limit])
                cursor += width
            }
        }
    }
    out.toString()
}

/** Byte-wise token match so slicing never splits a multi-byte character. */
func patternHasToken(pattern: String, cursor: Int64, token: String): Bool {
    if (cursor + token.size > pattern.size) {
        return false
    }
    var index = 0
    while (index < token.size) {
        if (pattern[cursor + index] != token[index]) {
            return false
        }
        index += 1
    }
    true
}

func utf8Width(leadByte: UInt8): Int64 {
    let value = Int64(leadByte)
    if (value < 0x80) {
        1
    } else if (value >= 0xF0) {
        4
    } else if (value >= 0xE0) {
        3
    } else if (value >= 0xC0) {
        2
    } else {
        1
    }
}

/* ------------------------------------------------------------------ */
/* Public helpers mirroring src/core/utils.ts                          */
/* ------------------------------------------------------------------ */

/** Truncates an ISO timestamp/date to its `YYYY-MM-DD` prefix (trimmed). */
public func dateKey(value: ?String): ?String {
    match (value) {
        case Some(raw) =>
            let trimmed = raw.trimAscii()
            if (trimmed.size >= 10) {
                Some(trimmed[0..10])
            } else {
                None
            }
        case None => None
    }
}

public func dateKey(value: String): ?String {
    dateKey(Some(value))
}

/** Local midnight of a `YYYY-MM-DD` key. */
public func parseDateKey(value: ?String): ?Int64 {
    match (dateKey(value)) {
        case Some(key) => parseIsoMillis(key)
        case None => None
    }
}

/** `formatDateKey(value, 'MM/dd')` in the Web build; `—` when unparsable. */
public func formatDateKey(value: ?String, pattern!: String = "MM/dd"): String {
    match (parseDateKey(value)) {
        case Some(millis) => formatWithPattern(millis, pattern)
        case None => "—"
    }
}

public func formatDateKey(value: String, pattern!: String = "MM/dd"): String {
    formatDateKey(Some(value), pattern: pattern)
}

/** `formatDateTime`: `yyyy-MM-dd HH:mm`, `—` when unparsable. */
public func formatDateTime(value: ?String): String {
    match (value) {
        case Some(raw) =>
            match (parseIsoMillis(raw)) {
                case Some(millis) => localDateTimeKey(millis)
                case None => "—"
            }
        case None => "—"
    }
}

/**
 * Current UTC ISO timestamp from the injected clock.
 *
 * There is deliberately no zero-argument overload: anything that reads the host
 * clock must say so (`Clock` is injected, or `systemNowMillis()` explicitly), so a
 * parity run can never silently depend on the wall clock.
 */
public func nowIso(clock: Clock): String {
    isoFromMillis(clock.nowMillis())
}

/** `2026-Q1` for the pinned local timezone. */
public func currentQuarter(fromMillis: Int64): String {
    let (year, month, _) = civilFromDays(dayIndex(fromMillis))
    "${year}-Q${(month - 1) / 3 + 1}"
}

public func currentQuarter(clock: Clock): String {
    currentQuarter(clock.nowMillis())
}

/** `2026-Q1` for a `YYYY-MM-DD` key; `None` when the key is unparsable. */
public func quarterOfDateKey(key: String): ?String {
    match (parseDateKey(Some(key))) {
        case Some(millis) => Some(currentQuarter(millis))
        case None => None
    }
}

public class QuarterRange {
    public let start: String
    public let end: String

    public init(start: String, end: String) {
        this.start = start
        this.end = end
    }
}

/** Parses `YYYY-Qn` into its first/last local date keys; None when malformed. */
public func quarterRange(period: String): ?QuarterRange {
    let text = period.trimAscii()
    if (text.size != 7 || text[4] != UInt8(45) || text[5] != UInt8(81)) {
        return None
    }
    if (text[6] < UInt8(49) || text[6] > UInt8(52)) {
        return None
    }
    let year = fourDigits(text, 0)
    let quarter = Int64(text[6]) - 48
    let startMonth = (quarter - 1) * 3 + 1
    let endMonth = startMonth + 2
    let startDays = daysFromCivil(year, startMonth, 1)
    let nextMonth = if (endMonth == 12) {
        daysFromCivil(year + 1, 1, 1)
    } else {
        daysFromCivil(year, endMonth + 1, 1)
    }
    let startKey = localDateKey(startDays * MILLIS_PER_DAY - LOCAL_OFFSET_MINUTES * MILLIS_PER_MINUTE)
    let endKey = localDateKey((nextMonth - 1) * MILLIS_PER_DAY - LOCAL_OFFSET_MINUTES * MILLIS_PER_MINUTE)
    Some(QuarterRange(startKey, endKey))
}

public func quarterStartKey(period: String): ?String {
    match (quarterRange(period)) {
        case Some(range) => Some(range.start)
        case None => None
    }
}

/** Adds `days` to an instant and returns the local date key. */
public func dayOffset(days: Int64, fromMillis: Int64): String {
    localDateKey(fromMillis + days * MILLIS_PER_DAY)
}

public func dayOffset(days: Int64, clock: Clock): String {
    dayOffset(days, clock.nowMillis())
}

/** Adds `days` to an instant and returns the UTC ISO timestamp. */
public func isoOffset(days: Int64, fromMillis: Int64): String {
    isoFromMillis(fromMillis + days * MILLIS_PER_DAY)
}

public func isoOffset(days: Int64, clock: Clock): String {
    isoOffset(days, clock.nowMillis())
}

public func addDaysToKey(key: String, days: Int64): String {
    match (parseDateKey(Some(key))) {
        case Some(millis) => localDateKey(millis + days * MILLIS_PER_DAY)
        case None => key
    }
}

/** `differenceInCalendarDays(to, from)` on local date keys. */
public func daysBetween(fromISO: String, toISO: String): Int64 {
    match (parseDateKey(Some(fromISO))) {
        case Some(fromMillis) =>
            match (parseDateKey(Some(toISO))) {
                case Some(toMillis) => dayIndex(toMillis) - dayIndex(fromMillis)
                case None => 0
            }
        case None => 0
    }
}

/** 0 = Sunday … 6 = Saturday, for the local date of `epochMillis`. */
public func dayOfWeek(epochMillis: Int64): Int64 {
    floorMod(dayIndex(epochMillis) + 4, 7)
}

public func startOfWeekKey(key: String): String {
    match (parseDateKey(Some(key))) {
        case Some(millis) =>
            let offset = floorMod(dayOfWeek(millis) + 6, 7)
            addDaysToKey(key, -offset)
        case None => key
    }
}

public func endOfWeekKey(key: String): String {
    addDaysToKey(startOfWeekKey(key), 6)
}

public func startOfMonthKey(key: String): String {
    match (parseDateKey(Some(key))) {
        case Some(millis) =>
            let (year, month, _) = civilFromDays(dayIndex(millis))
            localDateKey(daysFromCivil(year, month, 1) * MILLIS_PER_DAY -
                LOCAL_OFFSET_MINUTES * MILLIS_PER_MINUTE)
        case None => key
    }
}

public func endOfMonthKey(key: String): String {
    match (parseDateKey(Some(key))) {
        case Some(millis) =>
            let (year, month, _) = civilFromDays(dayIndex(millis))
            let nextMonth = if (month == 12) {
                daysFromCivil(year + 1, 1, 1)
            } else {
                daysFromCivil(year, month + 1, 1)
            }
            localDateKey((nextMonth - 1) * MILLIS_PER_DAY - LOCAL_OFFSET_MINUTES * MILLIS_PER_MINUTE)
        case None => key
    }
}

public func yearOfKey(key: String): Int64 {
    match (parseDateKey(Some(key))) {
        case Some(millis) =>
            let (year, _, _) = civilFromDays(dayIndex(millis))
            year
        case None => 0
    }
}

/* ------------------------------------------------------------------ */
/* Human-facing relative labels                                         */
/* ------------------------------------------------------------------ */

/**
 * Collection-time label used by the GTD list: 今天 / 昨天 / n 天前 / MM/dd.
 * Mirrors `relativeTimeLabel` in `src/modules/gtd/gtdLogic.ts`.
 */
public func relativeDayLabel(iso: ?String, nowMillis: Int64): String {
    match (iso) {
        case Some(raw) =>
            match (parseIsoMillis(raw)) {
                case Some(millis) =>
                    let diff = dayIndex(nowMillis) - dayIndex(millis)
                    if (diff <= 0) {
                        "今天"
                    } else if (diff == 1) {
                        "昨天"
                    } else if (diff < 14) {
                        "${diff} 天前"
                    } else {
                        formatWithPattern(millis, "MM/dd")
                    }
                case None => "—"
            }
        case None => "—"
    }
}

/**
 * Approximation of `formatDistanceToNow(..., { addSuffix: true, locale: zhCN })`.
 * date-fns uses calendar-aware thresholds; the buckets below match its wording
 * for the ranges the dashboard shows.
 */
public func relativeTimeText(iso: ?String, nowMillis: Int64): String {
    match (iso) {
        case Some(raw) =>
            match (parseIsoMillis(raw)) {
                case Some(millis) =>
                    let delta = nowMillis - millis
                    let future = delta < 0
                    let seconds = if (future) {
                        -delta / 1000
                    } else {
                        delta / 1000
                    }
                    let body = if (seconds < 45) {
                        "不到 1 分钟"
                    } else if (seconds < 45 * 60) {
                        "约 ${(seconds + 30) / 60} 分钟"
                    } else if (seconds < 24 * 3600) {
                        "约 ${(seconds + 1800) / 3600} 小时"
                    } else if (seconds < 30 * 86400) {
                        "${(seconds + 43200) / 86400} 天"
                    } else if (seconds < 365 * 86400) {
                        "约 ${(seconds + 15 * 86400) / (30 * 86400)} 个月"
                    } else {
                        "约 ${(seconds + 182 * 86400) / (365 * 86400)} 年"
                    }
                    if (future) {
                        "${body}内"
                    } else {
                        "${body}前"
                    }
                case None => "—"
            }
        case None => "—"
    }
}
