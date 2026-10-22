package textura.shell

import std.collection.*
import cui.*
import textura.core.data.*
import textura.ui.*

/*
 * `src/modules/appshell/CommandPalette.tsx` + `.palette*` (appshell.css:3-154).
 *
 * Modal 640px wide. Body: a search row (surface-2, 1px border, radius 8, search glyph,
 * Esc chip), a result list capped at 360px, and a footer of key hints. Rows are a
 * 18px / 1fr / auto grid with 12px gaps and 7px 8px padding; the active row gets a
 * surface-2 pill and a 2px accent inset bar. Matching/scoring comes from `fuzzy.cj`.
 *
 * Keyboard: ↑/↓ move (skipping disabled rows), Enter runs, Tab jumps groups, Esc closes.
 */

/** `.palette-row { padding: 7px 8px; font-size: 13px }`. */
public let PALETTE_ROW_HEIGHT: Float32 = 7.0 * 2.0 + lineBox(13.0)
/** `.palette-group { padding: 8px 8px 4px; font-size: 10.5px }`. */
public let PALETTE_GROUP_HEIGHT: Float32 = 8.0 + 4.0 + lineBox(10.5)

public class PaletteAction {
    public let id: String
    public let label: String
    public let hint: String
    public let glyph: IconGlyph
    public let keywords: Array<String>
    public let disabled: Bool
    public let run: () -> Unit

    public init(id: String, label: String, hint: String, glyph: IconGlyph, keywords: Array<String>, disabled: Bool,
        run: () -> Unit) {
        this.id = id
        this.label = label
        this.hint = hint
        this.glyph = glyph
        this.keywords = keywords
        this.disabled = disabled
        this.run = run
    }
}

public class PaletteRow {
    public let key: String
    public let group: String
    public let label: String
    public let hint: String
    public let glyph: IconGlyph
    public let disabled: Bool
    public let refType: String
    public let refId: String
    public let run: () -> Unit

    public init(key: String, group: String, label: String, hint: String, glyph: IconGlyph, disabled: Bool,
        refType: String, refId: String, run: () -> Unit) {
        this.key = key
        this.group = group
        this.label = label
        this.hint = hint
        this.glyph = glyph
        this.disabled = disabled
        this.refType = refType
        this.refId = refId
        this.run = run
    }
}

public func kindGlyph(kind: ItemKind): IconGlyph {
    match (kind) {
        case ItemKind.Objective => IconGlyph.Target
        case ItemKind.KeyResult => IconGlyph.Flag
        case ItemKind.Project => IconGlyph.Folder
        case ItemKind.Action => IconGlyph.Check
        case ItemKind.Sop => IconGlyph.Workflow
        case ItemKind.Step => IconGlyph.Workflow
        case ItemKind.Milestone => IconGlyph.Flag
        case ItemKind.Note => IconGlyph.Edit
        case ItemKind.Reference => IconGlyph.Link
    }
}

func routeForItemKind(kind: ItemKind): Route {
    match (kind) {
        case ItemKind.Objective | ItemKind.KeyResult => Route.Okr
        case ItemKind.Sop | ItemKind.Step => Route.Sop
        case ItemKind.Project | ItemKind.Action | ItemKind.Milestone => Route.Gantt
        case _ => Route.Gtd
    }
}

