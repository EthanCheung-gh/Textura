package textura.views.calendar

import std.collection.*
import cui.*
import textura.ui.*
import textura.views.calendar.logic.*

/*
 * 日历视图的绘制基元。
 *
 * 移动端/桌面端的 Web 版由 CSS 盒模型完成排版；仓颉侧没有 CSS，因此这里把
 * `calendar.css` 里用到的三类语义显式落成函数：
 *
 *   .cal-lunar { line-height: 1.35 }   -> drawTextLine(lineTop, lineHeight)
 *   .cal-daynum { height: 20px }       -> drawTextInBox(boxTop, boxH)
 *   border: 1px / box-shadow: inset   -> fillRect / 四边 1px 填充
 *
 * 每个数值都标注出处，视图不引入新的设计值；颜色一律来自 `ThemeTokens` 或
 * 领域数据 `Area.color`（`colorFromHex`）。
 */

/** 浏览器对 1px 边框与 6px 圆点做设备像素吸附；此处复刻同一取整。 */
func snapped(value: Float32): Float32 {
    if (value >= 0.0) {
        Float32(Int64(value + 0.5))
    } else {
        Float32(Int64(value - 0.5))
    }
}

/** 整数上下界（避免与集合版 `min`/`max` 重载混淆）。 */
func minInt(left: Int64, right: Int64): Int64 {
    return if (left < right) {
        left
    } else {
        right
    }
}

func maxInt(left: Int64, right: Int64): Int64 {
    return if (left > right) {
        left
    } else {
        right
    }
}

/** 十进制解析（`SelectOption.value` 是 `"2026"` 这类整数串）；非法时返回 `fallback`。 */
func parseIntOr(text: String, fallback: Int64): Int64 {
    let raw = text.trimAscii()
    if (raw.isEmpty()) {
        return fallback
    }
    var value: Int64 = 0
    for (index in 0..raw.size) {
        let byte = raw[index]
        if (byte < UInt8(48) || byte > UInt8(57)) {
            return fallback
        }
        value = value * 10 + Int64(byte - UInt8(48))
    }
    return value
}

/** 日期键加减天数（logic 包 `addDaysToKey` 与 core.data 同名，视图内用本封装避免歧义）。 */
func shiftDateKey(key: String, days: Int64): String {
    return match (dayNumberOfKey(key)) {
        case Some(number) => keyOfDayNumber(number + days)
        case None => key
    }
}

/** CSS 数值字重 -> CUI `FontStyle`。 */
func styleOf(weight: Int64): FontStyle {
    FontStyle(weight: cssWeight(weight))
}

/** 文本前进宽度（逻辑像素）。 */
func textWidthOf(ctx: UiContext, text: String, sizePx: Float32, weight: Int64): Float32 {
    if (text.isEmpty()) {
        return 0.0
    }
    ctx.textWidth(text, pointSize: sizePx, style: styleOf(weight))
}

/**
 * 单行文本：`lineTop` 是 CSS 行盒顶，`lineHeight` 是 `line-height`（px）。
 * 字体的自然盒在行盒内居中，复刻浏览器的 half-leading。
 */
func drawTextLine(
    ctx: UiContext,
    text: String,
    x: Float32,
    lineTop: Float32,
    lineHeight: Float32,
    color: Color,
    sizePx: Float32,
    weight: Int64,
    dy!: Float32 = 0.0
): Unit {
    if (text.isEmpty()) {
        return
    }
    let style = styleOf(weight)
    let fontH = ctx.textHeight(pointSize: sizePx, style: style)
    ctx.text(text, x, lineTop + (lineHeight - fontH) / 2.0 + dy, color, pointSize: sizePx, style: style)
}

/** 在固定高度的盒子内垂直居中（`.cal-daynum { height: 20px }` 一类）。 */
func drawTextInBox(
    ctx: UiContext,
    text: String,
    x: Float32,
    boxTop: Float32,
    boxH: Float32,
    color: Color,
    sizePx: Float32,
    weight: Int64,
    dy!: Float32 = 0.0
): Unit {
    if (text.isEmpty()) {
        return
    }
    let style = styleOf(weight)
    let fontH = ctx.textHeight(pointSize: sizePx, style: style)
    ctx.text(text, x, boxTop + (boxH - fontH) / 2.0 + dy, color, pointSize: sizePx, style: style)
}

