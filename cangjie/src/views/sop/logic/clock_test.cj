package textura.views.sop.logic

import std.unittest.*
import std.unittest.testmacro.*

// 时钟注入与 Asia/Shanghai 展示（对应 Web 版 new Date(iso) / formatDateTime）。

@Test
func testParseIsoMillisUtc(): Unit {
    let millis = parseIsoMillis("1970-01-01T00:00:00.000Z").getOrThrow()
    @Expect(millis, 0)
    let later = parseIsoMillis("2026-01-01T00:02:20.000Z").getOrThrow()
    @Expect(later - millis, 1767225740000)
}

@Test
func testParseIsoMillisRejectsGarbage(): Unit {
    @Expect(parseIsoMillis("bad").isNone(), true)
    @Expect(parseIsoMillis("").isNone(), true)
    @Expect(parseIsoMillis("2026-13-01T00:00:00.000Z").isNone(), true)
    @Expect(parseIsoMillis("2026-01-01T25:00:00.000Z").isNone(), true)
    @Expect(parseIsoMillis("2026-01-01T00:00:00.000Zjunk").isNone(), true)
}

@Test
func testParseIsoMillisWithOffset(): Unit {
    let utc = parseIsoMillis("2026-01-01T00:00:00.000Z").getOrThrow()
    let shanghai = parseIsoMillis("2026-01-01T08:00:00.000+08:00").getOrThrow()
    @Expect(shanghai, utc)
    let compact = parseIsoMillis("2026-01-01T08:00:00.000+0800").getOrThrow()
    @Expect(compact, utc)
}

@Test
func testIsoRoundTrip(): Unit {
    @Expect(isoFromMillis(0), "1970-01-01T00:00:00.000Z")
    @Expect(isoFromMillis(1767225740000), "2026-01-01T00:02:20.000Z")
    let millis = parseIsoMillis("2026-03-16T10:00:00.000Z").getOrThrow()
    @Expect(isoFromMillis(millis), "2026-03-16T10:00:00.000Z")
}

@Test
func testShanghaiFormatting(): Unit {
    // parity 固定时区 Asia/Shanghai（UTC+8，无夏令时）
    let millis = parseIsoMillis("2026-01-01T00:02:20.000Z").getOrThrow()
    @Expect(formatShanghaiDateTime(millis), "2026-01-01 08:02")
    @Expect(formatShanghaiDateTimeIso("2026-01-01T00:02:20.000Z"), "2026-01-01 08:02")
    @Expect(formatShanghaiDateTimeIso("bad"), "—")
    // 跨日：UTC 16:30 -> 上海次日 00:30
    let crossing = parseIsoMillis("2026-01-01T16:30:00.000Z").getOrThrow()
    @Expect(formatShanghaiDateTime(crossing), "2026-01-02 00:30")
}

@Test
func testElapsedMinutesBetweenInjectedClock(): Unit {
    let start = parseIsoMillis("2026-01-01T00:00:00.000Z").getOrThrow()
    let end = parseIsoMillis("2026-01-01T00:02:20.000Z").getOrThrow()
    @Expect(elapsedMinutesBetween(start, end), 2)
    @Expect(elapsedMinutesBetween(end, start), 0)
    @Expect(elapsedMinutesBetween(start, start), 0)
    // 29 分 40 秒 -> 30 分（.5 向上）
    @Expect(elapsedMinutesBetween(start, start + 29 * 60000 + 40000), 30)
    @Expect(elapsedMinutesBetween(start, start + 29 * 60000 + 29000), 29)
}
