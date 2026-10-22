package textura.views.dashboard

import cui.*
import textura.ui.*

/*
 * `.dash-card-head`（dashboard.css:152-197）：图标 + 标题 + 副标题在左，计数或 `.dash-link`
 * 在右，底部 1px 分隔线；`align-items: flex-start` 让右侧控件与标题行顶对齐。
 */
class CardHeadView <: Widget {
    private let tokens: ThemeTokens
    private let glyph: IconGlyph
    private let title: String
    private let sub: String
    private let trailingText: String
    private let onLink: () -> Unit
    private let linkId: String
    private var frame = Rect.zero()
    private var linkFrame = Rect.zero()
    private let hasLink: Bool

    init(tokens: ThemeTokens, glyph: IconGlyph, title: String, sub: String, trailingText!: String = "",
        asLink!: Bool = false, onLink!: () -> Unit = {=> ()}) {
        this.tokens = tokens
        this.glyph = glyph
        this.title = title
        this.sub = sub
        this.trailingText = trailingText
        this.onLink = onLink
        this.hasLink = asLink && !trailingText.isEmpty()
        if (this.hasLink) {
            this.linkId = focusableControlIdentity("dash-head-link-${title}")
        } else {
            this.linkId = ""
        }
        emit(this)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        let height = cardHeadHeight(ctx)
        Size(max(available.w, 0.0), min(height, max(available.h, height)))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        paintCardHead(ctx, tokens, frame, glyph, title, sub)
        let contentTopY = frame.y + CARD_HEAD_PAD_TOP
        let contentRight = frame.right() - tokens.space.s4
        if (hasLink) {
            // `.dash-link { padding: 2px 4px; font-size: 12px }`（dashboard.css:187-193）
            let size = cardLinkSize(ctx, trailingText)
            linkFrame = Rect(contentRight - size.w, contentTopY, size.w, size.h)
            drawCardLink(ctx, tokens, linkFrame, trailingText, ctx.isHovered(linkId) || ctx.isPressed(linkId))
            if (ctx.showFocusRing(linkId)) {
                focusRing(ctx, tokens, linkFrame, tokens.radius.sm)
            }
        } else if (!trailingText.isEmpty()) {
            // `.dash-card-count`（dashboard.css:180-185）：与标题行顶对齐。
            let height = lineBoxHeight(ctx, 11.5)
            let width = advanceWidth(ctx, trailingText, 11.5, 400)
            drawCardCount(ctx, tokens, Rect(contentRight - width, contentTopY, width, height), trailingText)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        if (!hasLink) {
            return false
        }
        match (event) {
            case UiEvent.MouseMove(_, _) =>
                claimHoverIfInside(ctx, event, linkFrame, linkId, CursorShape.Interactive)
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (linkFrame.contains(x, y)) {
                    ctx.focus(linkId, viaKeyboard: false)
                    ctx.press(linkId)
                    return true
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (ctx.isPressed(linkId)) {
                    ctx.clearPress()
                    if (linkFrame.contains(x, y)) {
                        onLink()
                        return true
                    }
                }
            case UiEvent.KeyDown(key, isRepeat) =>
                if (ctx.hasFocus(linkId) && !isRepeat) {
                    match (key) {
                        case Key.Enter | Key.Space =>
                            onLink()
                            return true
                        case _ => ()
                    }
                }
            case _ => ()
        }
        false
    }

    public func focusableIds(): Array<String> {
        if (hasLink) {
            [linkId]
        } else {
            Array<String>()
        }
    }
}

/** `.dash-card` 外壳：`padding: 1px`（`border: 1px` 等价）+ surface + `--radius-lg` + `--shadow-1`。 */
func cardShell(widget: Widget, tokens: ThemeTokens): Widget {
    widget
        .padding(tokens.metrics.borderWidth)
        .background(tokens.color.surface, tokens.radius.lg)
        .border(tokens.color.border, width: tokens.metrics.borderWidth, radius: tokens.radius.lg)
        .shadow(
            Shadow(
                color: tokens.shadow1.color,
                offsetY: tokens.shadow1.offsetY,
                offsetX: tokens.shadow1.offsetX,
                blur: tokens.shadow1.blur,
                spread: tokens.shadow1.spread
            ),
            radius: tokens.radius.lg
        )
}
