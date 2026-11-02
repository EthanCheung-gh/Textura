package textura.views.okr

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*
import textura.ui.{FocusOnceView, vp}

/*
 * 列表页（卡片画布）的**只读化**回归（P2）。
 *
 * P2 把文本编辑全部搬到独立编辑页（`okr_editor.cj`），列表页只保留：
 *   - 右上角的铅笔 `okr-edit-<objId>`（进编辑页）与 `okr-more-<objId>`（季度 / 复制 / 删除）；
 *   - 页底的「新增关键结果」入口 `okr-add-<objId>`（进编辑页并聚焦新增输入）；
 *   - 执行项勾选 `okr-exec-<itemId>`。
 *
 * 本文件过去钉的是「卡片上的原位编辑器落在字段矩形上」（`Ui.inlineEditor` 时代）。那条路径
 * 已按 `docs/OKR-EDIT-PLAN.md` §4.5 整体删除（`okr_prompt.cj` 不再存在），所以这里改为钉住
 * **新的边界**：卡片上不再有任何文本热区/输入框外观，铅笔与新增入口走编辑页。
 */

private let OKR_LIST_VIEWPORT: Rect = Rect(0.0, 0.0, 1440.0, 900.0)
/** shell 的 `.shell-content` 内盒：sidebar 240 + 24 内边距，topbar 56 + 24 内边距。 */
private let OKR_LIST_CONTENT_LEFT: Float32 = 264.0
private let OKR_LIST_CONTENT_TOP: Float32 = 80.0
private let OKR_LIST_ANCHOR: Int64 = 1773626400000

/** 卡片上**允许**存在的热区前缀（P2 之后的白名单）。 */
private let OKR_LIST_ALLOWED_PREFIXES: Array<String> = [
    "okr-view-seg",
    "okr-density-seg",
    "okr-new-objective",
    "okr-new-quarter",
    "okr-chip-",
    "okr-empty-new",
    "okr-edit-",
    "okr-more-",
    "okr-add-",
    "okr-exec-"
]

/** P2 之后**不允许**出现在卡片上的文本编辑热区前缀（旧 prompt 路径的全部入口）。 */
private let OKR_LIST_FORBIDDEN_PREFIXES: Array<String> = [
    "okr-title-",
    "okr-field-",
    "okr-owner-",
    "okr-addkr-",
    "okr-conf-",
    "okr-status-",
    "okr-up-",
    "okr-down-",
    "okr-del-",
    "okr-link-"
]

private class OkrListHarness {
    var page: ?OkrPage = None
    var ui: ?OkrUiState = None
    let store: AppStore
    let viewCtx: ViewContext

    init() {
        let clock = FixedClock(OKR_LIST_ANCHOR)
        this.store = AppStore(clock: clock)
        store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
        store.setRoute("okr")
        this.viewCtx = ViewContext(store, "light", "2026-01-01", 1440, 900, {_ => ()})
    }

    /** 与 `okr.cj` 的列表分支同一条构建路径（`OkrPage` + `okrDialogs` + 焦点载体）。 */
    func build(testHost: WidgetTestHost, events!: Array<UiEvent> = []): Unit {
        let _ = testHost.frame(OKR_LIST_VIEWPORT, events: events) {
            =>
                VStack(spacing: vp(0.0)) {
                    let ui = okrUiState()
                    let page = OkrPage(viewCtx, ui)
                    this.ui = ui
                    this.page = page
                    okrDialogs(viewCtx, ui, okrDialogScopeOf(page))
                    FocusOnceView(ui.editorFocus)
                }
                    .hug()
                    .padding(OKR_LIST_CONTENT_LEFT, OKR_LIST_CONTENT_TOP, 24.0, 24.0)
        }
    }

    func stateOrFail(): OkrUiState {
        match (ui) {
            case Some(value) => value
            case None => okrUiState()
        }
    }

    func hotspots(): Array<OkrHotspot> {
        match (page) {
            case Some(value) => value.hotspots()
            case None => Array<OkrHotspot>()
        }
    }

    /** 画布上第一个 id 以 `prefix` 开头的命中区。 */
    func hotspot(prefix: String): ?OkrHotspot {
        for (spot in hotspots()) {
            if (spot.id.startsWith(prefix)) {
                return Some(spot)
            }
        }
        None
    }

    /** 画布注册的焦点 id（Tab 顺序）；只读化之后不应再有文本字段。 */
    func focusableIds(): Array<String> {
        match (page) {
            case Some(value) => value.focusableIds()
            case None => Array<String>()
        }
    }

