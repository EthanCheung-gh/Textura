package textura.views.okr

import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*
import textura.ui.{vp}
import textura.views.okr.logic.{MetricField}

/*
 * 独立编辑页（P1+P2）的主机回归。
 *
 * 覆盖 `docs/OKR-EDIT-PLAN.md` §4.3 的宿主断言：
 *   1. 编辑页控件都在语义树里且有正宽高（字段可见）；
 *   2. 点铅笔才出现输入；同一时刻只有一个编辑目标（切换自动结束上一处）；
 *   3. Enter / 失焦写 store（标题、负责人、新增 KR）；
 *   4. notes 600ms 防抖：静默够久才写，失焦 / 返回立即 flush；
 *   5. 返回列表后 `editId == ""`，焦点请求指向卡片上的铅笔 `okr-edit-<id>`；
 *   6. 目标不存在 / 被删除 → 空态 + 返回按钮。
 *
 * 走的是 `okrView(ctx, ui)`（`render` 的唯一分支点），因此列表 / 编辑页的切换与真实路径一致。
 */

private let EDITOR_VIEWPORT: Rect = Rect(0.0, 0.0, 1440.0, 900.0)
private let EDITOR_ANCHOR: Int64 = 1773626400000

private class OkrEditorHarness {
    let host = WidgetTestHost()
    let store: AppStore
    let viewCtx: ViewContext
    let objectiveId: String
    var ui: ?OkrUiState = None

    init(openAtTarget!: String = "") {
        let clock = FixedClock(EDITOR_ANCHOR)
        this.store = AppStore(clock: clock)
        store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
        store.setRoute("okr")
        this.viewCtx = ViewContext(store, "light", "2026-01-01", 1440, 900, {_ => ()})
        this.objectiveId = okrFirstObjectiveOf(store)
        // 一帧列表态：`okrUiState()` 的 State 在这一帧登记，之后才能在事件阶段读它。
        this.frame()
        openOkrEditor(this.stateOrFail(), store, objectiveId, openAtTarget)
        this.frame()
    }

    func frame(events!: Array<UiEvent> = [], elapsedMs!: Int64 = 0): Unit {
        let _ = host.frame(EDITOR_VIEWPORT, elapsedMs: UInt64(elapsedMs), events: events) {
            =>
                VStack(spacing: vp(0.0)) {
                    let ui = okrUiState()
                    this.ui = ui
                    okrView(viewCtx, ui)
                }
                    .hug()
                    .padding(264.0, 80.0, 24.0, 24.0)
        }
    }

    func stateOrFail(): OkrUiState {
        match (ui) {
            case Some(value) => value
            case None => okrUiState()
        }
    }

    /** 当前目标在画布数据里的条目（`okrEditorEscape` 的输入）。 */
    func entryOrFail(): OkrObjEntry {
        let workspace = store.state.value()
        let fallback = quarterOfDate(okrToday(viewCtx.today))
        match (buildOkrEditorData(workspace, objectiveId, viewCtx.today, fallback)) {
            case Some(value) => value.entry
            case None =>
                @Expect("an editor entry", "none")
                OkrObjEntry(Item(objectiveId, ItemKind.Objective, ""), 0, 5, [], 0, Option<Area>.None)
        }
    }

    /** 语义节点（按 id）。 */
    func node(id: String): ?SemanticsNode {
        for (node in host.context.semanticsSnapshot()) {
            if (node.id == id) {
                return Some(node)
            }
        }
        None
    }

    /** 语义节点（按标签）。 */
    func nodeByLabel(label: String): ?SemanticsNode {
        for (node in host.context.semanticsSnapshot()) {
            if (node.properties.label == label) {
                return Some(node)
            }
        }
        None
    }

    /** 像用户一样点一下（按下 + 抬起同帧），随后再走一帧让状态落地。 */
    func click(rect: Rect): Unit {
        let x = rect.centerX()
        let y = rect.centerY()
        frame(events: [UiEvent.MouseDown(MouseButton.Left, x, y), UiEvent.MouseUp(MouseButton.Left, x, y)])
    }

