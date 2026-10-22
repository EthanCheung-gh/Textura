package textura.views.gantt.logic

import std.math.*

/**
 * 数值工具。
 *
 * 关键语义：TypeScript 的 `Math.round(x)` 是“向 +∞ 取半”（`Math.round(-2.5) === -2`），
 * 而仓颉 `round` 远离零取整，因此这里统一用 `floor(x + 0.5)` 复刻 TS 行为。
 */

/** 复刻 `Math.round`：半值向 +∞ 取整。 */
public func tsRound(value: Float64): Float64 {
    floor(value + 0.5)
}

/** 复刻 `Math.round` 的整数结果。 */
public func tsRoundInt(value: Float64): Int64 {
    Int64(tsRound(value))
}

/** 复刻 `Math.floor` 的整数结果。 */
public func tsFloorInt(value: Float64): Int64 {
    Int64(floor(value))
}

/** 复刻 `Math.ceil` 的整数结果。 */
public func tsCeilInt(value: Float64): Int64 {
    Int64(ceil(value))
}

/** `Number.isFinite` 的等价判断。 */
public func isFiniteNumber(value: Float64): Bool {
    !value.isNaN() && !value.isInf()
}

/** 非有限值退化为 `fallback`。 */
public func finiteOr(value: Float64, fallback: Float64): Float64 {
    if (isFiniteNumber(value)) {
        value
    } else {
        fallback
    }
}

public func minF64(a: Float64, b: Float64): Float64 {
    if (a < b) {
        a
    } else {
        b
    }
}

public func maxF64(a: Float64, b: Float64): Float64 {
    if (a > b) {
        a
    } else {
        b
    }
}

public func minInt(a: Int64, b: Int64): Int64 {
    if (a < b) {
        a
    } else {
        b
    }
}

public func maxInt(a: Int64, b: Int64): Int64 {
    if (a > b) {
        a
    } else {
        b
    }
}

/** 复刻 `Math.min(max, Math.max(min, value))`。 */
public func clampInt(value: Int64, lower: Int64, upper: Int64): Int64 {
    minInt(upper, maxInt(lower, value))
}

/** 复刻 `Math.min(max, Math.max(min, value))`。 */
public func clampF64(value: Float64, lower: Float64, upper: Float64): Float64 {
    minF64(upper, maxF64(lower, value))
}
