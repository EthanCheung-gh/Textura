package textura.views.calendar.logic

import std.unittest.*
import std.unittest.testmacro.*
import std.collection.*
import std.time.*

/**
 * 农历引擎验收：逐条移植 `src/modules/calendar/lunar.test.ts` 的全部断言，
 * 并追加一次 1900-01-31 ～ 2100-12-31 的全区间摘要对拍。
 */
@Test
class LunarTest {
    /** 春节（正月初一）。 */
    let SPRING_FESTIVALS = [
        "1900-01-31",
        "2020-01-25",
        "2021-02-12",
        "2022-02-01",
        "2023-01-22",
        "2024-02-10",
        "2025-01-29",
        "2026-02-17",
        "2027-02-06",
        "2028-01-26",
        "2029-02-13",
        "2030-02-03"
    ]

    /** 中秋（八月十五）。 */
    let MID_AUTUMNS = ["2024-09-17", "2025-10-06", "2026-09-25", "2027-09-15", "2028-10-03"]

    /** 端午（五月初五）。 */
    let DUANWUS = ["2024-06-10", "2025-05-31", "2026-06-19", "2027-06-09"]

    @TestCase
    func springFestivals(): Unit {
        for (key in SPRING_FESTIVALS) {
            let lunar = solarToLunar(key)
            @Expect(lunar.isSome(), true)
            let date = lunar.getOrThrow()
            @Expect(date.month, 1)
            @Expect(date.day, 1)
            @Expect(date.isLeap, false)
            @Expect(date.monthName, "正月")
            @Expect(date.dayName, "初一")
            @Expect(date.festival, Some("春节"))
            // 反向：该年正月初一回推为同一天
            @Expect(lunarToSolar(date.year, 1, 1), Some(key))
        }
    }

    @TestCase
    func midAutumns(): Unit {
        for (key in MID_AUTUMNS) {
            let lunar = solarToLunar(key)
            @Expect(lunar.isSome(), true)
            let date = lunar.getOrThrow()
            @Expect(date.month, 8)
            @Expect(date.day, 15)
            @Expect(date.isLeap, false)
            @Expect(date.monthName, "八月")
            @Expect(date.dayName, "十五")
            @Expect(date.festival, Some("中秋"))
            @Expect(lunarToSolar(date.year, 8, 15), Some(key))
        }
    }

    @TestCase
    func duanwus(): Unit {
        for (key in DUANWUS) {
            let lunar = solarToLunar(key)
            @Expect(lunar.isSome(), true)
            let date = lunar.getOrThrow()
            @Expect(date.month, 5)
            @Expect(date.day, 5)
            @Expect(date.isLeap, false)
            @Expect(date.festival, Some("端午"))
            @Expect(lunarToSolar(date.year, 5, 5), Some(key))
        }
    }

    @TestCase
    func leapMonth2023(): Unit {
        let lunar = solarToLunar("2023-03-22")
        @Expect(lunar.isSome(), true)
        let date = lunar.getOrThrow()
        @Expect(date.month, 2)
        @Expect(date.day, 1)
        @Expect(date.isLeap, true)
        @Expect(date.monthName, "闰二月")
        @Expect(lunarToSolar(2023, 2, 1, true), Some("2023-03-22"))
    }

    @TestCase
    func dayBeforeLeapMonth2023(): Unit {
        let lunar = solarToLunar("2023-03-21")
        @Expect(lunar.isSome(), true)
        let date = lunar.getOrThrow()
        @Expect(date.month, 2)
        @Expect(date.isLeap, false)
        @Expect(date.day, 30)
    }

    @TestCase
    func leapMonth2025(): Unit {
        let lunar = solarToLunar("2025-07-25")
        @Expect(lunar.isSome(), true)
        let date = lunar.getOrThrow()
        @Expect(date.month, 6)
        @Expect(date.day, 1)
        @Expect(date.isLeap, true)
        @Expect(date.monthName, "闰六月")
        @Expect(lunarToSolar(2025, 6, 1, true), Some("2025-07-25"))
    }

    @TestCase
    func nonexistentLeapMonths(): Unit {
        @Expect(lunarToSolar(2023, 3, 1, true).isNone(), true)
        @Expect(lunarToSolar(2026, 2, 1, true).isNone(), true)
    }

