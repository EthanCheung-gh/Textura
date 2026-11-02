package textura.views.dashboard.logic

import std.collection.*
import std.sort.*

/**
 * `String.prototype.trim` 语义：去掉首尾 Unicode WhiteSpace / LineTerminator。
 *
 * Web 版 `core/utils.dateKey` 用 `value.trim()`，所以这里逐 Rune 判定，不能用只覆盖
 * ASCII 的 `trimAscii()`——全角空格 (U+3000) 必须同样被裁掉。
 */
func trimJs(text: String): String {
    let runes = text.toRuneArray()
    var start = 0
    var end = runes.size
    while (start < end && isJsWhitespace(runes[start])) {
        start += 1
    }
    while (end > start && isJsWhitespace(runes[end - 1])) {
        end -= 1
    }
    if (start == 0 && end == runes.size) {
        return text
    }
    let kept = ArrayList<Rune>()
    var index = start
    while (index < end) {
        kept.add(runes[index])
        index += 1
    }
    return String(kept.toArray())
}

/** ECMAScript 的 WhiteSpace + LineTerminator 集合。 */
func isJsWhitespace(ch: Rune): Bool {
    let code = Int64(UInt32(ch))
    if (code == 0x09 || code == 0x0A || code == 0x0B || code == 0x0C || code == 0x0D) {
        return true
    }
    if (code == 0x20 || code == 0xA0 || code == 0x1680) {
        return true
    }
    if (code >= 0x2000 && code <= 0x200A) {
        return true
    }
    if (code == 0x2028 || code == 0x2029 || code == 0x202F || code == 0x205F) {
        return true
    }
    return code == 0x3000 || code == 0xFEFF
}

/** `value(0..count)` 的 Rune 版本，对齐 `String.prototype.slice(0, count)`。 */
func takeRunes(text: String, count: Int64): String {
    let runes = text.toRuneArray()
    if (count >= runes.size) {
        return text
    }
    if (count <= 0) {
        return String()
    }
    let kept = ArrayList<Rune>()
    var index = 0
    while (index < count) {
        kept.add(runes[index])
        index += 1
    }
    return String(kept.toArray())
}

/**
 * `localeCompare` 的确定性替代：按码点字节序比较。
 *
 * 本包比较的全部是定宽 ISO 串（`YYYY-MM-DD`、`YYYY-MM-DDTHH:mm:ss`、id），
 * 这些输入上字节序与 zh-CN 排序规则一致，不引入时区/ICU 依赖。
 */
func compareText(left: String, right: String): Int64 {
    if (left < right) {
        return -1
    }
    if (left > right) {
        return 1
    }
    return 0
}

/** JS `value ?? ''`。 */
func orEmpty(value: ?String): String {
    if (let Some(text) <- value) {
        return text
    }
    return String()
}

/** JS 真值判断：`null`、`undefined` 与空串都为假。 */
func isNonEmpty(value: ?String): Bool {
    if (let Some(text) <- value) {
        return !text.isEmpty()
    }
    return false
}

/** 向负无穷取整的整数除法。 */
func floorDiv(value: Int64, divisor: Int64): Int64 {
    var quotient = value / divisor
    if (value % divisor != 0 && (value < 0) != (divisor < 0)) {
        quotient -= 1
    }
    return quotient
}

/** `Math.round(numerator / denominator)`，要求两者非负。 */
func roundHalfUp(numerator: Int64, denominator: Int64): Int64 {
    if (denominator <= 0 || numerator <= 0) {
        return 0
    }
    return (numerator * 2 + denominator) / (denominator * 2)
}

/**
 * 与 JS `Array.prototype.sort` 等价（规范要求稳定排序）的排序。
 *
 * 显式把输入序号作为最后一级排序键，因此即使底层排序不稳定，同键元素也保持输入顺序。
 */
func stableSortBy<T>(values: Array<T>, compare: (T, T) -> Int64): Array<T> {
    let indices = ArrayList<Int64>()
    var index = 0
    while (index < values.size) {
        indices.add(index)
        index += 1
    }
    sort(
        indices,
        lessThan: {
            left, right =>
                let result = compare(values[left], values[right])
                if (result != 0) {
                    return result < 0
                }
                return left < right
        }
    )
    let ordered = ArrayList<T>()
    for (position in indices) {
        ordered.add(values[position])
    }
    return ordered.toArray()
}

/**
 * JS `values.slice(0, end)`：`end` 为负表示从末尾倒数，超出长度按长度截断。
 * Web 版的 `recentlyCompleted(ws, limit)` / `buildActivity(ws, limitPerSource)` 都走这个语义。
 */
func takeSlice<T>(values: Array<T>, end: Int64): Array<T> {
    let total = values.size
    let stop = if (end < 0) {
        let candidate = total + end
        if (candidate < 0) {
            0
        } else {
            candidate
        }
    } else if (end > total) {
        total
    } else {
        end
    }
    let kept = ArrayList<T>()
    var index = 0
    while (index < stop) {
        kept.add(values[index])
        index += 1
    }
    return kept.toArray()
}
