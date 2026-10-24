package textura.views.okr

import std.collection.ArrayList
import std.env.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*
import textura.ui.{FocusOnceView, vp}

/*
 * OKR 卡片画布上的原位编辑器：点中画上去的输入框，编辑器必须落在**那个盒子**上。
 *
 * 真机现场（docs/DEVICE-NOTES.md §25.1）：点「指标」输入框后，真控件出现在窗口左上角，
 * 原来的字段被画成编辑态（文字消失）——因为字段矩形存在每帧重建的 `OkrUiState` 里，
 * 下一帧读回 `Rect.zero()`。本用例从**真实点击路径**（画布登记的 hotspot → MouseDown/MouseUp）
 * 打开编辑器，再用语义节点的绝对 bounds 与字段矩形逐像素比较，并把「窗口绝对坐标」这一条
 * 写死：内容区原点 = 侧栏 240 + 内边距 24 = 264，顶栏 56 + 内边距 24 = 80。
 */
private let OKR_EDITOR_VIEWPORT: Rect = Rect(0.0, 0.0, 1440.0, 900.0)
/** shell 的 `.shell-content` 内盒：sidebar 240 + 24 内边距，topbar 56 + 24 内边距。 */
private let OKR_EDITOR_CONTENT_LEFT: Float32 = 264.0
private let OKR_EDITOR_CONTENT_TOP: Float32 = 80.0
private let OKR_PROMPT_KEY: String = "okr-prompt-input"
private let OKR_EDITOR_ANCHOR: Int64 = 1773626400000
private let OKR_EDITOR_HOME: String = "/tmp/textura-okr-inline-test-home"

private class OkrEditorHarness {
    var page: ?OkrPage = None
    var ui: ?OkrUiState = None
    let store: AppStore
    let viewCtx: ViewContext

    init() {
        try {
            setVariable("HOME", OKR_EDITOR_HOME)
        } catch (_: Exception) {
            ()
        }
        let clock = FixedClock(OKR_EDITOR_ANCHOR)
        this.store = AppStore(clock: clock)
        store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
        store.setRoute("okr")
        this.viewCtx = ViewContext(store, "light", "2026-01-01", 1440, 900, {_ => ()})
    }

    /**
     * 与 `okr.cj` 的 `render` 同一条构建路径（`OkrPage` + `okrDialogs` + 焦点载体），
     * 外面套一层与 shell 内容区等价的 padding，这样页面拿到的就是窗口绝对坐标。
     */
    func build(testHost: WidgetTestHost, events!: Array<UiEvent> = []): Unit {
        let _ = testHost.frame(OKR_EDITOR_VIEWPORT, events: events) {
            =>
                VStack(spacing: vp(0.0)) {
                    let ui = okrUiState()
                    let page = OkrPage(viewCtx, ui)
                    this.ui = ui
                    this.page = page
                    okrDialogs(viewCtx, ui, page)
                    FocusOnceView(ui.promptFocus)
                }
                    .hug()
                    .padding(OKR_EDITOR_CONTENT_LEFT, OKR_EDITOR_CONTENT_TOP, 24.0, 24.0)
        }
    }

    /** 画布上第一个 id 以 `prefix` 开头的命中区（点击走它）。 */
    func hotspot(prefix: String): ?OkrHotspot {
        match (page) {
            case Some(value) =>
                for (spot in value.hotspots()) {
                    if (spot.id.startsWith(prefix)) {
                        return Some(spot)
                    }
                }
                None
            case None => None
        }
    }

    /** 指定指标字段的命中区（`start` / `current` / `target` / `unit`）。 */
    func metricHotspot(field: String): ?OkrHotspot {
        match (page) {
            case Some(value) =>
                for (spot in value.hotspots()) {
                    if (spot.id.endsWith("-${field}") && spot.id.startsWith("okr-field-")) {
                        return Some(spot)
                    }
                }
                None
            case None => None
        }
    }

    /** 本帧原位编辑器正在编辑的条目 id（`OkrUiState.promptTarget`）。 */
    func promptTarget(): String {
        match (ui) {
            case Some(value) => value.promptTarget.value
            case None => ""
        }
    }