    func clickNode(id: String): Unit {
        match (node(id)) {
            case Some(value) => click(value.bounds)
            case None => @Expect("node ${id}", "missing")
        }
    }

    func clickLabel(label: String): Unit {
        match (nodeByLabel(label)) {
            case Some(value) => click(value.bounds)
            case None => @Expect("node ${label}", "missing")
        }
    }

    func typeText(text: String): Unit {
        frame(events: [UiEvent.TextInput(text)])
    }

    func pressEnter(): Unit {
        frame(events: [UiEvent.KeyDown(Key.Enter, false)])
    }

    func pressEscape(): Unit {
        frame(events: [UiEvent.KeyDown(Key.Escape, false)])
    }
}

private func okrFirstObjectiveOf(store: AppStore): String {
    for (item in store.state.value().items) {
        if (item.kind == ItemKind.Objective) {
            return item.id
        }
    }
    ""
}

private func okrFirstKeyResultOf(store: AppStore, objectiveId: String): String {
    for (item in store.state.value().items) {
        if (item.kind == ItemKind.KeyResult) {
            match (item.parentId) {
                case Some(parent) => if (parent == objectiveId) {
                    return item.id
                }
                case None => ()
            }
        }
    }
    ""
}

private func okrTitleOf(store: AppStore, id: String): String {
    for (item in store.state.value().items) {
        if (item.id == id) {
            return item.title
        }
    }
    ""
}

private func okrNotesOf(store: AppStore, id: String): String {
    for (item in store.state.value().items) {
        if (item.id == id) {
            return item.notes
        }
    }
    ""
}

private func expectVisible(harness: OkrEditorHarness, label: String): Unit {
    match (harness.nodeByLabel(label)) {
        case Some(node) =>
            @Expect(node.bounds.w > 0.0, true)
            @Expect(node.bounds.h > 0.0, true)
        case None => @Expect("visible node ${label}", "missing")
    }
}

/* ------------------------------------------------------------------ 1. 字段可见 */

/**
 * 编辑页的骨架：顶栏（返回 / 面包屑 / 保存状态）、目标区（标题 / 领域 / 状态 / 信心 / 进度）、
 * KR 区（每条 KR 的铅笔）与目标操作都在语义树里，而且有正宽高。
 */
@Test
func okrEditorShowsTheObjectiveAndItsKeyResults(): Unit {
    let harness = OkrEditorHarness()
    let ui = harness.stateOrFail()
    @Expect(ui.editId.value, harness.objectiveId)
    @Expect(ui.editTarget.value, "")
    expectVisible(harness, "返回目标列表")
    // `quarterLabel()` 的文案是「2026 Q1」（空格，见 `logic/quarter.cj:259`），不是 `2026-Q1`。
    expectVisible(harness, "2026 Q1 · 目标编辑")
    expectVisible(harness, "已保存")
    expectVisible(harness, "整体进度")
    expectVisible(harness, "备注")
    expectVisible(harness, "关键结果 · 3")
    expectVisible(harness, "新增关键结果")
    expectVisible(harness, "移动到其他季度")
    expectVisible(harness, "复制为新季度目标")
    expectVisible(harness, "删除目标")
    // 每条 KR 都有自己的铅笔（默认只有铅笔，没有输入框）。
    let krId = okrFirstKeyResultOf(harness.store, harness.objectiveId)
    @Expect(harness.node(okrEditorKrPencilId(krId)).isSome(), true)
    // 纯展示态：标题输入框不存在。
    @Expect(harness.node(okrEditorTitleId()).isNone(), true)
}

/* -------------------------------------------------------------- 2. 渐进式单编辑态 */

