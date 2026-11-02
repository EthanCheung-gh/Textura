package textura.shell

import std.env.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*
import textura.ui.*

/*
 * The store → CUI bridge and the primary-button alias, tested where they are decidable: a headless
 * frame, a real `AppStore` write and the shell tree.
 *
 * Why these tests exist (docs/DEVICE-NOTES.md §5): on the device a tap on a sidebar row reached
 * `SidebarView.handle`, moved focus to `shell-nav-okr` and called `store.setRoute("okr")` — and the
 * window kept rendering the dashboard, with `$HOME/.textura/ui-prefs.json` still saying `dashboard`.
 * `buildShell` was never re-executed, because nothing in CUI's incremental retained graph had marked
 * it dirty: `AppStore.ui` is a `core.data` cell, not a CUI `State`. `ShellHost.revision` fixes that,
 * and these tests pin both halves — the store write must invalidate the shell, and a press whose
 * button the backend could not name must navigate like a left click.
 */

private let BRIDGE_X: Float32 = 60.0
private let BRIDGE_Y: Float32 = 128.0
private let BRIDGE_RECT: Rect = Rect(0.0, 0.0, 1440.0, 900.0)
private let BRIDGE_ANCHOR: Int64 = 1773626400000
private let BRIDGE_HOME: String = "/tmp/textura-shell-bridge-test-home"

/* Counts body executions. A mutable local cannot be captured by a lambda (Cangjie rejects that), and
 * a `State` would itself invalidate the scope it is meant to observe. */
private class BuildCounter {
    var count: Int64 = 0

    func note(): Unit {
        count += 1
    }
}

private func bridgeTestHost(): ShellHost {
    try {
        setVariable("HOME", BRIDGE_HOME)
    } catch (_: Exception) {
        ()
    }
    let clock = FixedClock(BRIDGE_ANCHOR)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    store.setRoute(routeId(Route.Dashboard))
    let runtime = ShellRuntime(ShellPreferences.load(), store)
    let noLoadError: ?String = None
    ShellHost(store, runtime, "2026-01-01", false, noLoadError, 1440, 900)
}

/*
 * A store write invalidates the shell: `buildShell` must run again on the next frame.
 *
 * The counter is the observable. CUI only re-executes a declarative scope when a `State` read inside
 * it changed, so an unchanged counter after `setRoute` is exactly the device bug: a stale tree, no
 * matter how correct the store is.
 */
@Test
func storeWriteInvalidatesTheShellBody(): Unit {
    let host = bridgeTestHost()
    host.armStoreBridge({action => action()})
    let testHost = WidgetTestHost()
    let builds = BuildCounter()
    let body = {=>
        builds.note()
        buildShell(host)
    }
    let _ = testHost.frame(BRIDGE_RECT, body: body)
    @Expect(builds.count, 1)
    // An input frame that changes nothing in the store must not rebuild the shell.
    let _ = testHost.frame(BRIDGE_RECT, events: [UiEvent.MouseMove(2.0, 2.0)], body: body)
    @Expect(builds.count, 1)
    host.store.setRoute(routeId(Route.Calendar))
    let _ = testHost.frame(BRIDGE_RECT, body: body)
    @Expect(builds.count, 2)
    @Expect(routeId(host.route()), routeId(Route.Calendar))
}

/*
 * The route the rebuilt shell renders follows the store: the shell's own derived route, its theme and
 * the prefs it persists are all read from the same cell the bridge tracks.
 */
@Test
func storeWriteRebuildsWithTheNewRoute(): Unit {
    let host = bridgeTestHost()
    host.armStoreBridge({action => action()})
    let testHost = WidgetTestHost()
    let body = {=> buildShell(host)}
    let _ = testHost.frame(BRIDGE_RECT, body: body)
    @Expect(routeId(host.route()), routeId(Route.Dashboard))
    host.store.setRoute(routeId(Route.Okr))
    let frame = testHost.frame(BRIDGE_RECT, body: body)
    @Expect(routeId(host.route()), routeId(Route.Okr))
    // A rebuilt shell repaints text (the topbar title and the view's own labels); the stale tree did
    // not. Guards against "the body ran but the tree was reused unchanged".
    @Expect(frame.metrics.textDraws > UInt64(0), true)
}

/* A UI preference write (not just the workspace) invalidates too — the theme toggle depends on it. */
@Test
func uiPreferenceWriteInvalidatesTheShell(): Unit {
    let host = bridgeTestHost()
    host.armStoreBridge({action => action()})
    let testHost = WidgetTestHost()
    let builds = BuildCounter()
    let body = {=>
        builds.note()
        buildShell(host)
    }
    let _ = testHost.frame(BRIDGE_RECT, body: body)
    @Expect(builds.count, 1)
    host.store.setTheme("dark")
    let _ = testHost.frame(BRIDGE_RECT, body: body)
    @Expect(builds.count, 2)
    @Expect(host.themeName(), "dark")
}

