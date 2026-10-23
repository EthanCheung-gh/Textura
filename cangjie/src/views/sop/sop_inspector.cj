package textura.views.sop

import std.collection.*
import std.deriving.*
import cui.*
import textura.core.data.*
import textura.ui.*
import textura.views.sop.logic as lg

/*
 * Right column — `SopInspector.tsx` + `.sop-inspector*` (sop.css:682-842) and
 * `RunHistory.tsx` + `.sop-history*` (sop.css:851-908).
 *
 * Three variants, exactly like the Web build: nothing selected = SOP settings,
 * a node selected = step editor (title, notes, owner, duration, type chips,
 * checklist add/toggle/delete, duplicate/delete), an edge selected = branch label
 * presets. Every control writes through `ctx.store`.
 */

/** `.sop-inspector-head` height: `12px 16px` padding + eyebrow + title (sop.css:693). */
// 12 + 15.75 + 18.9 + 12 = 58.65 in CSS; the browser paints the bottom border on row 58, so the
// border box snaps to 58 (verified against tools/parity/ref/sop-light.png).
let SOP_INSP_HEAD_H: Float32 = 59.0  // 58 content + 1px bottom border (border-box rows 154..213)

/** Which inspector variant is on screen (`SopInspector.tsx`: node / edge / SOP). */
enum SopInspVariant {
    | SopSettings
    | Node
    | Edge
}

/** One checklist row inside the node inspector. */
class SopCheckRow {
    let entryId: String
    let checkbox: Rect
    let label: Rect
    let remove: Rect

    init(entryId: String, checkbox: Rect, label: Rect, remove: Rect) {
        this.entryId = entryId
        this.checkbox = checkbox
        this.label = label
        this.remove = remove
    }
}

/** Laid-out inspector geometry; shared by painting and hit-testing. */
class SopInspRects {
    let variant: SopInspVariant
    let card: Rect
    let head: Rect
    let body: Rect
    /** Unscrolled bottom of the last painted element (for `inspectorMaxScroll`). */
    let contentBottom: Float32
    // SOP variant.
    let nameInput: Rect
    let notesArea: Rect
    let ownerInput: Rect
    let areaInput: Rect
    let progressTrack: Rect
    let statsTop: Float32
    let recentTop: Float32
    let typeChips: Array<(String, Rect)>
    // Node variant.
    let titleInput: Rect
    let nodeNotesArea: Rect
    let durationInput: Rect
    let addChecklist: Rect
    let checkRows: Array<SopCheckRow>
    let actionButtons: Array<(String, Rect)>
    // Edge variant.
    let labelInput: Rect
    let presetChips: Array<(String, Rect)>

    init(
        variant: SopInspVariant,
        card: Rect,
        head: Rect,
        body: Rect,
        contentBottom: Float32,
        nameInput: Rect,
        notesArea: Rect,
        ownerInput: Rect,
        areaInput: Rect,
        progressTrack: Rect,
        statsTop: Float32,
        recentTop: Float32,
        typeChips: Array<(String, Rect)>,
        titleInput: Rect,
        nodeNotesArea: Rect,
        durationInput: Rect,
        addChecklist: Rect,
        checkRows: Array<SopCheckRow>,
        actionButtons: Array<(String, Rect)>,
        labelInput: Rect,
        presetChips: Array<(String, Rect)>
    ) {
        this.variant = variant
        this.card = card
        this.head = head
        this.body = body
        this.contentBottom = contentBottom
        this.nameInput = nameInput
        this.notesArea = notesArea
        this.ownerInput = ownerInput
        this.areaInput = areaInput
        this.progressTrack = progressTrack
        this.statsTop = statsTop
        this.recentTop = recentTop
        this.typeChips = typeChips
        this.titleInput = titleInput
        this.nodeNotesArea = nodeNotesArea
        this.durationInput = durationInput
        this.addChecklist = addChecklist
        this.checkRows = checkRows
        this.actionButtons = actionButtons
        this.labelInput = labelInput
        this.presetChips = presetChips
    }
}

/** `1fr 1fr` column width of `.sop-field-grid` (sop.css:733). */
func fieldColumnWidth(innerWidth: Float32): Float32 {
    (innerWidth - SOP_FIELD_GRID_GAP) / 2.0
}

/**
 * Computes every inspector box by walking the CSS box model in order (head padding,
 * body padding, 12px gaps, field label + 6px + control). Painting and hit-testing use
 * this single source of truth so the two can never drift apart.
 *
 * `scroll` shifts the whole body up by the wheel offset (the body scrolls inside the card,
 * exactly like `.sop-inspector-body { overflow-y: auto }`); painting clips to `body`, so a
 * short window scrolls its fields instead of drawing them over the run-history card.
 */
