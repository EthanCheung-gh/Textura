package textura.views.sop

import std.collection.*
import std.deriving.*
import cui.*
import textura.core.data.*
import textura.ui.*

/*
 * Left column — `src/modules/sop/SopList.tsx` + `.sop-list*` (sop.css:31-225).
 *
 * 44px head (`流程` + count + new-SOP icon button), scrollable list of SOP cards
 * (`--space-2` padding, 2px item gap, active card = surface + border + shadow-1),
 * and the footer hint. Clicking a row switches the active SOP, the plus button
 * creates one through `store.createItem`, the row's trash icon deletes it.
 */

/** `.sop-list { border-radius: var(--radius-lg) }` box. */
func listPanelRect(ctx: UiContext, view: SopFrame): Rect {
    view.listRect(ctx)
}

func listHeadRect(ctx: UiContext, view: SopFrame): Rect {
    let panel = listPanelRect(ctx, view)
    return Rect(panel.x + 1.0, panel.y + 1.0, panel.w - 2.0, SOP_LIST_HEAD_H)
}

/** One SOP card; `index` is the position inside `sopList(workspace)`. */
func listRowRect(ctx: UiContext, view: SopFrame, index: Int64): Rect {
    let panel = listPanelRect(ctx, view)
    let top = panel.y + 1.0 + SOP_LIST_HEAD_H + 1.0 + SOP_LIST_PAD + Float32(index) * (listRowHeight(ctx, view) +
        SOP_ROW_GAP)
    return Rect(panel.x + 1.0 + SOP_LIST_PAD, top, panel.w - 2.0 - SOP_LIST_PAD * 2.0, listRowHeight(ctx, view))
}

/** `7px 8px` padding + title line + 1px + meta line (the badge makes it 20.8px tall). */
func listRowHeight(ctx: UiContext, view: SopFrame): Float32 {
    let _ = ctx
    let _ = view
    return 2.0 + SOP_ROW_PAD_Y * 2.0 + SOP_ROW_TITLE_LINE + 1.0 + max(SOP_ROW_META_LINE, SOP_ROW_BADGE_H)
}

func listFootRect(ctx: UiContext, view: SopFrame): Rect {
    let panel = listPanelRect(ctx, view)
    let height = SOP_LIST_FOOT_H
    return Rect(panel.x + 1.0, panel.y + panel.h - 1.0 - height, panel.w - 2.0, height)
}

/** `.sop-list-row` icon action area (two 26px icon buttons, `opacity: 0` until hover). */
func listActionsWidth(): Float32 {
    SOP_ICON_SM * 2.0
}

func paintList(ctx: UiContext, view: SopFrame): Unit {
    let tk = view.tk
    let panel = listPanelRect(ctx, view)
    fillRound(ctx, panel, SOP_RADIUS_PANEL, tk.color.bgSubtle)
    strokeRound(ctx, panel, SOP_RADIUS_PANEL, SOP_BORDER, tk.color.border)

    // ---- head -------------------------------------------------------------------
    let head = listHeadRect(ctx, view)
    // `.sop-list-head { height: 44px; border-bottom: 1px }` is border-box: the rule sits inside.
    paintHLine(ctx, head.x, head.right(), head.bottom() - 1.0, tk.color.border)
    let centerY = head.y + head.h / 2.0
    let heading = "流程"
    paintText(ctx, heading, head.x + 16.0, centerY, 12.0, 650, tk.color.textMuted)
    let headingRight = head.x + 16.0 + measureText(ctx, heading, 12.0, 650)
    paintText(ctx, "${view.sops.size}", headingRight + 8.0, centerY, 11.5, 400, tk.color.textFaint)
    let plusRect = iconSmRect(head.right() - 8.0 - SOP_ICON_SM, centerY)
    paintIconButton(ctx, tk, IconGlyph.Plus, plusRect)

    // ---- rows -------------------------------------------------------------------
    let foot = listFootRect(ctx, view)
    if (view.sops.isEmpty()) {
        paintTextClipped(ctx, "没有 SOP", panel.x + 16.0, head.bottom() + 24.0, panel.w - 32.0, 14.0, 600,
            tk.color.text)
        return
    }
    var index = 0
    for (summary in view.sops) {
        let row = listRowRect(ctx, view, index)
        if (row.bottom() > foot.y - 4.0) {
            break
        }
        paintListRow(ctx, view, summary, row)
        index += 1
    }

    // ---- footer -----------------------------------------------------------------
    paintHLine(ctx, foot.x, foot.right(), foot.y, tk.color.border)
    let footCenter = foot.y + foot.h / 2.0
    let iconSide: Float32 = 13.0
    paintSpec(ctx, IconGlyph.Edit, Rect(foot.x + 16.0, footCenter - iconSide / 2.0, iconSide, iconSide),
        tk.color.textFaint)
    paintTextClipped(ctx, "双击重命名 · 删除会级联清除步骤与连线", foot.x + 16.0 + iconSide + 8.0, footCenter,
        foot.w - 32.0 - iconSide - 8.0, 10.5, 400, tk.color.textFaint)
}

