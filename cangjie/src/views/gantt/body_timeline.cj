package textura.views.gantt

import std.collection.*
import std.math.sqrt
import cui.*
import textura.core.data as data
import textura.ui.*
import textura.views.gantt.logic.*

/*
 * 时间轴：吸顶两级表头 + 网格 + 汇总条 + 任务条 + 依赖折线 + 今日线
 * （GanttTimeline.tsx / GanttBar.tsx / GanttDependencies.tsx，gantt.css:335-785）。
 *
 * 坐标系：
 * - 画布 x：`dateToX(日期, range.start, pxPerDay)`，原点在时间轴起点（不是视口）；
 * - 屏幕 x = 时间轴左边 + 画布 x − scrollLeft；
 * - 行 y：画布 y = `rowIndex * 36`，屏幕 y = 表头底 + 画布 y − scrollTop。
 */

func drawTimeline(ctx: UiContext, body: GanttBody): Unit {
    let rect = body.timelineRect()
    if (rect.w <= 0.0 || rect.h <= 0.0) {
        return
    }
    let tokens = body.tokens
    let ink = body.ink
    let config = zoomConfig(body.zoom)
    let px = Float32(config.pxPerDay)
    let header = buildHeader(body.range, body.zoom, today: body.today)
    let total = Float32(totalWidth(body.range, config.pxPerDay))
    let todayX = minFloat(total, maxFloat(0.0,
        Float32(diffDays(body.range.start, body.today)) * px + px / 2.0))

    let rowViewport = max(0.0, rect.h - HEADER_H)

    // 列窗口（左右各 2 列缓冲）与分组窗口（左右各 1 个）
    let widthList = columnWidths(header)
    let columnWindow = visibleColumns(Float64(body.scrollLeft), Float64(rect.w), widthList, 2.0)
    let groupWidths = ArrayList<Float64>()
    for (group in header.groups) {
        groupWidths.add(group.width)
    }
    let groupWindow = visibleColumns(Float64(body.scrollLeft), Float64(rect.w), groupWidths.toArray(), 1.0)

    // ---- 行区域：行底 / 过去遮罩 / 周末底色 / 网格线 / 月分隔线（CSS z-index 2 的 .gantt-layer）
    ctx.renderer.pushClip(Rect(rect.x, rect.y + HEADER_H, rect.w, rowViewport))
    let rowWindow = visibleRows(maxF64(0.0, Float64(body.scrollTop) - HEADER_HEIGHT),
        Float64(rowViewport), ROW_HEIGHT, 4.0, total: Some(body.rows.size))
    var index = rowWindow.start
    while (index < rowWindow.end) {
        drawTimelineRow(ctx, body, index, rect.y + HEADER_H + Float32(index) * ROW_H - body.scrollTop)
        index += 1
    }
    // `.gantt-past`：0..todayX，`bg-subtle` 45%
    let pastRight = rect.x + todayX - body.scrollLeft
    if (pastRight > rect.x) {
        fillRect(ctx, Rect(rect.x, rect.y + HEADER_H, minFloat(pastRight - rect.x, rect.w), rowViewport),
            ink.past)
    }
    // `.gantt-weekend`：可视列范围内每个周六/周日一条，`bg-subtle` 62%
    drawWeekendStripes(ctx, body, header, columnWindow, rect, rowViewport, px)
    // `.gantt-grid-line` / `.gantt-month-line`
    var column = columnWindow.start
    while (column < columnWindow.end) {
        let x = rect.x + Float32(header.columns[column].x) - body.scrollLeft
        if (x >= rect.x - 1.0 && x <= rect.right()) {
            vline(ctx, x, rect.y + HEADER_H, rowViewport, ink.gridLine)
        }
        column += 1
    }
    var group = groupWindow.start
    while (group < groupWindow.end) {
        let x = rect.x + Float32(header.groups[group].x) - body.scrollLeft
        if (x >= rect.x - 1.0 && x <= rect.right()) {
            vline(ctx, x, rect.y + HEADER_H, rowViewport, tokens.color.borderStrong)
        }
        group += 1
    }
    ctx.renderer.popClip()

    // ---- 汇总条 / 任务条 / 依赖 / 今日线（CSS z-index 3..6）
    ctx.renderer.pushClip(Rect(rect.x, rect.y + HEADER_H, rect.w, rowViewport))
    drawSummaryBars(ctx, body, rowWindow, rect)
    let rects = drawBars(ctx, body, rowWindow, rect, px)
    drawDependencies(ctx, body, rects, rect, total)
    let todayLineX = rect.x + todayX - body.scrollLeft
    if (todayLineX >= rect.x && todayLineX <= rect.right()) {
        vline(ctx, todayLineX, rect.y + HEADER_H, rowViewport, tokens.color.accent)
    }
    ctx.renderer.popClip()

    // ---- 吸顶表头
    drawTimelineHeader(ctx, body, header, columnWindow, groupWindow, rect, todayX)
    drawDragTip(ctx, body, rect, px)
}