func inspectorRects(ctx: UiContext, view: SopFrame, scroll!: Float32 = 0.0): SopInspRects {
    let card = view.inspectorRect(ctx)
    let innerWidth = card.w - 2.0 - SOP_INSP_BODY_PAD_X * 2.0
    let head = Rect(snapPx(card.x + 1.0), snapPx(card.y + 1.0), card.w - 2.0, SOP_INSP_HEAD_H)
    let bodyX = snapPx(card.x + 1.0 + SOP_INSP_BODY_PAD_X)
    // Every step is pixel-snapped so the 1px rules and input borders stay crisp (matching the
    // browser, whose border boxes also land on whole pixels).
    var cursor = snapPx(head.bottom() + SOP_INSP_BODY_PAD_TOP - scroll)
    let labelHeight = SOP_FIELD_LABEL_LINE + SOP_FIELD_GAP

    let emptyRect = Rect.zero()
    let node = view.selectedNode()
    let edge = view.selectedEdge()

    if (node.isSome()) {
        let item = node.getOrThrow()
        let titleInput = Rect(bodyX, cursor + labelHeight, innerWidth, SOP_INPUT_H)
        cursor = snapPx(cursor + labelHeight + SOP_INPUT_H + SOP_INSP_GAP)
        let notesArea = Rect(bodyX, cursor + labelHeight, innerWidth, SOP_TEXTAREA_H)
        cursor = snapPx(cursor + labelHeight + SOP_TEXTAREA_H + SOP_INSP_GAP)
        let columnWidth = fieldColumnWidth(innerWidth)
        let ownerInput = Rect(bodyX, cursor + labelHeight, columnWidth, SOP_INPUT_H)
        let durationInput = Rect(bodyX + columnWidth + SOP_FIELD_GRID_GAP, cursor + labelHeight, columnWidth,
            SOP_INPUT_H)
        cursor = snapPx(cursor + labelHeight + SOP_INPUT_H + SOP_INSP_GAP)
        // 类型: a row of chips (the CSS select cannot be ported 1:1, see UI-KIT §6.12).
        cursor = snapPx(cursor + SOP_FIELD_LABEL_LINE + SOP_FIELD_GAP)
        let chips = ArrayList<(String, Rect)>()
        var chipX = bodyX
        var chipY = cursor
        let chipHeight: Float32 = 24.0
        for (kind in allNodeTypes()) {
            let label = nodeTypeLabel(kind)
            let width = measureText(ctx, label, SOP_BTN_SM_FONT, 550) + 20.0
            if (chipX + width > bodyX + innerWidth) {
                chipX = bodyX
                chipY += chipHeight + 4.0
            }
            chips.add((lg.nodeTypeId(kind), Rect(chipX, chipY, width, chipHeight)))
            chipX += width + 4.0
        }
        cursor = snapPx(chipY + chipHeight + SOP_INSP_GAP)
        // 检查项 section: `border-top` + 8px padding.
        cursor = snapPx(cursor + 1.0 + SOP_BLOCK_PAD_TOP)
        let headRowY = cursor
        let addChecklist = Rect(bodyX + innerWidth - SOP_ICON_SM, headRowY - 3.0, SOP_ICON_SM, SOP_ICON_SM)
        cursor = snapPx(headRowY + SOP_SECTION_LABEL_LINE + SOP_BLOCK_GAP)
        let rows = ArrayList<SopCheckRow>()
        let checklist = checklistOf(item)
        for (entry in checklist) {
            let checkbox = Rect(bodyX, cursor + 8.0, 14.0, 14.0)
            let remove = Rect(bodyX + innerWidth - SOP_ICON_SM, cursor + 2.0, SOP_ICON_SM, SOP_ICON_SM)
            let label = Rect(bodyX + 22.0, cursor, innerWidth - 22.0 - SOP_ICON_SM - 4.0, 30.0)
            rows.add(SopCheckRow(entry.id, checkbox, label, remove))
            cursor = snapPx(cursor + 30.0 + 8.0)
        }
        if (checklist.isEmpty()) {
            cursor = snapPx(cursor + SOP_HINT_LINE)
        }
        cursor = snapPx(cursor + SOP_INSP_GAP)
        let rowWidth = (innerWidth - 8.0) / 2.0
        let buttons = ArrayList<(String, Rect)>()
        buttons.add(("duplicate", Rect(bodyX, cursor + 1.0, rowWidth, SOP_BTN_SM_H)))
        buttons.add(("delete-node", Rect(bodyX + rowWidth + 8.0, cursor + 1.0, rowWidth, SOP_BTN_SM_H)))
        return SopInspRects(SopInspVariant.Node, card, head, Rect(bodyX, head.bottom(), innerWidth,
            card.h - head.h - 1.0), cursor + 1.0 + SOP_BTN_SM_H + scroll, emptyRect, emptyRect, ownerInput, emptyRect,
            emptyRect, 0.0, 0.0,
            chips.toArray(),
            titleInput, notesArea, durationInput, addChecklist, rows.toArray(), buttons.toArray(), emptyRect,
            Array<(String, Rect)>())
    }

    if (edge.isSome()) {
        let labelInput = Rect(bodyX, snapPx(cursor + labelHeight), innerWidth, SOP_INPUT_H)
        cursor = snapPx(cursor + labelHeight + SOP_INPUT_H + SOP_INSP_GAP)
        let presets = ArrayList<(String, Rect)>()
        var chipX = bodyX
        for (preset in ["是", "否", "通过", "补充", "继续"]) {
            let width = measureText(ctx, preset, SOP_BTN_SM_FONT, 550) + 20.0
            presets.add((preset, Rect(chipX, cursor + 1.0, width, SOP_BTN_SM_H)))
            chipX += width + 4.0
        }
        cursor += SOP_BTN_SM_H + SOP_INSP_GAP + 1.0
        let buttons = ArrayList<(String, Rect)>()
        buttons.add(("delete-edge", Rect(bodyX, cursor + 1.0, innerWidth, SOP_BTN_SM_H)))
        return SopInspRects(SopInspVariant.Edge, card, head, Rect(bodyX, head.bottom(), innerWidth,
            card.h - head.h - 1.0), cursor + 1.0 + SOP_BTN_SM_H + scroll, emptyRect, emptyRect, emptyRect, emptyRect,
            emptyRect, 0.0, 0.0,
            Array<(String, Rect)>(),
            emptyRect, emptyRect, emptyRect, emptyRect, Array<SopCheckRow>(), buttons.toArray(), labelInput,
            presets.toArray())
    }

    // SOP settings (the variant shown by the reference screenshot).
    let nameInput = Rect(bodyX, snapPx(cursor + labelHeight), innerWidth, SOP_INPUT_H)
    cursor = snapPx(cursor + labelHeight + SOP_INPUT_H + SOP_INSP_GAP)
    let notesArea = Rect(bodyX, snapPx(cursor + labelHeight), innerWidth, SOP_TEXTAREA_H)
    cursor = snapPx(cursor + labelHeight + SOP_TEXTAREA_H + SOP_INSP_GAP)
    let columnWidth = fieldColumnWidth(innerWidth)
    let ownerInput = Rect(bodyX, snapPx(cursor + labelHeight), columnWidth, SOP_INPUT_H)
    let areaInput = Rect(snapPx(bodyX + columnWidth + SOP_FIELD_GRID_GAP), snapPx(cursor + labelHeight), columnWidth,
        SOP_INPUT_H)
    cursor = snapPx(cursor + labelHeight + SOP_INPUT_H + SOP_INSP_GAP)
    // 步骤统计 block (`border-top` + 8px padding).
    let statsTop = cursor
    cursor = snapPx(cursor + 1.0 + SOP_BLOCK_PAD_TOP)
    cursor = snapPx(cursor + SOP_SECTION_LABEL_LINE + SOP_BLOCK_GAP)
    let progressTrack = Rect(bodyX, snapPx(cursor + (SOP_SECTION_LABEL_LINE - SOP_PROGRESS_H) / 2.0),
        innerWidth - 38.0, SOP_PROGRESS_H)
    cursor = snapPx(cursor + SOP_SECTION_LABEL_LINE + SOP_BLOCK_GAP)
    let chips = ArrayList<(String, Rect)>()
    var chipX = bodyX
    for ((kind, count) in stepTypeCounts(view)) {
        if (count <= 0) {
            continue
        }
        let text = "${nodeTypeLabel(kind)} ${count}"
        let width = badgeWidth(ctx, text, SOP_BADGE_FONT, SOP_BADGE_PAD_X, 550)
        chips.add((text, Rect(chipX, cursor, width, SOP_BADGE_H)))
        chipX += width + 4.0
    }
    cursor = snapPx(cursor + SOP_BADGE_H + SOP_BLOCK_GAP)
    cursor = snapPx(cursor + SOP_HINT_LINE + SOP_INSP_GAP)
    // 最近运行 block.
    let recentTop = cursor
    cursor = snapPx(cursor + 1.0 + SOP_BLOCK_PAD_TOP)
    cursor = snapPx(cursor + SOP_SECTION_LABEL_LINE + SOP_BLOCK_GAP)
    cursor += SOP_BADGE_H
    let contentBottom = cursor + scroll
    return SopInspRects(SopInspVariant.SopSettings, card, head, Rect(bodyX, head.bottom(), innerWidth,
        card.h - head.h - 1.0), contentBottom, nameInput, notesArea, ownerInput, areaInput, progressTrack, statsTop, recentTop,
        chips.toArray(), emptyRect, emptyRect, emptyRect, emptyRect, Array<SopCheckRow>(), Array<(String, Rect)>(),
        emptyRect, Array<(String, Rect)>())
}

