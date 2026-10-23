package textura.views.okr

import std.collection.{ArrayList, HashMap}
import std.unicode.*
import std.convert.*
import cui.*
import textura.core.data.{AppStore, Item, ItemKind, ItemPatch, ItemPatchTarget, ItemStatus, Metric, MetricPatch,
    NewItemInput, NoticeTone, OkrPatch, SetValue, ViewContext, Workspace}
import textura.ui.*
import textura.views.okr.logic.{CivilDate, ConfidenceBucket, EMPTY_METRIC, METRIC_FIELDS, MetricDraft, MetricField,
    MetricProgressState, OkrMetric, OkrSummary, confidenceBucket, formatMetric, formatNumber, formatSchedule,
    jsNumberToString, metricFieldText, metricProgress, metricToDraft, metricToText, nextQuarter, pendingMetricPatch,
    quarterLabel, shiftQuarter, unitSuffix}

/*
 * OKR 视图（`src/modules/okr/OkrPage.tsx` 的 1:1 移植）。
 *
 * 页面结构：页头（标题 + 密度/视图分段 + 新建目标）→ 季度条 → 季度健康度 → 目标卡列表
 * （或表格 / 对齐大纲 / 空态）。几何全部取自 `src/modules/okr/okr.css`，关键处标注行号。
 *
 * 编辑链路：所有修改都写回 `ctx.store`（`updateItem(ItemPatch)` / `setMetric` /
 * `setConfidence` / `setOkrPeriod` / `createItem` / `createEdge` / `deleteEdge` /
 * `deleteItems` / `moveItem`），其它视图读同一个 `Workspace`，因此立即生效。
 */

/** 页面交互状态；全部用 `rememberState` 跨帧保留。 */
class OkrUiState {
    let view: State<Int64>
    let density: State<Int64>
    let objectiveOpen: State<Bool>
    let objectiveTitle: State<String>
    let objectiveNotes: State<String>
    let objectiveArea: State<String>
    let objectiveError: State<String>
    let quarterOpen: State<Bool>
    let quarterYear: State<Int64>
    let quarterIndex: State<Int64>
    let quarterMode: State<String>
    let quarterTarget: State<String>
    let linkOpen: State<Bool>
    let linkKr: State<String>
    let linkQuery: State<String>
    let linkSelected: State<Array<String>>
    /**
     * 已关联但被用户取消勾选的执行项（确认时删除对应的 `okr` 边）。
     * Web 版把已关联项禁用；本实现按用户要求允许取消，因此需要与「待关联」分开记。
     */
    let linkRemoved: State<Array<String>>
    /** 候选列表的滚动偏移（46vh 窗口）。 */
    let linkScroll: State<Float32>
    let linkFocus: FocusRequest
    let confirmObjective: State<String>
    let confirmKr: State<String>
    let statusKr: State<String>
    let focusTrack: State<String>
    let menuObjective: State<String>
    let menuOpen: State<Bool>
    let statusOpen: State<Bool>
    let confirmOpen: State<Bool>
    let collapsed: State<Array<String>>
    let expanded: State<Array<String>>
    let editTitle: State<String>
    let editFocus: State<Bool>
    /*
     * The inline editor used by the card canvas. A canvas declares its controls during layout,
     * where CUI registers no focus stop, so every text edit opens the shared `Ui.prompt`
     * instead of an inline `TextField` (docs/DEVICE-NOTES.md §16).
     */
    let promptOpen: State<Bool>
    let promptText: State<String>
    let promptKind: State<String>
    let promptTarget: State<String>
    let promptField: State<String>
    let promptError: State<String>
    let promptFocus: FocusRequest
    let fields: HashMap<String, State<String>>

    init() {
        this.view = rememberState<Int64>("okr-view") {0}
        this.density = rememberState<Int64>("okr-density") {1}
        this.objectiveOpen = rememberState<Bool>("okr-objective-open") {false}
        this.objectiveTitle = rememberState<String>("okr-objective-title") {""}
        this.objectiveNotes = rememberState<String>("okr-objective-notes") {""}
        this.objectiveArea = rememberState<String>("okr-objective-area") {""}
        this.objectiveError = rememberState<String>("okr-objective-error") {""}
        this.quarterOpen = rememberState<Bool>("okr-quarter-open") {false}
        this.quarterYear = rememberState<Int64>("okr-quarter-year") {2026}
        this.quarterIndex = rememberState<Int64>("okr-quarter-index") {1}
        this.quarterMode = rememberState<String>("okr-quarter-mode") {""}
        this.quarterTarget = rememberState<String>("okr-quarter-target") {""}
        this.linkOpen = rememberState<Bool>("okr-link-open") {false}
        this.linkKr = rememberState<String>("okr-link-kr") {""}
        this.linkQuery = rememberState<String>("okr-link-query") {""}
        this.linkSelected = rememberState<Array<String>>("okr-link-selected") {[]}
        this.linkRemoved = rememberState<Array<String>>("okr-link-removed") {[]}
        this.linkScroll = rememberState<Float32>("okr-link-scroll") {0.0}
        this.linkFocus = FocusRequest()
        this.confirmObjective = rememberState<String>("okr-confirm-objective") {""}
        this.confirmKr = rememberState<String>("okr-confirm-kr") {""}
        this.statusKr = rememberState<String>("okr-status-kr") {""}
        this.focusTrack = rememberState<String>("okr-focus-track") {""}
        this.menuObjective = rememberState<String>("okr-menu-objective") {""}
        this.menuOpen = rememberState<Bool>("okr-menu-open") {false}
        this.statusOpen = rememberState<Bool>("okr-status-open") {false}
        this.confirmOpen = rememberState<Bool>("okr-confirm-open") {false}
        this.collapsed = rememberState<Array<String>>("okr-collapsed") {[]}
        this.expanded = rememberState<Array<String>>("okr-expanded") {[]}
        this.editTitle = rememberState<String>("okr-edit-title") {""}
        this.editFocus = rememberState<Bool>("okr-edit-focus") {false}
        this.promptOpen = rememberState<Bool>("okr-prompt-open") {false}
        this.promptText = rememberState<String>("okr-prompt-text") {""}
        this.promptKind = rememberState<String>("okr-prompt-kind") {""}
        this.promptTarget = rememberState<String>("okr-prompt-target") {""}
        this.promptField = rememberState<String>("okr-prompt-field") {""}
        this.promptError = rememberState<String>("okr-prompt-error") {""}
        this.promptFocus = FocusRequest()
        this.fields = HashMap<String, State<String>>()
    }

