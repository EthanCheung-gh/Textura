package textura.views.sop

import std.collection.*
import std.deriving.*
import cui.*
import textura.core.data.*
import textura.ui.*
import textura.views.sop.logic as lg

/*
 * Shared numbers and per-frame view model for the SOP page.
 *
 * Every constant below is transcribed from `src/modules/sop/sop.css` (line numbers
 * in the comments) or from `src/styles/{tokens,shell}.css`; the canvas numbers come
 * from `textura.views.sop.logic` (SOP-NODE-* / layout / fit) so the view never
 * re-implements the dagre layout or the readable-fit policy.
 */

/** `--space-*` values are read from `ThemeTokens.space`; these are the raw CSS px of sop.css. */
let SOP_PAGE_PAD: Float32 = 24.0 // .shell-content { padding: var(--space-5) } (shell.css:259)
let SOP_HEADER_GAP: Float32 = 4.0 // .page-header-titles { gap: var(--space-1) } (shell.css:277)
let SOP_PAGE_GAP: Float32 = 16.0 // .page.sop-page { gap: var(--space-4) } (sop.css:9)
let SOP_BODY_GAP: Float32 = 16.0 // .sop-body { gap: var(--space-4) } (sop.css:23)
let SOP_LIST_W: Float32 = 272.0 // grid-template-columns: 272px … (sop.css:22)
let SOP_SIDE_W: Float32 = 320.0 // grid-template-columns: … 320px (sop.css:22)
let SOP_RADIUS_PANEL: Float32 = 14.0 // --radius-lg
let SOP_RADIUS_CTRL: Float32 = 8.0 // --radius-md
let SOP_BORDER: Float32 = 1.0 // border: 1px everywhere

/** Header: h1 22px/1.5 (shell.css:283, base.css:41) + p 13px/1.5 (shell.css:287). */
let SOP_H1_SIZE: Float32 = 22.0
let SOP_H1_LINE: Float32 = 33.0
let SOP_SUB_SIZE: Float32 = 13.0
let SOP_SUB_LINE: Float32 = 19.5

/** `.sop-list-head { height: 44px; padding: 0 var(--space-2) 0 var(--space-4) }` (sop.css:43). */
let SOP_LIST_HEAD_H: Float32 = 44.0  // border-box: includes the 1px bottom border
/** `.sop-list-foot { padding: var(--space-2) var(--space-4) }` (sop.css:211). */
let SOP_LIST_FOOT_H: Float32 = 34.0
/** `.sop-list-scroll { padding: var(--space-2) }` (sop.css:89). */
let SOP_LIST_PAD: Float32 = 8.0
/** `.sop-list-main { padding: 7px var(--space-2) }` (sop.css:127). */
let SOP_ROW_PAD_Y: Float32 = 7.0
let SOP_ROW_PAD_X: Float32 = 8.0
let SOP_ROW_GAP: Float32 = 2.0 // .sop-list-items { gap: 2px } (sop.css:96)
/** `.sop-list-title { font-size: 13px; line-height: 1.3 }` (sop.css:162). */
let SOP_ROW_TITLE_SIZE: Float32 = 13.0
let SOP_ROW_TITLE_LINE: Float32 = 16.9
/** `.sop-list-meta { font-size: 11px }` (sop.css:175). */
let SOP_ROW_META_SIZE: Float32 = 11.0
let SOP_ROW_META_LINE: Float32 = 16.5

/** `.sop-toolbar { padding: 6px var(--space-2) }` (sop.css:248); buttons are `.btn--sm`. */
let SOP_TOOLBAR_PAD_Y: Float32 = 6.0
let SOP_TOOLBAR_PAD_X: Float32 = 8.0
let SOP_BTN_SM_H: Float32 = 28.0 // .btn--sm { height: 28px } (ui.css:19)
let SOP_BTN_SM_PAD: Float32 = 10.0 // .btn--sm { padding: 0 10px }
let SOP_BTN_SM_FONT: Float32 = 12.5 // .btn--sm { font-size: 12.5px }
let SOP_ICON_SM: Float32 = 26.0 // .icon-btn--sm { 26x26 } (ui.css:120)
let SOP_TOOLBAR_GAP: Float32 = 8.0 // .sop-toolbar { gap: var(--space-2) }
let SOP_TOOLBAR_GROUP_GAP: Float32 = 2.0 // .sop-toolbar-group { gap: 2px }

