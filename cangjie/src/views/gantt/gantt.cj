package textura.views.gantt

import std.collection.*
import cui.*
import textura.core.data as data
import textura.ui.*
import textura.views.gantt.logic.*

/*
 * 甘特视图入口（Web 版 `src/modules/gantt/GanttPage.tsx` 的 1:1 移植）。
 *
 * 结构：
 *   page-header（甘特 / 时间轴上的承诺与依赖。）
 *   toolbar（日/周/月、上一段-今天-下一段、区间标签、已排期计数、新建任务/适配窗口/详情）
 *   body   （左 272 树 + 时间轴 + 可选 320 检查器）
 *
 * 分工：
 * - 布局与刻度全部来自 `textura.views.gantt.logic`（ROW_HEIGHT / HEADER_HEIGHT / buildRange /
 *   buildHeader / barGeometry / moveBar / resizeBar / visibleRows / visibleColumns /
 *   dependencyPath），视图层不重复实现取整或吸附；
 * - 工具栏用 `textura.ui` 控件，主体用自绘 Widget（见 body.cj 顶部说明）；
 * - 领域事实只来自 `ctx.store.state.value()`，写操作只走 `ctx.store.*`。
 */

public func bootstrapTitle(): String {
    "甘特"
}

public func bootstrapNote(): String {
    "甘特视图：时间轴上的承诺与依赖，支持日/周/月缩放、拖动改期与依赖折线。"
}

/** 首次进入时，最早任务左侧保留的天数（GanttPage.tsx:34 `FIT_MARGIN_DAYS`）。 */
let FIT_MARGIN_DAYS: Float32 = 4.0

