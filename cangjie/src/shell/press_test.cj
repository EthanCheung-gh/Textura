package textura.shell

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.ui.*

/*
 * Press → state change, per control class, with the button codings the two backends use.
 *
 * The device sends `MouseButton.Left` for a finger today, but the SDL port can also report
 * `RawCode(0)` (no button information) or `RawCode(1)` (the left button's real code) — see
 * docs/DEVICE-NOTES.md §1 and §4.4. `textura.ui.isPrimaryPointerButton` folds all three, and
 * these tests pin that each kind of control actually reacts to a press coded any of those
 * ways, rather than only to `Left`:
 *
 *   - a button (also the modal footer's save/cancel),
 *   - a segmented control's item,
 *   - a dialog's own footer button (dispatched through the overlay stack).
 *
 * Row selection is covered by `sidebar_click_test.cj` (a nav row press routes), and the
 * text-field press path by `input_focus_test.cj`.
 */

private let PRESS_THEME: Theme = Theme.light()
private let PRESS_TOKENS: ThemeTokens = ThemeTokens.light()
private let PRESS_RECT: Rect = Rect(0.0, 0.0, 400.0, 300.0)

/** A press with the given button coding, as the backend would deliver it. */
private func press(testHost: WidgetTestHost, button: MouseButton, x: Float32, y: Float32, body: () -> Unit): Unit {
    let _ = testHost.frame(PRESS_RECT,
        events: [
            UiEvent.MouseMove(x, y),
            UiEvent.MouseDown(button, x, y),
            UiEvent.MouseUp(button, x, y)
        ], body: body)
}

@Test
func buttonPressCountsUnderEveryButtonCoding(): Unit {
    let clicks = State<Int64>(0)
    let testHost = WidgetTestHost()
    let body = {=>
        VStack(spacing: vp(0.0)) {
            ButtonView(PRESS_TOKENS, "点我", {=> clicks.value = clicks.value + 1})
                .width(120.0).height(34.0)
        }.padding(20.0)
        ()
    }
    let _ = testHost.frame(PRESS_RECT, body: body)
    press(testHost, MouseButton.Left, 80.0, 37.0, body)
    @Expect(clicks.value, 1)
    press(testHost, MouseButton.RawCode(0), 80.0, 37.0, body)
    @Expect(clicks.value, 2)
    press(testHost, MouseButton.RawCode(1), 80.0, 37.0, body)
    @Expect(clicks.value, 3)
    // A secondary button is not a primary press: no extra click.
    press(testHost, MouseButton.RawCode(3), 80.0, 37.0, body)
    @Expect(clicks.value, 3)
}

@Test
func segmentedPressSelectsThePressedItem(): Unit {
    let selection = State<Int64>(0)
    let testHost = WidgetTestHost()
    let body = {=>
        VStack(spacing: vp(0.0)) {
            SegmentedView(PRESS_TOKENS, [SegmentedItem("月"), SegmentedItem("周")], selection)
                .width(200.0).height(34.0)
        }.padding(20.0)
        ()
    }
    let _ = testHost.frame(PRESS_RECT, body: body)
    // The tray is a 2vp padding + 1px border around two text-sized items with a 2vp gap
    // (`controls_display.cj`); compute the item centres the same way the control lays them out.
    let ctx = testHost.context
    let fontSize = fpSize(ctx, Float32(TextSize.label))
    let monthW: Float32 = textWidth(ctx, "月", fontSize, Int64(550)) + 20.0f32
    let weekW: Float32 = textWidth(ctx, "周", fontSize, Int64(550)) + 20.0f32
    let trayX: Float32 = 20.0f32 + 1.0f32 + 2.0f32
    let secondCenter: Float32 = trayX + monthW + 2.0f32 + weekW / 2.0f32
    let firstCenter: Float32 = trayX + monthW / 2.0f32
    let centerY: Float32 = 20.0f32 + 34.0f32 / 2.0f32
    press(testHost, MouseButton.RawCode(1), secondCenter, centerY, body)
    @Expect(selection.value, 1)
    press(testHost, MouseButton.Left, firstCenter, centerY, body)
    @Expect(selection.value, 0)
}

/**
 * A dialog's footer button reacts to a primary press even though the event enters through the
 * overlay stack rather than the page tree (the modal has to route it to its content layer).
 */
@Test
func dialogFooterButtonPressRunsThroughTheOverlay(): Unit {
    let saved = State<Int64>(0)
    let open = State<Bool>(true)
    let testHost = WidgetTestHost()
    let body = {=>
        Ui.modal(PRESS_THEME, open, {=> open.value = false}, title: "编辑", width: 400.0,
            footer: {=>
                // A CUI `Button` registers semantics (label + rect), which lets the test find the
                // control instead of hard-coding the panel's measured height.
                Button("保存", {=> saved.value = saved.value + 1})
            }, body: {=>
                Ui.field(PRESS_THEME, label: "标题") {
                    Ui.textInput(PRESS_THEME, State<String>("草稿"), key: "press-dialog-title")
                }
            })
        ()
    }
    let _ = testHost.frame(PRESS_RECT, body: body)
    var target: ?Rect = None
    for (node in testHost.context.semanticsSnapshot()) {
        match (node.properties.role) {
            case SemanticsRole.Button =>
                if (node.properties.label == "保存") {
                    target = Some(node.bounds)
                }
            case _ => ()
        }
    }
    @Expect(target.isSome(), true)
    match (target) {
        case Some(rect) => press(testHost, MouseButton.RawCode(0), rect.centerX(), rect.centerY(), body)
        case None => ()
    }
    @Expect(saved.value, 1)
}
