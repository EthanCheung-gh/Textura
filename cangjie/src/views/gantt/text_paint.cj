package textura.views.gantt

import std.collection.*
import cui.*
import textura.ui.*

/*
 * 文本绘制：把 `Renderer.text` 摆到与 CSS 单行文本一致的位置。
 *
 * 垂直规则：CSS 里一行文本放在 flex 行内时，行盒（line box）按字体度量（ascent+descent）
 * 在行高 `line-height: normal` 下居中（`align-items: center`）。CUI 的 `fontMetrics` 给出
 * 同源 FreeType 度量，所以 `text()` 的原点取 `centerY - (ascent + descent) / 2` 时，
 * 字形落点与浏览器相差 <1px（见 tools/parity 的逐像素核对）。
 *
 * 文本仍然走 SDL_ttf（与 `Label` 同一条栅格化路径），所以自绘不牺牲清晰度。
 */

func styleFor(weight: Int64): FontStyle {
    FontStyle(weight: cssWeight(weight))
}

/** 左对齐、垂直居中于 `centerY`。 */
func drawText(ctx: UiContext, text: String, x: Float32, centerY: Float32, sizePx: Float32, weight: Int64,
    color: Color): Unit {
    if (text.isEmpty()) {
        return
    }
    let style = styleFor(weight)
    let metrics = ctx.fontMetrics(pointSize: sizePx, style: style)
    ctx.text(text, x, baselineOn(centerY, sizePx, metrics.ascent), color, pointSize: sizePx, style: style)
}

/**
 * 单行文本的基线：CSS 把行盒（`line-height: normal` ≈ 1.448em，ascent 1.16em）居中在行内，
 * 基线因此落在 `centerY + (1.16 − 1.448/2) em`；`Renderer.text` 以行盒顶为原点，
 * 所以原点 y = 基线 − ascent。`Renderer.text` 会把原点吸附到整像素，而浏览器保留小数基线，
 * 因此再减去按字号分段的经验补偿 `nudgeFor`：
 * - ≥18px（页头 h1）：两种行盒差已够小，实测再补偿会偏高 1.1px，取 0；
 * - 其余（9.5~13px）：吸附后重心比参考图低 0.2~1.3px，上移 0.6px。
 *   （11~12.5px 试过 0.9，与 0.6 出图逐字节相同——0.3px 未跨过吸附边界，故只留两档。）
 */
func nudgeFor(sizePx: Float32): Float32 {
    if (sizePx >= 18.0) {
        0.0
    } else {
        0.6
    }
}

func baselineOn(centerY: Float32, sizePx: Float32, ascent: Float32): Float32 {
    centerY + sizePx * 0.436 - ascent - nudgeFor(sizePx)
}

/** 右对齐：文本最后一位落在 `right`。 */
func drawTextRight(ctx: UiContext, text: String, right: Float32, centerY: Float32, sizePx: Float32, weight: Int64,
    color: Color): Unit {
    if (text.isEmpty()) {
        return
    }
    drawText(ctx, text, right - textAdvance(ctx, text, sizePx, weight), centerY, sizePx, weight, color)
}

/** 水平居中：文本中心落在 `centerX`。 */
func drawTextCenter(ctx: UiContext, text: String, centerX: Float32, centerY: Float32, sizePx: Float32,
    weight: Int64, color: Color): Unit {
    if (text.isEmpty()) {
        return
    }
    drawText(ctx, text, centerX - textAdvance(ctx, text, sizePx, weight) / 2.0, centerY, sizePx, weight, color)
}

func textAdvance(ctx: UiContext, text: String, sizePx: Float32, weight: Int64): Float32 {
    if (text.isEmpty()) {
        0.0
    } else {
        ctx.textWidth(text, pointSize: sizePx, style: styleFor(weight))
    }
}