/** `.sop-node-surface { min-height: 56px }` — the DOM height React Flow reports (sop.css:363). */
let SOP_NODE_CSS_HEIGHT: Float64 = 56.0

/** `.sop-node*` (sop.css:353-556); geometry beyond width/height comes from the node surface box. */
let SOP_NODE_RADIUS: Float32 = 8.0 // .sop-node-surface { border-radius: var(--radius-md) }
let SOP_NODE_PAD_X: Float32 = 10.0 // padding: 8px 10px
let SOP_NODE_PAD_Y: Float32 = 8.0
let SOP_NODE_TITLE_SIZE: Float32 = 13.0 // .sop-node-title { font-size: 13px }
let SOP_NODE_TITLE_LINE: Float32 = 17.55 // line-height: 1.35
let SOP_NODE_META_SIZE: Float32 = 10.5 // .sop-node-meta { font-size: 10.5px }
let SOP_NODE_META_LINE: Float32 = 13.65 // line-height: 1.3
let SOP_NODE_INNER_GAP: Float32 = 2.0 // .sop-node-surface { gap: 2px }
let SOP_NODE_HANDLE: Float32 = 9.0 // .sop-node-handle { 9x9 }
let SOP_EDGE_W: Float32 = 1.5 // .react-flow__edge-path { stroke-width: 1.5 }
let SOP_EDGE_LABEL_SIZE: Float32 = 11.0 // .react-flow__edge-text { font-size: 11px }
let SOP_ARROW: Float32 = 16.0 // FLOW_EDGE_MARKER { width: 16, height: 16 }
let SOP_ARROW_HALF: Float32 = 4.0 // ArrowClosed marker: 45deg closed arrow (16*0.25 inset bottom)

/** `.sop-inspector-*` (sop.css:693-842). */
let SOP_INSP_HEAD_PAD_Y: Float32 = 12.0 // padding: var(--space-3) var(--space-4)
let SOP_INSP_HEAD_PAD_X: Float32 = 16.0
let SOP_INSP_EYEBROW_SIZE: Float32 = 10.5 // .sop-inspector-eyebrow { font-size: 10.5px }
let SOP_INSP_EYEBROW_LINE: Float32 = 15.75
let SOP_INSP_TITLE_SIZE: Float32 = 14.0 // .sop-inspector-title { font-size: 14px }
let SOP_INSP_TITLE_LINE: Float32 = 18.9 // line-height: 1.35
let SOP_INSP_BODY_PAD_TOP: Float32 = 12.0 // padding: var(--space-3) var(--space-4) var(--space-4)
let SOP_INSP_BODY_PAD_X: Float32 = 16.0
let SOP_INSP_BODY_PAD_BOTTOM: Float32 = 16.0
let SOP_INSP_GAP: Float32 = 12.0 // flex column gap: var(--space-3)
let SOP_FIELD_LABEL_SIZE: Float32 = 12.0 // .field-label { font-size: 12px }
let SOP_FIELD_LABEL_LINE: Float32 = 18.0
let SOP_FIELD_GAP: Float32 = 6.0 // .field { gap: 6px }
// .input { min-height: 34px; padding: 7px 10px; font-size: 13.5px }: the browser border box
// is 7+7+13.5*1.5+2 = 36.25px, which is what the reference screenshot shows.
let SOP_INPUT_H: Float32 = 36.25
let SOP_INPUT_PAD_X: Float32 = 10.0 // padding: 7px 10px
let SOP_INPUT_FONT: Float32 = 13.5 // .input { font-size: 13.5px }
// .textarea { min-height: 76px } with rows=3 renders as 7+7+3*20.9+3 = 79.7px in the browser.
let SOP_TEXTAREA_H: Float32 = 79.0
let SOP_FIELD_GRID_GAP: Float32 = 8.0 // .sop-field-grid { gap: var(--space-2) }
let SOP_SECTION_LABEL_SIZE: Float32 = 11.0 // .sop-section-label { font-size: 11px }
let SOP_SECTION_LABEL_LINE: Float32 = 16.5
let SOP_HINT_SIZE: Float32 = 11.5 // .sop-hint { font-size: 11.5px }
let SOP_HINT_LINE: Float32 = 17.25 // line-height: 1.5
let SOP_VALUE_SIZE: Float32 = 11.5 // .sop-stats-value { font-size: 11.5px }
let SOP_PROGRESS_H: Float32 = 5.0 // .progress--sm { height: 5px } (ui.css:305)
let SOP_BLOCK_GAP: Float32 = 8.0 // .sop-stats { gap: var(--space-2) }
let SOP_BLOCK_PAD_TOP: Float32 = 8.0 // .sop-stats { padding-top: var(--space-2) }
/** `.sop-history { max-height: 232px; padding: var(--space-3) var(--space-4) }` (sop.css:851). */
let SOP_HISTORY_PAD_Y: Float32 = 12.0
let SOP_HISTORY_PAD_X: Float32 = 16.0
let SOP_HISTORY_ITEM_SIZE: Float32 = 11.5 // .sop-history-item { font-size: 11.5px }
let SOP_HISTORY_NOTE_SIZE: Float32 = 11.0 // .sop-history-note { font-size: 11px }
let SOP_HISTORY_NOTE_LINE: Float32 = 16.5