public func render(ctx: data.ViewContext): Unit {
    let tokens = tokensFor(ctx.theme)
    let ink = GanttInk(tokens)
    let theme = tokens.theme()
    let workspace = ctx.store.state.value()
    let uiState = ctx.store.ui.value()
    let zoom = zoomFromWire(uiState.ganttZoom)
    let today = ctx.today

    // 投影 + 派生（每帧重建的纯函数层，10k 行以内是毫秒级）
    let projected = toGanttRows(workspace)
    let schedulable = ganttableRows(projected)
    let baseRange = buildRange(schedulable, zoom, today: today)

    // 跨帧状态：滚动位置与折叠集合
    let rev = rememberState<Int64>("gantt-rev") {0}
    let leftState = rememberState<Float64>("gantt-scroll-left") {-1.0}
    let topState = rememberState<Float64>("gantt-scroll-top") {0.0}
    let extraBefore = rememberState<Int64>("gantt-extra-before") {0}
    let extraAfter = rememberState<Int64>("gantt-extra-after") {0}
    let view = remember<GanttViewState>("gantt-view") {GanttViewState()}
    let _ = rev.value

    let range = DateRange(addDaysKey(baseRange.start, -extraBefore.value),
        addDaysKey(baseRange.end, extraAfter.value))
    let config = zoomConfig(zoom)
    let px = Float32(config.pxPerDay)

    // 横向滚动：缺省（-1）表示尚未滚动过，按「最早任务 − 4 天」对齐
    let defaultLeft = defaultScrollLeft(schedulable, range, px)
    let scrollLeft = if (leftState.value < 0.0) {
        defaultLeft
    } else {
        Float32(leftState.value)
    }
    let scrollTop = Float32(topState.value)
    let timelineWidth = max(1.0,
        view.viewportW - 2.0 * BODY_BORDER - TREE_WIDTH - if (uiState.inspectorOpen) {
            INSPECTOR_WIDTH
        } else {
            0.0
        })
    let visible = visibleRange(range, Float64(scrollLeft), Float64(timelineWidth), Float64(px))
    let rangeLabel = formatRangeLabel(visible.start, visible.end)
    let scheduled = scheduledCount(schedulable)
    let total = schedulable.size

    let rows = buildRows(projected, view.collapsed)
    let selectedId = ctx.store.selectedId.value().getOrDefault({=> ""})
    let depends = ArrayList<data.Edge>()
    for (edge in workspace.edges) {
        if (edge.edgeType == data.EdgeType.Depends) {
            depends.add(edge)
        }
    }

    let zoomIndexState = rememberState<Int64>("gantt-zoom-index") {zoomIndex(zoom)}
    let zoomBinding = zoomIndexState.project(
        get: {value => value},
        set: {_, next =>
            if (next != zoomIndex(zoom)) {
                applyZoom(ctx, schedulable, leftState, range, scrollLeft, px, zoomOfIndex(next))
            }
            next
        }
    )

    let bodyHeight = pageBodyHeight(ctx, tokens)

    VStack(spacing: vp(PAGE_GAP)) {
        GanttPageHeader(tokens)
        buildToolbar(theme, tokens, zoom, rangeLabel, scheduled, total, uiState.inspectorOpen,
            zoomBinding,
            compact: ctx.width <= 1180,
            onPrev: {=> navigate(ctx, extraBefore, extraAfter, scrollLeft, timelineWidth, px, -1)},
            onNext: {=> navigate(ctx, extraBefore, extraAfter, scrollLeft, timelineWidth, px, 1)},
            onToday: {=> scrollToToday(leftState, range, today, px, timelineWidth)},
            onFit: {=> fitToEarliest(leftState, schedulable, range, px)},
            onCreate: {=> createTask(ctx, view, workspace, selectedId, today)},
            onToggleInspector: {=> ctx.store.setUi({state => state.inspectorOpen = !state.inspectorOpen})})

        ZStack {
            GanttBody(tokens, ink, rows, projected, depends.toArray(), range, zoom, today, selectedId, scrollLeft,
                scrollTop, uiState.inspectorOpen, view, rev,
                onSelect: {id => ctx.store.select(cleared(id))},
                onCommitBar: {id, bar => commitBar(ctx, workspace, id, bar)},
                onScrollLeft: {value => leftState.value = Float64(value)},
                onScrollTop: {value => topState.value = Float64(value)})
            if (uiState.inspectorOpen) {
                HStack(spacing: vp(0.0)) {
                    Spacer()
                    VStack(spacing: vp(0.0)) {
                        buildInspector(ctx, theme, tokens, workspace, selectedId,
                            {id => ctx.store.select(cleared(id))},
                            {=> ctx.store.setUi({state => state.inspectorOpen = false})})
                    }.hug().width(INSPECTOR_WIDTH - 2.0)
                }
                    .hug()
                    .fillWidth()
                    .fillHeight()
                    .padding(vp(0.0), vp(BODY_BORDER), vp(BODY_BORDER), vp(BODY_BORDER))
            }
        }
            // 显式高度：shell 用 `ScrollView` 包裹路由内容（`overflow: auto`），父级高度是无界的，
            // 若让主体跟随父级，2000 行时画布会铺满整条内容（虚拟化失效）。这里按窗口高度
            // 减去 shell chrome 与页头/工具栏算出可视高度，主体内部滚动与行窗口才有意义。
            .height(bodyHeight)
            .fillWidth()
    }
        .crossAxisAlignment(CrossAxisAlignment.Start)
        .hug()
        .fillWidth()
}

/**
 * 主体高度 = 窗口高 − topbar − `.shell-content` 上下内边距 − 页头 − 两处 12px 间距 − 工具栏。
 *
 * shell chrome 的两个量取自设计令牌（`--topbar-height = 56`、`--space-5 = 24`），
 * 与 `shell.css` 的 `.topbar` / `.shell-content` 同源；1440×900 下等于实测的 667。
 */
func pageBodyHeight(ctx: data.ViewContext, tokens: ThemeTokens): Float32 {
    let chrome = tokens.metrics.topbarHeight + tokens.space.s5 * 2.0 + PAGE_HEADER_HEIGHT + PAGE_GAP * 2.0 +
        TOOLBAR_HEIGHT
    max(200.0, Float32(ctx.height) - chrome)
}

/** 缺省横向滚动：最早任务左侧留 4 天（GanttPage.tsx:300-315）。 */
func defaultScrollLeft(rows: Array<GanttRow>, range: DateRange, px: Float32): Float32 {
    match (earliestStart(rows)) {
        case Some(earliest) =>
            max(0.0, Float32(dateToX(earliest, range.start, Float64(px))) - FIT_MARGIN_DAYS * px)
        case None => 0.0
    }
}

