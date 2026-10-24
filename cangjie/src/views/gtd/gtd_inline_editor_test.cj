package textura.views.gtd

import std.env.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*
import textura.ui.{FocusOnceView, InlineAnchor, ThemeTokens, tokensOf, texturaLight, vp}

/*
 * GTD 行内日期 / 场景的原位编辑器：盒子记矩形 → 锚点跨帧 → 编辑器贴在盒子上。
 *
 * 真机现场（docs/DEVICE-NOTES.md §25.1/25.2）：点「下一步」行的日期盒，编辑器出现在**窗口左上角**，
 * 日期盒被画成编辑态（文字消失），而且**打不进字**——因为 `GtdState()` 每帧重建，
 * 日期矩形和焦点请求都是普通字段，下一帧就丢了。现在两者都由 `remember` 持有
 * （`InlineAnchor` + `FocusRequest`），盒子在 `layout` 里每帧写回自己的窗口绝对矩形。
 *
 * 三条链路各自被单独钉住：
 *   1. `GtdDateBox(editing: true, anchor:)` → layout 写回**绝对**矩形（含容器偏移），不编辑时不写；
 *   2. `openDateEditor` → `gtdDateDialog` → 编辑器语义 bounds == 那个矩形（不是 (0,0)）；
 *   3. Enter 写回 store、Esc 取消不写。
 */
private let GTD_EDITOR_VIEWPORT: Rect = Rect(0.0, 0.0, 1440.0, 900.0)
private let GTD_EDITOR_LEFT: Float32 = 300.0
private let GTD_EDITOR_TOP: Float32 = 200.0
private let GTD_EDITOR_TODAY: String = "2026-01-01"
private let GTD_EDITOR_ANCHOR: Int64 = 1773626400000
private let GTD_EDITOR_HOME: String = "/tmp/textura-gtd-inline-test-home"
private let GTD_EDITOR_ITEM: String = "gtd-inline-test-item"
private let GTD_EDITOR_ROW: String = "gtd-row-date:test"

/** 一帧里要握住的对象：状态壳、场景、以及日期盒自己的矩形。 */
private class GtdEditorHarness {
    let store: AppStore
    let viewCtx: ViewContext
    let tokens: ThemeTokens
    let theme: Theme
    var state: ?GtdState = None
    var scene: ?GtdScene = None
    /** 真实存在的「下一步」条目：提交/取消断言都落到这条记录上。 */
    var itemId: String = ""

    init() {
        try {
            setVariable("HOME", GTD_EDITOR_HOME)
        } catch (_: Exception) {
            ()
        }
        let clock = FixedClock(GTD_EDITOR_ANCHOR)
        this.store = AppStore(clock: clock)
        store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
        store.setRoute("gtd")
        this.viewCtx = ViewContext(store, "light", GTD_EDITOR_TODAY, 1440, 900, {_ => ()})
        this.tokens = tokensOf(texturaLight())
        this.theme = tokens.theme()
        let created = store.createItem(NewItemInput(ItemKind.Action, "行内日期编辑器用例",
            status: Some(ItemStatus.Next)))
        this.itemId = created.id
    }

    /**
     * 一帧：行内日期盒（编辑态）放在 `(300, 200)` 的容器里 + 日期编辑器。
     *
     * 与真机同构的最小组合：盒子负责「字段在哪」（layout 写锚点），对话框负责「编辑器摆在锚点上」。
     * 内容区偏移用 padding 表达（真机是侧栏 240 + 内边距 24），因此锚点必须是绝对坐标才能对上。
     */
    func build(testHost: WidgetTestHost, events!: Array<UiEvent> = []): Unit {
        let _ = testHost.frame(GTD_EDITOR_VIEWPORT, events: events) {
            =>
                let state = gtdState()
                let scene = GtdScene(viewCtx, tokens, theme, GTD_EDITOR_TODAY, store.state.value(),
                    toGtdWorkspace(store.state.value()), state)
                this.state = state
                this.scene = scene
                HStack(spacing: vp(0.0)) {
                    // 编辑态：盒子只留背景，文字与边框归真控件；它同时把自己这一帧的绝对矩形
                    // 写回锚点（`GtdDateBox.layout`），所以滚动/换行后编辑器仍贴在盒子上。
                    GtdDateBox(tokens, "", GTD_EDITOR_ROW, {_ => ()}, editing: true, anchor: state.dateAnchor)
                    Spacer()
                }
                    .crossAxisAlignment(CrossAxisAlignment.Start)
                    .hug()
                    .padding(GTD_EDITOR_LEFT, GTD_EDITOR_TOP, 0.0, 0.0)
                gtdDateDialog(scene)
                FocusOnceView(state.dateFocus)
        }
    }

    func stateOrFail() : GtdState {
        match (state) {
            case Some(value) => value
            case None => GtdState()
        }
    }
}

/** 盒子这一帧记下的绝对矩形（编辑器的目标位置）。 */
private func recordedRect(harness: GtdEditorHarness, testHost: WidgetTestHost): Rect {
    let _ = testHost
    harness.stateOrFail().dateAnchor.current()
}

/** 走真实入口打开日期编辑器（与 `GtdDateBox` 的 onClick 完全一致）。 */
private func openDate(harness: GtdEditorHarness, rect: Rect): Unit {
    let scene = match (harness.scene) {
        case Some(value) => value
        case None => return
    }
    let item = match (scene.item(harness.itemId)) {
        case Some(value) => toGtdItem(value)
        case None => return
    }
    openDateEditor(scene, item, rect)
}

