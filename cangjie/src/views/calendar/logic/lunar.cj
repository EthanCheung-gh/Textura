package textura.views.calendar.logic

import std.collection.*

/**
 * 中国农历换算（1900-01-31 ～ 2100-12-31），移植自
 * `src/modules/calendar/lunar.ts`。纯函数、零外部依赖、不读系统时钟。
 *
 * 输出字段与 TS `LunarDate` 一一对应。
 */

/** 支持范围下界（含）：农历 1900 年正月初一。 */
public let LUNAR_MIN_KEY: String = "1900-01-31"

/** 支持范围上界（含）：农历 2100 年腊月最后一天。 */
public let LUNAR_MAX_KEY: String = "2100-12-31"

/** 农历日期。`month` 1..12，`day` 1..30。 */
public struct LunarDate {
    /** 农历年（以春节为界）。 */
    public let year: Int64
    /** 农历月 1..12。 */
    public let month: Int64
    /** 农历日 1..30。 */
    public let day: Int64
    /** 是否闰月。 */
    public let isLeap: Bool
    /** 正月 / 二月 / … / 冬月 / 腊月（闰月带「闰」前缀）。 */
    public let monthName: String
    /** 初一 … 初十 / 十一 … 十九 / 二十 / 廿一 … 廿九 / 三十。 */
    public let dayName: String
    /** 干支年，如「丙午」。 */
    public let ganzhiYear: String
    /** 生肖，如「马」。 */
    public let zodiac: String
    /** 农历节日（含除夕、清明），无则 `None`。 */
    public let festival: ?String
    /** 当日节气名，无则 `None`。 */
    public let solarTerm: ?String

    public init(
        year: Int64,
        month: Int64,
        day: Int64,
        isLeap: Bool,
        monthName: String,
        dayName: String,
        ganzhiYear: String,
        zodiac: String,
        festival: ?String,
        solarTerm: ?String
    ) {
        this.year = year
        this.month = month
        this.day = day
        this.isLeap = isLeap
        this.monthName = monthName
        this.dayName = dayName
        this.ganzhiYear = ganzhiYear
        this.zodiac = zodiac
        this.festival = festival
        this.solarTerm = solarTerm
    }

    public func toString(): String {
        return "${ganzhiYear}年 ${monthName}${dayName}"
    }
}

/** 干支与生肖。 */
public struct Ganzhi {
    public let ganzhi: String
    public let zodiac: String

    public init(ganzhi: String, zodiac: String) {
        this.ganzhi = ganzhi
        this.zodiac = zodiac
    }
}

/** 农历某年闰哪个月；0 表示无闰月，超出 1900–2100 也返回 0。 */
public func isLeapMonth(year: Int64): Int64 {
    if (year < 1900 || year > 2100) {
        return 0
    }
    return LUNAR_INFO[year - 1900] & 0xf
}

/** 闰月天数（30 / 29），无闰月返回 0。 */
public func leapMonthDays(year: Int64): Int64 {
    if (isLeapMonth(year) == 0) {
        return 0
    }
    return if ((LUNAR_INFO[year - 1900] & 0x10000) != 0) {
        30
    } else {
        29
    }
}

/** 农历某年某月（1..12，非闰月）的天数。 */
public func lunarMonthDays(year: Int64, month: Int64): Int64 {
    if (year < 1900 || year > 2100 || month < 1 || month > 12) {
        return 0
    }
    return if ((LUNAR_INFO[year - 1900] & (0x10000 >> month)) != 0) {
        30
    } else {
        29
    }
}

/** 农历某年的总天数（含闰月）。 */
public func lunarYearDays(year: Int64): Int64 {
    if (year < 1900 || year > 2100) {
        return 0
    }
    let info = LUNAR_INFO[year - 1900]
    var days = 348 // 12 * 29
    var bit = 0x8000
    while (bit > 0x8) {
        if ((info & bit) != 0) {
            days += 1
        }
        bit >>= 1
    }
    return days + leapMonthDays(year)
}

/** 每个农历年正月初一相对 1900-01-31 的偏移天数（末尾多一项 = 2101 年起点）。 */
public let YEAR_START_DAYS: Array<Int64> = buildYearStartDays()

func buildYearStartDays(): Array<Int64> {
    let starts = Array<Int64>(202, repeat: 0)
    var acc: Int64 = 0
    for (year in 1900..=2100) {
        starts[year - 1900] = acc
        acc += lunarYearDays(year)
    }
    starts[201] = acc
    return starts
}

let MIN_DAY_NUMBER: Int64 = dayNumberOfKey(LUNAR_MIN_KEY) ?? 0
let MAX_DAY_NUMBER: Int64 = dayNumberOfKey(LUNAR_MAX_KEY) ?? 0

/** 是否在 1900-01-31 ～ 2100-12-31（含端点）内。 */
public func inSupportedRange(dayNumber: Int64): Bool {
    return dayNumber >= MIN_DAY_NUMBER && dayNumber <= MAX_DAY_NUMBER
}

/** 农历月名：正月…腊月。 */
public func lunarMonthName(month: Int64): String {
    return lunarMonthName(month, false)
}

/** 农历月名：正月…腊月，闰月加「闰」。 */
public func lunarMonthName(month: Int64, isLeap: Bool): String {
    let clamped = if (month < 1) {
        1
    } else if (month > 12) {
        12
    } else {
        month
    }
    let base = LUNAR_MONTH_NAMES[clamped - 1]
    let prefix = if (isLeap) {
        "闰"
    } else {
        ""
    }
    return "${prefix}${base}月"
}

