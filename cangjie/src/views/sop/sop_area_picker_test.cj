package textura.views.sop

import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import textura.core.data.*

/*
 * SOP 检查器的 Area 下拉（`sop_area_picker.cj`）。
 *
 * 真机反馈「Area 点了没反应」：检查器是自绘的，点击必须命中 `areaInput` 并打开一个可选择的
 * 浮层。本文件钉住候选集合（未指定 + 全部领域）、选择写回 `Item.areaId`、以及弹层几何
 * （窗口内、下方放不下时翻到上方）。
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
    let popup = sopAreaPopupLayout(anchor, 900.0, 4, 2)
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
    let flipped = sopAreaPopupLayout(low, 640.0, 8, 6)
    @Expect(flipped.rect.bottom() <= low.y, true)
    @Expect(flipped.rect.y >= 8.0, true)
}