/**
 * 切换缩放：把当前左边缘日期留在左边缘（GanttPage.tsx:216-224 / 287-298）。
 * 新范围只依赖 zoom 与条目，因此可以在这里直接算出来并落滚动位置。
 */
func applyZoom(ctx: data.ViewContext, rows: Array<GanttRow>, leftState: State<Float64>, range: DateRange,
    scrollLeft: Float32, px: Float32, next: GanttZoom): Unit {
    let leftKey = xToKey(Float64(scrollLeft), range.start, Float64(px))
    let nextRange = buildRange(rows, next, today: ctx.today)
    let nextPx = Float32(zoomConfig(next).pxPerDay)
    let target = max(0.0, Float32(dateToX(leftKey, nextRange.start, Float64(nextPx))))
    leftState.value = Float64(target)
    ctx.store.setGanttZoom(zoomWire(next))
}

/** 上下段平移（GanttPage.tsx:249-275）：到边界时扩画布而不是停住。 */
func navigate(ctx: data.ViewContext, extraBefore: State<Int64>, extraAfter: State<Int64>, scrollLeft: Float32,
    viewportW: Float32, px: Float32, direction: Int64): Unit {
    let _ = ctx
    let step = maxFloat(160.0, Float32(tsRound(Float64(viewportW * 0.8))))
    if (direction < 0) {
        if (scrollLeft <= 2.0) {
            let days = max(14, tsCeilInt(Float64(step / px)) + 7)
            extraBefore.value = extraBefore.value + days
        }
        return
    }
    let days = max(14, tsCeilInt(Float64(step / px)) + 7)
    extraAfter.value = extraAfter.value + days
}

/** 「今天」：把今天放到视口左侧 35% 处（GanttPage.tsx:226-231）。 */
func scrollToToday(left: State<Float64>, range: DateRange, today: String, px: Float32, viewportW: Float32): Unit {
    let x = Float32(dateToX(today, range.start, Float64(px)))
    left.value = Float64(maxFloat(0.0, minFloat(x - viewportW * 0.35, maxFloat(0.0, x))))
}

/** 「适配窗口」：回到最早任务前 4 天（GanttPage.tsx:233-247）。 */
func fitToEarliest(left: State<Float64>, rows: Array<GanttRow>, range: DateRange, px: Float32): Unit {
    left.value = Float64(defaultScrollLeft(rows, range, px))
}

/** 拖动落点写回 store（GanttPage.tsx:199-214）。 */
func commitBar(ctx: data.ViewContext, workspace: data.Workspace, id: String, bar: BarRange): Unit {
    let _ = workspace
    ctx.store.updateItem(id, data.ItemPatch().withGanttRange(Some(bar.start), Some(bar.end)))
}

/** 新建任务：在当前选中分组下建一条今天起 3 天的行动（GanttPage.tsx:179-197）。 */
func createTask(ctx: data.ViewContext, view: GanttViewState, workspace: data.Workspace, selectedId: String,
    today: String): Unit {
    var parentId: ?String = noKey()
    var selected: ?data.Item = noItem()
    if (!selectedId.isEmpty()) {
        selected = data.itemById(workspace, selectedId)
    }
    match (selected) {
        case Some(item) =>
            parentId = if (item.kind == data.ItemKind.Project || item.kind == data.ItemKind.Sop) {
                Some(item.id)
            } else {
                item.parentId
            }
        case None => ()
    }
    let gantt = data.GanttPatch()
    gantt.start = data.SetValue<?String>.Value(Some(today))
    gantt.end = data.SetValue<?String>.Value(Some(addDaysKey(today, 2)))
    gantt.progress = data.SetValue<Float64>.Value(0.0)
    let created = ctx.store.createItem(data.NewItemInput(data.ItemKind.Action, "新任务", parentId: parentId,
        status: Some(data.ItemStatus.Active), gantt: Some(gantt)))
    view.expandAncestors(toGanttRows(workspace), parentId)
    ctx.store.select(Some(created.id))
    ctx.store.setUi({state => state.inspectorOpen = true})
    ctx.store.notify("已创建任务，可在右侧详情里改标题", tone: data.NoticeTone.Success)
}