    @TestCase
    func leapMonthTable(): Unit {
        @Expect(isLeapMonth(2023), 2)
        @Expect(isLeapMonth(2025), 6)
        @Expect(isLeapMonth(2024), 0)
        @Expect(isLeapMonth(2026), 0)
        @Expect(leapMonthDays(2023), 29)
        @Expect(leapMonthDays(2025), 29)
        @Expect(leapMonthDays(2024), 0)
        @Expect(lunarMonthDays(2023, 2), 30)
        @Expect(lunarYearDays(2023), 384)
        @Expect(lunarYearDays(2024), 354)
        // 范围外按 TS 约定返回 0
        @Expect(isLeapMonth(1899), 0)
        @Expect(lunarYearDays(2101), 0)
        @Expect(lunarMonthDays(2026, 13), 0)
    }

    @TestCase
    func solarTerms2026(): Unit {
        let expected = [
            ("2026-02-04", "立春"),
            ("2026-03-20", "春分"),
            ("2026-04-05", "清明"),
            ("2026-06-21", "夏至"),
            ("2026-09-23", "秋分"),
            ("2026-12-22", "冬至")
        ]
        for (pair in expected) {
            @Expect(solarTermOf(pair[0]), Some(pair[1]))
        }
    }

    @TestCase
    func solarTerms2026Structure(): Unit {
        let terms = solarTermsOfYear(2026)
        @Expect(terms.size, 24)
        let names = HashSet<String>()
        let dates = HashSet<String>()
        for (term in terms) {
            names.add(term.name)
            dates.add(term.dateKey)
        }
        @Expect(names.size, 24)
        @Expect(dates.size, 24)
        for (index in 1..terms.size) {
            @Expect(terms[index - 1].dateKey < terms[index].dateKey, true)
        }
        for (term in terms) {
            @Expect(solarTermOf(term.dateKey), Some(term.name))
        }
    }

