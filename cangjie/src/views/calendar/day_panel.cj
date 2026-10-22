package textura.views.calendar

import std.collection.*
import cui.*
import textura.core.data.*
import textura.ui.*
import textura.views.calendar.logic.*

/*
 * 右侧日程面板（DayPanel.tsx + calendar.css:469-683）。
 *
 * 结构：头部（日期 / 农历 / 相对日期 + 徽章）→ 条目列表 → 快速添加 → 甘特入口。
 * 头部与列表自绘（逐像素对齐 CSS），快速添加使用 CUI `TextField` 以获得真实编辑、
 * IME 与 Enter 提交能力。
 */

/** `.cal-panel-head { padding: 12px 16px; gap: 3px }`。 */
let PANEL_PAD_H: Float32 = 16.0
let PANEL_PAD_V: Float32 = 12.0
let PANEL_DATE_FONT: Float32 = 14.5
let PANEL_DATE_LINE: Float32 = 21.75
let PANEL_LUNAR_FONT: Float32 = 12.0
let PANEL_LUNAR_LINE: Float32 = 18.0
let PANEL_DISTANCE_FONT: Float32 = 11.0
/** `.badge { padding: 2px 7px; font-size: 11px; line-height: 1.6; border: 1px }` -> 23.6。 */
let BADGE_H: Float32 = 23.6
let BADGE_FONT: Float32 = 11.0
let BADGE_PAD_H: Float32 = 7.0
let BADGE_GAP: Float32 = 6.0
/** 头部内容高：12 + 21.75 + 2 + 18 + 3 + 2 + 23.6 + 12。 */
let PANEL_HEAD_H: Float32 = 94.0
/** `.cal-panel-body { padding: var(--space-3) }`。 */
let PANEL_BODY_PAD: Float32 = 12.0
/** `.cal-item { padding: 2px 2px 2px 0; gap: 4px }`。 */
let ITEM_PAD: Float32 = 2.0
let ITEM_RADIUS: Float32 = 8.0
/** `.cal-item-main { padding: 7px 6px 7px 9px; gap: 8px }`。 */
let ITEM_MAIN_PAD_V: Float32 = 7.0
let ITEM_MAIN_PAD_LEFT: Float32 = 9.0
let ITEM_MAIN_GAP: Float32 = 8.0
let ITEM_ICON: Float32 = 15.0
let ITEM_TITLE_FONT: Float32 = 12.5
let ITEM_TITLE_LINE: Float32 = 16.875
let ITEM_META_GAP: Float32 = 3.0
let ITEM_META_ROW_GAP: Float32 = 6.0
let ITEM_META_FONT: Float32 = 11.0
let ITEM_SPAN_FONT: Float32 = 10.5
let ITEM_SPAN_LINE: Float32 = 14.175
/** 裁剪微调：实测卡片比 CSS 行盒相加多 1.35px（浏览器行盒取整），对齐参考图。 */
let ITEM_HEIGHT_FIX: Float32 = 1.35

struct PanelBadge {
    let text: String
    let tone: BadgeTone

    init(text: String, tone: BadgeTone) {
        this.text = text
        this.tone = tone
    }
}

/** 徽章背景/描边/文字三色（ui.css:264-298）。 */
struct BadgePaint {
    let fill: Color
    let border: Color
    let ink: Color

    init(fill: Color, border: Color, ink: Color) {
        this.fill = fill
        this.border = border
        this.ink = ink
    }
}

func badgePalette(c: TokenColors, tone: BadgeTone): BadgePaint {
    return match (tone) {
        case BadgeTone.Accent => BadgePaint(c.accentSoft, tint(c.accent, 28.0), c.accentInk)
        case BadgeTone.Ok => BadgePaint(tint(c.ok, 12.0), tint(c.ok, 30.0), c.okInk)
        case BadgeTone.Warn => BadgePaint(tint(c.warn, 14.0), tint(c.warn, 32.0), c.warnInk)
        case BadgeTone.Danger => BadgePaint(tint(c.danger, 12.0), tint(c.danger, 30.0), c.dangerInk)
        case BadgeTone.Info => BadgePaint(tint(c.info, 12.0), tint(c.info, 30.0), c.infoInk)
        case BadgeTone.Neutral => BadgePaint(c.surface2, c.border, c.textMuted)
    }
}

func badgeWidthOf(ctx: UiContext, text: String, dot!: Bool = false): Float32 {
    let extra: Float32 = if (dot) {
        10.0
    } else {
        0.0
    }
    return textWidthOf(ctx, text, BADGE_FONT, 550) + BADGE_PAD_H * 2.0 + 2.0 + extra
}