/** `.palette-row` — custom row so the hint column can be right-aligned at 13px/11px. */
class PaletteRowView <: Widget {
    private let tokens: ThemeTokens
    private let row: PaletteRow
    private let active: Bool
    private let query: String
    private let onHover: () -> Unit
    private let onRun: () -> Unit
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, row: PaletteRow, active: Bool, query: String, onHover: () -> Unit,
        onRun: () -> Unit) {
        this.tokens = tokens
        this.row = row
        this.active = active
        this.query = query
        this.onHover = onHover
        this.onRun = onRun
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(max(available.w, 0.0), PALETTE_ROW_HEIGHT)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        if (active) {
            fillRound(ctx, frame, tokens.radius.md, c.surface2)
            ctx.renderer.fill(Rect(frame.x, frame.y, 2.0, frame.h), c.accent)
        }
        let centerY = frame.centerY()
        let iconColor = if (active) {
            c.accent
        } else {
            c.textFaint
        }
        paintSpec(ctx, row.glyph, Rect(frame.x + 8.0, centerY - 9.0, 15.0, 15.0), iconColor)
        let labelX = frame.x + 8.0 + 18.0 + 12.0
        let labelColor = if (active) {
            c.text
        } else {
            c.textMuted
        }
        let fontSize = fpSize(ctx, 13.0)
        var x = labelX
        for (segment in highlightSegments(row.label, query)) {
            let width = textWidth(ctx, segment.text, fontSize, 400)
            if (segment.matched) {
                fillRect(ctx, Rect(x, frame.y + 7.0, width, PALETTE_ROW_HEIGHT - 14.0), c.accentSoft)
                textLeading(ctx, segment.text, x, centerY, c.accent, fontSize, 400)
            } else {
                textLeading(ctx, segment.text, x, centerY, labelColor, fontSize, 400)
            }
            x += width
        }
        if (!row.hint.isEmpty()) {
            let hintSize = fpSize(ctx, 11.0)
            textTrailing(ctx, row.hint, frame.right() - 8.0, centerY, c.textFaint, hintSize, 400)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (frame.contains(x, y)) {
                    onHover()
                    ctx.claimHover("palette-row-${row.key}", CursorShape.Interactive)
                    return true
                }
                return false
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    if (!row.disabled) {
                        onRun()
                    }
                    return true
                }
                return false
            case _ => return false
        }
    }
}

/** `.palette-search` backdrop. */
class PaletteSearchBackdrop <: Widget {
    private let tokens: ThemeTokens
    private var frame = Rect.zero()

    init(tokens: ThemeTokens) {
        this.tokens = tokens
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(max(available.w, 0.0), max(available.h, 0.0))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        fillRound(ctx, frame, tokens.radius.md, tokens.color.surface2)
        strokeRound(ctx, frame, tokens.radius.md, CHROME_BORDER, tokens.color.border)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        return false
    }
}

/** Transparent editor styling so the TextField sits inside `.palette-search`. */
func paletteSearchStyle(tokens: ThemeTokens): TextInputStyle {
    let c = tokens.color
    let transparent = Color.rgba(0, 0, 0, 0)
    return TextInputStyle(
        lineHeight: vp(21.0),
        padding: LengthInsets(Length(0.0, LengthUnit.Vp), Length(0.0, LengthUnit.Vp)),
        textColor: c.text,
        placeholderColor: c.textFaint,
        cursorColor: c.accent,
        surface: SurfaceStyle(transparent, border: transparent, radius: 0.0, borderWidth: 0.0),
        focusedSurface: SurfaceStyle(transparent, border: transparent, radius: 0.0, borderWidth: 0.0)
    )
}

/** `.palette-group` heading (10.5px/600, .08em tracking, faint). */
class PaletteGroupView <: Widget {
    private let tokens: ThemeTokens
    private let text: String
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, text: String) {
        this.tokens = tokens
        this.text = text
        emit(this)
    }

    public func measure(ctx: UiContext, _: Size): Size {
        Size(trackedWidth(ctx, text, fpSize(ctx, 10.5), 600, fpSize(ctx, 10.5) * 0.08), PALETTE_GROUP_HEIGHT)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func isFlexible(): Bool {
        return false
    }

    public func draw(ctx: UiContext): Unit {
        textTracked(ctx, text, frame.x, frame.y + 8.0 + lineBox(10.5) / 2.0, tokens.color.textFaint,
            fpSize(ctx, 10.5), 600, fpSize(ctx, 10.5) * 0.08)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        return false
    }
}

func okrPatchFor(period: String): OkrPatch {
    let patch = OkrPatch()
    patch.period = SetValue<String>.Value(period)
    patch
}

