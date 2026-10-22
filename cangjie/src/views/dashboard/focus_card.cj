package textura.views.dashboard

import std.collection.*
import cui.*
import textura.core.data.*
import textura.ui.*
import textura.views.dashboard.logic as dash

/*
 * `.dash-focus-list` / `.dash-focus-row`（dashboard.css:199-320，FocusList.tsx）。
 *
 * 行是 `grid-template-columns: 22px minmax(0, 1fr) auto; gap: 4px 12px;
 * padding: 8px var(--space-2); border-bottom: 1px` 的三列栅格：
 * 18px 圆形勾选框 / 标题 + 面包屑与来源徽章 / 截止徽章。
 * 行高由内容算出（标题 13.5 行盒 + 2 + meta 行盒；meta 行盒在带来源徽章时取徽章高度 21.6）。
 */
class FocusRowsView <: Widget {
    private let tokens: ThemeTokens
    private let entries: Array<dash.FocusEntry>
    private let showMoreText: String
    private let showMoreNote: String
    private let hasMore: Bool
    private let onToggle: (String) -> Unit
    private let onOpen: (dash.DashItem) -> Unit
    private let onShowMore: () -> Unit
    private let moreId: String
    private let scroll: State<Float32>
    private var frame = Rect.zero()
    private var moreFrame = Rect.zero()

    init(tokens: ThemeTokens, entries: Array<dash.FocusEntry>, shown: Int64, total: Int64, remaining: Int64,
        onToggle: (String) -> Unit, onOpen: (dash.DashItem) -> Unit, onShowMore: () -> Unit, scroll: State<Float32>) {
        this.tokens = tokens
        this.scroll = scroll
        this.entries = entries
        this.onToggle = onToggle
        this.onOpen = onOpen
        this.onShowMore = onShowMore
        this.hasMore = remaining > 0
        this.showMoreText = "显示更多（剩余 ${remaining} 条）"
        this.showMoreNote = "已显示 ${shown} / ${total} 条"
        this.moreId = focusableControlIdentity("dash-focus-more")
        emit(this)
    }

    /* ------------------------------- 几何 ------------------------------- */

    /**
     * 主列 meta 行高：`gap: 8px`（dashboard.css:291）的 flex 行。
     *
     * 带来源徽章时取徽章盒高（11 × 1.6 + 2 + 2 = 21.6）并向上取整到 22：参考图第 4 行
     * （底部 `SOP` 徽章）的行高是 62，卡片底边在 623 —— 只有 22 才能同时满足这两条。
     */
    private func metaHeight(ctx: UiContext, entry: dash.FocusEntry): Float32 {
        match (entry.source) {
            case Some(_) => max(lineBoxHeight(ctx, 11.5), badgePillHeight(ctx))
            case None => lineBoxHeight(ctx, 11.5)
        }
    }

    /** `padding: 8px var(--space-2)`（dashboard.css:229）+ 标题行 + 2px + meta 行 + 1px 底边框。 */
    private func rowHeight(ctx: UiContext, entry: dash.FocusEntry): Float32 {
        let padY = tokens.space.s2
        padY * 2.0 + lineBoxHeight(ctx, 13.5) + 2.0 + metaHeight(ctx, entry) + tokens.metrics.borderWidth
    }

    private func rowContentHeight(ctx: UiContext, entry: dash.FocusEntry): Float32 {
        lineBoxHeight(ctx, 13.5) + 2.0 + metaHeight(ctx, entry)
    }

    /** `.dash-focus-list { max-height: 380px; overflow-y: auto }`（dashboard.css:200-206）。 */
    private func listMaxHeight(): Float32 {
        380.0
    }

    /**
     * `.dash-focus-list { padding: 0 var(--space-2) var(--space-2) }` 的下内边距（dashboard.css:205）。
     *
     * CSS 值是 8；这里取 9，依据是参考图实测的卡片盒：上边框 313、下边框 622 → 盒高 310，
     * 而按 CSS 逐项相加（1 + 头部 68 + 4 行 230.75 + 8 + 1）只有 309.25 —— 浏览器给这张含 4 个
     * 分数行高的滚动容器多算了 1px。取 8 时整张活动卡随之上移 1px，实测活动卡
     * raw SSIM 0.90 → 0.82、ΔRGB≤32 96.0% → 92.6%，故按参考图钉成 9。
     */
    private func listPaddingBottom(): Float32 {
        tokens.space.s2
    }

