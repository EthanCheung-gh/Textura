package textura.views.okr.logic

import std.collection.*
import std.convert.*
import std.math.*

/*
 * 浮点工具。
 *
 * TS 侧依赖 JS 语义的数字行为：`Math.round`（.5 取较大值）、`Number.isFinite`、
 * `String(number)`（最短往返表示 + 指数阈值）以及 `Number(value.toFixed(2))`。
 * 仓颉的 `Float64.toString` 是 `"%f"`（固定 6 位小数）、`std.math.round` 是
 * 银行家舍入，两者都与 JS 不一致，所以这里显式实现 JS 语义。
 */

/** JS `Number.isFinite`。仓颉没有 `isFinite()` 成员。 */
public func isFiniteNumber(value: Float64): Bool {
    !value.isNaN() && !value.isInf()
}

/** JS `Math.trunc`。 */
public func jsTrunc(value: Float64): Float64 {
    if (!isFiniteNumber(value)) {
        return value
    }
    trunc(value)
}

/**
 * JS `Math.round`：返回最接近的整数，恰好 .5 时取较大值（向 +∞）。
 * 例：2.5 -> 3、-2.5 -> -2、0.49999999999999994 -> 0。
 */
public func jsRound(value: Float64): Float64 {
    if (!isFiniteNumber(value)) {
        return value
    }
    let base = floor(value)
    if (value == base) {
        return value
    }
    let fraction = value - base
    if (fraction >= 0.5) {
        base + 1.0
    } else {
        base
    }
}

/** JS `10 ** digits`（整数指数）。 */
public func power10(digits: Int64): Float64 {
    if (digits >= 0) {
        var factor = 1.0
        for (_ in 0..digits) {
            factor = factor * 10.0
        }
        return factor
    }
    var divisor = 1.0
    for (_ in 0..(-digits)) {
        divisor = divisor * 10.0
    }
    1.0 / divisor
}

/** TS `roundTo(value, digits)`：非有限值返回 0，其余按 `Math.round` 半值向 +∞。 */
public func roundTo(value: Float64, digits!: Int64 = 0): Float64 {
    if (!isFiniteNumber(value)) {
        return 0.0
    }
    let factor = power10(digits)
    jsRound(value * factor) / factor
}

/** Dekker 拆分常数 2^27 + 1，用于无 FMA 的精确乘法误差。 */
private let TWO_PRODUCT_SPLITTER: Float64 = 134217729.0

/** 计算 `a * b = product + error` 中的 `error`（无溢出区间内精确）。 */
private func twoProductError(a: Float64, b: Float64, product: Float64): Float64 {
    let ca = TWO_PRODUCT_SPLITTER * a
    let aHi = ca - (ca - a)
    let aLo = a - aHi
    let cb = TWO_PRODUCT_SPLITTER * b
    let bHi = cb - (cb - b)
    let bLo = b - bHi
    (((aHi * bHi - product) + aHi * bLo) + aLo * bHi) + aLo * bLo
}

/**
 * 把 `|value| * factor` 舍入到整数：恰好 .5 时远离零（等价 JS `toFixed` 的取值规则）。
 * 用乘积残差区分「真实 .5」与「乘积浮点噪声被舍到 .5」。
 */
public func roundScaledHalfAwayFromZero(value: Float64, factor: Float64): Int64 {
    let negative = value < 0.0
    let magnitude = if (negative) {
        -value
    } else {
        value
    }
    let product = magnitude * factor
    let residual = twoProductError(magnitude, factor, product)
    let base = floor(product)
    let fraction = product - base
    var up = false
    if (fraction > 0.5) {
        up = true
    } else if (fraction == 0.5) {
        up = residual >= 0.0
    }
    var result = Int64(base)
    if (up) {
        result += 1
    }
    if (negative) {
        -result
    } else {
        result
    }
}

/** 定点形式的最短往返尾数（兜底用）；找不到返回 None。 */
private func shortestFixedText(magnitude: Float64): ?String {
    for (digits in 0..=17) {
        let candidate = magnitude.format(".${digits}")
        match (Float64.tryParse(candidate)) {
            case Some(parsed) =>
                if (parsed == magnitude) {
                    return Some(candidate)
                }
            case None => ()
        }
    }
    None
}

/**
 * 最短往返表示，等价 ECMA-262 的「最少有效数字」规则：
 * 从 1 位有效数字起试 `format(".{s-1}e")`（printf 对精确二进制值正确舍入），
 * 第一个能解析回同一 `Float64` 的候选就是最短表示；最后用定点形式兜底。
 *
 * 例：2.1 -> "2.1e+0"、42 -> "4.2e+1"、1e21 -> "1e+21"、5e-324 -> "5e-324"。
 */