/* A notice is painted by the shell layer, so adding one must invalidate the shell as well. */
@Test
func noticeWriteInvalidatesTheShell(): Unit {
    let host = bridgeTestHost()
    host.armStoreBridge({action => action()})
    let testHost = WidgetTestHost()
    let builds = BuildCounter()
    let body = {=>
        builds.note()
        buildShell(host)
    }
    let _ = testHost.frame(BRIDGE_RECT, body: body)
    @Expect(builds.count, 1)
    host.store.notify("bridge test", tone: NoticeTone.Info)
    let _ = testHost.frame(BRIDGE_RECT, body: body)
    @Expect(builds.count, 2)
}

/*
 * A press the backend could not name still navigates: `RawCode(1)` is the real left button number, and
 * `RawCode(0)` is SDL's "unknown" value that a touch-driven pointer emulation can deliver. Both must
 * reach the same handler as `MouseButton.Left`, on the sidebar and on the `Ui` button kit.
 */
@Test
func aliasedPrimaryPressNavigates(): Unit {
    for (button in [MouseButton.RawCode(1), MouseButton.RawCode(0)]) {
        let host = bridgeTestHost()
        host.armStoreBridge({action => action()})
        let testHost = WidgetTestHost()
        let body = {=> buildShell(host)}
        let _ = testHost.frame(BRIDGE_RECT, body: body)
        let _ = testHost.frame(BRIDGE_RECT, events: [
            UiEvent.MouseDown(button, BRIDGE_X, BRIDGE_Y),
            UiEvent.MouseUp(button, BRIDGE_X, BRIDGE_Y)
        ], body: body)
        @Expect(host.store.ui.value().route, routeId(ROUTES[1]))
    }
}

/* Middle/right presses must not navigate: the alias accepts the primary button only. */
@Test
func nonPrimaryPressDoesNotNavigate(): Unit {
    let host = bridgeTestHost()
    host.armStoreBridge({action => action()})
    let testHost = WidgetTestHost()
    let body = {=> buildShell(host)}
    let _ = testHost.frame(BRIDGE_RECT, body: body)
    for (button in [MouseButton.Right, MouseButton.Middle, MouseButton.RawCode(3)]) {
        let _ = testHost.frame(BRIDGE_RECT, events: [
            UiEvent.MouseDown(button, BRIDGE_X, BRIDGE_Y),
            UiEvent.MouseUp(button, BRIDGE_X, BRIDGE_Y)
        ], body: body)
    }
    @Expect(host.store.ui.value().route, "dashboard")
}

/* `isPrimaryPointerButton` is the single decision point; keep its cases exact. */
@Test
func primaryPointerButtonMapping(): Unit {
    @Expect(isPrimaryPointerButton(MouseButton.Left), true)
    @Expect(isPrimaryPointerButton(MouseButton.RawCode(0)), true)
    @Expect(isPrimaryPointerButton(MouseButton.RawCode(1)), true)
    @Expect(isPrimaryPointerButton(MouseButton.RawCode(2)), false)
    @Expect(isPrimaryPointerButton(MouseButton.RawCode(3)), false)
    @Expect(isPrimaryPointerButton(MouseButton.Middle), false)
    @Expect(isPrimaryPointerButton(MouseButton.Right), false)
}

/* ------------------------------------------------------------------ preference file round-trip */

/*
 * `ShellPreferences` must round-trip through an explicit path: that is what the HarmonyOS host uses,
 * because a HAP process has no usable `$HOME` (docs/DEVICE-NOTES.md §6). Before this, the device build
 * resolved the path from `$HOME` and every write silently failed, so the app always reopened on the
 * dashboard and nothing anywhere said why.
 */
@Test
func preferencesRoundTripThroughExplicitPath(): Unit {
    // Fixed path, and no assertion about the state it starts in: the round trip below is what matters
    // and it must stay true on a second run of the suite.
    let path = "/tmp/textura-prefs-test/.textura/ui-prefs.json"
    let first = ShellPreferences.load(path)
    @Expect(first.path, path)
    first.route = "calendar"
    first.theme = "dark"
    first.persist()
    @Expect(first.lastWriteOk, true)
    @Expect(first.lastWriteError, "")
    let second = ShellPreferences.load(path)
    @Expect(second.route, "calendar")
    @Expect(second.theme, "dark")
}

/* A path that cannot be created reports the failure instead of pretending the write happened. */
@Test
func preferencesReportWriteFailure(): Unit {
    let prefs = ShellPreferences.load("/proc/textura-impossible/ui-prefs.json")
    prefs.route = "okr"
    prefs.persist()
    @Expect(prefs.lastWriteOk, false)
    @Expect(prefs.lastWriteError.isEmpty(), false)
}
