package textura.views.gtd

import cui.*
import textura.ui.*

/*
 * 单行文本叶子与文本绘制辅助。
 *
 * 为什么不直接用 `Label`：CSS 的行高（`.gtd-row-title { line-height: 1.35 }`、
 * `.gtd-flow-card-value { line-height: 1.15 }` 等）决定行盒高度，而 `Label` 的行盒来自
 * 字体自然行高（measure 里再加 6px），无法钉到同一像素网格。
 * 这里由调用方给出盒高，绘制时按字体 ascent/descent 在盒内垂直居中，
 * 与浏览器 `align-items: center` 的落点一致（同一条 SDL_ttf 栅格化路径）。
 */

/*
 * 显式空值：字面量 `None` 在部分推断上下文（默认参数等）会与 sdl 同名枚举构造器冲突，
 * 用带返回类型的辅助函数固定类型（与 gantt 视图的 `noKey()` 同一手法）。
 */
func noFamily(): ?String {
    None
}

func noColor(): ?Color {
    None
}

func noAction(): ?() -> Unit {
    None
}

func gtdStyle(weight: Int64): FontStyle {
    FontStyle(weight: cssWeight(weight))
}

/** 左对齐、垂直居中于 `centerY`。 */
func drawLine(
    ctx: UiContext,
    text: String,
    x: Float32,
    centerY: Float32,
    sizePx: Float32,
    weight: Int64,
    color: Color,
    family!: ?String = noFamily()
): Unit {
    if (text.isEmpty()) {
        return
    }
    let style = gtdStyle(weight)
    let metrics = ctx.fontMetrics(pointSize: sizePx, style: style, font: family)
    ctx.text(text, x, centerY - (metrics.ascent + metrics.descent) / 2.0, color,
        pointSize: sizePx, style: style, font: family)
}

/** 右对齐：文本末端落在 `right`。 */
func drawLineRight(
    ctx: UiContext,
    text: String,
    right: Float32,
    centerY: Float32,
    sizePx: Float32,
    weight: Int64,
    color: Color,
    family!: ?String = noFamily()
): Unit {
    if (text.isEmpty()) {
        return
    }
    drawLine(ctx, text, right - advanceOf(ctx, text, sizePx, weight, family: family), centerY, sizePx, weight,
        color, family: family)
}

/** 水平居中于 `centerX`。 */
func drawLineCenter(
    ctx: UiContext,
    text: String,
    centerX: Float32,
    centerY: Float32,
    sizePx: Float32,
    weight: Int64,
    color: Color,
    family!: ?String = noFamily()
): Unit {
    if (text.isEmpty()) {
        return
    }
    drawLine(ctx, text, centerX - advanceOf(ctx, text, sizePx, weight, family: family) / 2.0, centerY, sizePx,
        weight, color, family: family)
}

/**
 * 带 `letter-spacing` 的单行绘制：逐字符按「字宽 + tracking」推进。
 * CSS 的 `letter-spacing` 在 CUI 里没有对应 API，而 `h1 { letter-spacing: -0.01em }`
 * （base.css:43）与 `.gtd-group-header { letter-spacing: 0.05em }`（gtd.css:516）都会
 * 影响整行宽度，所以这里按 CSS 语义手工推进。
 */
func drawLineSpaced(
    ctx: UiContext,
    text: String,
    x: Float32,
    centerY: Float32,
    sizePx: Float32,
    weight: Int64,
    color: Color,
    tracking: Float32,
    family!: ?String = None
): Unit {
    if (text.isEmpty()) {
        return
    }
    var cursor = x
    let style = gtdStyle(weight)
    let metrics = ctx.fontMetrics(pointSize: sizePx, style: style, font: family)
    let top = centerY - (metrics.ascent + metrics.descent) / 2.0
    for (rune in text.toRuneArray()) {
        let glyph = String(rune)
        ctx.text(glyph, cursor, top, color, pointSize: sizePx, style: style, font: family)
        cursor += ctx.textWidth(glyph, pointSize: sizePx, style: style, font: family) + tracking
    }
}

/** 文本推进宽度（CSS `getBoundingClientRect().width` 的近似）。 */
func advanceOf(
    ctx: UiContext,
    text: String,
    sizePx: Float32,
    weight: Int64,
    family!: ?String = noFamily()
): Float32 {
    if (text.isEmpty()) {
        return 0.0
    }
    ctx.textWidth(text, pointSize: sizePx, style: gtdStyle(weight), font: family)
}

/**
 * `text-overflow: ellipsis` 的近似：超出宽度时保留能放下的前缀并补 `…`。
 * 只在标题/面包屑超过 maxWidth 时用到。
 */
func ellipsizeGtd(
    ctx: UiContext,
    text: String,
    sizePx: Float32,
    weight: Int64,
    maxWidth: Float32,
    family!: ?String = noFamily()
): String {
    if (maxWidth <= 0.0 || advanceOf(ctx, text, sizePx, weight, family: family) <= maxWidth) {
        return text
    }
    let runes = text.toRuneArray()
    var low: Int64 = 0
    var high = runes.size
    while (low < high) {
        let middle = (low + high + 1) / 2
        var candidate = ""
        var index: Int64 = 0
        while (index < middle) {
            candidate += String(runes[index])
            index += 1
        }
        if (advanceOf(ctx, candidate + "…", sizePx, weight, family: family) <= maxWidth) {
            low = middle
        } else {
            high = middle - 1
        }
    }
    var result = ""
    var index: Int64 = 0
    while (index < low) {
        result += String(runes[index])
        index += 1
    }
    result + "…"
}

