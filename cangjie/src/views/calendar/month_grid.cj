package textura.views.calendar

import cui.*
import textura.ui.*
import textura.views.calendar.logic.*

/*
 * 月视图 6×7 网格（MonthGrid.tsx + calendar.css:120-286）。
 *
 * 固定 6 行：行高 = 网格内高 / 6，与月份无关，因此不同月份的总高完全一致。
 * 1px 分隔线、格子背景、日号圆环、农历文字层级、领域色圆点与 `+n` 全部自绘，
 * 以便逐像素对齐（浏览器对 1px 边框做设备像素吸附，这里同样先取整再画）。
 */

/** `.cal-grid { border-radius: var(--radius-lg) }`。 */
let GRID_RADIUS: Float32 = 14.0
/** `.cal-grid-headcell { padding: 6px 8px; font-size: 11.5px }`（行高 1.5）。 */
let GRID_HEAD_PAD: Float32 = 6.0
let GRID_HEAD_FONT: Float32 = 11.5
let GRID_HEAD_LINE: Float32 = 17.25
/** `.cal-cell { padding: 5px 7px 6px; gap: 2px }`。 */
let CELL_PAD_TOP: Float32 = 5.0
let CELL_PAD_LEFT: Float32 = 7.0
let CELL_PAD_RIGHT: Float32 = 7.0
let CELL_PAD_BOTTOM: Float32 = 6.0
let CELL_GAP: Float32 = 2.0
/** `.cal-daynum { min-width: 20px; height: 20px; font-size: 13px }`。 */
let DAYNUM_BOX: Float32 = 20.0
let DAYNUM_FONT: Float32 = 13.0
/** `.cal-lunar { font-size: 10.5px; line-height: 1.35 }`。 */
let LUNAR_FONT: Float32 = 10.5
let LUNAR_LINE: Float32 = 14.175
/** `.cal-dots { min-height: 8px; padding-top: 2px }` + `.cal-dot { width/height: 6px }`。 */
let DOTS_BOX: Float32 = 8.0
let DOT_RADIUS: Float32 = 3.0
/** 实测（ref 截图）：相邻圆点起点相距 10px。 */
let DOT_STEP: Float32 = 9.0
/** `.cal-dot-more { font-size: 9.5px }`。 */
let DOT_MORE_FONT: Float32 = 9.5

/** 网格几何：全部基于取整后的外框，保证两次运行与参考图逐像素一致。 */
struct MonthGridGeom {
    let box: Rect
    let headTop: Float32
    let headH: Float32
    let bodyTop: Float32
    let bodyH: Float32
    let innerX: Float32
    let innerW: Float32
    let rowH: Float32

    init(frame: Rect) {
        let x0 = snapped(frame.x)
        let y0 = snapped(frame.y)
        let x1 = snapped(frame.right())
        let y1 = snapped(frame.bottom())
        let outer = Rect(x0, y0, x1 - x0, y1 - y0)
        let headTop = y0 + 1.0
        let headH = snapped(GRID_HEAD_PAD * 2.0 + GRID_HEAD_LINE)
        let bodyTop = headTop + headH + 1.0
        this.box = outer
        this.headTop = headTop
        this.headH = headH
        this.bodyTop = bodyTop
        this.bodyH = max(0.0, y1 - 1.0 - bodyTop)
        this.innerX = x0 + 1.0
        this.innerW = max(0.0, outer.w - 2.0)
        this.rowH = this.bodyH / 6.0
    }

    /** 第 `index` 条列边界（0..7）；浏览器按最近整数吸附。 */
    func colEdge(index: Int64): Float32 {
        innerX + snapped(innerW * Float32(index) / 7.0)
    }

    func cellRect(row: Int64, col: Int64): Rect {
        let left = colEdge(col)
        let right = colEdge(col + 1)
        Rect(left, bodyTop + rowH * Float32(row), right - left, rowH)
    }
}

/** `.cal-cell` 的底色优先级：selected > outside > weekend > surface。 */
func cellBackground(c: TokenColors, cell: DayCell): Color {
    if (cell.isSelected) {
        return c.accentSoft
    }
    if (!cell.inMonth) {
        return c.bgSubtle
    }
    if (cell.weekend) {
        return c.surface2
    }
    return c.surface
}

class MonthGridWidget <: Widget {
    private let tokens: ThemeTokens
    private let rows: Array<Array<DayCell>>
    private let today: String
    private let selected: String
    private let onSelect: (String) -> Unit
    private let onEnter: () -> Unit
    private let id: String
    private var frame = Rect.zero()