/** 点标题铅笔 → 出现输入框；`editTarget` 变成 `title`。 */
@Test
func okrEditorPencilRevealsTheTitleInput(): Unit {
    let harness = OkrEditorHarness()
    let ui = harness.stateOrFail()
    @Expect(harness.node(okrEditorTitleId()).isNone(), true)
    harness.clickNode(okrEditorPencilId("title"))
    @Expect(ui.editTarget.value, "title")
    match (harness.node(okrEditorTitleId())) {
        case Some(node) =>
            @Expect(node.bounds.w > 0.0, true)
            @Expect(node.bounds.h > 0.0, true)
        case None => @Expect("the title input", "missing")
    }
}

/**
 * 同一时刻只允许一个编辑目标：打开标题后点备注铅笔，标题输入框消失、备注出现，
 * 而且标题的草稿先被提交（「切换自动结束上一处」）。
 */
@Test
func okrEditorKeepsASingleEditTarget(): Unit {
    let harness = OkrEditorHarness()
    let ui = harness.stateOrFail()
    harness.clickNode(okrEditorPencilId("title"))
    harness.typeText("新的目标标题")
    @Expect(ui.editTarget.value, "title")
    harness.clickNode(okrEditorPencilId("notes"))
    @Expect(ui.editTarget.value, "notes")
    @Expect(harness.node(okrEditorTitleId()).isNone(), true)
    @Expect(harness.node(okrEditorNotesId()).isSome(), true)
    // 切走时上一处已经写库。
    @Expect(okrTitleOf(harness.store, harness.objectiveId), "新的目标标题")
    // 再点一次备注铅笔 = 收起（回到纯展示）。
    harness.clickNode(okrEditorPencilId("notes"))
    @Expect(ui.editTarget.value, "")
    @Expect(harness.node(okrEditorNotesId()).isNone(), true)
}

/** KR 行：点铅笔展开该行的完整编辑（标题 / 指标四格 / 负责人），收起后输入框全部消失。 */
@Test
func okrEditorExpandsOneKeyResultAtATime(): Unit {
    let harness = OkrEditorHarness()
    let ui = harness.stateOrFail()
    let krId = okrFirstKeyResultOf(harness.store, harness.objectiveId)
    harness.clickNode(okrEditorKrPencilId(krId))
    @Expect(ui.editTarget.value, okrEditorKrTarget(krId))
    @Expect(harness.node(okrEditorKrTitleId(krId)).isSome(), true)
    @Expect(harness.node(okrEditorOwnerId(krId)).isSome(), true)
    for (field in okrEditorTestFields()) {
        @Expect(harness.node(okrEditorMetricId(krId, field)).isSome(), true)
    }
    harness.clickNode(okrEditorKrPencilId(krId))
    @Expect(ui.editTarget.value, "")
    @Expect(harness.node(okrEditorKrTitleId(krId)).isNone(), true)
}

private func okrEditorTestFields(): Array<MetricField> {
    [
        MetricField.Start,
        MetricField.Current,
        MetricField.Target,
        MetricField.UnitField
    ]
}

/* ------------------------------------------------------------------ 3. 写 store */

/** Enter 立即写：标题输入框里敲字 + 回车 → store 的 title 变化、编辑态收起。 */
@Test
func okrEditorEnterWritesTheTitleToTheStore(): Unit {
    let harness = OkrEditorHarness()
    let ui = harness.stateOrFail()
    harness.clickNode(okrEditorPencilId("title"))
    harness.typeText("季度目标·改")
    harness.pressEnter()
    @Expect(okrTitleOf(harness.store, harness.objectiveId), "季度目标·改")
    @Expect(ui.editTarget.value, "")
}

/**
 * 真机回归 B（`docs/DEVICE-NOTES.md` 本轮）：标题按 Enter 后必须**留在编辑页**。
 *
 * `editId` 是「列表页 / 编辑页」的唯一开关（`okr.cj:37`），所以它是这类「误关闭」的判据：
 * Enter 之后标题已写库、输入框已收起，但页面仍然是编辑页（顶栏「返回目标列表」还在）。
 */