/** Builds the palette's action list for the current workspace/theme. */
public func paletteActions(host: ShellHost): Array<PaletteAction> {
    let store = host.store
    let workspace = store.state.value()
    let ui = store.ui.value()
    let period = ui.okrPeriod
    let objectives = objectivesOfPeriod(workspace, period)
    let firstObjective: ?Item = if (objectives.isEmpty()) {
        None
    } else {
        Some(objectives[0])
    }
    let actions = ArrayList<PaletteAction>()
    actions.add(
        PaletteAction("new-sop", "新建 SOP", "创建流程并打开画布", IconGlyph.Workflow, ["流程", "新建"], false,
            {=>
                let item = store.createItem(NewItemInput(ItemKind.Sop, "未命名 SOP", status: Some(ItemStatus.Active)))
                store.select(item.id)
                store.setUi({state =>
                    state.route = "sop"
                    state.paletteOpen = false
                })
                store.notify("SOP 已创建，去画布添加步骤吧", tone: NoticeTone.Success)
            })
    )
    actions.add(
        PaletteAction("new-objective", "新建目标", "周期 ${period}", IconGlyph.Target, ["okr", "目标", "新建"], false,
            {=>
                let item = store.createItem(NewItemInput(ItemKind.Objective, "新的目标",
                    status: Some(ItemStatus.Active), okr: Some(okrPatchFor(period))))
                store.select(item.id)
                store.setUi({state =>
                    state.route = "okr"
                    state.okrPeriod = period
                    state.paletteOpen = false
                })
                store.notify("目标已创建，接着添加关键结果吧", tone: NoticeTone.Success)
            })
    )
    let krHint = match (firstObjective) {
        case Some(value) => "归属「${value.title}」"
        case None => "需要先创建目标"
    }
    actions.add(
        PaletteAction("new-keyresult", "新建 KR", krHint, IconGlyph.Flag, ["关键结果", "okr", "新建"],
            firstObjective.isNone(), {=>
                match (firstObjective) {
                    case Some(objective) =>
                        let krPeriod = match (objective.okr) {
                            case Some(value) => value.period
                            case None => period
                        }
                        let item = store.createItem(NewItemInput(ItemKind.KeyResult, "新的关键结果",
                            parentId: Some(objective.id), status: Some(ItemStatus.Active),
                            okr: Some(okrPatchFor(krPeriod))))
                        store.select(item.id)
                        store.setUi({state =>
                            state.route = "okr"
                            state.okrPeriod = krPeriod
                            state.paletteOpen = false
                        })
                        store.notify("关键结果已创建", tone: NoticeTone.Success)
                    case None => store.notify("先创建一个目标，再添加关键结果", tone: NoticeTone.Error)
                }
            })
    )
    actions.add(
        PaletteAction("quick-capture", "快速收集", "收集到 GTD 收件箱", IconGlyph.Plus, ["收集", "inbox"], false,
            {=> host.openCapture()})
    )
    let isDark = host.themeName() == "dark"
    actions.add(
        PaletteAction("toggle-theme", if (isDark) {
            "切换到浅色主题"
        } else {
            "切换到深色主题"
        }, "外观", if (isDark) {
            IconGlyph.Sun
        } else {
            IconGlyph.Moon
        }, ["深色", "浅色", "dark", "light"], false, {=> host.toggleTheme()})
    )
    actions.add(
        PaletteAction("undo", "撤销", "⌘/Ctrl + Z", IconGlyph.ChevronLeft, ["undo", "回退"], !store.canUndo(),
            {=>
                store.undo()
                store.setUi({state => state.paletteOpen = false})
                store.notify("已撤销上一步", tone: NoticeTone.Success)
            })
    )
    actions.add(
        PaletteAction("redo", "重做", "⌘/Ctrl + ⇧ + Z", IconGlyph.ChevronRight, ["redo"], !store.canRedo(),
            {=>
                store.redo()
                store.setUi({state => state.paletteOpen = false})
                store.notify("已重做一步", tone: NoticeTone.Success)
            })
    )
    actions.add(
        PaletteAction("export", "导出工作区", "JSON 备份文件", IconGlyph.Folder, ["备份", "json", "export"], false,
            {=> host.exportWorkspace()})
    )
    actions.add(
        PaletteAction("open-settings", "打开设置", "存储、备份与关于", IconGlyph.Settings, ["偏好", "settings"], false,
            {=>
                store.setUi({state =>
                    state.route = "settings"
                    state.paletteOpen = false
                })
            })
    )
    for (route in ROUTES) {
        let target = route
        actions.add(
            PaletteAction("route:${routeId(target)}", "前往${routeLabel(target)}", routeSubtitle(target),
                routeGlyph(target), [routeLabel(target), routeId(target)], false,
                {=>
                    store.setUi({state =>
                        state.route = routeId(target)
                        state.paletteOpen = false
                    })
                })
        )
    }
    actions.toArray()
}