/** 文本墨迹高度（用于下划线/删除线这类需要贴合字形的装饰）。 */
func textInkBox(ctx: UiContext, text: String, sizePx: Float32, weight: Int64): Rect {
    ctx.renderer.textInkBounds(text, pointSize: sizePx, style: styleFor(weight))
}

/**
 * `text-overflow: ellipsis`：超出 `maxWidth` 时截断并补一个省略号。
 * 逐字符回退，标签长度都在几十字符内，代价可忽略。
 */
func ellipsize(ctx: UiContext, text: String, maxWidth: Float32, sizePx: Float32, weight: Int64): String {
    if (text.isEmpty() || maxWidth <= 0.0) {
        return ""
    }
    if (textAdvance(ctx, text, sizePx, weight) <= maxWidth) {
        return text
    }
    let runes = text.toRuneArray()
    let ellipsis = "…"
    let ellipsisWidth = textAdvance(ctx, ellipsis, sizePx, weight)
    if (ellipsisWidth > maxWidth) {
        return ""
    }
    var end = runes.size
    while (end > 0) {
        end -= 1
        let candidate = String(runes[0..end]) + ellipsis
        if (textAdvance(ctx, candidate, sizePx, weight) <= maxWidth) {
            return candidate
        }
    }
    ellipsis
}

/**
 * CSS `border: w solid` 的落点：浏览器把边框画在 border-box 内侧，
 * 因此描边中心位于 `rect.inset(w/2)`；直接描在 rect 上会糊成两行半覆盖。
 */
func cssBorder(ctx: UiContext, rect: Rect, radius: Float32, width: Float32, color: Color): Unit {
    strokeRound(ctx, rect.inset(width / 2.0), max(0.0, radius - width / 2.0), width, color)
}

/** `box-shadow: 0 0 0 w <color>` 的外环：描边中心在边框盒**外** w/2 处。 */
func cssRing(ctx: UiContext, rect: Rect, radius: Float32, width: Float32, color: Color): Unit {
    strokeRound(ctx, rect.inset(-width / 2.0), radius + width / 2.0, width, color)
}

/** 1px 水平细线（`border-bottom` / 删除线）。 */
func hairline(ctx: UiContext, x: Float32, y: Float32, width: Float32, color: Color): Unit {
    if (width <= 0.0) {
        return
    }
    ctx.renderer.fill(Rect(x, y, width, 1.0), color)
}

/** 1px 垂直细线。 */
func vline(ctx: UiContext, x: Float32, y: Float32, height: Float32, color: Color): Unit {
    if (height <= 0.0) {
        return
    }
    ctx.renderer.fill(Rect(x, y, 1.0, height), color)
}

/** 圆点（`.gantt-status-dot` / `.gantt-dep-joint`）。 */
func dot(ctx: UiContext, cx: Float32, cy: Float32, radius: Float32, color: Color): Unit {
    if (radius <= 0.0) {
        return
    }
    ctx.renderer.fillCircle(cx, cy, radius, color)
}

/** 菱形（`.gantt-milestone-mark`：13×13、`border-radius: 2px`、`rotate(45deg)`）。 */
func diamond(ctx: UiContext, cx: Float32, cy: Float32, half: Float32, color: Color): Unit {
    let points = ArrayList<Point>()
    points.add(Point(cx, cy - half))
    points.add(Point(cx + half, cy))
    points.add(Point(cx, cy + half))
    points.add(Point(cx - half, cy))
    ctx.renderer.fillConvexPolygon(points, color)
}

/** 任意三角形的实心填充（依赖箭头 `marker` 的三角头）。 */
func triangle(ctx: UiContext, ax: Float32, ay: Float32, bx: Float32, by: Float32, cx: Float32, cy: Float32,
    color: Color): Unit {
    let points = ArrayList<Point>()
    points.add(Point(ax, ay))
    points.add(Point(bx, by))
    points.add(Point(cx, cy))
    ctx.renderer.fillConvexPolygon(points, color)
}