/** Badge geometry: `.badge { padding: 2px 7px; font-size: 11px; line-height: 1.6 }` (ui.css:249). */
let SOP_BADGE_H: Float32 = 23.6
let SOP_BADGE_FONT: Float32 = 11.0
let SOP_BADGE_PAD_X: Float32 = 7.0
/** `.sop-list-items .badge { font-size: 10.5px; padding: 1px 6px }` (sop.css:205). */
let SOP_ROW_BADGE_H: Float32 = 20.8
let SOP_ROW_BADGE_FONT: Float32 = 10.5
let SOP_ROW_BADGE_PAD_X: Float32 = 6.0

/** `.sop-runbar { padding: var(--space-3) var(--space-4); gap: var(--space-4) }` (sop.css:560). */
let SOP_RUNBAR_PAD_Y: Float32 = 12.0
let SOP_RUNBAR_PAD_X: Float32 = 16.0
let SOP_RUNBAR_BAR: Float32 = 3.0 // border-left: 3px solid var(--accent)
let SOP_RUNBAR_TITLE_SIZE: Float32 = 14.0
let SOP_RUNBAR_META_SIZE: Float32 = 11.5
let SOP_CHIP_H: Float32 = 22.0 // .sop-runbar-check { padding: 2px 8px; font-size: 11.5px }

/** `.sop-side { gap: var(--space-3) }` (sop.css:675). */
let SOP_SIDE_GAP: Float32 = 12.0

/** One laid-out toolbar button (`SopCanvas.tsx:620-693`). */
class SopToolButton {
    let id: String
    let label: String
    let glyph: ?IconGlyph
    let iconOnly: Bool
    let rect: Rect

    init(id: String, label: String, glyph: ?IconGlyph, iconOnly: Bool, rect: Rect) {
        this.id = id
        this.label = label
        this.glyph = glyph
        this.iconOnly = iconOnly
        this.rect = rect
    }
}

/** `.sop-toolbar`: `6px 8px` padding, `--space-2` gap, wrapping groups (sop.css:248-272). */
class SopToolbar {
    let rect: Rect
    let buttons: Array<SopToolButton>
    let height: Float32
    /** Group separators as `(x, top, bottom)` vertical rules. */
    let separators: Array<(Float32, Float32, Float32)>

    init(rect: Rect, buttons: Array<SopToolButton>, height: Float32, separators: Array<(Float32, Float32, Float32)>) {
        this.rect = rect
        this.buttons = buttons
        this.height = height
        this.separators = separators
    }

    func button(id: String): ?SopToolButton {
        for (item in buttons) {
            if (item.id == id) {
                return Some(item)
            }
        }
        return None
    }
}

/** Toolbar content height for the two wrapped rows (28px buttons + 26px icon buttons + gap). */
func toolbarHeight(): Float32 {
    SOP_TOOLBAR_PAD_Y * 2.0 + SOP_BTN_SM_H + SOP_TOOLBAR_GAP + SOP_ICON_SM
}

