package textura.shell

import std.env.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*
import textura.ui.*

/*
 * 1024×640（应用允许的最小窗口）下七条路由都不得横向溢出。
 *
 * `ViewContext.width/height` 现在每帧来自真实窗口（见 viewport_test.cj），页面按它推导
 * 高度/列宽；本测试把整壳层放到 1024×640，逐路由收集语义树矩形，断言所有声明式控件都落在
 * 窗口内（画布类内容由 `tools/parity/out-1024` 的截图复核）。
 */

private let NARROW_RECT: Rect = Rect(0.0, 0.0, 1024.0, 640.0)
private let NARROW_HOME: String = "/tmp/textura-shell-narrow-home"
private let NARROW_ANCHOR: Int64 = 1773626400000
/** 1px 的边框/抗锯齿容差。 */
private let NARROW_TOLERANCE: Float32 = 1.5

@Test
func everyRouteStaysInsideTheMinimumWindow(): Unit {
    try {
        setVariable("HOME", NARROW_HOME)
    } catch (_: Exception) {
        ()
    }
    let routes = [
        Route.Dashboard,
        Route.Calendar,
        Route.Okr,
        Route.Gtd,
        Route.Gantt,
        Route.Sop,
        Route.Settings
    ]
    for (route in routes) {
        let clock = FixedClock(NARROW_ANCHOR)
        let store = AppStore(clock: clock)
        store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
        store.setRoute(routeId(route))
        let runtime = ShellRuntime(ShellPreferences.load(), store)
        let noLoadError: ?String = None
        let host = ShellHost(store, runtime, "2026-01-01", false, noLoadError, 1024, 640)
        host.armStoreBridge({action => action()})
        let testHost = WidgetTestHost()
        let _ = testHost.frame(NARROW_RECT, body: {=> buildShell(host)})
        // The host adopted the narrow viewport before the pages laid out.
        @Expect(host.viewportWidth, Int64(1024))
        for (node in testHost.context.semanticsSnapshot()) {
            let rect = node.bounds
            if (rect.w <= 0.0 || rect.h <= 0.0) {
                continue
            }
            if (rect.x < -NARROW_TOLERANCE || rect.right() > Float32(NARROW_RECT.w) + NARROW_TOLERANCE) {
                @Expect("${routeId(route)} node '${node.properties.label}' at ${rect.x}..${rect.right()}", "inside")
            }
        }
    }
}

/** The GTD two-column grid folds to one column below the breakpoint (Practically 1024). */
@Test
func gtdFoldsToASingleColumnAtTheMinimumWidth(): Unit {
    let clock = FixedClock(NARROW_ANCHOR)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    let ctx = ViewContext(store, "light", "2026-01-01", 1024, 640, {_ => ()})
    let tokens = tokensOf(texturaLight())
    // Content width = 1024 - 240 sidebar - 2 × 24 padding.
    @Expect(Float32(ctx.width) - tokens.metrics.sidebarWidth - 48.0, Float32(736.0))
    @Expect(736.0 < 900.0, true)
}

/*
 * Shrinking back is the same path as growing: the viewport epoch must bump and the tree must be
 * described again for 1024×640 (a maximised tree that is only re-laid out would keep 2880-wide,
 * 1620-tall pages and scroll sideways). `viewport_test.cj` covers the epoch itself; this keeps the
 * responsive-layout guarantee for all seven routes on the way down (docs/DEVICE-NOTES.md §18.4).
 */
@Test
func shrinkingAfterAMaximisedWindowKeepsEveryRouteInside(): Unit {
    let routes = [
        Route.Dashboard,
        Route.Calendar,
        Route.Okr,
        Route.Gtd,
        Route.Gantt,
        Route.Sop,
        Route.Settings
    ]
    for (route in routes) {
        try {
            setVariable("HOME", NARROW_HOME)
        } catch (_: Exception) {
            ()
        }
        let clock = FixedClock(NARROW_ANCHOR)
        let store = AppStore(clock: clock)
        store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
        store.setRoute(routeId(route))
        let runtime = ShellRuntime(ShellPreferences.load(), store)
        let noLoadError: ?String = None
        let host = ShellHost(store, runtime, "2026-01-01", false, noLoadError, 2880, 1620)
        host.armStoreBridge({action => action()})
        let testHost = WidgetTestHost()
        let body = {=> buildShell(host)}
        let _ = testHost.frame(Rect(0.0, 0.0, 2880.0, 1620.0), body: body)
        let _ = testHost.frame(NARROW_RECT, events: [UiEvent.WindowResized(1024, 640)], body: body)
        @Expect(host.viewportWidth, Int64(1024))
        @Expect(host.viewportHeight, Int64(640))
        @Expect(host.builtViewportWidth, Int64(1024))
        @Expect(host.builtViewportHeight, Int64(640))
        for (node in testHost.context.semanticsSnapshot()) {
            let rect = node.bounds
            if (rect.w <= 0.0 || rect.h <= 0.0) {
                continue
            }
            if (rect.x < -NARROW_TOLERANCE || rect.right() > Float32(NARROW_RECT.w) + NARROW_TOLERANCE) {
                @Fail("${routeId(route)} node '${node.properties.label}' at ${rect.x}..${rect.right()} after shrinking")
            }
        }
    }
}
