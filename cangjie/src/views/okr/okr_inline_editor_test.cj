package textura.views.okr

import std.collection.ArrayList
import std.env.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*
import textura.ui.{FocusOnceView, vp}
import textura.views.okr.logic.{OkrMetric}

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

    /** 本帧的状态壳（`okrTypingNeverWritesTheStore` 等用例要读草稿）。 */
    func stateOrFail(): OkrUiState {
        match (ui) {
            case Some(value) => value
            case None => OkrUiState()
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
func okrInvalidValueKeepsTheEditorUntilEscape(): Unit {    let harness = OkrEditorHarness()
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

/*
 * 「编辑期间不写 store」——本轮用户现场（点 KR「当前」→ 输入 42 → 打不进字，随后点什么都像冻住）
 * 的直接门禁。
 *
 * 为什么要数 store 的修订号：`ShellHost.armStoreBridge` 把 `store.state` / `store.ui` 的每一次写入
 * 都桥接成壳根的 CUI `State`，于是**一次 store 写入 = 一次整壳重建**。如果内联编辑器每按一个键
 * 就写一次 store，编辑器（连同它的焦点与输入法）每帧都会被重建一次，用户看到的就是「第一个字符
 * 之后再也打不进去」。这条用例把「打字不写库」钉成数字：连续输入 10 个字符，两个修订号必须
 * 一字不差。
 */
@Test
func okrTypingNeverWritesTheStore(): Unit {
    let harness = OkrEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let spot = match (harness.metricHotspot("current")) {
        case Some(value) => value
        case None =>
            @Expect("a current-metric hotspot on the card canvas", "none")
            return
    }
    harness.press(testHost, spot)
    harness.build(testHost)
    let stateRev = harness.store.state.revision()
    let uiRev = harness.store.ui.revision()
    let ui = harness.stateOrFail()
    var typed = ""
    // 逐帧输入 10 个字符：每一帧都是「按一次键」。
    for (offset in 0..10) {
        let ch = "${offset}"
        typed += ch
        harness.build(testHost, events: [UiEvent.TextInput(ch)])
        // 焦点必须一直在这个控件上：没有焦点，后面的字符会直接落进页面。
        @Expect(testHost.context.focusId, OKR_PROMPT_KEY)
        @Expect(ui.promptOpen.value, true)
    }
    // 指标是槽位：打开即全选，所以草稿就是这 10 个字符本身（不是旧值 + 输入）。
    @Expect(ui.promptText.value, typed)
    // 编辑期间 store 零写入：整壳不会因为打字被重建。
    @Expect(harness.store.state.revision(), stateRev)
    @Expect(harness.store.ui.revision(), uiRev)
}

/**
 * 指标是「槽位」而不是文档：打开即全选，输入 `42` 就是 42。
 *
 * 用户现场是「点『当前』→ 输入 42 → 界面显示 42」。如果插入符停在旧值末尾（CUI 默认），
 * 同样的操作会得到 `4742`——数字确实进去了，但不是用户要的那个，读起来仍然是「没生效」。
 */
@Test
func okrSlotFieldIsReplacedByTheTypedValue(): Unit {
    let harness = OkrEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let spot = match (harness.metricHotspot("current")) {
        case Some(value) => value
        case None =>
            @Expect("a current-metric hotspot on the card canvas", "none")
            return
    }
    harness.press(testHost, spot)
    harness.build(testHost)
    let ui = harness.stateOrFail()
    let krId = harness.promptTarget()
    harness.build(testHost, events: [UiEvent.TextInput("4")])
    harness.build(testHost, events: [UiEvent.TextInput("2")])
    @Expect(ui.promptText.value, "42")
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Enter, false)])
    @Expect(ui.promptOpen.value, false)
    @Expect(okrCurrentMetric(harness.store, krId), Float64(42.0))
}

/**
 * 重建窗口里的「一帧无焦点」不是失焦：编辑器不能被这一帧提交掉，下一个字符仍然要落进来。
 *
 * CUI 只在 build 阶段重新登记焦点 id，所以「本帧没有拥有者」完全可能只是编辑器正在被重建。
 * 修之前这里会 `onCommit`：值合法就悄悄结束编辑，值非法（例如指标留空）就留下一个**没有焦点**
 * 的编辑器 —— 之后的字符无处可去，而背板把每次点击都吃掉，看起来就是整个界面冻住。
 */