/** 盒内水平 + 垂直居中。 */
func drawTextCentered(
    ctx: UiContext,
    text: String,
    boxX: Float32,
    boxY: Float32,
    boxW: Float32,
    boxH: Float32,
    color: Color,
    sizePx: Float32,
    weight: Int64,
    dy!: Float32 = 0.0
): Unit {
    if (text.isEmpty()) {
        return
    }
    let width = textWidthOf(ctx, text, sizePx, weight)
    drawTextInBox(ctx, text, boxX + (boxW - width) / 2.0, boxY, boxH, color, sizePx, weight, dy: dy)
}

/** 右对齐，垂直居中于 `centerY`。 */
func drawTextTrailing(
    ctx: UiContext,
    text: String,
    right: Float32,
    centerY: Float32,
    color: Color,
    sizePx: Float32,
    weight: Int64
): Unit {
    if (text.isEmpty()) {
        return
    }
    let style = styleOf(weight)
    let fontH = ctx.textHeight(pointSize: sizePx, style: style)
    ctx.text(text, right - textWidthOf(ctx, text, sizePx, weight), centerY - fontH / 2.0, color, pointSize: sizePx,
        style: style)
}

/** 1px 横线（`border-bottom` / `border-top`）。 */
func fillHLine(ctx: UiContext, x: Float32, y: Float32, w: Float32, color: Color): Unit {
    fillRect(ctx, Rect(x, y, w, 1.0), color)
}

/** 1px 竖线（`border-right`）。 */
func fillVLine(ctx: UiContext, x: Float32, y: Float32, h: Float32, color: Color): Unit {
    fillRect(ctx, Rect(x, y, 1.0, h), color)
}

/** 圆形填充（`.cal-dot { 6px; border-radius: 50% }`）。 */
func fillDisc(ctx: UiContext, cx: Float32, cy: Float32, radius: Float32, color: Color): Unit {
    ctx.renderer.fillCircle(cx, cy, radius, color)
}

/** 1px 或 1.5px 圆环（`box-shadow: inset …` / `.cal-check-box`）。 */
func strokeDisc(ctx: UiContext, cx: Float32, cy: Float32, radius: Float32, width: Float32, color: Color): Unit {
    ctx.renderer.strokeCircle(cx, cy, radius, Pen(width: width, color: color))
}

/** 环内缩 1px 的矩形描边（复刻 `box-shadow: inset 0 0 0 1px`）。 */
func strokeInsetRect(ctx: UiContext, rect: Rect, width: Float32, color: Color): Unit {
    fillHLine(ctx, rect.x, rect.y, rect.w, color)
    fillHLine(ctx, rect.x, rect.y + rect.h - width, rect.w, color)
    fillRect(ctx, Rect(rect.x, rect.y, width, rect.h), color)
    fillRect(ctx, Rect(rect.x + rect.w - width, rect.y, width, rect.h), color)
}

/** 文本截断（`text-overflow: ellipsis`）。 */
func ellipsize(ctx: UiContext, text: String, maxWidth: Float32, sizePx: Float32, weight: Int64): String {
    if (text.isEmpty() || maxWidth <= 0.0) {
        return ""
    }
    if (textWidthOf(ctx, text, sizePx, weight) <= maxWidth) {
        return text
    }
    let ellipsis = "…"
    let ellipsisWidth = textWidthOf(ctx, ellipsis, sizePx, weight)
    if (ellipsisWidth > maxWidth) {
        return ""
    }
    let runes = text.toRuneArray()
    var count = runes.size - 1
    while (count > 0) {
        var candidate = StringBuilder()
        for (index in 0..count) {
            candidate.append(runes[index].toString())
        }
        let value = candidate.toString()
        if (textWidthOf(ctx, value, sizePx, weight) + ellipsisWidth <= maxWidth) {
            return value + ellipsis
        }
        count = count - 1
    }
    ellipsis
}

