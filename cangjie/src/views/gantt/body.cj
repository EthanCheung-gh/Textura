package textura.views.gantt

import std.collection.*
import std.math.sqrt
import cui.*
import textura.core.data as data
import textura.ui.*
import textura.views.gantt.logic.*

/*
 * 甘特主体（GanttPage.tsx:355-414 的 `.gantt-body`）。
 *
 * 为什么整块自绘：主体是“左侧 272px 树 + 时间轴（含表头/网格/任务条/依赖折线/今日线）”
 * 的像素级对齐场景，行高 36、表头 52、条高 22 都必须严格落格；CUI 的控件盒模型由字体度量
 * 决定，无法钉到这些值。这里用一个自定义 `Widget`（与 `CanvasWidget` 相同的
 * `Renderer` + 帧矩形协议，但自行控制背景与裁剪，见 docs/CUI-PRIMER.md §6）把主体画完整：
 * 文本仍走 `Renderer.text`（与 `Label` 同一条 SDL_ttf 栅格化路径），所以清晰度不受影响。
 *
 * 事件：滚轮纵向滚动（与时间轴同步）、点击选中、任务条拖动/拖边改期、分组折叠。
 * 手势状态放 `GanttViewState`（`remember` 保留），写入后递增 `rev` 触发重建；
 * 绘制阶段只读状态，不改状态。
 */

/** 主体器和器件的几何常量（gantt.css 出处见注释）。 */
let BODY_BORDER: Float32 = 1.0

class GanttBody <: Widget {
    let tokens: ThemeTokens
    let ink: GanttInk
    let rows: Array<GanttTreeRow>
    let projected: Array<GanttRow>
    let depends: Array<data.Edge>
    let range: DateRange
    let zoom: GanttZoom
    let today: String
    let selectedId: String
    let scrollLeft: Float32
    let scrollTop: Float32
    let inspectorOpen: Bool
    let state: GanttViewState
    let rev: State<Int64>
    let onSelect: (String) -> Unit
    let onCommitBar: (String, BarRange) -> Unit
    let onScrollLeft: (Float32) -> Unit
    let onScrollTop: (Float32) -> Unit
    var frame = Rect.zero()

    init(
        tokens: ThemeTokens,
        ink: GanttInk,
        rows: Array<GanttTreeRow>,
        projected: Array<GanttRow>,
        depends: Array<data.Edge>,
        range: DateRange,
        zoom: GanttZoom,
        today: String,
        selectedId: String,
        scrollLeft: Float32,
        scrollTop: Float32,
        inspectorOpen: Bool,
        state: GanttViewState,
        rev: State<Int64>,
        onSelect!: (String) -> Unit,
        onCommitBar!: (String, BarRange) -> Unit,
        onScrollLeft!: (Float32) -> Unit,
        onScrollTop!: (Float32) -> Unit
    ) {
        this.tokens = tokens
        this.ink = ink
        this.rows = rows
        this.projected = projected
        this.depends = depends
        this.range = range
        this.zoom = zoom
        this.today = today
        this.selectedId = selectedId
        this.scrollLeft = scrollLeft
        this.scrollTop = scrollTop
        this.inspectorOpen = inspectorOpen
        this.state = state
        this.rev = rev
        this.onSelect = onSelect
        this.onCommitBar = onCommitBar
        this.onScrollLeft = onScrollLeft
        this.onScrollTop = onScrollTop
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(max(0.0, available.w), max(0.0, available.h))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
        state.viewportW = rect.w
        state.viewportH = rect.h
    }

    public func isFlexible(): Bool {
        true
    }

    public func pointerEventScope(): PointerEventScope {
        PointerEventScope.LayoutBounds
    }

    /** 内容区（去掉 1px 边框）。 */
    func content(): Rect {
        Rect(frame.x + BODY_BORDER, frame.y + BODY_BORDER, max(0.0, frame.w - BODY_BORDER * 2.0),
            max(0.0, frame.h - BODY_BORDER * 2.0))
    }

