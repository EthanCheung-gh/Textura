package textura.views.gantt

import cui.*
import textura.ui.*

/*
 * 页头：`<h1>甘特</h1>` + `<p>时间轴上的承诺与依赖。</p>`
 * （GanttPage.tsx:333-338，shell.css:270-290）。
 *
 * 用自绘而不是 `Label` 栈：CSS 的 `.page-header-titles { gap: 4px }` 与
 * `h1 { font-size: 22px }` / `p { font-size: 13px; line-height: 1.5 }` 决定了
 * 两条基线（实测 y=87..108 与 121..133，页头高 57），Label 的行高由字体度量决定、
 * 无法钉到同一像素网格。
 */
class GanttPageHeader <: Widget {
    private let tokens: ThemeTokens
    private var frame = Rect.zero()

    init(tokens: ThemeTokens) {
        this.tokens = tokens
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, PAGE_HEADER_HEIGHT)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func isFlexible(): Bool {
        false
    }

    public func draw(ctx: UiContext): Unit {
        // h1：line-height 1.5 * 22 = 33，正文行盒中心 16.5
        drawText(ctx, "甘特", frame.x, frame.y + PAGE_TITLE_LINE_HEIGHT / 2.0, PAGE_TITLE_SIZE, 650, tokens.color.text)
        // p：13 * 1.5 = 19.5，起始于 h1 行盒 + gap 4
        let paragraphTop = PAGE_TITLE_LINE_HEIGHT + PAGE_HEADER_GAP
        drawText(ctx, "时间轴上的承诺与依赖。", frame.x, frame.y + paragraphTop + PAGE_SUBTITLE_LINE_HEIGHT / 2.0,
            PAGE_SUBTITLE_SIZE, 400, tokens.color.textMuted)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}
