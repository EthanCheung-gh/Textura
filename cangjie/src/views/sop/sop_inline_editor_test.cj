package textura.views.sop

import std.collection.ArrayList
import std.env.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*
import textura.ui.{FocusOnceView, ThemeTokens, tokensOf, texturaLight, vp}

/*
 * SOP 检查器里的原位编辑器：点检查器画出来的「输入框」，真控件必须落在**那个盒子**上。
 *
 * 检查器是画布自绘的（`sop_inspector.cj` 用 `paintInputBox` 画框），字段矩形只有 `layout`
 * 阶段算得出来（`inspectorRects`），而编辑器是构建期通过 `Portal` 摆放的。两者之间的唯一
 * 桥梁是 `SopViewState.promptAnchor`（跨帧锚点，窗口绝对坐标）。
 *
 * 断言口径与 OKR/GTD 完全一致：用语义节点的**绝对 bounds** 对字段矩形，而不是编辑器自己的
 * 返回值；并把「窗口绝对坐标」写死（内容区原点 = 侧栏 240 + 内边距 24 = 264，顶栏 56 + 24 = 80），
 * 这样「编辑器跑到窗口左上角」这条真机故障一定会红。
 */
private let SOP_EDITOR_CONTENT_LEFT: Float32 = 264.0
private let SOP_EDITOR_CONTENT_TOP: Float32 = 80.0
private let SOP_EDITOR_TODAY: String = "2026-01-01"
private let SOP_EDITOR_ANCHOR: Int64 = 1773626400000
private let SOP_EDITOR_HOME: String = "/tmp/textura-sop-inline-test-home"

private class SopEditorHarness {
    let store: AppStore
    let viewCtx: ViewContext
    let tokens: ThemeTokens
    let theme: Theme
    var state: ?SopViewState = None
    /** 这一帧用的视口（滚动用例要用矮窗口，检查器内容才会溢出、才滚得动）。 */
    let viewport: Rect

    init(viewportHeight!: Float32 = 900.0) {
        try {
            setVariable("HOME", SOP_EDITOR_HOME)
        } catch (_: Exception) {
            ()
        }
        let clock = FixedClock(SOP_EDITOR_ANCHOR)
        this.store = AppStore(clock: clock)
        store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
        store.setRoute("sop")
        this.viewCtx = ViewContext(store, "light", SOP_EDITOR_TODAY, 1440, 900, {_ => ()})
        this.tokens = tokensOf(texturaLight())
        this.theme = tokens.theme()
        this.viewport = Rect(0.0, 0.0, 1440.0, viewportHeight)
    }

    /**
     * 与 shell 内容区等价的一帧：`render(viewCtx)` 放在 `padding(264, 80, 24, 24)` 里，
     * 页面拿到的 layout 矩形就是 (264, 80, 1152, 796)，与真机一致。
     *
     * 视图状态在 render 之前先按**同样的 key**取一次（`remember` 是幂等的），
     * 这样测试拿到的就是 `render` 内部用的那份 `SopViewState`。
     *
     * 注意：这里只复刻**组合形状不变**的一帧。真机上「write → autosave 窗口 → 壳给 body 多套
     * 一层 `FrameHandler` → `remember` 键跟着变 → 状态壳重建」那一步无法在 `WidgetTestHost`
     * 里稳定复刻（宿主会重放整棵子树，body 不一定重跑），所以那一步由
     * `sopNodeInspectorSurvivesALostStateShell` 直接构造一个全新的 `SopViewState` 来钉住。
     */
    func build(testHost: WidgetTestHost, events!: Array<UiEvent> = []): Unit {
        let _ = testHost.frame(viewport, events: events) {
            =>
                VStack(spacing: vp(0.0)) {
                    // `sop.cj` 的 `render` 正文，逐行照抄：`remember` 的作用域按容器划分，
                    // 从外面先取一次会拿到**另一个** `SopViewState`（不同 scope ⇒ 不同 key 路径）。
                    let generation = rememberState<Int64>("sop-generation") {0}
                    let state = remember<SopViewState>("sop-view-state") {SopViewState(generation)}
                    let _ = generation.value
                    this.state = state
                    SopPageWidget(store.state.value(), store, theme, tokens, state, SOP_EDITOR_TODAY, 1440, 900)
                    sopPromptDialog(theme, store, state)
                    FocusOnceView(state.promptFocus)
                }
                    .hug()
                    .padding(SOP_EDITOR_CONTENT_LEFT, SOP_EDITOR_CONTENT_TOP, 24.0, 24.0)
        }
    }