/** `.sop-stats-types`: node type -> count, in `NODE_TYPE_LABELS` order (SopInspector.tsx:386-390). */
func stepTypeCounts(view: SopFrame): Array<(lg.SopNodeType, Int64)> {
    let result = ArrayList<(lg.SopNodeType, Int64)>()
    for (kind in allNodeTypes()) {
        var count = 0
        for (item in view.nodes) {
            if (isNodeType(nodeTypeOf(item), kind)) {
                count += 1
            }
        }
        result.add((kind, count))
    }
    result.toArray()
}

/** `checklist.filter(entry => entry.done).length` for core checklist entries. */
func countDone(entries: Array<ChecklistEntry>): Int64 {
    var done = 0
    for (entry in entries) {
        if (entry.done) {
            done += 1
        }
    }
    done
}

func checklistOf(item: Item): Array<ChecklistEntry> {
    match (item.sop) {
        case Some(data) => return data.checklist
        case None => return Array<ChecklistEntry>()
    }
}

/** `.sop-inspector-body { overflow-y: auto }`: how far the body can scroll for this window. */
func inspectorMaxScroll(ctx: UiContext, view: SopFrame): Float32 {
    let rects = inspectorRects(ctx, view)
    max(0.0, rects.contentBottom + SOP_INSP_BODY_PAD_BOTTOM - rects.body.bottom())
}

/** Clamps the retained scroll offset to the current content (content shrinks on edits). */
func clampInspectorScroll(ctx: UiContext, view: SopFrame): Float32 {
    let limit = inspectorMaxScroll(ctx, view)
    if (view.state.inspectorScroll > limit) {
        view.state.inspectorScroll = limit
    }
    if (view.state.inspectorScroll < 0.0) {
        view.state.inspectorScroll = 0.0
    }
    view.state.inspectorScroll
}

