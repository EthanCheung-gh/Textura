package textura.views.dashboard

import cui.*
import textura.ui.*

/** `.btn { gap: var(--space-2) }`（ui.css:10）。 */
let BUTTON_GAP: Float32 = 8.0

/*
 * `.page-header.dash-header`（shell.css:270-296 + dashboard.css:6-39）。
 *
 * 网页里的级联顺序是 `dashboard.css` 先、`shell.css` 后，因此同特异度的
 * `.page-header h1 { font-size: 22px }`（shell.css:283-285）胜过
 * `.dash-header h1 { font-size: 24px }`（dashboard.css:14-17），
 * `.page-header { align-items: flex-start }` 胜过 `.dash-header { align-items: flex-end }`。
 * 这两条都用参考图核对过：h1 墨水宽 227px（22px，非 24px），命令面板按钮贴顶。
 */
class PageHeaderView <: Widget {
    private let tokens: ThemeTokens
    private let eyebrow: String
    private let title: String
    private let summary: String
    private let onPalette: () -> Unit
    private let buttonId: String
    private var frame = Rect.zero()
    private var buttonFrame = Rect.zero()
    private let keyboardHint: String = "⌘K"

    init(tokens: ThemeTokens, eyebrow: String, title: String, summary: String, onPalette: () -> Unit) {
        this.tokens = tokens
        this.eyebrow = eyebrow
        this.title = title
        this.summary = summary
        this.onPalette = onPalette
        this.buttonId = focusableControlIdentity("dash-palette")
        emit(this)
    }

    /** `.page-header-titles { gap: var(--space-1) }`（dashboard.css:10-12）+ h1 22px（shell.css:283-285）。 */
    private func titlesHeight(ctx: UiContext): Float32 {
        lineBoxHeight(ctx, 11.5) + tokens.space.s1 + lineBoxHeight(ctx, 22.0) + tokens.space.s1 +
        lineBoxHeight(ctx, 13.0)
    }

    /** `.dash-kbd`（dashboard.css:31-39）：10.5px 等宽字、`padding: 1px 4px`、1px 边框。 */
    private func kbdWidth(ctx: UiContext): Float32 {
        // `.dash-kbd { font-family: var(--font-mono); font-size: 10.5px; padding: 1px 4px }`（dashboard.css:31-39）
        4.0 * 2.0 + 2.0 * tokens.metrics.borderWidth + advanceWidth(ctx, keyboardHint, 10.5, 400, family: fontMono())
    }

    private func kbdHeight(ctx: UiContext): Float32 {
        // 参考图实测 16px（`.dash-kbd` 是行内盒，行盒高 10.5 × 1.5 = 15.75 取整）。
        max(16.0, lineBoxHeight(ctx, 10.5))
    }

    /** `.btn--sm` 盒模型（ui.css:19-23）+ 图标、文字、kbd 的排布（ui.css:10 gap: 8px）。 */
    private func buttonWidth(ctx: UiContext): Float32 {
        let metrics = buttonMetricsOf(ControlSize.Sm)
        metrics.paddingH * 2.0 + metrics.iconSide + BUTTON_GAP + advanceWidth(ctx, "命令面板", metrics.fontSize, 550) +
        kbdWidth(ctx)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        // 块高吸附到整数设备像素：浏览器把每个盒子的绘制边吸附到整像素，因此统计卡的上边框
        // 落在 182（参考图实测），而不是 80 + 77.75 + 24 = 181.75。
        let height = snapToPixel(titlesHeight(ctx))
        Size(max(available.w, 0.0), min(height, max(available.h, height)))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        // 标题列（`.page-header-titles`）
        var y = frame.y
        // `.dash-eyebrow`：11.5px、`letter-spacing: .08em`、`text-faint`（dashboard.css:19-24）
        drawLine(ctx, eyebrow, frame.x, y, lineBoxHeight(ctx, 11.5), 11.5, 400, tokens.color.textFaint,
            tracking: 0.08 * 11.5)
        y += lineBoxHeight(ctx, 11.5) + tokens.space.s1
        // `h1`：22px / 650 / `letter-spacing: -0.02em`（shell.css:283-285 + dashboard.css:14-17）
        drawLine(ctx, title, frame.x, y, lineBoxHeight(ctx, 22.0), 22.0, 650, tokens.color.text,
            tracking: -0.02 * 22.0)
        y += lineBoxHeight(ctx, 22.0) + tokens.space.s1
        // `.dash-summary`：13px、`text-muted`（dashboard.css:26-29）
        drawLine(ctx, summary, frame.x, y, lineBoxHeight(ctx, 13.0), 13.0, 400, tokens.color.textMuted)
        drawPaletteButton(ctx)
    }

