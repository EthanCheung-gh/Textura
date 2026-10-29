package textura.views.okr

import cui.*
import textura.core.data.{AppStore, ViewContext}
import textura.ui.*

/*
 * OKR 视图入口。`shell` 在自己的声明块里调用 `render(ctx)`；CUI 每帧重建，
 * 因此每次调用都从 `ctx.store` 读最新工作区并重新布局。
 *
 * 两个页面二选一（`docs/OKR-EDIT-PLAN.md` §4.1）：
 *   - `ui.editId == ""` → 列表页 `OkrPage`（自绘画布，P2 之后**只读**：纯文本 + 只读信心 +
 *     铅笔 + 更多菜单；文本编辑全部在编辑页）；
 *   - `ui.editId != ""` → 独立编辑页 `okrEditorPage`（原生控件树，build 阶段声明，因此焦点与
 *     IME 天然可用；不再有 `Ui.inlineEditor` / `Portal` / IME 锚点）。
 *
 * 响应式：`core.data` 不允许依赖 `cui`，所以 store 的状态不是 CUI `State`。
 * 这里用 `OkrStoreBridge` 把 `AppStore.state` 的修订号桥接成一个 CUI `State`，
 * store 写入后视图在下一帧重建（`CORE-API.md` §12 的推荐接法）。
 */

public func render(ctx: ViewContext): Unit {
    let revision = rememberState<Int64>("okr-store-revision") {0}
    let bridge = remember<OkrStoreBridge>("okr-store-bridge") {OkrStoreBridge(ctx.store, revision)}
    let _ = revision.value
    okrView(ctx, okrUiState())
    let _ = bridge
}

/**
 * 列表 / 编辑页二选一（`render` 的唯一分支点）。
 *
 * 单独拆出来是因为测试要用**同一个**状态壳走这条真实路径（`render` 自己建的壳与测试持有的
 * 壳不是同一个对象，`peekField` 这类按实例缓存的读法会看不到草稿）。
 */
func okrView(ctx: ViewContext, ui: OkrUiState): Unit {
    if (ui.editId.value.isEmpty()) {
        let page = OkrPage(ctx, ui)
        okrDialogs(ctx, ui, okrDialogScopeOf(page))
        // Applies (and later restores) the one-shot focus request of the editor entry: a request
        // raised while returning to the list must still land on the card's pencil.
        FocusOnceView(ui.editorFocus)
    } else {
        okrEditorPage(ctx, ui)
    }
}

public func bootstrapTitle(): String {
    "OKR"
}

public func bootstrapNote(): String {
    "OKR 视图：季度切换、目标卡 / 表格 / 对齐、独立编辑页（P1+P2）。"
}