@Test
func okrEditorEnterOnTitleKeepsTheEditorPage(): Unit {
    let harness = OkrEditorHarness()
    let ui = harness.stateOrFail()
    harness.clickNode(okrEditorPencilId("title"))
    harness.typeText("回车提交但不退出")
    harness.pressEnter()
    harness.frame()
    @Expect(okrTitleOf(harness.store, harness.objectiveId), "回车提交但不退出")
    @Expect(ui.editTarget.value, "")
    @Expect(harness.node(okrEditorTitleId()).isNone(), true)
    @Expect(ui.editId.value, harness.objectiveId)
    @Expect(harness.nodeByLabel("返回目标列表").isSome(), true)
}

/**
 * 同一次按键被投递两次（真机上 SDL 原生键回调与输入法确认各来一次）时，
 * 第二个 Enter 也只能落在标题铅笔上——不能把页面关掉。
 */
@Test
func okrEditorDoubleEnterOnTitleStaysInTheEditorPage(): Unit {
    let harness = OkrEditorHarness()
    let ui = harness.stateOrFail()
    harness.clickNode(okrEditorPencilId("title"))
    harness.typeText("连按两次回车")
    harness.pressEnter()
    harness.pressEnter()
    harness.frame()
    @Expect(okrTitleOf(harness.store, harness.objectiveId), "连按两次回车")
    @Expect(ui.editId.value, harness.objectiveId)
    @Expect(harness.nodeByLabel("返回目标列表").isSome(), true)
}

/** KR 标题回车：同样只收起这一行，编辑页不关。 */
@Test
func okrEditorEnterOnKeyResultTitleKeepsTheEditorPage(): Unit {
    let harness = OkrEditorHarness()
    let ui = harness.stateOrFail()
    let krId = okrFirstKeyResultOf(harness.store, harness.objectiveId)
    harness.clickNode(okrEditorKrPencilId(krId))
    harness.typeText("KR 标题·改")
    harness.pressEnter()
    harness.frame()
    @Expect(okrTitleOf(harness.store, krId), "KR 标题·改")
    @Expect(ui.editTarget.value, "")
    @Expect(harness.node(okrEditorKrTitleId(krId)).isNone(), true)
    @Expect(ui.editId.value, harness.objectiveId)
    @Expect(harness.nodeByLabel("返回目标列表").isSome(), true)
}

/** 失焦立即写：标题输入框里敲字后点别处的铅笔（焦点离开），下一帧提交。 */
@Test
func okrEditorBlurWritesTheTitleToTheStore(): Unit {
    let harness = OkrEditorHarness()
    let ui = harness.stateOrFail()
    harness.clickNode(okrEditorPencilId("title"))
    harness.typeText("失焦提交的标题")
    // 点备注铅笔：焦点从标题输入框移到按钮 → 标题失焦提交。
    harness.clickNode(okrEditorPencilId("notes"))
    harness.frame()
    @Expect(okrTitleOf(harness.store, harness.objectiveId), "失焦提交的标题")
    @Expect(ui.editTarget.value, "notes")
}

/** KR 负责人失焦写：指标/负责人都在展开行里，Enter 与失焦都走 `okrEditorCommitKr`。 */
@Test
func okrEditorEnterWritesTheKeyResultOwner(): Unit {
    let harness = OkrEditorHarness()
    let krId = okrFirstKeyResultOf(harness.store, harness.objectiveId)
    harness.clickNode(okrEditorKrPencilId(krId))
    harness.clickNode(okrEditorOwnerId(krId))
    harness.typeText("林一")
    harness.pressEnter()
    @Expect(okrOwnerOf(harness.store, krId), "林一")
}

private func okrOwnerOf(store: AppStore, krId: String): String {
    for (item in store.state.value().items) {
        if (item.id == krId) {
            match (item.okr) {
                case Some(okr) => match (okr.krOwner) {
                    case Some(owner) => return owner
                    case None => return ""
                }
                case None => return ""
            }
        }
    }
    ""
}

