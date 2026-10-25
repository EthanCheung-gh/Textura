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
 * 检查项复选框（`sop_inspector.cj` 的 `.sop-checklist-item`）。
 *
 * 真机现场：选中带检查项的节点后，行内**文本**能点开原位编辑器，但点 14×14 的复选框
 * 勾选状态不变（`0/2` 不动）。本文件走**真实链路**把这条钉死：
 * `SopPageWidget.handle` → `handleCanvas` → `handleRunBar` → `handleInspector` →
 * `handleNodeInspector` → `commitChecklist` → `store.updateItem` → 下一帧的绘制数据。
 *
 * 结论（用例分工）：
 * - `sopChecklistCheckboxTogglesFromARealClick`：真链路本身没问题，点盒子中心就翻；
 * - `sopChecklistCheckboxAcceptsTheRecordedDevicePresses`：真机那九组坐标当时的落点全在
 *   行内、却在 14×14 小盒之外（见 `docs/DEVICE-NOTES.md` §27.4 B-4）——**命中区太小**才是根因，
 *   修法是把命中区扩到整条行首（`SopCheckRow.target`），画出来的盒子仍是 14×14；
 * - 其余四条：翻回来、编辑刚落幕的那一帧、点文本仍是编辑、三个盒子互不重叠。
 *
 * 断言口径：坐标一律取自 `inspectorRects`（绘制与命中共用的那一份），不自己拼；
 * 命中结果看 **store**（真源），绘制结果看下一帧 `checklistOf(selectedNode)`（画笔读的就是它）。
 */

private let CHK_CONTENT_LEFT: Float32 = 264.0
private let CHK_CONTENT_TOP: Float32 = 80.0
private let CHK_TODAY: String = "2026-01-01"
private let CHK_ANCHOR: Int64 = 1773626400000
private let CHK_HOME: String = "/tmp/textura-sop-check-test-home"
/** 种子数据里唯一条带检查项的步骤（`fixtures.cj`: chk_1 / chk_2，两条都未完成）。 */
private let CHK_NODE_ID: String = "step_check"

/*
 * 真机几何（`docs/DEVICE-NOTES.md` §27.4 的 B-4 现场）：最大化后窗口 `[0,14] 2880×1610`，
 * `densityPixels = 1.75` ⇒ 逻辑视口 2880÷1.75 = 1646 × 1610÷1.75 = 920（CUI 的逻辑单位，
 * 见 §24.2/§24.6）。`uitest` 注入的是**屏幕**坐标，SDD 后端把它减掉窗口原点再除密度，
 * 得到 CUI 的逻辑坐标：`logical = (screen - origin) / density`。
 */
private let CHK_DEVICE_WINDOW_X: Float32 = 0.0
private let CHK_DEVICE_WINDOW_Y: Float32 = 14.0
private let CHK_DEVICE_DENSITY: Float32 = 1.75
private let CHK_DEVICE_LOGICAL_W: Int64 = 1646
private let CHK_DEVICE_LOGICAL_H: Int64 = 920

/** 与 shell 内容区等价的一帧：默认 1440×900 下页面拿到的 layout 矩形是 (264, 80, 1152, 796)。 */
private class CheckHarness {
    let store: AppStore
    let viewCtx: ViewContext
    let tokens: ThemeTokens
    let theme: Theme
    var state: ?SopViewState = None
    let viewport: Rect
    let winW: Int64
    let winH: Int64

    init(viewportHeight!: Float32 = 900.0, winW!: Int64 = 1440, winH!: Int64 = 900) {
        try {
            setVariable("HOME", CHK_HOME)
        } catch (_: Exception) {
            ()
        }
        let clock = FixedClock(CHK_ANCHOR)
        this.store = AppStore(clock: clock)
        store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
        store.setRoute("sop")
        this.winW = winW
        this.winH = winH
        this.viewCtx = ViewContext(store, "light", CHK_TODAY, winW, winH, {_ => ()})
        this.tokens = tokensOf(texturaLight())
        this.theme = tokens.theme()
        this.viewport = Rect(0.0, 0.0, Float32(winW), viewportHeight)
    }

