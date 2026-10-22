package textura.views.calendar

import std.collection.*
import cui.*
import textura.ui.*
import textura.views.calendar.logic.*

/*
 * 周视图 7 列（WeekView.tsx + calendar.css:288-467）。
 *
 * 每列 = 列头（星期 / 日号 / 农历）+ 当日卡片列表；跨天条目在卡片尾部显示
 * `第 n/m 天`，已完成的卡片用 `surface-2` 底与删除线。
 */

/** `.cal-week-head { padding: 7px 8px; gap: 1px; border-left: 2px; border-bottom: 1px }`。 */
let WEEK_HEAD_PAD_V: Float32 = 7.0
let WEEK_HEAD_PAD_H: Float32 = 8.0
let WEEK_HEAD_BORDER_LEFT: Float32 = 2.0
let WEEK_HEAD_WEEKDAY_FONT: Float32 = 10.5
let WEEK_HEAD_WEEKDAY_LINE: Float32 = 15.75
let WEEK_HEAD_DAY_BOX: Float32 = 24.0
let WEEK_HEAD_DAY_FONT: Float32 = 16.0
let WEEK_HEAD_LUNAR_FONT: Float32 = 10.5
/** `.cal-week-body { padding: 6px; gap: 6px }`。 */
let WEEK_BODY_PAD: Float32 = 6.0
let WEEK_CARD_GAP: Float32 = 6.0
/** `.cal-week-card { padding: 6px 7px; gap: 4px; border-radius: 8px }`。 */
let WEEK_CARD_PAD_V: Float32 = 6.0
let WEEK_CARD_PAD_H: Float32 = 7.0
let WEEK_CARD_GAP_INNER: Float32 = 4.0
let WEEK_CARD_TITLE_FONT: Float32 = 11.5
let WEEK_CARD_TITLE_LINE: Float32 = 15.525
let WEEK_CARD_ICON: Float32 = 12.0
let WEEK_CARD_META_LINE: Float32 = 14.25
let WEEK_CARD_SPAN_FONT: Float32 = 9.5

/** 周视图几何。 */
struct WeekGeom {
    let box: Rect
    let headTop: Float32
    let headH: Float32
    let bodyTop: Float32
    let bodyH: Float32
    let innerX: Float32
    let innerW: Float32

    init(frame: Rect) {
        let x0 = snapped(frame.x)
        let y0 = snapped(frame.y)
        let x1 = snapped(frame.right())
        let y1 = snapped(frame.bottom())
        let outer = Rect(x0, y0, x1 - x0, y1 - y0)
        let headH = snapped(WEEK_HEAD_PAD_V * 2.0 + WEEK_HEAD_WEEKDAY_LINE + 1.0 + WEEK_HEAD_DAY_BOX + 1.0 +
            WEEK_HEAD_WEEKDAY_LINE)
        this.box = outer
        this.headTop = y0 + 1.0
        this.headH = headH
        this.bodyTop = y0 + 1.0 + headH + 1.0
        this.bodyH = max(0.0, y1 - 1.0 - this.bodyTop)
        this.innerX = x0 + 1.0
        this.innerW = max(0.0, outer.w - 2.0)
    }

    func colEdge(index: Int64): Float32 {
        innerX + snapped(innerW * Float32(index) / 7.0)
    }

    func colRect(index: Int64): Rect {
        let left = colEdge(index)
        let right = colEdge(index + 1)
        Rect(left, headTop, right - left, headH + 1.0 + bodyH)
    }
}

struct WeekCardBox {
    let rect: Rect
    let entry: DayEntry

    init(rect: Rect, entry: DayEntry) {
        this.rect = rect
        this.entry = entry
    }
}

