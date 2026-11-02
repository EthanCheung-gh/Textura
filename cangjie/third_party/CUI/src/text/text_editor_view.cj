package cui.text

import sdl.{Color, Rect}
import cui.core.{TextAlign, UiContext, drawSurface, clampScrollOffset}

private let EDITOR_BLINK_INTERVAL: UInt64 = 530
private let EDITOR_SCROLL_GUTTER: Float32 = 8.0

internal struct TextEditorViewState {
    let style: TextInputStyle
    let multiline: Bool
    let wrap: Bool
    let scroll: Float32
    let xShift: Float32
    let upstream: Bool
    init(style: TextInputStyle, multiline!: Bool, wrap!: Bool = false, scroll!: Float32 = 0.0, xShift!: Float32 = 0.0,
        upstream!: Bool = false) {
        this.style = style
        this.multiline = multiline
        this.wrap = wrap
        this.scroll = scroll
        this.xShift = xShift
        this.upstream = upstream
    }
}

// One geometry shared by paint, hit-testing, visual-row navigation, scrolling and IME.
internal class TextEditorView {
    let ctx: UiContext
    let display: TextEditorDisplay
    let layout: TextEditorLayout
    let style: TextInputStyle
    let viewport: Rect
    let rowHeight: Float32
    let textHeight: Float32
    let caretWidth: Float32
    let multiline: Bool
    let upstream: Bool
    var scroll: Float32
    var xShift: Float32

    init(ctx: UiContext, frame: Rect, display: TextEditorDisplay, cache: TextEditorLayoutCache,
        state: TextEditorViewState) {
        let style = state.style;
        let multiline = state.multiline
        this.ctx = ctx
        this.display = display
        this.style = style
        this.multiline = multiline
        this.upstream = state.upstream
        this.xShift = if (state.wrap && multiline) {
            Float32(0.0)
        } else {
            state.xShift
        }
        let inside = style.viewport(ctx, frame)
        this.viewport = if (multiline) {
            Rect(inside.x, inside.y, max(0.0, min(inside.right(), frame.right() - EDITOR_SCROLL_GUTTER) - inside.x),
                inside.h)
        } else {
            inside
        }
        this.textHeight = ctx.textHeight()
        this.rowHeight = style.rowHeight(ctx, multiline: multiline)
        this.caretWidth = min(max(1.0, viewport.w), ctx.resolve(style.cursorWidth))
        this.layout = cache.get(ctx, display.text, max(1.0, viewport.w - caretWidth), state.wrap && multiline, multiline)
        this.scroll = clampScrollOffset(state.scroll, Float32(layout.rows.size) * rowHeight, viewport.h)
    }

