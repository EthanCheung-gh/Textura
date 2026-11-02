package textura.views.sop

import std.env.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*
import textura.ui.{FocusOnceView, ThemeTokens, tokensOf, texturaLight, vp}

/*
 * SOP 检查器的 Area 下拉（`sop_area_picker.cj`）。
 *
 * 真机反馈「Area 点了没反应」：检查器是自绘的，点击必须命中 `areaInput` 并打开一个可选择的
 * 浮层。本文件钉住候选集合（未指定 + 全部领域）、选择写回 `Item.areaId`、以及弹层几何
 * （窗口内、下方放不下时翻到上方）。
 *
 * 后半部分是**从真实事件路径**钉住真机那三条现场：
 *   - 浮层在 `layout` 登记 → 同一帧的事件就能选中一行（draw 里登记则永远收不到，见文件头）；
 *   - 面板外的按下关闭且不写回，**同一帧也不会穿透到画布**选中节点/连线；
 *   - 字段矩形消失（换选中项）时弹层关闭，绝不按 `Rect.zero()` 排到窗口左上角。
 */

private func areaStore(): AppStore {
    let clock = FixedClock(1773626400000)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    store
}

private func firstSopId(workspace: Workspace): String {
    for (summary in sopList(workspace)) {
        return summary.sop.id
    }
    ""
}

@Test
func choicesListUnassignedAndEveryArea(): Unit {
    let store = areaStore()
    let workspace = store.state.value()
    let choices = sopAreaChoices(workspace)
    @Expect(choices.size, Int64(workspace.areas.size + 1))
    @Expect(choices[0].label, "未指定")
    @Expect(choices[0].areaId.isNone(), true)
    // `workspace.areas` keeps the sidebar order (产品 / 运营 / 个人 in the seed fixture).
    @Expect(choices[1].label, workspace.areas[0].name)
    @Expect(choices[1].areaId.getOrThrow(), workspace.areas[0].id)
    var index: Int64 = 1
    while (index < choices.size) {
        @Expect(choices[index].label.isEmpty(), false)
        index += 1
    }
}

@Test
func selectingAnAreaWritesItemAreaIdAndUnassignedClearsIt(): Unit {
    let store = areaStore()
    let workspace = store.state.value()
    let sopId = firstSopId(workspace)
    @Expect(sopId.isEmpty(), false)
    let choices = sopAreaChoices(workspace)
    let ops = workspace.areas[1].id
    let opsIndex = sopAreaIndexOf(choices, Some(ops))
    @Expect(opsIndex, Int64(2))
    @Expect(commitSopAreaChoice(store, sopId, choices, opsIndex), true)
    let assigned = match (itemById(store.state.value(), sopId)) {
        case Some(item) => item.areaId
        case None => Some("missing")
    }
    @Expect(assigned.getOrThrow(), ops)
    // The first choice is「未指定」: it clears the area instead of writing an empty id.
    @Expect(commitSopAreaChoice(store, sopId, choices, 0), true)
    let cleared = match (itemById(store.state.value(), sopId)) {
        case Some(item) => item.areaId.isNone()
        case None => false
    }
    @Expect(cleared, true)
    // Out-of-range indexes are rejected without touching the store.
    @Expect(commitSopAreaChoice(store, sopId, choices, choices.size), false)
}

@Test
func selectionStopsAtTheListEdges(): Unit {
    let state = SopViewState(State<Int64>(0))
    let count: Int64 = 4
    @Expect(moveSopAreaSelection(state, count, -1), Int64(0))
    @Expect(moveSopAreaSelection(state, count, 1), Int64(1))
    @Expect(moveSopAreaSelection(state, count, 99), Int64(3))
    @Expect(moveSopAreaSelection(state, count, 1), Int64(3))
}

