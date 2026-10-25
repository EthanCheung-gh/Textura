package cui.testing

import sdl.{Key, Rect, Size, UiEvent}
import cui.core.{ScrollView, UiContext, Widget, emit}

/*
 * A wheel over a `ScrollView` must reach the screen.
 *
 * The device report was "the OKR page does not repaint while the wheel scrolls it; switching to
 * another tab and back shows the scrolled page". The offset State did advance, so the missing link
 * was invalidation: the wheel moved a State that the frame only observed through a retained layout
 * phase, and (see Textura patch CUI-P12 in `core/state_phase_dependency.cj`) that observation could
 * be dropped, leaving the offset write with no listener at all. A layout that never re-runs keeps
 * the previous frame's geometry, and since the scroll viewport itself does not move, the page below
 * it paints exactly the same pixels — a wheel that looks broken until a rebuild forces new
 * coordinates.
 *
 * These tests pin the contract at the host level: one wheel event, then the very next frame has to
 * lay the content out again at the new offset and paint from those new coordinates, while a wheel
 * that cannot move the viewport must not invalidate anything.
 */

/* `core/scrolling.cj: CUI_SCROLL_WHEEL_STEP` — one wheel notch, in logical pixels. */
private let WHEEL_STEP: Float32 = 72.0

/* Geometry and paint counters shared by the probe instances of every build in one session. */
private class WheelCanvasRecord {
    var layoutCalls: Int64 = 0
    var drawCalls: Int64 = 0
    var layoutY: Float32 = 0.0
    var paintedY: Float32 = 0.0
}

/*
 * Self-drawn content: its paint geometry comes from the rectangle the frame assigned it, so a
 * missing re-layout is indistinguishable from a missing repaint — exactly like the OKR canvas.
 */
private class WheelCanvasProbe <: Widget {
    private let record: WheelCanvasRecord
    private let contentHeight: Float32

    init(record: WheelCanvasRecord, contentHeight: Float32) {
        this.record = record
        this.contentHeight = contentHeight
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, contentHeight)
    }

    public func layout(_: UiContext, assigned: Rect): Unit {
        record.layoutCalls += 1
        record.layoutY = assigned.y
    }

    public func draw(ctx: UiContext): Unit {
        record.drawCalls += 1
        record.paintedY = record.layoutY
        ctx.renderer.fill(Rect(0.0, record.paintedY, 24.0, 24.0), ctx.theme.accent)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

private let WHEEL_VIEWPORT: Rect = Rect(0.0, 0.0, 320.0, 200.0)

/* SDL reports a wheel-down notch as -1 on the y axis, which scrolls the viewport downwards. */
private let WHEEL_DOWN: UiEvent = UiEvent.MouseWheel(0.0, -1.0, 100.0, 100.0)

private func wheelBody(record: WheelCanvasRecord, contentHeight: Float32): () -> Unit {
    {
        =>
            ScrollView(key: Some("wheel-host")) {
                WheelCanvasProbe(record, contentHeight)
            }.width(WHEEL_VIEWPORT.w).height(WHEEL_VIEWPORT.h)
            ()
    }
}

@Test
func wheelScrollReLaysOutAndRepaintsTheContent(): Unit {
    let record = WheelCanvasRecord()
    let host = WidgetTestHost()
    let body = wheelBody(record, 4000.0)
    let _ = host.frame(WHEEL_VIEWPORT, body: body)
    @Expect(record.layoutY, Float32(0.0))
    let layoutsBefore = record.layoutCalls
    let drawsBefore = record.drawCalls

    let _ = host.frame(WHEEL_VIEWPORT, events: [WHEEL_DOWN], body: body)

    // The wheel frame itself carries the new geometry: no extra frame, no route change.
    @Expect(record.layoutY, -WHEEL_STEP)
    @Expect(record.layoutCalls > layoutsBefore, true)
    @Expect(record.drawCalls > drawsBefore, true)
    @Expect(record.paintedY, -WHEEL_STEP)

    // A second notch compounds on what is already painted.
    let _ = host.frame(WHEEL_VIEWPORT, events: [WHEEL_DOWN], body: body)
    @Expect(record.layoutY, -WHEEL_STEP * 2.0)
    @Expect(record.paintedY, -WHEEL_STEP * 2.0)
}

@Test
func wheelOverFittingContentNeitherMovesNorReLaysOut(): Unit {
    let record = WheelCanvasRecord()
    let host = WidgetTestHost()
    let body = wheelBody(record, WHEEL_VIEWPORT.h - 40.0)
    let _ = host.frame(WHEEL_VIEWPORT, body: body)
    @Expect(record.layoutY, Float32(0.0))
    let layoutsBefore = record.layoutCalls

    let _ = host.frame(WHEEL_VIEWPORT, events: [WHEEL_DOWN], body: body)

    // Nothing scrolls, so nothing is invalidated: the event bubbles out and the frame reuses the
    // committed layout instead of re-laying out an unchanged picture.
    @Expect(record.layoutY, Float32(0.0))
    @Expect(record.layoutCalls, layoutsBefore)
}

@Test
func wheelAtTheScrollLimitStopsMovingTheContent(): Unit {
    let record = WheelCanvasRecord()
    let host = WidgetTestHost()
    // 30px of travel: one notch clamps to the bottom, the next one has nowhere to go.
    let body = wheelBody(record, WHEEL_VIEWPORT.h + 30.0)
    let _ = host.frame(WHEEL_VIEWPORT, body: body)
    let _ = host.frame(WHEEL_VIEWPORT, events: [WHEEL_DOWN], body: body)
    @Expect(record.layoutY, -30.0)
    let layoutsAtLimit = record.layoutCalls

    let _ = host.frame(WHEEL_VIEWPORT, events: [WHEEL_DOWN], body: body)

    @Expect(record.layoutY, -30.0)
    @Expect(record.layoutCalls, layoutsAtLimit)
}

/* Opt-in keyboard scrolling shares the offset State, so it must keep re-laying the content out. */
@Test
func keyboardScrollStillPagesTheContent(): Unit {
    let record = WheelCanvasRecord()
    let host = WidgetTestHost()
    let body: () -> Unit = {
        =>
            ScrollView(key: Some("keyboard-host")) {
                WheelCanvasProbe(record, 4000.0)
            }.keyboardScroll(true).width(WHEEL_VIEWPORT.w).height(WHEEL_VIEWPORT.h)
            ()
    }
    let _ = host.frame(WHEEL_VIEWPORT, body: body)
    @Expect(record.layoutY, Float32(0.0))

    let _ = host.frame(WHEEL_VIEWPORT, events: [UiEvent.KeyDown(Key.PageDown, false)], body: body)

    // PageDown pages by 0.9 viewports.
    @Expect(record.layoutY, -(WHEEL_VIEWPORT.h * 0.9))
}