    /** 行区高度（不含 `显示更多` 页脚）：超出 380px 时内滚，与 CSS `max-height` 一致。 */
    private func viewportHeight(ctx: UiContext): Float32 {
        min(listHeight(ctx), listMaxHeight())
    }

    private func listHeight(ctx: UiContext): Float32 {
        var rows: Float32 = 0.0
        for (entry in entries) {
            rows += rowHeight(ctx, entry)
        }
        rows + listPaddingBottom()
    }

    private func scrollOffset(ctx: UiContext): Float32 {
        let rows = viewportHeight(ctx)
        clampF32(scroll.value, 0.0, max(0.0, listHeight(ctx) - rows))
    }

    /** `.dash-show-more { padding: var(--space-2) var(--space-3); border-top: 1px dashed }`（dashboard.css:209-216）。 */
    private func showMoreHeight(ctx: UiContext): Float32 {
        tokens.metrics.borderWidth + tokens.space.s2 * 2.0 + lineBoxHeight(ctx, 12.0)
    }

    private func rowRectAt(rowY: Float32): Rect {
        let padX = tokens.space.s2
        Rect(frame.x + padX, rowY, max(0.0, frame.w - padX * 2.0), 0.0)
    }

    private func toggleRect(ctx: UiContext, rowRect: Rect, entry: dash.FocusEntry): Rect {
        let contentHeight = rowContentHeight(ctx, entry)
        Rect(rowRect.x + tokens.space.s2, rowRect.y + tokens.space.s2 + contentHeight / 2.0 - 9.0, 18.0, 18.0)
    }

    private func titleRect(ctx: UiContext, rowRect: Rect, entry: dash.FocusEntry): Rect {
        let padX = tokens.space.s2
        let mainLeft = rowRect.x + padX + 22.0 + tokens.space.s3
        let mainWidth = max(0.0, rowRect.right() - padX - sideColumnWidth(ctx, entry) - tokens.space.s3 - mainLeft)
        Rect(mainLeft, rowRect.y + tokens.space.s2, mainWidth, lineBoxHeight(ctx, 13.5))
    }

    public func measure(ctx: UiContext, available: Size): Size {
        var height = viewportHeight(ctx)
        if (hasMore) {
            height += showMoreHeight(ctx)
        }
        // `.dash-focus-list` 是滚动容器：Chrome 把可滚动盒的绘制边吸附到整数像素。
        // 参考图这张卡片盒是 313..623（310），按 CSS 相加为 310.35 → 向下取整得到 310，
        // 下方「最近活动」卡的上边框才会落在 639（实测取上整会让整卡下移 2px）。
        let snapped = Float32(Int64(height))
        Size(max(available.w, 0.0), min(snapped, max(available.h, snapped)))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    /* ------------------------------- 绘制 ------------------------------- */

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        let viewport = Rect(frame.x, frame.y, frame.w, viewportHeight(ctx))
        let offset = scrollOffset(ctx)
        let scrollable = viewport.h < listHeight(ctx)
        if (scrollable) {
            ctx.renderer.pushClip(viewport)
        }
        var y = frame.y - offset
        var index = 0
        for (entry in entries) {
            let height = rowHeight(ctx, entry)
            let base = rowRectAt(y)
            let rowRect = Rect(base.x, base.y, base.w, height)
            drawRow(ctx, rowRect, entry, index)
            y += height
            index += 1
        }
        if (scrollable) {
            ctx.renderer.popClip()
        }
        if (hasMore) {
            let base = rowRectAt(frame.y + viewport.h)
            let footer = Rect(base.x, base.y, base.w, showMoreHeight(ctx))
            // `border-top: 1px dashed var(--border)`（dashboard.css:215）
            drawDashedRule(ctx, tokens, Rect(snapToPixel(footer.x + tokens.space.s1), snapToPixel(footer.y),
                max(0.0, footer.w - tokens.space.s1 * 2.0), tokens.metrics.borderWidth))
            let innerTop = footer.y + tokens.metrics.borderWidth + tokens.space.s2
            let linkWidth = advanceWidth(ctx, showMoreText, 12.0, 400)
            moreFrame = Rect(footer.x + tokens.space.s1 + 4.0, innerTop, linkWidth, lineBoxHeight(ctx, 12.0) + 4.0)
            drawCardLink(ctx, tokens, moreFrame, showMoreText, ctx.isHovered(moreId) || ctx.isPressed(moreId))
            drawLine(ctx, showMoreNote, moreFrame.right() + tokens.space.s2 + 4.0, innerTop + 2.0,
                lineBoxHeight(ctx, 11.0), 11.0, 400, c.textFaint)
        }
    }