/** Inspector card: head (eyebrow / title / badge) + body per variant. */
func paintInspector(ctx: UiContext, view: SopFrame): Unit {
    let tk = view.tk
    let scroll = clampInspectorScroll(ctx, view)
    let rects = inspectorRects(ctx, view, scroll: scroll)
    let card = rects.card
    fillRound(ctx, card, SOP_RADIUS_PANEL, tk.color.surface)
    strokeRound(ctx, card, SOP_RADIUS_PANEL, SOP_BORDER, tk.color.border)

    // ---- head --------------------------------------------------------------------
    let head = rects.head
    paintHLine(ctx, head.x, head.right(), head.bottom() - 1.0, tk.color.border)
    let textLeft = head.x + SOP_INSP_HEAD_PAD_X
    let eyebrow = match (rects.variant) {
        case SopInspVariant.Node => "节点"
        case SopInspVariant.Edge => "连线"
        case _ => "SOP 设置"
    }
    let title = match (rects.variant) {
        case SopInspVariant.Node => match (view.selectedNode()) {
            case Some(item) => item.title
            case None => ""
        }
        case SopInspVariant.Edge => "分支文案"
        case _ => match (view.sop) {
            case Some(sop) => sop.title
            case None => ""
        }
    }
    let eyebrowCenter = head.y + SOP_INSP_HEAD_PAD_Y + SOP_INSP_EYEBROW_LINE / 2.0
    paintText(ctx, eyebrow, textLeft, eyebrowCenter, SOP_INSP_EYEBROW_SIZE, 650, tk.color.textFaint)
    let titleCenter = eyebrowCenter + SOP_INSP_EYEBROW_LINE / 2.0 + SOP_INSP_TITLE_LINE / 2.0
    let badgeText = match (rects.variant) {
        case SopInspVariant.Node => match (view.selectedNode()) {
            case Some(item) => nodeTypeLabel(nodeTypeOf(item))
            case None => ""
        }
        case SopInspVariant.Edge => "flow"
        case _ => "${view.nodes.size} 步"
    }
    let badgeTone = match (rects.variant) {
        case SopInspVariant.Node => SopTone.Accent
        case SopInspVariant.Edge => SopTone.Info
        case _ => SopTone.Neutral
    }
    let badgeW = badgeWidth(ctx, badgeText, SOP_BADGE_FONT, SOP_BADGE_PAD_X, 550)
    paintTextClipped(ctx, title, textLeft, titleCenter, head.w - SOP_INSP_HEAD_PAD_X * 2.0 - badgeW - 8.0,
        SOP_INSP_TITLE_SIZE, 650, tk.color.text)
    let _ = paintBadge(ctx, tk, badgeText, head.right() - SOP_INSP_HEAD_PAD_X - badgeW,
        head.y + SOP_INSP_HEAD_PAD_Y + SOP_BADGE_H / 2.0, badgeTone)

    // ---- body --------------------------------------------------------------------
    let bodyX = rects.body.x
    let innerWidth = rects.body.w
    // The body is a scroll viewport: fields beyond the card bottom are clipped (they are
    // reachable by wheel, see `handleInspector`), never drawn over the run-history card.
    ctx.renderer.pushClip(rects.body)
    match (rects.variant) {
        case SopInspVariant.Node => paintNodeInspector(ctx, view, rects)
        case SopInspVariant.Edge => paintEdgeInspector(ctx, view, rects)
        case _ => paintSopInspector(ctx, view, rects)
    }
    ctx.renderer.popClip()
    let _ = bodyX
    let _ = innerWidth
}

/** Field label (`12px/600 text-muted`) with its control below. */
func paintFieldLabel(ctx: UiContext, view: SopFrame, text: String, x: Float32, controlTop: Float32): Unit {
    paintText(ctx, text, x, controlTop - SOP_FIELD_GAP - SOP_FIELD_LABEL_LINE / 2.0, SOP_FIELD_LABEL_SIZE, 600,
        view.tk.color.textMuted)
}

/** `.sop-section-label` (`11px/650`, uppercase, `text-faint`). */
func paintSectionLabel(ctx: UiContext, view: SopFrame, text: String, x: Float32, top: Float32): Unit {
    paintText(ctx, text, x, top + SOP_SECTION_LABEL_LINE / 2.0, SOP_SECTION_LABEL_SIZE, 650, view.tk.color.textFaint)
}

/** SOP settings variant (name, notes, owner/area, stats, latest run). */
func paintSopInspector(ctx: UiContext, view: SopFrame, rects: SopInspRects): Unit {
    let tk = view.tk
    let sop = match (view.sop) {
        case Some(value) => value
        case None => return
    }
    paintFieldLabel(ctx, view, "名称", rects.nameInput.x, rects.nameInput.y)
    paintInputBox(ctx, tk, rects.nameInput, sop.title, "")
    paintFieldLabel(ctx, view, "描述", rects.notesArea.x, rects.notesArea.y)
    paintTextAreaBox(ctx, tk, rects.notesArea, sop.notes, "这个流程解决什么问题、适用范围…")
    paintFieldLabel(ctx, view, "默认负责人", rects.ownerInput.x, rects.ownerInput.y)
    let owner = match (sop.sop) {
        case Some(data) => match (data.owner) {
            case Some(value) => value
            case None => ""
        }
        case None => ""
    }
    paintInputBox(ctx, tk, rects.ownerInput, owner, "未指定")
    paintFieldLabel(ctx, view, "Area", rects.areaInput.x, rects.areaInput.y)
    paintSelectBox(ctx, tk, rects.areaInput, areaNameOrEmpty(view, sop))

    // 步骤统计 (progress + type badges + hint).
    let statsTop = rects.statsTop
    paintHLine(ctx, rects.body.x, rects.body.x + rects.body.w, statsTop, tk.color.border)
    let headTop = statsTop + 1.0 + SOP_BLOCK_PAD_TOP
    paintSectionLabel(ctx, view, "步骤统计", rects.body.x, headTop)
    let headRight = rects.body.x + rects.body.w
    let value = "${view.nodes.size} 个节点 · ${countFlowEdges(view)} 条连线"
    paintTextRight(ctx, value, headRight, headTop + SOP_SECTION_LABEL_LINE / 2.0, SOP_VALUE_SIZE, 400,
        tk.color.textMuted)
    let percent = Float32(rollupProgress(view.workspace, sop.id))
    paintProgress(ctx, tk, rects.progressTrack, percent, tk.color.accent)
    paintTextRight(ctx, "${Int64(percent)}%", headRight, rects.progressTrack.centerY(), 11.0, 400,
        tk.color.textMuted)
    for ((text, rect) in rects.typeChips) {
        let _ = paintBadge(ctx, tk, text, rect.x, rect.centerY(), SopTone.Neutral)
    }
    if (rects.typeChips.isEmpty()) {
        let hintTop = rects.progressTrack.bottom() + SOP_BLOCK_GAP + (SOP_BADGE_H - SOP_HINT_LINE) / 2.0
        paintText(ctx, "画布还是空的。", rects.body.x, hintTop + SOP_HINT_LINE / 2.0, SOP_HINT_SIZE, 400,
            tk.color.textFaint)
    }
    let hintTop = rects.progressTrack.bottom() + SOP_BLOCK_GAP + SOP_BADGE_H + SOP_BLOCK_GAP
    paintTextClipped(ctx, "拖动节点移动 · 拖动圆点连线 · Delete 删除选中", rects.body.x, hintTop + SOP_HINT_LINE / 2.0,
        rects.body.w, SOP_HINT_SIZE, 400, tk.color.textFaint)

    // 最近运行.
    let recentTop = rects.recentTop
    paintHLine(ctx, rects.body.x, rects.body.x + rects.body.w, recentTop, tk.color.border)
    let recentHeadTop = recentTop + 1.0 + SOP_BLOCK_PAD_TOP
    paintSectionLabel(ctx, view, "最近运行", rects.body.x, recentHeadTop)
    let latest = latestRunFor(view.workspace, sop.id)
    match (latest) {
        case Some(run) =>
            paintTextRight(ctx, formatDateTime(run.at), rects.body.x + rects.body.w,
                recentHeadTop + SOP_SECTION_LABEL_LINE / 2.0, SOP_VALUE_SIZE, 400, tk.color.textMuted)
            let rowCenter = recentHeadTop + SOP_SECTION_LABEL_LINE + SOP_BLOCK_GAP + SOP_BADGE_H / 2.0
            let stepTitle = match (view.nodeById(run.stepId)) {
                case Some(item) => item.title
                case None => "已删除步骤"
            }
            let badgeW = badgeWidth(ctx, runBadgeLabel(run.result), SOP_BADGE_FONT, SOP_BADGE_PAD_X, 550)
            paintTextClipped(ctx, stepTitle, rects.body.x, rowCenter, rects.body.w - badgeW - 8.0, SOP_VALUE_SIZE,
                620, tk.color.text)
            let _ = paintBadge(ctx, tk, runBadgeLabel(run.result), rects.body.x + rects.body.w - badgeW, rowCenter,
                resultTone(run.result))
        case None =>
            paintTextClipped(ctx, "还没有运行记录。点画布工具栏的「运行」开始逐步执行。", rects.body.x,
                recentHeadTop + SOP_SECTION_LABEL_LINE + SOP_BLOCK_GAP + SOP_HINT_LINE / 2.0, rects.body.w,
                SOP_HINT_SIZE, 400, tk.color.textFaint)
    }
}