@Test
func popupStaysInsideTheWindowAndFlipsAbove(): Unit {
    let anchor = Rect(700.0, 300.0, 200.0, 36.0)
    let popup = sopAreaPopupLayout(anchor, 1440.0, 900.0, 4, 2)
    @Expect(popup.visible, Int64(4))
    @Expect(popup.rect.y >= 8.0, true)
    @Expect(popup.rect.bottom() <= 892.0, true)
    // The window follows the selected row: index 2 must be inside [first, first+visible).
    @Expect(popup.first <= 2, true)
    @Expect(2 < popup.first + popup.visible, true)
    // Clicking the middle row resolves to the right choice index.
    let rowY = popup.rect.y + 4.0 + 30.0 * 1.5
    @Expect(popup.rowAt(rowY).getOrThrow(), Int64(popup.first + 1))
    // Near the bottom edge there is no room below: the list flips above the field.
    let low = Rect(700.0, 580.0, 200.0, 36.0)
    let flipped = sopAreaPopupLayout(low, 1440.0, 640.0, 8, 6)
    @Expect(flipped.rect.bottom() <= low.y, true)
    @Expect(flipped.rect.y >= 8.0, true)
    // 右边缘的字段：整块面板被夹在窗口内，不会跑到屏幕外（真机「列表出现在侧栏」的另一半原因）。
    let rightEdge = Rect(1380.0, 300.0, 50.0, 36.0)
    let clamped = sopAreaPopupLayout(rightEdge, 1440.0, 900.0, 3, 0)
    @Expect(clamped.rect.right() <= 1432.0, true)
    @Expect(clamped.rect.x >= 8.0, true)
    @Expect(clamped.rect.w >= SOP_AREA_POPUP_MIN_W, true)
    // 面板外的点（含触发的字段本身）解析为「没有命中行」。
    @Expect(clamped.rowAt(clamped.rect.x - 1.0, clamped.rect.y + 10.0).isNone(), true)
    @Expect(clamped.rowAt(clamped.rect.centerX(), clamped.rect.bottom() + 1.0).isNone(), true)
}

// ---------------------------------------------------------------- 真机事件路径

private let AREA_CONTENT_LEFT: Float32 = 264.0
private let AREA_CONTENT_TOP: Float32 = 80.0
private let AREA_VIEWPORT: Rect = Rect(0.0, 0.0, 1440.0, 900.0)
private let AREA_TODAY: String = "2026-01-01"
private let AREA_ANCHOR: Int64 = 1773626400000
private let AREA_HOME: String = "/tmp/textura-sop-area-test-home"

/** 与 shell 内容区等价的一帧：页面拿到的 layout 矩形是 (264, 80, 1152, 796)。 */
private class AreaHarness {
    let store: AppStore
    let viewCtx: ViewContext
    let tokens: ThemeTokens
    let theme: Theme
    var state: ?SopViewState = None
    /** 本帧的页面 widget（兜底守卫用例要直接调它的 `handle`）。 */
    var page: ?SopPageWidget = None
    /**
     * 这一帧的视口。默认 1440×900（与参考图一致，检查器内容刚好放得下 → 滚不动）；
     * 「锚点跟着滚动走」的用例必须传矮窗口，否则 `clampInspectorScroll` 会把滚动量夹回 0，
     * 字段根本不会移动（见 `areaPopupAnchorFollowsTheScrolledField`）。
     */
    let viewport: Rect

    init(viewportHeight!: Float32 = 900.0) {
        try {
            setVariable("HOME", AREA_HOME)
        } catch (_: Exception) {
            ()
        }
        let clock = FixedClock(AREA_ANCHOR)
        this.store = AppStore(clock: clock)
        store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
        store.setRoute("sop")
        this.viewCtx = ViewContext(store, "light", AREA_TODAY, 1440, 900, {_ => ()})
        this.tokens = tokensOf(texturaLight())
        this.theme = tokens.theme()
        this.viewport = Rect(0.0, 0.0, AREA_VIEWPORT.w, viewportHeight)
    }

    func build(testHost: WidgetTestHost, events!: Array<UiEvent> = []): Unit {
        let _ = testHost.frame(viewport, events: events) {
            =>
                VStack(spacing: vp(0.0)) {
                    let generation = rememberState<Int64>("sop-generation") {0}
                    let state = remember<SopViewState>("sop-view-state") {SopViewState(generation)}
                    let _ = generation.value
                    this.state = state
                    let created = SopPageWidget(store.state.value(), store, theme, tokens, state, AREA_TODAY, 1440, 900)
                    this.page = created
                    sopPromptDialog(theme, store, state)
                    FocusOnceView(state.promptFocus)
                }
                    .hug()
                    .padding(AREA_CONTENT_LEFT, AREA_CONTENT_TOP, 24.0, 24.0)
        }
    }

    func frameOf(testHost: WidgetTestHost): ?SopFrame {
        match (state) {
            case Some(value) =>
                Some(
                    buildFrame(testHost.context, store.state.value(), store, theme, tokens, value, value.pageRect,
                        AREA_TODAY)
                )
            case None => None
        }
    }

    func stateOrFail(): SopViewState {
        match (state) {
            case Some(value) => value
            case None =>
                @Expect("a SOP view state", "none")
                SopViewState(State<Int64>(0))
        }
    }
}

