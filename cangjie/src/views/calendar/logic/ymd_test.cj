package textura.views.calendar.logic

import std.unittest.*
import std.unittest.testmacro.*

/**
 * 公历日期核心的单元测试。
 *
 * 期望值与 TS 版 `dayNumberFromKey` / `keyFromDayNumber` /
 * `weekdayIndexMonday` 完全一致（1970-01-01 = 0，周一 = 0）。
 */
@Test
class YmdTest {
    @TestCase
    func dayNumberEpoch(): Unit {
        @Expect(dayNumberOfKey("1970-01-01"), Some(0))
        @Expect(dayNumberOfKey("1970-01-02"), Some(1))
        @Expect(dayNumberOfKey("1969-12-31"), Some(-1))
        @Expect(dayNumberOfKey("1900-01-31"), Some(-25537))
    }

    @TestCase
    func roundTripKeys(): Unit {
        for (key in ["1900-01-31", "2000-02-29", "2024-12-31", "2100-12-31", "1970-01-01"]) {
            @Expect(keyOfDayNumber(dayNumberOfKey(key).getOrThrow()), key)
        }
    }

    @TestCase
    func weekdayOfKnownDates(): Unit {
        // 2026-10-21 是星期三
        @Expect(weekdayOfKey("2026-10-21"), 2)
        @Expect(weekdayLabel("2026-10-21"), "星期三")
        // 2026-10-19 是星期一
        @Expect(weekdayOfKey("2026-10-19"), 0)
        @Expect(weekdayOfKey("2026-10-25"), 6)
        // 1900-01-31 是星期三
        @Expect(weekdayOfKey("1900-01-31"), 2)
        // 1970-01-01 是星期四
        @Expect(weekdayOfKey("1970-01-01"), 3)
    }

    @TestCase
    func invalidKeys(): Unit {
        @Expect(dayNumberOfKey("not-a-date"), None)
        @Expect(dayNumberOfKey("2026-1-21"), None)
        @Expect(dayNumberOfKey("2026-13-01"), None)
        @Expect(dayNumberOfKey("2026-02-30"), None)
        @Expect(dayNumberOfKey(""), None)
        // JS Date.UTC 会把 0000–0099 年解释为 19xx，回读校验失败 → null
        @Expect(dayNumberOfKey("0099-01-01"), None)
        @Expect(dayNumberOfKey("2026-02-28").isSome(), true)
        @Expect(dayNumberOfKey("2024-02-29").isSome(), true)
    }

    @TestCase
    func addDaysAcrossBoundaries(): Unit {
        @Expect(addDaysToKey("2026-10-31", 1), "2026-11-01")
        @Expect(addDaysToKey("2026-12-31", 1), "2027-01-01")
        @Expect(addDaysToKey("2026-01-01", -1), "2025-12-31")
        @Expect(addDaysToKey("2024-02-28", 1), "2024-02-29")
        @Expect(addDaysToKey("2026-02-28", 1), "2026-03-01")
        // 非法输入原样返回（等价 TS 直接回退 key）
        @Expect(addDaysToKey("nope", 3), "nope")
    }

    @TestCase
    func daysInMonthMatchesJsSemantics(): Unit {
        @Expect(daysInMonth(2026, 1), 31)
        @Expect(daysInMonth(2026, 2), 28)
        @Expect(daysInMonth(2024, 2), 29)
        @Expect(daysInMonth(1900, 2), 28)
        @Expect(daysInMonth(2000, 2), 29)
        @Expect(daysInMonth(2026, 4), 30)
        @Expect(daysInMonth(2026, 12), 31)
        // Date.UTC(year, 0, 0) = 上一年 12 月最后一天
        @Expect(daysInMonth(2026, 0), 31)
        // Date.UTC(year, 13, 0) = 次年 1 月最后一天
        @Expect(daysInMonth(2026, 13), 31)
    }

    @TestCase
    func keyOfDoesNotNormalize(): Unit {
        // 与 TS makeKey 一致：字段原样拼接，不做范围归一化
        @Expect(keyOf(2026, 10, 21), "2026-10-21")
        @Expect(keyOf(2026, 1, 1), "2026-01-01")
        @Expect(parseKey("2026-13-01").isNone(), true)
    }

    @TestCase
    func ymdComparableAndArithmetic(): Unit {
        let date = Ymd(2026, 10, 21)
        @Expect(date < Ymd(2026, 10, 22), true)
        @Expect(date > Ymd(2026, 9, 30), true)
        @Expect(date == Ymd(2026, 10, 21), true)
        @Expect(date.addingDays(7).key(), "2026-10-28")
        @Expect(date.addingDays(-21).key(), "2026-09-30")
        @Expect(Ymd(2026, 10, 21).monday().key(), "2026-10-19")
        @Expect(Ymd(2026, 10, 25).monday().key(), "2026-10-19")
    }

    @TestCase
    func dateKeyNormalization(): Unit {
        // 等价 TS core/utils.ts 的 dateKey
        @Expect(dateKeyOf("2026-10-21T10:00:00.000Z"), "2026-10-21")
        @Expect(dateKeyOf("  2026-10-21  "), "2026-10-21")
        @Expect(dateKeyOf("2026-1"), "")
        @Expect(dateKeyOf(""), "")
    }
}