func areaNameOrEmpty(view: SopFrame, item: Item): String {
    let name = view.areaName(item)
    if (name.isEmpty()) {
        return "无归属 Area"
    }
    return name
}

func countFlowEdges(view: SopFrame): Int64 {
    var count = 0
    for (edge in view.edges) {
        if (edge.edgeType == EdgeType.Flow) {
            count += 1
        }
    }
    count
}

/** `.select` box: same surface as `.input` plus the caret (see UI-KIT §6.12). */
func paintSelectBox(ctx: UiContext, tk: ThemeTokens, rect: Rect, value: String): Unit {
    paintInputBox(ctx, tk, rect, value, "")
    let caret = tk.color.textMuted
    let cx = rect.right() - SOP_INPUT_PAD_X - 4.0
    let cy = rect.centerY()
    let corners = ArrayList<Point>()
    corners.add(Point(cx - 4.0, cy - 2.0))
    corners.add(Point(cx + 4.0, cy - 2.0))
    corners.add(Point(cx, cy + 3.0))
    ctx.renderer.fillConvexPolygon(corners, caret)
}

/** Node inspector: title / notes / owner / duration / type chips / checklist / actions. */
func paintNodeInspector(ctx: UiContext, view: SopFrame, rects: SopInspRects): Unit {
    let tk = view.tk
    let item = match (view.selectedNode()) {
        case Some(value) => value
        case None => return
    }
    paintFieldLabel(ctx, view, "标题", rects.titleInput.x, rects.titleInput.y)
    paintInputBox(ctx, tk, rects.titleInput, item.title, "")
    paintFieldLabel(ctx, view, "描述", rects.nodeNotesArea.x, rects.nodeNotesArea.y)
    paintTextAreaBox(ctx, tk, rects.nodeNotesArea, item.notes, "这一步要做什么、注意什么…")
    paintFieldLabel(ctx, view, "负责人", rects.ownerInput.x, rects.ownerInput.y)
    let owner = match (item.sop) {
        case Some(data) => match (data.owner) {
            case Some(value) => value
            case None => ""
        }
        case None => ""
    }
    paintInputBox(ctx, tk, rects.ownerInput, owner, "谁来做")
    paintFieldLabel(ctx, view, "预计耗时（分钟）", rects.durationInput.x, rects.durationInput.y)
    let duration = match (item.sop) {
        case Some(data) => match (data.durationMin) {
            case Some(minutes) => "${minutes}"
            case None => ""
        }
        case None => ""
    }
    paintInputBox(ctx, tk, rects.durationInput, duration, "5")

    // 类型 chips.
    var chipsTop = rects.durationInput.bottom() + SOP_INSP_GAP
    if (!rects.typeChips.isEmpty()) {
        let firstChip = rects.typeChips[0]
        chipsTop = firstChip[1].y
    }
    paintText(ctx, "类型", rects.body.x, chipsTop - SOP_FIELD_GAP - SOP_FIELD_LABEL_LINE / 2.0, SOP_FIELD_LABEL_SIZE,
        600, tk.color.textMuted)
    let current = nodeTypeOf(item)
    for ((id, rect) in rects.typeChips) {
        let active = id == lg.nodeTypeId(current)
        if (active) {
            paintBox(ctx, rect, SOP_RADIUS_CTRL, tk.color.accentStrong, tk.color.accentStrong)
            paintTextMid(ctx, nodeTypeLabel(current), rect.x, rect.right(), rect.centerY(), SOP_BTN_SM_FONT, 550,
                tk.color.textOnStrong)
        } else {
            paintBox(ctx, rect, SOP_RADIUS_CTRL, tk.color.surface, tk.color.border)
            let kind = match (lg.parseNodeType(id)) {
                case Some(value) => value
                case None => lg.SopNodeType.Action
            }
            paintTextMid(ctx, nodeTypeLabel(kind), rect.x, rect.right(), rect.centerY(), SOP_BTN_SM_FONT, 550,
                tk.color.textMuted)
        }
    }

    // 检查项.
    let checklist = checklistOf(item)
    let sectionTop = rects.addChecklist.y + 3.0 - SOP_BLOCK_PAD_TOP - 1.0 - SOP_SECTION_LABEL_LINE
    paintHLine(ctx, rects.body.x, rects.body.x + rects.body.w, sectionTop - 1.0, tk.color.border)
    paintSectionLabel(ctx, view, "检查项", rects.body.x, sectionTop)
    let doneCount = countDone(checklist)
    paintText(ctx, "${doneCount}/${checklist.size}", rects.body.x + measureText(ctx, "检查项", 11.0, 650) + 8.0,
        sectionTop + SOP_SECTION_LABEL_LINE / 2.0, 11.0, 400, tk.color.textFaint)
    paintIconButton(ctx, tk, IconGlyph.Plus, rects.addChecklist)
    if (checklist.isEmpty()) {
        paintTextClipped(ctx, "还没有检查项。检查项会显示在节点进度条与运行条里。", rects.body.x,
            rects.addChecklist.bottom() + 8.0 + SOP_HINT_LINE / 2.0, rects.body.w, SOP_HINT_SIZE, 400,
            tk.color.textFaint)
    }
    for (row in rects.checkRows) {
        var entry: ?ChecklistEntry = None
        for (candidate in checklist) {
            if (candidate.id == row.entryId) {
                entry = Some(candidate)
            }
        }
        match (entry) {
            case Some(value) =>
                paintCheckbox(ctx, tk, row.checkbox, value.done)
                let color = if (value.done) {
                    tk.color.textMuted
                } else {
                    tk.color.text
                }
                paintTextClipped(ctx, value.text, row.label.x, row.checkbox.centerY(), row.label.w, SOP_INPUT_FONT,
                    400, color)
                paintIconButton(ctx, tk, IconGlyph.Close, row.remove, tone: SopTone.Danger)
            case None => ()
        }
    }

    // 复制 / 删除节点.
    for ((id, rect) in rects.actionButtons) {
        if (id == "duplicate") {
            paintSecondaryButton(ctx, tk, "复制节点", rect, glyph: IconGlyph.Plus, glyphSide: 14.0)
        } else {
            paintDangerButton(ctx, tk, "删除节点", rect, glyph: IconGlyph.Trash, glyphSide: 14.0)
        }
    }
}

