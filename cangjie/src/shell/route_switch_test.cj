package textura.shell

import std.env.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*

/*
 * Switching routes by clicking the sidebar, in the order an operator actually does it.
 *
 * Why this exists: on the HarmonyOS device the app froze after a specific sidebar click — the store
 * took the new route, the window kept the previous frame and every later click was ignored. The
 * cause was a frame that threw during layout/draw and was swallowed by CUI's hosted failure
 * collector: input is dispatched *after* build/layout, so a frame that always throws is
 * indistinguishable from a dead window. These tests pin the part that is decidable on a host —
 * every route can be entered, in any order, and the shell keeps rendering it.
 */

private let NAV_X: Float32 = 60.0
private let SWITCH_RECT: Rect = Rect(0.0, 0.0, 1440.0, 900.0)
private let SWITCH_ANCHOR: Int64 = 1773626400000
private let SWITCH_HOME: String = "/tmp/textura-shell-route-switch-home"
/* First nav row centre (brand 56 + padding 16 + half a 34.25 row) and the row pitch (34.25 + 2 gap). */
private let NAV_ROW_TOP: Float32 = 72.0
private let NAV_ROW_PITCH: Float32 = 36.25

/* The sidebar order (routes.cj): 今日 → 日历 → OKR → GTD → 甘特 → SOP → 设置. */
private let ROUTE_ORDER: Array<Route> = ROUTES

private func routeSwitchHost(): ShellHost {
    try {
        setVariable("HOME", SWITCH_HOME)
    } catch (_: Exception) {
        ()
    }
    let clock = FixedClock(SWITCH_ANCHOR)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    store.setRoute(routeId(ROUTE_ORDER[0]))
    let runtime = ShellRuntime(ShellPreferences.load(), store)
    let noLoadError: ?String = None
    ShellHost(store, runtime, "2026-01-01", false, noLoadError, 1440, 900)
}

private func navRowCenter(index: Int64): Float32 {
    NAV_ROW_TOP + NAV_ROW_PITCH * Float32(index) + NAV_ROW_PITCH / 2.0 - 2.0
}

private func clickRow(testHost: WidgetTestHost, index: Int64, body: () -> Unit): TestFrameResult {
    let y = navRowCenter(index)
    return testHost.frame(SWITCH_RECT,
        events: [
            UiEvent.MouseMove(NAV_X, y),
            UiEvent.MouseDown(MouseButton.Left, NAV_X, y),
            UiEvent.MouseUp(MouseButton.Left, NAV_X, y)
        ], body: body)
}

/*
 * Every nav row navigates when pressed, one after another, in one session — no route transition may
 * leave the shell unable to render the next one.
 */
@Test
func everyRouteCanBeEnteredInSequence(): Unit {
    let host = routeSwitchHost()
    host.armStoreBridge({action => action()})
    let testHost = WidgetTestHost()
    let body = {=> buildShell(host)}
    let _ = testHost.frame(SWITCH_RECT, body: body)
    var index = 0
    while (index < ROUTE_ORDER.size) {
        let frame = clickRow(testHost, index, body)
        @Expect(host.store.ui.value().route, routeId(ROUTE_ORDER[index]))
        // A route the shell renders repaints text; a frozen shell draws nothing.
        @Expect(frame.metrics.textDraws > UInt64(0), true)
        index += 1
    }
}

/* The operator's first report: several rows in a row, then the same rows again. */
@Test
func routeSwitchSurvivesRepeatedVisits(): Unit {
    let host = routeSwitchHost()
    host.armStoreBridge({action => action()})
    let testHost = WidgetTestHost()
    let body = {=> buildShell(host)}
    let _ = testHost.frame(SWITCH_RECT, body: body)
    for (index in [Int64(0), 1, 4, 6, 2, 5, 3, 4, 0, 3, 1, 6]) {
        let _ = clickRow(testHost, index, body)
        @Expect(host.store.ui.value().route, routeId(ROUTE_ORDER[index]))
    }
}

/* A closed overlay must not stay on the overlay stack: it would swallow every later press. */
@Test
func closedOverlaysLeaveNoLayerBehind(): Unit {
    let host = routeSwitchHost()
    host.armStoreBridge({action => action()})
    let testHost = WidgetTestHost()
    let body = {=> buildShell(host)}
    let frame = testHost.frame(SWITCH_RECT, body: body)
    @Expect(frame.metrics.overlayCount, 0)
    @Expect(testHost.context.overlayCount(), 0)
    host.store.setUi({state => state.paletteOpen = true})
    let open = testHost.frame(SWITCH_RECT, body: body)
    @Expect(open.metrics.overlayCount, 1)
    host.closePalette()
    let closed = testHost.frame(SWITCH_RECT, body: body)
    @Expect(closed.metrics.overlayCount, 0)
    @Expect(testHost.context.overlayCount(), 0)
    // With no layer open, a sidebar press must reach the sidebar again.
    let _ = clickRow(testHost, 1, body)
    @Expect(host.store.ui.value().route, routeId(ROUTE_ORDER[1]))
}
