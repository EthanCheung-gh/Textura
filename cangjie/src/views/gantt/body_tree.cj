package textura.views.gantt

import std.collection.*
import cui.*
import textura.ui.*
import textura.views.gantt.logic.*

/*
 * 左侧任务树（GanttTree.tsx / gantt.css:70-333）。
 *
 * 列宽：`.gantt-tree { width: 272px; border-right: 1px }`（border-box）→ 内容宽 271，
 * 右侧 1px 描边落在 x=271；行高 36、表头 52（含 1px 底边）。
 * 行内左内边距 `padding: 0 8px`，条目行再叠加 `paddingLeft: 8 + depth * 14`
 * （GanttTree.tsx:135 `8 + row.depth * 14`）。
 */

/** `.gantt-tree` 内容宽（不含右侧 1px 描边）。 */
let TREE_INNER_WIDTH: Float32 = TREE_WIDTH - 1.0

/** 条目行缩进步长（GanttTree.tsx:135）。 */
let TREE_INDENT: Float32 = 14.0

/** 行内左右内边距（`.gantt-tree-row { padding: 0 8px }`，条目行右 6px）。 */
let TREE_PADDING_LEFT: Float32 = 8.0
let TREE_PADDING_RIGHT: Float32 = 6.0

/** 状态圆点尺寸（`.gantt-status-dot { width/height: 6px }`）。 */
let STATUS_DOT_RADIUS: Float32 = 3.0

/** 行内 flex `gap: 6px`（`.gantt-tree-row { gap: 6px }`）。 */
let TREE_GAP: Float32 = 6.0

func drawTree(ctx: UiContext, body: GanttBody): Unit {
    let tokens = body.tokens
    let ink = body.ink
    let rect = body.treeRect()
    if (rect.w <= 0.0 || rect.h <= 0.0) {
        return
    }
    let headCenterY = rect.y + HEADER_H / 2.0

    // `.gantt-tree-head`：11px/600 `text-faint`，左右 12px 内边距，底部 1px 描边
    drawText(ctx, "任务", rect.x + tokens.space.s3, headCenterY, TREE_HEAD_SIZE, 600, tokens.color.textFaint)
    drawTextRight(ctx, "${itemRowCount(body.rows)} 条", rect.x + TREE_INNER_WIDTH - tokens.space.s3, headCenterY,
        TREE_HEAD_SIZE, 500, tokens.color.textFaint)
    hairline(ctx, rect.x, rect.y + HEADER_H - 1.0, TREE_INNER_WIDTH, tokens.color.border)
    vline(ctx, rect.x + TREE_INNER_WIDTH, rect.y, rect.h, tokens.color.border)

    // 行区域：吸顶表头之下，按窗口虚拟化（GanttTree.tsx:274-287）
    let rowTop = rect.y + HEADER_H
    let rowHeight = rect.h - HEADER_H
    if (rowHeight <= 0.0) {
        return
    }
    ctx.renderer.pushClip(Rect(rect.x, rowTop, TREE_INNER_WIDTH, rowHeight))
    let window = visibleRows(maxF64(0.0, Float64(body.scrollTop) - HEADER_HEIGHT), Float64(rowHeight),
        ROW_HEIGHT, 4.0, total: Some(body.rows.size))
    var index = window.start
    while (index < window.end) {
        drawTreeRow(ctx, body, index, rowTop + Float32(index) * ROW_H - body.scrollTop)
        index += 1
    }
    if (body.rows.size == 0) {
        drawText(ctx, "暂无项目或行动。", rect.x + tokens.space.s4, rowTop + 18.0, TREE_ITEM_SIZE, 400,
            tokens.color.textFaint)
    }
    ctx.renderer.popClip()
}

func itemRowCount(rows: Array<GanttTreeRow>): Int64 {
    var count = 0
    for (row in rows) {
        match (row) {
            case GanttTreeRow.Item(_) => count += 1
            case GanttTreeRow.Group(_) => ()
        }
    }
    count
}

func drawTreeRow(ctx: UiContext, body: GanttBody, index: Int64, top: Float32): Unit {
    let tokens = body.tokens
    let ink = body.ink
    let rect = body.treeRect()
    let row = body.rows[index]
    let selected = body.rowSelected(row)
    let hovered = body.state.hoverRow == treeRowId(row)

    // 背景：分组 `--bg-subtle`，选中 `--accent-soft`，悬停 `--surface-2`
    match (row) {
        case GanttTreeRow.Group(_) =>
            fillRect(ctx, Rect(rect.x, top, TREE_INNER_WIDTH, ROW_H), tokens.color.bgSubtle)
        case GanttTreeRow.Item(_) => ()
    }
    if (hovered) {
        fillRect(ctx, Rect(rect.x, top, TREE_INNER_WIDTH, ROW_H), tokens.color.surface2)
    }
    if (selected) {
        fillRect(ctx, Rect(rect.x, top, TREE_INNER_WIDTH, ROW_H), tokens.color.accentSoft)
        // `box-shadow: inset 2px 0 0 var(--accent)`
        fillRect(ctx, Rect(rect.x, top, 2.0, ROW_H), tokens.color.accent)
    }
    // 行底细线 `color-mix(border 55%, transparent)`
    hairline(ctx, rect.x, top + ROW_H - 1.0, TREE_INNER_WIDTH, ink.treeRowLine)

    match (row) {
        case GanttTreeRow.Group(group) => drawGroupRow(ctx, body, group, selected, top)
        case GanttTreeRow.Item(item) => drawItemRow(ctx, body, item, selected, top)
    }
}