    /** 检查器列宽（含 1px 左边框）：`.gantt-inspector { width: 320px; border-left: 1px }`。 */
    func inspectorWidth(): Float32 {
        if (inspectorOpen) {
            INSPECTOR_WIDTH
        } else {
            0.0
        }
    }

    func timelineWidth(): Float32 {
        max(0.0, content().w - TREE_WIDTH - inspectorWidth())
    }

    func treeRect(): Rect {
        let box = content()
        Rect(box.x, box.y, min(TREE_WIDTH, box.w), box.h)
    }

    func timelineRect(): Rect {
        let box = content()
        Rect(box.x + TREE_WIDTH, box.y, timelineWidth(), box.h)
    }

    /** 行区域可视高度（扣掉 52px 吸顶表头，GanttTree.tsx:274）。 */
    func rowViewportHeight(): Float32 {
        max(0.0, content().h - HEADER_H)
    }

    /** 行滚动上限。 */
    func maxScrollTop(): Float32 {
        max(0.0, Float32(rows.size) * ROW_H - rowViewportHeight())
    }

    func maxScrollLeft(): Float32 {
        let px = zoomConfig(zoom).pxPerDay
        max(0.0, Float32(totalWidth(range, px)) - timelineWidth())
    }

    public func draw(ctx: UiContext): Unit {
        let box = frame
        if (box.w <= 0.0 || box.h <= 0.0) {
            return
        }
        // 圆角外角：`border-radius: 14` 之外是页面底色（`--bg`），先用底色打底再铺 surface，
        // 最后把四个角的“弧外区域”补回底色（CUI 没有圆角裁剪）。
        fillRound(ctx, box, BODY_RADIUS, tokens.color.bg)
        fillRound(ctx, box, BODY_RADIUS, tokens.color.surface)
        let contentRect = content()
        ctx.renderer.pushClip(contentRect)
        drawTree(ctx, this)
        drawTimeline(ctx, this)
        if (inspectorOpen) {
            drawInspectorSlot(ctx, this)
        }
        ctx.renderer.popClip()
        // 1px 描边（`.gantt-body { border: 1px solid border }`，圆角 14；CSS 边框在 border-box 内侧）
        cssBorder(ctx, box, BODY_RADIUS, tokens.metrics.borderWidth, tokens.color.border)
        paintCornerCutouts(ctx, box, BODY_RADIUS, tokens.color.bg)
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseWheel(_, _, dx, dy) =>
                scrollBy(dx, dy)
                true
            case UiEvent.MouseMove(x, y) => handleMove(x, y)
            case UiEvent.MouseDown(pressButton, x, y) where isPrimaryPointerButton(pressButton) => handleDown(x, y)
            case UiEvent.MouseUp(_, x, y) => handleUp(x, y)
            case _ => false
        }
    }

    // ------------------------------------------------------------------ 事件

    func scrollBy(dx: Float32, dy: Float32): Unit {
        if (dy != 0.0) {
            let next = clampRange(scrollTop + dy, 0.0, maxScrollTop())
            if (next != scrollTop) {
                onScrollTop(next)
            }
        }
        if (dx != 0.0) {
            let next = clampRange(scrollLeft + dx, 0.0, maxScrollLeft())
            if (next != scrollLeft) {
                onScrollLeft(next)
            }
        }
    }

    func handleMove(x: Float32, y: Float32): Bool {
        // 拖拽中：只更新吸附后的天数增量。`drawDragTip` / 任务条预览在 draw 里直接读 gesture，
        // 本帧的绘制就能看见，因此不递增 `rev`（那会重建整个 shell）。
        match (state.gesture) {
            case Some(gesture) =>
                let px = Float32(zoomConfig(zoom).pxPerDay)
                // 严格走 logic 的取整口径：Math.round 半值向 +∞（logic.tsRound）。
                let delta = tsRound(Float64((x - gesture.startX) / px))
                if (delta != gesture.deltaDays) {
                    gesture.deltaDays = delta
                }
                return true
            case None => ()
        }
        // 悬停行同理：`drawTreeRow` / `drawTimelineRow` 每帧读 `hoverRow`，只重绘即可。
        let rowId = rowIdAt(y)
        if (rowId != state.hoverRow) {
            state.hoverRow = rowId
        }
        false
    }

    func handleDown(x: Float32, y: Float32): Bool {
        if (!frame.contains(x, y)) {
            return false
        }
        // 左侧树：点分组箭头折叠，点行选中。
        let tree = treeRect()
        if (x < tree.right()) {
            let index = rowIndexAt(y)
            if (index >= 0) {
                match (rows[index]) {
                    case GanttTreeRow.Group(group) =>
                        if (x >= tree.x + 8.0 + 18.0) {
                            state.pressedRow = treeRowId(rows[index])
                            onSelect(match (group.item) {
                                case Some(item) => item.id
                                case None => ""
                            })
                        } else {
                            // 折叠改变行集合：必须重建（rows 是 render 期算出来的）。
                            state.toggleGroup(group.id)
                            rev.value = rev.value + 1
                        }
                    case GanttTreeRow.Item(item) =>
                        state.pressedRow = item.id
                        onSelect(item.id)
                }
                return true
            }
            onSelect("")
            return true
        }
        // 时间轴：命中任务条则开始拖拽，否则选中该行。
        let hit = barAt(x, y)
        match (hit) {
            case Some(target) =>
                state.pressedRow = target.id
                onSelect(target.id)
                state.gesture = Some(DragGesture(target.id, target.mode, x, target.range, target.rowIndex))
                true
            case None =>
                let index = rowIndexAt(y)
                if (index >= 0) {
                    state.pressedRow = treeRowId(rows[index])
                    match (rows[index]) {
                        case GanttTreeRow.Group(group) => onSelect(match (group.item) {
                            case Some(item) => item.id
                            case None => ""
                        })
                        case GanttTreeRow.Item(item) => onSelect(item.id)
                    }
                } else {
                    state.pressedRow = ""
                    onSelect("")
                }
                true
        }
    }

    func handleUp(x: Float32, y: Float32): Bool {
        let _ = x
        let _ = y
        state.pressedRow = ""
        match (state.gesture) {
            case Some(gesture) =>
                let preview = gesture.preview()
                state.gesture = None
                if (preview.start != gesture.origin.start || preview.end != gesture.origin.end) {
                    onCommitBar(gesture.id, preview)
                }
                true
            case None => false
        }
    }

    // ------------------------------------------------------------------ 命中测试

    /** 屏幕 y → 行下标（`-1` 表示不在行区域）。 */
    func rowIndexAt(y: Float32): Int64 {
        let box = content()
        let local = y - (box.y + HEADER_H)
        if (local < 0.0) {
            return -1
        }
        let index = Int64((Float64(local) + Float64(scrollTop)) / Float64(ROW_H))
        if (index < 0 || index >= rows.size) {
            -1
        } else {
            index
        }
    }

    func rowIdAt(y: Float32): String {
        let index = rowIndexAt(y)
        if (index < 0) {
            return ""
        }
        treeRowId(rows[index])
    }

    /**
     * 一行是否按「选中」绘制：`store.selectedId` 是权威来源，`state.pressedRow` 只是本帧的
     * 按下反馈，让点击的视觉反馈在 store 重建之前的那一帧就出现（两者同色，视觉无变化）。
     */
    func rowSelected(row: GanttTreeRow): Bool {
        if (isRowSelected(selectedId, row)) {
            return true
        }
        !state.pressedRow.isEmpty() && treeRowId(row) == state.pressedRow
    }

    /** 任务条命中：区分整体拖动与左右边缘拖拽（`.gantt-bar-handle` 宽 7）。 */
    func barAt(x: Float32, y: Float32): ?BarTarget {
        let index = rowIndexAt(y)
        if (index < 0) {
            return None
        }
        match (rows[index]) {
            case GanttTreeRow.Item(item) =>
                match (itemRange(item.row)) {
                    case Some(bar) =>
                        if (item.row.kind == GanttKind.Milestone) {
                            let geometry = barGeometry(bar, range.start, zoomConfig(zoom).pxPerDay)
                            let rect = barRect(geometry, index, milestone: true)
                            if (hitsBar(x, y, rect)) {
                                return Some(BarTarget(item.id, DragMode.Move, bar, index))
                            }
                            return None
                        }
                        let geometry = barGeometry(bar, range.start, zoomConfig(zoom).pxPerDay)
                        let rect = barRect(geometry, index)
                        if (!hitsBar(x, y, rect)) {
                            return None
                        }
                        let left = timelineRect().x + Float32(rect.x) - scrollLeft
                        let right = left + Float32(rect.w)
                        if (x < left + BAR_HANDLE_WIDTH) {
                            return Some(BarTarget(item.id, DragMode.Start, bar, index))
                        }
                        if (x > right - BAR_HANDLE_WIDTH) {
                            return Some(BarTarget(item.id, DragMode.End, bar, index))
                        }
                        Some(BarTarget(item.id, DragMode.Move, bar, index))
                    case None => None
                }
            case GanttTreeRow.Group(_) => None
        }
    }

    func hitsBar(x: Float32, y: Float32, rect: BarRect): Bool {
        let origin = timelineRect()
        let barX = origin.x + Float32(rect.x) - scrollLeft
        let barY = origin.y + HEADER_H + Float32(rect.y) - scrollTop
        x >= barX && x <= barX + Float32(rect.w) && y >= barY && y <= barY + Float32(rect.h)
    }
}

