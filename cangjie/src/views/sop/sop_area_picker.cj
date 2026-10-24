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
 * 点击字段 → 弹层列出「未指定」+ `workspace.areas`，Up/Down 移动、Enter 写回、
 * Esc / 点击浮层外 / 再次点触发字段关闭。
 *
 * ## 三条硬约束（真机现场换来的，别改回去）
 *
 * 1. **登记时机必须是 layout，不是 draw。** `DesktopApp.stepFrame` 的顺序是
 *    `build → layout → 事件派发 → draw`，而 `buildAndLayoutOnce` 每帧开头清空浮层栈；
 *    在 `draw` 里 `setOverlay` 的浮层要等到本帧画完才进栈，下一帧 build 就被清掉，
 *    于是**事件永远到不了它**（真机：点选项没反应、点外面穿透到画布选中了连线）。
 *    `ModalHost` / `InlineEditorHost` 都在 layout 登记，这里与它们一致。
 * 2. **弹层是模态的：消费所有指针事件。** 按下/抬起/移动/滚轮一律 `return true`，
 *    所以面板之外的那一下不会落到画布；页面侧还有一道 `state.areaOpen` 兜底
 *    （`sop.cj` 的 `handle`）。
 * 3. **锚点跨帧。** 打开时记下字段的窗口绝对矩形；每帧只在「检查器仍是 SOP 设置、
 *    且字段还在可见 body 内」时刷新。字段没了（换选中项）就关掉，不拿 `Rect.zero()`
 *    去排版——那会把列表画到窗口左上角/左侧边栏上（真机现场）。
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
/** 弹层与字段之间、与窗口边缘之间的留白。 */
let SOP_AREA_GAP: Float32 = 4.0
let SOP_AREA_MARGIN: Float32 = 8.0
/** 浮层 owner：跨帧原位替换（同 owner 重复登记不会叠层）。 */
let SOP_AREA_PICKER_OWNER: String = "sop-area-picker"

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

    /** Choice index under `(x, y)`, or `None` outside the rows / outside the panel. */
    func rowAt(x: Float32, y: Float32): ?Int64 {
        if (!rect.contains(x, y)) {
            return None
        }
        if (y < rect.y + SOP_AREA_POPUP_PAD || y >= rect.bottom() - SOP_AREA_POPUP_PAD) {
            return None
        }
        let row = Int64((y - rect.y - SOP_AREA_POPUP_PAD) / SOP_AREA_ROW_H)
        if (row < 0 || row >= visible) {
            return None
        }
        Some(first + row)
    }

    /** Row-only hit test (kept for tests / callers that already know the pointer is in the panel). */
    func rowAt(y: Float32): ?Int64 {
        rowAt(rect.centerX(), y)
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
 * above when it does not, and clamps the whole box inside the window — horizontally too, so a
 * field near the right edge cannot push the list over the sidebar or off-screen.
 */
func sopAreaPopupLayout(anchor: Rect, viewportWidth: Float32, viewportHeight: Float32, count: Int64,
    selected: Int64): SopAreaPopup {
    let width = min(max(anchor.w, SOP_AREA_POPUP_MIN_W), max(0.0, viewportWidth - SOP_AREA_MARGIN * 2.0))
    let left = clampF32(anchor.x, SOP_AREA_MARGIN, sopMaxF32(SOP_AREA_MARGIN, viewportWidth - width - SOP_AREA_MARGIN))
    let padding = SOP_AREA_POPUP_PAD * 2.0
    if (count <= 0) {
        return SopAreaPopup(Rect(left, anchor.bottom() + SOP_AREA_GAP, width, 0.0), 0, 0)
    }
    let spaceBelow = max(0.0, viewportHeight - (anchor.bottom() + SOP_AREA_GAP) - SOP_AREA_MARGIN)
    let spaceAbove = max(0.0, anchor.y - SOP_AREA_GAP - SOP_AREA_MARGIN)
    let space = max(spaceBelow, spaceAbove)
    let fitRows = Int64(max(1.0, (space - padding) / SOP_AREA_ROW_H))
    let visible = sopMaxI64(1, sopMinI64(sopMinI64(count, SOP_AREA_MAX_ROWS), fitRows))
    let height = Float32(visible) * SOP_AREA_ROW_H + padding
    var top = anchor.bottom() + SOP_AREA_GAP
    if (spaceBelow < height && spaceAbove >= height) {
        top = anchor.y - SOP_AREA_GAP - height
    }
    top = clampF32(top, SOP_AREA_MARGIN, sopMaxF32(SOP_AREA_MARGIN, viewportHeight - height - SOP_AREA_MARGIN))
    let first = sopMaxI64(0, sopMinI64(selected - visible / 2, count - visible))
    SopAreaPopup(Rect(left, top, width, height), first, visible)
}

/**
 * 打开浮层：锚点 = 被点字段的**窗口绝对矩形**，选中行 = 当前领域。
 *
 * 锚点在打开时快照一次，之后每帧只在字段仍然可见时刷新（见 `syncSopAreaAnchor`）。
 */
func openSopAreaPicker(state: SopViewState, anchor: Rect, choices: Array<SopAreaChoice>, areaId: ?String): Unit {
    state.areaIndex = sopAreaIndexOf(choices, areaId)
    state.areaAnchor = anchor
    state.areaPopup = None
    state.areaHover = -1
    state.areaOpen = anchor.w > 0.0 && anchor.h > 0.0
}

func closeSopAreaPicker(state: SopViewState): Unit {
    state.areaOpen = false
    state.areaPopup = None
    state.areaHover = -1
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

/**
 * 每帧刷新锚点（在页面 `layout` 里调用，早于事件派发）：检查器滚动、resize、换选中项都会
 * 反映到这里。字段消失（换成了节点/连线检查器，或滚出可见 body）时**关闭**弹层，绝不拿
 * `Rect.zero()` 去排版。
 */
func syncSopAreaAnchor(ctx: UiContext, view: SopFrame): Unit {
    let state = view.state
    if (!state.areaOpen) {
        return
    }
    if (view.sop.isNone()) {
        closeSopAreaPicker(state)
        return
    }
    let rects = inspectorRects(ctx, view, scroll: clampInspectorScroll(ctx, view))
    let settingsVariant = match (rects.variant) {
        case SopInspVariant.SopSettings => true
        case _ => false
    }
    let usable = settingsVariant && rects.areaInput.w > 0.0 && rects.areaInput.h > 0.0
    if (!usable) {
        closeSopAreaPicker(state)
        state.touch()
        return
    }
    // 字段被检查器 body 裁掉时不可见：弹层跟着消失，而不是贴在卡片边上。
    let visible = rects.body.intersection(rects.areaInput)
    if (visible.w <= 0.0 || visible.h <= 0.0) {
        closeSopAreaPicker(state)
        state.touch()
        return
    }
    state.areaAnchor = rects.areaInput
}

/**
 * Per-frame overlay registration (called from `SopPageWidget.layout`).
 *
 * 登记在 layout、不是 draw：见文件头「三条硬约束」第 1 条。浮层同时是遮罩——它消费所有指针
 * 事件，所以打开期间画布收不到任何按下，关闭的那一下也不会漏给画布。
 */
func layoutSopAreaPicker(ctx: UiContext, view: SopFrame): Unit {
    let state = view.state
    if (!state.areaOpen) {
        state.areaPopup = None
        ctx.removeOverlay(SOP_AREA_PICKER_OWNER)
        return
    }
    let sop = match (view.sop) {
        case Some(value) => value
        case None =>
            closeSopAreaPicker(state)
            ctx.removeOverlay(SOP_AREA_PICKER_OWNER)
            return
    }
    let choices = sopAreaChoices(view.workspace)
    let popup = sopAreaPopupLayout(state.areaAnchor, ctx.viewportWidth, ctx.viewportHeight, choices.size,
        state.areaIndex)
    state.areaPopup = Some(popup)
    let store = view.store
    ctx.setOverlay(
        Overlay(
            handleEvent: {inner, event => handleSopAreaEvent(inner, store, state, sop.id, choices, event)},
            render: {inner => drawSopAreaPopup(inner, view, choices, state)},
            owner: SOP_AREA_PICKER_OWNER
        )
    )
}

/**
 * 浮层的模态输入协议（全部消费，绝不透给画布）：
 *
 * | 事件 | 行为 |
 * |---|---|
 * | 主键按下 · 在候选行上 | 写回 `Item.areaId` 并关闭 |
 * | 主键按下 · 其他任何位置（含再次点 Area 字段） | 关闭，不写回 |
 * | 指针抬起 / 移动 / 滚轮 | 抬起吞掉，移动更新高亮，滚轮在候选里移动 |
 * | `Esc` / `Tab` | 关闭 |
 * | `Up` / `Down` / `Enter` / `Space` | 移动 / 写回 |
 */
func handleSopAreaEvent(ctx: UiContext, store: AppStore, state: SopViewState, sopId: String,
    choices: Array<SopAreaChoice>, event: UiEvent): Bool {
    match (event) {
        case UiEvent.MouseDown(button, x, y) =>
            if (isPrimaryPointerButton(button)) {
                let popup = match (state.areaPopup) {
                    case Some(value) => value
                    case None => return true
                }
                match (popup.rowAt(x, y)) {
                    case Some(index) =>
                        if (commitSopAreaChoice(store, sopId, choices, index)) {
                            closeSopAreaPicker(state)
                            state.touch()
                            ctx.requestFrame()
                        }
                    case None =>
                        // 面板外（含触发字段本身）与面板内的空白/内边距：关闭，不写回。
                        closeSopAreaPicker(state)
                        state.touch()
                        ctx.requestFrame()
                }
            }
            return true
        case UiEvent.MouseUp(_, _, _) => return true
        case UiEvent.MouseMove(x, y) =>
            let popup = match (state.areaPopup) {
                case Some(value) => value
                case None => return true
            }
            let hover = match (popup.rowAt(x, y)) {
                case Some(index) => index
                case None => -1
            }
            if (hover != state.areaHover) {
                state.areaHover = hover
                ctx.requestFrame()
            }
            claimHoverIfInside(ctx, event, popup.rect, SOP_AREA_PICKER_OWNER, CursorShape.Interactive)
            return true
        case UiEvent.MouseWheel(_, wheelY, _, _) =>
            if (wheelY != 0.0) {
                let _ = moveSopAreaSelection(state, choices.size, if (wheelY < 0.0) {
                    1
                } else {
                    -1
                })
                ctx.requestFrame()
            }
            return true
        case UiEvent.KeyDown(key, isRepeat) =>
            if (isRepeat) {
                return true
            }
            match (key) {
                case Key.Up =>
                    let _ = moveSopAreaSelection(state, choices.size, -1)
                    ctx.requestFrame()
                case Key.Down =>
                    let _ = moveSopAreaSelection(state, choices.size, 1)
                    ctx.requestFrame()
                case Key.Enter | Key.Space =>
                    if (commitSopAreaChoice(store, sopId, choices, state.areaIndex)) {
                        closeSopAreaPicker(state)
                        state.touch()
                        ctx.requestFrame()
                    }
                case Key.Escape | Key.Tab =>
                    closeSopAreaPicker(state)
                    state.touch()
                    ctx.requestFrame()
                case _ => ()
            }
            return true
        case UiEvent.KeyUp(_) => return true
        case UiEvent.TextInput(_) => return true
        case _ => return false
    }
}

/** Paints the list; geometry/selection come from `state` so a replayed overlay stays current. */
func drawSopAreaPopup(ctx: UiContext, view: SopFrame, choices: Array<SopAreaChoice>,
    state: SopViewState): Unit {
    let tk = view.tk
    let picker = match (state.areaPopup) {
        case Some(value) => value
        case None => return
    }
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
        let selected = index == state.areaIndex
        if (selected) {
            fillRect(ctx, rowRect, tk.color.accentSoft)
        } else if (index == state.areaHover) {
            fillRect(ctx, rowRect, tk.color.surface2)
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
