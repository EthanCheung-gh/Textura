package textura.views.okr

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*
import textura.views.okr.logic as lg

/*
 * 「关联执行项」弹窗（`LinkItemsDialog.tsx`）的主机回归。
 *
 * 真机反馈：打开后列表里看不到任何执行项。根因是旧的 `HStack { Button; VStack; ProgressView }`
 * 里 `ProgressView.measure` 返回 `available.w`，把整行宽度吃掉，flex 主列分到 0 宽，标题盒子
 * 宽度为 0（文字不可见）。列表改为 `OkrLinkList`（PageCanvas 逐像素布局）后，本文件钉住：
 * 候选非空、首屏 ≥5 行且行宽 >0、勾选/取消、确认写边、已关联回显与取消、空态。
 */

private let LINK_RECT: Rect = Rect(0.0, 0.0, 1024.0, 640.0)
private let LINK_ROW_PREFIX: String = "okr-link-row-"

private func linkStore(): AppStore {
    let clock = FixedClock(1773626400000)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    store
}

private func linkViewContext(store: AppStore, width!: Int64 = 1024, height!: Int64 = 640): ViewContext {
    ViewContext(store, "light", "2026-03-16", width, height, {_ => ()})
}

private func firstKr(workspace: Workspace): ?Item {
    for (item in workspace.items) {
        if (item.kind == ItemKind.KeyResult) {
            return Some(item)
        }
    }
    None
}

private func hasNodeLabel(nodes: Array<SemanticsNode>, label: String): Bool {
    for (node in nodes) {
        if (node.properties.label == label) {
            return true
        }
    }
    false
}

private func rowNode(nodes: Array<SemanticsNode>, itemId: String): ?SemanticsNode {
    let id = "${LINK_ROW_PREFIX}${itemId}"
    for (node in nodes) {
        if (node.id == id) {
            return Some(node)
        }
    }
    None
}

private func buttonNode(nodes: Array<SemanticsNode>, label: String): ?SemanticsNode {
    for (node in nodes) {
        if (node.properties.label == label) {
            return Some(node)
        }
    }
    None
}

/** Holds the page-state object across frames (a lambda may not capture a mutable `var`). */
private class LinkUiHolder {
    var value: ?OkrUiState = None
}

/** One rendered dialog: the host, the shared page state and the frame body. */
private class LinkScene {
    let host: WidgetTestHost
    let store: AppStore
    let ctx: ViewContext
    let holder = LinkUiHolder()
    let krId: String

    init(store: AppStore, width!: Int64 = 1024, height!: Int64 = 640) {
        this.store = store
        this.ctx = linkViewContext(store, width: width, height: height)
        this.host = WidgetTestHost()
        this.krId = match (firstKr(store.state.value())) {
            case Some(item) => item.id
            case None => ""
        }
    }

    func body(): Unit {
        let current = match (holder.value) {
            case Some(value) => value
            case None =>
                let created = okrUiState()
                holder.value = Some(created)
                created
        }
        let page = OkrPage(ctx, current)
        okrDialogs(ctx, current, okrDialogScopeOf(page))
    }

    /** Builds the page once, then opens the dialog with the given query. */
    func open(query!: String = ""): Unit {
        let _ = host.frame(LINK_RECT, body: {=> body()})
        match (holder.value) {
            case Some(current) =>
                current.linkKr.value = krId
                current.linkQuery.value = query
                current.linkSelected.value = []
                current.linkRemoved.value = []
                current.linkScroll.value = 0.0
                current.linkOpen.value = true
            case None => ()
        }
        let _ = host.frame(LINK_RECT, body: {=> body()})
    }

    func ui(): ?OkrUiState {
        holder.value
    }

    func nodes(): Array<SemanticsNode> {
        host.context.semanticsSnapshot()
    }

    func frame(): Unit {
        let _ = host.frame(LINK_RECT, body: {=> body()})
    }
}

@Test
func linkDialogCandidatesAreNotEmptyAndOrdered(): Unit {
    let store = linkStore()
    let workspace = store.state.value()
    let candidates = okrLinkCandidates(workspace)
    @Expect(candidates.size > 0, true)
    // Every candidate is a project or action; dropped items are excluded.
    for (item in candidates) {
        @Expect(item.kind == ItemKind.Project || item.kind == ItemKind.Action, true)
        @Expect(item.status != ItemStatus.Dropped, true)
    }
    // Stable order: parent path, then title.
    var index: Int64 = 0
    while (index + 1 < candidates.size) {
        let left = candidates[index]
        let right = candidates[index + 1]
        let leftKey = "${parentPathText(workspace, left.id)}\u{0001}${left.title}"
        let rightKey = "${parentPathText(workspace, right.id)}\u{0001}${right.title}"
        @Expect(leftKey <= rightKey, true)
        index += 1
    }
}

