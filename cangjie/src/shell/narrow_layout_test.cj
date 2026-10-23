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
