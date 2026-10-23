package textura.shell

import std.env.*
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*

/*
 * Keyboard delivery into the shell: the global hotkeys, Esc, and Tab traversal.
 *
 * Why these exist: on the HarmonyOS device the keys never reached the window at all (ArkUI only
 * dispatches hardware keys to a focused component and the XComponent never took focus), so every
 * shortcut looked unimplemented while the handlers were fine. The device-side evidence lives in
 * docs/DEVICE-NOTES.md §7; these tests pin the handler half so a regression there is caught on a
 * host, and so the device run only has to prove delivery.
 */

private let KEYS_RECT: Rect = Rect(0.0, 0.0, 1440.0, 900.0)
private let KEYS_ANCHOR: Int64 = 1773626400000
private let KEYS_HOME: String = "/tmp/textura-shell-keys-test-home"
/* SDL_KMOD_LCTRL / SDL_KMOD_LSHIFT, the bit values `EventKeyModifiers` decodes. */
private let MOD_CTRL: UInt16 = UInt16(0x0040)
private let MOD_SHIFT: UInt16 = UInt16(0x0001)
/* Sidebar second row (日历) centre: the press used to prove the page still takes input. */
private let NAV_X: Float32 = 60.0
private let NAV_FIRST_ROW_Y: Float32 = 126.0
private let ROUTE_ORDER: Array<Route> = ROUTES

private func keysTestHost(): ShellHost {
    try {
        setVariable("HOME", KEYS_HOME)
    } catch (_: Exception) {
        ()
    }
    let clock = FixedClock(KEYS_ANCHOR)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    store.setRoute(routeId(Route.Dashboard))
    let runtime = ShellRuntime(ShellPreferences.load(), store)
    let noLoadError: ?String = None
    ShellHost(store, runtime, "2026-01-01", false, noLoadError, 1440, 900)
}

/* A key press as the SDL backend delivers it: the event plus the modifier snapshot taken with it. */
private func keyRecord(key: Key, rawModifiers: UInt16): UiEventRecord {
    UiEventRecord(UiEvent.KeyDown(key, false),
        UiEventMetadata(modifiers: EventKeyModifiers(raw: rawModifiers)))
}

private func pressKey(testHost: WidgetTestHost, key: Key, rawModifiers: UInt16, body: () -> Unit): TestFrameResult {
    return testHost.frameRecords(KEYS_RECT, events: [keyRecord(key, rawModifiers)], body: body)
}

/* Ctrl+K opens the command palette; Esc (with no modifier) closes it again. */
@Test
func commandPaletteOpensOnCtrlKAndClosesOnEscape(): Unit {
    // Every route must route the hotkey the same way: a view that swallows keys before the shell's
    // handler sees them would break the palette only on that page.
    for (route in ROUTES) {
        let host = keysTestHost()
        host.armStoreBridge({action => action()})
        host.store.setRoute(routeId(route))
        let testHost = WidgetTestHost()
        let body = {=> buildShell(host)}
        // Some views keep a *paint-only* layer registered (the calendar's quick-add placeholder
        // overlay declines every event with `handleEvent: {_, _ => false}`), so the assertion is
        // "the palette adds exactly one layer and gives it back", not "the stack is empty".
        let baseline = testHost.frame(KEYS_RECT, body: body).metrics.overlayCount
        @Expect(host.store.ui.value().paletteOpen, false)
        let _ = pressKey(testHost, Key.Letter(UInt8(75)), MOD_CTRL, body)
        let opened = host.store.ui.value().paletteOpen
        let openOverlays = testHost.frame(KEYS_RECT, body: body).metrics.overlayCount
        let _ = pressKey(testHost, Key.Escape, UInt16(0), body)
        let stillOpen = host.store.ui.value().paletteOpen
        let closedOverlays = testHost.frame(KEYS_RECT, body: body).metrics.overlayCount
        @Expect(opened, true)
        @Expect(openOverlays, baseline + 1)
        @Expect(stillOpen, false)
        @Expect(closedOverlays, baseline)
        // With the dialog gone the page underneath must take input again.
        let y = NAV_FIRST_ROW_Y
        let _ = testHost.frame(KEYS_RECT,
            events: [
                UiEvent.MouseMove(NAV_X, y),
                UiEvent.MouseDown(MouseButton.Left, NAV_X, y),
                UiEvent.MouseUp(MouseButton.Left, NAV_X, y)
            ], body: body)
        @Expect(host.store.ui.value().route, routeId(ROUTE_ORDER[1]))
    }
}