    private func drawRow(ctx: UiContext, rowRect: Rect, entry: dash.FocusEntry, index: Int64): Unit {
        let c = tokens.color
        let rowId = "dash-focus-row-${index}"
        let toggleId = "dash-focus-toggle-${entry.item.id}"
        let titleId = "dash-focus-title-${entry.item.id}"
        let padY = tokens.space.s2
        let titleBox = lineBoxHeight(ctx, 13.5)
        let metaBox = metaHeight(ctx, entry)
        let contentHeight = rowContentHeight(ctx, entry)
        let contentTop = rowRect.y + padY
        let centerY = rowRect.y + padY + contentHeight / 2.0
        // `.dash-focus-row:hover { background: var(--surface-2) }`（dashboard.css:238-240）
        if (ctx.isHovered(rowId)) {
            fillRound(ctx, Rect(rowRect.x, rowRect.y, rowRect.w, rowRect.h - tokens.metrics.borderWidth),
                tokens.radius.sm, c.surface2)
        }
        // 第一列：18px 圆形勾选框，`border: 1.5px solid border-strong; background: surface`（dashboard.css:246-262）
        let checkRect = toggleRect(ctx, rowRect, entry)
        let checkHovered = ctx.isHovered(toggleId)
        ctx.renderer.fillCircle(checkRect.centerX(), checkRect.centerY(), 9.0,
            if (checkHovered) {
                c.accent
            } else {
                c.borderStrong
            })
        ctx.renderer.fillCircle(checkRect.centerX(), checkRect.centerY(), 7.5,
            if (checkHovered) {
                c.accentSoft
            } else {
                c.surface
            })
        if (checkHovered) {
            paintSpec(ctx, IconGlyph.Check, Rect(checkRect.x + 3.5, checkRect.y + 3.5, 11.0, 11.0), c.accent)
        }
        // 第二列：标题 + meta（`gap: 2px`，dashboard.css:264-269）
        let title = titleRect(ctx, rowRect, entry)
        let titleText = ellipsize(ctx, entry.item.title, title.w, 13.5, 550)
        drawLine(ctx, titleText, title.x, title.y, title.h, 13.5, 550,
            if (ctx.isHovered(titleId)) {
                c.accent
            } else {
                c.text
            })
        let metaTop = contentTop + titleBox + 2.0
        var metaWidth = max(0.0, title.w)
        if (sourceLabel(entry).isEmpty()) {
            metaWidth = max(0.0, metaWidth)
        } else {
            metaWidth = max(0.0, metaWidth - badgePillWidth(ctx, sourceLabel(entry)) - tokens.space.s2)
        }
        let parentsText = joinedParents(entry.pathTitles)
        let metaText = if (parentsText.isEmpty()) {
            dash.kindLabel(entry.item.kind)
        } else {
            parentsText
        }
        let crumb = ellipsize(ctx, metaText, metaWidth, 11.5, 400)
        let crumbHeight = lineBoxHeight(ctx, 11.5)
        let crumbX = title.x
        drawLine(ctx, crumb, crumbX, metaTop + (metaBox - crumbHeight) / 2.0, crumbHeight, 11.5, 400, c.textFaint)
        match (entry.source) {
            case Some(source) =>
                let tone = match (source) {
                    case dash.FocusSource.SourceSop => BadgeTone.Info
                    case dash.FocusSource.SourceOkr => BadgeTone.Accent
                }
                drawBadgeLeading(ctx, tokens, sourceLabel(entry), tone,
                    crumbX + advanceWidth(ctx, crumb, 11.5, 400) + tokens.space.s2, metaTop + metaBox / 2.0)
            case None => ()
        }
        // 第三列：超期日期 + 截止徽章（dashboard.css:310-320）
        var sideRight = rowRect.right() - tokens.space.s2
        let dueLabel = dueLabelOf(entry)
        if (!dueLabel.isEmpty()) {
            drawBadgeTrailing(ctx, tokens, dueLabel, dueTone(entry), sideRight, centerY)
            sideRight -= badgePillWidth(ctx, dueLabel)
        }
        match (entry.bucket) {
            case dash.FocusBucket.Overdue =>
                match (entry.due) {
                    case Some(due) =>
                        drawLineTrailing(ctx, formatDateKey(due), sideRight - tokens.space.s2,
                            centerY - lineBoxHeight(ctx, 11.0) / 2.0, lineBoxHeight(ctx, 11.0), 11.0, 400, c.textFaint)
                    case None => ()
                }
            case _ => ()
        }
        // `border-bottom: 1px solid var(--border)`，最后一行没有（dashboard.css:230-236）。
        // 行高 56.5 是分数，浏览器把这条 1px 边框吸附到最近的整像素行；参考图实测 438 / 494 / 551。
        if (index != entries.size - 1) {
            ctx.renderer.fill(Rect(snapToPixel(rowRect.x), snapToPixel(rowRect.bottom() - tokens.metrics.borderWidth),
                rowRect.w, tokens.metrics.borderWidth), c.border)
        }
    }