    /** 像用户一样点一下：按下 + 抬起都落在盒子里（画布的命中区按这个顺序触发）。 */
    func press(testHost: WidgetTestHost, spot: OkrHotspot): Unit {
        let ctx = testHost.context
        let x = spot.rect.centerX()
        let y = spot.rect.centerY()
        match (page) {
            case Some(value) =>
                let _ = value.handle(ctx, UiEvent.MouseDown(MouseButton.Left, x, y))
                let _ = value.handle(ctx, UiEvent.MouseUp(MouseButton.Left, x, y))
            case None => ()
        }
    }
}

private func okrEditorBoundsOf(testHost: WidgetTestHost, key: String): Rect {
    var bounds = Rect(0.0, 0.0, -1.0, -1.0)
    for (node in testHost.context.semanticsSnapshot()) {
        if (node.id == key) {
            bounds = node.bounds
        }
    }
    bounds
}

private func okrRectText(rect: Rect): String {
    "x=${rect.x} y=${rect.y} w=${rect.w} h=${rect.h}"
}

/**
 * 编辑器应有的矩形：**位置**与字段逐像素相同；**尺寸**不小于「一行可输入」的下限
 * （`ui/inline_editor.cj` 的 28 高 / 72 宽——插入符必须有地方落，画布上 18px 高的标题行
 * 本身装不下一行文字）。指标输入框是 78×28，正好等于自身，所以这条换算对它没有影响。
 */
private func okrEditorExpected(rect: Rect): Rect {
    Rect(rect.x, rect.y, max(rect.w, 72.0), max(rect.h, 28.0))
}

/**
 * 指标输入框（`起点/当前/目标/单位`）：点中之后编辑器必须**正好**压在它上面，
 * 而且矩形是窗口绝对坐标（内容区左边缘 ≥ 264、顶栏下边缘 ≥ 80），不是页面局部坐标。
 */
@Test
func okrMetricFieldEditorSitsOnTheFieldRectangle(): Unit {
    let harness = OkrEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let spot = match (harness.hotspot("okr-field-")) {
        case Some(value) => value
        case None =>
            @Expect("a metric field hotspot on the card canvas", "none")
            return
    }
    // 画布记录的矩形必须已经在窗口绝对坐标系里（内容区偏移已含）。
    @Expect(spot.rect.x >= OKR_EDITOR_CONTENT_LEFT, true)
    @Expect(spot.rect.y >= OKR_EDITOR_CONTENT_TOP, true)
    harness.press(testHost, spot)
    harness.build(testHost)
    @Expect(okrRectText(okrEditorBoundsOf(testHost, OKR_PROMPT_KEY)), okrRectText(okrEditorExpected(spot.rect)))
}

/** 目标 / KR 标题：同一条路径、同一个断言（标题是画布上的另一类字段）。 */
@Test
func okrTitleEditorSitsOnTheFieldRectangle(): Unit {
    let harness = OkrEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let spot = match (harness.hotspot("okr-title-")) {
        case Some(value) => value
        case None =>
            @Expect("a title hotspot on the card canvas", "none")
            return
    }
    @Expect(spot.rect.x >= OKR_EDITOR_CONTENT_LEFT, true)
    harness.press(testHost, spot)
    harness.build(testHost)
    @Expect(okrRectText(okrEditorBoundsOf(testHost, OKR_PROMPT_KEY)), okrRectText(okrEditorExpected(spot.rect)))
}

/**
 * 打开后换到另一个字段：编辑器跟着新盒子的矩形走（不能停在上一个位置上）。
 * 这条同时覆盖「矩形跨帧保留」——第二次点击前 `ui` 是**另一帧**的状态壳。
 */