@Test
func okrEditorSurvivesAFocusGap(): Unit {
    let harness = OkrEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let spot = match (harness.metricHotspot("current")) {
        case Some(value) => value
        case None =>
            @Expect("a current-metric hotspot on the card canvas", "none")
            return
    }
    harness.press(testHost, spot)
    harness.build(testHost)
    let ui = harness.stateOrFail()
    let stateRev = harness.store.state.revision()
    harness.build(testHost, events: [UiEvent.TextInput("7")])
    // 模拟真机上的那一帧：树被重新描述，焦点 id 还没被重新采纳。
    testHost.context.clearFocus()
    harness.build(testHost)
    // 这一帧结束前，逐帧钩子已经把焦点还回编辑器；编辑器没被提交、库没被写。
    @Expect(ui.promptOpen.value, true)
    @Expect(testHost.context.focusId, OKR_PROMPT_KEY)
    @Expect(harness.store.state.revision(), stateRev)
    // 于是**下一个**字符仍然落进同一个草稿（丢字符正是用户说的「打不进去」）。
    harness.build(testHost, events: [UiEvent.TextInput("8")])
    @Expect(ui.promptText.value, "78")
    @Expect(testHost.context.focusId, OKR_PROMPT_KEY)
    @Expect(harness.store.state.revision(), stateRev)
}

/** 提交后编辑器不再持有焦点（归还目标见下一条用例）。 */
@Test
func okrCommitHandsFocusBackToTheField(): Unit {
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
    @Expect(testHost.context.focusId, OKR_PROMPT_KEY)
    harness.build(testHost, events: [UiEvent.TextInput("x")])
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Enter, false)])
    @Expect(harness.stateOrFail().promptOpen.value, false)
    // 焦点归还要走一整帧（`FocusOnceView` 在 layout 里消费这次请求）。
    harness.build(testHost)
    // 编辑器已经把焦点交出去：它绝不会继续占着键盘。
    @Expect(testHost.context.focusId == OKR_PROMPT_KEY, false)
}

/**
 * 归还目标就是**打开编辑器的那个字段**：`okrPromptFocusTarget` 从编辑目标直接算出画布上的
 * 焦点 id，而不是依赖「打开前谁持有焦点」——画布热点是在 layout 里登记的，那一帧的拥有者未必
 * 还被焦点图认，靠 `release()` 会退化成「谁也不是」，真机上就只能靠 shell 兜底到侧栏行。
 */
@Test
func okrFocusRestoreTargetsTheOpenedField(): Unit {
    let harness = OkrEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let metric = match (harness.metricHotspot("current")) {
        case Some(value) => value
        case None =>
            @Expect("a current-metric hotspot", "none")
            return
    }
    harness.press(testHost, metric)
    harness.build(testHost)
    @Expect(okrPromptFocusTarget(harness.stateOrFail()), metric.id)
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Escape, false)])
    let title = match (harness.hotspot("okr-title-")) {
        case Some(value) => value
        case None =>
            @Expect("a title hotspot", "none")
            return
    }
    harness.press(testHost, title)
    harness.build(testHost)
    @Expect(okrPromptFocusTarget(harness.stateOrFail()), title.id)
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Escape, false)])
    let owner = match (harness.hotspot("okr-owner-")) {
        case Some(value) => value
        case None =>
            @Expect("an owner hotspot", "none")
            return
    }
    harness.press(testHost, owner)
    harness.build(testHost)
    @Expect(okrPromptFocusTarget(harness.stateOrFail()), owner.id)
}

/** 指标「当前」的数值（store 里那条 KR 的 `metric.current`）。 */
private func okrCurrentMetric(store: AppStore, krId: String): Float64 {
    for (item in store.state.value().items) {
        if (item.id == krId) {
            match (item.okr) {
                case Some(okr) => match (okr.metric) {
                    case Some(metric) => return metric.current
                    case None => return -1.0
                }
                case None => return -1.0
            }
        }
    }
    -1.0
}

/** 画布数据（每帧从 store 重建）里那条 KR 的完整指标：用例要区分「当前」与「目标」。 */
private func okrMetricOfPage(harness: OkrEditorHarness, krId: String): ?OkrMetric {
    match (harness.page) {
        case Some(page) =>
            for (entry in page.data.entries) {
                for (kr in entry.krs) {
                    if (kr.item.id == krId) {
                        return kr.metric
                    }
                }
            }
            Option<OkrMetric>.None
        case None => Option<OkrMetric>.None
    }
}