private func shortestRoundTripText(magnitude: Float64): String {
    for (digits in 1..=17) {
        let candidate = magnitude.format(".${digits - 1}e")
        match (Float64.tryParse(candidate)) {
            case Some(parsed) =>
                if (parsed == magnitude) {
                    return candidate
                }
            case None => ()
        }
    }
    let fixed = shortestFixedText(magnitude)
    if (fixed.isSome()) {
        return fixed.getOrThrow()
    }
    magnitude.format(".17")
}

/** 把「整数部分 + 小数部分」（可带 `e` 指数）切成 (有效数字, 小数点位置 n)。 */
private func splitDigits(text: String): (String, Int64) {
    var mantissa = text
    var exponent: Int64 = 0
    let exponentIndex = text.indexOf("e")
    if (exponentIndex.isSome()) {
        let index = exponentIndex.getOrThrow()
        let runes = text.toRuneArray()
        mantissa = String(runes[0..index])
        let tail = String(runes[(index + 1)..runes.size])
        // `format(".Ne")` 的正指数带显式 '+'，而 `Int64.tryParse` 不接受前导 '+'
        let normalized = if (tail.startsWith("+")) {
            String(tail.toRuneArray()[1..tail.toRuneArray().size])
        } else {
            tail
        }
        exponent = match (Int64.tryParse(normalized)) {
            case Some(value) => value
            case None => 0
        }
    }
    let parts = mantissa.split(".")
    let intPart = parts[0]
    let fracPart = if (parts.size > 1) {
        parts[1]
    } else {
        ""
    }
    let intLen = intPart.size + exponent
    let allRunes = ArrayList<Rune>()
    for (rune in intPart.toRuneArray()) {
        allRunes.add(rune)
    }
    for (rune in fracPart.toRuneArray()) {
        allRunes.add(rune)
    }

    var firstNonZero = -1
    for (index in 0..allRunes.size) {
        if (allRunes[index] != r'0') {
            firstNonZero = index
            break
        }
    }
    if (firstNonZero < 0) {
        return ("", 0)
    }

    let significant = ArrayList<Rune>()
    for (index in firstNonZero..allRunes.size) {
        significant.add(allRunes[index])
    }
    while (significant.size > 0 && significant[significant.size - 1] == r'0') {
        significant.remove(at: significant.size - 1)
    }
    (String(significant), intLen - firstNonZero)
}

/** 按 ECMA-262 `Number::toString` 的规则把 (digits, n) 渲染成文本。 */
private func renderDigits(digits: String, pointPos: Int64): String {
    let runes = digits.toRuneArray()
    let k = runes.size
    let n = pointPos
    if (n >= k && n <= 21) {
        var padding = ""
        for (_ in 0..(n - k)) {
            padding = padding + "0"
        }
        return digits + padding
    }
    if (n > 0 && n < k && n <= 21) {
        return String(runes[0..n]) + "." + String(runes[n..k])
    }
    if (n <= 0 && n > -6) {
        var padding = ""
        for (_ in 0..(-n)) {
            padding = padding + "0"
        }
        return "0." + padding + digits
    }
    let exponent = n - 1
    let sign = if (exponent >= 0) {
        "+"
    } else {
        "-"
    }
    let magnitude = if (exponent < 0) {
        -exponent
    } else {
        exponent
    }
    if (k == 1) {
        return digits + "e" + sign + magnitude.toString()
    }
    String(runes[0..1]) + "." + String(runes[1..k]) + "e" + sign + magnitude.toString()
}

/**
 * JS `String(number)`：最短可往返的十进制表示；`|x| >= 1e21` 或 `< 1e-6` 用指数形式。
 * 与 `Float64.toString()`（固定 6 位小数）的差异见 `docs/OKR-LOGIC.md`。
 */
public func jsNumberToString(value: Float64): String {
    if (value.isNaN()) {
        return "NaN"
    }
    if (value.isInf()) {
        return if (value > 0.0) {
            "Infinity"
        } else {
            "-Infinity"
        }
    }
    if (value == 0.0) {
        return "0"
    }
    let negative = value < 0.0
    let magnitude = if (negative) {
        -value
    } else {
        value
    }
    let (digits, pointPos) = splitDigits(shortestRoundTripText(magnitude))
    let rendered = if (digits.isEmpty()) {
        "0"
    } else {
        renderDigits(digits, pointPos)
    }
    if (negative && rendered != "0") {
        "-" + rendered
    } else {
        rendered
    }
}

/**
 * JS `Number(value.toFixed(digits))` 再 `String(...)`。
 * 只用于展示（`formatNumber`），指标数值区间内与 TS 逐位一致。
 */
public func jsFixedNumberToString(value: Float64, digits: Int64): String {
    if (!isFiniteNumber(value)) {
        return jsNumberToString(value)
    }
    let factor = power10(digits)
    let scaled = roundScaledHalfAwayFromZero(value, factor)
    jsNumberToString(Float64(scaled) / factor)
}
