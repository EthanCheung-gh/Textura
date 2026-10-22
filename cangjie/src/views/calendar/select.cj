package textura.views.calendar

import cui.*
import textura.ui.*
import textura.views.calendar.logic.*

/*
 * 工具栏的年 / 月选择器（CalendarToolbar.tsx 的 `<Select>` + ui.css `.select`）。
 *
 * 闭合态按 `.cal-select { min-height: 32px; padding: 4px 26px 4px 8px; font-size: 12.5px }`
 * 自绘；展开态用 CUI `Overlay` 浮出选项列表（原生 `<select>` 的弹层不参与截图对比）。
 */

/** `.cal-select { min-height: 32px; padding: 4px 26px 4px 8px; font-size: 12.5px }`。 */
let SELECT_HEIGHT: Float32 = 32.0
let SELECT_PAD_LEFT: Float32 = 8.0
let SELECT_FONT: Float32 = 12.5
/** 弹层行高与可见行数（原生 select 弹层不参与像素对比，取可用值）。 */
let SELECT_ROW_HEIGHT: Float32 = 26.0
let SELECT_VISIBLE_ROWS: Int64 = 8

class CalSelectView <: Widget {
    private let tokens: ThemeTokens
    private let label: String
    private let options: Array<SelectOption>
    private let currentValue: String
    private let openCode: Int64
    private let openState: State<Int64>
    private let scrollState: State<Int64>
    private let onPick: (String) -> Unit
    private var frame = Rect.zero()

    init(
        tokens: ThemeTokens,
        label: String,
        options: Array<SelectOption>,
        currentValue: String,
        openCode: Int64,
        openState: State<Int64>,
        scrollState: State<Int64>,
        onPick: (String) -> Unit
    ) {
        this.tokens = tokens
        this.label = label
        this.options = options
        this.currentValue = currentValue
        this.openCode = openCode
        this.openState = openState
        this.scrollState = scrollState
        this.onPick = onPick
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(min(available.w, 96.0), min(available.h, SELECT_HEIGHT))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        fillRound(ctx, frame, tokens.radius.md, c.surface)
        strokeRound(ctx, frame, tokens.radius.md, tokens.metrics.borderWidth, c.border)
        let text = ellipsize(ctx, label, frame.w - SELECT_PAD_LEFT - 26.0, SELECT_FONT, 400)
        let textTop = snapped(frame.y)
        drawTextInBox(ctx, text, frame.x + SELECT_PAD_LEFT, textTop, frame.h, c.text, SELECT_FONT, 400, dy: -1.0)
        // ui.css `.select` 的下拉三角：两个 5×5 渐变拼出 9×5 的实心三角。
        let centerX = frame.right() - 16.0
        let top = frame.y + 16.0
        var row = 0
        while (row < 5) {
            let width = 9.0 - 2.0 * Float32(row)
            fillRect(ctx, Rect(centerX - width / 2.0, top + Float32(row), width, 1.0), c.textFaint)
            row += 1
        }
        if (openState.value == openCode) {
            registerPopup(ctx)
        }
    }

    private func popupRect(): Rect {
        let rows = minInt(options.size, SELECT_VISIBLE_ROWS)
        let height = Float32(rows) * SELECT_ROW_HEIGHT + 8.0
        Rect(frame.x, frame.bottom() + 4.0, max(frame.w, 128.0), height)
    }

    private func registerPopup(ctx: UiContext): Unit {
        let tokens = this.tokens
        let options = this.options
        let openState = this.openState
        let scrollState = this.scrollState
        let onPick = this.onPick
        let popup = popupRect()
        let owner = "cal-select-${openCode.toString()}"
        let overlay = Overlay(
            handleEvent: {inner, event =>
                match (event) {
                    case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                        if (popup.contains(x, y)) {
                            let row = Int64((y - popup.y - 4.0) / SELECT_ROW_HEIGHT) + scrollState.value
                            if (row >= 0 && row < options.size) {
                                onPick(options[row].value)
                            }
                            openState.value = 0
                            return true
                        }
                        openState.value = 0
                        return true
                    case UiEvent.MouseWheel(_, _, _, dy) =>
                        let maxOffset = maxInt(0, options.size - SELECT_VISIBLE_ROWS)
                        scrollState.value = minInt(maxOffset, maxInt(0, scrollState.value - Int64(dy)))
                        return true
                    case UiEvent.KeyDown(key, _) =>
                        match (key) {
                            case Key.Escape =>
                                openState.value = 0
                                return true
                            case _ => ()
                        }
                    case _ => ()
                }
                false
            },
            render: {inner =>
                let c = tokens.color
                softShadow(inner, popup, tokens.radius.md, tokens.shadow2)
                fillRound(inner, popup, tokens.radius.md, c.surface)
                strokeRound(inner, popup, tokens.radius.md, tokens.metrics.borderWidth, c.border)
                inner.renderer.pushClip(Rect(popup.x + 1.0, popup.y + 1.0, popup.w - 2.0, popup.h - 2.0))
                var shown = 0
                let offset = scrollState.value
                while (shown < SELECT_VISIBLE_ROWS && offset + shown < options.size) {
                    let option = options[offset + shown]
                    let rowTop = popup.y + 4.0 + Float32(shown) * SELECT_ROW_HEIGHT
                    if (option.value == currentValue) {
                        fillRect(inner, Rect(popup.x + 1.0, rowTop, popup.w - 2.0, SELECT_ROW_HEIGHT), c.accentSoft)
                    }
                    drawTextInBox(inner, option.label, popup.x + 10.0, rowTop, SELECT_ROW_HEIGHT, c.text,
                        SELECT_FONT, 400)
                    shown = shown + 1
                }
                inner.renderer.popClip()
            },
            owner: owner
        )
        ctx.setOverlay(overlay)
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(_, _) => claimHoverIfInside(ctx, event, frame, "calselect:${openCode.toString()}",
                CursorShape.Interactive)
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    openState.value = if (openState.value == openCode) {
                        0
                    } else {
                        openCode
                    }
                    return true
                }
            case _ => ()
        }
        false
    }
}
