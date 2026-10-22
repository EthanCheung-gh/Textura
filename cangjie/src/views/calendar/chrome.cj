package textura.views.calendar

import cui.*
import textura.ui.*

/*
 * 页面级零件：标题区、网格下方提示条、面板底板、1px 分隔线。
 * 尺寸出处见各常量注释（calendar.css / shell.css / base.css）。
 */

/** `.page-header.cal-header h1 { font-size: 22px; line-height: 1.5 }`。 */
let HEADER_TITLE_FONT: Float32 = 22.0
let HEADER_TITLE_LINE: Float32 = 33.0
/** `.page-header-titles { gap: var(--space-1) }`。 */
let HEADER_TITLE_GAP: Float32 = 4.0
/** `.cal-subtitle { font-size: 13px }`（行高 1.5）。 */
let HEADER_SUBTITLE_FONT: Float32 = 13.0
let HEADER_SUBTITLE_LINE: Float32 = 19.5
/**
 * `.page-header.cal-header` 高度 = 33 + 4 + 19.5 = 56.5。
 *
 * 浏览器把紧随其后的 `.cal-layout` 顶边算到 152.5，再把 1px 边框吸附到整数行 153；
 * 仓颉侧没有边框吸附，若沿用 56.5 会让整条竖轴落在半像素上，1px 分隔线被抗锯齿稀释成
 * 两行浅灰（对比度骤降）。这里取 57 让布局行正好从整数 153 开始，复刻参考图的最终位置。
 */
let HEADER_HEIGHT: Float32 = 57.0
/** `.cal-hint { font-size: 11.5px }`（行高 1.5）。 */
let HINT_FONT: Float32 = 11.5
let HINT_LINE: Float32 = 17.25

/** 标题区：`<h1>日历</h1>` + 副标题（区间 · 干支生肖 · 农历月）。 */
class HeaderTitlesView <: Widget {
    private let tokens: ThemeTokens
    private let title: String
    private let subtitle: String
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, title: String, subtitle: String) {
        this.tokens = tokens
        this.title = title
        this.subtitle = subtitle
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(max(available.w, 0.0), HEADER_HEIGHT)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        // base.css:41 h1 { font-size: 20px } 被 calendar.css:20 覆盖为 22px / 650。
        // `.page-header.cal-header h1 { letter-spacing: -0.01em }`
        drawTextTracked(ctx, title, frame.x, frame.y, HEADER_TITLE_LINE, c.text, HEADER_TITLE_FONT, 650,
            -HEADER_TITLE_FONT * 0.01, dy: -1.0)
        let subtitleTop = frame.y + HEADER_TITLE_LINE + HEADER_TITLE_GAP
        let text = ellipsize(ctx, subtitle, frame.w, HEADER_SUBTITLE_FONT, 400)
        drawTextLine(ctx, text, frame.x, subtitleTop, HEADER_SUBTITLE_LINE, c.textMuted, HEADER_SUBTITLE_FONT, 400)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/** `.cal-hint`：今天 / 选中图例 + 键位提示。 */
class HintStripView <: Widget {
    private let tokens: ThemeTokens
    private let monthMode: Bool
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, monthMode: Bool) {
        this.tokens = tokens
        this.monthMode = monthMode
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(max(available.w, 0.0), HINT_LINE)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        // `.cal-hint` 顶边取整（浏览器把布局行的 1px 边框吸附到整数行）。
        let top = snapped(frame.y)
        let centerY = top + HINT_LINE / 2.0
        var x = frame.x
        // `.cal-hint-item { gap: 5px }` + `.cal-dot--today { inset 0 0 0 1.5px accent }`
        strokeDisc(ctx, x + 3.0, centerY, 2.25, 1.5, c.accent)
        x = x + 6.0 + 5.0
        drawTextInBox(ctx, "今天", x, top, HINT_LINE, c.textFaint, HINT_FONT, 400, dy: -1.0)
        x = x + textWidthOf(ctx, "今天", HINT_FONT, 400) + 12.0
        // `.cal-dot--selected { background: accent-soft; inset 0 0 0 1px accent }`
        fillDisc(ctx, x + 3.0, centerY, 3.0, c.accentSoft)
        strokeDisc(ctx, x + 3.0, centerY, 2.5, 1.0, c.accent)
        x = x + 6.0 + 5.0
        drawTextInBox(ctx, "选中", x, top, HINT_LINE, c.textFaint, HINT_FONT, 400, dy: -1.0)
        x = x + textWidthOf(ctx, "选中", HINT_FONT, 400) + 12.0
        let hint = if (monthMode) {
            "方向键 / Home / End / PageUp / PageDown 导航，Enter 进入日程面板"
        } else {
            "点击星期标题切换日期，点击卡片打开条目"
        }
        drawTextInBox(ctx, hint, x, top, HINT_LINE, c.textFaint, HINT_FONT, 400, dy: -1.0)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/** `.cal-panel` / `.cal-grid` 的底板：`shadow-1` + 圆角 surface + 1px 描边。 */
class PanelBackdropView <: Widget {
    private let tokens: ThemeTokens
    private var frame = Rect.zero()

    init(tokens: ThemeTokens) {
        this.tokens = tokens
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(max(available.w, 0.0), max(available.h, 0.0))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let radius = tokens.radius.lg
        // 面板几何取整：1px 描边必须落在整数像素行，否则会被抗锯齿摊成两行浅灰。
        let box = Rect(snapped(frame.x), snapped(frame.y), snapped(frame.w), snapped(frame.h))
        shadow1(ctx, tokens, box, radius)
        fillRound(ctx, box, radius, tokens.color.surface)
        strokeCrisp(ctx, box, radius, tokens.metrics.borderWidth, tokens.color.border)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/** 1px 横线（`border-top: 1px solid var(--border)`）。 */
class HairlineView <: Widget {
    private let color: Color
    private var frame = Rect.zero()

    init(color: Color) {
        this.color = color
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(max(available.w, 0.0), 1.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        fillHLine(ctx, frame.x, frame.y, frame.w, color)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}
