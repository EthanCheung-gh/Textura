package textura.shell

import std.collection.*
import std.fs.*
import cui.*
import textura.core.data.*
import textura.ui.*

/*
 * `src/app/AppShell.tsx` — the desktop shell.
 *
 *   .shell grid: (sidebar 240 | sidebar) + (topbar 56 / content), window min 1024×640
 *   .shell-content is the only scrolling region (24px padding, views own their .page)
 *   overlays: CommandPalette / QuickCapture / ShortcutsDialog + the notices toast stack
 *   status screens: workspace loading + load error (AppShell.tsx:115-134) and the route
 *   error card (RouteErrorBoundary) for a view that throws.
 *
 * Theme/route live in `AppStore.ui` (the single fact source) and are persisted to
 * `$HOME/.textura/ui-prefs.json` in interactive runs only; the parity CLI never writes
 * anything, so two `--snapshot` runs stay byte-identical.
 */

public class ShellHost {
    public let store: AppStore
    public let runtime: ShellRuntime
    public let today: String
    public let interactive: Bool
    public let loadError: ?String
    public let viewportWidth: Int64
    public let viewportHeight: Int64
    /**
     * The one CUI `State` the shell root reads, so that a store write can invalidate the tree.
     *
     * `AppStore.state` / `AppStore.ui` are `core.data` cells, not CUI states: writing them marks
     * nothing dirty in CUI's incremental retained graph, and `buildShell` is only re-executed when a
     * CUI `State` read inside its scope changes. On the device that meant a click could navigate the
     * store (`store.ui().route == "calendar"`, the row even took focus) while the window kept the old
     * route forever — the sidebar's `onNavigate` ran, the shell never rebuilt (see
     * `docs/DEVICE-NOTES.md` §5). This revision is the missing link; see `armStoreBridge`.
     */
    public let revision: State<Int64>

    private var revisionDelivery: ?((() -> Unit) -> Unit) = None
    private var bridgeArmed: Bool = false

    public init(
        store: AppStore,
        runtime: ShellRuntime,
        today: String,
        interactive: Bool,
        loadError: ?String,
        viewportWidth: Int64,
        viewportHeight: Int64
    ) {
        this.store = store
        this.runtime = runtime
        this.today = today
        this.interactive = interactive
        this.loadError = loadError
        this.viewportWidth = viewportWidth
        this.viewportHeight = viewportHeight
        this.revision = State<Int64>(0)
    }

    /**
     * Wires every store cell that can change what the shell paints to `revision`.
     *
     * Deliberately global: `buildShell` reads the store directly in a dozen places (route, theme,
     * workspace, notices, save phase), and views read `store.state` on their own. Routing each
     * mutation through its own view would leave the next reader of a new fact silently stale, so one
     * revision covers the whole shell and any store write repaints it. The cost is a full shell
     * rebuild per store write, which is what the Web build's React re-render does anyway.
     *
     * `deliver` runs a closure on the UI thread (`DesktopApp.deliver`): inline during a frame, posted
     * when a store write happens on a worker. Idempotent — the entry point calls it once per run.
     */
    public func armStoreBridge(deliver: (() -> Unit) -> Unit): Unit {
        if (bridgeArmed) {
            return
        }
        bridgeArmed = true
        revisionDelivery = Some(deliver)
        let pump: () -> Unit = {=> this.pumpRevision()}
        store.state.subscribe {_ => pump()}
        store.ui.subscribe {_ => pump()}
        store.notices.subscribe {_ => pump()}
        runtime.onVisualChange = pump
    }

    /** Reads the bridge revision: the CUI dependency `buildShell` establishes at its root. */
    public func revisionToken(): Int64 {
        revision.value
    }

    private func pumpRevision(): Unit {
        let bump: () -> Unit = {=> revision.value = revision.value + 1}
        match (revisionDelivery) {
            case Some(deliver) => deliver(bump)
            case None => bump()
        }
    }

    public func route(): Route {
        match (parseRoute(store.ui.value().route)) {
            case Some(value) => value
            case None => Route.Dashboard
        }
    }

    public func themeName(): String {
        store.ui.value().theme
    }

    public func navigate(id: String): Unit {
        store.setRoute(id)
        store.setUi({state =>
            state.paletteOpen = false
            state.quickCaptureOpen = false
            state.shortcutsOpen = false
        })
    }

    public func toggleTheme(): Unit {
        let next = if (themeName() == "dark") {
            "light"
        } else {
            "dark"
        }
        store.setTheme(next)
        store.notify(if (next == "dark") {
            "已切换到深色主题"
        } else {
            "已切换到浅色主题"
        }, tone: NoticeTone.Info)
    }