/** 按字符折行（CJK 标题不需要词边界；与 `overflow-wrap: anywhere` 等价）。 */
func wrapText(ctx: UiContext, text: String, maxWidth: Float32, sizePx: Float32, weight: Int64): Array<String> {
    let runes = text.toRuneArray()
    let lines = ArrayList<String>()
    if (runes.size == 0) {
        let empty = Array<String>(1, repeat: "")
        return empty
    }
    var builder = StringBuilder()
    for (index in 0..runes.size) {
        let next = builder.toString() + runes[index].toString()
        if (!builder.toString().isEmpty() && textWidthOf(ctx, next, sizePx, weight) > maxWidth) {
            lines.add(builder.toString())
            builder = StringBuilder()
        }
        builder.append(runes[index].toString())
    }
    if (!builder.toString().isEmpty()) {
        lines.add(builder.toString())
    }
    return lines.toArray()
}

/** 卡片高度（含边框）：1 + 6 + 标题行 + 4 + meta 行 + 6 + 1。 */
func weekCardHeight(titleLines: Int64): Float32 {
    return 2.0 + WEEK_CARD_PAD_V * 2.0 + WEEK_CARD_TITLE_LINE * Float32(titleLines) + WEEK_CARD_GAP_INNER +
        WEEK_CARD_META_LINE
}

/** 逐列卡片布局（draw 与命中测试共用同一套几何）。 */
func weekCardBoxes(ctx: UiContext, geom: WeekGeom, columns: Array<DayColumn>): Array<Array<WeekCardBox>> {
    let result = Array<Array<WeekCardBox>>(7, repeat: Array<WeekCardBox>())
    for (index in 0..7) {
        let column = columns[index]
        let columnWidth = geom.colEdge(index + 1) - geom.colEdge(index)
        let cardWidth = max(0.0, columnWidth - 1.0 - WEEK_BODY_PAD * 2.0)
        let titleWidth = max(0.0, cardWidth - 2.0 - WEEK_CARD_PAD_H * 2.0 - WEEK_CARD_ICON - 4.0)
        var y = geom.bodyTop + WEEK_BODY_PAD
        let boxes = ArrayList<WeekCardBox>()
        for (entry in column.entries) {
            let lines = wrapText(ctx, entry.item.title, titleWidth, WEEK_CARD_TITLE_FONT, 550)
            let height = weekCardHeight(Int64(lines.size))
            boxes.add(WeekCardBox(Rect(geom.colEdge(index) + WEEK_BODY_PAD, y, cardWidth, height), entry))
            y = y + height + WEEK_CARD_GAP
        }
        result[index] = boxes.toArray()
    }
    return result
}

class WeekViewWidget <: Widget {
    private let tokens: ThemeTokens
    private let columns: Array<DayColumn>
    private let selected: String
    private let selectedId: ?String
    private let onSelectDay: (String) -> Unit
    private let onOpenItem: (CalItem) -> Unit
    private var frame = Rect.zero()

    init(
        tokens: ThemeTokens,
        columns: Array<DayColumn>,
        selected: String,
        selectedId: ?String,
        onSelectDay: (String) -> Unit,
        onOpenItem: (CalItem) -> Unit
    ) {
        this.tokens = tokens
        this.columns = columns
        this.selected = selected
        this.selectedId = selectedId
        this.onSelectDay = onSelectDay
        this.onOpenItem = onOpenItem
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(max(available.w, 0.0), max(available.h, 0.0))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        let geom = WeekGeom(frame)
        if (geom.box.w < 8.0 || geom.box.h < 8.0) {
            return
        }
        shadow1(ctx, tokens, geom.box, GRID_RADIUS)
        fillRound(ctx, geom.box, GRID_RADIUS, c.surface)

        // 列背景：周末 `surface-2`（含列头），最后一列贴圆角。
        for (index in 0..7) {
            if (!columns[index].weekend) {
                continue
            }
            let rect = geom.colRect(index)
            let bottomLeft: Float32 = if (index == 0) {
                GRID_RADIUS - 1.0
            } else {
                0.0
            }
            let bottomRight: Float32 = if (index == 6) {
                GRID_RADIUS - 1.0
            } else {
                0.0
            }
            ctx.renderer.fillPerCornerRoundedRect(rect, c.surface2, topLeft: 0.0, topRight: 0.0,
                bottomRight: bottomRight, bottomLeft: bottomLeft)
        }

        for (index in 0..7) {
            drawColumn(ctx, geom, index, columns[index])
        }

        // 列分隔线（`border-right`，最后一列无）。
        for (index in 0..6) {
            fillVLine(ctx, geom.colEdge(index + 1) - 1.0, geom.headTop, geom.headH + geom.bodyH, c.border)
        }
        strokeCrisp(ctx, geom.box, GRID_RADIUS, tokens.metrics.borderWidth, c.border)
    }