/** 新增 KR：默认只有一个按钮，点开才出现输入；Enter 创建（信心 5）并收起。 */
@Test
func okrEditorAddsAKeyResultOnEnter(): Unit {
    let harness = OkrEditorHarness()
    let ui = harness.stateOrFail()
    let before = okrKeyResultCount(harness.store, harness.objectiveId)
    harness.clickLabel("新增关键结果")
    @Expect(ui.editTarget.value, "add-kr")
    @Expect(harness.node(okrEditorAddId()).isSome(), true)
    harness.typeText("把首周留存提升到 45%")
    harness.pressEnter()
    @Expect(okrKeyResultCount(harness.store, harness.objectiveId), before + 1)
    @Expect(ui.editTarget.value, "")
    @Expect(harness.node(okrEditorAddId()).isNone(), true)
}

private func okrKeyResultCount(store: AppStore, objectiveId: String): Int64 {
    var count: Int64 = 0
    for (item in store.state.value().items) {
        if (item.kind == ItemKind.KeyResult) {
            match (item.parentId) {
                case Some(parent) => if (parent == objectiveId) {
                    count += 1
                }
                case None => ()
            }
        }
    }
    count
}

/* ------------------------------------------------------------------ 4. notes 防抖 */

/**
 * notes 600ms 防抖：静默不足 600ms 不写，够了才写；时间来自 `FrameInfo.elapsedMs`
 * （`WidgetTestHost.frame(elapsedMs:)`），视图不读系统时钟。
 *
 * `TextArea` 与 Web `<textarea>` 一样从**插入符位置**插入，打开时插入符在末尾，所以草稿是
 * 「原备注 + 新输入」——断言按这个语义写，不假装它会清空。
 */
@Test
func okrEditorDebouncesNotesBySixHundredMilliseconds(): Unit {
    let harness = OkrEditorHarness()
    let ui = harness.stateOrFail()
    let before = okrNotesOf(harness.store, harness.objectiveId)
    let expected = before + "新的备注草稿"
    harness.clickNode(okrEditorPencilId("notes"))
    harness.typeText("新的备注草稿")
    // 输入后的第一帧：只记时间，不写库。
    harness.frame(elapsedMs: 100)
    @Expect(okrNotesOf(harness.store, harness.objectiveId), before)
    // 静默 400ms（总计 500ms < 600ms）：仍不写。
    harness.frame(elapsedMs: 500)
    @Expect(okrNotesOf(harness.store, harness.objectiveId), before)
    @Expect(ui.notesCommitted.value, before)
    // 静默到 700ms：写库。
    harness.frame(elapsedMs: 700)
    @Expect(okrNotesOf(harness.store, harness.objectiveId), expected)
    @Expect(ui.notesCommitted.value, expected)
}

/** 返回列表时 notes 立即 flush（不等防抖）。 */
@Test
func okrEditorFlushesNotesWhenReturning(): Unit {
    let harness = OkrEditorHarness()
    let ui = harness.stateOrFail()
    let before = okrNotesOf(harness.store, harness.objectiveId)
    harness.clickNode(okrEditorPencilId("notes"))
    harness.typeText("返回前最后一笔")
    harness.clickLabel("返回目标列表")
    @Expect(ui.editId.value, "")
    @Expect(okrNotesOf(harness.store, harness.objectiveId), before + "返回前最后一笔")
}

/* ------------------------------------------------------------------ 5. 返回 / Esc / 焦点 */

/**
 * Esc：第一次只取消当前字段（不写库、不回列表），第二次才返回列表；
 * 返回时焦点请求指向卡片上的铅笔 `okr-edit-<id>`。
 *
 * 断言读的是**请求本身**（`FocusRequest.pendingId()`）而不是返回后的 `focusId`：清单卡的铅笔是
 * 画布热点，它的 id 不在焦点图里（`focusableControlIdentity` 会加作用域前缀），请求落地那一帧
 * 之后会被焦点图清掉；这正是 `docs/OKR-EDIT-PLAN.md` §4.6 记的做法（与旧 prompt 的归还一致）。
 */
