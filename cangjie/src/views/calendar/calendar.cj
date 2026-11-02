package textura.views.calendar

import std.collection.*
import cui.*
import textura.core.data.*
import textura.ui.*
import textura.views.calendar.logic.*

/*
 * 日历视图（src/modules/calendar/CalendarPage.tsx 的 1:1 移植）。
 *
 * 页面骨架（calendar.css:8-118）：
 *   .cal-page      gap 16；头部 56.5 高；下面 1fr + 320px 两栏，间距 16
 *   .cal-main      gap 8；网格 flex，提示条 17.25
 *   .cal-panel     宽 320；头部 95.35 / 列表 flex / 快速添加 59.75 / 甘特入口 40
 *
 * 日期锚点一律来自 `ViewContext.today`，不读系统时钟；选中日期、视图模式、
 * 面板开关与输入草稿都放在 `rememberState` 里，重建后保持。
 */

/** `.cal-layout { grid-template-columns: minmax(0, 1fr) 320px; gap: var(--space-4) }`。 */
let LAYOUT_PANEL_WIDTH: Float32 = 320.0
let LAYOUT_GAP: Float32 = 16.0
/** `.cal-main { gap: var(--space-2) }`。 */
let MAIN_GAP: Float32 = 8.0
/** `.cal-toolbar { gap: var(--space-2) }`。 */
let TOOLBAR_GAP: Float32 = 8.0
/** `.cal-quick { padding: var(--space-3); gap: 6px }` + `.cal-quick .input { min-height: 30px }`。 */
let QUICK_PAD: Float32 = 12.0
let QUICK_GAP: Float32 = 6.0
let QUICK_INPUT_HEIGHT: Float32 = 35.0
/** 快速添加行总高：`border-top 1 + padding 12*2 + input 35`（实测 CUI TextField 高度）。 */
let QUICK_ROW_HEIGHT: Float32 = 60.0
/** 甘特入口行：`btn 28 + padding-bottom 12`。 */
let PANEL_FOOT_HEIGHT: Float32 = 40.0
let QUICK_FONT: Float32 = 12.5

/**
 * `.page.cal-page { height: calc(100vh - var(--topbar-height) - var(--space-5) * 2); min-height: 520px }`
 *
 * Web 用 `100vh`；桌面移植用 `ViewContext.height`（视口逻辑高）+ 同一组令牌换算，
 * 不读系统时钟/窗口状态。壳层内容区（`ScrollView` + `padding: 24px`）给的是无界高度，
 * 视图必须自己定死这一高度，否则页面会被撑高并出现滚动条车道。
 */
func calendarPageHeight(tk: ThemeTokens, viewportHeight: Int64): Float32 {
    let value = Float32(viewportHeight) - tk.metrics.topbarHeight - tk.space.s5 * 2.0
    if (value < 520.0) {
        520.0
    } else {
        value
    }
}

public func bootstrapTitle(): String {
    return "日历"
}

public func bootstrapNote(): String {
    return "日历视图：6×7 月网格、周视图、农历与节气、当日日程面板。"
}

