package textura.views.okr

import std.collection.ArrayList
import cui.*
import textura.core.data.{Area, Item}
import textura.ui.*
import textura.views.okr.logic.{OkrSchedule, formatSchedule}

/*
 * 「关联执行项」弹窗里的候选列表（`LinkItemsDialog.tsx` 的 `.okr-link-list`，okr.css:1333-1404）。
 *
 * ## 为什么是自绘列表
 *
 * 旧实现把每一行做成 `HStack { Button; VStack { Label… }; ProgressView }`。`ProgressView.measure`
 * 返回 `available.w`（进度条要占满轨道），而它在 HStack 里是**非 flex** 子项，于是固定测量阶段
 * 它独吞整行宽度，`.flex()` 的主列只能分到 0：标题/徽章的盒子宽度为 0，文字实际不可见
 * ——真机上就是「列表里看不到执行项」。这里按本页既有做法（`PageCanvas`）逐像素布局，
 * 每个字段的宽度都由 CSS 公式推导，不再依赖栈的剩余宽度分配。
 *
 * 行高/内边距/颜色全部来自 okr.css：
 *   `.okr-link-item { gap:10; padding:8px 10px; border:1px; radius:8 }`
 *   `.okr-link-title { 13px/1.5; weight 550 }`、`.okr-link-meta { gap:6; 10.5px }`
 *   `.okr-link-progress { flex: 0 0 100px; gap:6 }`、`.okr-check { 14×14 }`
 * 列表窗口 `max-height: 46vh`，行间距 2px，超出后滚轮滚动。
 */

/** `.okr-link-item` 边框盒高度：1 + 8 + 19.5 + 2 + 15.75 + 8 + 1（border-box）。 */
let OKR_LINK_ROW_H: Float32 = 55.25
/** `.okr-link-list { gap: 2px }`。 */
let OKR_LINK_ROW_GAP: Float32 = 2.0
/** `.okr-link-list { max-height: 46vh }`。 */
let OKR_LINK_LIST_RATIO: Float32 = 0.46
/** `.okr-link-item { padding: 8px 10px }`。 */
let OKR_LINK_ROW_PAD_X: Float32 = 10.0
/** `.okr-link-item { gap: 10px }`。 */
let OKR_LINK_ROW_GAP_X: Float32 = 10.0
/** `.okr-check { width: 14px; height: 14px }`（okr.css:773；Web 原版不是 16px）。 */
let OKR_LINK_CHECK: Float32 = 14.0
/** `.okr-link-progress { flex: 0 0 100px }`。 */
let OKR_LINK_PROGRESS_W: Float32 = 100.0
/** `.okr-link-progress { gap: 6px }`。 */
let OKR_LINK_PROGRESS_GAP: Float32 = 6.0
/** `.okr-link-title { font-size: 13px }` / `.okr-link-meta { font-size: 10.5px }`。 */
let OKR_LINK_TITLE_SIZE: Float32 = 13.0
let OKR_LINK_META_SIZE: Float32 = 10.5
let OKR_LINK_AREA_SIZE: Float32 = 11.5
/** 行标题行盒与元信息行盒（line-height 1.5）。 */
let OKR_LINK_TITLE_LINE: Float32 = OKR_LINK_TITLE_SIZE * 1.5
let OKR_LINK_META_LINE: Float32 = OKR_LINK_META_SIZE * 1.5
/** `.okr-link-meta { gap: 6px }`。 */
let OKR_LINK_META_GAP: Float32 = 6.0
/** `.okr-area-dot { width: 7px }` / `.okr-area { gap: 5px }`。 */
let OKR_LINK_DOT: Float32 = 7.0
let OKR_LINK_AREA_GAP: Float32 = 5.0
/** 列表行高亮/选中底色取令牌（accent-soft 与 surface-2）。 */
let OKR_LINK_CHECKED_BORDER_ALPHA: Int64 = 77

/** 行语义 id 前缀（`OkrLinkRowData.id()`；`toggleLinkRow` 依赖它取回条目 id）。 */
let OKR_LINK_ROW_ID_PREFIX: String = "okr-link-row-"

/** `.okr-link-meta` 的排期文案（`formatSchedule`：无排期显示「未排期」）。 */
func linkScheduleText(item: Item): String {
    match (item.gantt) {
        case Some(gantt) => formatSchedule(OkrSchedule(start: gantt.start, end: gantt.end))
        case None =>
            let missing: ?OkrSchedule = None
            formatSchedule(missing)
    }
}

/** One laid-out candidate row: data + the states the row paints. */class OkrLinkRowData {
    let item: Item
    let area: ?Area
    let linked: Bool
    let checked: Bool
    let progress: Float32

    init(item: Item, area: ?Area, linked: Bool, checked: Bool, progress: Float32) {
        this.item = item
        this.area = area
        this.linked = linked
        this.checked = checked
        this.progress = progress
    }

    func id(): String {
        "${OKR_LINK_ROW_ID_PREFIX}${item.id}"
    }
}