/** `.sop-checkbox` (14x14, `accent-color: var(--accent)`). */
func paintCheckbox(ctx: UiContext, tk: ThemeTokens, rect: Rect, checked: Bool): Unit {
    if (checked) {
        paintBox(ctx, rect, 3.0, tk.color.accent, tk.color.accent)
        let side = rect.w - 4.0
        paintSpec(ctx, IconGlyph.Check, Rect(rect.x + 2.0, rect.y + 2.0, side, side), tk.color.textOnStrong)
    } else {
        paintBox(ctx, rect, 3.0, tk.color.surface, tk.color.borderStrong)
    }
}

/** Edge inspector: branch label input, presets, delete. */
func paintEdgeInspector(ctx: UiContext, view: SopFrame, rects: SopInspRects): Unit {
    let tk = view.tk
    let edge = match (view.selectedEdge()) {
        case Some(value) => value
        case None => return
    }
    let fromTitle = match (view.nodeById(edge.from)) {
        case Some(item) => item.title
        case None => "未知"
    }
    let toTitle = match (view.nodeById(edge.to)) {
        case Some(item) => item.title
        case None => "未知"
    }
    let hintTop = rects.labelInput.y - SOP_FIELD_LABEL_LINE - SOP_FIELD_GAP
    paintTextClipped(ctx, "${fromTitle} → ${toTitle}", rects.body.x, hintTop + SOP_HINT_LINE / 2.0, rects.body.w,
        SOP_HINT_SIZE, 400, tk.color.textMuted)
    paintFieldLabel(ctx, view, "标签", rects.labelInput.x, rects.labelInput.y)
    paintInputBox(ctx, tk, rects.labelInput, edge.label, "例如：是 / 否 / 补充")
    for ((preset, rect) in rects.presetChips) {
        if (preset == edge.label) {
            paintPrimaryButton(ctx, tk, preset, rect)
        } else {
            paintSecondaryButton(ctx, tk, preset, rect)
        }
    }
    for ((id, rect) in rects.actionButtons) {
        if (id == "delete-edge") {
            paintDangerButton(ctx, tk, "删除连线", rect, glyph: IconGlyph.Trash, glyphSide: 14.0)
        }
    }
}