    /** 文本草稿（首次创建时使用 store 的当前值）。 */
    func field(key: String, initial: String): State<String> {
        match (fields.get(key)) {
            case Some(state) => state
            case None =>
                let created = rememberState<String>("okr-field-${key}") {initial}
                fields[key] = created
                created
        }
    }

    func isDetailed(): Bool {
        density.value == 1
    }

    func hasIn(list: Array<String>, id: String): Bool {
        for (value in list) {
            if (value == id) {
                return true
            }
        }
        false
    }

    private func toggleIn(state: State<Array<String>>, id: String): Unit {
        let next = ArrayList<String>()
        var removed = false
        for (value in state.value) {
            if (value == id) {
                removed = true
            } else {
                next.add(value)
            }
        }
        if (!removed) {
            next.add(id)
        }
        state.value = next.toArray()
    }

    func toggleCollapsed(id: String): Unit {
        toggleIn(collapsed, id)
    }

    func toggleExpanded(id: String): Unit {
        toggleIn(expanded, id)
    }

    func toggleSelected(id: String): Unit {
        toggleIn(linkSelected, id)
    }
}

/** 每帧新建一份状态壳；`rememberState` 负责复用同一个 State。 */
func okrUiState(): OkrUiState {
    OkrUiState()
}

/** `.btn` 变体（`ui.css:35-103`）。 */
let OKR_BTN_PRIMARY: Int64 = 0
let OKR_BTN_SECONDARY: Int64 = 1
let OKR_BTN_GHOST: Int64 = 2
let OKR_BTN_DANGER: Int64 = 3

/** 视图切换（`OkrPage.tsx` 的 `VIEW_OPTIONS` 顺序）。 */
let OKR_VIEW_CARDS: Int64 = 0
let OKR_VIEW_TABLE: Int64 = 1
let OKR_VIEW_ALIGN: Int64 = 2

/** 把 `AppStore` 的修订号桥接成 CUI `State`：store 写入后重新构建视图。 */
class OkrStoreBridge {
    let store: AppStore
    let revision: State<Int64>

    init(store: AppStore, revision: State<Int64>) {
        this.store = store
        this.revision = revision
        let _ = store.state.subscribe {_ => revision.value = revision.value + 1}
    }
}

class OkrPage <: Widget {
    let ctxData: ViewContext
    let store: AppStore
    let tokens: ThemeTokens
    let theme: Theme
    let workspace: Workspace
    let data: OkrPageData
    let ui: OkrUiState

    private var canvas: ?PageCanvas = None
    private var contentHeight: Float32 = 0.0
    private var measured: Bool = false
    private var measuredWidth: Float32 = -1.0
    private var registeredIds = ArrayList<String>()

    init(ctx: ViewContext, ui: OkrUiState) {
        this.ctxData = ctx
        this.store = ctx.store
        this.tokens = if (ctx.theme == "dark") {
            ThemeTokens.dark()
        } else {
            ThemeTokens.light()
        }
        this.theme = this.tokens.theme()
        this.workspace = ctx.store.state.value()
        let uiState = ctx.store.ui.value()
        this.data = buildOkrPageData(workspace, uiState.okrPeriod, uiState.search, ctx.today)
        this.ui = ui
        primeFieldStates()
        registerFocusOrder()
        emit(this)
    }

    /**
     * 构造期（构建阶段）预建所有文本草稿 State：`rememberState` 只能在构建阶段调用，
     * 而输入框在 layout 阶段构造，因此先把 key 全部登记到 `OkrUiState.fields`。
     */
    private func primeFieldStates(): Unit {
        for (entry in data.entries) {
            let objectiveId = entry.item.id
            let _ = ui.field("title-${objectiveId}", entry.item.title)
            let _ = ui.field("addkr-${objectiveId}", "")
            for (kr in entry.krs) {
                primeKrFields(kr)
            }
        }
    }

    private func primeKrFields(kr: OkrKrEntry): Unit {
        let krId = kr.item.id
        let _ = ui.field("title-${krId}", kr.item.title)
        let _ = ui.field("owner-${krId}", kr.owner)
        let base = match (kr.metric) {
            case Some(value) => value
            case None => EMPTY_METRIC
        }
        for (field in METRIC_FIELDS) {
            let text = if (field == MetricField.UnitField) {
                base.unit
            } else {
                metricToText(metricFieldValue(field, base))
            }
            let _ = ui.field("metric-${krId}-${metricFieldText(field)}", text)
        }
    }

    // ---------------------------------------------------------------- 焦点环

    private func mark(id: String): Unit {
        let actual = focusableControlIdentity(id)
        registeredIds.add(actual)
    }

    /**
     * 构造期登记焦点（CUI 的 Tab 顺序来自构建阶段的 `focusableControlIdentity`）。
     * 本页控件都在 layout 阶段构造，因此在这里按视觉顺序登记相同的 id。
     */
    private func registerFocusOrder(): Unit {
        mark("okr-view-seg")
        if (ui.view.value == OKR_VIEW_CARDS) {
            mark("okr-density-seg")
        }
        mark("okr-new-objective")
        for (chip in data.chips) {
            mark("okr-chip-${chip.period}")
        }
        mark("okr-new-quarter")
        if (data.hasQuery()) {
            mark("okr-clear-filter")
        }
        if (data.entries.size == 0) {
            mark("okr-empty-new")
            return
        }
        if (ui.view.value == OKR_VIEW_TABLE) {
            for (entry in data.entries) {
                mark("okr-table-obj-${entry.item.id}")
                for (kr in entry.krs) {
                    mark("okr-table-kr-${kr.item.id}")
                }
            }
        } else if (ui.view.value == OKR_VIEW_ALIGN) {
            for (entry in data.entries) {
                mark("okr-align-obj-${entry.item.id}")
                for (kr in entry.krs) {
                    mark("okr-align-kr-${kr.item.id}")
                    for (exec in kr.execs) {
                        mark("okr-align-exec-${exec.item.id}")
                    }
                }
            }
        } else {
            for (entry in data.entries) {
                registerCardFocus(entry)
            }
        }
    }

    private func registerCardFocus(entry: OkrObjEntry): Unit {
        let objectiveId = entry.item.id
        mark("okr-more-${objectiveId}")
        mark("okr-title-${objectiveId}")
        mark("okr-conf-${objectiveId}")
        mark("okr-addkr-${objectiveId}")
        mark("okr-add-${objectiveId}")
        for (kr in entry.krs) {
            registerKrFocus(kr)
        }
    }