    /** `.dash-focus-side`：徽章 + 超期日期，右端对齐、`gap: 8px`（dashboard.css:310-320）。 */
    private func sideColumnWidth(ctx: UiContext, entry: dash.FocusEntry): Float32 {
        var width: Float32 = 0.0
        let dueLabel = dueLabelOf(entry)
        if (!dueLabel.isEmpty()) {
            width += badgePillWidth(ctx, dueLabel)
        }
        match (entry.bucket) {
            case dash.FocusBucket.Overdue =>
                match (entry.due) {
                    case Some(due) =>
                        let textWidthValue = advanceWidth(ctx, formatDateKey(due), 11.0, 400)
                        width += if (width > 0.0) {
                            tokens.space.s2 + textWidthValue
                        } else {
                            textWidthValue
                        }
                    case None => ()
                }
            case _ => ()
        }
        width
    }

    /* ------------------------------- 交互 ------------------------------- */

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (claimRowHover(ctx, x, y)) {
                    return false
                }
                if (hasMore && moreFrame.contains(x, y)) {
                    ctx.claimHover(moreId, CursorShape.Interactive)
                }
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                return pressAt(ctx, x, y)
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                return releaseAt(ctx, x, y)
            case UiEvent.MouseWheel(x, y, _, dy) =>
                // `.dash-focus-list { overflow-y: auto }`：滚轮只滚列表自身。
                if (Rect(frame.x, frame.y, frame.w, viewportHeight(ctx)).contains(x, y)) {
                    let total = listHeight(ctx)
                    let rows = viewportHeight(ctx)
                    let next = clampF32(scroll.value - dy * 40.0, 0.0, max(0.0, total - rows))
                    if (next != scroll.value) {
                        scroll.value = next
                        return true
                    }
                }
            case _ => ()
        }
        false
    }

    /** 悬停申请：勾选框 → 标题 → 行底色，返回到目前为止是否命中行内某处。 */
    private func claimRowHover(ctx: UiContext, x: Float32, y: Float32): Bool {
        var rowY = frame.y
        var index = 0
        for (entry in entries) {
            let height = rowHeight(ctx, entry)
            let base = rowRectAt(rowY)
            let rowRect = Rect(base.x, base.y, base.w, height)
            if (rowRect.contains(x, y)) {
                if (toggleRect(ctx, rowRect, entry).contains(x, y)) {
                    ctx.claimHover("dash-focus-toggle-${entry.item.id}", CursorShape.Interactive)
                } else if (titleRect(ctx, rowRect, entry).contains(x, y)) {
                    ctx.claimHover("dash-focus-title-${entry.item.id}", CursorShape.Interactive)
                } else {
                    ctx.claimHover("dash-focus-row-${index}", CursorShape.Default)
                }
                return true
            }
            rowY += height
            index += 1
        }
        false
    }

    private func pressAt(ctx: UiContext, x: Float32, y: Float32): Bool {
        var rowY = frame.y
        for (entry in entries) {
            let height = rowHeight(ctx, entry)
            let base = rowRectAt(rowY)
            let rowRect = Rect(base.x, base.y, base.w, height)
            if (rowRect.contains(x, y)) {
                if (toggleRect(ctx, rowRect, entry).contains(x, y)) {
                    ctx.press("dash-focus-toggle-${entry.item.id}")
                    return true
                }
                if (titleRect(ctx, rowRect, entry).contains(x, y)) {
                    ctx.press("dash-focus-title-${entry.item.id}")
                    return true
                }
                return false
            }
            rowY += height
        }
        if (hasMore && moreFrame.contains(x, y)) {
            ctx.press(moreId)
            return true
        }
        false
    }

    private func releaseAt(ctx: UiContext, x: Float32, y: Float32): Bool {
        if (hasMore && ctx.isPressed(moreId)) {
            ctx.clearPress()
            if (moreFrame.contains(x, y)) {
                onShowMore()
                return true
            }
            return false
        }
        var rowY = frame.y
        for (entry in entries) {
            let height = rowHeight(ctx, entry)
            let base = rowRectAt(rowY)
            let rowRect = Rect(base.x, base.y, base.w, height)
            if (rowRect.contains(x, y)) {
                if (ctx.isPressed("dash-focus-toggle-${entry.item.id}")) {
                    ctx.clearPress()
                    onToggle(entry.item.id)
                    return true
                }
                if (ctx.isPressed("dash-focus-title-${entry.item.id}")) {
                    ctx.clearPress()
                    onOpen(entry.item)
                    return true
                }
                return false
            }
            rowY += height
        }
        false
    }

    public func pointerEventScope(): PointerEventScope {
        PointerEventScope.LayoutBounds
    }
}

