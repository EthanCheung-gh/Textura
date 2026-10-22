package textura.views.dashboard

import cui.*
import textura.ui.*

func okrTone(progress: Int64): ProgressTone {
    // DashboardPage.tsx:335 `progress >= 70 ? 'ok' : progress >= 35 ? 'accent' : 'warn'`
    if (progress >= 70) {
        ProgressTone.Ok
    } else if (progress >= 35) {
        ProgressTone.Accent
    } else {
        ProgressTone.Warn
    }
}

/*
 * `.dash-okr-list` / `.dash-okr-row`（dashboard.css:322-363）。
 * `grid-template-columns: minmax(0, 1fr) 88px auto; gap: var(--space-3);
 * padding: 9px var(--space-2)`，中列是 88px 宽的 `Progress size=sm`，右列是最小 34px 的百分比。
 */
class OkrRowsView <: Widget {
    private let tokens: ThemeTokens
    private let rows: Array<ObjectiveRow>
    private let onOpen: (String) -> Unit
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, rows: Array<ObjectiveRow>, onOpen: (String) -> Unit) {
        this.tokens = tokens
        this.rows = rows
        this.onOpen = onOpen
        emit(this)
    }

    private func rowHeight(ctx: UiContext): Float32 {
        // `padding: 9px var(--space-2)`（dashboard.css:335）+ 标题行盒（13px）
        tokens.space.s2 * 2.0 + 2.0 + lineBoxHeight(ctx, 13.0)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        // `.dash-okr-list { padding: 8px; gap: 2px }`：内容高 53.5 → 浏览器绘制吸附到 54，
        // 参考图卡片盒 313..437（124）。取整后下方 SOP 卡的上边框才落在 453。
        let raw = rowHeight(ctx) * Float32(rows.size) + tokens.space.s2 * 2.0 + 2.0 * Float32(max(0, rows.size - 1))
        let height = Float32(Int64(raw + 0.999))
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
        var index = 0
        for (row in rows) {
            let height = rowHeight(ctx)
            let rowRect = Rect(listLeft, y, max(0.0, listRight - listLeft), height)
            let rowId = "dash-okr-row-${row.id}"
            if (ctx.isHovered(rowId)) {
                // `.dash-okr-row:hover { background: var(--surface-2) }`（dashboard.css:340-342）
                fillRound(ctx, rowRect, tokens.radius.md, c.surface2)
            }
            let innerLeft = rowRect.x + pad
            let innerRight = rowRect.right() - pad
            let centerY = rowRect.centerY()
            // 中列 88px：`.progress--sm` 轨道高 5（ui.css:317-323）
            let meterWidth: Float32 = 88.0
            let valueWidth: Float32 = max(34.0, advanceWidth(ctx, "${row.progress}%", 12.0, 400))
            let meterLeft = innerRight - valueWidth - tokens.space.s3 - meterWidth
            let titleWidth = max(0.0, meterLeft - tokens.space.s3 - innerLeft)
            // `.dash-okr-title`：13px、单行省略、hover 变 accent（dashboard.css:344-355）
            drawLine(ctx, ellipsize(ctx, row.title, titleWidth, 13.0, 400), innerLeft,
                centerY - lineBoxHeight(ctx, 13.0) / 2.0, lineBoxHeight(ctx, 13.0), 13.0, 400,
                if (ctx.isHovered(rowId)) {
                    c.accent
                } else {
                    c.text
                })
            drawMeterSm(ctx, tokens, Rect(meterLeft, centerY - 2.5, meterWidth, 5.0), Float32(row.progress),
                okrTone(row.progress))
            // `.dash-okr-value`：12px、`text-muted`、右对齐、最小宽 34（dashboard.css:357-363）
            drawLineTrailing(ctx, "${row.progress}%", innerRight, centerY - lineBoxHeight(ctx, 12.0) / 2.0,
                lineBoxHeight(ctx, 12.0), 12.0, 400, c.textMuted)
            y += height + 2.0
            index += 1
        }
        let _ = index
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
                        ctx.claimHover("dash-okr-row-${row.id}", CursorShape.Interactive)
                        return false
                    }
                    rowY += height + 2.0
                }
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                match (rowAt(ctx, x, y)) {
                    case Some(id) =>
                        ctx.press("dash-okr-row-${id}")
                        return true
                    case None => ()
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                match (rowAt(ctx, x, y)) {
                    case Some(id) =>
                        if (ctx.isPressed("dash-okr-row-${id}")) {
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