/*
 * A view may open quick capture by writing `store.ui` itself (GTD's 快速收集 button, the dashboard
 * card, the command palette) — it cannot call `ShellHost.openCapture()` without importing the shell.
 * The focus request therefore hangs off the visibility edge detected in `buildShell`, not off the
 * shell's own opener; this pins that path.
 */
@Test
func quickCaptureOpenedFromAViewFocusesItsInput(): Unit {
    let host = keysTestHost()
    host.armStoreBridge({action => action()})
    let testHost = WidgetTestHost()
    let body = {=> buildShell(host)}
    let _ = testHost.frame(KEYS_RECT, body: body)
    host.store.setUi({ui => ui.quickCaptureOpen = true})
    let _ = testHost.frame(KEYS_RECT, body: body)
    @Expect(testHost.context.focusId, "capture-input")
    host.closeCapture()
    let _ = testHost.frame(KEYS_RECT, body: body)
    @Expect(testHost.context.focusId, "shell-nav-dashboard")
}

/*
 * Source gate for the ArkTS key bridge: it may only forward keys ArkUI would otherwise swallow.
 *
 * `harmony/entry/src/main/ets/pages/Index.ets` forwards Tab/Shift+Tab, the four arrows and
 * Ctrl/Cmd+letter into SDL through `libtextura_keys.so`. Escape must stay out of that table: the
 * XComponent's native key callback already delivers it (`ev#3 KeyDown key=Escape` on device), so
 * forwarding it as well delivered one physical press twice — the first Esc closed the top layer and
 * the duplicate immediately acted on the next one. This test reads the page source (the bridge is
 * ArkTS, not Cangjie) and pins both halves: no Escape, Tab/arrows still present.
 */
@Test
func arktsKeyBridgeForwardsOnlyKeysArkUiSwallows(): Unit {
    let root = match (getVariable("TEXTURA_CANGJIE_ROOT")) {
        case Some(value) => value
        case None => "."
    }
    let path = "${root}/harmony/entry/src/main/ets/pages/Index.ets"
    var text = ""
    try {
        text = String.fromUtf8(File.readFrom(path))
    } catch (_: Exception) {
        @Expect("missing ${path}", "")
    }
    let start = match (text.indexOf("private sdlScancodeFor")) {
        case Some(index) => index
        case None => Int64(-1)
    }
    let end = match (text.indexOf("private forwardKeyToSdl")) {
        case Some(index) => index
        case None => Int64(-1)
    }
    @Expect(start >= 0, true)
    @Expect(end > start, true)
    let table = text[start..end]
    @Expect(table.indexOf("KEYCODE_ESCAPE").isNone(), true)
    @Expect(table.indexOf("KEYCODE_TAB").isSome(), true)
    @Expect(table.indexOf("KEYCODE_DPAD_UP").isSome(), true)
    @Expect(table.indexOf("KEYCODE_A").isSome(), true)
}

/* `?` (no modifier) opens the shortcuts dialog, and Esc closes it. */
@Test
func shortcutsDialogTogglesOnQuestionMark(): Unit {
    let host = keysTestHost()
    host.armStoreBridge({action => action()})
    let testHost = WidgetTestHost()
    let body = {=> buildShell(host)}
    let _ = testHost.frame(KEYS_RECT, body: body)
    let _ = pressKey(testHost, Key.Letter(UInt8(63)), UInt16(0), body)
    @Expect(host.store.ui.value().shortcutsOpen, true)
    let _ = pressKey(testHost, Key.Escape, UInt16(0), body)
    @Expect(host.store.ui.value().shortcutsOpen, false)
}

/* Ctrl+N opens quick capture; Esc closes it. */
@Test
func quickCaptureOpensOnCtrlN(): Unit {
    let host = keysTestHost()
    host.armStoreBridge({action => action()})
    let testHost = WidgetTestHost()
    let body = {=> buildShell(host)}
    let _ = testHost.frame(KEYS_RECT, body: body)
    let _ = pressKey(testHost, Key.Letter(UInt8(78)), MOD_CTRL, body)
    @Expect(host.store.ui.value().quickCaptureOpen, true)
    let _ = pressKey(testHost, Key.Escape, UInt16(0), body)
    @Expect(host.store.ui.value().quickCaptureOpen, false)
}