    private func drawColumn(ctx: UiContext, geom: WeekGeom, index: Int64, column: DayColumn): Unit {
        let c = tokens.color
        let left = geom.colEdge(index)
        let width = geom.colEdge(index + 1) - left
        let isSelected = column.isSelected
        // `.cal-week-col.is-selected .cal-week-head { background: accent-soft; border-left-color: accent }`
        if (isSelected) {
            fillRect(ctx, Rect(left, geom.headTop, width - 1.0, geom.headH), c.accentSoft)
            fillRect(ctx, Rect(left, geom.headTop, WEEK_HEAD_BORDER_LEFT, geom.headH), c.accent)
        }
        fillHLine(ctx, left, geom.headTop + geom.headH, width - 1.0, c.border)

        let textX = left + WEEK_HEAD_BORDER_LEFT + WEEK_HEAD_PAD_H
        let headTop = geom.headTop + WEEK_HEAD_PAD_V
        drawTextLine(ctx, weekdayNameOf(column.ymd.key()), textX, headTop, WEEK_HEAD_WEEKDAY_LINE, c.textFaint,
            WEEK_HEAD_WEEKDAY_FONT, 400)
        let dayTop = headTop + WEEK_HEAD_WEEKDAY_LINE + 1.0
        let dayText = column.ymd.day.toString()
        let dayColor = if (column.isToday) {
            c.accentInk
        } else {
            c.text
        }
        drawTextInBox(ctx, dayText, textX, dayTop, WEEK_HEAD_DAY_BOX, dayColor, WEEK_HEAD_DAY_FONT, 650)
        if (column.isToday) {
            let dayWidth = max(WEEK_HEAD_DAY_BOX, textWidthOf(ctx, dayText, WEEK_HEAD_DAY_FONT, 650) + 2.0)
            strokeDisc(ctx, textX + dayWidth / 2.0, dayTop + WEEK_HEAD_DAY_BOX / 2.0, WEEK_HEAD_DAY_BOX / 2.0 - 0.75,
                1.5, c.accent)
        }
        let lunarTop = dayTop + WEEK_HEAD_DAY_BOX + 1.0
        if (!column.lunarText.isEmpty()) {
            let label = ellipsize(ctx, column.lunarText, width - WEEK_HEAD_BORDER_LEFT - WEEK_HEAD_PAD_H * 2.0,
                WEEK_HEAD_LUNAR_FONT, 400)
            drawTextLine(ctx, label, textX, lunarTop, WEEK_HEAD_WEEKDAY_LINE, c.textMuted, WEEK_HEAD_LUNAR_FONT, 400)
        }

        // `.cal-week-body { padding: 6px; gap: 6px }`
        let boxes = weekCardBoxes(ctx, geom, columns)
        if (column.entries.size == 0) {
            drawTextCentered(ctx, "—", left, geom.bodyTop + WEEK_BODY_PAD, width - 1.0, 32.0, c.textFaint, 12.0, 400)
            return
        }
        for (box in boxes[index]) {
            drawCard(ctx, box)
        }
    }