    /** `.btn--sm.btn--secondary`（ui.css:19-23, 59-69）+ `iconLeft` + `.dash-kbd`。 */
    private func drawPaletteButton(ctx: UiContext): Unit {
        let metrics = buttonMetricsOf(ControlSize.Sm)
        let width = buttonWidth(ctx)
        let height = metrics.height
        let hovered = ctx.isHovered(buttonId)
        let pressed = ctx.isPressed(buttonId)
        buttonFrame = Rect(frame.right() - width, frame.y, width, height)
        let c = tokens.color
        let fill = if (hovered || pressed) {
            c.surface2
        } else {
            c.surface
        }
        let border = if (hovered || pressed) {
            c.borderStrong
        } else {
            c.border
        }
        shadow1(ctx, tokens, buttonFrame, tokens.radius.md)
        fillRound(ctx, buttonFrame, tokens.radius.md, fill)
        strokeRound(ctx, buttonFrame, tokens.radius.md, tokens.metrics.borderWidth, border)
        let inner = buttonFrame.inset(tokens.metrics.borderWidth)
        var x = inner.x + metrics.paddingH
        let iconY = inner.centerY() - metrics.iconSide / 2.0
        paintSpec(ctx, IconGlyph.Search, Rect(x, iconY, metrics.iconSide, metrics.iconSide), c.text)
        x += metrics.iconSide + BUTTON_GAP
        let fontSize = metrics.fontSize
        let textHeight = lineBoxHeight(ctx, fontSize)
        drawLine(ctx, "命令面板", x, inner.centerY() - textHeight / 2.0, textHeight, fontSize, 550, c.text)
        x += advanceWidth(ctx, "命令面板", fontSize, 550)
        // `.dash-kbd`：行内紧跟文字（浏览器把连续行内内容包成单个匿名 flex item，故无 8px gap）。
        let kbdWidthValue = kbdWidth(ctx)
        let kbdHeightValue = kbdHeight(ctx)
        let kbdRect = Rect(x, inner.centerY() - kbdHeightValue / 2.0, kbdWidthValue, kbdHeightValue)
        fillRound(ctx, kbdRect, tokens.radius.sm, c.surface2)
        strokeRound(ctx, kbdRect, tokens.radius.sm, tokens.metrics.borderWidth, c.border)
        let kbdTextHeight = lineBoxHeight(ctx, 10.5)
        drawLine(ctx, keyboardHint, kbdRect.x + 4.0 + tokens.metrics.borderWidth,
            kbdRect.centerY() - kbdTextHeight / 2.0, kbdTextHeight, 10.5, 400, c.textFaint, family: fontMono())
        if (ctx.showFocusRing(buttonId)) {
            focusRing(ctx, tokens, buttonFrame, tokens.radius.md)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(_, _) =>
                claimHoverIfInside(ctx, event, buttonFrame, buttonId, CursorShape.Interactive)
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (buttonFrame.contains(x, y)) {
                    ctx.focus(buttonId, viaKeyboard: false)
                    ctx.press(buttonId)
                    return true
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (ctx.isPressed(buttonId)) {
                    ctx.clearPress()
                    if (buttonFrame.contains(x, y)) {
                        onPalette()
                        return true
                    }
                }
            case UiEvent.KeyDown(key, isRepeat) =>
                if (ctx.hasFocus(buttonId) && !isRepeat) {
                    match (key) {
                        case Key.Enter | Key.Space =>
                            onPalette()
                            return true
                        case _ => ()
                    }
                }
            case _ => ()
        }
        false
    }

    public func focusableIds(): Array<String> {
        [buttonId]
    }

    public func pointerEventScope(): PointerEventScope {
        PointerEventScope.LayoutBounds
    }
}

/** `.btn--sm` 的盒模型数值（ui.css:19-23）：高 28、内边距 10、字号 12.5、图标 14。 */
struct DashboardButtonMetrics {
    let height: Float32
    let paddingH: Float32
    let fontSize: Float32
    let iconSide: Float32

    init(height: Float32, paddingH: Float32, fontSize: Float32, iconSide: Float32) {
        this.height = height
        this.paddingH = paddingH
        this.fontSize = fontSize
        this.iconSide = iconSide
    }
}

/** `ui.css:19-29` 的 `.btn--sm` / `.btn--md`。 */
func buttonMetricsOf(size: ControlSize): DashboardButtonMetrics {
    match (size) {
        case ControlSize.Sm => DashboardButtonMetrics(28.0, 10.0, 12.5, 14.0)
        case ControlSize.Md => DashboardButtonMetrics(34.0, 14.0, 13.5, 16.0)
    }
}