/*
 * Quick capture puts the caret in its input on every open, not only on the first one.
 *
 * The field used to rely on `TextField.autofocus()`, whose "already done" latch is keyed by the
 * control id and remembered for the whole session: the second open found the latch set and left
 * focus wherever it was, so typing went nowhere. The shell now requests the focus itself, once per
 * opening, from `FocusRequestView.layout` — which also needs no session-scoped latch.
 *
 * Closing restores the control that held focus when the dialog opened (or the current sidebar row
 * when nothing did), because the dialog is removed from the tree and the focus graph would
 * otherwise just clear the focus.
 */
@Test
func quickCaptureFocusesItsInputOnEveryOpen(): Unit {
    let host = keysTestHost()
    host.armStoreBridge({action => action()})
    let testHost = WidgetTestHost()
    let body = {=> buildShell(host)}
    let _ = testHost.frame(KEYS_RECT, body: body)
    let _ = pressKey(testHost, Key.Letter(UInt8(78)), MOD_CTRL, body)
    @Expect(host.store.ui.value().quickCaptureOpen, true)
    @Expect(testHost.context.focusId, "capture-input")
    let _ = pressKey(testHost, Key.Escape, UInt16(0), body)
    @Expect(host.store.ui.value().quickCaptureOpen, false)
    // Nothing was focused before the first open, so the sidebar's current row takes it back.
    @Expect(testHost.context.focusId, "shell-nav-dashboard")
    // Second open: the caret must land in the input again, and closing must return to the row that
    // held focus when this second dialog opened.
    let _ = pressKey(testHost, Key.Letter(UInt8(78)), MOD_CTRL, body)
    @Expect(testHost.context.focusId, "capture-input")
    let _ = pressKey(testHost, Key.Escape, UInt16(0), body)
    @Expect(testHost.context.focusId, "shell-nav-dashboard")
}

/*
 * Tab walks the shell's focus stops in declaration order and Shift+Tab walks them back. The shell
 * registers its controls while building, so this is also a guard that the sidebar rows and the
 * topbar controls stay in the focus ring.
 */
@Test
func tabMovesFocusForwardAndBackward(): Unit {
    let host = keysTestHost()
    host.armStoreBridge({action => action()})
    let testHost = WidgetTestHost()
    let body = {=> buildShell(host)}
    let _ = testHost.frame(KEYS_RECT, body: body)
    let start = testHost.context.focusId
    let _ = pressKey(testHost, Key.Tab, UInt16(0), body)
    let first = testHost.context.focusId
    @Expect(first.isEmpty(), false)
    @Expect(first == start, false)
    let _ = pressKey(testHost, Key.Tab, UInt16(0), body)
    let second = testHost.context.focusId
    @Expect(second == first, false)
    let _ = pressKey(testHost, Key.Tab, MOD_SHIFT, body)
    @Expect(testHost.context.focusId, first)
}

/*
 * One hotkey table must serve both keycode conventions: SDL3 on the desktop reports lowercase
 * (`'k'` = 107) and the HarmonyOS port reports uppercase (`'K'` = 75). Before `isLetterKey` folded
 * both sides, `asciiLower(75)` produced 107, so the device never matched the table and Ctrl+K did
 * nothing even though `ev# KeyDown key=Letter(75) mods=64` reached the shell.
 */
@Test
func hotkeyLettersAreCaseInsensitive(): Unit {
    @Expect(asciiLower(UInt8(75)), UInt8(107))
    @Expect(asciiLower(UInt8(107)), UInt8(107))
    @Expect(isLetterKey(UInt8(75), UInt8(75)), true)
    @Expect(isLetterKey(UInt8(107), UInt8(75)), true)
    @Expect(isLetterKey(UInt8(75), UInt8(107)), true)
    @Expect(isLetterKey(UInt8(110), UInt8(78)), true)
    @Expect(isLetterKey(UInt8(90), UInt8(90)), true)
    @Expect(isLetterKey(UInt8(122), UInt8(90)), true)
    // Different letters stay different.
    @Expect(isLetterKey(UInt8(75), UInt8(78)), false)
    @Expect(isLetterKey(UInt8(107), UInt8(90)), false)
    // Non-letters are untouched (the `?` shortcut rides on this).
    @Expect(asciiLower(UInt8(63)), UInt8(63))
    @Expect(isLetterKey(UInt8(63), UInt8(63)), true)
}