private func gtdEditorBoundsOf(testHost: WidgetTestHost, key: String): Rect {
    var bounds = Rect(0.0, 0.0, -1.0, -1.0)
    for (node in testHost.context.semanticsSnapshot()) {
        if (node.id == key) {
            bounds = node.bounds
        }
    }
    bounds
}

private func gtdRectText(rect: Rect): String {
    "x=${rect.x} y=${rect.y} w=${rect.w} h=${rect.h}"
}

/** 日期盒在 layout 里写回自己的**窗口绝对矩形**（编辑器不知道盒子在哪，只能靠这一笔）。 */
@Test
func gtdDateBoxRecordsItsOwnRectWhileEditing(): Unit {
    let clock = FixedClock(GTD_EDITOR_ANCHOR)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    let tokens = tokensOf(texturaLight())
    let anchor = InlineAnchor(State<Int64>(0))
    let testHost = WidgetTestHost()
    // 盒子被放进一个带 300/200 偏移的容器：它记下的必须是偏移**之后**的绝对坐标。
    let _ = testHost.frame(GTD_EDITOR_VIEWPORT) {
        =>
            HStack(spacing: vp(0.0)) {
                GtdDateBox(tokens, "", GTD_EDITOR_ROW, {_ => ()}, editing: true, anchor: anchor)
                Spacer()
            }
                .crossAxisAlignment(CrossAxisAlignment.Start)
                .hug()
                .padding(GTD_EDITOR_LEFT, GTD_EDITOR_TOP, 0.0, 0.0)
    }
    let recorded = anchor.current()
    @Expect(gtdRectText(recorded),
        gtdRectText(Rect(GTD_EDITOR_LEFT, GTD_EDITOR_TOP, INLINE_DATE_W, INLINE_H)))
    @Expect(anchor.ready(), true)
}

/** 非编辑态的盒子不写锚点（编辑器只跟着「正在编辑的那一个」）。 */
@Test
func gtdDateBoxLeavesTheAnchorAloneWhenNotEditing(): Unit {
    let clock = FixedClock(GTD_EDITOR_ANCHOR)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    let tokens = tokensOf(texturaLight())
    let anchor = InlineAnchor(State<Int64>(0))
    let testHost = WidgetTestHost()
    let _ = testHost.frame(GTD_EDITOR_VIEWPORT) {
        =>
            HStack(spacing: vp(0.0)) {
                GtdDateBox(tokens, "", GTD_EDITOR_ROW, {_ => ()}, editing: false, anchor: anchor)
                Spacer()
            }
                .crossAxisAlignment(CrossAxisAlignment.Start)
                .hug()
                .padding(GTD_EDITOR_LEFT, GTD_EDITOR_TOP, 0.0, 0.0)
    }
    @Expect(anchor.ready(), false)
}

/**
 * 编辑器贴在日期盒上：盒子记下的矩形 = 编辑器语义 bounds，且拿到焦点（无插入符就是打不进字）。
 *
 * 矩形不是测试编出来的：它来自盒子自己的 `layout`（`GtdDateBox` 的 frame）。
 */
@Test
func gtdDateEditorSitsOnTheDateBox(): Unit {
    let harness = GtdEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let state = harness.stateOrFail()
    let recorded = state.dateAnchor.current()
    // 内容区偏移（300/200）已经在盒子的矩形里：编辑器必须在盒子上，不能在 (0,0)。
    @Expect(gtdRectText(recorded),
        gtdRectText(Rect(GTD_EDITOR_LEFT, GTD_EDITOR_TOP, INLINE_DATE_W, INLINE_H)))
    // 与点击同一条入口：`GtdDateBox` 的 onClick 就是 `openDateEditor(scene, item, frame)`。
    openDate(harness, recorded)
    harness.build(testHost)
    @Expect(gtdRectText(gtdEditorBoundsOf(testHost, GTD_DATE_INPUT)), gtdRectText(recorded))
    @Expect(testHost.context.focusId, GTD_DATE_INPUT)
}

/** Enter 提交：写回截止日期并关闭编辑器。 */
@Test
func gtdDateEditorCommitsTheTypedDate(): Unit {
    let harness = GtdEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let state = harness.stateOrFail()
    openDate(harness, recordedRect(harness, testHost))
    harness.build(testHost)
    @Expect(gtdEditorBoundsOf(testHost, GTD_DATE_INPUT).w > 0.0, true)
    state.dateDraft.value = "2026-11-05"
    harness.build(testHost)
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Enter, false)])
    @Expect(state.dateTarget.value, "")
    @Expect(gtdEditorBoundsOf(testHost, GTD_DATE_INPUT).w < 0.0, true)
    @Expect(gtdItemDue(harness.store, harness.itemId), "2026-11-05")
}

/** Esc 取消：不写回、编辑器消失（值非法或矩形异常时也必须能关，这是本轮的硬要求）。 */
@Test
func gtdDateEditorEscapeCancelsWithoutWriting(): Unit {
    let harness = GtdEditorHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let state = harness.stateOrFail()
    openDate(harness, recordedRect(harness, testHost))
    harness.build(testHost)
    state.dateDraft.value = "2026-12-31"
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Escape, false)])
    @Expect(state.dateTarget.value, "")
    @Expect(gtdEditorBoundsOf(testHost, GTD_DATE_INPUT).w < 0.0, true)
    @Expect(gtdItemDue(harness.store, harness.itemId), "")
}

/** 空字符串表示「没有截止日期」（`setDue` 的写回语义）。 */
private func gtdItemDue(store: AppStore, id: String): String {
    for (item in store.state.value().items) {
        if (item.id == id) {
            match (item.gantt) {
                case Some(gantt) => match (gantt.end) {
                    case Some(value) => return value
                    case None => return ""
                }
                case None => return ""
            }
        }
    }
    ""
}