    public func openCapture(): Unit {
        store.setUi({state =>
            state.quickCaptureOpen = true
            state.paletteOpen = false
            state.shortcutsOpen = false
        })
    }

    public func closeCapture(): Unit {
        store.setUi({state => state.quickCaptureOpen = false})
    }

    public func closePalette(): Unit {
        store.setUi({state => state.paletteOpen = false})
    }

    public func togglePalette(): Unit {
        let next = !store.ui.value().paletteOpen
        store.setUi({state =>
            state.paletteOpen = next
            state.quickCaptureOpen = false
            state.shortcutsOpen = false
        })
    }

    public func closeShortcuts(): Unit {
        store.setUi({state => state.shortcutsOpen = false})
    }

    public func toggleShortcuts(): Unit {
        let next = !store.ui.value().shortcutsOpen
        store.setUi({state =>
            state.shortcutsOpen = next
            state.paletteOpen = false
            state.quickCaptureOpen = false
        })
    }

    public func closeTopLayer(): Bool {
        let ui = store.ui.value()
        if (ui.shortcutsOpen) {
            closeShortcuts()
            return true
        }
        if (ui.paletteOpen) {
            closePalette()
            return true
        }
        if (ui.quickCaptureOpen) {
            closeCapture()
            return true
        }
        false
    }

    public func undo(): Unit {
        if (!store.canUndo()) {
            store.notify("没有可撤销的操作", tone: NoticeTone.Info)
            return
        }
        store.undo()
        store.notify("已撤销上一步", tone: NoticeTone.Success)
    }

    public func redo(): Unit {
        if (!store.canRedo()) {
            store.notify("没有可重做的操作", tone: NoticeTone.Info)
            return
        }
        store.redo()
        store.notify("已重做一步", tone: NoticeTone.Success)
    }

    /** `runItem` (CommandPalette.tsx:365-376): select + jump to the item's view. */
    public func runPaletteItem(id: String): Unit {
        let item = match (findItem(store.state.value(), id)) {
            case Some(value) => value
            case None => return
        }
        store.select(item.id)
        store.setUi({state =>
            state.route = routeId(routeForItemKind(item.kind))
            match (item.okr) {
                case Some(value) => state.okrPeriod = value.period
                case None => ()
            }
            state.paletteOpen = false
        })
    }

    /** `runArea` (CommandPalette.tsx:378-384): prefill the GTD search with the area name. */
    public func runPaletteArea(id: String): Unit {
        let area = match (findArea(store.state.value(), id)) {
            case Some(value) => value
            case None => return
        }
        store.setUi({state =>
            state.route = "gtd"
            state.search = area.name
            state.paletteOpen = false
        })
        store.notify("已在搜索框填入领域「${area.name}」，可在 GTD 视图继续用领域筛选收窄", tone: NoticeTone.Info)
    }

    /** Runs a palette row, remembers it in the recents list and resets the highlight. */
    public func runPaletteRow(row: PaletteRow, active: State<Int64>): Unit {
        if (row.disabled) {
            return
        }
        rememberPaletteRef(PaletteRecentRef(row.refType, row.refId))
        active.value = 0
        row.run()
    }

    public func rememberPaletteRef(ref: PaletteRecentRef): Unit {
        runtime.rememberRecent(ref, interactive)
    }

    /** `exportWorkspaceToFile` (workspaceIO.ts) without a native dialog: sibling file. */
    public func exportWorkspace(): Unit {
        let source = match (store.path()) {
            case Some(value) => value
            case None =>
                store.notify("导出失败：尚未指定工作区路径", tone: NoticeTone.Error)
                return
        }
        let parent = match (source.lastIndexOf("/")) {
            case Some(index) => source[0..index]
            case None => "."
        }
        let stamp = formatWithPattern(store.clock.nowMillis(), "yyyyMMdd-HHmm")
        let target = "${parent}/textura-workspace-${stamp}.json"
        try {
            File.writeTo(target, store.exportDocument().toArray())
            store.notify("已导出到 ${target}", tone: NoticeTone.Success)
        } catch (error: Exception) {
            store.notify("导出失败：${error.message}", tone: NoticeTone.Error)
        }
        store.setUi({state => state.paletteOpen = false})
    }

