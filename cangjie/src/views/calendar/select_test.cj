package textura.views.calendar

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.ui.*
import textura.views.calendar.logic.*

/*
 * 工具栏年 / 月选择器（用户反馈：年份没有默认选中今年、月份列表不全）。
 *
 * 修法在 `select.cj`：打开时把滚动窗口移到当前值（年份 201 项，旧实现固定从 1900 开始，
 * 所以看不到当年），并把可见行数从 8 提到 12（月份 1–12 一次看全）。
 */

private let SELECT_TEST_RECT: Rect = Rect(0.0, 0.0, 1440.0, 900.0)
/** The widget is the root of the test frame, so its box is the frame origin. */
private let SELECT_TEST_FIELD: Rect = Rect(0.0, 0.0, 94.0, 32.0)

private func monthValues(options: Array<SelectOption>): Array<String> {
    let values = ArrayList<String>()
    for (option in options) {
        values.add(option.value)
    }
    values.toArray()
}

@Test
func monthOptionsCoverAllTwelveMonths(): Unit {
    let options = monthOptions()
    @Expect(options.size, Int64(12))
    let values = monthValues(options)
    var month: Int64 = 1
    while (month <= 12) {
        @Expect(values[month - 1], "${month}")
        @Expect(options[month - 1].label.isEmpty(), false)
        month += 1
    }
    // No duplicate labels/values: the old popup cut the list at 8 rows, so 九月–十二月 were invisible.
    @Expect(options[8].label, "九月")
    @Expect(options[9].label, "十月")
    @Expect(options[10].label, "十一月")
    @Expect(options[11].label, "十二月")
}

@Test
func yearOptionsMatchTheWebRange(): Unit {
    let options = yearOptions()
    // `calendarLogic.ts:352` builds 1900…2100 inclusive.
    @Expect(options.size, Int64(201))
    @Expect(options[0].value, "1900")
    @Expect(options[0].label, "1900年")
    @Expect(options[200].value, "2100")
    @Expect(options[200].label, "2100年")
}

@Test
func openingTheYearSelectScrollsToTheCurrentYear(): Unit {
    let options = yearOptions()
    let today = parseKey("2026-10-23")
    let year = match (today) {
        case Some(value) => value.year
        case None => Int64(0)
    }
    @Expect(year, Int64(2026))
    let rows = calSelectVisibleRows(options, 900.0, SELECT_TEST_FIELD.bottom())
    @Expect(rows, Int64(12))
    let offset = calSelectInitialScroll(options, "${year}", rows)
    let index = 1900 + offset
    @Expect(index <= year, true)
    @Expect(year < 1900 + offset + rows, true)
}

@Test
func monthSelectShowsEveryRowWithoutScrolling(): Unit {
    let options = monthOptions()
    // A 900px window leaves room for all twelve 26px rows below the toolbar.
    @Expect(calSelectVisibleRows(options, 900.0, SELECT_TEST_FIELD.bottom()), Int64(12))
    let offset = calSelectInitialScroll(options, "10", 12)
    @Expect(offset, Int64(0))
    @Expect(options[offset + 9].value, "10")
}

/** Clicking the closed box opens it and aligns the window on the current value (2026). */
@Test
func clickingTheYearFieldOpensOnThisYear(): Unit {
    let openState = State<Int64>(0)
    let scrollState = State<Int64>(0)
    let host = WidgetTestHost()
    let today = match (parseKey("2026-10-23")) {
        case Some(value) => value
        case None => Ymd(1970, 1, 1)
    }
    let body: () -> Unit = {=>
        CalSelectView(tokensOf(texturaLight()), "${today.year}年", yearOptions(), "${today.year}", 1, openState,
            scrollState, {_ => ()})
            .width(SELECT_TEST_FIELD.w)
            .height(SELECT_TEST_FIELD.h)
    }
    let _ = host.frame(SELECT_TEST_RECT, body: body)
    let _ = host.frame(SELECT_TEST_RECT, events: [UiEvent.MouseDown(MouseButton.Left, SELECT_TEST_FIELD.centerX(),
        SELECT_TEST_FIELD.centerY())], body: body)
    @Expect(openState.value, Int64(1))
    let index = 1900 + scrollState.value
    @Expect(index <= today.year, true)
    @Expect(today.year < index + 12, true)
}