    @TestCase
    func solarTermNames(): Unit {
        let expected = [
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
        let terms = solarTermsOfYear(2026)
        for (index in 0..24) {
            @Expect(terms[index].name, expected[index])
        }
        @Expect(SOLAR_TERM_NAMES.size, 24)
    }

    @TestCase
    func qingmingIsBothTermAndFestival(): Unit {
        @Expect(solarTermFestivalOf("2026-04-05"), Some("清明"))
        @Expect(solarTermOf("2026-04-05"), Some("清明"))
        @Expect(festivalOf("2026-04-05"), Some("清明"))
        @Expect(solarTermFestivalOf("2026-04-06").isNone(), true)
    }

    @TestCase
    func nonTermDays(): Unit {
        @Expect(solarTermOf("2026-04-06").isNone(), true)
        @Expect(solarTermOf("2026-10-21").isNone(), true)
    }

    @TestCase
    func solarTermsAcrossRangeEdges(): Unit {
        for (year in [1900, 1950, 2000, 2050, 2100]) {
            let terms = solarTermsOfYear(year)
            @Expect(terms.size, 24)
            let days = HashSet<String>()
            for (term in terms) {
                days.add(term.dateKey)
            }
            @Expect(days.size, 24)
            for (index in 1..terms.size) {
                @Expect(terms[index - 1].dateKey < terms[index].dateKey, true)
            }
            let prefix = "${year.toString()}-"
            for (term in terms) {
                @Expect(term.dateKey.startsWith(prefix), true)
                // 1900-01-31 之前的节气不在农历支持范围内，按约定返回 None
                let expected: ?String = if (term.dateKey >= LUNAR_MIN_KEY) {
                    Some(term.name)
                } else {
                    None
                }
                @Expect(solarTermOf(term.dateKey), expected)
            }
        }
        // 超出 1900–2100 无节气
        @Expect(solarTermsOfYear(1899).size, 0)
        @Expect(solarTermsOfYear(2101).size, 0)
    }

    /** 全部 201 年的 24 节气逐一对照 TS 实现输出的黄金值。 */
    @TestCase
    func solarTermsMatchTypeScriptForEveryYear(): Unit {
        @Expect(SOLAR_TERM_TRUTH.size, 201)
        for (line in SOLAR_TERM_TRUTH) {
            let year = digitsOf(line, 0, 4)
            let terms = solarTermsOfYear(year)
            @Expect(terms.size, 24)
            let expected = line[5..line.size].split(",")
            @Expect(expected.size, 24)
            for (index in 0..24) {
                @Expect("${year.toString()}-${expected[index]}", terms[index].dateKey)
            }
        }
    }

    @TestCase
    func lunarNewYearEve2026(): Unit {
        let lunar = solarToLunar("2026-02-16")
        @Expect(lunar.isSome(), true)
        let date = lunar.getOrThrow()
        @Expect(date.year, 2025)
        @Expect(date.month, 12)
        @Expect(date.day, 29)
        @Expect(date.monthName, "腊月")
        @Expect(date.dayName, "廿九")
        @Expect(date.festival, Some("除夕"))
        @Expect(date.solarTerm.isNone(), true)
    }

    @TestCase
    func springFestivalDayIsNotNewYearEve(): Unit {
        @Expect(solarToLunar("2026-02-17").getOrThrow().festival, Some("春节"))
    }

    @TestCase
    func ganzhiSwitchesAtSpringFestival(): Unit {
        let after = solarToLunar("2026-02-17").getOrThrow()
        @Expect(after.year, 2026)
        @Expect(after.ganzhiYear, "丙午")
        @Expect(after.zodiac, "马")

        let before = solarToLunar("2026-02-16").getOrThrow()
        @Expect(before.year, 2025)
        @Expect(before.ganzhiYear, "乙巳")
        @Expect(before.zodiac, "蛇")

        let first = solarToLunar("1900-01-31").getOrThrow()
        @Expect(first.ganzhiYear, "庚子")
        @Expect(first.zodiac, "鼠")
    }

    @TestCase
    func ganzhiCycle(): Unit {
        // 60 年一个循环
        let base = ganzhiOfYear(2026)
        @Expect(base.ganzhi, "丙午")
        @Expect(base.zodiac, "马")
        @Expect(ganzhiOfYear(2026 + 60).ganzhi, "丙午")
        @Expect(ganzhiOfYear(2026 + 1).ganzhi, "丁未")
        @Expect(ganzhiOfYear(2026 - 1).ganzhi, "乙巳")
    }

    @TestCase
    func monthNames(): Unit {
        let expected = [
            "正月",
            "二月",
            "三月",
            "四月",
            "五月",
            "六月",
            "七月",
            "八月",
            "九月",
            "十月",
            "冬月",
            "腊月"
        ]
        for (index in 0..12) {
            @Expect(lunarMonthName(index + 1), expected[index])
        }
        @Expect(lunarMonthName(6, true), "闰六月")
    }

    @TestCase
    func dayNames(): Unit {
        let expected = [
            "初一",
            "初二",
            "初三",
            "初四",
            "初五",
            "初六",
            "初七",
            "初八",
            "初九",
            "初十",
            "十一",
            "十二",
            "十三",
            "十四",
            "十五",
            "十六",
            "十七",
            "十八",
            "十九",
            "二十",
            "廿一",
            "廿二",
            "廿三",
            "廿四",
            "廿五",
            "廿六",
            "廿七",
            "廿八",
            "廿九",
            "三十"
        ]
        for (index in 0..30) {
            @Expect(lunarDayName(index + 1), expected[index])
        }
        @Expect(lunarDayName(0), "")
        @Expect(lunarDayName(31), "")
    }

    @TestCase
    func leapMonthLength(): Unit {
        @Expect(lunarToSolar(2023, 2, 1, true), Some("2023-03-22"))
        @Expect(lunarToSolar(2023, 2, 29, true), Some("2023-04-19"))
        @Expect(lunarToSolar(2023, 2, 30, true).isNone(), true)
    }

    /** 2000-01-01 ～ 2050-12-31 每天 solarToLunar → lunarToSolar 还原。 */
    @TestCase
    func roundTripEveryDayTwoThousandToTwentyFifty(): Unit {
        let start = dayNumberOfKey("2000-01-01").getOrThrow()
        let end = dayNumberOfKey("2050-12-31").getOrThrow()
        var checked: Int64 = 0
        var failures = ArrayList<String>()
        for (dayNumber in start..=end) {
            let key = keyOfDayNumber(dayNumber)
            let lunar = solarToLunar(key)
            if (lunar.isNone()) {
                failures.add("${key}: null")
                continue
            }
            let date = lunar.getOrThrow()
            let back = lunarToSolar(date.year, date.month, date.day, date.isLeap)
            let restored = match (back) {
                case Some(value) => value
                case None => "<null>"
            }
            if (restored != key) {
                failures.add("${key} -> ${restored}")
            }
            checked += 1
        }
        @Expect(checked, 18628)
        @Expect(failures.size, 0)
    }

    /**
     * 全区间（1900-01-31 ～ 2100-12-31，共 73384 天）摘要对拍：
     * 黄金值由 TS `solarToLunar` 逐日输出后按同一多项式哈希计算得到。
     */
    @TestCase
    func fullRangeDigestMatchesTypeScript(): Unit {
        let records = ArrayList<String>()
        let start = dayNumberOfKey(LUNAR_MIN_KEY).getOrThrow()
        let end = dayNumberOfKey(LUNAR_MAX_KEY).getOrThrow()
        for (dayNumber in start..=end) {
            let key = keyOfDayNumber(dayNumber)
            match (solarToLunar(key)) {
                case Some(date) =>
                    let leap = if (date.isLeap) {
                        1
                    } else {
                        0
                    }
                    let festival = date.festival ?? "-"
                    let term = date.solarTerm ?? "-"
                    records.add(
                        "${key},${date.year},${date.month},${date.day},${leap},${date.monthName},${date.dayName},${date.ganzhiYear},${date.zodiac},${festival},${term}")
                case None => records.add("${key}:null")
            }
        }
        @Expect(records.size, 73384)
        @Expect(digestOf(records.toArray()), 379894082)

        // 201 个春节日期的摘要
        let springs = ArrayList<String>()
        for (year in 1900..=2100) {
            springs.add(lunarToSolar(year, 1, 1) ?? "null")
        }
        @Expect(springs.size, 201)
        @Expect(digestOf(springs.toArray()), 488893810)
    }

    @TestCase
    func rangeBoundaries(): Unit {
        @Expect(solarToLunar(LUNAR_MIN_KEY).getOrThrow().month, 1)
        @Expect(solarToLunar("1900-01-30").isNone(), true)
        @Expect(solarToLunar("2099-12-31").isSome(), true)
        @Expect(solarToLunar(LUNAR_MAX_KEY).getOrThrow().month, 12)
        @Expect(solarToLunar("2101-01-01").isNone(), true)
        @Expect(solarToLunar("not-a-date").isNone(), true)
        @Expect(lunarToSolar(1899, 12, 1).isNone(), true)
        @Expect(lunarToSolar(2101, 1, 1).isNone(), true)
        @Expect(lunarToSolar(2026, 13, 1).isNone(), true)
        @Expect(lunarToSolar(2026, 1, 31).isNone(), true)
        @Expect(lunarToSolar(2100, 12, 1), Some("2100-12-31"))
        @Expect(lunarToSolar(2100, 12, 2).isNone(), true)
        @Expect(festivalOf("2101-01-01").isNone(), true)
        @Expect(festivalOf("1900-01-30").isNone(), true)
    }

    @TestCase
    func reverseRoundTripAtBoundaries(): Unit {
        for (key in ["1900-01-31", "2099-12-31", "2100-12-31"]) {
            let lunar = solarToLunar(key)
            @Expect(lunar.isSome(), true)
            let date = lunar.getOrThrow()
            @Expect(lunarToSolar(date.year, date.month, date.day, date.isLeap), Some(key))
        }
    }

    /** 42 格 × 20 轮的农历换算应在毫秒级完成（拦住「每天线性扫描」实现）。 */
    @TestCase
    func conversionIsFast(): Unit {
        solarToLunar("2026-10-01")
        let started = MonoTime.now()
        for (round in 0..20) {
            for (day in 1..=42) {
                let month = pad2(round % 12 + 1)
                let dayPart = pad2((day - 1) % 28 + 1)
                solarToLunar("2026-${month}-${dayPart}")
            }
        }
        let elapsed = (MonoTime.now() - started).toMilliseconds()
        @Expect(elapsed < 40, true)
    }
}

/** 多项式哈希（与 TS 侧生成黄金值时完全相同的算法）。 */
func digestOf(records: Array<String>): Int64 {
    var hash: Int64 = 7
    for (record in records) {
        for (byte in record.toArray()) {
            hash = (hash * 131 + Int64(byte)) % 1000000007
        }
        hash = (hash * 1000003 + 17) % 1000000007
    }
    return hash
}