/** One `.sop-list-row` card. */
func paintListRow(ctx: UiContext, view: SopFrame, summary: SopSummary, row: Rect): Unit {
    let tk = view.tk
    let active = match (view.sop) {
        case Some(sop) => sop.id == summary.sop.id
        case None => false
    }
    if (active) {
        paintShadow1(ctx, tk, row, SOP_RADIUS_CTRL)
        paintBox(ctx, row, SOP_RADIUS_CTRL, tk.color.surface, tk.color.border)
    }
    let inner = Rect(row.x + 1.0, row.y + 1.0, row.w - 2.0, row.h - 2.0)
    let mainRight = inner.right() - 2.0 - listActionsWidth()
    let contentLeft = inner.x + SOP_ROW_PAD_X
    let contentRight = mainRight - SOP_ROW_PAD_X

    // `.sop-list-area`: 8px dot, transparent + inset ring when the SOP has no area.
    let dotCenterY = inner.y + inner.h / 2.0
    match (summary.sop.areaId) {
        case Some(_) =>
            let color = view.areaColor(summary.sop)
            match (color) {
                case Some(hex) => ctx.renderer.fillCircle(contentLeft + 4.0, dotCenterY, 4.0, hexColor(hex,
                    tk.color.surface2))
                case None => ()
            }
        case None =>
            ctx.renderer.fillCircle(contentLeft + 4.0, dotCenterY, 4.0, tk.color.borderStrong)
    }

    let textLeft = contentLeft + 8.0 + 8.0
    let titleCenter = inner.y + SOP_ROW_PAD_Y + SOP_ROW_TITLE_LINE / 2.0
    paintTextClipped(ctx, summary.sop.title, textLeft, titleCenter, contentRight - textLeft, SOP_ROW_TITLE_SIZE,
        if (active) {
            640
        } else {
            560
        }, tk.color.text)

    let metaCenter = inner.y + SOP_ROW_PAD_Y + SOP_ROW_TITLE_LINE + 1.0 + max(SOP_ROW_META_LINE, SOP_ROW_BADGE_H) / 2.0
    let areaName = view.areaName(summary.sop)
    let meta = if (areaName.isEmpty()) {
        "${summary.stepCount} 步"
    } else {
        "${summary.stepCount} 步 · ${areaName}"
    }
    let badgeText = match (summary.latestRun) {
        case Some(run) => runBadgeLabel(run.result)
        case None => "未运行"
    }
    let tone = match (summary.latestRun) {
        case Some(run) => resultTone(run.result)
        case None => SopTone.Neutral
    }
    let badgeW = badgeWidth(ctx, badgeText, SOP_ROW_BADGE_FONT, SOP_ROW_BADGE_PAD_X, 550)
    paintTextClipped(ctx, meta, textLeft, metaCenter, contentRight - textLeft - badgeW - 8.0, SOP_ROW_META_SIZE, 400,
        tk.color.textFaint)
    let _ = paintBadge(ctx, tk, badgeText, contentRight - badgeW, metaCenter, tone, font: SOP_ROW_BADGE_FONT,
        padX: SOP_ROW_BADGE_PAD_X, height: SOP_ROW_BADGE_H)

    // `.sop-list-actions { opacity: 0 }` (sop.css:192): the rename/delete icons only show on
    // hover, so the resting card is text-only. They stay clickable for the hit-tester.
}

/** `SopList.tsx` RUN_BADGE labels: 通过 / 未通过 / 跳过. */
func runBadgeLabel(result: RunResult): String {
    match (result) {
        case RunResult.Pass => return "通过"
        case RunResult.Fail => return "未通过"
        case RunResult.Skip => return "跳过"
    }
}

/** `pass/fail/skip` -> badge tone (`SopList.tsx` RUN_BADGE). */
func resultTone(result: RunResult): SopTone {
    match (result) {
        case RunResult.Pass => return SopTone.Ok
        case RunResult.Fail => return SopTone.Danger
        case RunResult.Skip => return SopTone.Warn
    }
}