public func render(ctx: ViewContext): Unit {
    let theme = if (ctx.theme == "dark") {
        texturaDark()
    } else {
        texturaLight()
    }
    let tk = tokensOf(theme)
    let workspace = ctx.store.state.value()
    let today = ctx.today

    /* ------------------------------- 视图状态 ------------------------------- */
    let modeState = rememberState<Int64>("calendar-mode") {0}
    let selectedState = rememberState<String>("calendar-selected") {today}
    let panelState = rememberState<Bool>("calendar-panel-open") {true}
    let collapsedState = rememberState<Bool>("calendar-user-collapsed") {false}
    let draftState = rememberState<String>("calendar-draft") {""}
    let openSelectState = rememberState<Int64>("calendar-open-select") {0}
    let yearScrollState = rememberState<Int64>("calendar-year-scroll") {0}
    let monthScrollState = rememberState<Int64>("calendar-month-scroll") {0}
    let listScrollState = rememberState<Float64>("calendar-list-scroll") {0.0}

    let pageHeight = calendarPageHeight(tk, ctx.height)
    let layoutHeight = pageHeight - HEADER_HEIGHT - LAYOUT_GAP
    /** 面板内容列高度（扣掉 1px 上下边框）。 */
    let panelInnerHeight = layoutHeight - 2.0
    let listHeight = panelInnerHeight - (PANEL_HEAD_H + 1.0) - QUICK_ROW_HEIGHT - PANEL_FOOT_HEIGHT

    let selected = selectedState.value
    let selectedDate = match (parseKey(selected)) {
        case Some(value) => value
        case None => Ymd(1970, 1, 1)
    }

    /* ------------------------------- 数据投影 ------------------------------- */
    let items = calItemsOf(workspace)
    let itemAreas = itemAreasOf(workspace)
    let rows = buildMonthView(selectedDate.year, selectedDate.month, items, today, selected)
    let weekColumns = buildWeekView(selected, items, today, selected)
    let dayItems = dayItemsOf(items, selected)
    let selectedLunar = lunarOf(selected)
    let currentSelectedId = ctx.store.selectedId.value()

    /* ------------------------------- 交互回调 ------------------------------- */
    let selectDate: (String) -> Unit = {key =>
        selectedState.value = key
        listScrollState.value = 0.0
        if (shouldAutoOpenPanel(panelState.value, ctx.width, collapsedState.value)) {
            panelState.value = true
        }
    }
    let stepSegment: (Int64) -> Unit = {direction =>
        if (modeState.value == 1) {
            selectedState.value = shiftDateKey(selectedState.value, direction * 7)
        } else {
            let next = shiftMonth(selectedDate.year, selectedDate.month, direction)
            let day = min(selectedDate.day, daysInMonth(next.year, next.month))
            selectDate(keyOf(next.year, next.month, day))
        }
        listScrollState.value = 0.0
    }
    let togglePanel: () -> Unit = {=>
        if (panelState.value) {
            panelState.value = false
            collapsedState.value = true
        } else {
            panelState.value = true
            collapsedState.value = false
        }
    }
    let openItem: (CalItem) -> Unit = {item =>
        ctx.store.select(item.id)
        ctx.navigate(routeForKind(item.kind))
    }
    let toggleDone: (String) -> Unit = {id => ctx.store.toggleDone(id)}
    let onCreate: (String) -> Unit = {title =>
        let trimmed = title.trimAscii()
        if (!trimmed.isEmpty()) {
            let gantt = GanttPatch()
            gantt.start = SetValue<?String>.Value(Some(selectedState.value))
            gantt.end = SetValue<?String>.Value(Some(selectedState.value))
            gantt.progress = SetValue<Float64>.Value(0.0)
            let gtd = GtdPatch()
            gtd.clarified = SetValue<Bool>.Value(true)
            ctx.store.createItem(NewItemInput(ItemKind.Action, trimmed, status: ItemStatus.Next, gantt: gantt,
                gtd: gtd))
            draftState.value = ""
            ctx.store.notify("已添加到 ${shortDateLabel(selectedState.value)}", tone: NoticeTone.Success)
        }
    }
    let openGantt: () -> Unit = {=>
        var target: ?CalItem = None
        for (item in dayItems) {
            match (currentSelectedId) {
                case Some(id) =>
                    if (id == item.id) {
                        target = Some(item)
                    }
                case None => ()
            }
        }
        if (target.isNone() && dayItems.size > 0) {
            target = Some(dayItems[0])
        }
        match (target) {
            case Some(item) => ctx.store.select(item.id)
            case None => ()
        }
        ctx.navigate("gantt")
    }

    /* ------------------------------- 文案 ------------------------------- */
    let rangeLabel = if (modeState.value == 1) {
        weekLabel(selected)
    } else {
        monthLabel(selectedDate.year, selectedDate.month)
    }
    let subtitle = match (selectedLunar) {
        case Some(lunar) => "${rangeLabel} · ${lunar.ganzhiYear}${lunar.zodiac}年 · 农历${lunar.monthName}"
        case None => "${rangeLabel} · 农历数据仅支持 1900–2100"
    }
    let dateLabel = fullDateLabel(selected)
    let lunarText = match (selectedLunar) {
        case Some(lunar) => lunarFullLabel(lunar)
        case None => "农历数据超出 1900–2100 支持范围"
    }
    let badges = ArrayList<PanelBadge>()
    match (selectedLunar) {
        case Some(lunar) =>
            match (lunar.festival) {
                case Some(festival) => badges.add(PanelBadge(festival, BadgeTone.Accent))
                case None => ()
            }
            match (lunar.solarTerm) {
                case Some(term) =>
                    let duplicate = match (lunar.festival) {
                        case Some(festival) => festival == term
                        case None => false
                    }
                    if (!duplicate) {
                        badges.add(PanelBadge(term, BadgeTone.Info))
                    }
                case None => ()
            }
        case None => ()
    }
    badges.add(PanelBadge("${dayItems.size.toString()} 项", BadgeTone.Neutral))

    /* ------------------------------- 页面 ------------------------------- */
    VStack(spacing: vp(LAYOUT_GAP)) {
        // `.page-header.cal-header`：左标题 / 右工具栏（flex-wrap，本实现固定单行）。
        HStack(spacing: vp(TOOLBAR_GAP)) {
            HeaderTitlesView(tk, "日历", subtitle).flex()
            HStack(spacing: vp(TOOLBAR_GAP)) {
                SegmentedView(tk, [SegmentedItem("月"), SegmentedItem("周")], modeState, size: ControlSize.Sm)
                    .height(vp(30.0))
                calNavTray(theme, tk, {=> stepSegment(-1)}, {=> selectDate(today)}, {=> stepSegment(1)})
                CalSelectView(tk, "${selectedDate.year.toString()}年", yearOptions(),
                    selectedDate.year.toString(), 1, openSelectState, yearScrollState, {value =>
                    let year = parseIntOr(value, selectedDate.year)
                    let day = minInt(selectedDate.day, daysInMonth(year, selectedDate.month))
                    selectDate(keyOf(year, selectedDate.month, day))
                }).width(vp(94.0)).height(vp(32.0))
                CalSelectView(tk, MONTH_NAMES_CN[selectedDate.month - 1], monthOptions(),
                    selectedDate.month.toString(), 2, openSelectState, monthScrollState, {value =>
                    let month = parseIntOr(value, selectedDate.month)
                    let day = minInt(selectedDate.day, daysInMonth(selectedDate.year, month))
                    selectDate(keyOf(selectedDate.year, month, day))
                }).width(vp(82.0)).height(vp(32.0))
            }.crossAxisAlignment(CrossAxisAlignment.Center).hug().height(vp(34.0))
        }.crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()

        HStack(spacing: vp(LAYOUT_GAP)) {
            VStack(spacing: vp(MAIN_GAP)) {
                if (modeState.value == 1) {
                    WeekViewWidget(tk, weekColumns, selected, currentSelectedId, selectDate, openItem).flex()
                } else {
                    MonthGridWidget(tk, rows, today, selected, selectDate, {=> togglePanel()}).flex()
                }
                HintStripView(tk, modeState.value == 0)
            }.flex()

            // `.cal-panel`：底板 + 内容（内容四周留 1px 边框宽）。
            ZStack {
                PanelBackdropView(tk)
                VStack(spacing: vp(0.0)) {
                    PanelHeadView(tk, dateLabel, lunarText, relativeDayLabel(selected, today), badges.toArray())
                    PanelListView(tk, dayItems, itemAreas, selected, currentSelectedId, listScrollState, draftState,
                        openItem, toggleDone).height(vp(listHeight))
                    HairlineView(tk.color.border)
                    HStack(spacing: vp(QUICK_GAP)) {
                        VStack(spacing: vp(0.0)) {
                            quickField(tk, draftState, onCreate)
                        }.flex()
                        Ui.button(theme, "添加", {=> onCreate(draftState.value)}, variant: ButtonVariant.Primary,
                            size: ControlSize.Sm, iconLeft: IconGlyph.Plus,
                            enabled: !draftState.value.trimAscii().isEmpty())
                    }.hug().width(vp(LAYOUT_PANEL_WIDTH - 2.0)).padding(QUICK_PAD).background(tk.color.surface2)
                    HStack(spacing: vp(TOOLBAR_GAP)) {
                        Ui.button(theme, "在甘特中查看", {=> openGantt()}, variant: ButtonVariant.Secondary,
                            size: ControlSize.Sm, iconLeft: IconGlyph.Timeline, block: true)
                    }.hug().width(vp(LAYOUT_PANEL_WIDTH - 2.0)).padding(QUICK_PAD, 0.0, QUICK_PAD, QUICK_PAD)
                        .background(tk.color.surface2, corners: Corners.bottom(GRID_RADIUS - 1.0))
                }.width(vp(LAYOUT_PANEL_WIDTH - 2.0)).height(vp(panelInnerHeight))
            }.width(LAYOUT_PANEL_WIDTH)
        }.fillWidth().flex()
    }.fillWidth().height(vp(pageHeight))
}

