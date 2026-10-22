package textura.views.dashboard

import cui.*
import textura.ui.*
import textura.views.dashboard.logic as dash

func badgeToneForResult(result: ?dash.RunResult): BadgeTone {
    match (result) {
        case Some(dash.RunResult.Fail) => BadgeTone.Danger
        case Some(dash.RunResult.Skip) => BadgeTone.Warn
        case Some(dash.RunResult.Pass) => BadgeTone.Ok
        case None => BadgeTone.Neutral
    }
}

/*
 * `.dash-sop-list` / `.dash-sop-row`（dashboard.css:365-423）。
 * `grid-template-columns: 26px minmax(0, 1fr) auto; gap: var(--space-2);
 * padding: 8px var(--space-2)`：26px 图标砖 + 标题/元信息 + 结果徽章。
 */
class SopRowsView <: Widget {
    private let tokens: ThemeTokens
    private let rows: Array<SopRow>
    private let nowIso: String
    private let onOpen: (String) -> Unit
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, rows: Array<SopRow>, nowIso: String, onOpen: (String) -> Unit) {
        this.tokens = tokens
        this.rows = rows
        this.nowIso = nowIso
        this.onOpen = onOpen
        emit(this)
    }

    /** 主列：标题 13 行盒 + `gap: 1px` + 元信息 11 行盒（dashboard.css:398-423）。 */
    private func rowHeight(ctx: UiContext): Float32 {
        tokens.space.s2 * 2.0 + lineBoxHeight(ctx, 13.0) + 1.0 + lineBoxHeight(ctx, 11.0)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        let height = rowHeight(ctx) * Float32(rows.size) + tokens.space.s2 * 2.0 + 2.0 * Float32(max(0, rows.size - 1))
        Size(max(available.w, 0.0), min(height, max(available.h, height)))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        let pad = tokens.space.s2
        let listLeft = frame.x + pad
        let listRight = frame.right() - pad
        var y = frame.y + pad
        for (row in rows) {
            let height = rowHeight(ctx)
            let rowRect = Rect(listLeft, y, max(0.0, listRight - listLeft), height)
            let rowId = "dash-sop-row-${row.id}"
            if (ctx.isHovered(rowId)) {
                // `.dash-sop-row:hover { background: var(--surface-2) }`（dashboard.css:383-385）
                fillRound(ctx, rowRect, tokens.radius.md, c.surface2)
            }
            let innerLeft = rowRect.x + pad
            let innerRight = rowRect.right() - pad
            let centerY = rowRect.centerY()
            // 图标砖：26×26、`radius-sm`、1px `border`、`surface-2`、`text-faint`（dashboard.css:387-396）
            let iconBox = Rect(innerLeft, centerY - 13.0, 26.0, 26.0)
            fillRound(ctx, iconBox, tokens.radius.sm, c.surface2)
            strokeRound(ctx, iconBox, tokens.radius.sm, tokens.metrics.borderWidth, c.border)
            paintSpec(ctx, IconGlyph.Workflow, Rect(iconBox.centerX() - 7.5, iconBox.centerY() - 7.5, 15.0, 15.0),
                c.textFaint)
            // 结果徽章（`Badge`，右列 `auto`）
            let label = match (row.lastRunResult) {
                case Some(result) => dash.runResultLabel(result)
                case None => "未运行"
            }
            let badgeWidth = badgePillWidth(ctx, label)
            drawBadgeTrailing(ctx, tokens, label, badgeToneForResult(row.lastRunResult), innerRight, centerY)
            // 主列
            let mainLeft = iconBox.right() + pad
            let mainWidth = max(0.0, innerRight - badgeWidth - pad - mainLeft)
            let titleTop = rowRect.y + pad
            drawLine(ctx, ellipsize(ctx, row.title, mainWidth, 13.0, 400), mainLeft, titleTop,
                lineBoxHeight(ctx, 13.0), 13.0, 400,
                if (ctx.isHovered(rowId)) {
                    c.accent
                } else {
                    c.text
                })
            let metaTail = match (row.lastRunResult) {
                case Some(result) => " · 最近 ${dash.runResultLabel(result)} ${dash.relativeTime(row.lastRunAt, nowIso)}"
                case None => " · 尚未运行"
            }
            let meta = "${row.steps} 个步骤" + metaTail
            drawLine(ctx, ellipsize(ctx, meta, mainWidth, 11.0, 400), mainLeft, titleTop + lineBoxHeight(ctx, 13.0) + 1.0,
                lineBoxHeight(ctx, 11.0), 11.0, 400, c.textFaint)
            y += height + 2.0
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                var rowY = frame.y + tokens.space.s2
                for (row in rows) {
                    let height = rowHeight(ctx)
                    let rowRect = Rect(frame.x + tokens.space.s2, rowY,
                        max(0.0, frame.w - tokens.space.s2 * 2.0), height)
                    if (rowRect.contains(x, y)) {
                        ctx.claimHover("dash-sop-row-${row.id}", CursorShape.Interactive)
                        return false
                    }
                    rowY += height + 2.0
                }
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                match (rowAt(ctx, x, y)) {
                    case Some(id) =>
                        ctx.press("dash-sop-row-${id}")
                        return true
                    case None => ()
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                match (rowAt(ctx, x, y)) {
                    case Some(id) =>
                        if (ctx.isPressed("dash-sop-row-${id}")) {
                            ctx.clearPress()
                            onOpen(id)
                            return true
                        }
                    case None => ()
                }
            case _ => ()
        }
        false
    }

    private func rowAt(ctx: UiContext, x: Float32, y: Float32): ?String {
        var rowY = frame.y + tokens.space.s2
        for (row in rows) {
            let height = rowHeight(ctx)
            let rowRect = Rect(frame.x + tokens.space.s2, rowY,
                max(0.0, frame.w - tokens.space.s2 * 2.0), height)
            if (rowRect.contains(x, y)) {
                return Some(row.id)
            }
            rowY += height + 2.0
        }
        None
    }

    public func pointerEventScope(): PointerEventScope {
        PointerEventScope.LayoutBounds
    }
}