/*
 * 数字槽位的「逐帧输入」门禁（本轮用户现场：点开「当前」后**只删得掉、打不进字**）。
 *
 * 真机上的一次按键不是一条事件：IME 先把组合内容送进控件（`TextEditing`），提交时再送
 * `TextInput`；两者占不同的帧，中间还夹着空闲帧（插入符闪烁、store 无关的重绘）。
 * 主机用例过去只喂 `TextInput` 一条事件、且不插空闲帧，所以「帧与帧之间草稿被重置/被全选覆盖」
 * 这类缺陷测不到。下面的辅助函数按真机节奏喂事件，让每条用例都走
 * `Ui.inlineEditor` + `okrPromptDialog` 的真实链路（不直接调 `commitOkrPrompt`）。
 */

/** 一次按键：组合一帧、提交一帧、再空一帧。 */
private func okrTypeChar(harness: OkrEditorHarness, testHost: WidgetTestHost, ch: String): Unit {
    harness.build(testHost, events: [UiEvent.TextEditing(ch, 0, Int32(ch.size))])
    harness.build(testHost, events: [UiEvent.TextInput(ch)])
    harness.build(testHost)
}

/** 依次输入给定的字符（逐帧）。用显式的字符数组，避免在用例里做 Rune → String 的转换。 */
private func okrTypeChars(harness: OkrEditorHarness, testHost: WidgetTestHost, chars: Array<String>): Unit {
    for (ch in chars) {
        okrTypeChar(harness, testHost, ch)
    }
}

/** 退格一次（真机上是 `KeyDown`/`KeyUp` 两条事件，中间一帧）。 */
private func okrBackspace(harness: OkrEditorHarness, testHost: WidgetTestHost): Unit {
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Backspace, false)])
    harness.build(testHost, events: [UiEvent.KeyUp(Key.Backspace)])
    harness.build(testHost)
}

/** 慢一点的一次点击：按下与抬起落在**不同的帧**（触屏上很常见），返回是否点中了槽位。 */
private func okrSlowTap(harness: OkrEditorHarness, testHost: WidgetTestHost, spot: OkrHotspot): Unit {
    let ctx = testHost.context
    let x = spot.rect.centerX()
    let y = spot.rect.centerY()
    match (harness.page) {
        case Some(page) =>
            let _ = page.handle(ctx, UiEvent.MouseDown(MouseButton.Left, x, y))
            harness.build(testHost)
            let _ = page.handle(ctx, UiEvent.MouseUp(MouseButton.Left, x, y))
            harness.build(testHost)
        case None => ()
    }
}

/**
 * 打开「当前」槽位（值 47）后一个字符一个字符地打 `42`：草稿必须是 `42`。
 *
 * 这条钉住用户现场的第一种成因：如果每个新字符之前都重来一次全选，草稿会停在**最后一位**（`2`）；
 * 如果草稿被每帧重置回原值，草稿会停在 `47`；如果插入符停在末尾（没有全选），会是 `4742`。
 * 三种都读作「打不进去」，所以这里逐帧断言每一步，而不是只断言最终值。
 */
@Test
func okrSlotTypingAccumulatesOneDigitPerFrame(): Unit {
    let harness = OkrEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let spot = match (harness.metricHotspot("current")) {
        case Some(value) => value
        case None =>
            @Expect("a current-metric hotspot on the card canvas", "none")
            return
    }
    okrSlowTap(harness, testHost, spot)
    let ui = harness.stateOrFail()
    // 槽位打开即全选：草稿还是原值，但第一字符会替换它。
    @Expect(ui.promptText.value, "47")
    @Expect(testHost.context.focusId, OKR_PROMPT_KEY)
    let stateRev = harness.store.state.revision()
    let uiRev = harness.store.ui.revision()
    okrTypeChar(harness, testHost, "4")
    // 关键断言：一个字符就是那一个字符（不是 `474`，不是 `74`，更不是空）。
    @Expect(ui.promptText.value, "4")
    @Expect(testHost.context.focusId, OKR_PROMPT_KEY)
    okrTypeChar(harness, testHost, "2")
    // 第二个字符必须**追加**：既不能把前一位替换掉（每帧全选），也不能被重置回 47。
    @Expect(ui.promptText.value, "42")
    @Expect(ui.promptOpen.value, true)
    // 打字期间不写库（一次 store 写入 = 一次整壳重建 = 焦点与输入法一起丢，§26.2）。
    @Expect(harness.store.state.revision(), stateRev)
    @Expect(harness.store.ui.revision(), uiRev)
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Enter, false)])
    @Expect(ui.promptOpen.value, false)
    @Expect(ui.promptError.value.isEmpty(), true)
    @Expect(okrCurrentMetric(harness.store, harness.promptTarget()), Float64(42.0))
}

