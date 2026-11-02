package textura.shell

import std.env.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*

/*
 * 全屏 / 窗口缩放自适应（docs/DEVICE-NOTES.md §18 与 §19）。
 *
 * 两个根因，一前一后：
 * 1. §18 —— `ShellHost.viewportWidth/Height` 过去是构造时捕获的 `let`，`ViewContext` 每帧都用那对
 *    旧值，窗口放大后页面仍按启动尺寸排版。现在 `ViewportSyncView` 在 layout 里把
 *    `UiContext.viewportWidth/Height` 写回 host，`ViewContext` 每帧读取新值。
 * 2. §19 —— 只更新字段不会让 CUI 重跑 build：`ViewContext` 是 build 期构造的，树会一直带着旧值。
 *    现在 `syncViewport` 变化时 bump `viewportEpoch`（CUI `State`），`buildShell` 根读它，于是同一帧
 *    内树被**重新描述**；`buildCount`/`builtViewport*` 就是「真的重建了」的证据。
 */

private let VIEWPORT_HOME: String = "/tmp/textura-shell-viewport-home"
private let VIEWPORT_ANCHOR: Int64 = 1773626400000
/** 1px 的边框/抗锯齿容差。 */
private let VIEWPORT_TOLERANCE: Float32 = 1.5

private func viewportHost(): ShellHost {
    routeHost(Route.Calendar, 1440, 900)
}

/** One shell host per route, so the maximised-window test can walk all seven. */
private func routeHost(route: Route, width: Int64, height: Int64): ShellHost {
    try {
        setVariable("HOME", VIEWPORT_HOME)
    } catch (_: Exception) {
        ()
    }
    let clock = FixedClock(VIEWPORT_ANCHOR)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    store.setRoute(routeId(route))
    let runtime = ShellRuntime(ShellPreferences.load(), store)
    let noLoadError: ?String = None
    let host = ShellHost(store, runtime, "2026-01-01", false, noLoadError, width, height)
    host.armStoreBridge({action => action()})
    host
}

@Test
func windowResizeUpdatesTheShellViewport(): Unit {
    let host = viewportHost()
    let testHost = WidgetTestHost()
    let body = {=> buildShell(host)}
    let _ = testHost.frame(Rect(0.0, 0.0, 1440.0, 900.0), body: body)
    @Expect(host.viewportWidth, Int64(1440))
    @Expect(host.viewportHeight, Int64(900))
    // Grow to a full-screen-like surface: the next frame adopts the new size.
    let _ = testHost.frame(Rect(0.0, 0.0, 1920.0, 1200.0), body: body)
    @Expect(host.viewportWidth, Int64(1920))
    @Expect(host.viewportHeight, Int64(1200))
    // And shrink below the design baseline: the shell must not keep the larger size.
    let _ = testHost.frame(Rect(0.0, 0.0, 1024.0, 640.0), body: body)
    @Expect(host.viewportWidth, Int64(1024))
    @Expect(host.viewportHeight, Int64(640))
}

/*
 * The regression that made the previous round's fix look ineffective on device: `viewportWidth/
 * Height` followed the window, but nothing invalidated the *build* scope, so the committed tree kept
 * the `ViewContext` it was described with and every page stayed at its launch height.
 *
 * `builtViewportHeight` is written only while the shell is being described, so it is proof that a
 * build really ran for the new size. Retained, incremental frames are what the device does; a
 * full-rebuild-every-frame harness would hide the bug.
 */
@Test
func windowResizeRebuildsTheViewsForTheNewHeight(): Unit {
    let host = viewportHost()
    let testHost = WidgetTestHost()
    let body = {=> buildShell(host)}
    let _ = testHost.frame(Rect(0.0, 0.0, 1440.0, 900.0), body: body)
    @Expect(host.builtViewportHeight, Int64(900))
    let _ = testHost.frame(Rect(0.0, 0.0, 1920.0, 1200.0), body: body)
    @Expect(host.builtViewportHeight, Int64(1200))
    let _ = testHost.frame(Rect(0.0, 0.0, 1920.0, 1200.0), body: body)
    @Expect(host.builtViewportHeight, Int64(1200))
    let _ = testHost.frame(Rect(0.0, 0.0, 1024.0, 640.0), body: body)
    @Expect(host.builtViewportHeight, Int64(640))
}

@Test
func syncViewportReportsOnlyRealChanges(): Unit {
    let host = viewportHost()
    @Expect(host.syncViewport(1440.0, 900.0), false)
    @Expect(host.syncViewport(1440.0, 900.0), false)
    @Expect(host.syncViewport(1441.0, 900.0), true)
    @Expect(host.viewportWidth, Int64(1441))
    // Degenerate driver reports never collapse the layout to zero.
    @Expect(host.syncViewport(0.0, -3.0), true)
    @Expect(host.viewportWidth, Int64(1))
    @Expect(host.viewportHeight, Int64(1))
}