/** Lays the toolbar out inside `canvas`; mirrors `flex-wrap: wrap` + `margin-left: auto`. */
func layoutToolbar(ctx: UiContext, canvas: Rect, running: Bool): SopToolbar {
    let left = canvas.x + 1.0 + SOP_TOOLBAR_PAD_X
    let right = canvas.right() - 1.0 - SOP_TOOLBAR_PAD_X
    let top = canvas.y + 1.0 + SOP_TOOLBAR_PAD_Y
    let buttons = ArrayList<SopToolButton>()
    let separators = ArrayList<(Float32, Float32, Float32)>()

    // Group 1: the four `+ <type>` ghost buttons (SopCanvas.tsx:622-635).
    var x = left
    let addTypes = [lg.SopNodeType.Action, lg.SopNodeType.Decision, lg.SopNodeType.Check, lg.SopNodeType.End]
    for (kind in addTypes) {
        let label = nodeTypeLabel(kind)
        let width = SOP_BTN_SM_PAD * 2.0 + 2.0 + contentWidth(ctx, label, Some(IconGlyph.Plus), 13.0, SOP_BTN_SM_FONT)
        buttons.add(SopToolButton("add:${lg.nodeTypeId(kind)}", label, Some(IconGlyph.Plus), false,
            Rect(x, top, width, SOP_BTN_SM_H)))
        x += width + SOP_TOOLBAR_GROUP_GAP
    }
    let group1Right = x - SOP_TOOLBAR_GROUP_GAP

    // Group 2: 运行 / 自动布局, with the `border-left + padding-left` group separator.
    let group2Left = group1Right + SOP_TOOLBAR_GAP
    separators.add((group2Left, top, top + SOP_BTN_SM_H))
    x = group2Left + 1.0 + SOP_TOOLBAR_PAD_X
    let runLabel = if (running) {
        "退出运行"
    } else {
        "运行"
    }
    let runGlyph = if (running) {
        IconGlyph.Close
    } else {
        IconGlyph.Play
    }
    let runWidth = SOP_BTN_SM_PAD * 2.0 + 2.0 + contentWidth(ctx, runLabel, Some(runGlyph), 13.0, SOP_BTN_SM_FONT)
    buttons.add(SopToolButton("run", runLabel, Some(runGlyph), false, Rect(x, top, runWidth, SOP_BTN_SM_H)))
    x += runWidth + SOP_TOOLBAR_GROUP_GAP
    let layoutLabel = "自动布局"
    let layoutWidth = SOP_BTN_SM_PAD * 2.0 + 2.0 + contentWidth(ctx, layoutLabel, Some(IconGlyph.Workflow), 13.0,
        SOP_BTN_SM_FONT)
    buttons.add(SopToolButton("layout", layoutLabel, Some(IconGlyph.Workflow), false,
        Rect(x, top, layoutWidth, SOP_BTN_SM_H)))
    let group2Right = x + layoutWidth

    // Group 3: icon-only buttons, right aligned on the second row (`margin-left: auto`).
    let iconIds = [
        ("fit", IconGlyph.Target), ("zoom-in", IconGlyph.ZoomIn), ("zoom-out", IconGlyph.ZoomOut),
        ("undo", IconGlyph.ChevronLeft), ("redo", IconGlyph.ChevronRight), ("delete", IconGlyph.Trash)
    ]
    let iconsWidth = Float32(iconIds.size) * SOP_ICON_SM + Float32(iconIds.size - 1) * SOP_TOOLBAR_GROUP_GAP
    let row2Top = top + SOP_BTN_SM_H + SOP_TOOLBAR_GAP
    var iconX = right - iconsWidth
    let group3Left = iconX - 1.0 - SOP_TOOLBAR_PAD_X
    if (group3Left > group2Right + SOP_TOOLBAR_GAP) {
        separators.add((group3Left, row2Top, row2Top + SOP_ICON_SM))
    }
    for ((id, glyph) in iconIds) {
        buttons.add(SopToolButton(id, "", Some(glyph), true, Rect(iconX, row2Top, SOP_ICON_SM, SOP_ICON_SM)))
        iconX += SOP_ICON_SM + SOP_TOOLBAR_GROUP_GAP
    }

    let height = toolbarHeight()
    return SopToolbar(Rect(canvas.x + 1.0, canvas.y + 1.0, canvas.w - 2.0, height), buttons.toArray(), height,
        separators.toArray())
}

