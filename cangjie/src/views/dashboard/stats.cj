package textura.views.dashboard

import cui.*
import textura.ui.*

/*
 * `.dash-stats` / `.dash-stat`（dashboard.css:42-125，StatCards.tsx）。
 *
 * 四张卡：`grid-template-columns: repeat(4, minmax(0, 1fr)); gap: var(--space-3)`(dashboard.css:42-46)。
 * 卡内是 16px 内边距 + 3px 纵向间隙的三段：标签行（11.5px + 15px 图标）、
 * 数值行（26px/650 + 12px/500 单位，基线对齐）、说明行（11.5px，单行省略）。
 */
class StatCardView <: Widget {
    private let tokens: ThemeTokens
    private let label: String
    private let value: String
    private let unit: String
    private let meta: String
    private let glyph: IconGlyph
    private let tone: StatTone
    private let onClick: () -> Unit
    private let controlId: String
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, label: String, value: String, unit: String, meta: String, glyph: IconGlyph,
        tone: StatTone, onClick: () -> Unit) {
        this.tokens = tokens
        this.label = label
        this.value = value
        this.unit = unit
        this.meta = meta
        this.glyph = glyph
        this.tone = tone
        this.onClick = onClick
        this.controlId = focusableControlIdentity("dash-stat-${label}")
        emit(this)
    }

    /** `.dash-stat` 高度：16 + 标签行 + 3 + 数值行 + 3 + 说明行 + 16 + 1px 边框 ×2。 */
    private func cardHeight(ctx: UiContext): Float32 {
        let pad = tokens.space.s4
        let gap: Float32 = 3.0
        tokens.metrics.borderWidth * 2.0 + pad * 2.0 + lineBoxHeight(ctx, 11.5) + gap +
        fpSize(ctx, 26.0) * 1.25 + gap + lineBoxHeight(ctx, 11.5)
    }

    private func toneColor(): Color {
        let c = tokens.color
        match (tone) {
            case StatTone.Accent => c.accent
            case StatTone.Ok => c.ok
            case StatTone.Warn => c.warn
            case StatTone.Danger => c.danger
            case StatTone.Info => c.info
            case StatTone.Neutral => c.text
        }
    }

    public func measure(ctx: UiContext, available: Size): Size {
        let height = cardHeight(ctx)
        Size(max(available.w, 0.0), min(height, max(available.h, height)))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        let border = tokens.metrics.borderWidth
        let radius = tokens.radius.lg
        let hovered = ctx.isHovered(controlId) || ctx.isPressed(controlId)
        shadow1(ctx, tokens, frame, radius)
        // `.dash-stat:hover { border-color: border-strong; background: surface-2 }`（dashboard.css:62-66）
        fillRound(ctx, frame, radius, if (hovered) {
            c.surface2
        } else {
            c.surface
        })
        strokeRound(ctx, frame, radius, border, if (hovered) {
            c.borderStrong
        } else {
            c.border
        })
        let pad = tokens.space.s4
        let left = frame.x + border + pad
        let right = frame.right() - border - pad
        var y = frame.y + border + pad
        // `.dash-stat-top`：`justify-content: space-between; align-items: center; gap: 8px`（dashboard.css:68-74）
        let labelBox = lineBoxHeight(ctx, 11.5)
        drawLine(ctx, label, left, y, labelBox, 11.5, 400, c.textFaint)
        let iconSide: Float32 = 15.0
        paintSpec(ctx, glyph, Rect(right - iconSide, y + labelBox / 2.0 - iconSide / 2.0, iconSide, iconSide),
            c.textFaint)
        y += labelBox + 3.0
        // `.dash-stat-value`：`font-size: 26px; line-height: 1.25; align-items: baseline; gap: 4px`（dashboard.css:81-97）
        let valueBox = fpSize(ctx, 26.0) * 1.25
        let baseline = baselineWithin(ctx, y, valueBox, 26.0, 650)
        drawAtBaseline(ctx, value, left, baseline, 26.0, 650, toneColor())
        if (!unit.isEmpty()) {
            let valueWidth = advanceWidth(ctx, value, 26.0, 650)
            drawAtBaseline(ctx, unit, left + valueWidth + 4.0, baseline, 12.0, 500, c.textMuted)
        }
        y += valueBox + 3.0
        // `.dash-stat-meta`：11.5px、`text-faint`、单行省略（dashboard.css:99-105）
        let metaText = ellipsize(ctx, meta, max(0.0, right - left), 11.5, 400)
        drawLine(ctx, metaText, left, y, lineBoxHeight(ctx, 11.5), 11.5, 400, c.textFaint)
        if (ctx.showFocusRing(controlId)) {
            focusRing(ctx, tokens, frame, radius)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(_, _) =>
                claimHoverIfInside(ctx, event, frame, controlId, CursorShape.Interactive)
            case UiEvent.MouseDown(pressButton, x, y) where isPrimaryPointerButton(pressButton) =>
                if (frame.contains(x, y)) {
                    ctx.focus(controlId, viaKeyboard: false)
                    ctx.press(controlId)
                    return true
                }
            case UiEvent.MouseUp(_, x, y) =>
                if (ctx.isPressed(controlId)) {
                    ctx.clearPress()
                    if (frame.contains(x, y)) {
                        onClick()
                        return true
                    }
                }
            case UiEvent.KeyDown(key, isRepeat) =>
                if (ctx.hasFocus(controlId) && !isRepeat) {
                    match (key) {
                        case Key.Enter | Key.Space =>
                            onClick()
                            return true
                        case _ => ()
                    }
                }
            case _ => ()
        }
        false
    }

    public func focusableIds(): Array<String> {
        [controlId]
    }

    public func pointerEventScope(): PointerEventScope {
        PointerEventScope.LayoutBounds
    }

    /** HStack 里四张卡等宽：`repeat(4, minmax(0, 1fr))`，各自权重 1。 */
    public func isFlexible(): Bool {
        true
    }

    public func flexWeight(): Float32 {
        1.0
    }
}