/** Run history card (`.sop-history`, `RunHistory.tsx`). */
func paintHistory(ctx: UiContext, view: SopFrame): Unit {
    let tk = view.tk
    let rect = view.historyRect(ctx)
    fillRound(ctx, rect, SOP_RADIUS_PANEL, tk.color.surface)
    strokeRound(ctx, rect, SOP_RADIUS_PANEL, SOP_BORDER, tk.color.border)
    let sop = match (view.sop) {
        case Some(value) => value
        case None => return
    }
    let left = rect.x + 1.0 + SOP_HISTORY_PAD_X
    let right = rect.right() - 1.0 - SOP_HISTORY_PAD_X
    let runs = recentRunsFor(view.workspace, sop.id, limit: 20)
    var top = rect.y + 1.0 + SOP_HISTORY_PAD_Y
    paintSectionLabel(ctx, view, "运行历史", left, top)
    paintTextRight(ctx, "最近 ${runs.size} / 20", right, top + SOP_SECTION_LABEL_LINE / 2.0, 11.0, 400,
        tk.color.textFaint)
    top += SOP_SECTION_LABEL_LINE + SOP_BLOCK_GAP
    if (runs.isEmpty()) {
        paintText(ctx, "还没有运行记录。", left, top + SOP_HINT_LINE / 2.0, SOP_HINT_SIZE, 400, tk.color.textFaint)
        return
    }
    for (run in runs) {
        let centerY = top + SOP_BADGE_H / 2.0
        let timeText = formatDateTime(run.at)
        paintText(ctx, timeText, left, centerY, SOP_HISTORY_ITEM_SIZE, 400, tk.color.textFaint)
        let timeWidth = measureText(ctx, timeText, SOP_HISTORY_ITEM_SIZE, 400)
        let stepText = match (view.nodeById(run.stepId)) {
            case Some(item) => item.title
            case None => "已删除步骤"
        }
        let badgeText = runBadgeLabel(run.result)
        let badgeW = badgeWidth(ctx, badgeText, SOP_BADGE_FONT, SOP_BADGE_PAD_X, 550)
        paintTextClipped(ctx, stepText, left + timeWidth + 8.0, centerY, right - badgeW - 8.0 - left - timeWidth - 8.0,
            SOP_HISTORY_ITEM_SIZE, 400, tk.color.text)
        let _ = paintBadge(ctx, tk, badgeText, right - badgeW, centerY, resultTone(run.result))
        top += SOP_BADGE_H
        if (!run.note.isEmpty()) {
            top += SOP_BLOCK_GAP
            paintTextClipped(ctx, run.note, left + 4.0, top + SOP_HISTORY_NOTE_LINE / 2.0, right - left - 4.0,
                SOP_HISTORY_NOTE_SIZE, 400, tk.color.textFaint)
            top += SOP_HISTORY_NOTE_LINE
        }
        top += SOP_BLOCK_GAP
    }
}

/** Inspector + history interactions (checklist, type chips, duplicate/delete, presets). */
func handleInspector(ctx: UiContext, view: SopFrame, event: UiEvent): Bool {
    match (event) {
        case UiEvent.MouseWheel(x, y, _, dy) =>
            let rects = inspectorRects(ctx, view)
            if (!rects.body.contains(x, y)) {
                return false
            }
            // Wheel scrolls the clipped inspector body (`.sop-inspector-body { overflow-y: auto }`).
            let limit = inspectorMaxScroll(ctx, view)
            if (limit <= 0.0) {
                return false
            }
            view.state.inspectorScroll = min(limit, max(0.0, view.state.inspectorScroll - dy * 40.0))
            ctx.requestFrame()
            return true
        case UiEvent.MouseDown(button, x, y) =>
            if (!isPrimaryPointerButton(button)) {
                return false
            }
            let rect = view.inspectorRect(ctx)
            let history = view.historyRect(ctx)
            if (!rect.contains(x, y) && !history.contains(x, y)) {
                return false
            }
            let scroll = clampInspectorScroll(ctx, view)
            let rects = inspectorRects(ctx, view, scroll: scroll)
            // Only the visible part of the body is interactive.
            if (history.contains(x, y) || !rects.body.contains(x, y)) {
                return false
            }
            match (rects.variant) {
                case SopInspVariant.Node => return handleNodeInspector(ctx, view, rects, x, y)
                case SopInspVariant.Edge => return handleEdgeInspector(view, rects, x, y)
                case _ => return handleSopSettings(view, rects, x, y)
            }
        case _ => return false
    }
}

/**
 * SOP 设置：名称 / 默认负责人是画上去的「输入框」，点击打开编辑浮层
 * （`sop_prompt.cj`；行内 `TextField` 在绘制期无法登记焦点）。
 */
func handleSopSettings(view: SopFrame, rects: SopInspRects, x: Float32, y: Float32): Bool {
    let sop = match (view.sop) {
        case Some(value) => value
        case None => return false
    }
    if (rects.nameInput.contains(x, y)) {
        openSopPrompt(view.state, SopPromptKind.SopTitle, sop.id, sop.title)
        return true
    }
    if (rects.notesArea.contains(x, y)) {
        openSopPrompt(view.state, SopPromptKind.SopNotes, sop.id, sop.notes)
        return true
    }
    if (rects.ownerInput.contains(x, y)) {
        openSopPrompt(view.state, SopPromptKind.SopOwner, sop.id, sopOwnerOf(sop))
        return true
    }
    if (rects.areaInput.contains(x, y)) {
        openSopAreaPicker(view.state, sopAreaChoices(view.workspace), sop.areaId)
        view.state.touch()
        return true
    }
    false
}

func sopOwnerOf(item: Item): String {
    match (item.sop) {
        case Some(data) => match (data.owner) {
            case Some(value) => value
            case None => ""
        }
        case None => ""
    }
}

