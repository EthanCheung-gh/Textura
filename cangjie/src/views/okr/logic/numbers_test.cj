package textura.views.okr.logic

import std.unittest.*
import std.unittest.testmacro.*

/*
 * `roundTo` / `jsRound` / `jsFixedNumberToString` 与 JS 语义逐条对齐。
 * 期望值来自 node 下直接运行 `Math.round` / `Number.prototype.toFixed` 的结果。
 */

@Test
func jsRoundFollowsMathRound() {
    @Assert(jsRound(2.5), 3.0)
    @Assert(jsRound(-2.5), -2.0)
    @Assert(jsRound(-0.5), -0.0)
    @Assert(jsRound(2.4), 2.0)
    @Assert(jsRound(-2.6), -3.0)
    // 0.49999999999999994 + 0.5 == 1，但 JS 取最近的 0
    @Assert(jsRound(0.49999999999999994), 0.0)
    @Assert(jsRound(4503599627370497.0), 4503599627370497.0)
    @Assert(jsRound(Float64.NaN).isNaN(), true)
    @Assert(jsRound(TEST_INF).isInf(), true)
}

@Test
func roundToMatchesTs() {
    @Assert(roundTo(1.2345, digits: 2), 1.23)
    @Assert(roundTo(-1.25, digits: 1), -1.2)
    @Assert(roundTo(2.5, digits: 0), 3.0)
    @Assert(roundTo(2.675, digits: 2), 2.68)
    @Assert(roundTo(Float64.NaN), 0.0)
    @Assert(roundTo(TEST_INF), 0.0)
    @Assert(roundTo(49.4382, digits: 1), 49.4)
    @Assert(roundTo(49.95, digits: 1), 50.0)
}

@Test
func power10CoversSigns() {
    @Assert(power10(0), 1.0)
    @Assert(power10(2), 100.0)
    @Assert(power10(-2), 0.01)
    @Assert(power10(-1), 0.1)
}

@Test
func jsFixedNumberToStringRoundsHalfAwayFromZero() {
    @Assert(jsFixedNumberToString(2.345, 2), "2.35")
    @Assert(jsFixedNumberToString(0.125, 2), "0.13")
    @Assert(jsFixedNumberToString(1.005, 2), "1")
    @Assert(jsFixedNumberToString(-12.345, 2), "-12.35")
    @Assert(jsFixedNumberToString(99.995, 2), "100")
    @Assert(jsFixedNumberToString(1.0 / 3.0, 2), "0.33")
    @Assert(jsFixedNumberToString(0.004, 2), "0")
    @Assert(jsFixedNumberToString(-0.004, 2), "0")
}

@Test
func isFiniteNumberAndTruncFollowJs() {
    @Assert(isFiniteNumber(0.0), true)
    @Assert(isFiniteNumber(Float64.NaN), false)
    @Assert(isFiniteNumber(TEST_INF), false)
    @Assert(isFiniteNumber(-TEST_INF), false)
    @Assert(jsTrunc(2.9), 2.0)
    @Assert(jsTrunc(-2.9), -2.0)
    @Assert(jsTrunc(Float64.NaN).isNaN(), true)
}