func findAction(source: Array<PaletteAction>, id: String): ?PaletteAction {
    for (action in source) {
        if (action.id == id) {
            return Some(action)
        }
    }
    None
}

func findItem(source: Workspace, id: String): ?Item {
    for (item in source.items) {
        if (item.id == id) {
            return Some(item)
        }
    }
    None
}

func findArea(source: Workspace, id: String): ?Area {
    for (area in source.areas) {
        if (area.id == id) {
            return Some(area)
        }
    }
    None
}

/** `buildPaletteResults` over the live workspace (CommandPalette.tsx:164-465). */
public func paletteRows(host: ShellHost, query: String): Array<PaletteRow> {
    let store = host.store
    let workspace = store.state.value()
    let actions = paletteActions(host)
    let hasQuery = !query.trimAscii().isEmpty()
    let recent = host.runtime.prefs.recent
    let rows = ArrayList<PaletteRow>()

    let commandCandidates = ArrayList<PaletteCommandCandidate>()
    for (action in actions) {
        commandCandidates.add(PaletteCommandCandidate(action.id, action.label, action.hint, action.keywords))
    }
    let itemCandidates = ArrayList<PaletteItemCandidate>()
    if (!hasQuery) {
        for (ref in recent) {
            if (ref.refType != "item") {
                continue
            }
            match (findItem(workspace, ref.id)) {
                case Some(item) =>
                    itemCandidates.add(PaletteItemCandidate(item.id, item.title, item.kind, [], []))
                case None => ()
            }
        }
    } else {
        for (item in workspace.items) {
            itemCandidates.add(
                PaletteItemCandidate(item.id, item.title, item.kind, item.tags, itemPathTitles(workspace, item.id)))
        }
    }
    let areaCandidates = ArrayList<PaletteAreaCandidate>()
    for (area in workspace.areas) {
        areaCandidates.add(PaletteAreaCandidate(area.id, area.name))
    }
    let results = buildPaletteResults(query, commandCandidates.toArray(), itemCandidates.toArray(),
        areaCandidates.toArray(), recent)

    // 1) recent rows (empty query only) — CommandPalette.tsx:414-426
    for (ref in results.recent) {
        match (ref.refType) {
            case "command" =>
                match (findAction(actions, ref.id)) {
                    case Some(action) =>
                        let captured = action
                        rows.add(
                            PaletteRow("recent:command:${ref.id}", "最近使用", action.label, action.hint,
                                action.glyph, false, ref.refType, ref.id,
                                {=>
                                    host.rememberPaletteRef(PaletteRecentRef("command", captured.id))
                                    captured.run()
                                }))
                    case None => ()
                }
            case "item" =>
                match (findItem(workspace, ref.id)) {
                    case Some(item) =>
                        let itemId = item.id
                        let title = item.title
                        let kind = item.kind
                        rows.add(
                            PaletteRow("recent:item:${itemId}", "最近使用", title,
                                "条目 · ${itemKindLabel(kind)}", kindGlyph(kind), false, ref.refType, itemId,
                                {=> host.runPaletteItem(itemId)}))
                    case None => ()
                }
            case _ =>
                match (findArea(workspace, ref.id)) {
                    case Some(area) =>
                        let areaId = area.id
                        let name = area.name
                        rows.add(
                            PaletteRow("recent:area:${areaId}", "最近使用", name, "领域", IconGlyph.Folder, false,
                                ref.refType, areaId, {=> host.runPaletteArea(areaId)}))
                    case None => ()
                }
        }
    }
    // 2) commands
    for (action in results.commands) {
        match (findAction(actions, action.id)) {
            case Some(found) =>
                let captured = found
                rows.add(
                    PaletteRow("command:${captured.id}", "命令", captured.label, captured.hint, captured.glyph,
                        captured.disabled, "command", captured.id,
                        {=>
                            host.rememberPaletteRef(PaletteRecentRef("command", captured.id))
                            captured.run()
                        }))
            case None => ()
        }
    }
    // 3) items
    for (ranked in results.items) {
        let candidate = ranked.candidate
        let hint = if (candidate.pathTitles.size > 1) {
            String.join(candidate.pathTitles[0..candidate.pathTitles.size - 1], delimiter: " / ")
        } else {
            itemKindLabel(candidate.kind)
        }
        let itemId = candidate.id
        let title = candidate.title
        let kind = candidate.kind
        rows.add(
            PaletteRow("item:${itemId}", "条目", title, hint, kindGlyph(kind), false, "item", itemId,
                {=> host.runPaletteItem(itemId)}))
    }
    // 4) areas
    for (area in results.areas) {
        let areaId = area.id
        let name = area.name
        rows.add(
            PaletteRow("area:${areaId}", "领域", name, "在 GTD 中筛选", IconGlyph.Folder, false, "area", areaId,
                {=> host.runPaletteArea(areaId)}))
    }
    rows.toArray()
}

