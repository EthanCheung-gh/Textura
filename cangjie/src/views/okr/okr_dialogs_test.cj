package textura.views.okr

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*

/*
 * OKR 其余浮层（新建目标 / 季度选择 / 目标菜单 / KR 状态 / 删除确认）的可见性回归。
 *
 * 与「关联执行项」同源的问题：浮层正文若在 layout 期构造，控件拿不到焦点；若用宽度为 0 的
 * 容器包住文字，标题/按钮会「存在但看不见」。这里把每个浮层打开一次，断言关键文案与页脚
 * 按钮都真的进入语义树、且有正的宽高。
 */

private let DIALOG_RECT: Rect = Rect(0.0, 0.0, 1440.0, 900.0)

private func dialogStore(): AppStore {
    let clock = FixedClock(1773626400000)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    store
}

/** Holds the page-state object across frames. */
private class DialogHolder {
    var value: ?OkrUiState = None
}

private class DialogScene {
    let host = WidgetTestHost()
    let store: AppStore
    let ctx: ViewContext
    let holder = DialogHolder()

    init(store: AppStore) {
        this.store = store
        this.ctx = ViewContext(store, "light", "2026-03-16", 1440, 900, {_ => ()})
    }

    private func body(): Unit {
        let current = match (holder.value) {
            case Some(value) => value
            case None =>
                let created = okrUiState()
                holder.value = Some(created)
                created
        }
        let page = OkrPage(ctx, current)
        okrDialogs(ctx, current, page)
    }

    func open(mutate: (OkrUiState) -> Unit): Unit {
        let _ = host.frame(DIALOG_RECT, body: {=> body()})
        match (holder.value) {
            case Some(current) => mutate(current)
            case None => ()
        }
        let _ = host.frame(DIALOG_RECT, body: {=> body()})
    }

    func nodes(): Array<SemanticsNode> {
        host.context.semanticsSnapshot()
    }
}

/** Asserts a labelled node exists and occupies real space. */
private func expectVisible(nodes: Array<SemanticsNode>, label: String): Unit {
    for (node in nodes) {
        if (node.properties.label == label) {
            @Expect(node.bounds.w > 0.0, true)
            @Expect(node.bounds.h > 0.0, true)
            return
        }
    }
    @Expect(label, "visible")
}

@Test
func objectiveDialogRendersItsFieldsAndFooter(): Unit {
    let store = dialogStore()
    let scene = DialogScene(store)
    scene.open {ui => ui.objectiveOpen.value = true}
    let nodes = scene.nodes()
    expectVisible(nodes, "新建季度目标")
    expectVisible(nodes, "目标（定性描述）")
    expectVisible(nodes, "创建目标")
    expectVisible(nodes, "取消")
}

@Test
func quarterDialogRendersTheYearAndQuarterPickers(): Unit {
    let store = dialogStore()
    let scene = DialogScene(store)
    scene.open {ui =>
        ui.quarterYear.value = 2026
        ui.quarterIndex.value = 4
        ui.quarterMode.value = ""
        ui.quarterOpen.value = true
    }
    let nodes = scene.nodes()
    expectVisible(nodes, "新建季度")
    expectVisible(nodes, "年份")
    expectVisible(nodes, "季度")
    // The Q1…Q4 segments are painted by the shared Segmented control (no semantics node of
    // its own); the dialog's captions and primary action prove the body/footer laid out.
    expectVisible(nodes, "切换到该季度")
}

/** First item id of `kind`, or "" when the fixture has none. */
private func firstIdOf(workspace: Workspace, kind: ItemKind): String {
    for (item in workspace.items) {
        if (item.kind == kind) {
            return item.id
        }
    }
    ""
}

@Test
func menuAndStatusDialogsRenderTheirOptions(): Unit {
    let store = dialogStore()
    let workspace = store.state.value()
    let objectiveId = firstIdOf(workspace, ItemKind.Objective)
    let krId = firstIdOf(workspace, ItemKind.KeyResult)
    @Expect(objectiveId.isEmpty(), false)
    @Expect(krId.isEmpty(), false)
    let scene = DialogScene(store)
    scene.open {ui =>
        ui.menuObjective.value = objectiveId
        ui.menuOpen.value = true
    }
    let menuNodes = scene.nodes()
    expectVisible(menuNodes, "目标操作")
    expectVisible(menuNodes, "移动到其他季度")
    expectVisible(menuNodes, "复制为新季度目标")
    // Switch to the KR status dialog (the menu closes first, as a user click would).
    scene.open {ui =>
        ui.menuOpen.value = false
        ui.statusKr.value = krId
        ui.statusOpen.value = true
    }
    let statusNodes = scene.nodes()
    expectVisible(statusNodes, "KR 状态")
    expectVisible(statusNodes, "进行中")
    expectVisible(statusNodes, "已完成")
}

@Test
func deleteConfirmationRendersItsWarningAndActions(): Unit {
    let store = dialogStore()
    let workspace = store.state.value()
    let objectiveId = firstIdOf(workspace, ItemKind.Objective)
    @Expect(objectiveId.isEmpty(), false)
    let scene = DialogScene(store)
    scene.open {ui =>
        ui.confirmObjective.value = objectiveId
        ui.confirmOpen.value = true
    }
    let nodes = scene.nodes()
    expectVisible(nodes, "删除目标？")
    expectVisible(nodes, "删除目标")
    expectVisible(nodes, "取消")
}