/** 一行的时间轴底色与分隔线（`.gantt-row`）。 */
func drawTimelineRow(ctx: UiContext, body: GanttBody, index: Int64, y: Float32): Unit {
    let tokens = body.tokens
    let ink = body.ink
    let rect = body.timelineRect()
    let row = body.rows[index]
    let selected = isRowSelected(body.selectedId, row)
    let hovered = body.state.hoverRow == treeRowId(row)
    match (row) {
        case GanttTreeRow.Group(_) =>
            // `.gantt-row.is-group { background: color-mix(bg-subtle 72%, transparent) }`
            fillRect(ctx, Rect(rect.x, y, rect.w, ROW_H),
                if (selected) {
                    ink.groupRowSelected
                } else {
                    ink.groupRow
                })
        case GanttTreeRow.Item(_) => ()
    }
    if (hovered) {
        fillRect(ctx, Rect(rect.x, y, rect.w, ROW_H), tokens.color.surface2)
    }
    if (selected && !isGroupRow(row)) {
        fillRect(ctx, Rect(rect.x, y, rect.w, ROW_H), tokens.color.accentSoft)
    }
    hairline(ctx, rect.x, y + ROW_H - 1.0, rect.w, ink.timelineRowLine)
}

func drawWeekendStripes(ctx: UiContext, body: GanttBody, header: TimelineHeader, window: WindowRange, rect: Rect,
    rowViewport: Float32, px: Float32): Unit {
    if (window.start >= window.end) {
        return
    }
    let ink = body.ink
    let firstKey = header.columns[window.start].start
    let lastKey = header.columns[window.end - 1].end
    var cursor = firstKey
    var guard = 0
    while (cursor <= lastKey && guard < 400) {
        guard += 1
        match (parseDateKey(cursor)) {
            case Some(number) =>
                let weekday = weekdayOf(number)
                if (weekday == 0 || weekday == 6) {
                    let x = rect.x + Float32(dateToX(cursor, body.range.start, Float64(px))) - body.scrollLeft
                    let band = Rect(x, rect.y + HEADER_H, px, rowViewport)
                    // 只画视口内的部分（视口裁剪已生效，这里只跳过明显不可见的列）
                    if (band.right() > rect.x && band.x < rect.right()) {
                        fillRect(ctx, band, ink.weekend)
                    }
                }
            case None => ()
        }
        cursor = addDaysKey(cursor, 1)
    }
}

