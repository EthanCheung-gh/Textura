package textura.shell

import std.env.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*

/*
 * 窗口尺寸 / 屏幕密度推送的门禁（docs/DEVICE-NOTES.md §24）。
 *
 * 这条链路在主机上没有 SDL 窗口可供观察，所以把可判定的部分提到 `DisplayPush` / `DisplayPushLog`：
 * 像素→逻辑单位的换算、以及「只在真的变化时采纳」这条去抖规则。真机侧的 `onAreaChange` 与
 * `SDL_SetWindowSize` 只能靠探针（§24.5）证明。
 */

/** 2880×1620 外接屏：物理 2560×1440、渲染 2880×1620，densityPixels = 1.125。 */
private let EXTERNAL_DENSITY: Float32 = 1.125
/** 1x 屏（主机、1440×900 基线）。 */
private let BASELINE_DENSITY: Float32 = 1.0

@Test
func densityOneKeepsTheViewportInPixels(): Unit {
    // 1x 屏必须逐像素不变，否则桌面/基线截图会整体位移（parity 14/14 的护栏）。
    @Expect(DisplayPush.logical(1440, BASELINE_DENSITY), Int64(1440))
    @Expect(DisplayPush.logical(900, BASELINE_DENSITY), Int64(900))
    @Expect(DisplayPush.logical(2880, BASELINE_DENSITY), Int64(2880))
}

@Test
func densityShrinksTheLogicalViewportProportionally(): Unit {
    // 2024 宽的外接屏放大 1.125 后渲染成 2880：逻辑单位仍是 2560×1440，布局不留空白也不溢出。
    @Expect(DisplayPush.logical(2880, EXTERNAL_DENSITY), Int64(2560))
    @Expect(DisplayPush.logical(1620, EXTERNAL_DENSITY), Int64(1440))
    // 1.5x / 2x 屏同样按比例收窄，取整落在最近的单位上。
    @Expect(DisplayPush.logical(2880, Float32(2.0)), Int64(1440))
    @Expect(DisplayPush.logical(1620, Float32(1.5)), Int64(1080))
    @Expect(DisplayPush.logical(1930, Float32(1.5)), Int64(1287))
}

@Test
func degenerateDensityAndSizeFallBackToPixels(): Unit {
    // 驱动报 0 / NaN / 负数时不做除法，免得布局塌成 0 或负数。
    @Expect(DisplayPush.logical(2880, Float32(0.0)), Int64(2880))
    @Expect(DisplayPush.logical(2880, Float32(-1.0)), Int64(2880))
    @Expect(DisplayPush.logical(2880, Float32.NaN), Int64(2880))
    @Expect(DisplayPush.logical(0, BASELINE_DENSITY), Int64(1))
}

@Test
func pushIsAppliedOnceAndOnlyWhenItChanges(): Unit {
    let log = DisplayPushLog()
    @Expect(log.current().isNone(), true)
    // 首次上报：采纳。
    let first = log.accept(2880, 1620, EXTERNAL_DENSITY)
    @Expect(first.isSome(), true)
    match (first) {
        case Some(push) =>
            @Expect(push.pixelWidth, Int64(2880))
            @Expect(push.logicalWidth(), Int64(2560))
            @Expect(push.logicalHeight(), Int64(1440))
        case None => @Fail("the first push must be accepted")
    }
    // 同尺寸同密度再报一次（onAreaChange 每轮布局都会触发）：不重复应用，否则会跟 SDL 互相触发。
    @Expect(log.accept(2880, 1620, EXTERNAL_DENSITY).isNone(), true)
    @Expect(log.accept(2880, 1620, EXTERNAL_DENSITY).isNone(), true)
    // 只改尺寸、只改密度，各自都要采纳一次。
    @Expect(log.accept(2560, 1440, EXTERNAL_DENSITY).isSome(), true)
    @Expect(log.accept(2560, 1440, Float32(1.0)).isSome(), true)
    // 缩回启动尺寸也一样（还原窗口）。
    @Expect(log.accept(1930, 1020, Float32(1.0)).isSome(), true)
}

@Test
func repeatedDensityIsComparedInThousandths(): Unit {
    let log = DisplayPushLog()
    let _ = log.accept(2560, 1440, Float32(1.125))
    // 同一个值的另一种浮点写法不算变化。
    @Expect(log.accept(2560, 1440, Float32(1.1250001)).isNone(), true)
    // 1/1000 以上的差别算变化。
    @Expect(log.accept(2560, 1440, Float32(1.126)).isSome(), true)
}