    /** 像用户一样点一下：按下 + 抬起都落在盒子里。 */
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

/** 固定数据下的第一个目标 id（`createSeedWorkspace` 的第一张卡）。 */
private func okrFirstObjectiveId(store: AppStore): String {
    for (item in store.state.value().items) {
        if (item.kind == ItemKind.Objective) {
            return item.id
        }
    }
    ""
}

/** 固定数据下的第一个 KR id。 */
private func okrFirstKrId(store: AppStore): String {
    for (item in store.state.value().items) {
        if (item.kind == ItemKind.KeyResult) {
            return item.id
        }
    }
    ""
}

/**
 * 卡片上不再有文本编辑热区（P2 只读化）。
 *
 * 白名单 + 黑名单双向断言：黑名单抓「漏删的旧热区」，白名单抓「为了过测而把整张卡的热区都删光」
 * ——铅笔、更多、新增入口、执行项勾选必须还在。
 */
@Test
func okrListCardRegistersOnlyReadOnlyHotspots(): Unit {
    let harness = OkrListHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let spots = harness.hotspots()
    @Expect(spots.size > 0, true)
    for (spot in spots) {
        for (prefix in OKR_LIST_FORBIDDEN_PREFIXES) {
            @Expect(spot.id.startsWith(prefix), false)
        }
        var allowed = false
        for (prefix in OKR_LIST_ALLOWED_PREFIXES) {
            if (spot.id.startsWith(prefix)) {
                allowed = true
            }
        }
        @Expect(allowed, true)
    }
    // 铅笔 / 更多 / 新增入口都在（这三条是 P2 之后列表页仅有的入口）。
    let objectiveId = okrFirstObjectiveId(harness.store)
    @Expect(harness.hotspot("okr-edit-${objectiveId}").isSome(), true)
    @Expect(harness.hotspot("okr-more-${objectiveId}").isSome(), true)
    @Expect(harness.hotspot("okr-add-${objectiveId}").isSome(), true)
}

/** 焦点环同理：`okr-title-` / `okr-field-` / `okr-owner-` / `okr-addkr-` 不再是焦点项。 */
@Test
func okrListFocusOrderHasNoTextFieldStops(): Unit {
    let harness = OkrListHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let ids = harness.focusableIds()
    @Expect(ids.size > 0, true)
    for (id in ids) {
        for (prefix in OKR_LIST_FORBIDDEN_PREFIXES) {
            @Expect(containsFragment(id, prefix), false)
        }
    }
    // 铅笔仍是一个焦点停靠点。注意 `focusableControlIdentity()` 会把 id 加上**构建作用域前缀**
    // 与去重后缀（`store.uniqueControlId`），所以这里只按片段匹配，不比较完整字符串。
    let objectiveId = okrFirstObjectiveId(harness.store)
    var pencilStops: Int64 = 0
    for (id in ids) {
        if (containsFragment(id, "okr-edit-${objectiveId}")) {
            pencilStops += 1
        }
    }
    @Expect(pencilStops > 0, true)
}

/** 子串包含（焦点 id 带作用域前缀/去重后缀，不能按前缀或相等比较）。 */
private func containsFragment(haystack: String, needle: String): Bool {
    if (needle.size > haystack.size) {
        return false
    }
    let text = haystack.toRuneArray()
    let target = needle.toRuneArray()
    var index = 0
    while (index + target.size <= text.size) {
        var matched = true
        var offset = 0
        while (offset < target.size) {
            if (text[index + offset] != target[offset]) {
                matched = false
            }
            offset += 1
        }
        if (matched) {
            return true
        }
        index += 1
    }
    false
}

/**
 * 铅笔 → 编辑页：`editId` 写目标、`store.select(id)` 同步侧栏 / 检查器、
 * 焦点请求指向编辑页的「返回目标列表」（同一次点击不会同时请求列表上的东西）。
 */
@Test
func okrListPencilOpensTheEditorPage(): Unit {
    let harness = OkrListHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let objectiveId = okrFirstObjectiveId(harness.store)
    let ui = harness.stateOrFail()
    @Expect(ui.editId.value, "")
    let pencil = match (harness.hotspot("okr-edit-${objectiveId}")) {
        case Some(value) => value
        case None =>
            @Expect("an okr-edit hotspot", "none")
            return
    }
    // 26×26 的图标按钮，且排在 `okr-more` 左边（Web 的 `data-edit-objective` 位置）。
    @Expect(pencil.rect.w, Float32(26.0))
    @Expect(pencil.rect.h, Float32(26.0))
    match (harness.hotspot("okr-more-${objectiveId}")) {
        case Some(more) => @Expect(pencil.rect.x < more.rect.x, true)
        case None => @Expect("an okr-more hotspot", "none")
    }
    harness.press(testHost, pencil)
    @Expect(ui.editId.value, objectiveId)
    @Expect(harness.store.selectedId.value(), Some(objectiveId))
    @Expect(ui.editTarget.value, "")
    @Expect(ui.editorFocus.isPending(), true)
}

/** 页底「新增关键结果」→ 编辑页并直接展开新增输入（`editTarget == "add-kr"`）。 */
@Test
func okrListAddKeyResultOpensTheEditorWithTheAddInput(): Unit {
    let harness = OkrListHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let objectiveId = okrFirstObjectiveId(harness.store)
    let entry = match (harness.hotspot("okr-add-${objectiveId}")) {
        case Some(value) => value
        case None =>
            @Expect("an okr-add hotspot", "none")
            return
    }
    harness.press(testHost, entry)
    let ui = harness.stateOrFail()
    @Expect(ui.editId.value, objectiveId)
    @Expect(ui.editTarget.value, "add-kr")
}

/**
 * 保留的即时动作：执行项勾选仍然在列表页直接改 store（不进 IME、不开浮层，
 * 与旧 prompt 崩溃组合无关，所以 P2 之后仍然保留）。
 *
 * seed 数据的 KR 没有 `okr` 边，先按用户的方式关联一个执行项，勾选框才会出现。
 */
@Test
func okrListExecutionCheckboxStillTogglesDone(): Unit {
    let harness = OkrListHarness()
    let krId = okrFirstKrId(harness.store)
    let execId = okrFirstProjectId(harness.store)
    @Expect(krId.isEmpty(), false)
    @Expect(execId.isEmpty(), false)
    let _ = harness.store.linkOkr(krId, execId)
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let spot = match (harness.hotspot("okr-exec-${execId}")) {
        case Some(value) => value
        case None =>
            @Expect("an okr-exec hotspot", "none")
            return
    }
    let before = okrItemStatusOf(harness.store, execId)
    harness.press(testHost, spot)
    let after = okrItemStatusOf(harness.store, execId)
    @Expect(before != after, true)
}

/** 第一个项目（`project`）id：用来建立一条 `okr` 边。 */
private func okrFirstProjectId(store: AppStore): String {
    for (item in store.state.value().items) {
        if (item.kind == ItemKind.Project) {
            return item.id
        }
    }
    ""
}

private func okrItemStatusOf(store: AppStore, id: String): ItemStatus {
    for (item in store.state.value().items) {
        if (item.id == id) {
            return item.status
        }
    }
    ItemStatus.Next
}

/** 信心刻度只读：点上去不改 store（改信心请进编辑页）。 */
@Test
func okrListConfidenceScaleIsReadOnly(): Unit {
    let harness = OkrListHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let krId = okrFirstKrId(harness.store)
    let before = okrConfidenceOf(harness.store, krId)
    // 刻度格子没有热区（`okr-conf-<id>-n`）——直接点到 KR 行中间不该有任何写入。
    let row = Rect(OKR_LIST_CONTENT_LEFT + 200.0, OKR_LIST_CONTENT_TOP + 300.0, 40.0, 20.0)
    let ctx = testHost.context
    match (harness.page) {
        case Some(page) =>
            let _ = page.handle(ctx, UiEvent.MouseDown(MouseButton.Left, row.centerX(), row.centerY()))
            let _ = page.handle(ctx, UiEvent.MouseUp(MouseButton.Left, row.centerX(), row.centerY()))
        case None => ()
    }
    @Expect(okrConfidenceOf(harness.store, krId), before)
    @Expect(harness.hotspot("okr-conf-").isNone(), true)
}

private func okrConfidenceOf(store: AppStore, id: String): Int64 {
    for (item in store.state.value().items) {
        if (item.id == id) {
            match (item.okr) {
                case Some(okr) => return okr.confidence
                case None => return -1
            }
        }
    }
    -1
}

/**
 * `editId` 非空时 `render` 二选一：列表页不再被构建（否则编辑页与画布同时存在，
 * 两套热点会在同一帧抢同一次点击）。
 */
@Test
func okrRenderSwitchesToTheEditorWhenEditIdIsSet(): Unit {
    let clock = FixedClock(OKR_LIST_ANCHOR)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    store.setRoute("okr")
    let viewCtx = ViewContext(store, "light", "2026-01-01", 1440, 900, {_ => ()})
    let objectiveId = okrFirstObjectiveId(store)
    let testHost = WidgetTestHost()
    let _ = testHost.frame(OKR_LIST_VIEWPORT) {
        =>
            let ui = okrUiState()
            ui.editId.value = objectiveId
            okrView(viewCtx, ui)
    }
    // 编辑页独有的语义节点（卡片上没有这个标签），且标题输入框不存在（纯展示态）。
    var back = false
    var titleInput = false
    for (node in testHost.context.semanticsSnapshot()) {
        if (node.properties.label == "返回目标列表") {
            back = true
        }
        if (node.id == okrEditorTitleId()) {
            titleInput = true
        }
    }
    @Expect(back, true)
    @Expect(titleInput, false)
}