/** 分组汇总条（`.gantt-summary-bar`：8px 药丸、`--accent` 描边、进度实心填充）。 */
func drawSummaryBars(ctx: UiContext, body: GanttBody, window: WindowRange, rect: Rect): Unit {
    let tokens = body.tokens
    let config = zoomConfig(body.zoom)
    var index = window.start
    while (index < window.end) {
        match (body.rows[index]) {
            case GanttTreeRow.Group(group) => match (group.start) {
                case Some(start) => match (group.end) {
                    case Some(end) =>
                        let geometry = barGeometry(BarRange(start, end), body.range.start, config.pxPerDay)
                        let x = rect.x + Float32(geometry.x) - body.scrollLeft
                        let width = maxFloat(6.0, Float32(geometry.width))
                        let y = rect.y + HEADER_H + Float32(index) * ROW_H - body.scrollTop + 14.0
                        let barRect = Rect(x, y, width, 8.0)
                        if (barRect.right() > rect.x && barRect.x < rect.right()) {
                            let selected = isRowSelected(body.selectedId, body.rows[index])
                            fillRound(ctx, barRect, 4.0, tokens.color.surface2)
                            let fillWidth = clampRange(Float32(group.progress) / 100.0, 0.0, 1.0) * width
                            if (fillWidth > 0.0) {
                                fillRound(ctx, Rect(x, y, fillWidth, 8.0), 4.0, tokens.color.accent)
                            }
                            cssBorder(ctx, barRect, 4.0, tokens.metrics.borderWidth,
                                if (selected) {
                                    tokens.color.accentInk
                                } else {
                                    tokens.color.accent
                                })
                        }
                    case None => ()
                }
                case None => ()
            }
            case GanttTreeRow.Item(_) => ()
        }
        index += 1
    }
}

/** 任务条；返回可见条的依赖端点表（`id → DepRect`）。 */
func drawBars(ctx: UiContext, body: GanttBody, window: WindowRange, rect: Rect, px: Float32): HashMap<String, DepRect> {
    let rects = HashMap<String, DepRect>()
    let config = zoomConfig(body.zoom)
    let blocks = ArrayList<DepRect>()
    var index = window.start
    while (index < window.end) {
        match (body.rows[index]) {
            case GanttTreeRow.Item(item) =>
                match (itemRange(item.row)) {
                    case Some(base) =>
                        let preview = match (body.state.gesture) {
                            case Some(gesture) =>
                                if (gesture.id == item.id) {
                                    gesture.preview()
                                } else {
                                    base
                                }
                            case None => base
                        }
                        let geometry = barGeometry(preview, body.range.start, config.pxPerDay)
                        let depRect = depRect(geometry, index)
                        rects.add(item.id, depRect)
                        blocks.add(depRect)
                        let x = rect.x + Float32(geometry.x) - body.scrollLeft
                        let y = rect.y + HEADER_H + Float32(index) * ROW_H - body.scrollTop
                        if (x + Float32(geometry.width) > rect.x && x < rect.right()) {
                            drawBar(ctx, body, item, geometry, index, x, y)
                        }
                    case None => ()
                }
            case GanttTreeRow.Group(_) => ()
        }
        index += 1
    }
    let _ = px
    let _ = blocks
    rects
}