    func build(testHost: WidgetTestHost, events!: Array<UiEvent> = []): Unit {
        let _ = testHost.frame(viewport, events: events) {
            =>
                VStack(spacing: vp(0.0)) {
                    let generation = rememberState<Int64>("sop-generation") {0}
                    let state = remember<SopViewState>("sop-view-state") {SopViewState(generation)}
                    let _ = generation.value
                    this.state = state
                    SopPageWidget(store.state.value(), store, theme, tokens, state, CHK_TODAY, winW, winH)
                    sopPromptDialog(theme, store, state)
                    FocusOnceView(state.promptFocus)
                }
                    .hug()
                    .padding(CHK_CONTENT_LEFT, CHK_CONTENT_TOP, 24.0, 24.0)
        }
    }

    func frameOf(testHost: WidgetTestHost): ?SopFrame {
        match (state) {
            case Some(value) =>
                Some(
                    buildFrame(testHost.context, store.state.value(), store, theme, tokens, value, value.pageRect,
                        CHK_TODAY)
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

/** 选中带检查项的节点（真源写成 store 选择 + `state.selectedNodeId`，与 `stateSelectNode` 一致）。 */
private func chkSelectChecklistNode(harness: CheckHarness, testHost: WidgetTestHost): SopFrame {
    let view = match (harness.frameOf(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return buildFrame(testHost.context, harness.store.state.value(), harness.store, harness.theme,
                harness.tokens, SopViewState(State<Int64>(0)), Rect(264.0, 80.0, 1152.0, 796.0), CHK_TODAY)
    }
    let state = harness.stateOrFail()
    state.selectedNodeId = Some(CHK_NODE_ID)
    state.selectedEdgeId = None
    state.inspectorScroll = 0.0
    harness.store.select(Some(CHK_NODE_ID))
    state.touch()
    harness.build(testHost)
    match (harness.frameOf(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            view
    }
}

private func chkIsNodeVariant(rects: SopInspRects): Bool {
    match (rects.variant) {
        case SopInspVariant.Node => true
        case _ => false
    }
}

private func chkRectText(rect: Rect): String {
    "x=${rect.x} y=${rect.y} w=${rect.w} h=${rect.h}"
}

/** `done` 标志串（`true,false`）：一条断言同时看出翻转与「别动别的行」。 */
private func chkDoneFlags(store: AppStore, itemId: String): String {
    let item = match (itemById(store.state.value(), itemId)) {
        case Some(value) => value
        case None =>
            @Expect("the stored item", "missing")
            return "<missing>"
    }
    var flags = ""
    for (entry in checklistOf(item)) {
        let flag = if (entry.done) {
            "true"
        } else {
            "false"
        }
        if (flags.isEmpty()) {
            flags = flag
        } else {
            flags = "${flags},${flag}"
        }
    }
    flags
}

/**
 * 点复选框中心 → 该行 `done` 翻转，`0/2` → `1/2`。
 *
 * 按下点从 `inspectorRects(...).checkRows[0].checkbox` 的真中心取（不是写死坐标），
 * 事件走 `WidgetTestHost` 派发，即页面真实的 `handle` 顺序。
 */
@Test
func sopChecklistCheckboxTogglesFromARealClick(): Unit {
    let harness = CheckHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let view = chkSelectChecklistNode(harness, testHost)
    let rects = inspectorRects(testHost.context, view)
    @Expect(chkIsNodeVariant(rects), true)
    @Expect(rects.checkRows.size, Int64(2))
    @Expect(chkDoneFlags(harness.store, CHK_NODE_ID), "false,false")
    let checkbox = rects.checkRows[0].checkbox
    // 14×14 的逻辑像素盒：真机上这个中心点就是手指要落的地方。
    @Expect(checkbox.w, 14.0)
    @Expect(checkbox.h, 14.0)
    harness.build(testHost, events: [
        UiEvent.MouseDown(MouseButton.Left, checkbox.centerX(), checkbox.centerY()),
        UiEvent.MouseUp(MouseButton.Left, checkbox.centerX(), checkbox.centerY())
    ])
    @Expect(chkDoneFlags(harness.store, CHK_NODE_ID), "true,false")
    // 绘制端读的是 `checklistOf(selectedNode())`：下一帧的计数必须是 1/2。
    let after = match (harness.frameOf(testHost)) {
        case Some(value) => value
        case None =>
            @Expect("a laid-out SOP frame", "none")
            return
    }
    match (after.selectedNode()) {
        case Some(item) => @Expect("${countDone(checklistOf(item))}/${checklistOf(item).size}", "1/2")
        case None => @Expect("the selected node", "none")
    }
    // 命中矩形在翻转前后完全一致（行高不随 checked 变化）。
    let afterRects = inspectorRects(testHost.context, after)
    @Expect(afterRects.checkRows.size, Int64(2))
    @Expect(chkRectText(afterRects.checkRows[0].checkbox), chkRectText(checkbox))
}

/** 屏幕坐标 → CUI 逻辑坐标（§24.6）：`logical = (screen - 窗口原点) / density`。 */
private func chkLogical(screen: Float32, origin: Float32): Float32 {
    (screen - origin) / CHK_DEVICE_DENSITY
}

/** 在真机几何下按一个**屏幕**坐标按下，返回该下划线是否真的把第一行勾上了。 */
private func chkDevicePressTogglesRowZero(screenX: Float32, screenY: Float32): Bool {
    let harness = CheckHarness(viewportHeight: Float32(CHK_DEVICE_LOGICAL_H), winW: CHK_DEVICE_LOGICAL_W,
        winH: CHK_DEVICE_LOGICAL_H)
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let _ = chkSelectChecklistNode(harness, testHost)
    harness.build(testHost, events: [
        UiEvent.MouseDown(MouseButton.Left, chkLogical(screenX, CHK_DEVICE_WINDOW_X),
            chkLogical(screenY, CHK_DEVICE_WINDOW_Y))
    ])
    chkDoneFlags(harness.store, CHK_NODE_ID) == "true,false"
}

/**
 * 重放真机 B-4 的九组注入坐标（`docs/DEVICE-NOTES.md` §27.4，屏幕坐标 x 2228/2241/2256 ×
 * y 1082/1123/1214，窗口 `[0,14]`、density 1.75）。当时九个点全是 `0/2`。
 *
 * 换算后第一行复选框在窗口逻辑 `x 1280..1294, y 614..628`，文本行在 `x 1302..`、`y 606..636`：
 * 三组 x 里 2241/2256 落在复选框所在的**左栏**（逻辑 1280.6 / 1289.1），y 1082/1123 落在**行内**
 * （逻辑 610.3 / 633.7）但都在 14px 高的小盒子之外 —— 所以「同一列的文本字段点得开、复选框点不动」。
 *
 * 期望矩阵（修复后）：
 * - 左栏 × 行内 的四个点 → 勾上（`2241/2256 × 1082/1123`）；
 * - x = 2228 → 逻辑 1273.1，在检查器 body（1280 起）**外面**，必须仍然什么都不做；
 * - y = 1214 → 逻辑 685.7，在两行之间的空白里，必须什么都不做。
 */
@Test
func sopChecklistCheckboxAcceptsTheRecordedDevicePresses(): Unit {
    let xs: Array<Float32> = [2228.0, 2241.0, 2256.0]
    let ys: Array<Float32> = [1082.0, 1123.0, 1214.0]
    var actual = ""
    for (screenX in xs) {
        for (screenY in ys) {
            let hit = chkDevicePressTogglesRowZero(screenX, screenY)
            actual += "${Int64(screenX)}x${Int64(screenY)}=${hit};"
        }
    }
    let expected = "2228x1082=false;2228x1123=false;2228x1214=false;" + "2241x1082=true;2241x1123=true;" +
        "2241x1214=false;" + "2256x1082=true;2256x1123=true;2256x1214=false;"
    @Expect(actual, expected)
}

/**
 * 原位编辑器刚关掉的那一帧，按在复选框上仍然要生效（`InlineEditorHost` 的遮罩不许吃掉这一下）。
 */
@Test
func sopChecklistCheckboxStillWorksRightAfterTheEditorCloses(): Unit {
    let harness = CheckHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let view = chkSelectChecklistNode(harness, testHost)
    let rects = inspectorRects(testHost.context, view)
    let label = rects.checkRows[0].label
    harness.build(testHost, events: [UiEvent.MouseDown(MouseButton.Left, label.centerX(), label.centerY())])
    let state = harness.stateOrFail()
    @Expect(state.promptOpen.value, true)
    harness.build(testHost, events: [UiEvent.KeyDown(Key.Escape, false)])
    @Expect(state.promptOpen.value, false)
    let closed = chkSelectChecklistNode(harness, testHost)
    let box = inspectorRects(testHost.context, closed).checkRows[0].checkbox
    harness.build(testHost, events: [UiEvent.MouseDown(MouseButton.Left, box.centerX(), box.centerY())])
    @Expect(chkDoneFlags(harness.store, CHK_NODE_ID), "true,false")
}

/** 再点一下翻回来：同一行可以反复切换，且只动这一行。 */
@Test
func sopChecklistCheckboxTogglesBackAndLeavesTheOtherRowAlone(): Unit {
    let harness = CheckHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let view = chkSelectChecklistNode(harness, testHost)
    let rects = inspectorRects(testHost.context, view)
    let second = rects.checkRows[1].checkbox
    harness.build(testHost, events: [UiEvent.MouseDown(MouseButton.Left, second.centerX(), second.centerY())])
    @Expect(chkDoneFlags(harness.store, CHK_NODE_ID), "false,true")
    let toggled = chkSelectChecklistNode(harness, testHost)
    let rows = inspectorRects(testHost.context, toggled).checkRows
    harness.build(testHost, events: [
        UiEvent.MouseDown(MouseButton.Left, rows[1].checkbox.centerX(), rows[1].checkbox.centerY())
    ])
    @Expect(chkDoneFlags(harness.store, CHK_NODE_ID), "false,false")
}

/**
 * 文本行仍然是「打开原位编辑器」（Web 原版 `.sop-checklist-item` 里文本是 `DraftInput`，
 * 只有 `<input type="checkbox">` 才切勾选），并且点文本**不许**顺带翻转 `done`。
 */
@Test
func sopChecklistTextPressEditsAndDoesNotToggle(): Unit {
    let harness = CheckHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let view = chkSelectChecklistNode(harness, testHost)
    let rects = inspectorRects(testHost.context, view)
    let label = rects.checkRows[0].label
    harness.build(testHost, events: [UiEvent.MouseDown(MouseButton.Left, label.centerX(), label.centerY())])
    let state = harness.stateOrFail()
    @Expect(state.promptOpen.value, true)
    @Expect(state.promptKind.value, "check-text")
    @Expect(state.promptTarget.value, CHK_NODE_ID)
    @Expect(chkDoneFlags(harness.store, CHK_NODE_ID), "false,false")
    closeSopPrompt(state)
}

/**
 * 画出来的盒子与命中区的关系：`.sop-checkbox` 仍是 14×14（`sop.css` 的像素，parity 不变），
 * 命中区扩到整条行首（`label.x` 之前 × 整行高），两者都与文本框互不重叠。
 */
@Test
func sopChecklistCheckboxBoxIsSeparateFromTheTextRow(): Unit {
    let harness = CheckHarness()
    let testHost = WidgetTestHost()
    harness.build(testHost)
    let view = chkSelectChecklistNode(harness, testHost)
    let rects = inspectorRects(testHost.context, view)
    var previousBottom: Float32 = 0.0
    var index: Int64 = 0
    for (row in rects.checkRows) {
        // 绘制：14×14，右边 8px 才是文本。
        @Expect(row.checkbox.w, 14.0)
        @Expect(row.checkbox.h, 14.0)
        @Expect(row.label.x - row.checkbox.right(), 8.0)
        // 命中：整条行首，正好到文本开始处为止（不吞文本，也不吞下一行）。
        @Expect(row.target.x, row.checkbox.x)
        @Expect(row.target.right(), row.label.x)
        @Expect(row.target.y, row.label.y)
        @Expect(row.target.h, row.label.h)
        @Expect(row.checkbox.y > row.target.y, true)
        @Expect(row.checkbox.bottom() < row.target.bottom(), true)
        if (index > 0) {
            @Expect(previousBottom <= row.target.y, true)
            @Expect(row.target.y - previousBottom, 8.0)
        }
        previousBottom = row.target.bottom()
        // 删除按钮在最右，不与文本行重叠。
        @Expect(row.label.right() <= row.remove.x, true)
        index += 1
    }
}