/** `.sop-runbar` height: `12px 16px` padding, badge row + checklist row, `--space-2` gap. */
func measureRunBarHeight(view: SopFrame): Float32 {
    var secondRow = SOP_CHIP_H
    match (view.currentStep()) {
        case Some(step) => match (step.sop) {
            case Some(data) =>
                if (data.checklist.isEmpty()) {
                    secondRow = SOP_HINT_LINE
                }
            case None => secondRow = SOP_HINT_LINE
        }
        case None => secondRow = SOP_HINT_LINE
    }
    return SOP_RUNBAR_PAD_Y * 2.0 + SOP_BADGE_H + SOP_BLOCK_GAP + secondRow + 2.0
}

/**
 * Persistent interaction state for the page. CUI rebuilds the tree every frame, so
 * everything that must survive a rebuild (selection, run session, viewport, drag
 * gesture) lives in this object; it is retained through `remember` and every
 * mutation bumps `generation` so the declarative tree is rebuilt.
 */
class SopViewState {
    let generation: State<Int64>
    /** Page rect assigned by the last layout, so event hit-testing can reuse it. */
    var pageRect: Rect = Rect.zero()
    var selectedSopId: ?String = None
    var selectedNodeId: ?String = None
    var selectedEdgeId: ?String = None
    /** Run session (SopPage.tsx `run`). */
    var session: ?lg.RunSession = None
    var branchOptions: Array<lg.BranchOption> = Array<lg.BranchOption>()
    var branchOpen: Bool = false
    var branchResult: lg.RunResult = lg.RunResult.Pass
    /** Last finished-run message, shown in the run bar strip. */
    var notice: String = ""
    /** Canvas transform (zoom / pan), mirroring React Flow's viewport. */
    var zoom: Float64 = 1.0
    var panX: Float64 = 0.0
    var panY: Float64 = 0.0
    var viewReady: Bool = false
    /** Vertical preview layout is dropped once the user drags or auto-layouts (sop.css preview). */
    var previewDisabled: Bool = false
    /** Node drag gesture. */
    var dragNodeId: ?String = None
    var dragGrabX: Float64 = 0.0
    var dragGrabY: Float64 = 0.0
    var dragPosX: Float64 = 0.0
    var dragPosY: Float64 = 0.0
    var dragMoved: Bool = false
    /** Pane pan gesture. */
    var panning: Bool = false
    var panFromX: Float64 = 0.0
    var panFromY: Float64 = 0.0
    var panStartX: Float64 = 0.0
    var panStartY: Float64 = 0.0
    var inspectorOpen: Bool = true
    var createDraft: Bool = false
    var runSeq: Int64 = 0
    /*
     * The inspector is painted, not declared: it lays its "fields" out during draw. CUI only
     * registers a focus stop for a control declared during build, so those painted boxes open
     * the shared `Ui.prompt` instead of hosting an inline `TextField`
     * (docs/DEVICE-NOTES.md §16). One prompt serves every field; `promptKind` says which.
     */
    var promptOpen: State<Bool> = State<Bool>(false)
    var promptText: State<String> = State<String>("")
    var promptKind: State<String> = State<String>("")
    var promptTarget: State<String> = State<String>("")
    var promptEntry: State<String> = State<String>("")
    var promptError: State<String> = State<String>("")
    var promptFocus: FocusRequest = FocusRequest()
    /**
     * 被点字段的**窗口绝对矩形**（检查器 layout 时记录的 `rects.*`）。编辑器按它原位摆放：
     * 画布只知道自己画在哪，`Ui.inlineEditor` 需要这个矩形才能贴着字段出现。
     *
     * 用跨帧锚点而不是普通字段：普通字段一旦被「每帧重建的状态壳」持有就会回到 `Rect.zero()`，
     * 编辑器便画到窗口左上角（OKR/GTD 真机现场，docs/DEVICE-NOTES.md §25.1）。锚点还负责
     * 「滚动检查器 / resize 时编辑器跟着字段走」。
     */
    let promptAnchor: InlineAnchor
    /*
     * Area 下拉（`sop_area_picker.cj`）：检查器里唯一的多选一字段，弹层由 Overlay 承载。
     * `areaIndex` 是「未指定」+ `workspace.areas` 的候选下标。
     */
    var areaOpen: Bool = false
    var areaIndex: Int64 = 0
    /**
     * Area 字段的**窗口绝对矩形**（打开弹层时快照，之后每帧由 `syncSopAreaAnchor` 刷新）。
     * 弹层按它排版；字段消失时先关闭弹层，绝不拿 `Rect.zero()` 排版（那会把列表画到左侧边栏）。
     */
    var areaAnchor: Rect = Rect.zero()
    /** 本帧弹层几何（`layout` 算好，overlay 的 render/handle 共用，保证两边永远一致）。 */
    var areaPopup: ?SopAreaPopup = None
    /** 指针悬停的候选下标（-1 = 无）。 */
    var areaHover: Int64 = -1
    /** `.sop-inspector-body` 的滚动偏移（内容高于卡片时窗口内滚动，而非压到卡片外）。 */
    var inspectorScroll: Float32 = 0.0