/** 单条任务条（GanttBar.tsx + gantt.css:529-689）。 */
func drawBar(ctx: UiContext, body: GanttBody, item: GanttItemRow, geometry: BarGeometry, index: Int64, x: Float32,
    y: Float32): Unit {
    let tokens = body.tokens
    let ink = body.ink
    let row = item.row
    let selected = item.id == body.selectedId
    let dragging = match (body.state.gesture) {
        case Some(gesture) => gesture.id == item.id
        case None => false
    }
    let overdue = row.status != GanttStatus.Done && row.status != GanttStatus.Dropped && isOverdue(row, body.today)
    let progress = displayProgress(row)

    if (row.kind == GanttKind.Milestone) {
        // 里程碑：菱形 13×13 旋转 45°（↔ 对角线 18.4），标题在右侧 20px 处
        let centerX = x + 6.5
        let centerY = y + BAR_TOP + 11.0
        diamond(ctx, centerX, centerY, 9.19, tokens.color.accent)
        if (selected) {
            diamond(ctx, centerX, centerY, 12.19, ink.barFill)
        }
        drawText(ctx, row.title, x + 20.0, y + BAR_TOP + 10.0, BAR_LABEL_SIZE, 400, tokens.color.text)
        return
    }

    let width = Float32(geometry.width)
    let barRect = Rect(x, y + BAR_TOP, width, BAR_H)
    let done = row.status == GanttStatus.Done
    let fillColor = if (done) {
        ink.barFillDone
    } else {
        ink.barFill
    }
    let accentColor = if (done) {
        tokens.color.ok
    } else {
        tokens.color.accent
    }
    let labelColor = if (done) {
        tokens.color.textMuted
    } else {
        tokens.color.text
    }

    // `--shadow-1` + 底色
    shadow1(ctx, tokens, barRect, BAR_RADIUS)
    fillRound(ctx, barRect, BAR_RADIUS, if (done) {
        tokens.color.bgSubtle
    } else {
        tokens.color.surface2
    })
    // 进度填充：`left/top/bottom: 0; width: progress%` + `border-bottom: 2px accent`
    let innerWidth = maxFloat(0.0, width - 2.0)
    let fillWidth = innerWidth * clampRange(Float32(progress) / 100.0, 0.0, 1.0)
    if (fillWidth > 0.0) {
        ctx.renderer.pushClip(Rect(barRect.x + 1.0, barRect.y + 1.0, innerWidth, BAR_H - 2.0))
        fillRect(ctx, Rect(barRect.x + 1.0, barRect.y + 1.0, fillWidth, BAR_H - 2.0), fillColor)
        fillRect(ctx, Rect(barRect.x + 1.0, barRect.y + BAR_H - 3.0, fillWidth, 2.0), accentColor)
        ctx.renderer.popClip()
    }
    // 描边：状态语义（`.is-active` accent / `.is-scheduled` info / `.is-done` 强描边）
    var borderColor = ink.strongBorder
    match (row.status) {
        case GanttStatus.Active => borderColor = tokens.color.accent
        case GanttStatus.Scheduled => borderColor = tokens.color.info
        case _ => ()
    }
    if (overdue) {
        borderColor = tokens.color.danger
        cssRing(ctx, barRect, BAR_RADIUS, tokens.metrics.borderWidth, ink.overdueRing)
    }
    if (selected) {
        borderColor = tokens.color.accentInk
        cssRing(ctx, barRect, BAR_RADIUS, tokens.metrics.borderWidth, tokens.color.accentInk)
    }
    cssBorder(ctx, barRect, BAR_RADIUS, tokens.metrics.borderWidth, borderColor)
    if (dragging) {
        cssRing(ctx, barRect, BAR_RADIUS, tokens.metrics.borderWidth, tokens.color.accentInk)
    }

    // 标题：`padding: 0 8px`、11.5px、`overflow: hidden`
    let labelWidth = maxFloat(0.0, width - 16.0)
    if (labelWidth > 0.0) {
        let label = ellipsize(ctx, row.title, labelWidth, BAR_LABEL_SIZE, 400)
        drawText(ctx, label, x + 8.0, barRect.centerY(), BAR_LABEL_SIZE, 400, labelColor)
    }
    let _ = index
}