    func contentHeight(): Float32 {
        Float32(layout.rows.size) * rowHeight
    }
    func cursorRow(): Int64 {
        layout.rowAt(display.cursor, upstream: upstream && !display.composing())
    }
    func textY(row: Int64): Float32 {
        let leading = if (style.lineHeight.isSome()) {
            (rowHeight - textHeight) / 2.0
        } else {
            Float32(0.0)
        }
        if (multiline) {
            viewport.y + Float32(row) * rowHeight - scroll + leading
        } else {
            viewport.centerY() - textHeight / 2.0
        }
    }
    func rowX(row: Int64): Float32 {
        match (style.alignment) {
            case TextAlign.Leading => return viewport.x - xShift;
            case _ => ()
        }
        alignedX(layout.width(ctx, row))
    }
    func alignedX(width: Float32): Float32 {
        let space = max(0.0, viewport.w - caretWidth - width)
        let aligned = match (style.alignment) {
            case TextAlign.Leading => Float32(0.0)
            case TextAlign.Center => space / 2.0
            case TextAlign.Trailing => space
        }
        viewport.x + aligned - xShift
    }
    func localX(row: Int64, byte: Int64): Float32 {
        let line = layout.rows[row]
        ctx.textWidth(display.text[line.start..max(line.start, min(line.end, byte))])
    }
    func followHorizontal(): Float32 {
        let row = cursorRow()
        let caret = localX(row, display.cursor)
        let width = max(1.0, viewport.w - caretWidth)
        var offset = max(0.0, min(xShift, max(0.0, layout.width(ctx, row) - width)))
        if (caret < offset) {
            offset = caret
        } else if (caret > offset + width) {
            offset = caret - width
        }
        xShift = offset
        offset
    }
    func followVertical(): Float32 {
        scroll = textAreaVisibleScroll(cursorRow(), scroll, rowHeight, viewport.h, contentHeight())
        scroll
    }
    func hit(x: Float32, y: Float32): (Int64, Bool) {
        let row = if (multiline) {
            max(0, min(layout.rows.size - 1, Int64(max(0.0, y - viewport.y + scroll) / rowHeight)))
        } else {
            Int64(0)
        }
        let line = layout.rows[row]
        let offset = textCursorForOffset(ctx, display.text, line.start, line.end, x - rowX(row))
        let affinity = row + 1 < layout.rows.size && offset == line.end && layout.rows[row + 1].start == offset
        (display.documentOffset(offset), affinity)
    }
    func verticalTarget(direction: Int64, preferredX: Float32): (Int64, Float32, Bool) {
        let current = cursorRow()
        let goal = if (preferredX < 0.0) {
            rowX(current) - viewport.x + xShift + localX(current, display.cursor)
        } else {
            preferredX
        }
        if (current + direction < 0) {
            return (0, goal, false)
        }
        if (current + direction >= layout.rows.size) {
            return (display.documentOffset(display.text.size), goal, false)
        }
        let row = max(0, min(layout.rows.size - 1, current + direction))
        let line = layout.rows[row]
        let offset = textCursorForOffset(ctx, display.text, line.start, line.end, goal - (rowX(row) - viewport.x + xShift))
        (display.documentOffset(offset), goal, row + 1 < layout.rows.size && offset == line.end &&
                layout.rows[row + 1].start == offset)
    }

    func draw(frame: Rect, id: String, editable: Bool, placeholder: String, blinkEpoch: UInt64): Unit {
        let surface = if (ctx.hasFocus(id) && style.focusedSurface.isSome()) {
            style.focusedSurface
        } else {
            style.surface
        }
        drawSurface(ctx, frame, surface.getOrDefault({=> ctx.theme.fieldSurface(active: ctx.showFocusRing(id))}))
        ctx.renderer.pushClip(viewport)
        try {
            drawEditorRows(this, id, placeholder)
            if (editable && ctx.hasFocus(id)) {
                paintCaret(blinkEpoch)
            }
        } finally {
            ctx.renderer.popClip()
        }
    }

    private func paintCaret(epoch: UInt64): Unit {
        let row = cursorRow()
        let caret = Rect(rowX(row) + localX(row, display.cursor), textY(row), caretWidth, textHeight)
        // Even when the user scrolls the caret out of view, keep the native input session alive.
        let anchor = Rect(max(viewport.x, min(caret.x, viewport.right() - caretWidth)),
            max(viewport.y, min(caret.y, viewport.bottom() - min(textHeight, viewport.h))), min(caretWidth, viewport.w),
            min(textHeight, viewport.h))
        ctx.setTextInputAnchor(anchor)
        let elapsed = ctx.frame.elapsedMs
        let phase = if (elapsed >= epoch) {
            elapsed - epoch
        } else {
            UInt64(0)
        }
        let wait = EDITOR_BLINK_INTERVAL - phase % EDITOR_BLINK_INTERVAL
        if (UInt64.Max - elapsed >= wait) {
            ctx.requestFrameAt(elapsed + wait)
        }
        if (display.composing() || textCursorVisible(ctx, epoch: epoch)) {
            ctx.renderer.fill(caret, style.cursorColor.getOrDefault({=> ctx.theme.accent}))
        }
    }
}

