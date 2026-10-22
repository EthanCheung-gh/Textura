package textura.views.sop

import std.collection.*
import std.deriving.*
import cui.*
import textura.core.data.*
import textura.ui.*
import textura.views.sop.logic as lg

/*
 * SOP page — 1:1 port of `src/modules/sop/SopPage.tsx` (with SopList / SopCanvas /
 * SopNode / SopInspector / SopRunBar / RunHistory + sop.css).
 *
 * Layout ownership: `render` fills the content box the shell assigns (the shell owns
 * `.shell-content`'s 24px padding); this file adds `.page`'s max-width centring and
 * the page grid `272px | 1fr | 320px` with `--space-4` gaps (sop.css:18-25).
 *
 * The page is drawn by custom widgets instead of CUI stacks: the SOP page mixes a
 * CSS grid, an absolutely positioned graph and box-shadow hover cards, none of which
 * map onto linear stacks. All colours/spacings come from `textura.ui` tokens, all
 * canvas maths from `textura.views.sop.logic`, and every interaction writes through
 * `ctx.store` so the page stays a real (not painted) UI.
 */

/** `LAYOUT_UNBOUNDED`-style probe from `ScrollView.measure` (anything this tall is a probe). */
let SOP_UNBOUNDED_PROBE: Float32 = 4096.0

/** `.page { max-width: 1280px; margin: 0 auto }` (shell.css:262). */
let SOP_PAGE_MAX_WIDTH: Float32 = 1280.0

/** `.sop-header` height: h1 22px/1.5 + `--space-1` + p 13px/1.5 (shell.css:270-290). */
let SOP_HEADER_H: Float32 = SOP_H1_LINE + SOP_HEADER_GAP + SOP_SUB_LINE

/** Route title used by the shell's route table (`docs/STRUCTURE.md` §3.6). */
public func bootstrapTitle(): String {
    "SOP"
}

/** Placeholder note; kept so the shell's dispatch contract keeps compiling. */
public func bootstrapNote(): String {
    "SOP 视图：可执行的流程图（节点＝步骤，连线＝下一步）。"
}

public func render(ctx: ViewContext): Unit {
    let workspace = ctx.store.state.value()
    let theme = if (ctx.theme == "dark") {
        texturaDark()
    } else {
        texturaLight()
    }
    let tokens = tokensOf(theme)
    // Page-local state survives rebuilds; every mutation bumps the generation cell,
    // which this body reads, so the declarative tree is re-described (CUI rebuilds it
    // every time a subscribed State changes).
    let generation = rememberState<Int64>("sop-generation") {0}
    let state = remember<SopViewState>("sop-view-state") {SopViewState(generation)}
    let _ = generation.value
    SopPageWidget(workspace, ctx.store, theme, tokens, state, ctx.today, ctx.width, ctx.height)
}

/** Page shell: header + (run bar) + list/canvas/inspector grid. */
class SopPageWidget <: Widget {
    private let workspace: Workspace
    private let store: AppStore
    private let theme: Theme
    private let tk: ThemeTokens
    private let state: SopViewState
    private let today: String
    private let windowWidth: Int64
    private let windowHeight: Int64
    private var view: ?SopFrame = None
    private var frame = Rect.zero()

    init(
        workspace: Workspace,
        store: AppStore,
        theme: Theme,
        tk: ThemeTokens,
        state: SopViewState,
        today: String,
        windowWidth: Int64,
        windowHeight: Int64
    ) {
        this.workspace = workspace
        this.store = store
        this.theme = theme
        this.tk = tk
        this.state = state
        this.today = today
        this.windowWidth = windowWidth
        this.windowHeight = windowHeight
        emit(this)
    }

