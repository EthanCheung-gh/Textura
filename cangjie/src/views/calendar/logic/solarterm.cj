package textura.views.calendar.logic

import std.math.*
import std.collection.*
import std.convert.*
import std.sync.*

/**
 * 二十四节气（太阳视黄经 + ΔT），移植自 `src/modules/calendar/lunar.ts`。
 *
 * 算法：
 * 1. 以太阳视黄经为目标（小寒 285°，其后每个节气 +15°，共 24 个），
 *    用牛顿迭代反解时刻；迭代步长按太阳日均行度 0.98564736°/天折算。
 * 2. 太阳视黄经取 Meeus《Astronomical Algorithms》第 25 章低精度公式
 *    （平黄经 + 中心差 + 章动近似），并叠加 5 项行星长周期摄动。
 * 3. ΔT（TT − UT）用 Espenak–Meeus 分段多项式换算为民用时。
 * 4. 结果按北京时间（UTC+8）取日历日，输出 `YYYY-MM-DD`。
 *
 * 所有浮点运算都是 IEEE-754 双精度，与 TS 版本逐句对应。
 */

/** 24 节气名（小寒 → 冬至）。 */
public let SOLAR_TERM_NAMES: Array<String> = [
    "小寒",
    "大寒",
    "立春",
    "雨水",
    "惊蛰",
    "春分",
    "清明",
    "谷雨",
    "立夏",
    "小满",
    "芒种",
    "夏至",
    "小暑",
    "大暑",
    "立秋",
    "处暑",
    "白露",
    "秋分",
    "寒露",
    "霜降",
    "立冬",
    "小雪",
    "大雪",
    "冬至"
]

/** 各节气对应的太阳视黄经（度）。 */
let SOLAR_TERM_LONGITUDES: Array<Float64> = [
    285.0,
    300.0,
    315.0,
    330.0,
    345.0,
    0.0,
    15.0,
    30.0,
    45.0,
    60.0,
    75.0,
    90.0,
    105.0,
    120.0,
    135.0,
    150.0,
    165.0,
    180.0,
    195.0,
    210.0,
    225.0,
    240.0,
    255.0,
    270.0
]

/** 节气信息。 */
public struct SolarTermInfo <: Equatable<SolarTermInfo> {
    public let name: String
    /** 北京时间当天的 `YYYY-MM-DD`。 */
    public let dateKey: String

    public init(name: String, dateKey: String) {
        this.name = name
        this.dateKey = dateKey
    }

    public operator func ==(other: SolarTermInfo): Bool {
        return name == other.name && dateKey == other.dateKey
    }

    public operator func !=(other: SolarTermInfo): Bool {
        return !(this == other)
    }

    public func toString(): String {
        return "${dateKey} ${name}"
    }
}

const DAY_MS: Float64 = 86400000.0
const BEIJING_OFFSET_MS: Float64 = 28800000.0
/** 2000-01-01T12:00Z = JD 2451545.0。 */
const J2000_UNIX_EPOCH_MS: Float64 = 946728000000.0
/** 1° 对应的弧度（与 `Math.PI / 180` 的双精度值相同）。 */
const RAD: Float64 = 3.141592653589793 / 180.0

/** 某年的节气表。 */
struct TermYear {
    let terms: Array<SolarTermInfo>
    let byDate: HashMap<String, String>

    init(terms: Array<SolarTermInfo>, byDate: HashMap<String, String>) {
        this.terms = terms
        this.byDate = byDate
    }
}

/** 年度节气缓存（TS 里的 `termCache`）。 */
class TermStore {
    static let lock: Mutex = Mutex()
    static let years: HashMap<Int64, TermYear> = HashMap<Int64, TermYear>()
}

/** 某年 24 节气的北京时间日期（按小寒 → 冬至排列）；超出 1900–2100 返回空数组。 */
public func solarTermsOfYear(year: Int64): Array<SolarTermInfo> {
    if (year < 1900 || year > 2100) {
        return Array<SolarTermInfo>()
    }
    let cached = termYearOf(year)
    if (cached.terms.size == 0) {
        return Array<SolarTermInfo>()
    }
    let copy = Array<SolarTermInfo>(cached.terms.size, repeat: cached.terms[0])
    for (index in 0..cached.terms.size) {
        copy[index] = cached.terms[index]
    }
    return copy
}

/** 当日节气名（北京时间日期）；不是节气日或超出 1900–2100 返回 `None`。 */
public func solarTermOf(dateKey: String): ?String {
    let dayNumber = dayNumberOfKey(dateKey)
    if (dayNumber.isNone() || !inSupportedRange(dayNumber.getOrThrow())) {
        return None
    }
    let year = Int64.parse(dateKey[0..4])
    if (year < 1900 || year > 2100) {
        return None
    }
    return termYearOf(year).byDate.get(dateKey)
}

/** 当天是否某个「以节气定日」的节日（目前仅清明），是则返回节名。 */
public func solarTermFestivalOf(dateKey: String): ?String {
    if (solarTermOf(dateKey) == Some("清明")) {
        return Some("清明")
    }
    return None
}