/** `.cal-nav`：`‹ 今天 ›` 的内凹托盘（padding 2px / border 1px / surface-2）。 */
func calNavTray(theme: Theme, tk: ThemeTokens, onPrev: () -> Unit, onToday: () -> Unit, onNext: () -> Unit): Unit {
    HStack(spacing: vp(0.0)) {
        Ui.iconButton(theme, IconGlyph.ChevronLeft, onPrev, size: ControlSize.Sm, tooltip: "上一段")
        Ui.button(theme, "今天", onToday, variant: ButtonVariant.Ghost, size: ControlSize.Sm)
        Ui.iconButton(theme, IconGlyph.ChevronRight, onNext, size: ControlSize.Sm, tooltip: "下一段")
    }.hug().padding(2.0).background(tk.color.surface2, tk.radius.md)
        .border(tk.color.border, width: tk.metrics.borderWidth, radius: tk.radius.md)
}

/** `.cal-quick .input`：`min-height: 30px; font-size: 12.5px`，Enter 提交到当天。 */
func quickField(tk: ThemeTokens, draft: State<String>, onCreate: (String) -> Unit): Unit {
    let field = TextField(draft, key: "calendar-quick-input")
    field.style(TextInputStyle(
        padding: LengthInsets(Length(10.0, LengthUnit.Vp), Length(7.0, LengthUnit.Vp)),
        textColor: tk.color.text,
        placeholderColor: tk.color.textFaint,
        cursorColor: tk.color.accent,
        surface: SurfaceStyle(tk.color.surface, border: tk.color.border, radius: tk.radius.md,
            borderWidth: tk.metrics.borderWidth),
        focusedSurface: SurfaceStyle(tk.color.surface, border: tk.color.accent, radius: tk.radius.md,
            borderWidth: tk.metrics.borderWidth)
    ))
    field.height(QUICK_INPUT_HEIGHT)
    field.onSubmit({value => onCreate(value)})
}