    init(generation: State<Int64>) {
        this.generation = generation
        // 本状态壳由 `remember<SopViewState>` 持有，所以锚点直接构造即可（不需要再 remember）；
        // `State` 可以随时构造，读它时才建立构建期依赖。
        this.promptAnchor = InlineAnchor(State<Int64>(0))
    }

    /** Marks the frame dirty: the declarative body reads `generation`, so it rebuilds. */
    func touch(): Unit {
        generation.value = generation.value + 1
    }
}

/**
 * One frame of SOP data: the active SOP, its graph, the display positions (saved
 * canvas coords or the compact preview layout) and the canvas transform.
 */
class SopFrame {
    let workspace: Workspace
    let store: AppStore
    let theme: Theme
    let tk: ThemeTokens
    let sops: Array<SopSummary>
    let sop: ?Item
    let nodes: Array<Item>
    let edges: Array<Edge>
    let state: SopViewState
    /** Canvas coordinates actually drawn (preview layout merged over `sop.canvas`). */
    let display: HashMap<String, lg.SopPosition>
    /** Saved canvas coordinates, used when writing drags back to the store. */
    let saved: HashMap<String, lg.SopPosition>
    let previewActive: Bool
    let flow: Rect
    let zoom: Float64
    let panX: Float64
    let panY: Float64
    /** `.page` box (already centred at max-width 1280). */
    let page: Rect
    let headerH: Float32
    let toolbar: SopToolbar
    let historyH: Float32
    let today: String

    init(
        workspace: Workspace,
        store: AppStore,
        theme: Theme,
        tk: ThemeTokens,
        sops: Array<SopSummary>,
        sop: ?Item,
        nodes: Array<Item>,
        edges: Array<Edge>,
        state: SopViewState,
        display: HashMap<String, lg.SopPosition>,
        saved: HashMap<String, lg.SopPosition>,
        previewActive: Bool,
        flow: Rect,
        zoom: Float64,
        panX: Float64,
        panY: Float64,
        page: Rect,
        headerH: Float32,
        toolbar: SopToolbar,
        historyH: Float32,
        today: String
    ) {
        this.today = today
        this.page = page
        this.headerH = headerH
        this.toolbar = toolbar
        this.historyH = historyH
        this.workspace = workspace
        this.store = store
        this.theme = theme
        this.tk = tk
        this.sops = sops
        this.sop = sop
        this.nodes = nodes
        this.edges = edges
        this.state = state
        this.display = display
        this.saved = saved
        this.previewActive = previewActive
        this.flow = flow
        this.zoom = zoom
        this.panX = panX
        this.panY = panY
    }

    /** Run mode (`SopPage.tsx` renders `SopRunBar` only while a session exists). */
    func running(): Bool {
        state.session.isSome()
    }

    func pageRect(): Rect {
        page
    }

    func headerRect(): Rect {
        Rect(page.x, page.y, page.w, headerH)
    }

    /** Top of the list/canvas/inspector grid (below the header and the optional run bar). */
    func bodyTop(ctx: UiContext): Float32 {
        let base = page.y + headerH + SOP_PAGE_GAP
        if (!running()) {
            return base
        }
        return base + measureRunBarHeight(this) + SOP_PAGE_GAP
    }

    func bodyRect(ctx: UiContext): Rect {
        let top = bodyTop(ctx)
        return Rect(page.x, top, page.w, page.y + page.h - top)
    }

    func runBarRect(ctx: UiContext): Rect {
        let top = page.y + headerH + SOP_PAGE_GAP
        return Rect(page.x, top, page.w, measureRunBarHeight(this))
    }

    func listRect(ctx: UiContext): Rect {
        let body = bodyRect(ctx)
        return Rect(body.x, body.y, SOP_LIST_W, body.h)
    }

