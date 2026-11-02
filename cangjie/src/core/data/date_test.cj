package textura.core.data

import std.unittest.*
import std.unittest.testmacro.*

/**
 * Date helpers must behave like `date-fns` under `Asia/Shanghai`, and never
 * read the wall clock when a clock is injected.
 */

@Test
func dateParsesIsoUtc(): Unit {
    match (parseIsoMillis("2026-03-16T02:00:00.000Z")) {
        case Some(millis) => @Expect(millis, TEST_ANCHOR)
        case None => @Expect(false, true)
    }
    // Same instant expressed with the +08:00 offset.
    match (parseIsoMillis("2026-03-16T10:00:00+08:00")) {
        case Some(millis) => @Expect(millis, TEST_ANCHOR)
        case None => @Expect(false, true)
    }
    // Date-only input means local midnight.
    match (parseIsoMillis("2026-03-16")) {
        case Some(millis) => @Expect(localDateKey(millis), "2026-03-16")
        case None => @Expect(false, true)
    }
    match (parseIsoMillis("not-a-date")) {
        case Some(_) => @Expect(false, true)
        case None => @Expect(true, true)
    }
}

@Test
func dateFormatsAsJavascriptToIsoString(): Unit {
    @Expect(isoFromMillis(TEST_ANCHOR), "2026-03-16T02:00:00.000Z")
    @Expect(localDateKey(TEST_ANCHOR), "2026-03-16")
    @Expect(localDateTimeKey(TEST_ANCHOR), "2026-03-16 10:00")
    @Expect(nowIso(FixedClock(TEST_ANCHOR)), "2026-03-16T02:00:00.000Z")
}

@Test
func dateUsesShanghaiCalendarDay(): Unit {
    // 2026-03-15T20:00Z is 2026-03-16 04:00 in Shanghai.
    match (parseIsoMillis("2026-03-15T20:00:00.000Z")) {
        case Some(millis) => @Expect(localDateKey(millis), "2026-03-16")
        case None => @Expect(false, true)
    }
    // The textual `dateKey` helper intentionally keeps the UTC prefix.
    @Expect(dateKey("2026-03-15T20:00:00.000Z") ?? "", "2026-03-15")
    match (localDayKey("2026-03-15T20:00:00.000Z")) {
        case Some(value) => @Expect(value, "2026-03-16")
        case None => @Expect(false, true)
    }
}

@Test
func dateQuarters(): Unit {
    @Expect(currentQuarter(TEST_ANCHOR), "2026-Q1")
    @Expect(currentQuarter(FixedClock(TEST_ANCHOR)), "2026-Q1")
    match (quarterRange("2026-Q1")) {
        case Some(range) =>
            @Expect(range.start, "2026-01-01")
            @Expect(range.end, "2026-03-31")
        case None => @Expect(false, true)
    }
    match (quarterRange("2026-Q4")) {
        case Some(range) =>
            @Expect(range.start, "2026-10-01")
            @Expect(range.end, "2026-12-31")
        case None => @Expect(false, true)
    }
    match (quarterRange("2026-Q5")) {
        case Some(_) => @Expect(false, true)
        case None => @Expect(true, true)
    }
    match (quarterRange("nope")) {
        case Some(_) => @Expect(false, true)
        case None => @Expect(true, true)
    }
}

@Test
func dateOffsets(): Unit {
    @Expect(dayOffset(-1, TEST_ANCHOR), "2026-03-15")
    @Expect(dayOffset(0, TEST_ANCHOR), "2026-03-16")
    @Expect(dayOffset(16, TEST_ANCHOR), "2026-04-01")
    @Expect(isoOffset(0, TEST_ANCHOR), "2026-03-16T02:00:00.000Z")
    @Expect(isoOffset(-1, TEST_ANCHOR), "2026-03-15T02:00:00.000Z")
    @Expect(addDaysToKey("2026-03-16", 5), "2026-03-21")
    @Expect(addDaysToKey("2026-02-28", 1), "2026-03-01")
    @Expect(addDaysToKey("2024-02-28", 1), "2024-02-29")
}

@Test
func dateDayDiffs(): Unit {
    @Expect(daysBetween("2026-03-10", "2026-03-16"), 6)
    @Expect(daysBetween("2026-03-16", "2026-03-10"), -6)
    @Expect(daysBetween("2026-03-16", "2026-03-16"), 0)
    @Expect(daysBetween("bad", "2026-03-16"), 0)
}

@Test
func dateFormattingHelpers(): Unit {
    @Expect(formatDateKey(Some("2026-02-04T02:00:00.000Z")), "02/04")
    @Expect(formatDateKey(Some("2026-02-04"), pattern: "yyyy-MM-dd"), "2026-02-04")
    @Expect(formatDateKey(Some("nope")), "—")
    @Expect(formatDateTime(Some("2026-02-04T02:00:00.000Z")), "2026-02-04 10:00")
    @Expect(formatDateTime(None), "—")
    @Expect(formatWithPattern(TEST_ANCHOR, "yyyy年M月 d"), "2026年3月 16")
    @Expect(formatWithPattern(TEST_ANCHOR, "MM/dd HH:mm:ss"), "03/16 10:00:00")
}

@Test
func dateWeekAndMonthBounds(): Unit {
    // 2026-03-16 is a Monday.
    @Expect(dayOfWeek(TEST_ANCHOR), 1)
    @Expect(startOfWeekKey("2026-03-16"), "2026-03-16")
    @Expect(endOfWeekKey("2026-03-16"), "2026-03-22")
    @Expect(startOfWeekKey("2026-03-18"), "2026-03-16")
    @Expect(startOfMonthKey("2026-03-16"), "2026-03-01")
    @Expect(endOfMonthKey("2026-03-16"), "2026-03-31")
    @Expect(endOfMonthKey("2026-02-10"), "2026-02-28")
    @Expect(yearOfKey("2026-03-16"), 2026)
}

@Test
func dateRelativeLabels(): Unit {
    @Expect(relativeDayLabel(Some("2026-03-16T02:00:00.000Z"), TEST_ANCHOR), "今天")
    @Expect(relativeDayLabel(Some("2026-03-15T02:00:00.000Z"), TEST_ANCHOR), "昨天")
    @Expect(relativeDayLabel(Some("2026-03-13T02:00:00.000Z"), TEST_ANCHOR), "3 天前")
    @Expect(relativeDayLabel(Some("2026-02-01T02:00:00.000Z"), TEST_ANCHOR), "02/01")
    @Expect(relativeDayLabel(None, TEST_ANCHOR), "—")
    @Expect(relativeTimeText(Some("2026-03-16T02:00:00.000Z"), TEST_ANCHOR), "不到 1 分钟前")
    @Expect(relativeTimeText(Some("2026-03-16T00:00:00.000Z"), TEST_ANCHOR), "约 2 小时前")
}

@Test
func dateClockInjectionIsDeterministic(): Unit {
    let frozen = FixedClock(TEST_ANCHOR)
    @Expect(nowIso(frozen), nowIso(frozen))
    @Expect(currentQuarter(frozen), "2026-Q1")
    @Expect(dayOffset(-3, frozen), "2026-03-13")
    @Expect(isBeforeSystemNow(frozen), true)
}

func isBeforeSystemNow(clock: Clock): Bool {
    clock.nowMillis() != systemNowMillis()
}