    /** QuickCapture submit: an inbox action with tags/context/energy/due date. */
    public func collectCapture(raw: String, closeAfter: Bool): Unit {
        let parsed = parseCapture(raw, today)
        if (!parsed.hasContent) {
            return
        }
        let gtd = GtdPatch()
        gtd.clarified = SetValue<Bool>.Value(false)
        gtd.context = SetValue<?String>.Value(parsed.context)
        gtd.energy = SetValue<?Energy>.Value(parsed.energy)
        let gantt = GanttPatch()
        gantt.end = SetValue<?String>.Value(parsed.date)
        let item = store.createItem(
            NewItemInput(ItemKind.Action, parsed.title, status: Some(ItemStatus.Inbox), tags: parsed.tags,
                gtd: Some(gtd), gantt: Some(gantt))
        )
        runtime.captureSession.add(CaptureEntry(item.id, parsed.title, parsed.tags, parsed.context,
            parsed.energy, parsed.date), at: 0)
        store.notify("已收集「${parsed.title}」", tone: NoticeTone.Success)
        if (closeAfter) {
            closeCapture()
        }
    }

    public func undoLastCapture(): Unit {
        if (runtime.captureSession.isEmpty()) {
            return
        }
        let last = runtime.captureSession[0]
        runtime.captureSession.remove(at: 0)
        store.deleteItems([last.id])
        store.notify("已撤销「${last.title}」", tone: NoticeTone.Info)
    }

    /** Global hotkeys (useGlobalHotkeys.ts). Returns true when the key was consumed. */
    public func handleHotkey(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.KeyDown(key, isRepeat) =>
                if (isRepeat) {
                    return false
                }
                let modifiers = ctx.eventModifiers()
                let command = modifiers.command
                let alt = modifiers.alt
                match (key) {
                    case Key.Escape =>
                        return closeTopLayer()
                    case Key.Letter(code) =>
                        let lower = asciiLower(code)
                        if (command && !alt) {
                            if (lower == UInt8(75) && !modifiers.shift) {
                                togglePalette()
                                return true
                            }
                            if (lower == UInt8(78)) {
                                openCapture()
                                return true
                            }
                            if (lower == UInt8(90) && !focusLooksEditable(ctx.focusId)) {
                                let route = route()
                                if (route == Route.Gtd || route == Route.Sop) {
                                    return false
                                }
                                if (modifiers.shift) {
                                    redo()
                                } else {
                                    undo()
                                }
                                return true
                            }
                        }
                        if (!command && !alt && code == UInt8(63) && !focusLooksEditable(ctx.focusId)) {
                            toggleShortcuts()
                            return true
                        }
                        return false
                    case _ => return false
                }
            case _ => return false
        }
    }
}

func asciiLower(value: UInt8): UInt8 {
    if (value >= UInt8(65) && value <= UInt8(90)) {
        value + UInt8(32)
    } else {
        value
    }
}

/** Approximates `isEditableTarget`: the shell knows its own editor keys, views' ids by suffix. */
func focusLooksEditable(focusId: String): Bool {
    if (focusId.isEmpty()) {
        return false
    }
    if (focusId == "shell-search" || focusId == "capture-input" || focusId == "palette-search") {
        return true
    }
    focusId.endsWith("-input") || focusId.endsWith("-search") || focusId.endsWith("-note") ||
        focusId.endsWith("-title")
}

/** `Sidebar.tsx` data: nav counts, areas, save state and the storage footer. */
func buildSidebarData(host: ShellHost, workspace: Workspace, route: Route): SidebarData {
    let counts = countByStatus(workspace)
    let inbox = match (counts.get("inbox")) {
        case Some(value) => value
        case None => Int64(0)
    }
    let nav = ArrayList<SidebarNavItem>()
    for (entry in ROUTES) {
        nav.add(
            SidebarNavItem(routeId(entry), routeLabel(entry), routeGlyph(entry), if (entry == Route.Gtd) {
                inbox
            } else {
                Int64(0)
            }, entry == route))
    }
    let areas = ArrayList<SidebarAreaItem>()
    let tokens = tokensOf(themeByName(host.themeName()))
    for (area in workspace.areas) {
        var open = 0
        for (item in workspace.items) {
            let sameArea = match (item.areaId) {
                case Some(value) => value == area.id
                case None => false
            }
            if (sameArea && item.status != ItemStatus.Done && item.status != ItemStatus.Dropped) {
                open += 1
            }
        }
        areas.add(SidebarAreaItem(area.name, hexColor(area.color, tokens.color.accent), open))
    }
    SidebarData(nav.toArray(), areas.toArray(), host.runtime.savePhase,
        "${workspace.items.size} 条记录 · v${workspace.version}")
}

