package textura.views.sop

import std.collection.*
import cui.*
import textura.core.data.*
import textura.ui.*

/*
 * SOP 设置里的 Area 下拉。
 *
 * 检查器是画布自绘的（`sop_inspector.cj`），里面的「输入框」在 draw 阶段才出现，
 * 行内 `Select` 拿不到焦点（docs/DEVICE-NOTES.md §16），所以 Area 走一个弹出列表：
 * 点击字段 → 注册一个 CUI `Overlay`（在整棵树之后绘制、在所有 widget 之前收事件），
 * 列出「未指定」+ `workspace.areas`，Up/Down 移动、Enter 写回、Esc / 点击浮层外关闭。
 *
 * 选中即写 `store.updateItem(..., withAreaId(...))`，画布节点与列表的颜色标记立刻更新。
 */

/** 弹层行高：与检查器输入框（36.25）同一节奏，略紧凑。 */
let SOP_AREA_ROW_H: Float32 = 30.0
/** 弹层内边距（上下各 4，与 `.cal-select` 弹层一致）。 */
let SOP_AREA_POPUP_PAD: Float32 = 4.0
/** 弹层最小宽度：至少放得下「未指定」。 */
let SOP_AREA_POPUP_MIN_W: Float32 = 168.0
/** 最多一次显示的行数（超过时窗口跟随选择滚动）。 */
let SOP_AREA_MAX_ROWS: Int64 = 8
let SOP_AREA_ROW_PAD_X: Float32 = 10.0
/** 领域颜色圆点半径（`.sop-area-dot` 8px）。 */
let SOP_AREA_DOT_R: Float32 = 4.0

/** 一行候选：`areaId == None` 是「未指定」。 */
class SopAreaChoice {
    let areaId: ?String
    let label: String
    let color: ?String

    init(areaId: ?String, label: String, color!: ?String = None) {
        this.areaId = areaId
        this.label = label
        this.color = color
    }
}

/* 本包只用到整数与 Float32 的极值；写成具名函数避免与 `std.core` 的泛型重载歧义。 */
func sopMinI64(a: Int64, b: Int64): Int64 {
    if (a < b) {
        a
    } else {
        b
    }
}

func sopMaxI64(a: Int64, b: Int64): Int64 {
    if (a > b) {
        a
    } else {
        b
    }
}

func sopMaxF32(a: Float32, b: Float32): Float32 {
    if (a > b) {
        a
    } else {
        b
    }
}

/** Lays the popup out below (or above) the Area field; shared by painting and hit-testing. */
class SopAreaPopup {
    let rect: Rect
    /** First visible choice index (window follows the selection). */
    let first: Int64
    let visible: Int64

    init(rect: Rect, first: Int64, visible: Int64) {
        this.rect = rect
        this.first = first
        this.visible = visible
    }

    /** Choice index under `y`, or `None` outside the rows. */
    func rowAt(y: Float32): ?Int64 {
        if (y < rect.y + SOP_AREA_POPUP_PAD || y >= rect.bottom() - SOP_AREA_POPUP_PAD) {
            return None
        }
        let row = Int64((y - rect.y - SOP_AREA_POPUP_PAD) / SOP_AREA_ROW_H)
        if (row < 0 || row >= visible) {
            return None
        }
        return Some(first + row)
    }

    func rowRect(row: Int64): Rect {
        Rect(rect.x + 1.0, rect.y + SOP_AREA_POPUP_PAD + Float32(row) * SOP_AREA_ROW_H, rect.w - 2.0,
            SOP_AREA_ROW_H)
    }
}

/** 「未指定」+ 工作区全部领域（顺序与侧栏一致：`workspace.areas` 的 order）。 */
func sopAreaChoices(workspace: Workspace): Array<SopAreaChoice> {
    let choices = ArrayList<SopAreaChoice>()
    choices.add(SopAreaChoice(Option<String>.None, "未指定"))
    for (area in workspace.areas) {
        choices.add(SopAreaChoice(Option<String>.Some(area.id), area.name, color: Option<String>.Some(area.color)))
    }
    choices.toArray()
}

