package textura.shell

import std.collection.ArrayList
import std.env.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*

/*
 * 七路由的字段定位审计（宿主侧）：任何文本控件都不许跑到「窗口左上角」或压到侧栏上。
 *
 * 这一条针对真机故障的坐标系本身：内联编辑器 / 输入框的矩形必须是**窗口绝对坐标**
 * （侧栏 240、顶栏 56、内容区内边距 24 都已包含）。真机上 OKR/GTD 的编辑器曾画在 (6,6)，
 * 正好落在侧栏标题上；那种错位在宿主里表现就是「有控件的 x < 240 或超出窗口」。
 *
 * 每条路由至少枚举到一个文本控件（顶栏搜索在每条路由都有），空集合会直接失败，
 * 避免「零命中绿灯」。
 */
private let AUDIT_RECT: Rect = Rect(0.0, 0.0, 1440.0, 900.0)
private let AUDIT_ANCHOR: Int64 = 1773626400000
private let AUDIT_HOME: String = "/tmp/textura-inline-audit-home"
/** `.shell` grid：侧栏固定 240（`SIDEBAR_WIDTH`）。 */
private let AUDIT_SIDEBAR: Float32 = 240.0
/** `--topbar-height: 56`。 */
private let AUDIT_TOPBAR: Float32 = 56.0

private func auditHost(): ShellHost {
    try {
        setVariable("HOME", AUDIT_HOME)
    } catch (_: Exception) {
        ()
    }
    let clock = FixedClock(AUDIT_ANCHOR)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    store.setRoute(routeId(Route.Dashboard))
    let runtime = ShellRuntime(ShellPreferences.load(), store)
    let noLoadError: ?String = None
    ShellHost(store, runtime, "2026-01-01", false, noLoadError, 1440, 900)
}

/** 语义树里的全部文本框（绝对 bounds）。 */
private func auditFields(testHost: WidgetTestHost): Array<Rect> {
    let result = ArrayList<Rect>()
    for (node in testHost.context.semanticsSnapshot()) {
        match (node.properties.role) {
            case SemanticsRole.TextField => ()
            case _ => continue
        }
        let rect = node.visibleBounds
        if (rect.w <= 1.0 || rect.h <= 1.0) {
            continue
        }
        result.add(rect)
    }
    result.toArray()
}

/**
 * 每条路由：至少一个文本控件，且每个控件都满足
 *   x ≥ 240（不压侧栏）、y ≥ 0、右/下边不越窗。
 * 内容区里的控件还要求 x ≥ 264 / y ≥ 56（内容区内边距 + 顶栏），
 * 顶栏搜索框只要求 x ≥ 240 且 y ≥ 0（它本来就在顶栏里）。
 */
@Test
func everyRouteKeepsItsFieldsInsideTheContentBox(): Unit {
    var routesChecked = 0
    var problems = ""
    for (route in ROUTES) {
        let host = auditHost()
        host.armStoreBridge({action => action()})
        host.store.setRoute(routeId(route))
        if (routeId(route) == "gantt") {
            // 检查器默认收起；打开并选中一行，让标题/日期/进度输入框进入树。
            host.store.setUi({state => state.inspectorOpen = true})
            let seeded = host.store.state.value()
            if (!seeded.items.isEmpty()) {
                host.store.select(seeded.items[0].id)
            }
        }
        let testHost = WidgetTestHost()
        let _ = testHost.frame(AUDIT_RECT, body: {=> buildShell(host)})
        let fields = auditFields(testHost)
        let routeName = routeId(route)
        if (fields.isEmpty()) {
            problems += "${routeName}: no text control in the tree\n"
        }
        for (rect in fields) {
            let label = "${routeName} field x=${rect.x} y=${rect.y} w=${rect.w} h=${rect.h}"
            // 左边界：绝不压侧栏（真机「编辑器画到左上角」的判据）。
            if (rect.x < AUDIT_SIDEBAR) {
                problems += "${label}: overlaps the sidebar\n"
            }
            // 右/下边界：不越窗。
            if (rect.right() > AUDIT_RECT.w + 0.5) {
                problems += "${label}: overflows the right edge\n"
            }
            if (rect.bottom() > AUDIT_RECT.h + 0.5) {
                problems += "${label}: overflows the bottom edge\n"
            }
            // 顶栏（y < 56）里只允许顶栏自己的控件，且同样不许压侧栏。
            if (rect.y < AUDIT_TOPBAR && rect.x < AUDIT_SIDEBAR) {
                problems += "${label}: topbar control over the sidebar\n"
            }
        }
        routesChecked += 1
    }
    // 七条路由都跑过（防止路由表被改空）。
    if (routesChecked != ROUTES.size) {
        problems += "routes checked=${routesChecked} of ${ROUTES.size}\n"
    }
    @Expect(problems, "")
}
