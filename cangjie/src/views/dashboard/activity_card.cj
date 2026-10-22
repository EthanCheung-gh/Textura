package textura.views.dashboard

import cui.*
import textura.ui.*
import textura.views.dashboard.logic as dash

/*
 * `.dash-activity-list` / `.dash-activity-row`（dashboard.css:425-508，ActivityFeed.tsx）。
 * `grid-template-columns: 24px minmax(0, 1fr) auto; gap: var(--space-3);
 * padding: 8px var(--space-1); align-items: start`：24px 圆形图标 + 标题/详情 + 相对时间。
 */
class ActivityRowsView <: Widget {
    private let tokens: ThemeTokens
    private let entries: Array<dash.ActivityEntry>
    private let nowIso: String
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, entries: Array<dash.ActivityEntry>, nowIso: String) {
        this.tokens = tokens
        this.entries = entries
        this.nowIso = nowIso
        emit(this)
    }

    /** 主列：标题 12.5 行盒 + 1px + 详情 11.5 行盒；行内 `padding: 8px 4px` + 底边框（dashboard.css:434-441）。 */
    private func rowHeight(ctx: UiContext): Float32 {
        tokens.space.s2 * 2.0 + lineBoxHeight(ctx, 12.5) + 1.0 + lineBoxHeight(ctx, 11.5) + tokens.metrics.borderWidth
    }

    public func measure(ctx: UiContext, available: Size): Size {
        let height = rowHeight(ctx) * Float32(entries.size) + tokens.space.s2
        Size(max(available.w, 0.0), min(height, max(available.h, height)))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        let padX = tokens.space.s3
        let listLeft = frame.x + padX
        let listRight = frame.right() - padX
        var y = frame.y
        var index = 0
        for (entry in entries) {
            let height = rowHeight(ctx)
            let rowRect = Rect(listLeft, y, max(0.0, listRight - listLeft), height)
            let innerLeft = rowRect.x + tokens.space.s1
            let innerRight = rowRect.right() - tokens.space.s1
            let contentTop = rowRect.y + tokens.space.s2
            // 圆形图标 24×24（dashboard.css:447-456），底色按 kind / result 变化（458-478）
            let circleRect = Rect(innerLeft, contentTop, 24.0, 24.0)
            let skin = activityIconSkin(tokens, entry)
            // `border-radius: 50%; border: 1px solid ...; background: ...`（dashboard.css:447-456）
            ctx.renderer.fillCircle(circleRect.centerX(), circleRect.centerY(), 12.0, skin.border)
            ctx.renderer.fillCircle(circleRect.centerX(), circleRect.centerY(), 11.0, skin.fill)
            paintSpec(ctx, activityGlyph(entry), Rect(circleRect.centerX() - 6.5, circleRect.centerY() - 6.5, 13.0,
                13.0), skin.ink)
            // 时间列：11px、`text-faint`、`align-items: start`（dashboard.css:503-508）
            let timeText = dash.relativeTime(entry.at, nowIso)
            drawLineTrailing(ctx, timeText, innerRight, contentTop, lineBoxHeight(ctx, 11.0), 11.0, 400,
                c.textFaint)
            let timeWidth = advanceWidth(ctx, timeText, 11.0, 400)
            // 主列
            let mainLeft = circleRect.right() + tokens.space.s3
            let mainWidth = max(0.0, innerRight - timeWidth - tokens.space.s3 - mainLeft)
            drawLine(ctx, ellipsize(ctx, entry.title, mainWidth, 12.5, 400), mainLeft, contentTop,
                lineBoxHeight(ctx, 12.5), 12.5, 400, c.text)
            drawLine(ctx, ellipsize(ctx, entry.detail, mainWidth, 11.5, 400), mainLeft,
                contentTop + lineBoxHeight(ctx, 12.5) + 1.0, lineBoxHeight(ctx, 11.5), 11.5, 400, c.textFaint)
            // 行高 54 是整数，边框吸附后与参考图的行分隔线（761 / 815 / 869）逐行对齐。
            if (index != entries.size - 1) {
                ctx.renderer.fill(Rect(snapToPixel(rowRect.x),
                    snapToPixel(rowRect.bottom() - tokens.metrics.borderWidth), rowRect.w, tokens.metrics.borderWidth),
                    c.border)
            }
            y += height
            index += 1
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/**
 * 图标砖配色（`data-kind='completed'` / `data-result` 覆盖规则，dashboard.css:447-478）。
 * `fill`/`border` 已合成到卡片 `--surface` 上，因此可以整块不透明地画两层圆。
 */
struct ActivitySkin {
    let fill: Color
    let border: Color
    let ink: Color

    init(fill: Color, border: Color, ink: Color) {
        this.fill = fill
        this.border = border
        this.ink = ink
    }
}

func activityIconSkin(tokens: ThemeTokens, entry: dash.ActivityEntry): ActivitySkin {
    let c = tokens.color
    let plain = ActivitySkin(c.surface2, c.border, c.textFaint)
    match (entry.kind) {
        case dash.ActivityKind.Completed => tintedSkin(tokens, c.ok)
        case dash.ActivityKind.Run => match (entry.result) {
            case Some(dash.RunResult.Pass) => tintedSkin(tokens, c.ok)
            case Some(dash.RunResult.Fail) => tintedSkin(tokens, c.danger)
            case Some(dash.RunResult.Skip) => ActivitySkin(c.surface2, c.border, c.warn)
            case None => plain
        }
    }
}

/** `background: color-mix(C 12%); border-color: color-mix(C 32%)`（dashboard.css:458-478）合成到 surface。 */
func tintedSkin(tokens: ThemeTokens, color: Color): ActivitySkin {
    let surface = tokens.color.surface
    ActivitySkin(overColor(surface, tint(color, 12.0)), overColor(surface, tint(color, 32.0)), color)
}

/** ActivityFeed.tsx:29-33：`run` 用 play（失败 x），`completed` 用 check。 */
func activityGlyph(entry: dash.ActivityEntry): IconGlyph {
    match (entry.kind) {
        case dash.ActivityKind.Completed => IconGlyph.Check
        case dash.ActivityKind.Run => match (entry.result) {
            case Some(dash.RunResult.Fail) => IconGlyph.Cross
            case _ => IconGlyph.Play
        }
    }
}