    func canvasRect(ctx: UiContext): Rect {
        let body = bodyRect(ctx)
        let width = canvasWidth()
        return Rect(body.x + SOP_LIST_W + SOP_BODY_GAP, body.y, width, body.h)
    }

    /** `.sop-body` grid: `272px minmax(0,1fr) 320px` with `--space-4` gaps (sop.css:22-28). */
    func canvasWidth(): Float32 {
        var width = page.w - SOP_LIST_W - SOP_BODY_GAP
        if (state.inspectorOpen) {
            width -= SOP_SIDE_W + SOP_BODY_GAP
        }
        return width
    }

    func sideRect(ctx: UiContext): Rect {
        let body = bodyRect(ctx)
        if (!state.inspectorOpen) {
            return Rect.zero()
        }
        let left = body.x + SOP_LIST_W + SOP_BODY_GAP + canvasWidth() + SOP_BODY_GAP
        return Rect(left, body.y, SOP_SIDE_W, body.h)
    }

    /** `.sop-side { gap: var(--space-3) }` between the inspector and the run history (sop.css:675). */
    func inspectorRect(ctx: UiContext): Rect {
        let side = sideRect(ctx)
        return Rect(side.x, side.y, side.w, side.h - historyH - SOP_SIDE_GAP)
    }

    func historyRect(ctx: UiContext): Rect {
        let side = sideRect(ctx)
        return Rect(side.x, side.y + side.h - historyH, side.w, historyH)
    }

    /** Canvas coordinate -> screen coordinate inside `flow`. */
    func screenX(flowX: Float64): Float32 {
        Float32(Float64(flow.x) + panX + flowX * zoom)
    }

    func screenY(flowY: Float64): Float32 {
        Float32(Float64(flow.y) + panY + flowY * zoom)
    }

    /** Screen coordinate -> canvas coordinate (for drags). */
    func flowXAt(screenXValue: Float32): Float64 {
        (Float64(screenXValue) - Float64(flow.x) - panX) / zoom
    }

    func flowYAt(screenYValue: Float32): Float64 {
        (Float64(screenYValue) - Float64(flow.y) - panY) / zoom
    }

    func nodePos(id: String): lg.SopPosition {
        if (display.contains(id)) {
            return display[id]
        }
        return lg.SopPosition(0.0, 0.0)
    }

    func nodeRect(item: Item): Rect {
        let position = nodePos(item.id)
        let left = screenX(position.x)
        let top = screenY(position.y)
        return Rect(left, top, Float32(lg.SOP_NODE_WIDTH * zoom), Float32(SOP_NODE_CSS_HEIGHT * zoom))
    }

    func nodeById(id: String): ?Item {
        for (item in nodes) {
            if (item.id == id) {
                return Some(item)
            }
        }
        return None
    }

    func edgeById(id: String): ?Edge {
        for (edge in edges) {
            if (edge.id == id) {
                return Some(edge)
            }
        }
        return None
    }

    func selectedNode(): ?Item {
        match (state.selectedNodeId) {
            case Some(id) => return nodeById(id)
            case None => return None
        }
    }

    func selectedEdge(): ?Edge {
        match (state.selectedEdgeId) {
            case Some(id) => return edgeById(id)
            case None => return None
        }
    }

    /** Run highlight state for the canvas (`buildCanvasNodes` run argument). */
    func runState(): ?lg.CanvasRunState {
        match (state.session) {
            case Some(session) => return Some(lg.CanvasRunState(currentId: session.currentId, visited: session.visited,
                failed: session.failed))
            case None => return None
        }
    }

    func currentStep(): ?Item {
        match (state.session) {
            case Some(session) => return nodeById(session.currentId)
            case None => return None
        }
    }

    func areaColor(item: Item): ?String {
        match (item.areaId) {
            case Some(id) => match (areaById(workspace, id)) {
                case Some(area) => return Some(area.color)
                case None => return None
            }
            case None => return None
        }
    }

    func areaName(item: Item): String {
        match (item.areaId) {
            case Some(id) => match (areaById(workspace, id)) {
                case Some(area) => return area.name
                case None => return ""
            }
            case None => return ""
        }
    }
}