private func drawEditorRows(view: TextEditorView, id: String, placeholder: String): Unit {
    let ctx = view.ctx
    let first = if (view.multiline) {
        Int64(max(0.0, view.scroll) / view.rowHeight)
    } else {
        Int64(0)
    }
    var row = min(first, view.layout.rows.size - 1)
    while (row < view.layout.rows.size && view.textY(row) < view.viewport.bottom()) {
        let line = view.layout.rows[row]
        let selection = editorSelectionRect(view, row)
        if (let Some(rect) <- selection) {
            let color = if (ctx.hasFocus(id)) {
                view.style.selectionColor.getOrDefault({=> ctx.theme.accent.withAlpha(115)})
            } else {
                view.style.inactiveSelectionColor.getOrDefault({=> ctx.theme.mutedText.withAlpha(45)})
            }
            ctx.renderer.fill(rect, color)
        }
        let text = view.display.text[line.start..line.end]
        if (view.display.text.isEmpty() && !view.display.composing()) {
            ctx.text(placeholder, view.alignedX(ctx.textWidth(placeholder)), view.textY(row),
                view.style.placeholderColor.getOrDefault({=> ctx.theme.mutedText}))
        } else {
            drawEditorRowInk(view, row, text, selection)
        }
        drawEditorCompositionLine(view, row)
        row += 1
    }
}

private func drawEditorRowInk(view: TextEditorView, row: Int64, text: String, selection: ?Rect): Unit {
    let color = view.style.textColor.getOrDefault({=> view.ctx.theme.text})
    if (let Some(selected) <- view.style.selectedTextColor) {
        if (let Some(rect) <- selection) {
            let bounds = view.viewport
            // Preserve full-line shaping, but never draw normal ink below selected ink.
            drawClippedEditorInk(view, row, text, color, Rect(bounds.x, bounds.y, max(0.0, rect.x - bounds.x), bounds.h))
            drawClippedEditorInk(view, row, text, color,
                Rect(rect.right(), bounds.y, max(0.0, bounds.right() - rect.right()), bounds.h))
            drawClippedEditorInk(view, row, text, selected, rect)
            return
        }
    }
    view.ctx.text(text, view.rowX(row), view.textY(row), color)
}

private func drawClippedEditorInk(view: TextEditorView, row: Int64, text: String, color: Color, clip: Rect): Unit {
    if (clip.w <= 0.0 || clip.h <= 0.0) {
        return
    }
    view.ctx.renderer.pushClip(clip)
    try {
        view.ctx.text(text, view.rowX(row), view.textY(row), color)
    } finally {
        view.ctx.renderer.popClip()
    }
}

private func editorSelectionRect(view: TextEditorView, row: Int64): ?Rect {
    let line = view.layout.rows[row]
    let a = max(line.start, view.display.selectionStart)
    let b = min(line.end, view.display.selectionEnd)
    let selectedBreak = view.display.selectionStart <= line.end && view.display.selectionEnd > line.end && line.next > line
        .end
    if (a >= b && !selectedBreak) {
        return None
    }
    let x = view.rowX(row) + view.localX(row, a)
    let end = if (selectedBreak) {
        view.viewport.right()
    } else {
        view.rowX(row) + view.localX(row, b)
    }
    let height = if (view.style.lineHeight.isSome()) {
        view.rowHeight
    } else {
        view.textHeight
    }
    let y = view.textY(row) - if (view.style.lineHeight.isSome()) {
        (view.rowHeight - view.textHeight) / 2.0
    } else {
        0.0
    }
    Some(Rect(x, y, max(0.0, end - x), height))
}

private func drawEditorCompositionLine(view: TextEditorView, row: Int64): Unit {
    if (!view.display.composing()) {
        return
    }
    let line = view.layout.rows[row]
    let a = max(line.start, view.display.compositionStart)
    let b = min(line.end, view.display.compositionEnd)
    if (a >= b) {
        return
    }
    let x = view.rowX(row) + view.localX(row, a)
    let end = view.rowX(row) + view.localX(row, b)
    let y = view.textY(row) + view.textHeight - 1.0
    view.ctx.renderer.line(x, y, end, y, view.style.cursorColor.getOrDefault({=> view.ctx.theme.accent}))
}