/** 节点检查器：标题 / 描述 / 负责人 / 预计耗时 / 检查项文本都走编辑浮层。 */
func handleNodeFields(view: SopFrame, rects: SopInspRects, item: Item, x: Float32, y: Float32): Bool {
    if (rects.titleInput.contains(x, y)) {
        openSopPrompt(view.state, SopPromptKind.NodeTitle, item.id, item.title)
        return true
    }
    if (rects.nodeNotesArea.contains(x, y)) {
        openSopPrompt(view.state, SopPromptKind.NodeNotes, item.id, item.notes)
        return true
    }
    if (rects.ownerInput.contains(x, y)) {
        openSopPrompt(view.state, SopPromptKind.NodeOwner, item.id, sopOwnerOf(item))
        return true
    }
    if (rects.durationInput.contains(x, y)) {
        let minutes = match (item.sop) {
            case Some(data) => match (data.durationMin) {
                case Some(value) => "${value}"
                case None => ""
            }
            case None => ""
        }
        openSopPrompt(view.state, SopPromptKind.NodeDuration, item.id, minutes)
        return true
    }
    for (row in rects.checkRows) {
        if (row.label.contains(x, y)) {
            for (entry in checklistOf(item)) {
                if (entry.id == row.entryId) {
                    openSopPrompt(view.state, SopPromptKind.CheckText, item.id, entry.text, entry: entry.id)
                }
            }
            return true
        }
    }
    false
}

func handleNodeInspector(ctx: UiContext, view: SopFrame, rects: SopInspRects, x: Float32, y: Float32): Bool {
    let item = match (view.selectedNode()) {
        case Some(value) => value
        case None => return false
    }
    let _ = ctx
    // 标题 / 负责人 / 耗时 / 检查项文本：画布自绘的字段，点击打开编辑浮层。
    if (handleNodeFields(view, rects, item, x, y)) {
        return true
    }
    // 检查项: toggle / delete / add.
    for (row in rects.checkRows) {
        if (row.checkbox.contains(x, y)) {
            let next = ArrayList<ChecklistEntry>()
            for (entry in checklistOf(item)) {
                if (entry.id == row.entryId) {
                    next.add(ChecklistEntry(entry.id, entry.text, !entry.done))
                } else {
                    next.add(entry)
                }
            }
            commitChecklist(view, item.id, next.toArray())
            return true
        }
        if (row.remove.contains(x, y)) {
            let next = ArrayList<ChecklistEntry>()
            for (entry in checklistOf(item)) {
                if (entry.id != row.entryId) {
                    next.add(entry)
                }
            }
            commitChecklist(view, item.id, next.toArray())
            return true
        }
    }
    if (rects.addChecklist.contains(x, y)) {
        let next = ArrayList<ChecklistEntry>(checklistOf(item))
        next.add(ChecklistEntry("chk_${view.state.runSeq}", "新检查项", false))
        view.state.runSeq += 1
        commitChecklist(view, item.id, next.toArray())
        return true
    }
    // 类型 chips.
    for ((id, chip) in rects.typeChips) {
        if (chip.contains(x, y)) {
            match (lg.parseNodeType(id)) {
                case Some(kind) =>
                    if (!isNodeType(kind, nodeTypeOf(item))) {
                        let patch = SopPatch()
                        patch.nodeType = SetValue<SopNodeType>.Value(coreNodeType(kind))
                        view.store.updateItem(item.id, ItemPatch().withSop(patch))
                        view.state.touch()
                    }
                case None => ()
            }
            return true
        }
    }
    // 复制 / 删除节点.
    for ((id, button) in rects.actionButtons) {
        if (!button.contains(x, y)) {
            continue
        }
        if (id == "delete-node") {
            deleteSelection(view)
            return true
        }
        duplicateNode(view, item)
        return true
    }
    return false
}

func handleEdgeInspector(view: SopFrame, rects: SopInspRects, x: Float32, y: Float32): Bool {
    let edge = match (view.selectedEdge()) {
        case Some(value) => value
        case None => return false
    }
    if (rects.labelInput.contains(x, y)) {
        openSopPrompt(view.state, SopPromptKind.EdgeLabel, edge.id, edge.label)
        return true
    }
    for ((preset, chip) in rects.presetChips) {
        if (chip.contains(x, y)) {
            view.store.updateEdge(edge.id, label: preset)
            view.state.touch()
            return true
        }
    }
    for ((id, button) in rects.actionButtons) {
        if (id == "delete-edge" && button.contains(x, y)) {
            view.store.deleteEdge(edge.id)
            view.store.notify("已删除连线", tone: NoticeTone.Info)
            view.state.selectedEdgeId = None
            view.state.touch()
            return true
        }
    }
    return false
}

func commitChecklist(view: SopFrame, itemId: String, entries: Array<ChecklistEntry>): Unit {
    let patch = SopPatch()
    patch.checklist = SetValue<Array<ChecklistEntry>>.Value(entries)
    view.store.updateItem(itemId, ItemPatch().withSop(patch))
    view.state.touch()
}

/** `复制节点`: same fields, offset by 30px, inserted as a sibling step. */
func duplicateNode(view: SopFrame, item: Item): Unit {
    let sopPatch = SopPatch()
    sopPatch.nodeType = SetValue<SopNodeType>.Value(coreNodeType(nodeTypeOf(item)))
    let position = view.nodePos(item.id)
    sopPatch.canvasX = SetValue<Float64>.Value(position.x + 30.0)
    sopPatch.canvasY = SetValue<Float64>.Value(position.y + 30.0)
    match (item.sop) {
        case Some(data) =>
            sopPatch.checklist = SetValue<Array<ChecklistEntry>>.Value(data.checklist)
            sopPatch.owner = SetValue<?String>.Value(data.owner)
            sopPatch.durationMin = SetValue<?Int64>.Value(data.durationMin)
        case None => ()
    }
    let parentId = match (view.sop) {
        case Some(sop) => sop.id
        case None => ""
    }
    let input = NewItemInput(ItemKind.Step, item.title, notes: item.notes, parentId: parentId,
        status: Some(ItemStatus.Next), areaId: item.areaId, sop: sopPatch)
    let created = view.store.createItem(input)
    view.state.selectedNodeId = Some(created.id)
    view.store.select(created.id)
    view.state.previewDisabled = true
    view.store.notify("已复制节点", tone: NoticeTone.Success)
    view.state.touch()
}