    init(
        tokens: ThemeTokens,
        rows: Array<Array<DayCell>>,
        today: String,
        selected: String,
        onSelect: (String) -> Unit,
        onEnter: () -> Unit
    ) {
        this.id = focusableControlIdentity("CalMonthGrid")
        this.tokens = tokens
        this.rows = rows
        this.today = today
        this.selected = selected
        this.onSelect = onSelect
        this.onEnter = onEnter
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
        let geom = MonthGridGeom(frame)
        if (geom.box.w < 8.0 || geom.box.h < 8.0) {
            return
        }
        // `.cal-grid { background: surface; border: 1px; border-radius: 14; box-shadow: shadow-1 }`
        shadow1(ctx, tokens, geom.box, GRID_RADIUS)
        fillRound(ctx, geom.box, GRID_RADIUS, c.surface2)

        // `.cal-grid-headcell { padding: 6px 8px; text-align: center; 11.5px/600 }`
        for (col in 0..7) {
            let left = geom.colEdge(col)
            let right = geom.colEdge(col + 1)
            let color = if (col >= 5) {
                c.textFaint
            } else {
                c.textMuted
            }
            drawTextCentered(ctx, WEEKDAY_LABELS[col], left, geom.headTop, right - left, geom.headH, color,
                GRID_HEAD_FONT, 600, dy: -1.0)
        }
        // `.cal-grid-head { border-bottom: 1px solid border }`
        fillHLine(ctx, geom.innerX, geom.headTop + geom.headH, geom.innerW, c.border)

        // `.cal-grid-body`：先铺 surface，再按格覆盖 weekend / outside / selected。
        ctx.renderer.fillPerCornerRoundedRect(Rect(geom.innerX, geom.bodyTop, geom.innerW, geom.bodyH), c.surface,
            topLeft: 0.0, topRight: 0.0, bottomRight: GRID_RADIUS - 1.0, bottomLeft: GRID_RADIUS - 1.0)
        for (row in 0..6) {
            for (col in 0..7) {
                let cell = rows[row][col]
                let rect = geom.cellRect(row, col)
                let background = cellBackground(c, cell)
                if (row == 5) {
                    // 最后一行贴着圆角容器，需要按角裁剪。
                    let bottomLeft: Float32 = if (col == 0) {
                        GRID_RADIUS - 1.0
                    } else {
                        0.0
                    }
                    let bottomRight: Float32 = if (col == 6) {
                        GRID_RADIUS - 1.0
                    } else {
                        0.0
                    }
                    ctx.renderer.fillPerCornerRoundedRect(rect, background, topLeft: 0.0, topRight: 0.0,
                        bottomRight: bottomRight, bottomLeft: bottomLeft)
                } else {
                    fillRect(ctx, rect, background)
                }
            }
        }

        // `.cal-cell { border-right: 1px; border-bottom: 1px }`（最后一列/行无边框）。
        for (col in 0..6) {
            fillVLine(ctx, geom.colEdge(col + 1) - 1.0, geom.bodyTop, geom.bodyH, c.border)
        }
        for (row in 0..5) {
            fillHLine(ctx, geom.innerX, geom.bodyTop + geom.rowH * Float32(row + 1) - 1.0, geom.innerW, c.border)
        }

        for (row in 0..6) {
            for (col in 0..7) {
                drawCell(ctx, geom, row, col, rows[row][col])
            }
        }

        // 选中格 `box-shadow: inset 0 0 0 1px var(--accent)`（内阴影画在背景之上、边框之下）。
        for (row in 0..6) {
            for (col in 0..7) {
                let cell = rows[row][col]
                if (!cell.isSelected) {
                    continue
                }
                let rect = geom.cellRect(row, col)
                fillHLine(ctx, rect.x, rect.y, rect.w, c.accent)
                fillHLine(ctx, rect.x, rect.y + rect.h - 1.0, rect.w, c.accent)
                fillVLine(ctx, rect.x, rect.y, rect.h, c.accent)
            }
        }

        // `.cal-grid { border: 1px solid var(--border) }`
        strokeCrisp(ctx, geom.box, GRID_RADIUS, tokens.metrics.borderWidth, c.border)
    }