/** Choice index of the current `areaId`（未知 / 已删除的领域落在「未指定」）。 */
func sopAreaIndexOf(choices: Array<SopAreaChoice>, areaId: ?String): Int64 {
    var index = 0
    for (choice in choices) {
        let same = match (choice.areaId) {
            case Some(id) => match (areaId) {
                case Some(current) => id == current
                case None => false
            }
            case None => areaId.isNone()
        }
        if (same) {
            return index
        }
        index += 1
    }
    0
}

/**
 * Popup box for `anchor` (the Area field). Uses the space below the field when it fits, flips
 * above when it does not, and clamps the whole box inside the window so the last row is never
 * clipped.
 */
func sopAreaPopupLayout(anchor: Rect, viewportHeight: Float32, count: Int64, selected: Int64): SopAreaPopup {
    if (count <= 0) {
        return SopAreaPopup(Rect(anchor.x, anchor.bottom() + 4.0, anchor.w, 0.0), 0, 0)
    }
    let padding = SOP_AREA_POPUP_PAD * 2.0
    let gap: Float32 = 4.0
    let margin: Float32 = 8.0
    let spaceBelow = max(0.0, viewportHeight - (anchor.bottom() + gap) - margin)
    let spaceAbove = max(0.0, anchor.y - gap - margin)
    let space = max(spaceBelow, spaceAbove)
    let fitRows = Int64(max(1.0, (space - padding) / SOP_AREA_ROW_H))
    let visible = sopMaxI64(1, sopMinI64(sopMinI64(count, SOP_AREA_MAX_ROWS), fitRows))
    let height = Float32(visible) * SOP_AREA_ROW_H + padding
    var top = anchor.bottom() + gap
    if (spaceBelow < height && spaceAbove >= height) {
        top = anchor.y - gap - height
    }
    top = clampF32(top, margin, sopMaxF32(margin, viewportHeight - height - margin))
    let width = max(anchor.w, SOP_AREA_POPUP_MIN_W)
    let first = sopMaxI64(0, sopMinI64(selected - visible / 2, count - visible))
    SopAreaPopup(Rect(anchor.x, top, width, height), first, visible)
}

/** 打开浮层：定位到当前领域所在行。 */
func openSopAreaPicker(state: SopViewState, choices: Array<SopAreaChoice>, areaId: ?String): Unit {
    state.areaIndex = sopAreaIndexOf(choices, areaId)
    state.areaOpen = true
}

func closeSopAreaPicker(state: SopViewState): Unit {
    state.areaOpen = false
}

/** Up/Down 在候选里移动（到边界即停，不循环），返回新的索引。 */
func moveSopAreaSelection(state: SopViewState, count: Int64, delta: Int64): Int64 {
    if (count <= 0) {
        state.areaIndex = 0
        return 0
    }
    state.areaIndex = sopMaxI64(0, sopMinI64(count - 1, state.areaIndex + delta))
    state.areaIndex
}

/** 写回 `Item.areaId`；`None` 清空归属。 */
func commitSopAreaChoice(store: AppStore, sopId: String, choices: Array<SopAreaChoice>,
    index: Int64): Bool {
    if (index < 0 || index >= choices.size) {
        return false
    }
    store.updateItem(sopId, ItemPatch().withAreaId(choices[index].areaId))
    true
}

/** Per-frame overlay: paints the list above the page and owns Up/Down/Enter/Esc. */
func paintSopAreaPicker(ctx: UiContext, view: SopFrame): Unit {
    let state = view.state
    if (!state.areaOpen) {
        return
    }
    let sop = match (view.sop) {
        case Some(value) => value
        case None =>
            state.areaOpen = false
            return
    }
    let choices = sopAreaChoices(view.workspace)
    let anchor = inspectorRects(ctx, view, scroll: view.state.inspectorScroll).areaInput
    let picker = sopAreaPopupLayout(anchor, ctx.viewportHeight, choices.size, state.areaIndex)
    let store = view.store
    let owner = "sop-area-picker"
    ctx.setOverlay(
        Overlay(
            handleEvent: {inner, event => handleSopAreaEvent(inner, store, state, sop.id, choices, picker, event)},
            render: {inner => drawSopAreaPopup(inner, view, choices, picker)},
            owner: owner
        )
    )
}