    /** 当前页面的 `SopFrame`（与 `paintInspector` 用同一套公式）。 */
    func frame(testHost: WidgetTestHost): ?SopFrame {
        match (state) {
            case Some(value) =>
                Some(
                    buildFrame(testHost.context, store.state.value(), store, theme, tokens, value, value.pageRect,
                        SOP_EDITOR_TODAY)
                )
            case None => None
        }
    }
}

private func sopEditorBoundsOf(testHost: WidgetTestHost, key: String): Rect {
    var bounds = Rect(0.0, 0.0, -1.0, -1.0)
    for (node in testHost.context.semanticsSnapshot()) {
        if (node.id == key) {
            bounds = node.bounds
        }
    }
    bounds
}

private func sopRectText(rect: Rect): String {
    "x=${rect.x} y=${rect.y} w=${rect.w} h=${rect.h}"
}

/** 检查器里「名称」输入框：点它 → 编辑器必须正好压在它上面，并且是窗口绝对坐标。 */
@Test
func sopInspectorFieldEditorSitsOnTheFieldRectangle(): Unit {
    let harness = SopEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let view = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let rects = inspectorRects(testHost.context, view)
    // 内容区偏移已经在画布坐标里：名称框一定在页面右栏（x ≥ 264）。
    @Expect(rects.nameInput.x >= SOP_EDITOR_CONTENT_LEFT, true)
    @Expect(rects.nameInput.y >= SOP_EDITOR_CONTENT_TOP, true)
    let handled = handleSopSettings(view, rects, rects.nameInput.centerX(), rects.nameInput.centerY())
    harness.build(testHost)
    @Expect(handled, true)
    @Expect(sopRectText(sopEditorBoundsOf(testHost, SOP_PROMPT_INPUT)), sopRectText(rects.nameInput))
}

/** 检查器内部滚动：字段上移多少，编辑器跟着上移多少（`trackSopPrompt` 的每帧写回）。 */
@Test
func sopInspectorEditorFollowsTheScrolledField(): Unit {
    // 矮窗口（560px 高）让检查器 body 真的溢出，`inspectorScroll` 才有可滚区间。
    let harness = SopEditorHarness(viewportHeight: 560.0)
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let state = match (harness.state) {
        case Some(value) => value
        case None =>
            @Expect("a SOP view state", "none")
            return
    }
    let view = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let rects = inspectorRects(testHost.context, view)
    @Expect(handleSopSettings(view, rects, rects.nameInput.centerX(), rects.nameInput.centerY()), true)
    harness.build(testHost)
    @Expect(sopRectText(sopEditorBoundsOf(testHost, SOP_PROMPT_INPUT)), sopRectText(rects.nameInput))
    // 检查器 body 滚动 40px（`overflow-y: auto`）：字段与编辑器一起上移 40px。
    state.inspectorScroll = 40.0
    // 滚动偏移是普通字段（CUI 保留图不会因为它变脏），这里显式 `touch()` 让页面重新描述一次；
    // 真机上滚轮事件每帧都会带来一次重排，跑的是同一条 `trackSopPrompt`。
    state.touch()
    harness.build(testHost)
    let scrolled = inspectorRects(testHost.context, view, scroll: state.inspectorScroll).nameInput
    @Expect(sopRectText(sopEditorBoundsOf(testHost, SOP_PROMPT_INPUT)), sopRectText(scrolled))
    @Expect(scrolled.y < rects.nameInput.y, true)
}

/** Esc 取消：不写回（名称保持原值），编辑器消失。 */
@Test
func sopInspectorEditorEscapeKeepsTheStoredValue(): Unit {
    let harness = SopEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let view = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let rects = inspectorRects(testHost.context, view)
    @Expect(handleSopSettings(view, rects, rects.nameInput.centerX(), rects.nameInput.centerY()), true)
    harness.build(testHost)
    let state = match (harness.state) {
        case Some(value) => value
        case None =>
            @Expect("a SOP view state", "none")
            return
    }
    // 打开时草稿就是当前名称（编辑器与 store 一致）。
    @Expect(state.promptText.value, view.sop.getOrThrow().title)
    state.promptText.value = "改坏的名字"
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Escape, false)])
    @Expect(state.promptOpen.value, false)
    @Expect(sopEditorBoundsOf(testHost, SOP_PROMPT_INPUT).w < 0.0, true)
    // 取消不改数据：store 里的 SOP 名称仍是原值。
    let active = view.sop.getOrThrow()
    var stored = ""
    for (item in harness.store.state.value().items) {
        if (item.id == active.id) {
            stored = item.title
        }
    }
    @Expect(stored, active.title)
}