/** 打开下拉：点检查器里画出来的 Area 字段（走 `handleSopSettings` 的同一条命中路径）。 */
private func openAreaThroughThePage(harness: AreaHarness, testHost: WidgetTestHost): Rect {
    let view = match (harness.frameOf(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return Rect.zero()
    }
    let rects = inspectorRects(testHost.context, view)
    harness.build(testHost, events: [
        UiEvent.MouseDown(MouseButton.Left, rects.areaInput.centerX(), rects.areaInput.centerY())
    ])
    rects.areaInput
}

private func storedAreaId(store: AppStore, sopId: String): ?String {
    match (itemById(store.state.value(), sopId)) {
        case Some(item) => item.areaId
        case None => Some("missing")
    }
}

/**
 * 浮层必须在 **layout** 登记：同一帧（build → layout → 事件）里按下候选行就要写回。
 * 旧实现把 `setOverlay` 放在 draw，事件派发时栈里没有它，这一下会落到底下的画布上。
 */
@Test
func areaPickerCommitsARowThroughTheOverlayRegisteredInLayout(): Unit {
    let harness = AreaHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let anchor = openAreaThroughThePage(harness, testHost)
    let state = harness.stateOrFail()
    @Expect(state.areaOpen, true)
    @Expect(state.areaAnchor.x, anchor.x)
    @Expect(state.areaAnchor.y, anchor.y)
    @Expect(testHost.context.overlayCount() > 0, true)
    let popup = match (state.areaPopup) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out area popup", "none")
            return
    }
    // 选「运营」（第二块领域 = 候选下标 2）：按在它那一行的中心。
    let rowIndex = Int64(2) - popup.first
    @Expect(rowIndex >= 0 && rowIndex < popup.visible, true)
    let row = popup.rowRect(rowIndex)
    let workspace = harness.store.state.value()
    let sopId = firstSopId(workspace)
    harness.build(testHost, events: [
        UiEvent.MouseDown(MouseButton.Left, row.centerX(), row.centerY()),
        UiEvent.MouseUp(MouseButton.Left, row.centerX(), row.centerY())
    ])
    @Expect(state.areaOpen, false)
    @Expect(storedAreaId(harness.store, sopId).getOrThrow(), workspace.areas[1].id)
}

/** 面板外的按下：关闭、不写回；同一帧也不会穿透到画布选中节点。 */
@Test
func areaPickerOutsidePressClosesWithoutWritingNorReachingTheCanvas(): Unit {
    let harness = AreaHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let _ = openAreaThroughThePage(harness, testHost)
    let state = harness.stateOrFail()
    let view = match (harness.frameOf(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let before = storedAreaId(harness.store, firstSopId(harness.store.state.value()))
    // 画布上第一个节点的中心：旧实现（浮层收不到事件）这一下会 `stateSelectNode`。
    let node = view.nodes[0]
    let nodeRect = view.nodeRect(node)
    @Expect(state.selectedNodeId.isNone(), true)
    harness.build(testHost, events: [
        UiEvent.MouseDown(MouseButton.Left, nodeRect.centerX(), nodeRect.centerY())
    ])
    @Expect(state.areaOpen, false)
    @Expect(state.selectedNodeId.isNone(), true)
    @Expect(state.selectedEdgeId.isNone(), true)
    @Expect(storedAreaId(harness.store, firstSopId(harness.store.state.value())), before)
}

/** 再次点触发字段 = 关闭（面板不覆盖字段本身，所以这一下解析成「外部」）。 */
@Test
func areaPickerTriggerPressTogglesTheListClosed(): Unit {
    let harness = AreaHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let anchor = openAreaThroughThePage(harness, testHost)
    let state = harness.stateOrFail()
    @Expect(state.areaOpen, true)
    harness.build(testHost, events: [
        UiEvent.MouseDown(MouseButton.Left, anchor.centerX(), anchor.centerY())
    ])
    @Expect(state.areaOpen, false)
}

/** Esc 关闭且不写回；Up/Down 在候选里移动（到边界即停）。 */
@Test
func areaPickerEscapeClosesAndArrowsMoveTheSelection(): Unit {
    let harness = AreaHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let _ = openAreaThroughThePage(harness, testHost)
    let state = harness.stateOrFail()
    let before = storedAreaId(harness.store, firstSopId(harness.store.state.value()))
    let start = state.areaIndex
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Down, false)])
    @Expect(state.areaOpen, true)
    @Expect(state.areaIndex >= start, true)
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Escape, false)])
    @Expect(state.areaOpen, false)
    @Expect(storedAreaId(harness.store, firstSopId(harness.store.state.value())), before)
}

