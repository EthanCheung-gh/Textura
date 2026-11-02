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
/** 弹层行高与最多可见行数（原生 select 弹层不参与像素对比，取可用值）。 */
let SELECT_ROW_HEIGHT: Float32 = 26.0
/**
 * 一次最多显示 12 行：月份正好 1–12 全部可见（用户反馈「列表不全」），
 * 年份（1900–2100）窗口跟随选中项滚动。
 */
let SELECT_VISIBLE_ROWS: Int64 = 12
let SELECT_MIN_VISIBLE_ROWS: Int64 = 3

/**
 * 打开弹层时的滚动位置：让当前值落在可见窗口内并尽量居中。
 *
 * 年份列表有 201 项，旧实现固定从 1900 开始滚动，弹层里看不到、也没有高亮今年的项
 * ——看起来就像「没有默认选中今年」。这里按当前值算窗口，保证选中项可见。
 */
func calSelectInitialScroll(options: Array<SelectOption>, currentValue: String, visible: Int64): Int64 {
    var index = 0
    var found = false
    var scan = 0
    for (option in options) {
        if (!found && option.value == currentValue) {
            index = scan
            found = true
        }
        scan += 1
    }
    let rows = if (visible < 1) {
        1
    } else {
        visible
    }
    var offset = index - (rows - 1) / 2
    let maxOffset = if (options.size > rows) {
        options.size - rows
    } else {
        0
    }
    if (offset < 0) {
        offset = 0
    }
    if (offset > maxOffset) {
        offset = maxOffset
    }
    offset
}

/** Select 弹层可见行数：12 行封顶，并保证不超出窗口下沿。 */
func calSelectVisibleRows(options: Array<SelectOption>, viewportHeight: Float32,
    anchorBottom: Float32): Int64 {
    let space = viewportHeight - anchorBottom - 16.0
    var fit = Int64(space / SELECT_ROW_HEIGHT)
    if (fit < SELECT_MIN_VISIBLE_ROWS) {
        fit = SELECT_MIN_VISIBLE_ROWS
    }
    if (fit > SELECT_VISIBLE_ROWS) {
        fit = SELECT_VISIBLE_ROWS
    }
    if (options.size < fit) {
        return options.size
    }
    fit
}

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

    private func popupRect(ctx: UiContext): Rect {
        let rows = calSelectVisibleRows(options, ctx.viewportHeight, frame.bottom())
        let height = Float32(rows) * SELECT_ROW_HEIGHT + 8.0
        // 下面放不下时翻到字段上方（小窗口 / 全屏切换后仍能看全列表）。
        var top = frame.bottom() + 4.0
        if (top + height > ctx.viewportHeight - 8.0 && frame.y - 4.0 - height >= 8.0) {
            top = frame.y - 4.0 - height
        }
        Rect(frame.x, top, max(frame.w, 128.0), height)
    }

    private func registerPopup(ctx: UiContext): Unit {
        let tokens = this.tokens
        let options = this.options
        let openState = this.openState
        let scrollState = this.scrollState
        let onPick = this.onPick
        let popup = popupRect(ctx)
        let rows = calSelectVisibleRows(options, ctx.viewportHeight, frame.bottom())
        let owner = "cal-select-${openCode.toString()}"
        let overlay = Overlay(
            handleEvent: {inner, event =>
                match (event) {
                    case UiEvent.MouseDown(pressButton, x, y) where isPrimaryPointerButton(pressButton) =>
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
                    case UiEvent.MouseWheel(_, dy, _, _) =>
                        let maxOffset = maxInt(0, options.size - rows)
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
                while (shown < rows && offset + shown < options.size) {
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
            case UiEvent.MouseDown(pressButton, x, y) where isPrimaryPointerButton(pressButton) =>
                if (frame.contains(x, y)) {
                    if (openState.value == openCode) {
                        openState.value = 0
                    } else {
                        // 打开时把窗口滚到当前值（年份默认落在今年，而不是 1900）。
                        let visible = calSelectVisibleRows(options, ctx.viewportHeight, frame.bottom())
                        scrollState.value = calSelectInitialScroll(options, currentValue, visible)
                        openState.value = openCode
                    }
                    return true
                }
            case _ => ()
        }
        false
    }
}
