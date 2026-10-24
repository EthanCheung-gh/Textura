package textura.shell

import std.env.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*

/*
 * 全屏 / 窗口缩放自适应（docs/DEVICE-NOTES.md §18）。
 *
 * 根因回归：`ShellHost.viewportWidth/Height` 过去是构造时捕获的 `let`，`ViewContext` 每帧都用
 * 那对旧值，窗口放大后页面仍按启动尺寸排版。现在 `ViewportSyncView` 在 layout 里把
 * `UiContext.viewportWidth/Height` 写回 host（并在变化时请求下一帧），`ViewContext` 每帧读取
 * 新值。本测试直接改变宿主窗口尺寸，断言 host 的视口跟随（而不是停在 1440×900）。
 */

private let VIEWPORT_HOME: String = "/tmp/textura-shell-viewport-home"
private let VIEWPORT_ANCHOR: Int64 = 1773626400000

private func viewportHost(): ShellHost {
    try {
        setVariable("HOME", VIEWPORT_HOME)
    } catch (_: Exception) {
        ()
    }
    let clock = FixedClock(VIEWPORT_ANCHOR)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    store.setRoute(routeId(Route.Calendar))
    let runtime = ShellRuntime(ShellPreferences.load(), store)
    let noLoadError: ?String = None
    let host = ShellHost(store, runtime, "2026-01-01", false, noLoadError, 1440, 900)
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