@Test
func okrEditorEscapeCancelsThenReturnsWithFocusOnThePencil(): Unit {
    let harness = OkrEditorHarness()
    let ui = harness.stateOrFail()
    let entry = harness.entryOrFail()
    let before = okrTitleOf(harness.store, harness.objectiveId)
    harness.clickNode(okrEditorPencilId("title"))
    harness.typeText("不该写库的草稿")
    harness.pressEscape()
    @Expect(ui.editTarget.value, "")
    @Expect(ui.editId.value, harness.objectiveId)
    @Expect(okrTitleOf(harness.store, harness.objectiveId), before)
    @Expect(harness.node(okrEditorTitleId()).isNone(), true)
    // 再按一次：返回列表，并把焦点请求指向进入时的那支铅笔。
    let handled = okrEditorEscape(harness.host.context, UiEvent.KeyDown(Key.Escape, false), harness.store, ui, entry)
    @Expect(handled, true)
    @Expect(ui.editId.value, "")
    @Expect(ui.editorFocus.pendingId(), "okr-edit-${harness.objectiveId}")
    // 下一帧渲染的是列表页（编辑页的面包屑与返回按钮都消失；列表页是自绘画布，没有语义节点）。
    harness.frame()
    @Expect(harness.nodeByLabel("2026 Q1 · 目标编辑").isNone(), true)
    @Expect(harness.nodeByLabel("返回目标列表").isNone(), true)
}

/** 「返回目标列表」按钮同一条路径（Esc 之外的第二个入口）。 */
@Test
func okrEditorBackButtonReturnsToList(): Unit {
    let harness = OkrEditorHarness()
    let ui = harness.stateOrFail()
    harness.clickLabel("返回目标列表")
    @Expect(ui.editId.value, "")
    // 回到列表：编辑页的面包屑 / 返回按钮 / 「关键结果 · N」都不在了。
    @Expect(harness.nodeByLabel("2026 Q1 · 目标编辑").isNone(), true)
    @Expect(harness.nodeByLabel("返回目标列表").isNone(), true)
    @Expect(harness.nodeByLabel("关键结果 · 3").isNone(), true)
}

/* ------------------------------------------------------------------ 6. 空态 */

/** 目标不存在 / 已被删除：空态文案 + 返回按钮，不白屏。 */
@Test
func okrEditorShowsAnEmptyStateForAMissingObjective(): Unit {
    let clock = FixedClock(EDITOR_ANCHOR)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    store.setRoute("okr")
    let viewCtx = ViewContext(store, "light", "2026-01-01", 1440, 900, {_ => ()})
    let host = WidgetTestHost()
    let holder = OkrEditorUiHolder()
    let body: () -> Unit = {=>
        VStack(spacing: vp(0.0)) {
            let ui = okrUiState()
            holder.value = ui
            if (ui.editId.value.isEmpty()) {
                ui.editId.value = "missing-objective"
            }
            okrView(viewCtx, ui)
        }.hug().padding(264.0, 80.0, 24.0, 24.0)
    }
    let _ = host.frame(EDITOR_VIEWPORT, body: body)
    let _ = host.frame(EDITOR_VIEWPORT, body: body)
    var emptyState = false
    var back = false
    for (node in host.context.semanticsSnapshot()) {
        if (node.properties.label == "目标不存在或已被删除") {
            emptyState = true
        }
        if (node.properties.label == "返回目标列表") {
            back = true
        }
    }
    @Expect(emptyState, true)
    @Expect(back, true)
    match (holder.value) {
        case Some(ui) => @Expect(ui.editId.value, "missing-objective")
        case None => @Expect("a ui state", "missing")
    }
}

/** 测试里跨帧持有的状态壳（闭包不能捕获 `var`，所以包一层对象）。 */
private class OkrEditorUiHolder {
    var value: ?OkrUiState = None
}