let SOP_NODE_TYPE_LABELS_START: String = "开始"
let SOP_NODE_TYPE_LABELS_ACTION: String = "行动"
let SOP_NODE_TYPE_LABELS_DECISION: String = "判断"
let SOP_NODE_TYPE_LABELS_CHECK: String = "检查"
let SOP_NODE_TYPE_LABELS_END: String = "结束"
let SOP_NODE_TYPE_LABELS_NOTE: String = "便签"

/** `NODE_TYPE_LABELS` from `SopNode.tsx` (the badge/section wording shared by canvas + inspector). */
func nodeTypeLabel(kind: lg.SopNodeType): String {
    match (kind) {
        case lg.SopNodeType.Start => SOP_NODE_TYPE_LABELS_START
        case lg.SopNodeType.Action => SOP_NODE_TYPE_LABELS_ACTION
        case lg.SopNodeType.Decision => SOP_NODE_TYPE_LABELS_DECISION
        case lg.SopNodeType.Check => SOP_NODE_TYPE_LABELS_CHECK
        case lg.SopNodeType.End => SOP_NODE_TYPE_LABELS_END
        case lg.SopNodeType.Note => SOP_NODE_TYPE_LABELS_NOTE
    }
}

/** Node-type equality (the logic enum derives `Equatable` inside its own package only). */
func isNodeType(kind: lg.SopNodeType, target: lg.SopNodeType): Bool {
    lg.nodeTypeId(kind) == lg.nodeTypeId(target)
}

/** `NODE_TYPE_OPTIONS` order (SopInspector.tsx) — also the order of the type chips. */
func allNodeTypes(): Array<lg.SopNodeType> {
    [
        lg.SopNodeType.Start,
        lg.SopNodeType.Action,
        lg.SopNodeType.Decision,
        lg.SopNodeType.Check,
        lg.SopNodeType.End,
        lg.SopNodeType.Note
    ]
}

/** `Item.sop.nodeType` (core enum) -> logic node type. */
func nodeTypeOf(item: Item): lg.SopNodeType {
    match (item.sop) {
        case Some(data) => match (lg.parseNodeType(sopNodeTypeWire(data.nodeType))) {
            case Some(kind) => return kind
            case None => return lg.SopNodeType.Action
        }
        case None => return lg.SopNodeType.Action
    }
}

/** Core `Item` -> logic `SopNode` (canvas / run / layout input). */
func toSopNode(item: Item): lg.SopNode {
    let entries = ArrayList<lg.ChecklistEntry>()
    var owner = ""
    var duration: ?Int64 = None
    var canvasX = 0.0
    var canvasY = 0.0
    match (item.sop) {
        case Some(data) =>
            for (entry in data.checklist) {
                entries.add(lg.ChecklistEntry(entry.id, text: entry.text, done: entry.done))
            }
            match (data.owner) {
                case Some(value) => owner = value
                case None => ()
            }
            duration = data.durationMin
            canvasX = data.canvas.x
            canvasY = data.canvas.y
        case None => ()
    }
    lg.SopNode(item.id, title: item.title, nodeType: nodeTypeOf(item), canvasX: canvasX, canvasY: canvasY,
        checklist: entries.toArray(), owner: owner, durationMin: duration)
}

func toSopNodes(nodes: Array<Item>): Array<lg.SopNode> {
    let result = ArrayList<lg.SopNode>()
    for (item in nodes) {
        result.add(toSopNode(item))
    }
    result.toArray()
}

/** Core `Edge` -> logic `SopEdge` (canvas / layout / run input). */
func toSopEdges(edges: Array<Edge>): Array<lg.SopEdge> {
    let result = ArrayList<lg.SopEdge>()
    for (edge in edges) {
        if (edge.edgeType == EdgeType.Flow) {
            result.add(lg.SopEdge(edge.from, edge.to, label: edge.label, id: edge.id))
        }
    }
    result.toArray()
}

func flowEdges(edges: Array<Edge>): Array<Edge> {
    let result = ArrayList<Edge>()
    for (edge in edges) {
        if (edge.edgeType == EdgeType.Flow) {
            result.add(edge)
        }
    }
    result.toArray()
}

/** `SOP_NODE_WIDTH/HEIGHT` from `layout.cj`, exposed as view floats. */
func nodeWidth(): Float32 {
    Float32(lg.SOP_NODE_WIDTH)
}

func nodeHeight(): Float32 {
    Float32(lg.SOP_NODE_HEIGHT)
}