/** 保存后立刻点下一个字段：这一下必须当场打开（真机现场：提交后第一下点击被吞掉）。 */
@Test
func sopInspectorNextFieldOpensRightAfterCommit(): Unit {
    let harness = SopEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let state = match (harness.state) {
        case Some(value) => value
        case None =>
            @Expect("a SOP view state", "none")
            return
    }
    let view = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let rects = inspectorRects(testHost.context, view)
    harness.build(testHost, events: [
        UiEvent.MouseDown(MouseButton.Left, rects.nameInput.centerX(), rects.nameInput.centerY())
    ])
    @Expect(state.promptOpen.value, true)
    @Expect(state.promptKind.value, "sop-title")
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Enter, false)])
    @Expect(state.promptOpen.value, false)
    harness.build(testHost, events: [
        UiEvent.MouseDown(MouseButton.Left, rects.notesArea.centerX(), rects.notesArea.centerY())
    ])
    @Expect(state.promptOpen.value, true)
    @Expect(state.promptKind.value, "sop-notes")
}

/* ---------------- 节点检查器：改一次字段不许被踢回「SOP 设置」 ---------------- */

private func sopPress(x: Float32, y: Float32): Array<UiEvent> {
    [
        UiEvent.MouseDown(MouseButton.Left, x, y),
        UiEvent.MouseUp(MouseButton.Left, x, y)
    ]
}

private func sopIsNodeVariant(rects: SopInspRects): Bool {
    match (rects.variant) {
        case SopInspVariant.Node => true
        case _ => false
    }
}

private func sopSelectedNodeId(state: SopViewState): String {
    match (state.selectedNodeId) {
        case Some(id) => id
        case None => "<none>"
    }
}

/** 画布上第一个节点的中心（真实按下点，走 `handleCanvas` 的命中判定）。 */
private func sopFirstNodeCenter(view: SopFrame): (String, Float32, Float32) {
    let item = view.nodes[0]
    let rect = view.nodeRect(item)
    (item.id, rect.centerX(), rect.centerY())
}

/** 画布 flow 区的左下角：一定没有节点/连线，且落在 `view.flow` 内（不是检查器）。 */
private func sopBlankPanePoint(view: SopFrame): (Float32, Float32) {
    (view.flow.x + 3.0, view.flow.bottom() - 3.0)
}

private func sopItemTitle(store: AppStore, id: String): String {
    match (itemById(store.state.value(), id)) {
        case Some(item) => item.title
        case None => "<missing>"
    }
}

/**
 * 选中节点 → 点「标题」→ 输入 → Enter（一次 store 写入）→ 检查器必须仍停在该节点。
 *
 * 真机现场：节点检查器里改一个字段，右侧立刻跳回「SOP 设置」变体（标题变「流程设置」）。
 * 变体只有一条判据（`inspectorRects` 看 `selectedNode()`），所以这条用例同时钉住
 * 「`selectedNodeId` 还在」与「`nodes` 里还能按 id 找到那个节点」。
 */