@Test
func linkDialogRendersVisibleRowsWithRealWidth(): Unit {
    let store = linkStore()
    let scene = LinkScene(store)
    scene.open()
    let candidates = okrLinkCandidates(store.state.value())
    @Expect(candidates.size > 0, true)
    let nodes = scene.nodes()
    // First screen: the 46vh window shows at least five 55.25px rows at 640px height.
    var visible = 0
    for (item in candidates) {
        match (rowNode(nodes, item.id)) {
            case Some(node) =>
                // A zero-width row was the device bug: the title box collapsed to 0.
                @Expect(node.bounds.w > 0.0, true)
                @Expect(node.bounds.h > 40.0, true)
                visible += 1
            case None => ()
        }
    }
    @Expect(visible >= 5, true)
}

@Test
func linkDialogSelectsAndConfirmsANewEdge(): Unit {
    let store = linkStore()
    let scene = LinkScene(store)
    scene.open()
    let workspace = store.state.value()
    let linked = ArrayList<String>()
    for (ref in lg.executionItemsOf(buildOkrWorkspace(workspace), scene.krId)) {
        linked.add(ref.item.id)
    }
    var target = ""
    for (item in okrLinkCandidates(workspace)) {
        var isLinked = false
        for (id in linked) {
            if (id == item.id) {
                isLinked = true
            }
        }
        if (!isLinked && target.isEmpty()) {
            target = item.id
        }
    }
    @Expect(target.isEmpty(), false)
    // Toggle the row through its semantics action (the same path a click takes).
    @Expect(scene.host.context.performSemanticsAction("${LINK_ROW_PREFIX}${target}",
        SemanticsAction.Activate), true)
    scene.frame()
    match (scene.ui()) {
        case Some(current) => @Expect(current.linkSelected.value.size, 1)
        case None => @Expect("ui", "missing")
    }
    // The footer's primary button confirms and closes.
    let confirm = match (buttonNode(scene.nodes(), "关联所选")) {
        case Some(node) => node
        case None =>
            @Expect("关联所选 button", "missing")
            return
    }
    @Expect(scene.host.context.performSemanticsAction(confirm.id, SemanticsAction.Activate), true)
    scene.frame()
    var hasEdge = false
    for (edge in store.state.value().edges) {
        if (edge.edgeType == EdgeType.Okr && edge.from == scene.krId && edge.to == target) {
            hasEdge = true
        }
    }
    @Expect(hasEdge, true)
    match (scene.ui()) {
        case Some(current) => @Expect(current.linkOpen.value, false)
        case None => @Expect("ui", "missing")
    }
}

@Test
func linkDialogUnchecksALinkedRowAndDeletesItsEdge(): Unit {
    let store = linkStore()
    let workspace = store.state.value()
    let scene = LinkScene(store)
    let candidate = okrLinkCandidates(workspace)[0]
    let edge = store.linkOkr(scene.krId, candidate.id)
    scene.open()
    let node = match (rowNode(scene.nodes(), candidate.id)) {
        case Some(value) => value
        case None =>
            @Expect("linked row", "missing")
            return
    }
    // Linked rows are shown as checked.
    @Expect(node.properties.checked.getOrThrow(), true)
    @Expect(scene.host.context.performSemanticsAction(node.id, SemanticsAction.Activate), true)
    scene.frame()
    match (scene.ui()) {
        case Some(current) => @Expect(current.linkRemoved.value.size, 1)
        case None => @Expect("ui", "missing")
    }
    let confirm = match (buttonNode(scene.nodes(), "关联所选")) {
        case Some(value) => value
        case None =>
            @Expect("关联所选 button", "missing")
            return
    }
    @Expect(scene.host.context.performSemanticsAction(confirm.id, SemanticsAction.Activate), true)
    scene.frame()
    var stillThere = false
    for (item in store.state.value().edges) {
        if (item.id == edge.id) {
            stillThere = true
        }
    }
    @Expect(stillThere, false)
}

@Test
func linkDialogShowsAnEmptyStateWhenTheQueryMatchesNothing(): Unit {
    let store = linkStore()
    let scene = LinkScene(store)
    scene.open(query: "不存在的关键词")
    let nodes = scene.nodes()
    @Expect(hasNodeLabel(nodes, "没有匹配的执行项"), true)
    for (item in okrLinkCandidates(store.state.value())) {
        @Expect(rowNode(nodes, item.id).isNone(), true)
    }
}