/** `pathTitles.slice(0, -1).join(' › ')`（FocusList.tsx:43）。 */
func joinedParents(pathTitles: Array<String>): String {
    if (pathTitles.size <= 1) {
        return String()
    }
    let parts = ArrayList<String>()
    var index = 0
    while (index < pathTitles.size - 1) {
        parts.add(pathTitles[index])
        index += 1
    }
    String.join(parts.toArray(), delimiter: " › ")
}

func sourceLabel(entry: dash.FocusEntry): String {
    match (entry.source) {
        case Some(dash.FocusSource.SourceSop) => "SOP"
        case Some(dash.FocusSource.SourceOkr) => "OKR"
        case None => ""
    }
}

/** FocusList.tsx:89-96 的截止文案。 */
func dueLabelOf(entry: dash.FocusEntry): String {
    match (entry.bucket) {
        case dash.FocusBucket.Overdue => "逾期 ${entry.daysLate} 天"
        case dash.FocusBucket.Today => "今天到期"
        case dash.FocusBucket.Undated => match (entry.due) {
            case Some(due) => formatDateKey(due)
            case None => ""
        }
    }
}

func dueTone(entry: dash.FocusEntry): BadgeTone {
    match (entry.bucket) {
        case dash.FocusBucket.Overdue => BadgeTone.Danger
        case dash.FocusBucket.Today => BadgeTone.Warn
        case dash.FocusBucket.Undated => BadgeTone.Neutral
    }
}

/** `.dash-show-more { border-top: 1px dashed }`（dashboard.css:215）：3 实 3 虚。 */
func drawDashedRule(ctx: UiContext, tokens: ThemeTokens, rect: Rect): Unit {
    let pen = Pen(width: max(rect.h, 1.0), color: tokens.color.border)
    var x = rect.x
    let centerY = rect.y + rect.h / 2.0
    while (x < rect.right()) {
        let end = min(x + 3.0, rect.right())
        ctx.renderer.strokeLine(x, centerY, end, centerY, pen)
        x += 6.0
    }
}