    private func drawCard(ctx: UiContext, box: WeekCardBox): Unit {
        let c = tokens.color
        let rect = box.rect
        let entry = box.entry
        let current = match (selectedId) {
            case Some(id) => id == entry.item.id
            case None => false
        }
        let radius = tokens.radius.md
        shadow1(ctx, tokens, rect, radius)
        let fill = if (current) {
            c.accentSoft
        } else if (entry.isDone) {
            c.surface2
        } else {
            c.surface
        }
        fillRound(ctx, rect, radius, fill)
        strokeRound(ctx, rect, radius, tokens.metrics.borderWidth, if (current) {
            c.accent
        } else {
            c.border
        })

        let contentX = rect.x + 1.0 + WEEK_CARD_PAD_H
        let contentWidth = rect.w - 2.0 - WEEK_CARD_PAD_H * 2.0
        let titleTop = rect.y + 1.0 + WEEK_CARD_PAD_V
        let titleWidth = contentWidth - WEEK_CARD_ICON - 4.0
        let lines = wrapText(ctx, entry.item.title, titleWidth, WEEK_CARD_TITLE_FONT, 550)
        let glyph = iconGlyphFromId(kindIcon(entry.item.kind)).getOrDefault({=> IconGlyph.Edit})
        paintSpec(ctx, glyph, Rect(contentX, titleTop + 1.0, WEEK_CARD_ICON, WEEK_CARD_ICON), c.textFaint)
        let titleColor = if (entry.isDone) {
            c.textMuted
        } else {
            c.text
        }
        var lineIndex = 0
        for (line in lines) {
            drawTextLine(ctx, line, contentX + WEEK_CARD_ICON + 4.0,
                titleTop + WEEK_CARD_TITLE_LINE * Float32(lineIndex), WEEK_CARD_TITLE_LINE, titleColor,
                WEEK_CARD_TITLE_FONT, 550)
            lineIndex += 1
        }

        // `.cal-week-card-meta { gap: 4px }`：领域点 / 状态点 / `第 n/m 天`。
        let metaTop = titleTop + WEEK_CARD_TITLE_LINE * Float32(lines.size) + WEEK_CARD_GAP_INNER
        let metaCenter = metaTop + WEEK_CARD_META_LINE / 2.0
        var dotX = contentX + 3.5
        fillDisc(ctx, dotX, metaCenter, 3.5, colorFromHex(entry.item.areaColor, c.textFaint))
        dotX = dotX + 3.5 + 4.0 + 3.5
        strokeDisc(ctx, dotX, metaCenter, 2.75, 1.5, statusColorOf(c, entry.item.status))
        if (!entry.spanText.isEmpty()) {
            drawTextTrailing(ctx, entry.spanText, rect.x + rect.w - 1.0 - WEEK_CARD_PAD_H, metaCenter, c.textFaint,
                WEEK_CARD_SPAN_FONT, 400)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        let geom = WeekGeom(frame)
        match (event) {
            case UiEvent.MouseMove(_, _) =>
                claimHoverIfInside(ctx, event, geom.box, "calweek:hover", CursorShape.Interactive)
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (!geom.box.contains(x, y)) {
                    return false
                }
                let boxes = weekCardBoxes(ctx, geom, columns)
                for (index in 0..7) {
                    for (box in boxes[index]) {
                        if (box.rect.contains(x, y)) {
                            onOpenItem(box.entry.item)
                            return true
                        }
                    }
                }
                if (y < geom.bodyTop) {
                    var index: Int64 = 0
                    while (index < 7) {
                        if (x < geom.colEdge(index + 1)) {
                            break
                        }
                        index += 1
                    }
                    if (index < 7) {
                        onSelectDay(columns[index].ymd.key())
                        return true
                    }
                }
            case _ => ()
        }
        false
    }
}

/** `statusColor` 的语义色映射（itemDisplay.ts `statusColor`）。 */
func statusColorOf(c: TokenColors, status: String): Color {
    return match (statusColorToken(status)) {
        case "ok" => c.ok
        case "warn" => c.warn
        case "danger" => c.danger
        case "info" => c.info
        case "accent" => c.accent
        case _ => c.textFaint
    }
}