func termYearOf(year: Int64): TermYear {
    synchronized(TermStore.lock) {
        match (TermStore.years.get(year)) {
            case Some(value) => return value
            case None => ()
        }
        let computed = computeTermYear(year)
        TermStore.years[year] = computed
        return computed
    }
}

func computeTermYear(year: Int64): TermYear {
    let terms = ArrayList<SolarTermInfo>()
    let byDate = HashMap<String, String>()
    for (index in 0..24) {
        let dateKey = solarTermDateKey(year, index)
        if (!byDate.contains(dateKey)) {
            terms.add(SolarTermInfo(SOLAR_TERM_NAMES[index], dateKey))
        }
        byDate[dateKey] = SOLAR_TERM_NAMES[index]
    }
    return TermYear(terms.toArray(), byDate)
}

/** 某年第 index 个节气（0 = 小寒）的北京时间日期。 */
func solarTermDateKey(year: Int64, index: Int64): String {
    let ms = solarTermTimeMs(year, index) + BEIJING_OFFSET_MS
    return keyOfDayNumber(Int64(floor(ms / DAY_MS)))
}

/** 某年第 index 个节气的北京时间毫秒时间戳（可为小数）。 */
func solarTermTimeMs(year: Int64, index: Int64): Float64 {
    let target = SOLAR_TERM_LONGITUDES[index]
    // 初值：1 月 1 日 + 每个节气间隔约 15.2184 天
    var ms = Float64(dayNumberOf(year, 1, 1)) * DAY_MS + (Float64(index) * 15.2184 + 4.5) * DAY_MS
    for (_ in 0..30) {
        let jde = julianDayFromUnixMs(ms) + deltaTSeconds(year) / 86400.0
        var diff = normalizeDegrees(sunApparentLongitude(jde) - target)
        if (diff > 180.0) {
            diff -= 360.0
        }
        if (abs(diff) < 1e-8) {
            break
        }
        ms -= (diff / 0.98564736) * DAY_MS
    }
    return ms
}

func julianDayFromUnixMs(ms: Float64): Float64 {
    return (ms - J2000_UNIX_EPOCH_MS) / DAY_MS + 2451545.0
}

func normalizeDegrees(value: Float64): Float64 {
    return fmod(fmod(value, 360.0) + 360.0, 360.0)
}

/** ΔT = TT − UT（秒），Espenak–Meeus 多项式，覆盖 1900–2100。 */
func deltaTSeconds(year: Int64): Float64 {
    let y = Float64(year)
    if (year < 1920) {
        let t = y - 1900.0
        return -2.79 + 1.494119 * t - 0.0598939 * t * t + 0.0061966 * t * t * t - 0.000197 * t * t * t * t
    }
    if (year < 1941) {
        let t = y - 1920.0
        return 21.2 + 0.84493 * t - 0.0761 * t * t + 0.0020936 * t * t * t
    }
    if (year < 1961) {
        let t = y - 1950.0
        return 29.07 + 0.407 * t - t * t / 233.0 + t * t * t / 2547.0
    }
    if (year < 1986) {
        let t = y - 1975.0
        return 45.45 + 1.067 * t - t * t / 260.0 - t * t * t / 718.0
    }
    if (year < 2005) {
        let t = y - 2000.0
        return 63.86 + 0.3345 * t - 0.060374 * t * t + 0.0017275 * t * t * t + 0.000651814 * t * t * t * t +
            0.00002373599 * t * t * t * t * t
    }
    if (year < 2050) {
        let t = y - 2000.0
        return 62.92 + 0.32217 * t + 0.005589 * t * t
    }
    let u = (y - 1820.0) / 100.0
    return -20.0 + 32.0 * u * u - 0.5628 * (2150.0 - y)
}

/** 太阳视黄经（度），入参为力学时儒略日（JDE）。 */
func sunApparentLongitude(jde: Float64): Float64 {
    let t = (jde - 2451545.0) / 36525.0
    let meanLongitude = 280.46646 + 36000.76983 * t + 0.0003032 * t * t
    let meanAnomaly = (357.52911 + 35999.05029 * t - 0.0001537 * t * t) * RAD
    let equationOfCenter = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(meanAnomaly) + (0.019993 - 0.000101 * t) *
        sin(2.0 * meanAnomaly) + 0.000289 * sin(3.0 * meanAnomaly)
    let omega = (125.04 - 1934.136 * t) * RAD
    var lambda = meanLongitude + equationOfCenter - 0.00569 - 0.00478 * sin(omega)

    // 行星长周期摄动（Meeus 第 25 章）
    let a = (153.23 + 22518.7541 * t) * RAD
    let b = (216.57 + 45037.5082 * t) * RAD
    let c = (312.69 + 32964.3577 * t) * RAD
    let d = (350.74 + 445267.1142 * t - 0.00144 * t * t) * RAD
    let e = (231.19 + 20.2 * t) * RAD
    lambda += 0.00134 * cos(a) + 0.00154 * cos(b) + 0.002 * cos(c) + 0.00179 * sin(d) + 0.00178 * sin(e)
    return normalizeDegrees(lambda)
}
