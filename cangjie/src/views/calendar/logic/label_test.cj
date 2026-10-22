package textura.views.calendar.logic

import std.unittest.*
import std.unittest.testmacro.*

/**
 * 文案层验收：逐条移植 `calendarLogic.test.ts` 的「农历标签优先级」
 * 与「无障碍与相对日期文案」「shouldAutoOpenPanel」断言。
 */
@Test
class LabelTest {
    @TestCase
    func festivalBeatsTermAndLunarDay(): Unit {
        @Expect(lunarLabel("2026-09-25"), "中秋")
        @Expect(lunarLabelInfo("2026-09-25"), LabelTone(LunarLabelKind.Festival, "中秋"))
    }

    @TestCase
    func qingmingCountsAsFestival(): Unit {
        @Expect(lunarLabel("2026-04-05"), "清明")
        @Expect(lunarLabelInfo("2026-04-05").kind, LunarLabelKind.Festival)
    }

    @TestCase
    func termBeatsLunarDay(): Unit {
        @Expect(lunarLabel("2026-09-23"), "秋分")
        @Expect(lunarLabelInfo("2026-09-23"), LabelTone(LunarLabelKind.Term, "秋分"))
    }

    @TestCase
    func firstDayShowsMonthName(): Unit {
        @Expect(lunarLabel("2026-10-10"), "九月")
        @Expect(lunarLabelInfo("2026-10-10").kind, LunarLabelKind.Lunar)
    }

    @TestCase
    func otherDaysShowDayName(): Unit {
        @Expect(lunarLabel("2026-10-21"), "十二")
    }

    @TestCase
    func leapMonthFirstDayShowsLeapMonthName(): Unit {
        let lunar = solarToLunar("2025-07-25")
        @Expect(lunar.isSome(), true)
        @Expect(lunarLabel("2025-07-25"), lunar.getOrThrow().monthName)
        @Expect(lunarLabel("2025-07-25"), "闰六月")
    }

    @TestCase
    func outOfRangeGivesEmptyLabel(): Unit {
        @Expect(lunarLabel("1900-01-01"), "")
        @Expect(lunarLabelInfo("2101-05-01"), LabelTone(LunarLabelKind.NoLabel, ""))
        @Expect(lunarLabelInfo("not-a-date").kind, LunarLabelKind.NoLabel)
    }

    @TestCase
    func lunarFullLabelText(): Unit {
        let lunar = solarToLunar("2026-10-21")
        @Expect(lunar.isSome(), true)
        @Expect(lunarFullLabel(lunar.getOrThrow()), "丙午年 九月十二")
    }

    @TestCase
    func fullDateLabelText(): Unit {
        @Expect(fullDateLabel("2026-10-21"), "2026年10月21日 星期三")
        @Expect(fullDateLabel("not-a-date"), "")
    }

    @TestCase
    func ariaLabelWithToday(): Unit {
        @Expect(cellAriaLabel("2026-10-21", "2026-10-21"), "2026年10月21日，星期三，农历九月十二，今天")
        @Expect(cellAriaLabel("2026-10-21", "2026-10-22"), "2026年10月21日，星期三，农历九月十二")
    }

    @TestCase
    func ariaLabelIncludesFestival(): Unit {
        @Expect(cellAriaLabel("2026-09-25", "2026-10-21"), "2026年9月25日，星期五，农历八月十五，中秋")
    }

    @TestCase
    func ariaLabelIncludesTermSuffix(): Unit {
        @Expect(cellAriaLabel("2026-09-23", "2026-10-21"), "2026年9月23日，星期三，农历八月十三，秋分节气")
    }

    @TestCase
    func ariaLabelWithoutLunarData(): Unit {
        // 超出农历范围：只有公历与星期
        @Expect(cellAriaLabel("1900-01-01", "1900-01-01"), "1900年1月1日，星期一，今天")
    }

    @TestCase
    func relativeDayLabels(): Unit {
        @Expect(relativeDayLabel("2026-10-21", "2026-10-21"), "今天")
        @Expect(relativeDayLabel("2026-10-22", "2026-10-21"), "明天")
        @Expect(relativeDayLabel("2026-10-20", "2026-10-21"), "昨天")
        @Expect(relativeDayLabel("2026-10-31", "2026-10-21"), "10 天后")
        @Expect(relativeDayLabel("2026-10-11", "2026-10-21"), "10 天前")
        @Expect(relativeDayLabel("2026-11-30", "2026-10-21"), "40 天后")
        @Expect(relativeDayLabel("bad", "2026-10-21"), "")
        @Expect(relativeDayLabel("2026-10-21", "bad"), "")
    }

    @TestCase
    func autoOpenPanelOnNarrowViewport(): Unit {
        @Expect(shouldAutoOpenPanel(false, 1024, false), true)
    }

    @TestCase
    func noAutoOpenOnWideViewport(): Unit {
        @Expect(shouldAutoOpenPanel(false, 1440, false), false)
    }

    @TestCase
    func noAutoOpenWhenAlreadyOpen(): Unit {
        @Expect(shouldAutoOpenPanel(true, 1024, false), false)
    }

    @TestCase
    func respectUserCollapse(): Unit {
        @Expect(shouldAutoOpenPanel(false, 1024, true), false)
    }

    @TestCase
    func breakpointIsInclusive(): Unit {
        @Expect(shouldAutoOpenPanel(false, 1180, false), true)
        @Expect(shouldAutoOpenPanel(false, 1181, false), false)
        @Expect(PANEL_BREAKPOINT, 1180)
        // 显式断点覆盖
        @Expect(shouldAutoOpenPanel(false, 900, false, 900), true)
        @Expect(shouldAutoOpenPanel(false, 901, false, 900), false)
    }
}