func isRowSelected(selectedId: String, row: GanttTreeRow): Bool {
    if (selectedId.isEmpty()) {
        return false
    }
    match (row) {
        case GanttTreeRow.Group(group) => match (group.item) {
            case Some(item) => item.id == selectedId
            case None => false
        }
        case GanttTreeRow.Item(item) => item.id == selectedId
    }
}

/** 分组行（GanttTree.tsx:195-248）。 */
func drawGroupRow(ctx: UiContext, body: GanttBody, group: GanttGroupRow, selected: Bool, top: Float32): Unit {
    let tokens = body.tokens
    let ink = body.ink
    let rect = body.treeRect()
    let _ = selected
    let centerY = top + ROW_H / 2.0

    // 折叠箭头：18×18 按钮内居中 14px 图标（`.gantt-group-toggle`）
    let toggleX = rect.x + TREE_PADDING_LEFT
    let toggleY = top + (ROW_H - 18.0) / 2.0
    let glyph = if (group.collapsed) {
        IconGlyph.ChevronRight
    } else {
        IconGlyph.ChevronDown
    }
    paintSpec(ctx, glyph, Rect(toggleX + 2.0, toggleY + 2.0, 14.0, 14.0), tokens.color.textFaint)

    // 分组图标：14px、`--accent`
    let folderX = toggleX + 18.0 + TREE_GAP
    paintSpec(ctx, IconGlyph.Folder, Rect(folderX, centerY - 7.0, 14.0, 14.0), tokens.color.accent)

    // `.gantt-group-main`：两行文本（12.5px/620 + 10.5px），行高 1.15、上下 3/4 内边距
    let mainX = folderX + 14.0 + TREE_GAP
    let titleCenterY = top + GROUP_TITLE_CENTER
    let metaCenterY = top + GROUP_META_CENTER
    let rangeText = rangeLabelOf(group.start, group.end)
    let meta = "${rangeText} · ${group.progress}%"
    let metaWidth = textAdvance(ctx, meta, GROUP_META_SIZE, 400)
    let countText = "${group.count}"
    let countWidth = textAdvance(ctx, countText, GROUP_COUNT_SIZE, 550) + 12.0
    let titleMax = max(0.0, rect.x + TREE_INNER_WIDTH - TREE_PADDING_RIGHT - countWidth - 5.0 - mainX)
    let title = ellipsize(ctx, group.title, titleMax, GROUP_TITLE_SIZE, 620)
    drawText(ctx, title, mainX, titleCenterY, GROUP_TITLE_SIZE, 620, tokens.color.text)

    // `.gantt-group-count`：10px/550 药丸，1px 描边、`--surface` 底
    let pillX = mainX + textAdvance(ctx, title, GROUP_TITLE_SIZE, 620) + 5.0
    let pillRect = Rect(pillX, titleCenterY - 8.5, countWidth, 17.0)
    fillRound(ctx, pillRect, 8.5, tokens.color.surface)
    cssBorder(ctx, pillRect, 8.5, tokens.metrics.borderWidth, tokens.color.border)
    drawTextCenter(ctx, countText, pillRect.centerX(), titleCenterY, GROUP_COUNT_SIZE, 550, tokens.color.textFaint)

    // `.gantt-group-meta`：10.5px `text-faint`
    let metaX = mainX
    drawText(ctx, ellipsize(ctx, meta, max(0.0, rect.x + TREE_INNER_WIDTH - TREE_PADDING_RIGHT - metaX), GROUP_META_SIZE,
        400), metaX, metaCenterY, GROUP_META_SIZE, 400, tokens.color.textFaint)
    let _ = metaWidth

    // `.gantt-group-progress`：行底 2px 强调条，宽度 = 进度百分比
    let barWidth = clampRange(Float32(group.progress) / 100.0, 0.0, 1.0) * TREE_INNER_WIDTH
    if (barWidth > 0.0) {
        fillRect(ctx, Rect(rect.x, top + ROW_H - 3.0, barWidth, 2.0), tokens.color.accent)
    }
}

