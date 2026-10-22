package textura.views.okr

import cui.*
import textura.core.data.{AppStore, ViewContext}
import textura.ui.*

/*
 * OKR 视图入口。`shell` 在自己的声明块里调用 `render(ctx)`；CUI 每帧重建，
 * 因此每次调用都从 `ctx.store` 读最新工作区并重新布局。
 *
 * 响应式：`core.data` 不允许依赖 `cui`，所以 store 的状态不是 CUI `State`。
 * 这里用 `OkrStoreBridge` 把 `AppStore.state` 的修订号桥接成一个 CUI `State`，
 * store 写入后视图在下一帧重建（`CORE-API.md` §12 的推荐接法）。
 */

public func render(ctx: ViewContext): Unit {
    let revision = rememberState<Int64>("okr-store-revision") {0}
    let bridge = remember<OkrStoreBridge>("okr-store-bridge") {OkrStoreBridge(ctx.store, revision)}
    let _ = revision.value
    let ui = okrUiState()
    let page = OkrPage(ctx, ui)
    okrDialogs(ctx, ui, page)
    let _ = bridge
}

public func bootstrapTitle(): String {
    "OKR"
}

public func bootstrapNote(): String {
    "OKR 视图：季度切换、目标卡 / 表格 / 对齐、指标与信心编辑。"
}