@Test
func unusablePushesAreIgnoredInsteadOfCollapsingTheWindow(): Unit {
    let log = DisplayPushLog()
    let _ = log.accept(2880, 1620, EXTERNAL_DENSITY)
    // 收尾时的 onAreaChange 可能报 0×0，密度也可能缺失：都不能把窗口缩成 0。
    @Expect(log.accept(0, 0, EXTERNAL_DENSITY).isNone(), true)
    @Expect(log.accept(-8, 1620, EXTERNAL_DENSITY).isNone(), true)
    @Expect(log.accept(2880, 1620, Float32(0.0)).isNone(), true)
    @Expect(log.accept(2880, 1620, Float32.NaN).isNone(), true)
    match (log.current()) {
        case Some(push) => @Expect(push.pixelWidth, Int64(2880))
        case None => @Fail("an unusable push must not replace the accepted one")
    }
    // 被忽略的推送不影响后续比较：同样的好值仍然算「没变」。
    @Expect(log.accept(2880, 1620, EXTERNAL_DENSITY).isNone(), true)
}

/*
 * 外接高分屏的实际布局尺寸：2880×1620 像素、densityPixels 1.125 → 逻辑 2560×1440。
 *
 * 与 `viewport_test.cj` 的 2880×1620 用例互补：那一条证明「树按像素尺寸重建」，这一条证明「按密度
 * 换算后的逻辑尺寸同样能铺满且不溢出」——密度换算写错（除以 1.125 之外的值、或干脆不除）时，七条路由
 * 会在右/下各留出 12.5% 的空白或溢出一截。
 */
private let DENSITY_LOGICAL_WIDTH: Int64 = 2560
private let DENSITY_LOGICAL_HEIGHT: Int64 = 1440
private let DENSITY_LAYOUT_HOME: String = "/tmp/textura-shell-density-home"
private let DENSITY_ANCHOR: Int64 = 1773626400000
/** 1px 的边框/抗锯齿容差。 */
private let DENSITY_TOLERANCE: Float32 = 1.5

@Test
func everyRouteFillsTheDensityScaledExternalScreen(): Unit {
    let routes = [Route.Dashboard, Route.Calendar, Route.Okr, Route.Gtd, Route.Gantt, Route.Sop, Route.Settings]
    for (route in routes) {
        try {
            setVariable("HOME", DENSITY_LAYOUT_HOME)
        } catch (_: Exception) {
            ()
        }
        let clock = FixedClock(DENSITY_ANCHOR)
        let store = AppStore(clock: clock)
        store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
        store.setRoute(routeId(route))
        let runtime = ShellRuntime(ShellPreferences.load(), store)
        let noLoadError: ?String = None
        let host = ShellHost(store, runtime, "2026-01-01", false, noLoadError, 1440, 900)
        host.armStoreBridge({action => action()})
        let testHost = WidgetTestHost()
        let body = {=> buildShell(host)}
        let _ = testHost.frame(Rect(0.0, 0.0, 1440.0, 900.0), body: body)
        // What CUI sees once the 2880×1620 surface is divided by the pushed 1.125 density.
        let _ = testHost.frame(Rect(0.0, 0.0, Float32(DENSITY_LOGICAL_WIDTH), Float32(DENSITY_LOGICAL_HEIGHT)),
            events: [UiEvent.WindowResized(Int32(DENSITY_LOGICAL_WIDTH), Int32(DENSITY_LOGICAL_HEIGHT))],
            body: body)
        @Expect(host.builtViewportWidth, DENSITY_LOGICAL_WIDTH)
        @Expect(host.builtViewportHeight, DENSITY_LOGICAL_HEIGHT)
        @Expect(host.viewportEpochValue(), Int64(1))
        var maxRight: Float32 = 0.0
        for (node in testHost.context.semanticsSnapshot()) {
            let rect = node.bounds
            if (rect.w <= 0.0 || rect.h <= 0.0) {
                continue
            }
            if (rect.x < -DENSITY_TOLERANCE || rect.right() > Float32(DENSITY_LOGICAL_WIDTH) + DENSITY_TOLERANCE ||
                rect.y < -DENSITY_TOLERANCE || rect.bottom() > Float32(DENSITY_LOGICAL_HEIGHT) + DENSITY_TOLERANCE) {
                @Fail("${routeId(route)} node '${node.properties.label}' at" +
                    " ${rect.x},${rect.y}..${rect.right()},${rect.bottom()} escaped the density-scaled window")
            }
            if (rect.right() > maxRight) {
                maxRight = rect.right()
            }
        }
        // The launch window was 1930×1020: content that stops there never adopted the new size.
        if (maxRight <= 1930.0) {
            @Fail("${routeId(route)} stopped at right=${maxRight}: the tree kept the launch width")
        }
    }
}
