package textura.views.sop

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