/** 连打三位 → 退格一位 → 补一位：`123` → `12` → `124`，提交写回 124。 */
@Test
func okrSlotTypingThreeBackspaceThenOneMore(): Unit {
    let harness = OkrEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let spot = match (harness.metricHotspot("current")) {
        case Some(value) => value
        case None =>
            @Expect("a current-metric hotspot on the card canvas", "none")
            return
    }
    okrSlowTap(harness, testHost, spot)
    let ui = harness.stateOrFail()
    let krId = harness.promptTarget()
    okrTypeChars(harness, testHost, ["1", "2", "3"])
    @Expect(ui.promptText.value, "123")
    okrBackspace(harness, testHost)
    @Expect(ui.promptText.value, "12")
    okrTypeChar(harness, testHost, "4")
    @Expect(ui.promptText.value, "124")
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Enter, false)])
    @Expect(ui.promptOpen.value, false)
    @Expect(okrCurrentMetric(harness.store, krId), Float64(124.0))
}

/**
 * 打开后不改任何东西直接回车：关闭、**不报错**、值保持原样。
 *
 * 修之前这里显示「这个值无法解析成数字。」并且编辑器不关：`pendingMetricPatch` 返回 `None`
 * 有两种含义（解析失败 / 与库里的值相同、无需写回），旧代码把两者都当解析失败。真机上用户先删
 * 后打、打进去没生效时草稿仍是原值，回车就撞上这一条——用户报的「有一定概率出现无法解析」。
 * 这里也钉住「不重复写库」：写一个相同的值只会多一条历史，没有任何收益。
 */
@Test
func okrSlotEnterWithoutChangesClosesWithoutAnError(): Unit {
    let harness = OkrEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let spot = match (harness.metricHotspot("current")) {
        case Some(value) => value
        case None =>
            @Expect("a current-metric hotspot on the card canvas", "none")
            return
    }
    okrSlowTap(harness, testHost, spot)
    let ui = harness.stateOrFail()
    let krId = harness.promptTarget()
    let stateRev = harness.store.state.revision()
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Enter, false)])
    @Expect(ui.promptOpen.value, false)
    @Expect(ui.promptError.value, "")
    @Expect(okrCurrentMetric(harness.store, krId), Float64(47.0))
    @Expect(harness.store.state.revision(), stateRev)
}

/** 把原值重打一遍（`47` → `47`）：与库里相同，同样不报错、不写库、值不变。 */
@Test
func okrSlotRetypingTheSameValueIsNotAnError(): Unit {
    let harness = OkrEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let spot = match (harness.metricHotspot("current")) {
        case Some(value) => value
        case None =>
            @Expect("a current-metric hotspot on the card canvas", "none")
            return
    }
    okrSlowTap(harness, testHost, spot)
    let ui = harness.stateOrFail()
    let krId = harness.promptTarget()
    okrTypeChars(harness, testHost, ["4", "7"])
    @Expect(ui.promptText.value, "47")
    let stateRev = harness.store.state.revision()
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Enter, false)])
    @Expect(ui.promptOpen.value, false)
    @Expect(ui.promptError.value, "")
    @Expect(okrCurrentMetric(harness.store, krId), Float64(47.0))
    @Expect(harness.store.state.revision(), stateRev)
}

/**
 * 非法值（`1,5`）→ 回车 → 错误行出现、编辑器不关、草稿保留；随后改成 `15` 仍能提交。
 *
 * 「拒绝之后还能继续干活」是这一条的要点：拒绝不能顺手清空草稿，也不能把焦点或输入法弄丢。
 */