func hexValue(byte: UInt8): Int64 {
    if (byte >= UInt8(48) && byte <= UInt8(57)) {
        return Int64(byte - UInt8(48))
    }
    if (byte >= UInt8(65) && byte <= UInt8(70)) {
        return Int64(byte - UInt8(65)) + 10
    }
    if (byte >= UInt8(97) && byte <= UInt8(102)) {
        return Int64(byte - UInt8(97)) + 10
    }
    return -1
}

/**
 * 解析领域数据里的 `#RRGGBB`（`Area.color`）。视图不硬编码颜色，
 * 但领域色属于数据，需要在这里落到 `Color`。
 */
func colorFromHex(text: String, fallback: Color): Color {
    let raw = text.trimAscii()
    if (raw.size != 7 || raw[0] != UInt8(35)) {
        return fallback
    }
    var value: Int64 = 0
    for (index in 1..7) {
        let digit = hexValue(raw[index])
        if (digit < 0) {
            return fallback
        }
        value = value * 16 + digit
    }
    Color.rgb((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
}

/**
 * `border: 1px solid` 的圆角描边。
 *
 * `Renderer.strokeRoundedRect` 的笔宽以路径为中心：矩形边在整数 x 上时线覆盖 x±0.5，
 * 会被抗锯齿摊到两列。CSS 的边框画在边框盒内侧，等价于「路径内缩半个笔宽」，因此这里
 * 先 `.inset(0.5)` 再描边，1px 线正好落在一列/一行像素上。
 */
func strokeCrisp(ctx: UiContext, rect: Rect, radius: Float32, width: Float32, color: Color, dy!: Float32 = 0.0): Unit {
    let box = Rect(snapped(rect.x), snapped(rect.y) + dy, snapped(rect.w), snapped(rect.h))
    if (box.w <= 0.0 || box.h <= 0.0) {
        return
    }
    // 圆角部分：曲线本身就该抗锯齿，保持描边。
    ctx.renderer.strokeRoundedRect(Rect(box.x + width / 2.0, box.y + width / 2.0,
        max(0.0, box.w - width), max(0.0, box.h - width)), max(0.0, radius - width / 2.0),
        Pen(width: width, color: color))
    // 四条直边：浏览器把 `border: 1px` 画成实心单像素行/列；这里逐像素覆盖，
    // 避免描边环在半像素上摊成两行浅灰。
    let inset = min(radius, min(box.w / 2.0, box.h / 2.0))
    let straightW = max(0.0, box.w - inset * 2.0)
    let straightH = max(0.0, box.h - inset * 2.0)
    if (straightW > 0.0) {
        fillRect(ctx, Rect(box.x + inset, box.y, straightW, width), color)
        fillRect(ctx, Rect(box.x + inset, box.bottom() - width, straightW, width), color)
    }
    if (straightH > 0.0) {
        fillRect(ctx, Rect(box.x, box.y + inset, width, straightH), color)
        fillRect(ctx, Rect(box.right() - width, box.y + inset, width, straightH), color)
    }
}

/**
 * 带字距的单行文本（`letter-spacing` 的等效实现）。
 *
 * CSS 的 `.cal-panel-date` / `.cal-header h1` 有 `letter-spacing: -0.01em`，CUI 没有字距
 * API；逐字符按「前进宽度 + tracking」排布可以复刻浏览器把整行收紧 2px 的效果。
 */
func drawTextTracked(
    ctx: UiContext,
    text: String,
    x: Float32,
    lineTop: Float32,
    lineHeight: Float32,
    color: Color,
    sizePx: Float32,
    weight: Int64,
    tracking: Float32,
    dy!: Float32 = 0.0
): Unit {
    if (text.isEmpty()) {
        return
    }
    let style = styleOf(weight)
    let fontH = ctx.textHeight(pointSize: sizePx, style: style)
    let y = lineTop + (lineHeight - fontH) / 2.0 + dy
    let runes = text.toRuneArray()
    var cursor = x
    var index = 0
    while (index < runes.size) {
        var single = StringBuilder()
        single.append(runes[index].toString())
        let glyph = single.toString()
        ctx.text(glyph, cursor, y, color, pointSize: sizePx, style: style)
        cursor = cursor + ctx.textWidth(glyph, pointSize: sizePx, style: style) + tracking
        index += 1
    }
}
