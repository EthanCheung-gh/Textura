package textura.shell

import std.env.*
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