@Test
func okrSlotUnparseableValueKeepsTheEditorAndATypedFixCommits(): Unit {
    let harness = OkrEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let spot = match (harness.metricHotspot("current")) {
        case Some(value) => value
        case None =>
            @Expect("a current-metric hotspot on the card canvas", "none")
            return
    }
    okrSlowTap(harness, testHost, spot)
    let ui = harness.stateOrFail()
    let krId = harness.promptTarget()
    okrTypeChars(harness, testHost, ["1", ",", "5"])
    @Expect(ui.promptText.value, "1,5")
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Enter, false)])
    // 拒绝：不关、有错误行、草稿原样保留、库里的值没动。
    @Expect(ui.promptOpen.value, true)
    @Expect(ui.promptError.value.isEmpty(), false)
    @Expect(ui.promptText.value, "1,5")
    @Expect(okrCurrentMetric(harness.store, krId), Float64(47.0))
    @Expect(testHost.context.focusId, OKR_PROMPT_KEY)
    // 改对：三位退格清空，再打 `15`，回车写回。
    okrBackspace(harness, testHost)
    okrBackspace(harness, testHost)
    okrBackspace(harness, testHost)
    @Expect(ui.promptText.value, "")
    okrTypeChars(harness, testHost, ["1", "5"])
    @Expect(ui.promptText.value, "15")
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Enter, false)])
    @Expect(ui.promptOpen.value, false)
    @Expect(ui.promptError.value, "")
    @Expect(okrCurrentMetric(harness.store, krId), Float64(15.0))
}

/**
 * 打第一位之后的一个「无焦点帧」（重建窗口）不得丢字符：`4` + 空焦点一帧 + `2` = `42`。
 *
 * 这是 `INLINE_BLUR_FRAMES` 去抖的真机形态：CUI 只在**本次 build** 里重新认领焦点 id，任何让子树
 * 重新描述的帧都可能报告 `focusId == ""`。那一帧若被当成失焦，值合法就静默结束编辑、不合法就留下
 * 一个没有焦点的编辑器——之后的字符无处可去。
 */
@Test
func okrSlotTypingSurvivesAFocusGapBetweenDigits(): Unit {
    let harness = OkrEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let spot = match (harness.metricHotspot("current")) {
        case Some(value) => value
        case None =>
            @Expect("a current-metric hotspot on the card canvas", "none")
            return
    }
    okrSlowTap(harness, testHost, spot)
    let ui = harness.stateOrFail()
    let krId = harness.promptTarget()
    okrTypeChar(harness, testHost, "4")
    @Expect(ui.promptText.value, "4")
    let stateRev = harness.store.state.revision()
    // 重建窗口：这一帧树被重新描述，编辑器自己的焦点 id 还没被重新采纳。
    testHost.context.clearFocus()
    harness.build(testHost)
    @Expect(ui.promptOpen.value, true)
    @Expect(testHost.context.focusId, OKR_PROMPT_KEY)
    @Expect(harness.store.state.revision(), stateRev)
    okrTypeChar(harness, testHost, "2")
    @Expect(ui.promptText.value, "42")
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Enter, false)])
    @Expect(ui.promptOpen.value, false)
    @Expect(okrCurrentMetric(harness.store, krId), Float64(42.0))
}

/**
 * 换一个槽位（`当前` → `目标`）后草稿必须是**新字段**的值，不是上一个字段的草稿。
 *
 * 所有 OKR 字段共用一个编辑器 key（`OKR_PROMPT_INPUT`），跨字段复用同一个 `InlineEditFrame`；
 * 打开新字段时草稿、全选、错误行都必须按新字段重置，否则用户会「改的是上一个字段」。
 */
@Test
func okrSlotReopeningAnotherFieldUsesThatFieldsValue(): Unit {
    let harness = OkrEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let current = match (harness.metricHotspot("current")) {
        case Some(value) => value
        case None =>
            @Expect("a current-metric hotspot on the card canvas", "none")
            return
    }
    okrSlowTap(harness, testHost, current)
    let ui = harness.stateOrFail()
    okrTypeChar(harness, testHost, "9")
    @Expect(ui.promptText.value, "9")
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Escape, false)])
    @Expect(ui.promptOpen.value, false)
    let target = match (harness.metricHotspot("target")) {
        case Some(value) => value
        case None =>
            @Expect("a target-metric hotspot on the card canvas", "none")
            return
    }
    okrSlowTap(harness, testHost, target)
    let krId = harness.promptTarget()
    @Expect(ui.promptText.value, "60")
    @Expect(ui.promptField.value, "target")
    okrTypeChar(harness, testHost, "8")
    // 新会话的第一字符照样是替换（全选只按会话生效，不跨字段残留）。
    @Expect(ui.promptText.value, "8")
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Enter, false)])
    @Expect(ui.promptOpen.value, false)
    match (okrMetricOfPage(harness, krId)) {
        case Some(metric) =>
            @Expect(metric.target, Float64(8.0))
            // 相邻字段没被顺手改掉。
            @Expect(metric.start, Float64(42.0))
        case None => @Expect("a stored metric", "none")
    }
}