/**
 * 检查器滚动后锚点跟着字段走：弹层顶边 = 字段底边 + 4（或翻到上方），不会留在旧位置。
 *
 * 用 **560px 矮窗口**：1440×900 下 SOP 设置的内容正好放得下（参考图就是完整可见的那一屏），
 * `inspectorMaxScroll` == 0，`clampInspectorScroll` 会把请求的 40px 夹回 0 —— 字段本来就不动，
 * 旧断言在那里只测到夹取逻辑。矮窗口下 body 真的溢出：先把检查器滚到「还能回滚 40px」的位置，
 * 让 Area 字段进入可见 body，打开弹层，再滚到上限，字段与弹层必须同期上移 40px。
 */
@Test
func areaPopupAnchorFollowsTheScrolledField(): Unit {
    let harness = AreaHarness(viewportHeight: 560.0)
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let view = match (harness.frameOf(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let state = harness.stateOrFail()
    // 前提：这个窗口下检查器确实能滚 40px（否则下面的位移断言没有意义）。
    let limit = inspectorMaxScroll(testHost.context, view)
    @Expect(limit >= 40.0, true)
    // 矮窗口下 Area 字段在首屏之外：把它滚进可见 body，并留出「再上滚 40px」的余量
    // （滚太多会把字段顶到 body 上沿之外，`syncSopAreaAnchor` 会判定字段不可见而关闭弹层）。
    let base = inspectorRects(testHost.context, view)
    let lowest = base.areaInput.y - base.body.y - 48.0
    let start = clampF32(lowest, 0.0, limit - 40.0)
    state.inspectorScroll = start
    state.touch()
    harness.build(testHost)
    let rects = inspectorRects(testHost.context, view, scroll: state.inspectorScroll)
    let visible = rects.body.intersection(rects.areaInput)
    @Expect(visible.w > 0.0 && visible.h > 0.0, true)
    @Expect(visible.h >= rects.areaInput.h - 0.5, true)
    openSopAreaPicker(state, rects.areaInput, sopAreaChoices(view.workspace), view.sop.getOrThrow().areaId)
    state.touch()
    harness.build(testHost)
    let before = match (state.areaPopup) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out area popup", "none")
            return
    }
    @Expect(state.areaOpen, true)
    // 再滚 40px：字段与弹层一起上移。
    state.inspectorScroll = state.inspectorScroll + 40.0
    state.touch()
    harness.build(testHost)
    let after = match (state.areaPopup) {
        case Some(value) => value
        case None =>
            @Expect("a re-laid-out area popup", "none")
            return
    }
    @Expect(state.areaOpen, true)
    @Expect(after.rect.y, before.rect.y - 40.0)
    // 锚点就是新的字段矩形（不是页面局部坐标、也不是零矩形）。
    let scrolled = inspectorRects(testHost.context, view, scroll: state.inspectorScroll).areaInput
    @Expect(state.areaAnchor.y, scrolled.y)
    @Expect(after.rect.y >= 8.0, true)
    @Expect(after.rect.bottom() <= harness.viewport.h - 8.0, true)
}

/**
 * 页面兜底：即使浮层这一帧没登记上，`areaOpen` 期间的指针事件也不会落到画布。
 */
@Test
func pageSwallowsPointerPressesWhileTheAreaListIsOpen(): Unit {
    let harness = AreaHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let _ = openAreaThroughThePage(harness, testHost)
    let state = harness.stateOrFail()
    let page = match (harness.page) {
        case Some(value) => value
        case None =>
            @Expect("a SOP page widget", "none")
            return
    }
    let view = match (harness.frameOf(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let nodeRect = view.nodeRect(view.nodes[0])
    @Expect(state.areaOpen, true)
    @Expect(page.handle(testHost.context, UiEvent.MouseDown(MouseButton.Left, nodeRect.centerX(), nodeRect.centerY())),
        true)
    @Expect(state.selectedNodeId.isNone(), true)
    // 关闭后同一坐标恢复成画布的：证明「吞掉」只属于弹层打开期间。
    state.areaOpen = false
    let _ = page.handle(testHost.context, UiEvent.MouseDown(MouseButton.Left, nodeRect.centerX(), nodeRect.centerY()))
    @Expect(state.selectedNodeId.isSome(), true)
}