@Test
func sopNodeInspectorStaysOnTheNodeAfterAFieldCommit(): Unit {
    let harness = SopEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let state = match (harness.state) {
        case Some(value) => value
        case None =>
            @Expect("a SOP view state", "none")
            return
    }
    let first = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let (nodeId, nodeX, nodeY) = sopFirstNodeCenter(first)
    // 真实链路：点画布上的节点（`handleCanvas` → `stateSelectNode`）。
    harness.build(testHost, events: sopPress(nodeX, nodeY))
    @Expect(sopSelectedNodeId(state), nodeId)
    let view = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let rects = inspectorRects(testHost.context, view)
    @Expect(sopIsNodeVariant(rects), true)
    // 点「标题」→ 原位编辑器打开在字段上。
    harness.build(testHost, events: sopPress(rects.titleInput.centerX(), rects.titleInput.centerY()))
    @Expect(state.promptOpen.value, true)
    @Expect(state.promptKind.value, "node-title")
    @Expect(state.promptTarget.value, nodeId)
    // 输入并提交（一次 store 写入）。
    state.promptText.value = "逐条核对告警"
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Enter, false)])
    @Expect(state.promptOpen.value, false)
    @Expect(sopItemTitle(harness.store, nodeId), "逐条核对告警")
    // 提交之后的下一帧：选中项与检查器变体都不许变。
    harness.build(testHost)
    @Expect(sopSelectedNodeId(state), nodeId)
    let after = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let afterRects = inspectorRects(testHost.context, after)
    @Expect(sopIsNodeVariant(afterRects), true)
    let painted = match (after.selectedNode()) {
        case Some(item) => item.title
        case None => "<none>"
    }
    @Expect(painted, "逐条核对告警")
    // 节点变体才有这些盒子；SOP 设置变体给的是 `Rect.zero()`。
    @Expect(afterRects.titleInput.w > 0.0, true)
    @Expect(afterRects.typeChips.isEmpty(), false)
}

/**
 * 提交后**紧接着**点同一检查器里的下一个字段：仍打开编辑器、仍停在节点变体。
 *
 * 这是真机现象的第二半：即使选中项还在，提交后第一下点击若被画布空白吃掉，编辑器就不会出现。
 */
@Test
func sopNodeInspectorNextFieldStillOpensAfterCommit(): Unit {
    let harness = SopEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let state = match (harness.state) {
        case Some(value) => value
        case None =>
            @Expect("a SOP view state", "none")
            return
    }
    let first = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let (nodeId, nodeX, nodeY) = sopFirstNodeCenter(first)
    harness.build(testHost, events: sopPress(nodeX, nodeY))
    let view = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let rects = inspectorRects(testHost.context, view)
    harness.build(testHost, events: sopPress(rects.titleInput.centerX(), rects.titleInput.centerY()))
    state.promptText.value = "重新排队"
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Enter, false)])
    @Expect(state.promptOpen.value, false)
    // 提交后立刻点「负责人」：这一下必须当场打开，并且目标还是这个节点。
    harness.build(testHost, events: sopPress(rects.ownerInput.centerX(), rects.ownerInput.centerY()))
    @Expect(state.promptOpen.value, true)
    @Expect(state.promptKind.value, "node-owner")
    @Expect(state.promptTarget.value, nodeId)
    @Expect(sopSelectedNodeId(state), nodeId)
    let after = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    @Expect(sopIsNodeVariant(inspectorRects(testHost.context, after)), true)
}

/**
 * 提交后点**画布空白**：这时才允许清空选中、回到「SOP 设置」。
 *
 * 与上面两条互为正反面：修复不能把「点空白取消选中」一起改掉。
 */
@Test
func sopNodeInspectorBlankCanvasStillClearsTheSelection(): Unit {
    let harness = SopEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let state = match (harness.state) {
        case Some(value) => value
        case None =>
            @Expect("a SOP view state", "none")
            return
    }
    let first = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let (_, nodeX, nodeY) = sopFirstNodeCenter(first)
    harness.build(testHost, events: sopPress(nodeX, nodeY))
    let view = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let rects = inspectorRects(testHost.context, view)
    harness.build(testHost, events: sopPress(rects.titleInput.centerX(), rects.titleInput.centerY()))
    state.promptText.value = "先改一次"
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Enter, false)])
    @Expect(sopSelectedNodeId(state) == "<none>", false)
    let (blankX, blankY) = sopBlankPanePoint(view)
    harness.build(testHost, events: sopPress(blankX, blankY))
    @Expect(sopSelectedNodeId(state), "<none>")
    let after = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    @Expect(sopIsNodeVariant(inspectorRects(testHost.context, after)), false)
}

/**
 * 编辑提交后其它节点的 id 不许漂移：检查器按 id 找回节点，id 一变就必然跳回整体设置。
 */