/**
 * Command palette overlay. `query`/`active` are remembered states so typing and the
 * highlighted row survive CUI's per-frame rebuild; the modal itself is rebuilt each frame.
 */
public func buildCommandPalette(
    host: ShellHost,
    theme: Theme,
    open: Bool,
    query: State<String>,
    active: State<Int64>
): Unit {
    if (!open) {
        return
    }
    let tokens = tokensOf(theme)
    let c = tokens.color
    let rows = paletteRows(host, query.value)
    if (host.runtime.paletteQueryMemory != query.value) {
        host.runtime.paletteQueryMemory = query.value
        active.value = 0
    }
    let activeIndex = if (active.value >= Int64(rows.size) || active.value < 0) {
        Int64(0)
    } else {
        active.value
    }
    // Scroll height cap: `.palette-results { max-height: 360px }`.
    var contentHeight: Float32 = 0.0
    var lastGroup = ""
    for (row in rows) {
        if (row.group != lastGroup) {
            contentHeight += PALETTE_GROUP_HEIGHT
            lastGroup = row.group
        }
        contentHeight += PALETTE_ROW_HEIGHT + 1.0
    }
    let resultsHeight = if (rows.isEmpty()) {
        72.0f32
    } else {
        min(contentHeight, 360.0f32)
    }
    let presented = State<Bool>(true)

    Ui.modal(theme, presented, {=> host.closePalette()}, title: "命令面板", description: "搜索命令、条目与领域",
        width: 640.0, body: {=>
            VStack(spacing: vp(tokens.space.s3)) {
                ZStack {
                    PaletteSearchBackdrop(tokens)
                    HStack(spacing: vp(tokens.space.s2)) {
                        Ui.icon(theme, IconGlyph.Search, side: 16.0, color: c.textFaint)
                        EventHandler(onEvent: {ctx, event =>
                            handlePaletteKey(host, rows, active, activeIndex, ctx, event)
                        }) {
                            TextField(query, key: "palette-search")
                                .style(paletteSearchStyle(tokens))
                                .placeholder("输入命令、条目标题、标签或领域…")
                                .textStyle(TextStyle(fontSize: fp(14.0)))
                                .height(21.0)
                                .flex()
                        }.flex()
                        KeyChipView(tokens, "Esc", style: KeyChipStyle.Palette)
                    }.padding(12.0, 9.0).height(41.0).fillWidth()
                }.height(41.0).fillWidth()
                ScrollView(key: "palette-results") {
                    VStack(spacing: vp(1.0)) {
                        var previous = ""
                        var index = 0
                        while (index < rows.size) {
                            let rowIndex = index
                            let row = rows[index]
                            if (row.group != previous) {
                                PaletteGroupView(tokens, row.group).fillWidth()
                                previous = row.group
                            }
                            PaletteRowView(tokens, row, activeIndex == rowIndex, query.value,
                                {=> if (!row.disabled) {
                                    active.value = rowIndex
                                }}, {=> host.runPaletteRow(row, active)}).fillWidth()
                            index += 1
                        }
                        if (rows.isEmpty()) {
                            Label("没有匹配的结果")
                                .fontSize(Length(12.5, LengthUnit.Fp))
                                .foregroundColor(c.textFaint)
                                .textAlign(TextAlign.Center)
                                .fillWidth()
                                .padding(24.0, 24.0, 24.0, 24.0)
                        }
                    }.hug().fillWidth()
                }.height(resultsHeight)
                // .palette-footer { border-top 1px; padding-top 12; gap: 8px 16px; font-size 11px }
                Divider().foregroundColor(c.border)
                HStack(spacing: vp(16.0)) {
                    paletteFooterHint(tokens, ["↑", "↓"], "选择")
                    paletteFooterHint(tokens, ["Enter"], "执行")
                    paletteFooterHint(tokens, ["Tab"], "切换分组")
                    paletteFooterHint(tokens, ["Esc"], "关闭")
                    Spacer()
                    Label("⌘/Ctrl + K 开关面板").fontSize(Length(11.0, LengthUnit.Fp)).foregroundColor(c.textFaint)
                }.hug().fillWidth().padding(0.0, tokens.space.s3, 0.0, 0.0)
            }.hug().fillWidth()
        })
}