/*
 * The device path: SDL delivers `UiEvent.WindowResized(w, h)` when the user maximises the window, CUI
 * turns it into a new `UiContext.viewportWidth/Height`, and the shell must *describe itself again* for
 * that size inside the same frame (CUI re-runs the dirty build scope once after layout wrote the
 * epoch). `buildCount` is the number that proves it: a retained tree that is merely laid out again
 * keeps a build count that does not move.
 */
@Test
func windowResizedEventRebuildsTheShellForTheNewSize(): Unit {
    let host = viewportHost()
    let testHost = WidgetTestHost()
    let body = {=> buildShell(host)}
    let _ = testHost.frame(Rect(0.0, 0.0, 1440.0, 900.0), body: body)
    @Expect(host.builtViewportWidth, Int64(1440))
    @Expect(host.builtViewportHeight, Int64(900))
    let launchBuilds = host.buildCount
    @Expect(launchBuilds >= Int64(1), true)
    @Expect(host.viewportEpochValue(), Int64(0))
    // Maximise: the event carries the new size, the driver's viewport follows it.
    let _ = testHost.frame(Rect(0.0, 0.0, 2880.0, 1620.0), events: [UiEvent.WindowResized(2880, 1620)], body: body)
    @Expect(host.viewportWidth, Int64(2880))
    @Expect(host.viewportHeight, Int64(1620))
    @Expect(host.viewportEpochValue(), Int64(1))
    @Expect(host.builtViewportWidth, Int64(2880))
    @Expect(host.builtViewportHeight, Int64(1620))
    @Expect(host.buildCount > launchBuilds, true)
    // An idle frame at the same size must not rebuild: the epoch is the dependency, not the frame.
    let settledBuilds = host.buildCount
    let _ = testHost.frame(Rect(0.0, 0.0, 2880.0, 1620.0), body: body)
    @Expect(host.buildCount, settledBuilds)
    @Expect(host.builtViewportHeight, Int64(1620))
    // Restoring the window walks the same path in reverse.
    let _ = testHost.frame(Rect(0.0, 0.0, 1440.0, 900.0), events: [UiEvent.WindowResized(1440, 900)], body: body)
    @Expect(host.viewportEpochValue(), Int64(2))
    @Expect(host.builtViewportWidth, Int64(1440))
    @Expect(host.builtViewportHeight, Int64(900))
    @Expect(host.buildCount > settledBuilds, true)
}

/*
 * Every route must actually use the new window size, not just report it.
 *
 * The page geometry itself is painted by custom widgets (a calendar grid, a gantt body, a canvas), so
 * the shell-level proof has two parts: `builtViewportWidth/Height` are the exact numbers the single
 * `ViewContext` construction site hands to all seven views, and the semantics rectangles must reach
 * past the launch window — 1930×1020 is the measured device window (docs/DEVICE-NOTES.md §2), i.e. the
 * envelope a stale, never-rebuilt tree is stuck in. The top bar's search field sits at the right edge,
 * so `right > 1930` is the "the tree was described for the wider window" check that every route can
 * make without reaching into a view's private helpers.
 */
@Test
func everyRouteUsesTheMaximisedWindow(): Unit {
    let routes = [Route.Dashboard, Route.Calendar, Route.Okr, Route.Gtd, Route.Gantt, Route.Sop, Route.Settings]
    for (route in routes) {
        let host = routeHost(route, 1440, 900)
        let testHost = WidgetTestHost()
        let body = {=> buildShell(host)}
        let _ = testHost.frame(Rect(0.0, 0.0, 1440.0, 900.0), body: body)
        let _ = testHost.frame(Rect(0.0, 0.0, 2880.0, 1620.0),
            events: [UiEvent.WindowResized(2880, 1620)], body: body)
        @Expect(host.builtViewportWidth, Int64(2880))
        @Expect(host.builtViewportHeight, Int64(1620))
        @Expect(host.viewportEpochValue(), Int64(1))
        var maxRight: Float32 = 0.0
        for (node in testHost.context.semanticsSnapshot()) {
            let rect = node.bounds
            if (rect.w <= 0.0 || rect.h <= 0.0) {
                continue
            }
            if (rect.x < -VIEWPORT_TOLERANCE || rect.right() > 2880.0 + VIEWPORT_TOLERANCE ||
                rect.y < -VIEWPORT_TOLERANCE || rect.bottom() > 1620.0 + VIEWPORT_TOLERANCE) {
                @Fail("${routeId(route)} node '${node.properties.label}' at" +
                    " ${rect.x},${rect.y}..${rect.right()},${rect.bottom()} escaped the window")
            }
            if (rect.right() > maxRight) {
                maxRight = rect.right()
            }
        }
        if (maxRight <= 1930.0) {
            @Fail("${routeId(route)} stopped at right=${maxRight}: the tree kept the launch width")
        }
    }
}