    /**
     * `.page.sop-page { height: 100% }` (sop.css:6-12): the page claims the shell content box.
     *
     * The shell hosts the content slot in a `ScrollView`, whose measure probe offers an
     * *unbounded* height. Echoing that back made the page ~1e6px tall, the canvas flow area
     * ~1e6px tall, and `paintDots` then emitted ~2 million circle meshes per frame — enough to
     * overflow the SDL geometry batch and segfault later inside `SDL_UpdateTexture`
     * (`text_glyph_atlas.cj:180`). A page view must therefore report the viewport height, which
     * is the window minus the frozen shell chrome: topbar and the content padding
     * (`--topbar-height: 56`, `.shell-content { padding: var(--space-5) }`).
     */
    public func measure(_: UiContext, available: Size): Size {
        // A bounded offer (a plain host) is authoritative; the ScrollView probe is not.
        let bounded = available.h < SOP_UNBOUNDED_PROBE
        let height = if (bounded) {
            available.h
        } else {
            // Window height minus the shell chrome (`--topbar-height` + 2 × `--space-5`).
            max(0.0, Float32(windowHeight) - tk.metrics.topbarHeight - tk.space.s5 * 2.0)
        }
        Size(min(max(0.0, available.w), 8192.0), min(height, 8192.0))
    }

    public func layout(ctx: UiContext, rect: Rect): Unit {
        frame = rect
        view = buildFrame(ctx, workspace, store, theme, tk, state, rect, today)
    }