@Test
func sopNodeInspectorCommitKeepsEveryNodeId(): Unit {
    let harness = SopEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let state = match (harness.state) {
        case Some(value) => value
        case None =>
            @Expect("a SOP view state", "none")
            return
    }
    let first = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let before = ArrayList<String>()
    for (item in first.nodes) {
        before.add(item.id)
    }
    let (nodeId, nodeX, nodeY) = sopFirstNodeCenter(first)
    harness.build(testHost, events: sopPress(nodeX, nodeY))
    let view = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let rects = inspectorRects(testHost.context, view)
    harness.build(testHost, events: sopPress(rects.titleInput.centerX(), rects.titleInput.centerY()))
    state.promptText.value = "换一个说法"
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Enter, false)])
    let after = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    @Expect("${after.nodes.size}", "${before.size}")
    var index = 0
    for (item in after.nodes) {
        @Expect(item.id, before[index])
        index += 1
    }
    @Expect(sopSelectedNodeId(state), nodeId)
}

/**
 * 真机那条链路：提交一次字段（= 一次 store 写入）之后，**状态壳被重建**，检查器必须仍停在该节点。
 *
 * 为什么状态壳会被重建（不是猜的，宿主侧两次探针）：
 * 1. `appshell.cj` 在 `runtime.needsTick(store)` 为真时把整个 body 包进一层 `FrameHandler`，
 *    而任何一次 store 写入都会让 `observeWorkspace` 把 `savePhase` 置成 `saving`
 *    （探针：`updateItem` 后 `needsTick` false → true）；
 * 2. CUI 的 `remember` 键 = 组合祖先作用域 + key（`automatic_composition.cj` 的
 *    `@VStack[1]` 逐层拼进 `scopedKey`），祖先多一段就换一个 `State`
 *    （探针：body 多包一层 FrameHandler 后，remember 的计数器 6 → 3，即重新从 0 开始）。
 *
 * 于是 `sop-view-state` 解析成另一个 `State`，`SopViewState` 全新构造、`selectedNodeId` 归零，
 * `inspectorRects` 找不到 `selectedNode()`，右侧从「节点」跳回「SOP 设置」——真机现象。
 *
 * 这里直接复刻「壳没了」这一步（宿主里套 FrameHandler 不能稳定复刻，见 `build` 的注释）：
 * 一个全默认的新 `SopViewState` 重新描述页面，断言选中项从 store 补了回来。
 */
@Test
func sopNodeInspectorSurvivesALostStateShell(): Unit {
    let harness = SopEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let state = match (harness.state) {
        case Some(value) => value
        case None =>
            @Expect("a SOP view state", "none")
            return
    }
    let first = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let (nodeId, nodeX, nodeY) = sopFirstNodeCenter(first)
    harness.build(testHost, events: sopPress(nodeX, nodeY))
    let view = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let rects = inspectorRects(testHost.context, view)
    harness.build(testHost, events: sopPress(rects.titleInput.centerX(), rects.titleInput.centerY()))
    @Expect(state.promptKind.value, "node-title")
    state.promptText.value = "按区域回访"
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Enter, false)])
    @Expect(sopItemTitle(harness.store, nodeId), "按区域回访")
    // 壳被重建：全新 `SopViewState`（全默认值，等价于 remember 换了 key 之后的那一个）。
    let lost = SopViewState(State<Int64>(0))
    @Expect(lost.selectedNodeId.isNone(), true)
    @Expect("${lost.runSeq}", "0")
    @Expect(lost.inspectorOpen, true)
    let rebuilt = buildFrame(testHost.context, harness.store.state.value(), harness.store, harness.theme,
        harness.tokens, lost, view.pageRect(), SOP_EDITOR_TODAY)
    // 选中项没跟着状态壳一起丢：真源在 store（`stateSelectNode` 早就写过）。
    @Expect(sopSelectedNodeId(lost), nodeId)
    let rebuiltRects = inspectorRects(testHost.context, rebuilt)
    @Expect(sopIsNodeVariant(rebuiltRects), true)
    let painted = match (rebuilt.selectedNode()) {
        case Some(item) => item.title
        case None => "<none>"
    }
    @Expect(painted, "按区域回访")
    // 新壳上的检查器照常可编辑：点「负责人」当场打开，目标仍是这个节点。
    @Expect(handleInspector(testHost.context, rebuilt, UiEvent.MouseDown(MouseButton.Left,
        rebuiltRects.ownerInput.centerX(), rebuiltRects.ownerInput.centerY())), true)
    @Expect(lost.promptOpen.value, true)
    @Expect(lost.promptKind.value, "node-owner")
    @Expect(lost.promptTarget.value, nodeId)
    closeSopPrompt(lost)
}