    private func registerKrFocus(kr: OkrKrEntry): Unit {
        let krId = kr.item.id
        for (field in METRIC_FIELDS) {
            mark("okr-field-${krId}-${metricFieldText(field)}")
        }
        mark("okr-title-${krId}")
        mark("okr-conf-${krId}")
        mark("okr-owner-${krId}")
        mark("okr-status-${krId}")
        mark("okr-link-${krId}")
        mark("okr-up-${krId}")
        mark("okr-down-${krId}")
        mark("okr-del-${krId}")
        for (exec in kr.execs) {
            mark("okr-exec-${exec.item.id}")
            mark("okr-unlink-${exec.item.id}")
        }
    }

    public func focusableIds(): Array<String> {
        registeredIds.toArray()
    }

    // ---------------------------------------------------------------- Widget

    /**
     * `.page.okr-page` 的高度是**内容高度的和**（行高全部来自 okr.css 的固定值），只有跑一遍布局
     * 才知道；而外层 `.shell-content` 的 `ScrollView` 会先 `child.measure(...)` 再
     * `child.layout(Rect(…, measured.h))`。
     *
     * 修复前的 `measure` 直接返回上一次布局缓存 `contentHeight`，新实例第一次被量时它是 0：
     * 换路由进入 OKR 那一帧量到 0 → VStack 只分到 0 高 → `layout` 仍会被调用（rect 高 0），
     * 但页面内容被父级裁掉，而且此后没有脏标记再触发重新测量，于是**永久空白**（首次启动能显示，
     * 是因为窗口尺寸变化额外引发了一次 measure→layout）。见 docs/DEVICE-NOTES.md §12。
     *
     * 因此这里在未知高度时先跑一遍「只算高度」的布局（`PageCanvas(measureOnly: true)`：
     * 相同的行/列公式，但不构造控件、不提交草稿、不写焦点状态），把真实高度交给父级；
     * 真正的 `layout` 仍按原路径执行一次，交互与像素都不变。
     */
    public func measure(ctx: UiContext, available: Size): Size {
        let pageW = min(OKR_PAGE_MAX_W, max(0.0, available.w))
        if (!measured || measuredWidth != pageW) {
            let probe = PageCanvas(tokens, theme, measureOnly: true)
            layoutPage(ctx, probe, Rect(0.0, 0.0, pageW, 1.0))
            measured = true
            measuredWidth = pageW
        }
        Size(pageW, contentHeight)
    }

    public func layout(ctx: UiContext, rect: Rect): Unit {
        let cv = PageCanvas(tokens, theme)
        layoutPage(ctx, cv, rect)
        canvas = Some(cv)
    }