/** 依赖折线（GanttDependencies.tsx + gantt.css:717-751）。 */
func drawDependencies(ctx: UiContext, body: GanttBody, rects: HashMap<String, DepRect>, rect: Rect,
    total: Float32): Unit {
    if (body.depends.size == 0 || rects.size == 0) {
        return
    }
    let tokens = body.tokens
    let blockers = ArrayList<DepRect>()
    for ((_, value) in rects) {
        blockers.add(value)
    }
    let all = blockers.toArray()
    for (edge in body.depends) {
        let dependent: ?DepRect = rects.get(edge.from)
        let prerequisite: ?DepRect = rects.get(edge.to)
        if (dependent.isNone() || prerequisite.isNone()) {
            continue
        }
        let from = dependent.getOrThrow()
        let to = prerequisite.getOrThrow()
        let hot = !body.selectedId.isEmpty() && (edge.from == body.selectedId || edge.to == body.selectedId)
        let color = if (hot) {
            tokens.color.accentInk
        } else {
            tokens.color.textMuted
        }
        let strokeWidth: Float32 = if (hot) {
            2.2
        } else {
            1.3
        }
        let points = dependencyPath(from, to, all, Float64(total))
        var step = 1
        while (step < points.size) {
            let previous = points[step - 1]
            let point = points[step]
            ctx.renderer.strokeLine(rect.x + Float32(previous.x) - body.scrollLeft,
                rect.y + HEADER_H + Float32(previous.y) - body.scrollTop,
                rect.x + Float32(point.x) - body.scrollLeft,
                rect.y + HEADER_H + Float32(point.y) - body.scrollTop,
                Pen(width: strokeWidth, color: color))
            step += 1
        }
        // 箭头（`marker` 7×7、`refX 6`：尖端落在折线末点）
        let last = points.size - 1
        drawArrow(ctx, body, points[last].x, points[last].y, points[last - 1].x, points[last - 1].y, rect, color)
        if (hot) {
            dot(ctx, rect.x + Float32(to.x2) - body.scrollLeft,
                rect.y + HEADER_H + Float32(to.cy) - body.scrollTop, 2.2, tokens.color.accentInk)
        }
    }
}

func drawArrow(ctx: UiContext, body: GanttBody, tipXValue: Float64, tipYValue: Float64, fromX: Float64,
    fromY: Float64, rect: Rect, color: Color): Unit {
    let dx = Float32(tipXValue - fromX)
    let dy = Float32(tipYValue - fromY)
    let length = Float32(sqrt(Float64(dx * dx + dy * dy)))
    if (length <= 0.01) {
        return
    }
    let ux = dx / length
    let uy = dy / length
    let tipX = rect.x + Float32(tipXValue) - body.scrollLeft
    let tipY = rect.y + HEADER_H + Float32(tipYValue) - body.scrollTop
    let baseX = tipX - ux * 7.0
    let baseY = tipY - uy * 7.0
    let half: Float32 = 3.5
    triangle(ctx, tipX, tipY, baseX - uy * half, baseY + ux * half, baseX + uy * half, baseY - ux * half, color)
}