@Test
func okrEditorFollowsTheNextClickedField(): Unit {
    let harness = OkrEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    var first: ?OkrHotspot = None
    var second: ?OkrHotspot = None
    for (spot in match (harness.page) {
        case Some(page) => page.hotspots()
        case None => Array<OkrHotspot>()
    }) {
        if (!spot.id.startsWith("okr-field-")) {
            continue
        }
        if (first.isNone()) {
            first = Some(spot)
        } else if (second.isNone()) {
            second = Some(spot)
        }
    }
    match ((first, second)) {
        case (Some(a), Some(b)) =>
            harness.press(testHost, a)
            harness.build(testHost)
            @Expect(okrRectText(okrEditorBoundsOf(testHost, OKR_PROMPT_KEY)), okrRectText(okrEditorExpected(a.rect)))
            harness.press(testHost, b)
            harness.build(testHost)
            @Expect(okrRectText(okrEditorBoundsOf(testHost, OKR_PROMPT_KEY)), okrRectText(okrEditorExpected(b.rect)))
        case _ => @Expect("at least two metric hotspots", "fewer")
    }
}

/**
 * 提交写回：Enter 把草稿写进 store 并关闭编辑器（与 `okr_prompt.cj` 的提交路径一致）。
 *
 * 用「单位」字段而不是起点/当前/目标：单位的改动不参与 `pendingMetricPatch` 的数值换算，
 * 不会因为「起点 42 与目标值不自洽」被拒绝——那条拒绝是产品语义，不是本用例要断言的东西
 * （拒绝后编辑器必须**留在原地**，由 Esc 关闭，见 `okrInvalidValueKeepsTheEditorUntilEscape`）。
 */
@Test
func okrInlineEditorCommitsTheTypedValue(): Unit {
    let harness = OkrEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let spot = match (harness.metricHotspot("unit")) {
        case Some(value) => value
        case None =>
            @Expect("a unit field hotspot on the card canvas", "none")
            return
    }
    harness.press(testHost, spot)
    harness.build(testHost)
    @Expect(okrEditorBoundsOf(testHost, OKR_PROMPT_KEY).w > 0.0, true)
    let ui = match (harness.ui) {
        case Some(value) => value
        case None =>
            @Expect("an OKR ui state", "none")
            return
    }
    let krId = harness.promptTarget()
    @Expect(krId.isEmpty(), false)
    ui.promptText.value = "点/周"
    harness.build(testHost)
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Enter, false)])
    // 编辑器关闭 + 值真的写回了 store，界面下一帧读到的就是新单位。
    @Expect(ui.promptOpen.value, false)
    @Expect(okrEditorBoundsOf(testHost, OKR_PROMPT_KEY).w < 0.0, true)
    var unit = ""
    for (item in harness.store.state.value().items) {
        if (item.id == krId) {
            match (item.okr) {
                case Some(okr) => match (okr.metric) {
                    case Some(metric) => unit = metric.unit
                    case None => ()
                }
                case None => ()
            }
        }
    }
    @Expect(unit, "点/周")
}

/**
 * 非法值 + backdrop 点击：提交被拒时编辑器**留在原地**并显示错误（Web 一致），
 * 但 Esc 必须仍然能关掉它——「无法消除」是本轮用户现场里最硬的一条。
 */
@Test
func okrInvalidValueKeepsTheEditorUntilEscape(): Unit {
    let harness = OkrEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let spot = match (harness.hotspot("okr-field-")) {
        case Some(value) => value
        case None =>
            @Expect("a metric field hotspot on the card canvas", "none")
            return
    }
    harness.press(testHost, spot)
    harness.build(testHost)
    let ui = match (harness.ui) {
        case Some(value) => value
        case None =>
            @Expect("an OKR ui state", "none")
            return
    }
    // 起点填一个非数字：`pendingMetricPatch` 一定拒绝。
    ui.promptText.value = "abc"
    harness.build(testHost)
    // 点编辑器外面的空白处（backdrop 提交）：校验拒绝 → 编辑器留在原地并显示错误行。
    harness.build(testHost,
        events: [UiEvent.MouseDown(MouseButton.Left, 60.0, 700.0), UiEvent.MouseUp(MouseButton.Left, 60.0, 700.0)])
    @Expect(ui.promptOpen.value, true)
    @Expect(ui.promptError.value.isEmpty(), false)
    // Esc 无条件取消：即使值非法、矩形异常，也必须能关掉。
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Escape, false)])
    @Expect(ui.promptOpen.value, false)
    @Expect(okrEditorBoundsOf(testHost, OKR_PROMPT_KEY).w < 0.0, true)
}

