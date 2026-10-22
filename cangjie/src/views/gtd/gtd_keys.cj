package textura.views.gtd

import std.collection.*
import cui.*
import textura.core.data.*
import textura.ui.*
import textura.views.gtd.logic as gl

/*
 * 行级键盘交互（`useRowKeyboard.ts` 语义）。
 *
 * Web 版把 `onKeyDown` 绑在 `.gtd-rows` 容器上：
 *   ↑ / ↓      在**当前可见行**之间移动选中行（越界回绕）
 *   x / X      完成选中行
 *   Enter      打开选中行的澄清面板
 * 输入框 / 文本域 / 下拉内的按键不拦截，避免破坏行内编辑。
 *
 * 本移植在视图根节点用 `EventHandler` 截获按键，并额外支持：
 *   Space      完成选中行（与勾选圆等价）
 *   Escape     关闭浮层（交给 `Ui.modal`）或清除选中行
 * 浮层打开时不拦截，按键全部交给弹窗。
 */

/** 与 `resolvedActiveId` 同义，但只针对 id 列表（键盘层用）。 */
func resolvedIdFromValues(current: String, ids: Array<String>): String {
    if (!current.isEmpty()) {
        return current
    }
    if (ids.isEmpty()) {
        return ""
    }
    ids[0]
}

/** 收件箱当前可见行 id（分页后）。 */
func inboxVisibleIds(scene: GtdScene): Array<String> {
    let page = gl.paginateItems(scene.inbox, scene.state.inboxLimit.value)
    let ids = ArrayList<String>()
    for (item in page.items) {
        ids.add(item.id)
    }
    ids.toArray()
}

/** 下一步当前可见行 id（筛选 → 分组 → 折叠 → 分页，与 `nextRows` 同一条链路）。 */
func nextVisibleIds(scene: GtdScene): Array<String> {
    let groups = gl.groupByContext(nextFiltered(scene))
    let collapsed = scene.state.collapsed.value
    let visible = ArrayList<gl.GtdItem>()
    for (group in groups) {
        if (!setHas(collapsed, group.context)) {
            for (item in group.items) {
                visible.add(item)
            }
        }
    }
    let limit = gl.resolvePageLimit(gl.PaginationState(scene.state.nextPageKey.value,
        scene.state.nextLimit.value), nextPageKeyOf(scene))
    let slice = gl.paginateItems(visible.toArray(), limit)
    let ids = ArrayList<String>()
    for (item in slice.items) {
        ids.add(item.id)
    }
    ids.toArray()
}

func activeStateOf(scene: GtdScene, target: String): State<String> {
    if (target == "next") {
        scene.state.activeNext
    } else {
        scene.state.activeInbox
    }
}

/** `move(delta)`：`nextIndex = current < 0 ? 0 : (current + delta + len) % len`。 */
func moveActiveRow(scene: GtdScene, target: String, ids: Array<String>, delta: Int64): Unit {
    if (ids.isEmpty()) {
        return
    }
    let holder = activeStateOf(scene, target)
    let currentId = resolvedIdFromValues(holder.value, ids)
    var currentIndex: Int64 = -1
    var index: Int64 = 0
    for (id in ids) {
        if (id == currentId) {
            currentIndex = index
        }
        index += 1
    }
    let size = ids.size
    let nextIndex = if (currentIndex < 0) {
        0
    } else {
        ((currentIndex + delta) % size + size) % size
    }
    holder.value = ids[nextIndex]
}

func completeActiveRow(scene: GtdScene, target: String, ids: Array<String>): Unit {
    let currentId = resolvedIdFromValues(activeStateOf(scene, target).value, ids)
    if (currentId.isEmpty()) {
        return
    }
    let title = match (itemTitleOf(scene, currentId)) {
        case Some(value) => value
        case None => ""
    }
    scene.ctx.store.toggleDone(currentId)
    scene.ctx.store.notify("已完成「${title}」", tone: NoticeTone.Success)
}

func itemTitleOf(scene: GtdScene, id: String): ?String {
    match (scene.item(id)) {
        case Some(item) => Some(item.title)
        case None => None
    }
}

/**
 * 根节点按键拦截。返回 `true` 表示已消费，避免同一次按键再触发子控件。
 */
func gtdKeyHandler(scene: GtdScene, event: UiEvent): Bool {
    // 弹窗打开时把按键全部让给浮层（Esc 关闭由 ModalHost 处理）。
    if (!scene.state.clarifyId.value.isEmpty() || !scene.state.picker.value.isEmpty() ||
        !scene.state.dateTarget.value.isEmpty()) {
        return false
    }
    match (event) {
        case UiEvent.KeyDown(key, isRepeat) =>
            if (isRepeat) {
                return false
            }
            let target = if (scene.state.keyTarget.value == "next") {
                "next"
            } else {
                "inbox"
            }
            match (key) {
                case Key.Down =>
                    moveActiveRow(scene, target, if (target == "next") {
                        nextVisibleIds(scene)
                    } else {
                        inboxVisibleIds(scene)
                    }, 1)
                    true
                case Key.Up =>
                    moveActiveRow(scene, target, if (target == "next") {
                        nextVisibleIds(scene)
                    } else {
                        inboxVisibleIds(scene)
                    }, -1)
                    true
                case Key.Space =>
                    completeActiveRow(scene, target, if (target == "next") {
                        nextVisibleIds(scene)
                    } else {
                        inboxVisibleIds(scene)
                    })
                    true
                case Key.Letter(code) =>
                    if (code == UInt8(120) || code == UInt8(88)) {
                        completeActiveRow(scene, target, if (target == "next") {
                            nextVisibleIds(scene)
                        } else {
                            inboxVisibleIds(scene)
                        })
                        return true
                    }
                    false
                case Key.Enter =>
                    let ids = if (target == "next") {
                        nextVisibleIds(scene)
                    } else {
                        inboxVisibleIds(scene)
                    }
                    let currentId = resolvedIdFromValues(activeStateOf(scene, target).value, ids)
                    if (currentId.isEmpty()) {
                        return false
                    }
                    scene.openClarify(currentId)
                    true
                case Key.Escape =>
                    let holder = activeStateOf(scene, target)
                    if (holder.value.isEmpty()) {
                        return false
                    }
                    holder.value = ""
                    true
                case _ => false
            }
        case _ => false
    }
}