    public func draw(ctx: UiContext): Unit {
        match (view) {
            case Some(active) =>
                ctx.renderer.fill(active.pageRect(), tk.color.bg)
                paintHeader(ctx, active, active.headerRect())
                paintList(ctx, active)
                paintCanvas(ctx, active)
                paintInspector(ctx, active)
                paintHistory(ctx, active)
                if (active.running()) {
                    paintRunBar(ctx, active)
                }
                if (active.state.branchOpen) {
                    paintBranchPanel(ctx, active)
                }
            case None => ()
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (view) {
            case Some(active) =>
                if (!frame.contains(mouseX(event), mouseY(event)) && !isDragPhase(active, event)) {
                    return false
                }
                if (active.state.branchOpen && handleBranchPanel(ctx, active, event)) {
                    return true
                }
                if (handleCanvas(ctx, active, event)) {
                    return true
                }
                if (handleRunBar(ctx, active, event)) {
                    return true
                }
                if (handleInspector(ctx, active, event)) {
                    return true
                }
                if (handleList(ctx, active, event)) {
                    return true
                }
                return handleHeader(ctx, active, event)
            case None => return false
        }
    }

    /** A drag that started inside the canvas keeps receiving moves outside of it. */
    private func isDragPhase(active: SopFrame, event: UiEvent): Bool {
        if (active.state.dragNodeId.isSome() || active.state.panning) {
            match (event) {
                case UiEvent.MouseMove(_, _) => return true
                case UiEvent.MouseUp(_, _, _) => return true
                case _ => return false
            }
        }
        return false
    }
}

func mouseX(event: UiEvent): Float32 {
    match (event) {
        case UiEvent.MouseDown(_, x, _) => return x
        case UiEvent.MouseUp(_, x, _) => return x
        case UiEvent.MouseMove(x, _) => return x
        case UiEvent.MouseWheel(x, _, _, _) => return x
        case _ => return -1.0
    }
}

func mouseY(event: UiEvent): Float32 {
    match (event) {
        case UiEvent.MouseDown(_, _, y) => return y
        case UiEvent.MouseUp(_, _, y) => return y
        case UiEvent.MouseMove(_, y) => return y
        case UiEvent.MouseWheel(_, y, _, _) => return y
        case _ => return -1.0
    }
}

/** Per-frame model: page grid + toolbar + canvas transform + display coordinates. */
func buildFrame(
    ctx: UiContext,
    workspace: Workspace,
    store: AppStore,
    theme: Theme,
    tk: ThemeTokens,
    state: SopViewState,
    assigned: Rect,
    today: String
): SopFrame {
    // `.page { max-width: 1280px; margin: 0 auto }`: centre the page inside the content box.
    let pageWidth = min(assigned.w, SOP_PAGE_MAX_WIDTH)
    let page = Rect(assigned.x + (assigned.w - pageWidth) / 2.0, assigned.y, pageWidth, assigned.h)
    state.pageRect = page

    let summaries = sopList(workspace)
    let activeSop = resolveActiveSop(summaries, state)
    var nodes = Array<Item>()
    var edges = Array<Edge>()
    match (activeSop) {
        case Some(sop) =>
            let graph = sopGraph(workspace, sop.id)
            nodes = graph.nodes
            edges = graph.edges
        case None => ()
    }

    let running = state.session.isSome()
    let headerH = SOP_HEADER_H
    let bodyTop = page.y + headerH + SOP_PAGE_GAP
    let bodyBottom = page.y + page.h
    let historyH = measureHistoryHeight(ctx, workspace, activeSop, tk)
    let sideWidth: Float32 = if (state.inspectorOpen) {
        SOP_SIDE_W
    } else {
        0.0
    }
    let gapAfterList = SOP_BODY_GAP
    let gapAfterCanvas: Float32 = if (state.inspectorOpen) {
        SOP_BODY_GAP
    } else {
        0.0
    }
    let canvasWidth = page.w - SOP_LIST_W - gapAfterList - sideWidth - gapAfterCanvas
    let canvas = Rect(page.x + SOP_LIST_W + gapAfterList, bodyTop, canvasWidth, bodyBottom - bodyTop)
    let toolbar = layoutToolbar(ctx, canvas, running)
    let flowTop = canvas.y + 1.0 + toolbar.height + 1.0
    let flow = Rect(canvas.x + 1.0, flowTop, canvas.w - 2.0, canvas.y + canvas.h - 1.0 - flowTop)

    // Saved canvas coordinates (`Item.sop.canvas`).
    let saved = HashMap<String, lg.SopPosition>()
    for (item in nodes) {
        match (item.sop) {
            case Some(data) => saved[item.id] = lg.SopPosition(data.canvas.x, data.canvas.y)
            case None => saved[item.id] = lg.SopPosition(0.0, 0.0)
        }
    }
    let sopEdges = toSopEdges(edges)
    let savedBounds = lg.boundsOfPositions(saved, nodeWidth: lg.SOP_NODE_WIDTH, nodeHeight: lg.FIT_NODE_HEIGHT)

    // Compact vertical preview when the saved layout is very wide (SopCanvas.tsx:207-224):
    // display only — dragging or the auto-layout button writes real coordinates back.
    var previewActive = false
    let display = HashMap<String, lg.SopPosition>()
    for (item in nodes) {
        display[item.id] = saved[item.id]
    }
    if (!state.previewDisabled && nodes.size >= 4 && lg.isWideLayout(savedBounds)) {
        let ids = ArrayList<String>()
        for (item in nodes) {
            ids.add(item.id)
        }
        let preview = lg.layoutIds(ids.toArray(), sopEdges, options: lg.PREVIEW_LAYOUT)
        for (item in nodes) {
            if (preview.contains(item.id)) {
                display[item.id] = preview[item.id]
            }
        }
        previewActive = true
    }

    // Initial viewport (SopCanvas.tsx:313-325): computed once from the container box and
    // the readable-fit policy in `fit.cj`.
    if (!state.viewReady) {
        let bounds = lg.boundsOfPositions(display, nodeWidth: lg.SOP_NODE_WIDTH, nodeHeight: lg.FIT_NODE_HEIGHT)
        match (bounds) {
            case Some(value) =>
                let fitted = lg.computeReadableViewport(
                    lg.ReadableFitOptions(Float64(flow.w), Float64(flow.h), value, padding: lg.INITIAL_FIT_PADDING,
                        minZoom: lg.READABLE_MIN_ZOOM, maxZoom: lg.MAX_FIT_ZOOM)
                )
                state.zoom = fitted.zoom
                state.panX = fitted.viewport.x
                state.panY = fitted.viewport.y
            case None =>
                state.zoom = 1.0
                state.panX = 0.0
                state.panY = 0.0
        }
        state.viewReady = true
    }

    return SopFrame(workspace, store, theme, tk, summaries, activeSop, nodes, edges, state, display, saved, previewActive,
        flow, state.zoom, state.panX, state.panY, page, headerH, toolbar, historyH, today)
}

/** `selectedSopId` first, then the first SOP (SopPage.tsx:41). */
func resolveActiveSop(summaries: Array<SopSummary>, state: SopViewState): ?Item {
    match (state.selectedSopId) {
        case Some(id) =>
            for (summary in summaries) {
                if (summary.sop.id == id) {
                    return Some(summary.sop)
                }
            }
        case None => ()
    }
    if (summaries.isEmpty()) {
        return None
    }
    return Some(summaries[0].sop)
}

/** `.sop-header` title block (`shell.css:270-292`). */
func paintHeader(ctx: UiContext, view: SopFrame, rect: Rect): Unit {
    let tk = view.tk
    let h1Center = rect.y + SOP_H1_LINE / 2.0
    paintText(ctx, "SOP", rect.x, h1Center, SOP_H1_SIZE, 650, tk.color.text)
    let subCenter = rect.y + SOP_H1_LINE + SOP_HEADER_GAP + SOP_SUB_LINE / 2.0
    paintText(ctx, "把流程画成可执行的图：节点是步骤，连线决定下一步。", rect.x, subCenter, SOP_SUB_SIZE, 400,
        tk.color.textMuted)

    match (view.sop) {
        case Some(_) =>
            let label = if (view.state.inspectorOpen) {
                "收起右栏"
            } else {
                "展开右栏"
            }
            let glyph = if (view.state.inspectorOpen) {
                IconGlyph.ChevronRight
            } else {
                IconGlyph.ChevronLeft
            }
            let width = SOP_BTN_SM_PAD * 2.0 + 2.0 + contentWidth(ctx, label, Some(glyph), 14.0, SOP_BTN_SM_FONT)
            let buttonRect = Rect(rect.right() - width, rect.y, width, SOP_BTN_SM_H)
            paintGhostButton(ctx, tk, label, buttonRect, glyph: glyph, glyphSide: 14.0)
        case None => ()
    }
}

func handleHeader(ctx: UiContext, view: SopFrame, event: UiEvent): Bool {
    let _ = ctx
    match (event) {
        case UiEvent.MouseDown(MouseButton.Left, x, y) =>
            match (view.sop) {
                case Some(_) =>
                    let rect = view.headerRect()
                    let label = if (view.state.inspectorOpen) {
                        "收起右栏"
                    } else {
                        "展开右栏"
                    }
                    let glyph = if (view.state.inspectorOpen) {
                        IconGlyph.ChevronRight
                    } else {
                        IconGlyph.ChevronLeft
                    }
                    let width = SOP_BTN_SM_PAD * 2.0 + 2.0 + contentWidth(ctx, label, Some(glyph), 14.0,
                        SOP_BTN_SM_FONT)
                    if (Rect(rect.right() - width, rect.y, width, SOP_BTN_SM_H).contains(x, y)) {
                        view.state.inspectorOpen = !view.state.inspectorOpen
                        view.state.touch()
                        return true
                    }
                case None => ()
            }
        case _ => ()
    }
    return false
}

/** `.sop-history` height: content-driven, capped at 232px (sop.css:851). */
func measureHistoryHeight(ctx: UiContext, workspace: Workspace, sop: ?Item, tk: ThemeTokens): Float32 {
    let _ = tk
    var count = 0
    var notes = 0
    match (sop) {
        case Some(item) =>
            for (run in recentRunsFor(workspace, item.id, limit: 20)) {
                count += 1
                if (!run.note.isEmpty()) {
                    notes += 1
                }
            }
        case None => ()
    }
    if (count == 0) {
        return SOP_HISTORY_PAD_Y * 2.0 + SOP_SECTION_LABEL_LINE + SOP_BLOCK_GAP + SOP_HINT_LINE + 2.0
    }
    var height = SOP_HISTORY_PAD_Y * 2.0 + SOP_SECTION_LABEL_LINE + SOP_BLOCK_GAP
    height += Float32(count) * SOP_BADGE_H
    height += Float32(count - 1) * SOP_BLOCK_GAP
    height += Float32(notes) * (SOP_BLOCK_GAP + SOP_HISTORY_NOTE_LINE)
    return min(height + 2.0, 232.0)
}