/**
 * 反方向：用户点了画布空白（`store.select(None)`）之后，状态壳重建**不许**把选中项复活。
 * 修复只补「状态壳被重建」丢的那一份，不改变用户明确的取消。
 */
@Test
func sopClearedSelectionIsNotResurrectedByALostStateShell(): Unit {
    let harness = SopEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let first = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let (_, nodeX, nodeY) = sopFirstNodeCenter(first)
    harness.build(testHost, events: sopPress(nodeX, nodeY))
    let view = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let (blankX, blankY) = sopBlankPanePoint(view)
    harness.build(testHost, events: sopPress(blankX, blankY))
    let lost = SopViewState(State<Int64>(0))
    let rebuilt = buildFrame(testHost.context, harness.store.state.value(), harness.store, harness.theme,
        harness.tokens, lost, view.pageRect(), SOP_EDITOR_TODAY)
    @Expect(sopSelectedNodeId(lost), "<none>")
    @Expect(sopIsNodeVariant(inspectorRects(testHost.context, rebuilt)), false)
}

/**
 * 类型 chips 与检查项之间的分隔线：线在 chips 下方 `--space-3`（12px），小标题再往下
 * `1px border + 8px padding`。旧实现从加号按钮反推，把线画到 chips 底下 5.5px（压线）。
 */
@Test
func nodeInspectorChecklistRuleSitsBelowTheTypeChips(): Unit {
    let harness = SopEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let state = match (harness.state) {
        case Some(value) => value
        case None =>
            @Expect("a SOP view state", "none")
            return
    }
    let view = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    // 选中第一个节点 → 检查器切到节点变体（类型 chips + 检查项都在这里）。
    state.selectedNodeId = Some(view.nodes[0].id)
    state.selectedEdgeId = None
    state.touch()
    harness.build(testHost)
    let rects = inspectorRects(testHost.context, view)
    let nodeVariant = match (rects.variant) {
        case SopInspVariant.Node => true
        case _ => false
    }
    @Expect(nodeVariant, true)
    @Expect(rects.typeChips.isEmpty(), false)
    var chipsBottom: Float32 = 0.0
    for ((_, chip) in rects.typeChips) {
        if (chip.bottom() > chipsBottom) {
            chipsBottom = chip.bottom()
        }
    }
    // 线严格在 chips 下方，且正好隔 12px（像素对齐允许 1px 抖动）。
    @Expect(rects.checklistRuleY >= chipsBottom + 11.0, true)
    @Expect(rects.checklistRuleY <= chipsBottom + 13.0, true)
    // 小标题 = 线 + 1px 边框 + 8px padding。
    @Expect(rects.checklistLabelY, rects.checklistRuleY + 1.0 + SOP_BLOCK_PAD_TOP)
    // 「+」按钮与标题同一行（命中区仍覆盖标题行）。
    @Expect(rects.addChecklist.centerY() >= rects.checklistLabelY, true)
    @Expect(rects.addChecklist.centerY() <= rects.checklistLabelY + SOP_SECTION_LABEL_LINE, true)
}
/**
 * 滚轮按**鼠标坐标**命中检查器 body、按 `wheelY` 滚动。
 *
 * `UiEvent.MouseWheel` 的载荷顺序是 `(wheelX, wheelY, mouseX, mouseY)`（`cangjie-sdl/src/events.cj`
 * 第 131 行）。如果把前两个当成坐标，浮动窗口下鼠标永远"不在 body 里"，右栏就滚不动——这正是
 * 「检查项被裁切且右栏不可滚动」的现场。
 */
@Test
func sopInspectorWheelUsesPointerCoordinates(): Unit {
    let harness = SopEditorHarness(viewportHeight: 560.0)
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let state = match (harness.state) {
        case Some(value) => value
        case None =>
            @Expect("a SOP view state", "none")
            return
    }
    let view = match (harness.frame(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    let ctx = testHost.context
    let rects = inspectorRects(ctx, view)
    // 矮窗口必须真的溢出，否则这条用例只能证明"没滚"。
    @Expect(inspectorMaxScroll(ctx, view) > 0.0, true)
    let x = rects.body.centerX()
    let y = rects.body.centerY()
    @Expect(handleInspector(ctx, view, UiEvent.MouseWheel(0.0, -1.0, x, y)), true)
    @Expect(state.inspectorScroll > 0.0, true)
    @Expect(state.inspectorScroll <= inspectorMaxScroll(ctx, view), true)
}