/** 药丸徽章：`padding: 2px 7px; border: 1px; border-radius: 999px`。 */
func drawBadge(ctx: UiContext, tokens: ThemeTokens, text: String, tone: BadgeTone, left: Float32, top: Float32,
    dot!: Bool = false): Unit {
    let width = badgeWidthOf(ctx, text, dot: dot)
    let paint = badgePalette(tokens.color, tone)
    let rect = Rect(left, top, width, BADGE_H)
    fillRound(ctx, rect, BADGE_H / 2.0, paint.fill)
    strokeCrisp(ctx, rect, BADGE_H / 2.0, tokens.metrics.borderWidth, paint.border)
    if (dot) {
        // `.badge-dot { width: 5px; height: 5px }` + `.badge { gap: 5px }`
        fillDisc(ctx, left + BADGE_PAD_H + 2.5, top + BADGE_H / 2.0, 2.5, paint.ink)
        drawTextInBox(ctx, text, left + BADGE_PAD_H + 10.0, top, BADGE_H, paint.ink, BADGE_FONT, 550, dy: -1.0)
    } else {
        drawTextCentered(ctx, text, left, top, width, BADGE_H, paint.ink, BADGE_FONT, 550, dy: -1.0)
    }
}

/** 面板头部：日期标题、农历全称、相对日期与徽章（节日 / 节气 / 条目数）。 */
class PanelHeadView <: Widget {
    private let tokens: ThemeTokens
    private let dateLabel: String
    private let lunarText: String
    private let distance: String
    private let badges: Array<PanelBadge>
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, dateLabel: String, lunarText: String, distance: String, badges: Array<PanelBadge>) {
        this.tokens = tokens
        this.dateLabel = dateLabel
        this.lunarText = lunarText
        this.distance = distance
        this.badges = badges
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(max(available.w, 0.0), PANEL_HEAD_H + 1.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        let contentX = frame.x + PANEL_PAD_H
        let right = frame.right() - PANEL_PAD_H
        let top = snapped(frame.y)
        // `.cal-panel-date { letter-spacing: -0.01em }`
        drawTextTracked(ctx, dateLabel, contentX, top + PANEL_PAD_V, PANEL_DATE_LINE, c.text, PANEL_DATE_FONT, 650,
            -PANEL_DATE_FONT * 0.01)
        drawTextLine(ctx, lunarText, contentX, top + PANEL_PAD_V + PANEL_DATE_LINE + 2.0, PANEL_LUNAR_LINE,
            c.textMuted, PANEL_LUNAR_FONT, 400, dy: -1.0)
        let metaTop = top + PANEL_PAD_V + PANEL_DATE_LINE + 2.0 + PANEL_LUNAR_LINE + 3.0 + 2.0
        drawTextInBox(ctx, distance, contentX, metaTop, BADGE_H, c.textFaint, PANEL_DISTANCE_FONT, 400, dy: -1.0)
        var x = right
        var index = badges.size - 1
        while (index >= 0) {
            let badge = badges[index]
            let width = badgeWidthOf(ctx, badge.text)
            x = x - width
            drawBadge(ctx, tokens, badge.text, badge.tone, x, metaTop)
            x = x - BADGE_GAP
            index = index - 1
        }
        // `.cal-panel-head { border-bottom: 1px solid var(--border) }`
        fillHLine(ctx, frame.x, top + PANEL_HEAD_H, frame.w, c.border)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/** 面板条目列表。 */
class PanelListView <: Widget {
    private let tokens: ThemeTokens
    private let items: Array<CalItem>
    private let areas: HashMap<String, Area>
    private let dateKey: String
    private let selectedId: ?String
    private let onOpen: (CalItem) -> Unit
    private let onToggle: (String) -> Unit
    private let scroll: State<Float64>
    private let draft: State<String>
    private var frame = Rect.zero()

    init(
        tokens: ThemeTokens,
        items: Array<CalItem>,
        areas: HashMap<String, Area>,
        dateKey: String,
        selectedId: ?String,
        scroll: State<Float64>,
        draft: State<String>,
        onOpen: (CalItem) -> Unit,
        onToggle: (String) -> Unit
    ) {
        this.tokens = tokens
        this.items = items
        this.areas = areas
        this.dateKey = dateKey
        this.selectedId = selectedId
        this.scroll = scroll
        this.draft = draft
        this.onOpen = onOpen
        this.onToggle = onToggle
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(max(available.w, 0.0), max(available.h, 0.0))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    private func cardX(): Float32 {
        return frame.x + PANEL_BODY_PAD
    }

    private func cardWidth(): Float32 {
        return max(0.0, frame.w - PANEL_BODY_PAD * 2.0)
    }

    private func titleWidth(cardWidth: Float32): Float32 {
        return max(0.0, cardWidth - 2.0 - ITEM_MAIN_PAD_LEFT - 6.0 - ITEM_ICON - ITEM_MAIN_GAP)
    }

    private func contentHeight(titleLines: Int64): Float32 {
        return ITEM_MAIN_PAD_V * 2.0 + ITEM_TITLE_LINE * Float32(titleLines) + ITEM_META_GAP + BADGE_H +
            ITEM_META_ROW_GAP + ITEM_SPAN_LINE
    }

    private func cardHeight(titleLines: Int64): Float32 {
        return 2.0 + ITEM_PAD * 2.0 + contentHeight(titleLines) + ITEM_HEIGHT_FIX
    }

    /** 逐张卡片的高度（draw 与命中测试共用）。 */
    private func cardHeights(ctx: UiContext): Array<Float32> {
        let heights = Array<Float32>(items.size, repeat: 0.0)
        let width = titleWidth(cardWidth())
        for (index in 0..items.size) {
            let lines = wrapText(ctx, items[index].title, width, ITEM_TITLE_FONT, 550)
            heights[index] = cardHeight(Int64(lines.size))
        }
        return heights
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        let heights = cardHeights(ctx)
        ctx.renderer.pushClip(Rect(frame.x, frame.y, frame.w, frame.h))
        var y = frame.y + PANEL_BODY_PAD - Float32(scroll.value)
        for (index in 0..items.size) {
            drawCard(ctx, items[index], y, heights[index])
            y = y + heights[index] + ITEM_META_ROW_GAP
        }
        ctx.renderer.popClip()
        let _ = c
        registerQuickPlaceholder(ctx)
    }

    /**
     * `.cal-quick .input` 的占位提示按 12.5px 绘制。
     *
     * CUI `TextField` 的占位字号来自继承的 TextStyle，而本构建对 `TextField` 调
     * `textStyle(...)` 会让控件不再绘制；因此关闭控件自带占位，由只读浮层按 CSS 尺寸补画，
     * 有输入时自动消失。浮层 `handleEvent` 返回 false，点击仍落到输入框上。
     */
    private func registerQuickPlaceholder(ctx: UiContext): Unit {
        if (!draft.value.isEmpty()) {
            return
        }
        let tokens = this.tokens
        let inputX = frame.x + PANEL_BODY_PAD
        let inputY = frame.y + frame.h + 1.0 + QUICK_PAD
        ctx.setOverlay(Overlay(
            handleEvent: {_, _ => false},
            render: {inner =>
                drawTextInBox(inner, "添加一条日程，按 Enter 保存", inputX + 10.0, snapped(inputY),
                    QUICK_INPUT_HEIGHT, tokens.color.textFaint, QUICK_FONT, 400, dy: -1.0)
            },
            owner: "calendar-quick-placeholder"))
    }

    private func drawCard(ctx: UiContext, item: CalItem, cardY: Float32, height: Float32): Unit {
        let c = tokens.color
        let left = cardX()
        let width = cardWidth()
        let rect = Rect(snapped(left), snapped(cardY), snapped(width), snapped(height))
        let done = isDoneItem(item)
        let current = match (selectedId) {
            case Some(id) => id == item.id
            case None => false
        }
        // `.cal-item { background: surface-2; border: 1px; border-radius: 8px }`；当前条目用强调色。
        if (current) {
            fillRound(ctx, rect, ITEM_RADIUS, c.accentSoft)
            strokeCrisp(ctx, rect, ITEM_RADIUS, tokens.metrics.borderWidth, c.accent)
        } else {
            fillRound(ctx, rect, ITEM_RADIUS, c.surface2)
            strokeCrisp(ctx, rect, ITEM_RADIUS, tokens.metrics.borderWidth, c.border)
        }

        let titleTop = cardY + 1.0 + ITEM_PAD + ITEM_MAIN_PAD_V
        let iconX = left + 1.0 + ITEM_MAIN_PAD_LEFT
        let bodyX = iconX + ITEM_ICON + ITEM_MAIN_GAP
        let metaTop = titleTop + ITEM_TITLE_LINE * Float32(1) + ITEM_META_GAP
        // 标题可能折行：先量行数，再用同一结果排 meta 行。
        let lines = wrapText(ctx, item.title, titleWidth(width), ITEM_TITLE_FONT, 550)
        let bodyHeight = height - 2.0 - ITEM_PAD * 2.0
        let iconCenterY = cardY + 1.0 + ITEM_PAD + bodyHeight / 2.0
        let glyph = iconGlyphFromId(kindIcon(item.kind)).getOrDefault({=> IconGlyph.Edit})
        paintSpec(ctx, glyph, Rect(iconX, iconCenterY - ITEM_ICON / 2.0, ITEM_ICON, ITEM_ICON), c.textFaint)

        let titleColor = if (done) {
            c.textMuted
        } else {
            c.text
        }
        var lineIndex = 0
        for (line in lines) {
            drawTextLine(ctx, line, bodyX, titleTop + ITEM_TITLE_LINE * Float32(lineIndex), ITEM_TITLE_LINE,
                titleColor, ITEM_TITLE_FONT, 550, dy: -1.0)
            lineIndex += 1
        }
        let metaRowTop = titleTop + ITEM_TITLE_LINE * Float32(lines.size) + ITEM_META_GAP
        let _ = metaTop

        // `.cal-item-meta { gap: 6px; font-size: 11px }`：领域点 + 领域名 → 状态徽章 → 区间文案。
        var x = bodyX
        match (areas.get(item.id)) {
            case Some(area) =>
                let dotCenter = metaRowTop + BADGE_H / 2.0
                fillDisc(ctx, x + 3.5, dotCenter, 3.5, colorFromHex(area.color, c.textFaint))
                let nameX = x + 7.0 + 4.0
                drawTextInBox(ctx, area.name, nameX, metaRowTop, BADGE_H, c.textMuted, ITEM_META_FONT, 400, dy: -1.0)
                x = nameX + textWidthOf(ctx, area.name, ITEM_META_FONT, 400) + BADGE_GAP
            case None => ()
        }
        let tone = match (statusTone(item.status)) {
            case "ok" => BadgeTone.Ok
            case "warn" => BadgeTone.Warn
            case "danger" => BadgeTone.Danger
            case "info" => BadgeTone.Info
            case "accent" => BadgeTone.Accent
            case _ => BadgeTone.Neutral
        }
        drawBadge(ctx, tokens, statusLabel(item.status), tone, x, metaRowTop, dot: true)
        let span = panelSpanText(item, dateKey)
        if (!span.isEmpty()) {
            let spanTop = metaRowTop + BADGE_H + ITEM_META_ROW_GAP
            drawTextLine(ctx, span, bodyX, spanTop, ITEM_SPAN_LINE, c.textFaint, ITEM_SPAN_FONT, 400, dy: -1.0)
        }

        // `.cal-item-check { margin: 5px 4px 0 0 }` + `.cal-check-box { 15px; border: 1.5px }`
        let checkRight = left + width - 1.0 - ITEM_PAD - 4.0
        let checkTop = cardY + 1.0 + ITEM_PAD + 5.0
        let checkRect = Rect(checkRight - 26.0, checkTop, 26.0, 26.0)
        let box = Rect(checkRect.centerX() - 7.5, checkRect.centerY() - 7.5, 15.0, 15.0)
        if (done) {
            fillRound(ctx, box, 4.0, c.okInk)
            paintSpec(ctx, IconGlyph.Check, Rect(box.x + 2.0, box.y + 2.0, 11.0, 11.0), c.surface)
        } else {
            strokeDisc(ctx, 0.0, 0.0, 0.0, 0.0, c.surface)
            fillRound(ctx, box, 4.0, c.surface)
            ctx.renderer.strokeRoundedRect(box, 4.0, Pen(width: 1.5, color: c.textFaint))
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseWheel(_, _, _, dy) =>
                let heights = cardHeights(ctx)
                var total = PANEL_BODY_PAD * 2.0
                for (height in heights) {
                    total = total + height + ITEM_META_ROW_GAP
                }
                let limit = max(0.0, total - frame.h)
                scroll.value = Float64(max(0.0, min(Float64(limit), scroll.value - Float64(dy) * 24.0)))
                return true
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (!frame.contains(x, y)) {
                    return false
                }
                let heights = cardHeights(ctx)
                var cardY = frame.y + PANEL_BODY_PAD - Float32(scroll.value)
                for (index in 0..items.size) {
                    let rect = Rect(cardX(), cardY, cardWidth(), heights[index])
                    if (rect.contains(x, y)) {
                        let checkRight = rect.x + rect.w - 1.0 - ITEM_PAD - 4.0
                        let checkRect = Rect(checkRight - 26.0, rect.y + 1.0 + ITEM_PAD + 5.0, 26.0, 26.0)
                        if (checkRect.contains(x, y)) {
                            onToggle(items[index].id)
                        } else {
                            onOpen(items[index])
                        }
                        return true
                    }
                    cardY = cardY + heights[index] + ITEM_META_ROW_GAP
                }
            case _ => ()
        }
        false
    }
}