/**
 * `#rrggbb` -> `Color`. `Area.color` is a domain palette value (not a design token), so the
 * view has to decode it; unparsable values fall back to the passed token colour.
 */
func hexColor(hex: String, fallback: Color): Color {
    if (hex.size < 7 || !hex.startsWith("#")) {
        return fallback
    }
    let r = parseHexPair(hex, 1)
    let g = parseHexPair(hex, 3)
    let b = parseHexPair(hex, 5)
    match (r) {
        case Some(rv) => match (g) {
            case Some(gv) => match (b) {
                case Some(bv) => return Color.rgb(rv, gv, bv)
                case None => ()
            }
            case None => ()
        }
        case None => ()
    }
    return fallback
}

func parseHexPair(hex: String, offset: Int64): ?Int64 {
    var value: Int64 = 0
    for (index in offset..offset + 2) {
        let code = hexDigit(hex, index)
        match (code) {
            case Some(digit) => value = value * 16 + digit
            case None => return None
        }
    }
    return Some(value)
}

func hexDigit(hex: String, index: Int64): ?Int64 {
    if (index < 0 || index >= hex.size) {
        return None
    }
    let byte = hex[index]
    if (byte >= UInt8(0x30) && byte <= UInt8(0x39)) {
        return Some(Int64(byte - UInt8(0x30)))
    }
    if (byte >= UInt8(0x41) && byte <= UInt8(0x46)) {
        return Some(Int64(byte - UInt8(0x41)) + 10)
    }
    if (byte >= UInt8(0x61) && byte <= UInt8(0x66)) {
        return Some(Int64(byte - UInt8(0x61)) + 10)
    }
    return None
}

func handleList(ctx: UiContext, view: SopFrame, event: UiEvent): Bool {
    match (event) {
        case UiEvent.MouseDown(pressButton, x, y) where isPrimaryPointerButton(pressButton) =>
            let panel = listPanelRect(ctx, view)
            if (!panel.contains(x, y)) {
                return false
            }
            // New SOP (`sop-list-head` IconButton).
            let head = listHeadRect(ctx, view)
            let plusRect = iconSmRect(head.right() - 8.0 - SOP_ICON_SM, head.y + head.h / 2.0)
            if (plusRect.contains(x, y)) {
                return createSop(view)
            }
            var index = 0
            for (summary in view.sops) {
                let row = listRowRect(ctx, view, index)
                if (row.contains(x, y)) {
                    let inner = Rect(row.x + 1.0, row.y + 1.0, row.w - 2.0, row.h - 2.0)
                    let mainRight = inner.right() - 2.0 - listActionsWidth()
                    let editRect = iconSmRect(mainRight + 2.0, inner.y + inner.h / 2.0)
                    let trashRect = iconSmRect(mainRight + 2.0 + SOP_ICON_SM, inner.y + inner.h / 2.0)
                    if (trashRect.contains(x, y)) {
                        view.store.deleteItems([summary.sop.id])
                        if (view.state.selectedSopId == Some(summary.sop.id)) {
                            view.state.selectedSopId = None
                        }
                        view.state.selectedNodeId = None
                        view.state.selectedEdgeId = None
                        view.state.session = None
                        view.state.branchOpen = false
                        view.store.notify("已删除 SOP「${summary.sop.title}」及其步骤", tone: NoticeTone.Info)
                        view.state.touch()
                        return true
                    }
                    if (editRect.contains(x, y)) {
                        // Renaming needs a text field; the Web build opens an inline input. The
                        // port selects the SOP and leaves the rename draft to the inspector.
                        selectSop(view, summary.sop.id)
                        return true
                    }
                    selectSop(view, summary.sop.id)
                    return true
                }
                index += 1
            }
        case _ => ()
    }
    return false
}

/** Switching SOP clears the canvas selection and the run session (SopPage.tsx:50-54). */
func selectSop(view: SopFrame, id: String): Unit {
    view.state.selectedSopId = Some(id)
    view.state.selectedNodeId = None
    view.state.selectedEdgeId = None
    view.state.session = None
    view.state.branchOpen = false
    view.state.viewReady = false
    view.state.previewDisabled = false
    view.store.select(id)
    view.state.touch()
}

/** `sop-list-head` plus button -> `createItem({ kind: 'sop' })` (SopList.tsx:79-91). */
func createSop(view: SopFrame): Bool {
    let input = NewItemInput(ItemKind.Sop, "新建 SOP")
    let created = view.store.createItem(input)
    selectSop(view, created.id)
    view.store.notify("已创建 SOP「新建 SOP」", tone: NoticeTone.Success)
    return true
}