    public func draw(ctx: UiContext): Unit {
        match (canvas) {
            case Some(cv) =>
                cv.draw(ctx)
                cv.drawChildren(ctx)
            case None => ()
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        let cv = match (canvas) {
            case Some(value) => value
            case None => return false
        }
        match (event) {
            case UiEvent.MouseMove(_, _) =>
                for (spot in cv.hotspots) {
                    claimHoverIfInside(ctx, event, spot.rect, spot.id, CursorShape.Interactive)
                }
                for (child in cv.children) {
                    let _ = child.handle(ctx, event)
                }
                false
            case UiEvent.MouseDown(pressButton, x, y) where isPrimaryPointerButton(pressButton) =>
                if (handleChildEvent(ctx, cv, event)) {
                    return true
                }
                var index = cv.hotspots.size - 1
                while (index >= 0) {
                    let spot = cv.hotspots[index]
                    if (spot.rect.contains(x, y)) {
                        ctx.focus(spot.id)
                        ctx.press(spot.id)
                        return true
                    }
                    index -= 1
                }
                false
            case UiEvent.MouseUp(_, x, y) =>
                var hit = false
                var index = cv.hotspots.size - 1
                while (index >= 0) {
                    let spot = cv.hotspots[index]
                    if (ctx.isPressed(spot.id)) {
                        ctx.clearPress()
                        if (spot.rect.contains(x, y)) {
                            spot.action()
                        }
                        hit = true
                        break
                    }
                    index -= 1
                }
                if (handleChildEvent(ctx, cv, event)) {
                    return true
                }
                hit
            case UiEvent.KeyDown(key, isRepeat) =>
                if (handlePaintedKey(ctx, key, isRepeat)) {
                    return true
                }
                handleChildEvent(ctx, cv, event)
            case _ => handleChildEvent(ctx, cv, event)
        }
    }

    private func handleChildEvent(ctx: UiContext, cv: PageCanvas, event: UiEvent): Bool {
        var index = cv.children.size - 1
        while (index >= 0) {
            if (cv.children[index].handle(ctx, event)) {
                return true
            }
            index -= 1
        }
        false
    }

    // ---------------------------------------------------------------- 布局

    private func layoutPage(ctx: UiContext, cv: PageCanvas, rect: Rect): Unit {
        let pageW = min(OKR_PAGE_MAX_W, max(0.0, rect.w))
        let x0 = rect.x + (rect.w - pageW) / 2.0
        if (!cv.measureOnly) {
            commitPendingEdits(ctx)
        }
        var y = rect.y
        y = layoutHeader(ctx, cv, x0, pageW, y)
        y += OKR_S4
        y = layoutPeriodBar(ctx, cv, x0, pageW, y)
        y += OKR_S4
        y = layoutHealth(ctx, cv, x0, pageW, y)
        y += OKR_S4
        if (data.hasQuery()) {
            y = layoutFilterNote(ctx, cv, x0, pageW, y)
            y += OKR_S4
        }
        if (data.entries.size == 0) {
            y = layoutEmptyState(this, ctx, cv, x0, pageW, y)
        } else {
            if (ui.view.value == OKR_VIEW_TABLE) {
                y = layoutTable(this, ctx, cv, x0, pageW, y)
            } else if (ui.view.value == OKR_VIEW_ALIGN) {
                y = layoutAlignment(this, ctx, cv, x0, pageW, y)
            } else {
                y = layoutCards(this, ctx, cv, x0, pageW, y)
            }
        }
        contentHeight = y - rect.y
        if (!cv.measureOnly) {
            ui.focusTrack.value = focusedField(ctx)
        }
    }

    // ---------------------------------------------------------------- 页头

    /** `.page-header`（h1 22px、p 13px，`okr.css:5-8` 把 gap 收紧到 --space-4）。 */
    private func layoutHeader(ctx: UiContext, cv: PageCanvas, x0: Float32, w: Float32, y: Float32): Float32 {
        let c = tokens.color
        let h1Line: Float32 = 22.0 * 1.5
        let pLine: Float32 = 13.0 * 1.5
        cv.text(ctx, x0, y + h1Line / 2.0, "OKR", 22.0, 650, c.text)
        let elapsed = jsNumberToString(data.summary.elapsedPercent)
        let subtitle = "用可量化的关键结果推进 ${quarterLabel(data.period)} · 时间已过 ${elapsed}%"
        cv.text(ctx, x0, y + h1Line + OKR_S1 + pLine / 2.0, subtitle, 13.0, 400, c.textMuted)
        var right = x0 + w
        let buttonW = buttonWidth(ctx, "新建目标", 1, Some(IconGlyph.Plus))
        paintButton(ctx, cv, "okr-new-objective", Rect(right - buttonW, y, buttonW, 34.0), "新建目标", OKR_BTN_PRIMARY, 1,
            Some(IconGlyph.Plus), true, {=> openObjectiveDialog()})
        right -= buttonW + OKR_S2
        let viewLabels = ["卡片", "表格", "对齐"]
        let viewW = segmentedWidth(ctx, viewLabels)
        paintSegmented(ctx, cv, "okr-view-seg", Rect(right - viewW, y + 2.0, viewW, 30.0), viewLabels, ui.view.value) {
            index => ui.view.value = index
        }
        right -= viewW + OKR_S2
        if (ui.view.value == OKR_VIEW_CARDS) {
            let densityLabels = ["紧凑", "详细"]
            let densityW = segmentedWidth(ctx, densityLabels)
            paintSegmented(ctx, cv, "okr-density-seg", Rect(right - densityW, y + 2.0, densityW, 30.0),
                densityLabels, ui.density.value) {index => ui.density.value = index}
        }
        y + h1Line + OKR_S1 + pLine
    }

    // ---------------------------------------------------------------- 季度条

    /** `.okr-periodbar` / `.okr-period-chip`（okr.css:34-105）。 */
    private func layoutPeriodBar(ctx: UiContext, cv: PageCanvas, x0: Float32, w: Float32, y: Float32): Float32 {
        let c = tokens.color
        let chipH: Float32 = 30.0
        let countH: Float32 = 17.0
        var x = x0
        for (chip in data.chips) {
            let active = chip.isActive
            let label = quarterLabel(chip.period)
            let labelW = okrTextW(ctx, label, 12.5, 550)
            let countText = "${chip.count}"
            let countW = max(18.0, okrTextW(ctx, countText, 10.5, 400) + 10.0)
            let nowLabel = "本季"
            let nowW: Float32 = if (chip.isCurrent) {
                7.0 + okrTextW(ctx, nowLabel, 10.0, 550)
            } else {
                0.0
            }
            var contentW = labelW + 6.0 + countW
            if (chip.isCurrent) {
                contentW += 6.0 + nowW
            }
            let chipW = contentW + 20.0 + 2.0
            let chipRect = Rect(x, y, chipW, chipH)
            let chipId = "okr-chip-${chip.period}"
            let hovered = ctx.isHovered(chipId)
            let ink = if (active) {
                c.accentInk
            } else if (hovered) {
                c.text
            } else {
                c.textMuted
            }
            cv.fill(chipRect, chipH / 2.0, if (active) {
                c.accentSoft
            } else {
                c.surface
            })
            cv.stroke(chipRect, chipH / 2.0, if (active) {
                tint(c.accent, 40.0)
            } else if (hovered) {
                c.borderStrong
            } else {
                c.border
            })
            let centerY = y + chipH / 2.0
            var cursor = x + 1.0 + 10.0
            cv.text(ctx, cursor, centerY, label, 12.5, 550, ink)
            cursor += labelW + 6.0
            let countRect = Rect(cursor, centerY - countH / 2.0, countW, countH)
            cv.fill(countRect, countH / 2.0, if (active) {
                tint(c.accent, 16.0)
            } else {
                c.surface2
            })
            cv.textCenter(ctx, countRect.centerX(), centerY, countText, 10.5, 400, if (active) {
                c.accentInk
            } else {
                c.textMuted
            })
            cursor += countW
            if (chip.isCurrent) {
                cv.vLine(cursor + 6.0, centerY - 5.0, centerY + 5.0, ink)
                cv.text(ctx, cursor + 7.0, centerY, nowLabel, 10.0, 550, ink)
            }
            let period = chip.period
            let store = this.store
            cv.addHotspot(chipId, chipRect, {=> store.setOkrPeriod(period)})
            cv.focusRingFor(chipId, chipRect, chipH / 2.0)
            x += chipW + OKR_S2
        }
        let newW = buttonWidth(ctx, "新建季度", 0, Some(IconGlyph.Plus))
        paintButton(ctx, cv, "okr-new-quarter", Rect(x0 + w - newW, y + 1.0, newW, 28.0), "新建季度", OKR_BTN_GHOST, 0,
            Some(IconGlyph.Plus), true, {=> openQuarterDialog("", "")})
        y + chipH
    }

    // ---------------------------------------------------------------- 健康度

    /** `.okr-health`（okr.css:123-217）。 */
    private func layoutHealth(ctx: UiContext, cv: PageCanvas, x0: Float32, w: Float32, y: Float32): Float32 {
        let c = tokens.color
        let statsH: Float32 = 20.0 * 1.1 + 1.0 + 11.0 * 1.5
        let sideH: Float32 = OKR_BADGE_H + 6.0 + 11.0 * 1.5
        let contentH = max(statsH, sideH)
        let cardH = OKR_S3 + contentH + OKR_S3 + 2.0
        let cardTop = cv.snapValue(y)
        let cardRect = Rect(x0, cardTop, w, cardH)
        cv.shadow(cardRect, OKR_R_MD)
        cv.fill(cardRect, OKR_R_MD, c.surface)
        cv.stroke(cardRect, OKR_R_MD, c.border)
        let contentTop = cardTop + 1.0 + OKR_S3
        let statsTop = contentTop + (contentH - statsH) / 2.0
        // .okr-health padding 16 → 统计列从卡片内边距之后开始；第一个 stat 自身 padding-left 4
        var statX = x0 + 1.0 + OKR_S4
        let values = [
            "${data.summary.objectives}",
            "${data.summary.keyResults}",
            "${Int64(roundPercent(data.summary.averageProgress))}%",
            "${data.summary.behind}"
        ]
        let labels = ["目标", "关键结果", "平均进度", "落后 KR"]
        let tones = [
            c.text,
            c.text,
            c.text,
            if (data.summary.behind > 0) {
                c.dangerInk
            } else {
                c.okInk
            }
        ]
        var index = 0
        while (index < 4) {
            let first = index == 0
            let padLeft: Float32 = if (first) {
                OKR_S1
            } else {
                OKR_S4
            }
            let borderW: Float32 = if (first) {
                0.0
            } else {
                1.0
            }
            let valueW = okrTextW(ctx, values[index], 20.0, 650, mono: true)
            let labelW = okrTextW(ctx, labels[index], 11.0, 400)
            let statW = max(72.0, padLeft + max(valueW, labelW) + OKR_S4 + borderW)
            if (!first) {
                cv.vLine(statX, contentTop, contentTop + contentH, c.border)
            }
            let valueX = statX + borderW + padLeft
            cv.text(ctx, valueX, statsTop + 22.0 / 2.0, values[index], 20.0, 650, tones[index], mono: true)
            cv.text(ctx, valueX, statsTop + 22.0 + 1.0 + 11.0 * 1.5 / 2.0, labels[index], 11.0, 400, c.textMuted)
            statX += statW
            index += 1
        }
        let sideRight = x0 + w - 1.0 - OKR_S4
        let b1 = "低 1–3 · ${data.summary.confidenceLow}"
        let b2 = "中 4–6 · ${data.summary.confidenceMid}"
        let b3 = "高 7–10 · ${data.summary.confidenceHigh}"
        let labelW = okrTextW(ctx, "信心分布", 11.0, 400)
        let rowW = labelW + 6.0 + badgeWidth(ctx, b1, true) + 6.0 + badgeWidth(ctx, b2, true) + 6.0 +
            badgeWidth(ctx, b3, true)
        let rowCenter = contentTop + OKR_BADGE_H / 2.0
        var cursor = sideRight - rowW
        cv.text(ctx, cursor, rowCenter, "信心分布", 11.0, 400, c.textMuted)
        cursor += labelW + 6.0
        cursor += cv.badge(ctx, cursor, contentTop, b1, BadgeTone.Danger, dot: true) + 6.0
        cursor += cv.badge(ctx, cursor, contentTop, b2, BadgeTone.Warn, dot: true) + 6.0
        cursor += cv.badge(ctx, cursor, contentTop, b3, BadgeTone.Ok, dot: true)
        let timeW = min(300.0, w)
        let timeCenter = contentTop + OKR_BADGE_H + 6.0 + 11.0 * 1.5 / 2.0
        let timeLeft = sideRight - timeW
        let timeLabel = "季度时间进度"
        let timeLabelW = okrTextW(ctx, timeLabel, 11.0, 400)
        cv.text(ctx, timeLeft, timeCenter, timeLabel, 11.0, 400, c.textMuted)
        let pctText = "${jsNumberToString(data.summary.elapsedPercent)}%"
        let pctW = max(34.0, okrTextW(ctx, pctText, 11.0, 400, mono: true))
        let barLeft = timeLeft + timeLabelW + OKR_S2
        let barRight = sideRight - pctW - OKR_S2
        cv.progress(ctx, Rect(barLeft, timeCenter - 2.5, max(0.0, barRight - barLeft), 5.0),
            Float32(data.summary.elapsedPercent), ProgressTone.Info, ControlSize.Sm)
        cv.textRight(ctx, sideRight, timeCenter, pctText, 11.0, 400, c.textMuted, mono: true)
        _ = cursor
        cardTop + cardH
    }

    /** `.okr-filter-note`（okr.css:888-894）。 */
    private func layoutFilterNote(ctx: UiContext, cv: PageCanvas, x0: Float32, w: Float32, y: Float32): Float32 {
        let c = tokens.color
        let rowH: Float32 = 18.0
        let centerY = y + rowH / 2.0
        cv.icon(Rect(x0, centerY - 7.0, 14.0, 14.0), IconGlyph.Search, c.textMuted)
        let text = "筛选「${data.search.trim()}」· ${data.entries.size} 个目标"
        cv.text(ctx, x0 + 14.0 + OKR_S2, centerY, text, 12.0, 400, c.textMuted)
        let buttonW = buttonWidth(ctx, "清除筛选", 0, Option<IconGlyph>.None)
        paintButton(ctx, cv, "okr-clear-filter", Rect(x0 + w - buttonW, y, buttonW, 28.0), "清除筛选", OKR_BTN_GHOST,
            0, Option<IconGlyph>.None, true, {=> store.setSearch("")})
        y + rowH
    }

    // ---------------------------------------------------------------- 按钮 / 分段 / 刻度

    /** `.btn--sm { height: 28; padding: 0 10; font-size 12.5; icon 14 }`
     *  `.btn--md { height: 34; padding: 0 14; font-size 13.5; icon 16 }`（ui.css:19-29）。 */
    func buttonMetrics(size: Int64): (Float32, Float32, Float32, Float32) {
        if (size == 0) {
            (28.0, 10.0, 12.5, 14.0)
        } else {
            (34.0, 14.0, 13.5, 16.0)
        }
    }

    func buttonWidth(ctx: UiContext, label: String, size: Int64, glyph: ?IconGlyph): Float32 {
        let (_, padH, fontSize, iconSide) = buttonMetrics(size)
        var content = okrTextW(ctx, label, fontSize, 550)
        match (glyph) {
            case Some(_) => content += (if (content > 0.0) {
                OKR_S2
            } else {
                0.0
            }) + iconSide
            case None => ()
        }
        content + padH * 2.0 + 2.0
    }

    /** `.btn`（ui.css:5-113），几何与 ui-kit 的 ButtonView 一致。 */
    func paintButton(ctx: UiContext, cv: PageCanvas, id: String, rect: Rect, label: String, variant: Int64,
        size: Int64, glyph: ?IconGlyph, enabled: Bool, action: () -> Unit): Unit {
        let c = tokens.color
        let (_, _, fontSize, iconSide) = buttonMetrics(size)
        let hovered = enabled && ctx.isHovered(id)
        let pressed = enabled && ctx.isPressed(id)
        var fill = Color.rgba(0, 0, 0, 0)
        var border = Color.rgba(0, 0, 0, 0)
        var ink = c.text
        var elevated = false
        if (variant == OKR_BTN_PRIMARY) {
            fill = if (pressed) {
                c.accentStrongActive
            } else if (hovered) {
                c.accentStrongHover
            } else {
                c.accentStrong
            }
            border = fill
            ink = c.textOnStrong
            elevated = true
        } else if (variant == OKR_BTN_SECONDARY) {
            fill = if (hovered || pressed) {
                c.surface2
            } else {
                c.surface
            }
            border = if (hovered || pressed) {
                c.borderStrong
            } else {
                c.border
            }
            elevated = true
        } else if (variant == OKR_BTN_GHOST) {
            fill = if (hovered || pressed) {
                c.surface2
            } else {
                Color.rgba(0, 0, 0, 0)
            }
            ink = if (hovered || pressed) {
                c.text
            } else {
                c.textMuted
            }
        } else {
            fill = if (pressed) {
                c.dangerStrongActive
            } else if (hovered) {
                c.dangerStrongHover
            } else {
                c.dangerStrong
            }
            border = fill
            ink = c.textOnStrong
        }
        if (!enabled) {
            ink = withOpacity(c.textMuted, 0.55)
            fill = withOpacity(fill, 0.55)
            border = withOpacity(border, 0.55)
        }
        if (elevated) {
            cv.shadow(rect, OKR_R_MD)
        }
        cv.fill(rect, OKR_R_MD, fill)
        cv.stroke(rect, OKR_R_MD, border)
        let centerY = rect.centerY()
        var contentW = okrTextW(ctx, label, fontSize, 550)
        match (glyph) {
            case Some(_) => contentW += (if (contentW > 0.0) {
                OKR_S2
            } else {
                0.0
            }) + iconSide
            case None => ()
        }
        var x = rect.centerX() - contentW / 2.0
        match (glyph) {
            case Some(value) =>
                cv.icon(Rect(x, centerY - iconSide / 2.0, iconSide, iconSide), value, ink)
                x += iconSide + OKR_S2
            case None => ()
        }
        cv.text(ctx, x, centerY, label, fontSize, 550, ink)
        if (enabled) {
            cv.focusRingFor(id, rect, OKR_R_MD)
            cv.addHotspot(id, rect, action)
        }
    }

    /** `.icon-btn--ghost|danger`（ui.css:116-158），26×26。 */
    func paintIconButton(ctx: UiContext, cv: PageCanvas, id: String, rect: Rect, glyph: IconGlyph,
        danger: Bool, enabled: Bool, action: () -> Unit): Unit {
        let c = tokens.color
        let hovered = enabled && ctx.isHovered(id)
        let pressed = enabled && ctx.isPressed(id)
        var ink = if (danger) {
            c.danger
        } else {
            c.textMuted
        }
        if (hovered || pressed) {
            if (danger) {
                cv.fill(rect, OKR_R_MD, tint(c.danger, 12.0))
                ink = if (pressed) {
                    c.dangerStrongActive
                } else {
                    c.dangerStrong
                }
            } else {
                cv.fill(rect, OKR_R_MD, c.surface2)
                ink = c.text
            }
        }
        if (!enabled) {
            ink = withOpacity(ink, 0.4)
        }
        let side = min(min(rect.w, rect.h), 16.0)
        cv.icon(Rect(rect.centerX() - side / 2.0, rect.centerY() - side / 2.0, side, side), glyph, ink)
        if (enabled) {
            cv.focusRingFor(id, rect, OKR_R_MD)
            cv.addHotspot(id, rect, action)
        }
    }

    /** `.segmented`（ui.css:405-448）：2px 凹槽 + surface 药丸。 */
    func segmentedWidth(ctx: UiContext, labels: Array<String>): Float32 {
        var width: Float32 = 0.0
        var index = 0
        for (label in labels) {
            if (index > 0) {
                width += 2.0
            }
            width += okrTextW(ctx, label, 12.0, 550) + 16.0
            index += 1
        }
        width + 4.0 + 2.0
    }

    func paintSegmented(ctx: UiContext, cv: PageCanvas, id: String, rect: Rect, labels: Array<String>,
        selected: Int64, onSelect: (Int64) -> Unit): Unit {
        let c = tokens.color
        cv.fill(rect, OKR_R_MD, c.surface2)
        cv.stroke(rect, OKR_R_MD, c.border)
        var x = rect.x + 1.0 + 2.0
        let itemH: Float32 = 24.0
        let itemY = rect.centerY() - itemH / 2.0
        var index = 0
        for (label in labels) {
            let width = okrTextW(ctx, label, 12.0, 550) + 16.0
            let itemRect = Rect(x, itemY, width, itemH)
            let itemId = "${id}-${index}"
            let hovered = ctx.isHovered(itemId)
            if (index == selected) {
                cv.fill(itemRect, OKR_R_MD - 2.0, c.surface)
            }
            let ink = if (index == selected || hovered) {
                c.text
            } else {
                c.textMuted
            }
            cv.textCenter(ctx, itemRect.centerX(), itemRect.centerY(), label, 12.0, 550, ink)
            let target = index
            cv.addHotspot(itemId, itemRect, {=> onSelect(target)})
            x += width + 2.0
            index += 1
        }
        cv.focusRingFor(id, rect, OKR_R_MD)
    }

    /** `.okr-conf`（okr.css:534-595）：10 格单选。 */
    func paintConfidenceScale(ctx: UiContext, cv: PageCanvas, itemId: String, rect: Rect, value: Int64,
        onChange: (Int64) -> Unit): Unit {
        let c = tokens.color
        let id = "okr-conf-${itemId}"
        let active = clampConfidence(value)
        cv.fill(rect, OKR_R_MD, c.surface2)
        cv.stroke(rect, OKR_R_MD, c.border)
        let cellW: Float32 = 19.0
        let cellH: Float32 = 22.0
        let cellY = rect.centerY() - cellH / 2.0
        var x = rect.x + 1.0 + 2.0
        var score: Int64 = 1
        while (score <= 10) {
            let cellRect = Rect(x, cellY, cellW, cellH)
            let cellId = "${id}-${score}"
            let hovered = ctx.isHovered(cellId)
            if (score == active) {
                cv.fill(cellRect, 3.0, confidenceFill(score))
                cv.stroke(cellRect, 3.0, c.textOnStrong)
                cv.textCenter(ctx, cellRect.centerX(), cellRect.centerY(), "${score}", 10.5, 700, c.textOnStrong)
            } else {
                if (hovered) {
                    cv.fill(cellRect, 3.0, c.surface)
                }
                cv.textCenter(ctx, cellRect.centerX(), cellRect.centerY(), "${score}", 10.5, 400, if (hovered) {
                    c.text
                } else {
                    c.textMuted
                })
            }
            let picked = score
            cv.addHotspot(cellId, cellRect, {=> onChange(picked)})
            x += cellW + 1.0
            score += 1
        }
        cv.focusRingFor(id, rect, OKR_R_MD)
    }

    func confidenceFill(score: Int64): Color {
        let c = tokens.color
        match (confidenceBucket(Float64(score))) {
            case ConfidenceBucket.Low => c.dangerStrong
            case ConfidenceBucket.Mid => if (tokens.isDark) {
                c.bg.lerp(c.warn, 0.55)
            } else {
                c.warnInk
            }
            case ConfidenceBucket.High => if (tokens.isDark) {
                c.bg.lerp(c.ok, 0.55)
            } else {
                c.okInk
            }
        }
    }

    func badgeWidth(ctx: UiContext, text: String, dot: Bool): Float32 {
        var width = okrTextW(ctx, text, 11.0, 550) + OKR_BADGE_CHROME
        if (dot) {
            width += 10.0
        }
        width
    }

    // ---------------------------------------------------------------- 键盘

    private func handlePaintedKey(ctx: UiContext, key: Key, isRepeat: Bool): Bool {
        if (isRepeat) {
            return false
        }
        for (chip in data.chips) {
            if (ctx.hasFocus("okr-chip-${chip.period}")) {
                match (key) {
                    case Key.Left | Key.Up =>
                        store.setOkrPeriod(shiftQuarter(chip.period, -1))
                        return true
                    case Key.Right | Key.Down =>
                        store.setOkrPeriod(shiftQuarter(chip.period, 1))
                        return true
                    case Key.Enter | Key.Space =>
                        store.setOkrPeriod(chip.period)
                        return true
                    case _ => ()
                }
            }
        }
        for (entry in data.entries) {
            if (confidenceKey(ctx, key, entry.item.id, entry.confidence)) {
                return true
            }
            for (kr in entry.krs) {
                if (confidenceKey(ctx, key, kr.item.id, kr.confidence)) {
                    return true
                }
            }
        }
        false
    }

    private func confidenceKey(ctx: UiContext, key: Key, itemId: String, value: Int64): Bool {
        if (!ctx.hasFocus("okr-conf-${itemId}")) {
            return false
        }
        var next = value
        match (key) {
            case Key.Left | Key.Down => next = value - 1
            case Key.Right | Key.Up => next = value + 1
            case Key.Home => next = 1
            case Key.End => next = 10
            case _ => return false
        }
        store.setConfidence(itemId, clampConfidence(next))
        true
    }

    // ---------------------------------------------------------------- 编辑落库

    private func focusedField(ctx: UiContext): String {
        for (entry in data.entries) {
            if (ctx.hasFocus("okr-title-${entry.item.id}")) {
                return "okr-title-${entry.item.id}"
            }
            if (ctx.hasFocus("okr-addkr-${entry.item.id}")) {
                return "okr-addkr-${entry.item.id}"
            }
            for (kr in entry.krs) {
                let krId = kr.item.id
                if (ctx.hasFocus("okr-title-${krId}") || ctx.hasFocus("okr-owner-${krId}")) {
                    return if (ctx.hasFocus("okr-title-${krId}")) {
                        "okr-title-${krId}"
                    } else {
                        "okr-owner-${krId}"
                    }
                }
                for (field in METRIC_FIELDS) {
                    let id = "okr-field-${krId}-${metricFieldText(field)}"
                    if (ctx.hasFocus(id)) {
                        return id
                    }
                }
            }
        }
        ""
    }

    /**
     * 草稿 → store。失焦（上一帧还聚焦、本帧已失焦）时提交；聚焦期间保留用户输入；
     * 其余情况把 store 的值同步回草稿，撤销或其它视图的修改因此能反映进来。
     */
    private func commitPendingEdits(ctx: UiContext): Unit {
        let previous = ui.focusTrack.value
        for (entry in data.entries) {
            for (kr in entry.krs) {
                commitKrEdits(ctx, kr, previous)
            }
        }
        if (!ui.editTitle.value.isEmpty()) {
            let editing = ui.editTitle.value
            if (ctx.hasFocus(editing)) {
                ui.editFocus.value = true
            } else if (ui.editFocus.value) {
                commitTitle(editing, previous)
                ui.editTitle.value = ""
                ui.editFocus.value = false
            }
        }
    }

    /** 行内标题（`EditableTitle.tsx`）：只有处于编辑态时才存在输入框。 */
    private func commitTitle(id: String, previous: String): Unit {
        _ = previous
        let state = ui.field("title-${id}", "")
        let draft = state.value.trim()
        if (draft.isEmpty()) {
            return
        }
        store.updateItem(id, ItemPatch().withTitle(draft))
    }

    private func commitKrEdits(ctx: UiContext, kr: OkrKrEntry, previous: String): Unit {
        let krId = kr.item.id
        let ownerId = "okr-owner-${krId}"
        let ownerState = ui.field("owner-${krId}", kr.owner)
        if (ctx.hasFocus(ownerId)) {
            // 聚焦时不覆盖草稿
        } else if (previous == ownerId) {
            let draft = ownerState.value.trim()
            if (draft != kr.owner) {
                commitOwner(krId, draft)
            }
            ownerState.value = draft
        } else if (ownerState.value != kr.owner) {
            ownerState.value = kr.owner
        }
        let base = match (kr.metric) {
            case Some(value) => value
            case None => EMPTY_METRIC
        }
        var editing = false
        for (field in METRIC_FIELDS) {
            if (ctx.hasFocus("okr-field-${krId}-${metricFieldText(field)}")) {
                editing = true
            }
        }
        if (editing) {
            return
        }
        let draft = MetricDraft(
            start: ui.field("metric-${krId}-start", metricToText(base.start)).value,
            current: ui.field("metric-${krId}-current", metricToText(base.current)).value,
            target: ui.field("metric-${krId}-target", metricToText(base.target)).value,
            unit: ui.field("metric-${krId}-unit", base.unit).value
        )
        if (previous.startsWith("okr-field-${krId}-")) {
            match (pendingMetricPatch(kr.metric, draft, metricToDraft(base))) {
                case Some(decision) =>
                    store.setMetric(krId, decision.metric.start, decision.metric.target, decision.metric.current,
                        decision.metric.unit)
                    syncMetricDrafts(krId, decision.metric)
                case None => syncMetricDrafts(krId, base)
            }
        } else {
            syncMetricDrafts(krId, base)
        }
    }

    private func syncMetricDrafts(krId: String, metric: OkrMetric): Unit {
        setField("metric-${krId}-start", metricToText(metric.start))
        setField("metric-${krId}-current", metricToText(metric.current))
        setField("metric-${krId}-target", metricToText(metric.target))
        setField("metric-${krId}-unit", metric.unit)
    }

    private func setField(key: String, value: String): Unit {
        let state = ui.field(key, value)
        if (state.value != value) {
            state.value = value
        }
    }

    private func commitOwner(krId: String, owner: String): Unit {
        let patch = ItemPatch()
        let okr = OkrPatch()
        let ownerValue: ?String = if (owner.isEmpty()) {
            None
        } else {
            Some(owner)
        }
        okr.krOwner = SetValue<?String>.Value(ownerValue)
        patch.okr = Some(okr)
        store.updateItem(krId, patch)
    }

    // ---------------------------------------------------------------- 动作

    func openObjectiveDialog(): Unit {
        ui.objectiveTitle.value = ""
        ui.objectiveNotes.value = ""
        ui.objectiveArea.value = ""
        ui.objectiveError.value = ""
        ui.objectiveOpen.value = true
    }

    func openQuarterDialog(mode: String, objectiveId: String): Unit {
        let parts = parsePeriodParts(nextQuarter(data.period))
        ui.quarterYear.value = parts[0]
        ui.quarterIndex.value = parts[1]
        ui.quarterMode.value = mode
        ui.quarterTarget.value = objectiveId
        ui.quarterOpen.value = true
    }

    func createKeyResult(entry: OkrObjEntry, title: String): Unit {
        let trimmed = title.trim()
        if (trimmed.isEmpty()) {
            return
        }
        let created = store.createItem(
            NewItemInput(
                ItemKind.KeyResult,
                trimmed,
                status: Some(ItemStatus.Active),
                parentId: Some(entry.item.id),
                areaId: entry.item.areaId,
                okr: okrBlock(itemPeriod(entry.item, data.period), 5)
            )
        )
        setField("addkr-${entry.item.id}", "")
        store.select(created.id)
    }

    func addKeyResult(objectiveId: String, title: String): Unit {
        if (title.trim().isEmpty()) {
            return
        }
        for (entry in data.entries) {
            if (entry.item.id == objectiveId) {
                createKeyResult(entry, title)
                return
            }
        }
    }

    func moveObjective(entry: OkrObjEntry, period: String): Unit {
        let patches = ArrayList<ItemPatchTarget>()
        patches.add(ItemPatchTarget(entry.item.id, patchPeriod(period)))
        for (kr in entry.krs) {
            patches.add(ItemPatchTarget(kr.item.id, patchPeriod(period)))
        }
        store.updateItems(patches.toArray())
        store.setOkrPeriod(period)
        store.notify("目标已移动到 ${quarterLabel(period)}", tone: NoticeTone.Success)
    }

    func copyObjective(entry: OkrObjEntry, period: String): Unit {
        let copy = store.createItem(
            NewItemInput(
                ItemKind.Objective,
                entry.item.title,
                notes: entry.item.notes,
                status: Some(ItemStatus.Active),
                tags: entry.item.tags,
                areaId: entry.item.areaId,
                okr: okrBlock(period, entry.confidence)
            )
        )
        for (kr in entry.krs) {
            let metric: ?Metric = match (kr.metric) {
                case Some(value) => Some(Metric(value.start, value.target, value.start, value.unit))
                case None => None
            }
            let _ = store.createItem(
                NewItemInput(
                    ItemKind.KeyResult,
                    kr.item.title,
                    notes: kr.item.notes,
                    status: Some(kr.item.status),
                    parentId: Some(copy.id),
                    tags: kr.item.tags,
                    areaId: kr.item.areaId,
                    okr: okrBlock(period, kr.confidence, metric: metric, owner: if (kr.owner.isEmpty()) {
                        None
                    } else {
                        Some(kr.owner)
                    })
                )
            )
        }
        store.setOkrPeriod(period)
        store.select(copy.id)
        store.notify("已复制为新季度目标：${quarterLabel(period)}", tone: NoticeTone.Success)
    }

    func okrBlock(period: String, confidence: Int64, metric!: ?Metric = None,
        owner!: ?String = None): OkrPatch {
        let okr = OkrPatch()
        okr.period = SetValue<String>.Value(period)
        okr.confidence = SetValue<Int64>.Value(clampConfidence(confidence))
        match (metric) {
            case Some(value) =>
                let patch = MetricPatch()
                patch.start = SetValue<Float64>.Value(value.start)
                patch.target = SetValue<Float64>.Value(value.target)
                patch.current = SetValue<Float64>.Value(value.current)
                patch.unit = SetValue<String>.Value(value.unit)
                okr.metric = Some(patch)
            case None => ()
        }
        match (owner) {
            case Some(value) => okr.krOwner = SetValue<?String>.Value(Some(value))
            case None => ()
        }
        okr
    }

    func patchPeriod(period: String): ItemPatch {
        let patch = ItemPatch()
        let okr = OkrPatch()
        okr.period = SetValue<String>.Value(period)
        patch.okr = Some(okr)
        patch
    }
}

/** `Item.okr.period`，缺省用页面周期。 */
func itemPeriod(item: Item, fallback: String): String {
    match (item.okr) {
        case Some(okr) => if (okr.period.isEmpty()) {
            fallback
        } else {
            okr.period
        }
        case None => fallback
    }
}

/** `YYYY-Qn` → [year, quarter]。 */
func parsePeriodParts(period: String): Array<Int64> {
    let parts = period.split("-Q")
    if (parts.size == 2) {
        let year = match (Int64.tryParse(parts[0])) {
            case Some(value) => value
            case None => Int64(2026)
        }
        let quarter = match (Int64.tryParse(parts[1])) {
            case Some(value) => value
            case None => Int64(1)
        }
        return [year, min(max(quarter, 1), 4)]
    }
    [2026, 1]
}

/** `YYYY-Qn` ← [year, quarter]。 */
func periodFromParts(year: Int64, quarter: Int64): String {
    "${year}-Q${min(max(quarter, 1), 4)}"
}
