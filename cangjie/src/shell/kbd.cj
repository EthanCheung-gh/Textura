package textura.shell

import cui.*
import textura.ui.*

/*
 * `kbd` chips shared by the command palette (`.palette-kbd`), quick capture (`.capture-kbd`)
 * and the shortcuts dialog (`.shortcut-key`). CUI has no inline <kbd>, so the shell draws
 * the chip: mono 10.5px, `--surface-2` fill, 1px `--border`, radius 4, 1px 5-6px padding.
 */

public enum KeyChipStyle {
    | Palette
    | Capture
    | Shortcut
}

public class KeyChipView <: Widget {
    private let tokens: ThemeTokens
    private let text: String
    private let style: KeyChipStyle
    private var frame = Rect.zero()

    public init(tokens: ThemeTokens, text: String, style!: KeyChipStyle = KeyChipStyle.Palette) {
        this.tokens = tokens
        this.text = text
        this.style = style
        emit(this)
    }

    private func paddings(): (Float32, Float32) {
        match (style) {
            case KeyChipStyle.Palette => (5.0, 1.0)
            case KeyChipStyle.Capture => (5.0, 1.0)
            case KeyChipStyle.Shortcut => (6.0, 1.0)
        }
    }

    private func bottomBorder(): Float32 {
        match (style) {
            case KeyChipStyle.Shortcut => 2.0
            case _ => CHROME_BORDER
        }
    }

    public func measure(ctx: UiContext, _: Size): Size {
        let (padX, padY) = paddings()
        let fontSize = fpSize(ctx, 10.5)
        let width = textWidth(ctx, text, fontSize, 400) + padX * 2.0 + CHROME_BORDER * 2.0
        let height = lineBox(10.5) + padY * 2.0 + CHROME_BORDER + bottomBorder()
        Size(width, height)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func isFlexible(): Bool {
        false
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        fillRound(ctx, frame, tokens.radius.sm, c.surface2)
        // `border: 1px solid border; border-bottom-width: 2px` for `.shortcut-key`.
        ctx.renderer.strokeRoundedRect(frame, tokens.radius.sm, Pen(width: CHROME_BORDER, color: c.border))
        if (bottomBorder() > CHROME_BORDER) {
            ctx.renderer.fill(Rect(frame.x + 1.0, frame.bottom() - bottomBorder(), frame.w - 2.0,
                bottomBorder()), c.border)
        }
        let (_, padY) = paddings()
        textCentered(ctx, text, Rect(frame.x, frame.y + padY, frame.w, lineBox(10.5)), c.textMuted,
            fpSize(ctx, 10.5), 400, family: fontMono())
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}