    private func drawCell(ctx: UiContext, geom: MonthGridGeom, row: Int64, col: Int64, cell: DayCell): Unit {
        let c = tokens.color
        let rect = geom.cellRect(row, col)
        let outside = !cell.inMonth
        // `.cal-cell.is-outside .cal-daynum { color: text-faint; font-weight: 500 }`
        let numColor = if (cell.isToday) {
            c.accentInk
        } else if (outside) {
            c.textFaint
        } else {
            c.text
        }
        let numText = cell.ymd.day.toString()
        let numWidth = max(DAYNUM_BOX, textWidthOf(ctx, numText, DAYNUM_FONT, 600) + 2.0)
        drawTextCentered(ctx, numText, rect.x + CELL_PAD_LEFT, rect.y + CELL_PAD_TOP, numWidth, DAYNUM_BOX, numColor,
            DAYNUM_FONT, 600, dy: -2.0)
        if (cell.isToday) {
            // `.cal-daynum.is-today { box-shadow: inset 0 0 0 1.5px var(--accent); border-radius: 50% }`
            strokeDisc(ctx, rect.x + CELL_PAD_LEFT + numWidth / 2.0, rect.y + CELL_PAD_TOP + DAYNUM_BOX / 2.0,
                DAYNUM_BOX / 2.0 - 0.75, 1.5, c.accent)
        }

        // `.cal-lunar { font-size: 10.5px; line-height: 1.35 }`；节日/节气层级见 calendar.css:255-263。
        if (!cell.lunarText.isEmpty()) {
            var weight = 400
            var color = c.textMuted
            if (outside) {
                color = c.textFaint
                weight = 500
            } else if (cell.lunarKind == LunarLabelKind.Festival) {
                color = c.accentInk
                weight = 600
            } else if (cell.lunarKind == LunarLabelKind.Term) {
                color = c.infoInk
                weight = 550
            }
            let maxWidth = rect.w - CELL_PAD_LEFT - CELL_PAD_RIGHT
            let text = ellipsize(ctx, cell.lunarText, maxWidth, LUNAR_FONT, weight)
            drawTextLine(ctx, text, rect.x + CELL_PAD_LEFT, rect.y + CELL_PAD_TOP + DAYNUM_BOX + CELL_GAP, LUNAR_LINE,
                color, LUNAR_FONT, weight, dy: -1.0)
        }

        // `.cal-dots { margin-top: auto; padding-top: 2px }`：贴住格子底部。
        let borderRow = row < 5
        let bottomInset: Float32 = if (borderRow) {
            1.0
        } else {
            0.0
        }
        let dotsTop = rect.y + rect.h - bottomInset - CELL_PAD_BOTTOM - DOTS_BOX
        let centerY = dotsTop + 2.0 + DOT_RADIUS
        var index = 0
        for (item in cell.visibleItems) {
            let color = colorFromHex(item.areaColor, c.textFaint)
            fillDisc(ctx, rect.x + CELL_PAD_LEFT + DOT_RADIUS + DOT_STEP * Float32(index), centerY, DOT_RADIUS, color)
            index += 1
        }
        if (cell.overflowCount > 0) {
            let text = "+${cell.overflowCount.toString()}"
            let x = rect.x + CELL_PAD_LEFT + DOT_STEP * Float32(index)
            drawTextInBox(ctx, text, x, dotsTop, DOTS_BOX, c.textFaint, DOT_MORE_FONT, 400, dy: 1.0)
        }
    }

    private func keyAt(geom: MonthGridGeom, x: Float32, y: Float32): ?String {
        if (!geom.box.contains(x, y)) {
            return None
        }
        let offset = y - geom.bodyTop
        if (offset < 0.0) {
            return None
        }
        var row: Int64 = 0
        while (row < 6) {
            if (offset < geom.rowH * Float32(row + 1)) {
                break
            }
            row += 1
        }
        if (row >= 6) {
            return None
        }
        var col: Int64 = 0
        while (col < 7) {
            if (x < geom.colEdge(col + 1)) {
                break
            }
            col += 1
        }
        if (col >= 7) {
            return None
        }
        return rows[row][col].key()
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        let geom = MonthGridGeom(frame)
        match (event) {
            case UiEvent.MouseMove(_, _) =>
                claimHoverIfInside(ctx, event, geom.box, "${id}:hover", CursorShape.Interactive)
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                match (keyAt(geom, x, y)) {
                    case Some(key) =>
                        ctx.focus(id, viaKeyboard: false)
                        onSelect(key)
                        return true
                    case None => ()
                }
            case UiEvent.KeyDown(key, isRepeat) =>
                if (ctx.hasFocus(id) && !isRepeat) {
                    match (key) {
                        case Key.Left =>
                            onSelect(addDaysToKey(selected, -1))
                            return true
                        case Key.Right =>
                            onSelect(addDaysToKey(selected, 1))
                            return true
                        case Key.Up =>
                            onSelect(addDaysToKey(selected, -7))
                            return true
                        case Key.Down =>
                            onSelect(addDaysToKey(selected, 7))
                            return true
                        case Key.Home =>
                            onSelect(weekRange(selected).start.key())
                            return true
                        case Key.End =>
                            onSelect(weekRange(selected).end.key())
                            return true
                        case Key.PageUp =>
                            onSelect(addDaysToKey(selected, -7))
                            return true
                        case Key.PageDown =>
                            onSelect(addDaysToKey(selected, 7))
                            return true
                        case Key.Enter =>
                            onEnter()
                            return true
                        case _ => ()
                    }
                }
            case _ => ()
        }
        false
    }

    public func focusableId(): ?String {
        Some(id)
    }
}