/**
 * The scrollable candidate list. Rows are painted by a `PageCanvas` (same layout maths as the
 * OKR page); clicks, hover and the wheel are handled by the widget itself.
 */
class OkrLinkList <: Widget {    private let tokens: ThemeTokens
    private let theme: Theme
    private let rows: Array<OkrLinkRowData>
    private let scroll: State<Float32>
    private let onToggle: (String) -> Unit
    private var frame = Rect.zero()
    private var canvas: ?PageCanvas = None
    private var hitRows: Array<(String, Rect)> = Array<(String, Rect)>()
    private var contentHeight: Float32 = 0.0

    init(tokens: ThemeTokens, theme: Theme, rows: Array<OkrLinkRowData>, scroll: State<Float32>,
        onToggle: (String) -> Unit) {
        this.tokens = tokens
        this.theme = theme
        this.rows = rows
        this.scroll = scroll
        this.onToggle = onToggle
        emit(this)
    }

    /** Natural content height of all rows (row boxes + the 2px gaps between them). */
    private func naturalHeight(): Float32 {
        if (rows.isEmpty()) {
            return 0.0
        }
        Float32(rows.size) * OKR_LINK_ROW_H + Float32(rows.size - 1) * OKR_LINK_ROW_GAP
    }

    /** `.okr-link-list { max-height: 46vh }` — the viewport the list may occupy. */
    private func maxHeight(ctx: UiContext): Float32 {
        max(0.0, ctx.viewportHeight * OKR_LINK_LIST_RATIO)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        contentHeight = naturalHeight()
        Size(max(available.w, 0.0), min(contentHeight, maxHeight(ctx)))
    }