/** 条目行（GanttTree.tsx:98-186）。 */
func drawItemRow(ctx: UiContext, body: GanttBody, item: GanttItemRow, selected: Bool, top: Float32): Unit {
    let tokens = body.tokens
    let ink = body.ink
    let rect = body.treeRect()
    let centerY = top + ROW_H / 2.0
    let padLeft = TREE_PADDING_LEFT + Float32(item.depth) * TREE_INDENT
    let row = item.row

    // 状态圆点（`.gantt-status-dot`）
    dot(ctx, rect.x + padLeft + STATUS_DOT_RADIUS, centerY, STATUS_DOT_RADIUS, statusDotColor(tokens, row.status))

    let titleX = rect.x + padLeft + STATUS_DOT_RADIUS * 2.0 + TREE_GAP
    let range = itemRange(row)
    let progress = displayProgress(row)
    let rightEdge = rect.x + TREE_INNER_WIDTH - TREE_PADDING_RIGHT

    // 右侧块：已排期显示进度，未排期显示「未排期 + 排期」按钮
    var rightBlockLeft = rightEdge
    match (range) {
        case Some(_) =>
            let label = "${progress}%"
            let color = if (selected) {
                tokens.color.textMuted
            } else {
                tokens.color.textFaint
            }
            drawTextRight(ctx, label, rightEdge, centerY, ITEM_PROGRESS_SIZE, 400, color)
            rightBlockLeft = rightEdge - textAdvance(ctx, label, ITEM_PROGRESS_SIZE, 400)
        case None =>
            let buttonText = "排期"
            let buttonWidth = textAdvance(ctx, buttonText, ITEM_SCHEDULE_SIZE, 600) + 14.0
            let buttonHeight: Float32 = 19.0
            let buttonRect = Rect(rightEdge - buttonWidth, centerY - buttonHeight / 2.0, buttonWidth, buttonHeight)
            fillRound(ctx, buttonRect, buttonHeight / 2.0, tokens.color.accentSoft)
            cssBorder(ctx, buttonRect, buttonHeight / 2.0, tokens.metrics.borderWidth, tokens.color.accent)
            drawTextCenter(ctx, buttonText, buttonRect.centerX(), centerY, ITEM_SCHEDULE_SIZE, 600,
                tokens.color.accentInk)
            let unscheduledColor = if (selected) {
                tokens.color.textMuted
            } else {
                tokens.color.textFaint
            }
            drawTextRight(ctx, "未排期", buttonRect.x - TREE_GAP, centerY, ITEM_PROGRESS_SIZE, 400, unscheduledColor)
            rightBlockLeft = buttonRect.x - TREE_GAP - textAdvance(ctx, "未排期", ITEM_PROGRESS_SIZE, 400)
    }

    // 超期标签（`.gantt-overdue`）：结束日期已过且未完成、未放弃
    if (isOverdue(row, body.today)) {
        let label = "超期"
        let width = textAdvance(ctx, label, ITEM_OVERDUE_SIZE, 600)
        drawTextRight(ctx, label, rightBlockLeft - TREE_GAP, centerY, ITEM_OVERDUE_SIZE, 600,
            tokens.color.dangerInk)
        rightBlockLeft = rightBlockLeft - TREE_GAP - width
    }

    // 标题（`text-overflow: ellipsis`）
    let titleMax = max(0.0, rightBlockLeft - TREE_GAP - titleX)
    let done = row.status == GanttStatus.Done
    let color = if (done) {
        tokens.color.textMuted
    } else {
        tokens.color.text
    }
    let title = ellipsize(ctx, row.title, titleMax, ITEM_TITLE_SIZE, 400)
    drawText(ctx, title, titleX, centerY, ITEM_TITLE_SIZE, 400, color)
    if (done) {
        // `.is-done .gantt-item-title { text-decoration: line-through; color: border-strong }`
        // 删除线落在字形中部（参考图实测 centerY − 0.5）
        let width = textAdvance(ctx, title, ITEM_TITLE_SIZE, 400)
        hairline(ctx, titleX, centerY - 0.5, width, tokens.color.borderStrong)
    }
    let _ = ink
}

/** `isOverdue`（GanttTree.tsx:35-39）。 */
func isOverdue(row: GanttRow, today: String): Bool {
    match (itemRange(row)) {
        case Some(range) =>
            range.end < today && row.status != GanttStatus.Done && row.status != GanttStatus.Dropped
        case None => false
    }
}

/** `.gantt-status-dot.is-*`（gantt.css:242-263）。 */
func statusDotColor(tokens: ThemeTokens, status: GanttStatus): Color {
    let c = tokens.color
    match (status) {
        case GanttStatus.Active => c.accent
        case GanttStatus.Done => c.ok
        case GanttStatus.Waiting => c.warn
        case GanttStatus.Scheduled => c.info
        case _ => c.textFaint
    }
}