func handleSopAreaEvent(ctx: UiContext, store: AppStore, state: SopViewState, sopId: String,
    choices: Array<SopAreaChoice>, picker: SopAreaPopup, event: UiEvent): Bool {
    match (event) {
        case UiEvent.MouseDown(button, x, y) where isPrimaryPointerButton(button) =>
            match (picker.rowAt(y)) {
                case Some(index) =>
                    if (commitSopAreaChoice(store, sopId, choices, index)) {
                        state.touch()
                    }
                case None => ()
            }
            // 浮层外的按压同样关闭（遮罩语义：列表是模态的，页面不接收这一次点击）。
            closeSopAreaPicker(state)
            state.touch()
            return true
        case UiEvent.MouseMove(_, _) =>
            claimHoverIfInside(ctx, event, picker.rect, "sop-area-picker", CursorShape.Interactive)
        case UiEvent.MouseWheel(_, wheelY, _, _) =>
            let _ = moveSopAreaSelection(state, choices.size, if (wheelY < 0.0) {
                1
            } else {
                -1
            })
            ctx.requestFrame()
            return true
        case UiEvent.KeyDown(key, isRepeat) =>
            if (isRepeat) {
                return false
            }
            match (key) {
                case Key.Up =>
                    let _ = moveSopAreaSelection(state, choices.size, -1)
                    ctx.requestFrame()
                    return true
                case Key.Down =>
                    let _ = moveSopAreaSelection(state, choices.size, 1)
                    ctx.requestFrame()
                    return true
                case Key.Enter | Key.Space =>
                    if (commitSopAreaChoice(store, sopId, choices, state.areaIndex)) {
                        state.touch()
                    }
                    closeSopAreaPicker(state)
                    state.touch()
                    return true
                case Key.Escape | Key.Tab =>
                    closeSopAreaPicker(state)
                    state.touch()
                    return true
                case _ => ()
            }
        case _ => ()
    }
    return false
}

func drawSopAreaPopup(ctx: UiContext, view: SopFrame, choices: Array<SopAreaChoice>,
    picker: SopAreaPopup): Unit {
    let tk = view.tk
    let rect = picker.rect
    if (rect.w <= 0.0 || rect.h <= 0.0) {
        return
    }
    softShadow(ctx, rect, SOP_RADIUS_CTRL, tk.shadow2)
    fillRound(ctx, rect, SOP_RADIUS_CTRL, tk.color.surface)
    strokeRound(ctx, rect, SOP_RADIUS_CTRL, SOP_BORDER, tk.color.border)
    ctx.renderer.pushClip(rect)
    var row: Int64 = 0
    while (row < picker.visible) {
        let index = picker.first + row
        if (index < 0 || index >= choices.size) {
            break
        }
        let choice = choices[index]
        let rowRect = picker.rowRect(row)
        let selected = index == view.state.areaIndex
        if (selected) {
            fillRect(ctx, rowRect, tk.color.accentSoft)
        }
        var textLeft = rowRect.x + SOP_AREA_ROW_PAD_X
        match (choice.color) {
            case Some(hex) =>
                ctx.renderer.fillCircle(textLeft + SOP_AREA_DOT_R, rowRect.centerY(), SOP_AREA_DOT_R,
                    hexColor(hex, tk.color.accent))
                textLeft += SOP_AREA_DOT_R * 2.0 + 8.0
            case None => ()
        }
        let weight: Int64 = if (selected) {
            600
        } else {
            400
        }
        paintTextClipped(ctx, choice.label, textLeft, rowRect.centerY(),
            rowRect.right() - textLeft - SOP_AREA_ROW_PAD_X, SOP_INPUT_FONT, weight,
            if (choice.areaId.isNone()) {
                tk.color.textMuted
            } else {
                tk.color.text
            })
        row += 1
    }
    ctx.renderer.popClip()
}