func noticeRows(notices: Array<Notice>): Array<NoticeRow> {
    let rows = ArrayList<NoticeRow>()
    for (notice in notices) {
        rows.add(NoticeRow(notice.id, notice.message, notice.tone))
    }
    rows.toArray()
}

/**
 * Shell root builder. Call from `app.run { buildShell(host) }`.
 *
 * `frame_tick`: when the autosave flash or a toast is alive the body is wrapped in a
 * `FrameHandler`, which keeps requesting frames so timers advance; otherwise the shell is
 * purely event-driven (and the parity snapshot path never ticks).
 */
public func buildShell(host: ShellHost): Unit {
    // Read the bridge revision *first*, before any declarative scope is opened: this is the CUI
    // dependency that makes `AppStore` writes repaint the shell (see `ShellHost.revision`). Nothing
    // else in this function may run ahead of it, or a store write could arrive before the tree
    // declared that it depends on the write.
    let _ = host.revisionToken()
    let store = host.store
    let ui = store.ui.value()
    let theme = themeByName(ui.theme)
    let tokens = tokensOf(theme)
    let route = host.route()
    let workspace = store.state.value()

    host.runtime.observeWorkspace(store)
    host.runtime.observeNotices(store)
    host.runtime.persistUi(ui.route, ui.theme, host.interactive)

    if (host.loadError.isSome()) {
        buildWorkspaceErrorScreen(theme, host.loadError.getOrThrow(), {=>
            match (store.path()) {
                case Some(path) => store.load(path)
                case None => ()
            }
        })
        return
    }
    if (store.storeStatus() == StoreStatus.Loading) {
        LoadingScreenView(tokens, "正在织理工作区…")
        return
    }

    // Remembered editor state: survives CUI's per-frame rebuild.
    let searchText = rememberState<String>("shell-search") {ui.search}
    let paletteQuery = rememberState<String>("palette-query") {""}
    let paletteActive = rememberState<Int64>("palette-active") {0}
    let captureText = rememberState<String>("capture-text") {""}
    if (searchText.value != ui.search) {
        store.setSearch(searchText.value)
    }

    let sidebar = buildSidebarData(host, workspace, route)

    let body = {=>
        EventHandler(onEvent: {ctx, event => host.handleHotkey(ctx, event)}) {
            ZStack {
                HStack(spacing: vp(0.0), flexible: false) {
                    SidebarView(tokens, sidebar, {id => host.navigate(id)}).width(SIDEBAR_WIDTH).fillHeight()
                    VStack(spacing: vp(0.0)) {
                        buildTopBar(theme, routeMetaTitle(route), routeSubtitle(route), searchText,
                            if (ui.theme == "dark") {
                                IconGlyph.Sun
                            } else {
                                IconGlyph.Moon
                            },
                            if (ui.theme == "dark") {
                                "切换到浅色主题"
                            } else {
                                "切换到深色主题"
                            }, {=> host.toggleTheme()})
                        // `.shell-content { flex:1; min-height:0; overflow:auto; padding: 24px }`
                        // Textura patch CUI-P02: overlay-style scrollbar — the content keeps the
                        // full 1152px width (1440 - 240 sidebar - 48 padding) like the Web build,
                        // which draws no scrollbar gutter (parity ref uses overlay scrollbars).
                        ScrollView(key: "shell-content") {
                            VStack(spacing: vp(0.0)) {
                                renderRoute(route,
                                    ViewContext(store, ui.theme, host.today, host.viewportWidth, host.viewportHeight,
                                        {id => host.navigate(id)}))
                            }.hug().fillWidth().padding(CONTENT_PAD)
                        }.scrollBarVisible(false).keyboardScroll(true).revealFocusedOnFocus(true)
                    }.fillHeight()
                }.fillWidth().fillHeight()
                NoticeLayerView(tokens, noticeRows(store.notices.value()))
            }.fillWidth().fillHeight().background(tokens.color.bg)
        }
        buildCommandPalette(host, theme, ui.paletteOpen, paletteQuery, paletteActive)
        buildQuickCapture(theme, ui.quickCaptureOpen, captureText, host.runtime.captureSession, host.today,
            {=> host.closeCapture()}, {raw, closeAfter =>
                host.collectCapture(raw, closeAfter)
                captureText.value = ""
            }, {=> host.undoLastCapture()})
        buildShortcutsDialog(host, theme, ui.shortcutsOpen)
    }

    if (host.runtime.needsTick(store)) {
        FrameHandler(onFrame: {info =>
            host.runtime.tick(store, info)
        }) {
            body()
        }
    } else {
        body()
    }
}