    public func layout(ctx: UiContext, rect: Rect): Unit {
        frame = rect
        let content = naturalHeight()
        let limit = max(0.0, content - rect.h)
        scroll.value = min(limit, max(0.0, scroll.value))
        let c = tokens.color
        let board = PageCanvas(tokens, theme)
        let hits = ArrayList<(String, Rect)>()
        let visible = ArrayList<OkrLinkRowData>()
        var top = rect.y - scroll.value
        for (row in rows) {
            let rowRect = Rect(rect.x, top, rect.w, OKR_LINK_ROW_H)
            top += OKR_LINK_ROW_H + OKR_LINK_ROW_GAP
            // Only rows that intersect the viewport are painted/hit-tested.
            if (rowRect.bottom() <= rect.y || rowRect.y >= rect.bottom()) {
                continue
            }
            visible.add(row)
            hits.add((row.id(), rowRect))
            let hovered = ctx.isHovered(row.id())
            let centerY = rowRect.centerY()
            let mainX = rowRect.x + 1.0 + OKR_LINK_ROW_PAD_X + OKR_LINK_CHECK + OKR_LINK_ROW_GAP_X
            let progressX = rowRect.right() - 1.0 - OKR_LINK_ROW_PAD_X - OKR_LINK_PROGRESS_W
            let mainRight = progressX - OKR_LINK_ROW_GAP_X
            // `.okr-link-item.is-linked { background: surface-2 }` wins over `.is-checked`
            // in the Web cascade (is-linked is declared after is-checked).
            if (row.linked) {
                board.fill(rowRect, OKR_R_MD, c.surface2)
            } else if (row.checked) {
                board.fill(rowRect, OKR_R_MD, c.accentSoft)
                board.stroke(rowRect, OKR_R_MD, c.accent.withAlpha(OKR_LINK_CHECKED_BORDER_ALPHA))
            } else if (hovered) {
                board.fill(rowRect, OKR_R_MD, c.surface2)
            }
            // `.okr-check` 14×14, vertically centred by `align-items: center`.
            let checkRect = Rect(rowRect.x + 1.0 + OKR_LINK_ROW_PAD_X, centerY - OKR_LINK_CHECK / 2.0,
                OKR_LINK_CHECK, OKR_LINK_CHECK)
            if (row.checked) {
                board.fill(checkRect, 3.0, c.accent)
                board.icon(Rect(checkRect.x + 1.5, checkRect.y + 1.5, checkRect.w - 3.0, checkRect.h - 3.0),
                    IconGlyph.Check, c.textOnStrong)
            } else {
                board.fill(checkRect, 3.0, c.surface)
                board.stroke(checkRect, 3.0, c.borderStrong)
            }
            let titleCenter = rowRect.y + 1.0 + 8.0 + OKR_LINK_TITLE_LINE / 2.0
            board.text(ctx, mainX, titleCenter,
                ellipsize(ctx, row.item.title, OKR_LINK_TITLE_SIZE, 550, max(0.0, mainRight - mainX)),
                OKR_LINK_TITLE_SIZE, 550, if (row.linked) {
                    c.textMuted
                } else {
                    c.text
                })
            let metaCenter = titleCenter + OKR_LINK_TITLE_LINE / 2.0 + 2.0 + OKR_LINK_META_LINE / 2.0
            var metaX = mainX
            metaX += board.badge(ctx, metaX, metaCenter - OKR_BADGE_H / 2.0, okrKindLabel(row.item.kind),
                BadgeTone.Neutral) + OKR_LINK_META_GAP
            metaX += board.badge(ctx, metaX, metaCenter - OKR_BADGE_H / 2.0, okrStatusLabel(row.item.status),
                okrStatusTone(row.item.status)) + OKR_LINK_META_GAP
            match (row.area) {
                case Some(area) =>
                    board.dot(metaX + OKR_LINK_DOT / 2.0, metaCenter, OKR_LINK_DOT / 2.0,
                        hexColor(area.color, c.textMuted))
                    metaX += OKR_LINK_DOT + OKR_LINK_AREA_GAP
                    metaX += board.text(ctx, metaX, metaCenter,
                        ellipsize(ctx, area.name, OKR_LINK_AREA_SIZE, 400, max(0.0, mainRight - metaX)),
                        OKR_LINK_AREA_SIZE, 400, c.textMuted) + OKR_LINK_META_GAP
                case None => ()
            }
            metaX += board.text(ctx, metaX, metaCenter,
                ellipsize(ctx, linkScheduleText(row.item), OKR_LINK_META_SIZE, 400,
                    max(0.0, mainRight - metaX)), OKR_LINK_META_SIZE, 400, c.textMuted, mono: true) + OKR_LINK_META_GAP
            if (row.linked) {
                let _ = board.badge(ctx, metaX, metaCenter - OKR_BADGE_H / 2.0, "已关联", BadgeTone.Ok)
            }
            // `.okr-link-progress`: the bar takes the remaining 100px minus label and 6px gap.
            let label = "${Int64(row.progress)}%"
            let labelW = okrTextW(ctx, label, OKR_LINK_META_SIZE, 400, mono: true)
            let barW = max(0.0, OKR_LINK_PROGRESS_W - OKR_LINK_PROGRESS_GAP - labelW)
            let _ = board.progress(ctx, Rect(progressX, centerY - 2.5, barW, 5.0), row.progress,
                okrProgressTone(Int64(row.progress), false), ControlSize.Sm)
            board.text(ctx, progressX + barW + OKR_LINK_PROGRESS_GAP, centerY, label, OKR_LINK_META_SIZE, 400,
                c.textMuted, mono: true)
        }
        canvas = board
        hitRows = hits.toArray()
        // The whole row is one accessible checkbox: it carries the title, the checked state and
        // the same Activate action a click performs (keeps the list assertable from a11y/tests).
        var index: Int64 = 0
        while (index < visible.size && index < hitRows.size) {
            let row = visible[index]
            let (id, rowRect) = hitRows[index]
            let top = max(rowRect.y, rect.y)
            let bottom = min(rowRect.bottom(), rect.bottom())
            let clipped = Rect(rowRect.x, top, rowRect.w, max(0.0, bottom - top))
            ctx.registerSemantics(
                SemanticsNode(id, Semantics(label: row.item.title, role: SemanticsRole.Checkbox,
                    checked: Some(row.checked)), rowRect, actions: [SemanticsAction.Activate],
                    visibleBounds: Some(clipped)), perform: {action =>
                    match (action) {
                        case SemanticsAction.Activate =>
                            onToggle(id)
                            true
                        case _ => false
                    }
                })
            index += 1
        }
    }

    public func draw(ctx: UiContext): Unit {
        ctx.renderer.pushClip(frame)
        match (canvas) {
            case Some(board) =>
                board.draw(ctx)
                board.drawChildren(ctx)
            case None => ()
        }
        ctx.renderer.popClip()
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(_, _) =>
                for ((id, rect) in hitRows) {
                    claimHoverIfInside(ctx, event, rect, id, CursorShape.Interactive)
                }
            case UiEvent.MouseDown(button, x, y) where isPrimaryPointerButton(button) =>
                for ((id, rect) in hitRows) {
                    if (rect.contains(x, y)) {
                        onToggle(id)
                        return true
                    }
                }
            case UiEvent.MouseWheel(_, dy, x, y) =>
                if (!frame.contains(x, y)) {
                    return false
                }
                let limit = max(0.0, naturalHeight() - frame.h)
                if (limit <= 0.0) {
                    return false
                }
                scroll.value = min(limit, max(0.0, scroll.value - dy * 40.0))
                ctx.requestFrame()
                return true
            case _ => ()
        }
        false
    }

    public func isFlexible(): Bool {
        true
    }
}