/** 吸顶表头（`.gantt-header`，gantt.css:363-458）。 */
func drawTimelineHeader(ctx: UiContext, body: GanttBody, header: TimelineHeader, columnWindow: WindowRange,
    groupWindow: WindowRange, rect: Rect, todayX: Float32): Unit {
    let tokens = body.tokens
    let ink = body.ink
    let secondaryCenter = rect.y + HEADER_H / 4.0 * 3.0

    ctx.renderer.pushClip(Rect(rect.x, rect.y, rect.w, HEADER_H))
    // 上层：月 / 季分组；贴住左边缘的标签保持可读（`.is-pinned`）
    var group = groupWindow.start
    while (group < groupWindow.end) {
        let entry = header.groups[group]
        let left = maxFloat(rect.x + Float32(entry.x) - body.scrollLeft, rect.x)
        let right = rect.x + Float32(entry.x + entry.width) - body.scrollLeft
        let width = right - left
        if (width >= 2.0) {
            let pinned = left > rect.x + Float32(entry.x) - body.scrollLeft
            if (!pinned) {
                vline(ctx, left, rect.y, HEADER_H / 2.0 - 1.0, tokens.color.border)
            }
            drawText(ctx, entry.label, left + tokens.space.s2, rect.y + HEADER_H / 4.0, HEADER_GROUP_SIZE, 600,
                tokens.color.textMuted)
        }
        group += 1
    }
    // 下层：日 / 周 / 月列
    var column = columnWindow.start
    while (column < columnWindow.end) {
        let entry = header.columns[column]
        let left = rect.x + Float32(entry.x) - body.scrollLeft
        if (left + Float32(entry.width) > rect.x && left < rect.right()) {
            if (entry.weekend) {
                fillRect(ctx, Rect(left, rect.y + HEADER_H / 2.0, Float32(entry.width),
                    HEADER_H / 2.0 - 1.0), tokens.color.bgSubtle)
            }
            vline(ctx, left, rect.y + HEADER_H / 2.0, HEADER_H / 2.0 - 1.0, ink.columnLine)
            let labelColor = if (entry.past) {
                tokens.color.textFaint
            } else {
                tokens.color.textMuted
            }
            match (entry.sublabel) {
                case Some(sublabel) =>
                    let width = Float32(entry.width)
                    let labelWidth = textAdvance(ctx, entry.label, HEADER_COLUMN_SIZE, 400)
                    let subWidth = textAdvance(ctx, sublabel, HEADER_SUBLABEL_SIZE, 400)
                    let startX = left + (width - labelWidth - 3.0 - subWidth) / 2.0
                    drawText(ctx, entry.label, startX, secondaryCenter, HEADER_COLUMN_SIZE, 400, labelColor)
                    drawText(ctx, sublabel, startX + labelWidth + 3.0, secondaryCenter, HEADER_SUBLABEL_SIZE, 400,
                        tokens.color.textFaint)
                case None =>
                    drawTextCenter(ctx, entry.label, left + Float32(entry.width) / 2.0, secondaryCenter,
                        HEADER_COLUMN_SIZE, 400, labelColor)
            }
        }
        column += 1
    }
    hairline(ctx, rect.x, rect.y + HEADER_H - 1.0, rect.w, tokens.color.border)
    // `.gantt-today-marker`：2px 强调色竖条 + 「今天」药丸
    let markerX = rect.x + todayX - body.scrollLeft
    if (markerX >= rect.x - 2.0 && markerX <= rect.right() + 2.0) {
        fillRect(ctx, Rect(markerX - 1.0, rect.y, 2.0, HEADER_H), tokens.color.accent)
        let pillText = "今天"
        let pillWidth = textAdvance(ctx, pillText, TODAY_PILL_SIZE, 600) + 10.0
        let pillRect = Rect(markerX + 2.0, rect.y + 2.0, pillWidth, 16.0)
        fillRound(ctx, pillRect, 8.0, tokens.color.accentStrong)
        drawTextCenter(ctx, pillText, pillRect.centerX(), pillRect.centerY(), TODAY_PILL_SIZE, 600,
            tokens.color.textOnStrong)
    }
    ctx.renderer.popClip()
}

/** 拖拽提示（`.gantt-drag-tip`，GanttTimeline.tsx:439-450）。 */
func drawDragTip(ctx: UiContext, body: GanttBody, rect: Rect, px: Float32): Unit {
    let gesture = match (body.state.gesture) {
        case Some(value) => value
        case None => return
    }
    let preview = gesture.preview()
    let config = zoomConfig(body.zoom)
    let geometry = barGeometry(preview, body.range.start, config.pxPerDay)
    let x = rect.x + Float32(geometry.x) - body.scrollLeft
    let top = maxFloat(4.0, Float32(gesture.rowIndex) * ROW_H - 22.0)
    let y = rect.y + HEADER_H + top - body.scrollTop
    let days = diffDays(preview.start, preview.end) + 1
    let text = "${monthDay(Some(preview.start))} → ${monthDay(Some(preview.end))} · ${days} 天"
    let width = textAdvance(ctx, text, DRAG_TIP_SIZE, 400) + 14.0
    let box = Rect(x, y - 22.0, width, 22.0)
    shadow1(ctx, body.tokens, box, 4.0)
    fillRound(ctx, box, 4.0, body.tokens.color.surface)
    cssBorder(ctx, box, 4.0, body.tokens.metrics.borderWidth, body.ink.strongBorder)
    drawText(ctx, text, box.x + 7.0, box.centerY(), DRAG_TIP_SIZE, 400, body.tokens.color.text)
    let _ = px
}

func minFloat(a: Float32, b: Float32): Float32 {
    if (a < b) {
        a
    } else {
        b
    }
}

func maxFloat(a: Float32, b: Float32): Float32 {
    if (a > b) {
        a
    } else {
        b
    }
}
