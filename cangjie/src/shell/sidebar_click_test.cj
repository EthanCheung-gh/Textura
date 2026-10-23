package textura.shell

import std.env.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*

/*
 * The sidebar click chain, tested where it is decidable: the shell tree, a real MouseDown(Left) and
 * the store.
 *
 * Why this exists: on the HarmonyOS device a primary press on a nav row was seen by SDL (its own
 * `MOUSE EVENT` hilog lines show action=1 button=0x1 at sidebar coordinates) and the route still
 * never changed. That leaves two candidates — the shell's handler or everything above it — and this
 * test removes the first: with a properly decoded left button the row navigates. If this test passes
 * on a host and the device still does not navigate, the break is above CUI (SDL event delivery or
 * button decoding), not in `SidebarView`.
 *
 * Coordinates come from the sidebar metrics, not from pixels of a screenshot: with the shell at
 * 1440x900 the nav column starts at x=16 and the rows start at y=72 (56px brand + 16px padding),
 * each 34.25px high with a 2px gap, so (60, 128) is the centre of the second row.
 */

private let CLICK_X: Float32 = 60.0
private let CLICK_Y: Float32 = 128.0
private let SHELL_RECT: Rect = Rect(0.0, 0.0, 1440.0, 900.0)
/* Frozen clock, same anchor the parity CLI uses, so today-dependent views are deterministic. */
private let CLICK_TEST_ANCHOR: Int64 = 1773626400000
/* Preference reads are redirected here so a developer's own ui-prefs.json cannot leak into a test. */
private let TEMP_HOME_ROOT: String = "/tmp/textura-shell-click-test-home"

/* A store over the demo workspace, with no file touched and no preference written. */
private func clickTestHost(): ShellHost {
    try {
        setVariable("HOME", TEMP_HOME_ROOT)
    } catch (_: Exception) {
        ()
    }
    let clock = FixedClock(CLICK_TEST_ANCHOR)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    store.setRoute(routeId(Route.Dashboard))
    let runtime = ShellRuntime(ShellPreferences.load(), store)
    let noLoadError: ?String = None
    // interactive: false — a test must not persist anything, exactly like the parity snapshot run.
    ShellHost(store, runtime, "2026-01-01", false, noLoadError, 1440, 900)
}

/** A primary press on the second nav row switches the route to that row's view. */
@Test
func sidebarPrimaryPressNavigates(): Unit {
    let host = clickTestHost()
    let store = host.store
    @Expect(store.ui.value().route, "dashboard")
    let testHost = WidgetTestHost()
    let _ = testHost.frame(SHELL_RECT, body: {=> buildShell(host)})
    let hovered = testHost.frame(SHELL_RECT, events: [UiEvent.MouseMove(CLICK_X, CLICK_Y)],
        body: {=> buildShell(host)})
    // The row under the pointer is the one this press must activate; failing here means the test
    // coordinates no longer match the sidebar metrics.
    @Expect(testHost.context.hoverId, "shell-nav-${routeId(ROUTES[1])}")
    let _ = hovered
    let _ = testHost.frame(SHELL_RECT,
        events: [
            UiEvent.MouseDown(MouseButton.Left, CLICK_X, CLICK_Y),
            UiEvent.MouseUp(MouseButton.Left, CLICK_X, CLICK_Y)
        ], body: {=> buildShell(host)})
    @Expect(store.ui.value().route, routeId(ROUTES[1]))
    @Expect(store.ui.value().paletteOpen, false)
}

/** A press outside every nav row must not navigate (guards against a whole-column hit). */
@Test
func sidebarPressOutsideRowsDoesNotNavigate(): Unit {
    let host = clickTestHost()
    let testHost = WidgetTestHost()
    let _ = testHost.frame(SHELL_RECT, body: {=> buildShell(host)})
    // y=60 is the brand block (0..56 is the topbar row, 56..72 the scroll padding).
    let _ = testHost.frame(SHELL_RECT,
        events: [UiEvent.MouseDown(MouseButton.Left, CLICK_X, 62.0)], body: {=> buildShell(host)})
    @Expect(host.store.ui.value().route, "dashboard")
}
