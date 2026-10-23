package textura.shell
import std.env.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*
/*
 * 甘特行的悬停/点击反馈不能触发 shell 重建（真机证据见 docs/DEVICE-NOTES.md §13）。
 *
 * `GanttBody.draw` 每帧直接读 `state.hoverRow` / `state.gesture` / `state.pressedRow`，而输入帧
 * 本身一定会重绘（宿主 `mustRender`），所以这些临时状态只值一次重绘。曾经它们在变化时递增
 * `rev`，而 `rev` 是在 `gantt.render` 的作用域里被读取的 —— 也就是整个 shell body 作用域：
 * 一次跨行 hover 就重算整页（真机 30–55ms 级），表现为「悬浮变色慢半拍」。
 */

private let GH_RECT: Rect = Rect(0.0, 0.0, 1440.0, 900.0)
private let GH_ANCHOR: Int64 = 1773626400000
private let GH_HOME: String = "/tmp/textura-shell-gantt-hover-home"
/* Shell content starts at 56 + 24; gantt page header 57, two 12px gaps and the 48px toolbar. */
private let GH_TIMELINE_X: Float32 = 760.0
private let GH_ROW_0_Y: Float32 = 270.0
private let GH_ROW_4_Y: Float32 = 414.0

private class ShellBuilds {
    var count: Int64 = 0

    func note(): Unit {
        count += 1
    }
}

@Test
func ganttHoverRepaintsWithoutRebuildingTheShell(): Unit {
    try {
        setVariable("HOME", GH_HOME)
    } catch (_: Exception) {
        ()
    }
    let clock = FixedClock(GH_ANCHOR)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    store.setRoute(routeId(Route.Gantt))
    let runtime = ShellRuntime(ShellPreferences.load(), store)
    let noLoadError: ?String = None
    let host = ShellHost(store, runtime, "2026-01-01", false, noLoadError, 1440, 900)
    host.armStoreBridge({action => action()})
    let testHost = WidgetTestHost()
    let builds = ShellBuilds()
    let body = {=>
        builds.note()
        buildShell(host)
    }
    let _ = testHost.frame(GH_RECT, body: body)
    let afterFirst = builds.count
    // Two moves on different rows: each changes the hovered row. A rebuild here is the bug.
    let _ = testHost.frame(GH_RECT, events: [UiEvent.MouseMove(GH_TIMELINE_X, GH_ROW_0_Y)], body: body)
    @Expect(builds.count, afterFirst)
    let _ = testHost.frame(GH_RECT, events: [UiEvent.MouseMove(GH_TIMELINE_X, GH_ROW_4_Y)], body: body)
    @Expect(builds.count, afterFirst)
}