/** 命中的任务条：id、拖拽模式、原始区间、行号。 */
class BarTarget {
    let id: String
    let mode: DragMode
    let range: BarRange
    let rowIndex: Int64

    init(id: String, mode: DragMode, range: BarRange, rowIndex: Int64) {
        this.id = id
        this.mode = mode
        this.range = range
        this.rowIndex = rowIndex
    }
}

func clampRange(value: Float32, lower: Float32, upper: Float32): Float32 {
    if (value < lower) {
        lower
    } else if (value > upper) {
        upper
    } else {
        value
    }
}

/**
 * 圆角矩形的“弧外区域”补底色：`border-radius: 14px` 的四个角在 CSS 里是页面底色，
 * CUI 的裁剪只有矩形，所以逐行回填（半径 14 → 每个角 14 条 1px 细条）。
 */
func paintCornerCutouts(ctx: UiContext, box: Rect, radius: Float32, color: Color): Unit {
    let r = max(0.0, min(radius, minFloat(box.w, box.h) / 2.0))
    if (r <= 0.0) {
        return
    }
    var dy: Float32 = 0.0
    while (dy < r) {
        let drop = r - dy
        let cut = r - Float32(sqrt(Float64(r * r - drop * drop)))
        if (cut > 0.0) {
            let y = box.y + dy
            ctx.renderer.fill(Rect(box.x, y, cut, 1.0), color)
            ctx.renderer.fill(Rect(box.right() - cut, y, cut, 1.0), color)
            let bottomY = box.bottom() - 1.0 - dy
            ctx.renderer.fill(Rect(box.x, bottomY, cut, 1.0), color)
            ctx.renderer.fill(Rect(box.right() - cut, bottomY, cut, 1.0), color)
        }
        dy += 1.0
    }
}

/**
 * 检查器列的底：`.gantt-inspector { width: 320px; border-left: 1px solid border; background: surface }`
 * （gantt.css:806-815）。面板内容由 `textura.ui` 控件绘制在画布之上，这里只铺底与左边框。
 */
func drawInspectorSlot(ctx: UiContext, body: GanttBody): Unit {
    let box = body.content()
    let x = box.right() - body.inspectorWidth()
    if (body.inspectorWidth() <= 0.0) {
        return
    }
    fillRect(ctx, Rect(x, box.y, body.inspectorWidth(), box.h), body.tokens.color.surface)
    vline(ctx, x, box.y, box.h, body.tokens.color.border)
}