/** 农历日名：初一…初十、十一…十九、二十、廿一…廿九、三十。越界返回空串。 */
public func lunarDayName(day: Int64): String {
    if (day < 1 || day > 30) {
        return ""
    }
    if (day == 10) {
        return "初十"
    }
    if (day == 20) {
        return "二十"
    }
    if (day == 30) {
        return "三十"
    }
    if (day < 10) {
        return "初${LUNAR_DIGITS[day - 1]}"
    }
    if (day < 20) {
        return "十${LUNAR_DIGITS[day - 11]}"
    }
    return "廿${LUNAR_DIGITS[day - 21]}"
}

/** 干支与生肖（以农历年为准，春节切换）。 */
public func ganzhiOfYear(lunarYear: Int64): Ganzhi {
    let index = ((lunarYear - 1864) % 60 + 60) % 60
    return Ganzhi(
        "${HEAVENLY_STEMS[index % 10]}${EARTHLY_BRANCHES[index % 12]}",
        ZODIAC_ANIMALS[index % 12]
    )
}

/** 公历 `YYYY-MM-DD` → 农历；超出 1900-01-31 ～ 2100-12-31 返回 `None`。 */
public func solarToLunar(dateKey: String): ?LunarDate {
    let dayNumber = dayNumberOfKey(dateKey)
    if (dayNumber.isNone()) {
        return None
    }
    let raw = rawLunarFromDayNumber(dayNumber.getOrThrow())
    if (raw.isNone()) {
        return None
    }
    let lunar = raw.getOrThrow()
    let gz = ganzhiOfYear(lunar.year)
    let term = solarTermOf(dateKey)
    var festival: ?String = lunarFestival(lunar)
    if (festival.isNone() && term == Some("清明")) {
        festival = Some("清明")
    }
    return LunarDate(
        lunar.year,
        lunar.month,
        lunar.day,
        lunar.isLeap,
        lunarMonthName(lunar.month, lunar.isLeap),
        lunarDayName(lunar.day),
        gz.ganzhi,
        gz.zodiac,
        festival,
        term
    )
}

/** 农历 → 公历 `YYYY-MM-DD`（非闰月）。 */
public func lunarToSolar(year: Int64, month: Int64, day: Int64): ?String {
    return lunarToSolar(year, month, day, false)
}

/** 农历 → 公历 `YYYY-MM-DD`；非法 / 超出范围返回 `None`。 */
public func lunarToSolar(year: Int64, month: Int64, day: Int64, isLeap: Bool): ?String {
    if (year < 1900 || year > 2100) {
        return None
    }
    if (month < 1 || month > 12) {
        return None
    }
    let leap = isLeapMonth(year)
    if (isLeap && leap != month) {
        return None
    }
    if (day < 1) {
        return None
    }
    var offset = YEAR_START_DAYS[year - 1900]
    for (m in 1..month) {
        offset += lunarMonthDays(year, m)
        if (leap == m) {
            offset += leapMonthDays(year)
        }
    }
    if (isLeap) {
        offset += lunarMonthDays(year, month)
    }
    let duration = if (isLeap) {
        leapMonthDays(year)
    } else {
        lunarMonthDays(year, month)
    }
    if (day > duration) {
        return None
    }
    offset += day - 1
    let dayNumber = MIN_DAY_NUMBER + offset
    if (!inSupportedRange(dayNumber)) {
        return None
    }
    return keyOfDayNumber(dayNumber)
}

/** 农历节日（含除夕、清明）；无则 `None`。超出范围返回 `None`。 */
public func festivalOf(dateKey: String): ?String {
    return match (solarToLunar(dateKey)) {
        case Some(lunar) => lunar.festival
        case None => None
    }
}

// ---------------------------------------------------------------------------
// 内部：原始农历字段
// ---------------------------------------------------------------------------

struct RawLunar {
    let year: Int64
    let month: Int64
    let day: Int64
    let isLeap: Bool
    let monthDays: Int64

    init(year: Int64, month: Int64, day: Int64, isLeap: Bool, monthDays: Int64) {
        this.year = year
        this.month = month
        this.day = day
        this.isLeap = isLeap
        this.monthDays = monthDays
    }
}

/** 公历日序号 → 原始农历字段；超出支持范围返回 `None`。 */
func rawLunarFromDayNumber(dayNumber: Int64): ?RawLunar {
    if (!inSupportedRange(dayNumber)) {
        return None
    }
    var offset = dayNumber - MIN_DAY_NUMBER

    // 二分查找农历年（YEAR_START_DAYS 单调递增）
    var low: Int64 = 0
    var high: Int64 = 200 // 1900..2100
    while (low < high) {
        let mid = (low + high + 1) / 2
        if (YEAR_START_DAYS[mid] <= offset) {
            low = mid
        } else {
            high = mid - 1
        }
    }
    let year = 1900 + low
    offset -= YEAR_START_DAYS[low]

    let leap = isLeapMonth(year)
    for (month in 1..=12) {
        let days = lunarMonthDays(year, month)
        if (offset < days) {
            return RawLunar(year, month, offset + 1, false, days)
        }
        offset -= days
        if (leap == month) {
            let leapDays = leapMonthDays(year)
            if (offset < leapDays) {
                return RawLunar(year, month, offset + 1, true, leapDays)
            }
            offset -= leapDays
        }
    }
    return None
}

func lunarFestival(raw: RawLunar): ?String {
    if (raw.isLeap) {
        return None
    }
    match (LUNAR_FESTIVALS.get("${raw.month.toString()}-${raw.day.toString()}")) {
        case Some(name) => return Some(name)
        case None => ()
    }
    // 除夕：农历腊月的最后一天（可能是廿九，也可能是三十）
    if (raw.month == 12 && raw.day == raw.monthDays) {
        return Some("除夕")
    }
    return None
}