func paletteFooterHint(tokens: ThemeTokens, keys: Array<String>, label: String): Unit {
    HStack(spacing: vp(4.0)) {
        for (key in keys) {
            KeyChipView(tokens, key, style: KeyChipStyle.Palette)
        }
        Label(label).fontSize(Length(11.0, LengthUnit.Fp)).foregroundColor(tokens.color.textFaint)
    }.hug()
}

func handlePaletteKey(
    host: ShellHost,
    rows: Array<PaletteRow>,
    active: State<Int64>,
    activeIndex: Int64,
    ctx: UiContext,
    event: UiEvent
): Bool {
    match (event) {
        case UiEvent.KeyDown(key, isRepeat) =>
            if (isRepeat) {
                return false
            }
            match (key) {
                case Key.Down =>
                    movePaletteActive(rows, active, activeIndex, 1)
                    return true
                case Key.Up =>
                    movePaletteActive(rows, active, activeIndex, -1)
                    return true
                case Key.Enter =>
                    if (activeIndex >= 0 && activeIndex < Int64(rows.size)) {
                        host.runPaletteRow(rows[activeIndex], active)
                    }
                    return true
                case Key.Tab =>
                    jumpPaletteGroup(rows, active, activeIndex, if (ctx.eventModifiers().shift) {
                        -1
                    } else {
                        1
                    })
                    return true
                case _ => return false
            }
        case _ => return false
    }
}

func movePaletteActive(rows: Array<PaletteRow>, active: State<Int64>, activeIndex: Int64, direction: Int64): Unit {
    if (rows.isEmpty()) {
        return
    }
    var index = activeIndex
    var step = 0
    while (step < rows.size) {
        index = (index + direction + Int64(rows.size)) % Int64(rows.size)
        if (!rows[index].disabled) {
            active.value = index
            return
        }
        step += 1
    }
}

func jumpPaletteGroup(rows: Array<PaletteRow>, active: State<Int64>, activeIndex: Int64, direction: Int64): Unit {
    let groups = ArrayList<String>()
    for (row in rows) {
        if (!groups.contains(row.group)) {
            groups.add(row.group)
        }
    }
    if (groups.size < 2) {
        return
    }
    let current = if (activeIndex >= 0 && activeIndex < Int64(rows.size)) {
        rows[activeIndex].group
    } else {
        groups[0]
    }
    var start = 0
    var index = 0
    while (index < groups.size) {
        if (groups[index] == current) {
            start = index
        }
        index += 1
    }
    var step = 1
    while (step <= groups.size) {
        let position = floorModulo(Int64(start) + direction * Int64(step), Int64(groups.size))
        let group = groups[position]
        var rowIndex = 0
        while (rowIndex < rows.size) {
            if (rows[rowIndex].group == group && !rows[rowIndex].disabled) {
                active.value = Int64(rowIndex)
                return
            }
            rowIndex += 1
        }
        step += 1
    }
}