/** 一行文本叶子：固定盒高、可点击、可 hover 换色。 */
public class GtdText <: Widget {
    private let text: String
    private let size: Float32
    private let weight: Int64
    private let color: Color
    private let hoverColor: ?Color
    private let boxHeight: Float32
    private let maxTextWidth: Float32
    private let family: ?String
    private let onClick: ?() -> Unit
    private let tracking: Float32
    private let hoverId: String
    private var frame = Rect.zero()

    public init(
        text: String,
        size: Float32,
        weight: Int64,
        color: Color,
        boxHeight!: Float32 = 0.0,
        hoverColor!: ?Color = noColor(),
        maxWidth!: Float32 = 0.0,
        family!: ?String = noFamily(),
        hoverId!: String = "",
        onClick!: ?() -> Unit = noAction(),
        tracking!: Float32 = 0.0
    ) {
        this.text = text
        this.size = size
        this.weight = weight
        this.color = color
        this.hoverColor = hoverColor
        this.boxHeight = if (boxHeight <= 0.0) {
            lineBox(size)
        } else {
            boxHeight
        }
        this.maxTextWidth = maxWidth
        this.family = family
        this.hoverId = if (hoverId.isEmpty()) {
            "gtd-text:${text}"
        } else {
            hoverId
        }
        this.onClick = onClick
        this.tracking = tracking
        emit(this)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        var width = advanceOf(ctx, text, size, weight, family: family)
        if (tracking != 0.0) {
            for (rune in text.toRuneArray()) {
                width += tracking
                let _ = rune
            }
        }
        if (maxTextWidth > 0.0 && width > maxTextWidth) {
            width = maxTextWidth
        }
        Size(min(width, max(available.w, 0.0)), boxHeight)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let hovered = containsPointer(ctx) && onClick.isSome()
        let ink = if (hovered) {
            match (hoverColor) {
                case Some(value) => value
                case None => color
            }
        } else {
            color
        }
        let fitted = ellipsizeGtd(ctx, text, size, weight, frame.w, family: family)
        if (tracking == 0.0) {
            drawLine(ctx, fitted, frame.x, frame.centerY(), size, weight, ink, family: family)
        } else {
            drawLineSpaced(ctx, fitted, frame.x, frame.centerY(), size, weight, ink, tracking, family: family)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        if (onClick.isNone()) {
            return false
        }
        match (event) {
            case UiEvent.MouseMove(_, _) =>
                if (containsPointer(ctx)) {
                    ctx.claimHover(hoverId, CursorShape.Interactive)
                }
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    ctx.press(hoverId)
                    return true
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (ctx.isPressed(hoverId)) {
                    ctx.clearPress()
                    if (frame.contains(x, y)) {
                        match (onClick) {
                            case Some(action) => action()
                            case None => ()
                        }
                        return true
                    }
                }
            case _ => ()
        }
        false
    }

    private func containsPointer(ctx: UiContext): Bool {
        frame.contains(ctx.mouseX, ctx.mouseY)
    }
}

/** 带字距的一行文本叶子（`letter-spacing` 只影响宽度，不影响 hover 语义）。 */
class GtdTextSpaced <: Widget {
    private let text: String
    private let size: Float32
    private let weight: Int64
    private let color: Color
    private let tracking: Float32
    private let boxHeight: Float32
    private var frame = Rect.zero()

    init(text: String, size: Float32, weight: Int64, color: Color, tracking: Float32) {
        this.text = text
        this.size = size
        this.weight = weight
        this.color = color
        this.tracking = tracking
        this.boxHeight = lineBox(size)
        emit(this)
    }

    private func advanceWidth(ctx: UiContext): Float32 {
        var width: Float32 = 0.0
        for (rune in text.toRuneArray()) {
            width += ctx.textWidth(String(rune), pointSize: size, style: gtdStyle(weight)) + tracking
        }
        width
    }

    public func measure(ctx: UiContext, available: Size): Size {
        Size(min(advanceWidth(ctx), max(available.w, 0.0)), boxHeight)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        drawLineSpaced(ctx, text, frame.x, frame.centerY(), size, weight, color, tracking)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/**
 * 一条 1px 分隔线（CSS `border-bottom: 1px solid`）。
 *
 * 自绘并把纵向起点吸附到整数像素：行高来自 CSS 的小数（如 65.825），直接画会让
 * 1px 线跨两条设备像素、变成两行 50% 混合色；浏览器在同一点会把边框吸附到整像素。
 */
class GtdRule <: Widget {
    private let color: Color
    private var frame = Rect.zero()

    init(color: Color) {
        this.color = color
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(max(available.w, 0.0), 1.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        if (color.a == 0 || frame.w <= 0.0) {
            return
        }
        ctx.renderer.fill(Rect(frame.x, Float32(Int64(frame.y + 0.5)), frame.w, 1.0), color)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

func gtdRule(color: Color): Unit {
    GtdRule(color)
}

/** 虚线分隔线（CSS `border-bottom: 1px dashed`）。 */
class GtdDashedRule <: Widget {
    private let color: Color
    private var frame = Rect.zero()

    init(color: Color) {
        this.color = color
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(max(available.w, 0.0), 1.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        var x = frame.x
        while (x < frame.right()) {
            let width = min(4.0, frame.right() - x)
            ctx.renderer.fill(Rect(x, frame.y, width, 1.0), color)
            x += 8.0
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}
