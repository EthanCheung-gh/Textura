package textura.core.data

import std.collection.*
import std.fs.*
import std.random.*

/**
 * The single global store. Ported from `src/core/store.ts`.
 *
 * Contract for every view:
 * - there is exactly one fact source (`AppStore.state.value`);
 * - every write pushes an undo snapshot, produces a **new** `Workspace`, and
 *   bumps the revision, so "change once, all views update" holds;
 * - saving is explicit (`save()`) and atomic (temp file + rename), with failures
 *   surfaced as an error notice instead of being swallowed.
 *
 * Why not CUI's `State`? `textura.core.data` must not depend on `cui`
 * (`docs/STRUCTURE.md` §2). CUI re-describes the whole tree every frame, so
 * reading `state.value` per frame is already reactive; `StateCell` additionally
 * offers `revision()`/`subscribe()` for shells that want an explicit hook.
 */

/** Minimal observable cell (std-only stand-in for `cui.State`). */
public class StateCell<T> {
    private var current: T
    private var revisionCounter: Int64 = 0
    private var nextListenerId: Int64 = 0
    private let listeners: ArrayList<(Int64, (T) -> Unit)>

    public init(initial: T) {
        this.current = initial
        this.listeners = ArrayList<(Int64, (T) -> Unit)>()
    }

    public func value(): T {
        current
    }

    public func revision(): Int64 {
        revisionCounter
    }

    public func set(next: T): Unit {
        current = next
        revisionCounter += 1
        for ((_, listener) in listeners.toArray()) {
            listener(next)
        }
    }

    /** Returns a listener id usable with `unsubscribe`. */
    public func subscribe(listener: (T) -> Unit): Int64 {
        let id = nextListenerId
        nextListenerId += 1
        listeners.add((id, listener))
        id
    }

    public func unsubscribe(id: Int64): Unit {
        var position = 0
        while (position < listeners.size) {
            let (listenerId, _) = listeners[position]
            if (listenerId == id) {
                listeners.remove(at: position)
                break
            }
            position += 1
        }
    }
}

/* ------------------------------------------------------------------ */
/* UI state                                                            */
/* ------------------------------------------------------------------ */

public let THEME_LIGHT: String = "light"
public let THEME_DARK: String = "dark"

/** Route ids in sidebar order; mirrors `ROUTE_IDS` in `src/core/routeState.ts`. */
public let ROUTE_IDS: Array<String> = [
    "dashboard", "calendar", "okr", "gtd", "gantt", "sop", "settings"
]

public func isRouteId(value: String): Bool {
    for (candidate in ROUTE_IDS) {
        if (candidate == value) {
            return true
        }
    }
    false
}

/** `?route=okr` -> `okr`; missing/invalid -> None. */
public func routeFromSearch(search: String): ?String {
    match (queryParam(search, "route")) {
        case Some(value) => if (isRouteId(value)) {
            Some(value)
        } else {
            None
        }
        case None => None
    }
}

/** `?item=obj_activation` -> `obj_activation`; blank -> None. */
public func itemIdFromSearch(search: String): ?String {
    match (queryParam(search, "item")) {
        case Some(value) => if (value.trimAscii().isEmpty()) {
            None
        } else {
            Some(value.trimAscii())
        }
        case None => None
    }
}

/** Startup route priority: valid deep link > remembered route > dashboard. */
public func resolveInitialRoute(search: String, stored: ?String): String {
    match (routeFromSearch(search)) {
        case Some(value) => return value
        case None => ()
    }
    match (stored) {
        case Some(value) => if (isRouteId(value)) {
            return value
        }
        case None => ()
    }
    "dashboard"
}

func queryParam(search: String, key: String): ?String {
    let trimmed = if (search.size > 0 && search[0] == UInt8(63)) {
        search[1..search.size]
    } else {
        search
    }
    for (pair in trimmed.split("&")) {
        if (pair.isEmpty()) {
            continue
        }
        let separator = pair.indexOf("=")
        match (separator) {
            case Some(index) =>
                if (pair[0..index] == key) {
                    return Some(pair[index + 1..pair.size])
                }
            case None => if (pair == key) {
                return Some("")
            }
        }
    }
    None
}

public class UiState {
    public var route: String = "dashboard"
    public var theme: String = THEME_LIGHT
    public var okrPeriod: String = ""
    public var ganttZoom: String = "week"
    public var gtdContext: ?String = None
    public var search: String = ""
    public var inspectorOpen: Bool = false
    public var paletteOpen: Bool = false
    public var quickCaptureOpen: Bool = false
    public var shortcutsOpen: Bool = false

    public init() {}

    public func clone(): UiState {
        let copy = UiState()
        copy.route = route
        copy.theme = theme
        copy.okrPeriod = okrPeriod
        copy.ganttZoom = ganttZoom
        copy.gtdContext = gtdContext
        copy.search = search
        copy.inspectorOpen = inspectorOpen
        copy.paletteOpen = paletteOpen
        copy.quickCaptureOpen = quickCaptureOpen
        copy.shortcutsOpen = shortcutsOpen
        copy
    }
}

public class Notice {
    public let id: String
    public let message: String
    public let tone: NoticeTone
    public let at: String

    public init(id: String, message: String, tone: NoticeTone, at: String) {
        this.id = id
        this.message = message
        this.tone = tone
        this.at = at
    }
}

public enum SaveState {
    | Idle
    | Saving
    | Saved
    | Error

    public operator func ==(right: SaveState): Bool {
        saveStateWire(this) == saveStateWire(right)
    }

    public operator func !=(right: SaveState): Bool {
        saveStateWire(this) != saveStateWire(right)
    }
}

public func saveStateWire(value: SaveState): String {
    match (value) {
        case SaveState.Idle => "idle"
        case SaveState.Saving => "saving"
        case SaveState.Saved => "saved"
        case SaveState.Error => "error"
    }
}

public enum StoreStatus {
    | Loading
    | Ready
    | Error

    public operator func ==(right: StoreStatus): Bool {
        storeStatusWire(this) == storeStatusWire(right)
    }

    public operator func !=(right: StoreStatus): Bool {
        storeStatusWire(this) != storeStatusWire(right)
    }
}

public func storeStatusWire(value: StoreStatus): String {
    match (value) {
        case StoreStatus.Loading => "loading"
        case StoreStatus.Ready => "ready"
        case StoreStatus.Error => "error"
    }
}

/* ------------------------------------------------------------------ */
/* Patches                                                             */
/* ------------------------------------------------------------------ */

/** Presence-aware field: `Unset` keeps the current value, `Value` overwrites it. */
public enum SetValue<T> {
    | Unset
    | Value(T)

    public func isSet(): Bool {
        match (this) {
            case SetValue.Unset => false
            case SetValue.Value(_) => true
        }
    }
}

public class MetricPatch {
    public var start: SetValue<Float64> = SetValue<Float64>.Unset
    public var target: SetValue<Float64> = SetValue<Float64>.Unset
    public var current: SetValue<Float64> = SetValue<Float64>.Unset
    public var unit: SetValue<String> = SetValue<String>.Unset

    public init() {}
}

public class OkrPatch {
    public var period: SetValue<String> = SetValue<String>.Unset
    public var confidence: SetValue<Int64> = SetValue<Int64>.Unset
    public var metric: ?MetricPatch = None
    public var krOwner: SetValue<?String> = SetValue<?String>.Unset

    public init() {}
}

public class SopPatch {
    public var nodeType: SetValue<SopNodeType> = SetValue<SopNodeType>.Unset
    public var canvasX: SetValue<Float64> = SetValue<Float64>.Unset
    public var canvasY: SetValue<Float64> = SetValue<Float64>.Unset
    public var checklist: SetValue<Array<ChecklistEntry>> = SetValue<Array<ChecklistEntry>>.Unset
    public var owner: SetValue<?String> = SetValue<?String>.Unset
    public var durationMin: SetValue<?Int64> = SetValue<?Int64>.Unset

    public init() {}
}

public class GtdPatch {
    public var capturedAt: SetValue<String> = SetValue<String>.Unset
    public var clarified: SetValue<Bool> = SetValue<Bool>.Unset
    public var context: SetValue<?String> = SetValue<?String>.Unset
    public var energy: SetValue<?Energy> = SetValue<?Energy>.Unset
    public var waitingFor: SetValue<?String> = SetValue<?String>.Unset
    public var twoMinuteCandidate: SetValue<?Bool> = SetValue<?Bool>.Unset

    public init() {}
}

public class GanttPatch {
    public var start: SetValue<?String> = SetValue<?String>.Unset
    public var end: SetValue<?String> = SetValue<?String>.Unset
    public var progress: SetValue<Float64> = SetValue<Float64>.Unset

    public init() {}
}

/**
 * Patch for `updateItem`. Mirrors `ItemPatch` in `src/core/model.ts`:
 * unset fields are ignored (they never clear a value), the four data blocks are
 * merged shallowly, and `updatedAt` is always refreshed.
 */
public class ItemPatch {
    public var title: SetValue<String> = SetValue<String>.Unset
    public var notes: SetValue<String> = SetValue<String>.Unset
    public var parentId: SetValue<?String> = SetValue<?String>.Unset
    public var order: SetValue<Int64> = SetValue<Int64>.Unset
    public var status: SetValue<ItemStatus> = SetValue<ItemStatus>.Unset
    public var tags: SetValue<Array<String>> = SetValue<Array<String>>.Unset
    public var areaId: SetValue<?String> = SetValue<?String>.Unset
    public var completedAt: SetValue<?String> = SetValue<?String>.Unset
    public var okr: ?OkrPatch = None
    public var sop: ?SopPatch = None
    public var gtd: ?GtdPatch = None
    public var gantt: ?GanttPatch = None

    public init() {}

    public func withTitle(value: String): ItemPatch {
        title = SetValue<String>.Value(value)
        this
    }

    public func withNotes(value: String): ItemPatch {
        notes = SetValue<String>.Value(value)
        this
    }

    public func withParentId(value: ?String): ItemPatch {
        parentId = SetValue<?String>.Value(value)
        this
    }

    public func withOrder(value: Int64): ItemPatch {
        order = SetValue<Int64>.Value(value)
        this
    }

    public func withStatus(value: ItemStatus): ItemPatch {
        status = SetValue<ItemStatus>.Value(value)
        this
    }

    public func withTags(value: Array<String>): ItemPatch {
        tags = SetValue<Array<String>>.Value(value)
        this
    }

    public func withAreaId(value: ?String): ItemPatch {
        areaId = SetValue<?String>.Value(value)
        this
    }

    public func withOkr(value: OkrPatch): ItemPatch {
        okr = Some(value)
        this
    }

    public func withSop(value: SopPatch): ItemPatch {
        sop = Some(value)
        this
    }

    public func withGtd(value: GtdPatch): ItemPatch {
        gtd = Some(value)
        this
    }

    public func withGantt(value: GanttPatch): ItemPatch {
        gantt = Some(value)
        this
    }

    /** Convenience: only the gantt progress. */
    public func withProgress(value: Float64): ItemPatch {
        let ganttPatch = GanttPatch()
        ganttPatch.progress = SetValue<Float64>.Value(value)
        gantt = Some(ganttPatch)
        this
    }

    /** Convenience: only the due date (`gantt.end`). */
    public func withDueDate(value: ?String): ItemPatch {
        let ganttPatch = GanttPatch()
        ganttPatch.end = SetValue<?String>.Value(value)
        gantt = Some(ganttPatch)
        this
    }

    /** Convenience: both gantt ends (either may be null to clear). */
    public func withGanttRange(start: ?String, end: ?String): ItemPatch {
        let ganttPatch = GanttPatch()
        ganttPatch.start = SetValue<?String>.Value(start)
        ganttPatch.end = SetValue<?String>.Value(end)
        gantt = Some(ganttPatch)
        this
    }
}

/** Input for `createItem`; everything except kind/title has a default. */
public class NewItemInput {
    public let kind: ItemKind
    public let title: String
    public let notes: String
    public let parentId: ?String
    public let status: ?ItemStatus
    public let tags: Array<String>
    public let areaId: ?String
    public let order: ?Int64
    public let okr: ?OkrPatch
    public let sop: ?SopPatch
    public let gtd: ?GtdPatch
    public let gantt: ?GanttPatch

    public init(
        kind: ItemKind,
        title: String,
        notes!: String = "",
        parentId!: ?String = None,
        status!: ?ItemStatus = None,
        tags!: Array<String> = [],
        areaId!: ?String = None,
        order!: ?Int64 = None,
        okr!: ?OkrPatch = None,
        sop!: ?SopPatch = None,
        gtd!: ?GtdPatch = None,
        gantt!: ?GanttPatch = None
    ) {
        this.kind = kind
        this.title = title
        this.notes = notes
        this.parentId = parentId
        this.status = status
        this.tags = tags
        this.areaId = areaId
        this.order = order
        this.okr = okr
        this.sop = sop
        this.gtd = gtd
        this.gantt = gantt
    }
}

public class ItemPatchTarget {
    public let id: String
    public let patch: ItemPatch

    public init(id: String, patch: ItemPatch) {
        this.id = id
        this.patch = patch
    }
}

/* ------------------------------------------------------------------ */
/* Undo / redo                                                         */
/* ------------------------------------------------------------------ */

public let DEFAULT_HISTORY_LIMIT: Int64 = 80

class HistoryStack {
    let limit: Int64
    let past: ArrayList<Workspace>
    let future: ArrayList<Workspace>

    init(limit: Int64) {
        this.limit = limit
        this.past = ArrayList<Workspace>()
        this.future = ArrayList<Workspace>()
    }

    func record(current: Workspace): Unit {
        if (past.size >= limit) {
            past.remove(at: 0)
        }
        past.add(current)
        future.clear()
    }

    func undo(current: Workspace): ?Workspace {
        if (past.isEmpty()) {
            return None
        }
        let previous = past.remove(at: past.size - 1)
        if (future.size >= limit) {
            future.remove(at: 0)
        }
        future.add(current)
        Some(previous)
    }

    func redo(current: Workspace): ?Workspace {
        if (future.isEmpty()) {
            return None
        }
        let next = future.remove(at: future.size - 1)
        if (past.size >= limit) {
            past.remove(at: 0)
        }
        past.add(current)
        Some(next)
    }

    func canUndo(): Bool {
        !past.isEmpty()
    }

    func canRedo(): Bool {
        !future.isEmpty()
    }

    func clearRedo(): Unit {
        future.clear()
    }

    func clear(): Unit {
        past.clear()
        future.clear()
    }

    func size(): Int64 {
        past.size
    }
}

/* ------------------------------------------------------------------ */
/* View entry point                                                    */
/* ------------------------------------------------------------------ */

/**
 * Everything a view needs from the shell. Views may not import `textura.shell`,
 * so this is the only bridge: each view package exposes
 * `public func render(ctx: ViewContext): Unit`, called by the shell inside its
 * CUI declaration block. `today` is the frozen parity anchor (workspace
 * `updatedAt` or `--today`), never the system clock.
 */
public class ViewContext {
    public let store: AppStore
    /** "light" | "dark" */
    public let theme: String
    /** "YYYY-MM-DD" */
    public let today: String
    public let width: Int64
    public let height: Int64
    /** Route-level navigation requested from inside a view. */
    public let navigate: (String) -> Unit

    public init(
        store: AppStore,
        theme: String,
        today: String,
        width: Int64,
        height: Int64,
        navigate: (String) -> Unit
    ) {
        this.store = store
        this.theme = theme
        this.today = today
        this.width = width
        this.height = height
        this.navigate = navigate
    }
}

/* ------------------------------------------------------------------ */
/* Store                                                               */
/* ------------------------------------------------------------------ */

public class AppStore {
    public let state: StateCell<Workspace>
    public let ui: StateCell<UiState>
    public let notices: StateCell<Array<Notice>>
    public let selectedId: StateCell<?String>
    public let clock: Clock

    private let random = Random()
    private let history = HistoryStack(DEFAULT_HISTORY_LIMIT)
    private var status: StoreStatus = StoreStatus.Loading
    private var saveState: SaveState = SaveState.Idle
    private var lastError: ?String = None
    private var lastSaveBytes: Int64 = 0
    private var workspacePath: ?String = None
    private var initialised: Bool = false
    /** Parity freeze: when set, "today" comes from here, never from `clock`. */
    private var todayOverride: ?String = None

    /**
     * `clock` is a required argument on purpose: a store must never silently fall
     * back to the wall clock, because the parity snapshot has to stay reproducible.
     * Use [AppStore.forParity] for snapshot runs and `SystemClock()` for interactive runs.
     */
    public init(clock!: Clock, todayOverride!: ?String = None) {
        this.clock = clock
        this.todayOverride = todayOverride
        this.state = StateCell<Workspace>(emptyWorkspace(clock))
        // Cannot call `anchorQuarter()` yet: the remaining fields are still unset.
        let initialAnchor = match (todayOverride) {
            case Some(value) => value
            case None => localDateKey(clock.nowMillis())
        }
        let initialUi = UiState()
        initialUi.okrPeriod = match (quarterOfDateKey(initialAnchor)) {
            case Some(value) => value
            case None => ""
        }
        this.ui = StateCell<UiState>(initialUi)
        this.notices = StateCell<Array<Notice>>([])
        this.selectedId = StateCell<?String>(None)
    }

    /**
     * Parity construction path: freezes both the clock (at local midnight of
     * `anchorDate`) and "today". This is what `main.cj` uses when the anchor comes
     * from `workspace.updatedAt` or `--today`, so the current quarter, relative
     * dates and any written timestamp all follow the workspace instead of the host
     * wall clock.
     *
     * Throws when the anchor is not an ISO date: silence here would let a snapshot
     * drift to the system clock, which is exactly what parity forbids.
     */
    public static func forParity(anchorDate: String): AppStore {
        let millis = match (parseIsoMillis(anchorDate)) {
            case Some(value) => value
            case None => throw IllegalArgumentException("parity 锚点日期无法解析：${anchorDate}")
        }
        AppStore(clock: FixedClock(millis), todayOverride: Some(anchorDate))
    }

    /* ---------------- reads ---------------- */

    /** Current workspace snapshot (immutable value). */
    public func workspace(): Workspace {
        state.value()
    }

    public func revision(): Int64 {
        state.revision()
    }

    public func storeStatus(): StoreStatus {
        status
    }

    public func saveStatus(): SaveState {
        saveState
    }

    public func error(): ?String {
        lastError
    }

    public func savedBytes(): Int64 {
        lastSaveBytes
    }

    public func path(): ?String {
        workspacePath
    }

    /**
     * The store's "today":
     * - parity/store-frozen: the explicit `todayOverride` (= `--today` or the
     *   workspace `updatedAt` date), regardless of the host clock;
     * - interactive: the injected clock's local date.
     */
    public func anchorToday(): String {
        match (todayOverride) {
            case Some(value) => value
            case None => localDateKey(clock.nowMillis())
        }
    }

    /** Freeze "today" explicitly (the CLI `--today` override). */
    public func setTodayOverride(today: ?String): Unit {
        todayOverride = today
        setUi({state => state.okrPeriod = anchorQuarter()})
    }

    /** Quarter of the anchor date; empty string when the anchor is unparsable. */
    func anchorQuarter(): String {
        match (quarterOfDateKey(anchorToday())) {
            case Some(value) => value
            case None => ""
        }
    }

    public func canUndo(): Bool {
        history.canUndo()
    }

    public func canRedo(): Bool {
        history.canRedo()
    }

    public func historySteps(): Int64 {
        history.size()
    }

    public func historyLimit(): Int64 {
        history.limit
    }

    public func select(id: ?String): Unit {
        selectedId.set(id)
    }

    public func selected(): ?Item {
        match (selectedId.value()) {
            case Some(id) => itemById(workspace(), id)
            case None => None
        }
    }

    /* ---------------- notices ---------------- */

    public func notify(message: String, tone!: NoticeTone = NoticeTone.Info): Notice {
        let notice = Notice(uid("notice", random), message, tone, nowIso(clock))
        let existing = notices.value()
        let kept = ArrayList<Notice>()
        for (entry in existing) {
            kept.add(entry)
        }
        kept.add(notice)
        while (kept.size > 4) {
            kept.remove(at: 0)
        }
        notices.set(kept.toArray())
        notice
    }

    public func dismissNotice(id: String): Unit {
        let kept = ArrayList<Notice>()
        for (entry in notices.value()) {
            if (entry.id != id) {
                kept.add(entry)
            }
        }
        notices.set(kept.toArray())
    }

    public func clearNotices(): Unit {
        notices.set([])
    }

    /* ---------------- loading ---------------- */

    /** Loads `path`; a missing/blank file is a fresh install (seeds demo data). */
    public func load(path: String): Unit {
        workspacePath = Some(path)
        let loaded = loadWorkspaceFromPath(path, clock)
        var next = loaded.workspace
        let isBlank = next.items.isEmpty() && next.areas.isEmpty() && next.runs.isEmpty()
        if (isBlank && loaded.freshInstall) {
            next = createSeedWorkspace(clock)
            persist(next, false)
        }
        history.clear()
        status = StoreStatus.Ready
        saveState = SaveState.Idle
        lastError = None
        let currentUi = ui.value().clone()
        currentUi.okrPeriod = initialOkrPeriod(next, anchorToday())
        ui.set(currentUi)
        state.set(next)
        selectedId.set(None)
        notifyCorrections(loaded.corrections)
        if (!loaded.parentCycles.isEmpty()) {
            let labels = cycleLabels(next, loaded.parentCycles)
            let saved = saveRepairedCopy(next)
            notify(
                "检测到父子环（${loaded.parentCycles.size} 处：${labels}），已自动切断 parentId；" +
                "修复副本：${saved}。原始文件未被覆盖；下次编辑会写回修复结果。",
                tone: NoticeTone.Error
            )
        }
    }

    /** Loads from an in-memory document (tests, clipboard import). */
    public func loadFromText(text: String): Bool {
        try {
            let loaded = normalizeForLoad(parseJson(text), clock)
            history.clear()
            status = StoreStatus.Ready
            saveState = SaveState.Idle
            lastError = None
            let currentUi = ui.value().clone()
            currentUi.okrPeriod = initialOkrPeriod(loaded.workspace, anchorToday())
            ui.set(currentUi)
            state.set(loaded.workspace)
            notifyCorrections(loaded.corrections)
            true
        } catch (error: Exception) {
            status = StoreStatus.Error
            lastError = error.message
            notify("工作区无法读取：${error.message}", tone: NoticeTone.Error)
            false
        }
    }

    public func reload(): Unit {
        match (workspacePath) {
            case Some(path) => load(path)
            case None => notify("尚未指定工作区路径，无法重新加载", tone: NoticeTone.Error)
        }
    }

    func notifyCorrections(summary: CorrectionSummary): Unit {
        if (summary.total == 0) {
            return
        }
        notify("已修正 ${summary.total} 处非法数据（详见日志）", tone: NoticeTone.Info)
    }

    /* ---------------- saving ---------------- */

    /**
     * Atomic save: write `<path>.tmp`, then rename over the target. A failure
     * keeps the previous document intact and posts an error notice.
     */
    public func save(): Bool {
        if (status != StoreStatus.Ready) {
            return false
        }
        persist(workspace(), false)
    }

    public func saveTo(path: String): Bool {
        workspacePath = Some(path)
        persist(workspace(), false)
    }

    func persist(snapshot: Workspace, throwOnError: Bool): Bool {
        let path = match (workspacePath) {
            case Some(value) => value
            case None =>
                saveState = SaveState.Error
                lastError = Some("尚未指定工作区路径")
                notify("保存失败：尚未指定工作区路径", tone: NoticeTone.Error)
                return false
        }
        saveState = SaveState.Saving
        let document = encodeWorkspaceDocument(snapshot)
        let bytes = document.toArray()
        try {
            let temporary = "${path}.tmp"
            File.writeTo(temporary, bytes)
            rename(temporary, to: path, overwrite: true)
            saveState = SaveState.Saved
            lastSaveBytes = Int64(bytes.size)
            lastError = None
            true
        } catch (error: Exception) {
            saveState = SaveState.Error
            lastError = Some(error.message)
            notify("保存失败：${error.message}", tone: NoticeTone.Error)
            if (throwOnError) {
                throw error
            }
            false
        }
    }

    /**
     * Writes a diagnostic copy of a cycle-repaired workspace next to the main
     * document. The main file is never touched here.
     */
    func saveRepairedCopy(snapshot: Workspace): String {
        let path = match (workspacePath) {
            case Some(value) => value
            case None => return "保存失败"
        }
        let dot = path.lastIndexOf(".")
        let repaired = match (dot) {
            case Some(index) => "${path[0..index]}.repaired${path[index..path.size]}"
            case None => "${path}.repaired.json"
        }
        try {
            File.writeTo(repaired, encodeWorkspaceDocument(snapshot).toArray())
            repaired
        } catch (_: Exception) {
            "保存失败"
        }
    }

    /* ---------------- commit plumbing ---------------- */

    /** Records a snapshot, applies `recipe`, refreshes timestamps and notifies. */
    func commit(recipe: (Workspace) -> Workspace): Workspace {
        let current = workspace()
        history.record(current)
        let next = recipe(current).withUpdatedAt(nowIso(clock))
        state.set(next)
        saveState = SaveState.Idle
        lastError = None
        next
    }

    /* ---------------- item actions ---------------- */

    public func createItem(input: NewItemInput): Item {
        let current = workspace()
        let timestamp = nowIso(clock)
        let status = match (input.status) {
            case Some(value) => value
            case None => if (input.kind == ItemKind.Note || input.kind == ItemKind.Reference) {
                ItemStatus.Inbox
            } else {
                ItemStatus.Next
            }
        }
        let parentId = input.parentId
        let order = match (input.order) {
            case Some(value) => value
            case None => nextSiblingOrder(current, parentId)
        }
        var okr: ?OkrData = None
        if (input.kind == ItemKind.Objective || input.kind == ItemKind.KeyResult) {
            let patch = input.okr
            let period = takeText(patch, {value => value.period}, currentQuarter(clock))
            let confidence = takeConfidence(patch, 5)
            let metric: ?Metric = match (patch) {
                case Some(value) => match (value.metric) {
                    case Some(metricPatch) => Some(applyMetricPatch(None, metricPatch))
                    case None => None
                }
                case None => None
            }
            okr = Some(OkrData(period, confidence, metric: metric))
        }
        var sop: ?SopData = None
        if (input.kind == ItemKind.Sop || input.kind == ItemKind.Step) {
            sop = Some(applySopPatch(None, input.sop))
        }
        var gantt: ?GanttData = None
        if (input.kind == ItemKind.Action || input.kind == ItemKind.Project) {
            gantt = Some(applyGanttPatch(None, input.gantt))
        }
        var gtd: ?GtdData = None
        if (input.kind == ItemKind.Action) {
            let patch = input.gtd
            let capturedAt = takeText(patch, {value => value.capturedAt}, timestamp)
            let clarified = takeBool(patch, {value => value.clarified}, status != ItemStatus.Inbox)
            gtd = Some(GtdData(
                capturedAt,
                clarified,
                context: takeOptionalText(patch, {value => value.context}),
                energy: takeOptionalEnergy(patch),
                waitingFor: takeOptionalText(patch, {value => value.waitingFor}),
                twoMinuteCandidate: takeOptionalBool(patch, {value => value.twoMinuteCandidate})
            ))
        } else {
            match (input.gtd) {
                case Some(patch) =>
                    let capturedAt = takeText(Some(patch), {value => value.capturedAt}, timestamp)
                    let clarified = takeBool(Some(patch), {value => value.clarified}, true)
                    gtd = Some(GtdData(
                        capturedAt,
                        clarified,
                        context: takeOptionalText(Some(patch), {value => value.context}),
                        energy: takeOptionalEnergy(Some(patch)),
                        waitingFor: takeOptionalText(Some(patch), {value => value.waitingFor}),
                        twoMinuteCandidate: takeOptionalBool(Some(patch), {value => value.twoMinuteCandidate})
                    ))
                case None => ()
            }
        }
        let item = Item(
            uid(itemKindPrefix(input.kind), random),
            input.kind,
            input.title,
            notes: input.notes,
            parentId: parentId,
            order: order,
            status: status,
            tags: input.tags,
            areaId: input.areaId,
            createdAt: timestamp,
            updatedAt: timestamp,
            completedAt: if (status == ItemStatus.Done) {
                Some(timestamp)
            } else {
                None
            },
            okr: okr,
            sop: sop,
            gtd: gtd,
            gantt: gantt
        )
        commit({currentWorkspace => currentWorkspace.withItems(appendItem(currentWorkspace.items, item))})
        item
    }

    public func updateItem(id: String, patch: ItemPatch): Unit {
        let timestamp = nowIso(clock)
        commit({currentWorkspace =>
            let items = ArrayList<Item>()
            var found = false
            for (item in currentWorkspace.items) {
                if (item.id == id) {
                    items.add(applyItemPatch(item, patch, timestamp, clock))
                    found = true
                } else {
                    items.add(item)
                }
            }
            if (!found) {
                return currentWorkspace
            }
            currentWorkspace.withItems(items.toArray())
        })
    }

    public func updateItems(patches: Array<ItemPatchTarget>, recordHistory!: Bool = true): Unit {
        if (patches.isEmpty()) {
            return
        }
        let current = workspace()
        let targets = HashMap<String, ItemPatch>()
        for (target in patches) {
            match (itemById(current, target.id)) {
                case Some(_) => targets[target.id] = target.patch
                case None => ()
            }
        }
        if (targets.isEmpty()) {
            return
        }
        if (recordHistory) {
            history.record(current)
        } else {
            history.clearRedo()
        }
        let timestamp = nowIso(clock)
        let items = ArrayList<Item>()
        for (item in current.items) {
            match (targets.get(item.id)) {
                case Some(patch) => items.add(applyItemPatch(item, patch, timestamp, clock))
                case None => items.add(item)
            }
        }
        state.set(current.withItems(items.toArray()).withUpdatedAt(timestamp))
        saveState = SaveState.Idle
        lastError = None
    }

    public func deleteItems(ids: Array<String>): Unit {
        if (ids.isEmpty()) {
            return
        }
        let doomed = HashMap<String, Bool>()
        let queue = ArrayList<String>()
        for (id in ids) {
            doomed[id] = true
            queue.add(id)
        }
        let index = workspace().index()
        while (!queue.isEmpty()) {
            let parentId = queue.remove(at: queue.size - 1)
            for (child in itemsAt(index.children, parentId)) {
                match (doomed.get(child.id)) {
                    case Some(_) => continue
                    case None =>
                        doomed[child.id] = true
                        queue.add(child.id)
                }
            }
        }
        commit({currentWorkspace =>
            let keptItems = ArrayList<Item>()
            for (item in currentWorkspace.items) {
                match (doomed.get(item.id)) {
                    case Some(_) => ()
                    case None => keptItems.add(item)
                }
            }
            let keptEdges = ArrayList<Edge>()
            for (edge in currentWorkspace.edges) {
                if (doomed.get(edge.from).isNone() && doomed.get(edge.to).isNone()) {
                    keptEdges.add(edge)
                }
            }
            let keptRuns = ArrayList<SopRunEntry>()
            for (run in currentWorkspace.runs) {
                if (doomed.get(run.sopId).isNone() && doomed.get(run.stepId).isNone()) {
                    keptRuns.add(run)
                }
            }
            currentWorkspace
                .withItems(keptItems.toArray())
                .withEdges(keptEdges.toArray())
                .withRuns(keptRuns.toArray())
        })
        match (selectedId.value()) {
            case Some(id) => if (itemById(workspace(), id).isNone()) {
                selectedId.set(None)
            }
            case None => ()
        }
    }

    public func toggleDone(id: String): Unit {
        match (itemById(workspace(), id)) {
            case Some(item) => setStatus(id, if (item.status == ItemStatus.Done) {
                ItemStatus.Next
            } else {
                ItemStatus.Done
            })
            case None => ()
        }
    }

    public func setStatus(id: String, status: ItemStatus): Unit {
        let timestamp = nowIso(clock)
        commit({currentWorkspace =>
            let items = ArrayList<Item>()
            for (item in currentWorkspace.items) {
                if (item.id == id) {
                    items.add(Item(
                        item.id,
                        item.kind,
                        item.title,
                        notes: item.notes,
                        parentId: item.parentId,
                        order: item.order,
                        status: status,
                        tags: item.tags,
                        areaId: item.areaId,
                        createdAt: item.createdAt,
                        updatedAt: timestamp,
                        completedAt: if (status == ItemStatus.Done) {
                            Some(timestamp)
                        } else {
                            None
                        },
                        okr: item.okr,
                        sop: item.sop,
                        gtd: item.gtd,
                        gantt: item.gantt,
                        extras: item.extras,
                        keyOrder: item.keyOrder
                    ))
                } else {
                    items.add(item)
                }
            }
            currentWorkspace.withItems(items.toArray())
        })
    }

    /**
     * Re-parents an item and renumbers siblings; refuses to move a node under
     * its own descendant.
     */
    public func moveItem(id: String, parentId: ?String, order: ?Int64): Unit {
        let timestamp = nowIso(clock)
        commit({currentWorkspace =>
            let index = currentWorkspace.index()
            let moving = match (index.byId.get(id)) {
                case Some(value) => value
                case None => return currentWorkspace
            }
            match (parentId) {
                case Some(targetParent) => if (targetParent == id) {
                    return currentWorkspace
                }
                case None => ()
            }
            match (parentId) {
                case Some(targetParent) =>
                    var cursor: ?String = Some(targetParent)
                    let seen = HashMap<String, Bool>()
                    while (true) {
                        match (cursor) {
                            case None => break
                            case Some(cursorId) =>
                                if (cursorId == id) {
                                    return currentWorkspace
                                }
                                match (seen.get(cursorId)) {
                                    case Some(_) => break
                                    case None => ()
                                }
                                seen[cursorId] = true
                                cursor = match (index.byId.get(cursorId)) {
                                    case Some(node) => node.parentId
                                    case None => None
                                }
                        }
                    }
                case None => ()
            }
            let oldParentId = moving.parentId
            let updates = HashMap<String, Item>()
            updates[id] = Item(
                moving.id,
                moving.kind,
                moving.title,
                notes: moving.notes,
                parentId: parentId,
                order: moving.order,
                status: moving.status,
                tags: moving.tags,
                areaId: moving.areaId,
                createdAt: moving.createdAt,
                updatedAt: timestamp,
                completedAt: moving.completedAt,
                okr: moving.okr,
                sop: moving.sop,
                gtd: moving.gtd,
                gantt: moving.gantt,
                extras: moving.extras,
                keyOrder: moving.keyOrder
            )
            renumberSiblings(index, parentId, id, order, updates, true)
            if (!sameParent(oldParentId, parentId)) {
                renumberSiblings(index, oldParentId, id, None, updates, false)
            }
            let items = ArrayList<Item>()
            for (item in currentWorkspace.items) {
                match (updates.get(item.id)) {
                    case Some(replacement) => items.add(replacement)
                    case None => items.add(item)
                }
            }
            currentWorkspace.withItems(items.toArray())
        })
    }

    /* ---------------- edges ---------------- */

    /** Returns the existing edge when the same (from,to,type) already exists. */
    public func createEdge(from: String, to: String, edgeType: EdgeType, label!: String = ""): Edge {
        let current = workspace()
        for (edge in current.edges) {
            if (edge.from == from && edge.to == to && edge.edgeType == edgeType) {
                return edge
            }
        }
        let edge = Edge(uid("edge", random), from, to, edgeType, label: label)
        commit({currentWorkspace => currentWorkspace.withEdges(appendEdge(currentWorkspace.edges, edge))})
        edge
    }

    public func updateEdge(id: String, label!: ?String = None): Unit {
        commit({currentWorkspace =>
            let edges = ArrayList<Edge>()
            for (edge in currentWorkspace.edges) {
                if (edge.id == id) {
                    let nextLabel = match (label) {
                        case Some(value) => value
                        case None => edge.label
                    }
                    edges.add(Edge(
                        edge.id,
                        edge.from,
                        edge.to,
                        edge.edgeType,
                        label: nextLabel,
                        extras: edge.extras,
                        keyOrder: edge.keyOrder
                    ))
                } else {
                    edges.add(edge)
                }
            }
            currentWorkspace.withEdges(edges.toArray())
        })
    }

    public func deleteEdge(id: String): Unit {
        commit({currentWorkspace =>
            let edges = ArrayList<Edge>()
            for (edge in currentWorkspace.edges) {
                if (edge.id != id) {
                    edges.add(edge)
                }
            }
            currentWorkspace.withEdges(edges.toArray())
        })
    }

    /** Adds a `depends` edge (gantt dependency). */
    public func addDependency(from: String, to: String, label!: String = ""): Edge {
        createEdge(from, to, EdgeType.Depends, label: label)
    }

    public func removeDependency(from: String, to: String): Unit {
        let current = workspace()
        let doomed = ArrayList<String>()
        for (edge in current.edges) {
            if (edge.edgeType == EdgeType.Depends && edge.from == from && edge.to == to) {
                doomed.add(edge.id)
            }
        }
        for (id in doomed) {
            deleteEdge(id)
        }
    }

    /* ---------------- areas ---------------- */

    public func createArea(name: String): Area {
        let current = workspace()
        var nextOrder = 0
        if (!current.areas.isEmpty()) {
            var maximum = current.areas[0].order
            for (area in current.areas) {
                if (area.order > maximum) {
                    maximum = area.order
                }
            }
            nextOrder = maximum + 1
        }
        let area = Area(uid("area", random), name, areaPalette(current.areas.size), order: nextOrder)
        commit({currentWorkspace => currentWorkspace.withAreas(appendArea(currentWorkspace.areas, area))})
        area
    }

    public func updateArea(id: String, name!: ?String = None, color!: ?String = None): Unit {
        commit({currentWorkspace =>
            let areas = ArrayList<Area>()
            for (area in currentWorkspace.areas) {
                if (area.id == id) {
                    let nextName = match (name) {
                        case Some(value) => value
                        case None => area.name
                    }
                    let nextColor = match (color) {
                        case Some(value) => value
                        case None => area.color
                    }
                    areas.add(Area(
                        area.id,
                        nextName,
                        nextColor,
                        order: area.order,
                        extras: area.extras,
                        keyOrder: area.keyOrder
                    ))
                } else {
                    areas.add(area)
                }
            }
            currentWorkspace.withAreas(areas.toArray())
        })
    }

    /** Deletes an area and detaches its items (`areaId` -> null). */
    public func deleteArea(id: String): Unit {
        commit({currentWorkspace =>
            let areas = ArrayList<Area>()
            for (area in currentWorkspace.areas) {
                if (area.id != id) {
                    areas.add(area)
                }
            }
            let items = ArrayList<Item>()
            for (item in currentWorkspace.items) {
                let matches = match (item.areaId) {
                    case Some(areaId) => areaId == id
                    case None => false
                }
                if (matches) {
                    items.add(replaceItem(item, areaId: SetValue<?String>.Value(None)))
                } else {
                    items.add(item)
                }
            }
            currentWorkspace.withAreas(areas.toArray()).withItems(items.toArray())
        })
    }

    /* ---------------- SOP runs ---------------- */

    public func logRun(sopId: String, stepId: String, result: RunResult, note!: String = ""): SopRunEntry {
        let run = SopRunEntry(uid("run", random), sopId, stepId, nowIso(clock), result, note: note)
        commit({currentWorkspace => currentWorkspace.withRuns(appendRun(currentWorkspace.runs, run))})
        run
    }

    /* ---------------- domain shortcuts ---------------- */

    /** Quick capture: an inbox action captured now, not yet clarified. */
    public func quickCapture(title: String, context!: ?String = None): Item {
        createItem(NewItemInput(
            ItemKind.Action,
            title,
            status: ItemStatus.Inbox,
            gtd: Some(quickCaptureGtd(context))
        ))
    }

    /** Schedules an item (either side may be null to clear it). */
    public func reschedule(id: String, start: ?String, end: ?String): Unit {
        let patch = ItemPatch()
        let gantt = GanttPatch()
        gantt.start = SetValue<?String>.Value(start)
        gantt.end = SetValue<?String>.Value(end)
        patch.gantt = Some(gantt)
        updateItem(id, patch)
    }

    public func setDueDate(id: String, due: ?String): Unit {
        let patch = ItemPatch()
        let gantt = GanttPatch()
        gantt.end = SetValue<?String>.Value(due)
        patch.gantt = Some(gantt)
        updateItem(id, patch)
    }

    public func setProgress(id: String, progress: Float64): Unit {
        let patch = ItemPatch()
        let gantt = GanttPatch()
        gantt.progress = SetValue<Float64>.Value(clampFloat(progress, 0.0, 100.0))
        patch.gantt = Some(gantt)
        updateItem(id, patch)
    }

    /** OKR metric update (start/target/current/unit in one call). */
    public func setMetric(id: String, start: Float64, target: Float64, current: Float64, unit: String): Unit {
        let patch = ItemPatch()
        let okr = OkrPatch()
        let metric = MetricPatch()
        metric.start = SetValue<Float64>.Value(start)
        metric.target = SetValue<Float64>.Value(target)
        metric.current = SetValue<Float64>.Value(current)
        metric.unit = SetValue<String>.Value(unit)
        okr.metric = Some(metric)
        patch.okr = Some(okr)
        updateItem(id, patch)
    }

    /** Only the `current` value of a KR metric (the common dashboard tweak). */
    public func setMetricCurrent(id: String, current: Float64): Unit {
        let patch = ItemPatch()
        let okr = OkrPatch()
        let metric = MetricPatch()
        metric.current = SetValue<Float64>.Value(current)
        okr.metric = Some(metric)
        patch.okr = Some(okr)
        updateItem(id, patch)
    }

    public func setConfidence(id: String, confidence: Int64): Unit {
        let patch = ItemPatch()
        let okr = OkrPatch()
        okr.confidence = SetValue<Int64>.Value(clampInt(confidence, 1, 10))
        patch.okr = Some(okr)
        updateItem(id, patch)
    }

    public func setOkrPeriod(id: String, period: String): Unit {
        let patch = ItemPatch()
        let okr = OkrPatch()
        okr.period = SetValue<String>.Value(period)
        patch.okr = Some(okr)
        updateItem(id, patch)
    }

    /** Links an execution item to a KR through an `okr` edge. */
    public func linkOkr(krId: String, itemId: String): Edge {
        createEdge(krId, itemId, EdgeType.Okr)
    }

    /**
     * Applies a clarification form: patch fields + target status in one history
     * step. Returns validation errors without mutating when the form is invalid.
     */
    public func clarify(id: String, form: ClarifyFormState): ?ClarifyErrors {
        let errors = validateClarifyForm(form)
        if (errors.hasError()) {
            return Some(errors)
        }
        let target = clarifyTargetStatus(form)
        updateItem(id, clarifyPatch(form))
        setStatus(id, target)
        if (target == ItemStatus.Done) {
            setProgress(id, 100.0)
        }
        None
    }

    /* ---------------- undo / redo ---------------- */

    public func undo(): Bool {
        match (history.undo(workspace())) {
            case Some(snapshot) =>
                state.set(snapshot.withUpdatedAt(nowIso(clock)))
                saveState = SaveState.Idle
                true
            case None => false
        }
    }

    public func redo(): Bool {
        match (history.redo(workspace())) {
            case Some(snapshot) =>
                state.set(snapshot.withUpdatedAt(nowIso(clock)))
                saveState = SaveState.Idle
                true
            case None => false
        }
    }

    /* ---------------- UI actions ---------------- */

    public func setUi(update: (UiState) -> Unit): Unit {
        let next = ui.value().clone()
        update(next)
        ui.set(next)
    }

    public func setRoute(route: String): Unit {
        if (!isRouteId(route)) {
            return
        }
        setUi({state => state.route = route})
    }

    public func setTheme(theme: String): Unit {
        if (theme != THEME_LIGHT && theme != THEME_DARK) {
            return
        }
        setUi({state => state.theme = theme})
    }

    public func toggleTheme(): Unit {
        setTheme(if (ui.value().theme == THEME_DARK) {
            THEME_LIGHT
        } else {
            THEME_DARK
        })
    }

    public func setSearch(text: String): Unit {
        setUi({state => state.search = text})
    }

    public func setOkrPeriod(period: String): Unit {
        setUi({state => state.okrPeriod = period})
    }

    public func setGanttZoom(zoom: String): Unit {
        setUi({state => state.ganttZoom = zoom})
    }

    public func setGtdContext(context: ?String): Unit {
        setUi({state => state.gtdContext = context})
    }

    /* ---------------- import / export ---------------- */

    /** Serialized document (pretty JSON + trailing newline), for export. */
    public func exportDocument(): String {
        encodeWorkspaceDocument(workspace())
    }

    /**
     * Strict import: unknown fields are kept, cycles are rejected. Returns the
     * error message on failure (nothing is mutated in that case).
     */
    public func importDocument(text: String): ?String {
        try {
            let migrated = migrateWorkspaceWithReport(parseJson(text), clock)
            let next = migrated.workspace.withUpdatedAt(nowIso(clock))
            history.record(workspace())
            state.set(next)
            selectedId.set(None)
            saveState = SaveState.Idle
            lastError = None
            let currentUi = ui.value().clone()
            currentUi.okrPeriod = initialOkrPeriod(next, anchorToday())
            ui.set(currentUi)
            notifyCorrections(migrated.corrections)
            persist(next, false)
            None
        } catch (error: Exception) {
            notify("导入失败：${error.message}", tone: NoticeTone.Error)
            Some(error.message)
        }
    }
}

/* ------------------------------------------------------------------ */
/* Patch application                                                   */
/* ------------------------------------------------------------------ */

func takeText(patch: ?OkrPatch, pick: (OkrPatch) -> SetValue<String>, fallback: String): String {
    match (patch) {
        case Some(value) => match (pick(value)) {
            case SetValue.Value(text) => text
            case SetValue.Unset => fallback
        }
        case None => fallback
    }
}

func takeText(patch: ?GtdPatch, pick: (GtdPatch) -> SetValue<String>, fallback: String): String {
    match (patch) {
        case Some(value) => match (pick(value)) {
            case SetValue.Value(text) => text
            case SetValue.Unset => fallback
        }
        case None => fallback
    }
}

func takeConfidence(patch: ?OkrPatch, fallback: Int64): Int64 {
    match (patch) {
        case Some(value) => match (value.confidence) {
            case SetValue.Value(confidence) => clampInt(confidence, 1, 10)
            case SetValue.Unset => fallback
        }
        case None => fallback
    }
}

func takeBool(patch: ?GtdPatch, pick: (GtdPatch) -> SetValue<Bool>, fallback: Bool): Bool {
    match (patch) {
        case Some(value) => match (pick(value)) {
            case SetValue.Value(flag) => flag
            case SetValue.Unset => fallback
        }
        case None => fallback
    }
}

func takeOptionalText(patch: ?GtdPatch, pick: (GtdPatch) -> SetValue<?String>): ?String {
    match (patch) {
        case Some(value) => match (pick(value)) {
            case SetValue.Value(text) => text
            case SetValue.Unset => None
        }
        case None => None
    }
}

func takeOptionalEnergy(patch: ?GtdPatch): ?Energy {
    match (patch) {
        case Some(value) => match (value.energy) {
            case SetValue.Value(energy) => energy
            case SetValue.Unset => None
        }
        case None => None
    }
}

func takeOptionalBool(patch: ?GtdPatch, pick: (GtdPatch) -> SetValue<?Bool>): ?Bool {
    match (patch) {
        case Some(value) => match (pick(value)) {
            case SetValue.Value(flag) => flag
            case SetValue.Unset => None
        }
        case None => None
    }
}

func itemKindPrefix(kind: ItemKind): String {
    let wire = itemKindWire(kind)
    if (wire.size <= 3) {
        wire
    } else {
        wire[0..3]
    }
}

func nextSiblingOrder(workspace: Workspace, parentId: ?String): Int64 {
    let siblings = childrenOf(workspace, parentId)
    if (siblings.isEmpty()) {
        return 0
    }
    var maximum = siblings[0].order
    for (item in siblings) {
        if (item.order > maximum) {
            maximum = item.order
        }
    }
    maximum + 1
}

func appendItem(items: Array<Item>, item: Item): Array<Item> {
    let next = ArrayList<Item>()
    for (entry in items) {
        next.add(entry)
    }
    next.add(item)
    next.toArray()
}

func appendEdge(edges: Array<Edge>, edge: Edge): Array<Edge> {
    let next = ArrayList<Edge>()
    for (entry in edges) {
        next.add(entry)
    }
    next.add(edge)
    next.toArray()
}

func appendArea(areas: Array<Area>, area: Area): Array<Area> {
    let next = ArrayList<Area>()
    for (entry in areas) {
        next.add(entry)
    }
    next.add(area)
    next.toArray()
}

func appendRun(runs: Array<SopRunEntry>, run: SopRunEntry): Array<SopRunEntry> {
    let next = ArrayList<SopRunEntry>()
    for (entry in runs) {
        next.add(entry)
    }
    next.add(run)
    next.toArray()
}

/** Copy of `item` with only `areaId` changed (keeps key order/extras). */
func replaceItem(item: Item, areaId!: SetValue<?String>): Item {
    let nextArea = match (areaId) {
        case SetValue.Value(value) => value
        case SetValue.Unset => item.areaId
    }
    Item(
        item.id,
        item.kind,
        item.title,
        notes: item.notes,
        parentId: item.parentId,
        order: item.order,
        status: item.status,
        tags: item.tags,
        areaId: nextArea,
        createdAt: item.createdAt,
        updatedAt: item.updatedAt,
        completedAt: item.completedAt,
        okr: item.okr,
        sop: item.sop,
        gtd: item.gtd,
        gantt: item.gantt,
        extras: item.extras,
        keyOrder: item.keyOrder
    )
}

func applyMetricPatch(base: ?Metric, patch: MetricPatch): Metric {
    let existing = match (base) {
        case Some(value) => value
        case None => Metric(0.0, 0.0, 0.0, "")
    }
    let start = match (patch.start) {
        case SetValue.Value(value) => value
        case SetValue.Unset => existing.start
    }
    let target = match (patch.target) {
        case SetValue.Value(value) => value
        case SetValue.Unset => existing.target
    }
    let current = match (patch.current) {
        case SetValue.Value(value) => value
        case SetValue.Unset => existing.current
    }
    let unit = match (patch.unit) {
        case SetValue.Value(value) => value
        case SetValue.Unset => existing.unit
    }
    Metric(start, target, current, unit)
}

/** Shallow merge of an SOP block (matches `applyItemPatch` in the Web store). */
func applySopPatch(base: ?SopData, patch: ?SopPatch): SopData {
    let existing = match (base) {
        case Some(value) => value
        case None => SopData(SopNodeType.Action)
    }
    var nodeType = existing.nodeType
    var canvasX = existing.canvas.x
    var canvasY = existing.canvas.y
    var checklist = existing.checklist
    var owner = existing.owner
    var duration = existing.durationMin
    match (patch) {
        case Some(value) =>
            match (value.nodeType) {
                case SetValue.Value(next) => nodeType = next
                case SetValue.Unset => ()
            }
            match (value.canvasX) {
                case SetValue.Value(next) => canvasX = next
                case SetValue.Unset => ()
            }
            match (value.canvasY) {
                case SetValue.Value(next) => canvasY = next
                case SetValue.Unset => ()
            }
            match (value.checklist) {
                case SetValue.Value(next) => checklist = next
                case SetValue.Unset => ()
            }
            match (value.owner) {
                case SetValue.Value(next) => owner = next
                case SetValue.Unset => ()
            }
            match (value.durationMin) {
                case SetValue.Value(next) => duration = next
                case SetValue.Unset => ()
            }
        case None => ()
    }
    SopData(nodeType, canvas: CanvasPos(canvasX, canvasY), checklist: checklist, owner: owner, durationMin: duration)
}

func applyGanttPatch(base: ?GanttData, patch: ?GanttPatch): GanttData {
    let existing = match (base) {
        case Some(value) => value
        case None => GanttData()
    }
    var start = existing.start
    var end = existing.end
    var progress = existing.progress
    match (patch) {
        case Some(value) =>
            match (value.start) {
                case SetValue.Value(next) => start = next
                case SetValue.Unset => ()
            }
            match (value.end) {
                case SetValue.Value(next) => end = next
                case SetValue.Unset => ()
            }
            match (value.progress) {
                case SetValue.Value(next) => progress = clampFloat(next, 0.0, 100.0)
                case SetValue.Unset => ()
            }
        case None => ()
    }
    GanttData(start: start, end: end, progress: progress)
}

func applyGtdPatch(base: ?GtdData, patch: ?GtdPatch, timestamp: String): GtdData {
    let existing = match (base) {
        case Some(value) => value
        case None => GtdData(timestamp, true)
    }
    var capturedAt = existing.capturedAt
    var clarified = existing.clarified
    var context = existing.context
    var energy = existing.energy
    var waitingFor = existing.waitingFor
    var twoMinute = existing.twoMinuteCandidate
    match (patch) {
        case Some(value) =>
            match (value.capturedAt) {
                case SetValue.Value(next) => capturedAt = next
                case SetValue.Unset => ()
            }
            match (value.clarified) {
                case SetValue.Value(next) => clarified = next
                case SetValue.Unset => ()
            }
            match (value.context) {
                case SetValue.Value(next) => context = next
                case SetValue.Unset => ()
            }
            match (value.energy) {
                case SetValue.Value(next) => energy = next
                case SetValue.Unset => ()
            }
            match (value.waitingFor) {
                case SetValue.Value(next) => waitingFor = next
                case SetValue.Unset => ()
            }
            match (value.twoMinuteCandidate) {
                case SetValue.Value(next) => twoMinute = next
                case SetValue.Unset => ()
            }
        case None => ()
    }
    GtdData(capturedAt, clarified, context: context, energy: energy, waitingFor: waitingFor, twoMinuteCandidate: twoMinute)
}

func applyOkrPatch(base: ?OkrData, patch: ?OkrPatch, clock: Clock): ?OkrData {
    let existing = match (base) {
        case Some(value) => value
        case None => OkrData(currentQuarter(clock), 5)
    }
    var period = existing.period
    var confidence = existing.confidence
    var metric = existing.metric
    var owner = existing.krOwner
    match (patch) {
        case Some(value) =>
            match (value.period) {
                case SetValue.Value(next) => period = next
                case SetValue.Unset => ()
            }
            match (value.confidence) {
                case SetValue.Value(next) => confidence = clampInt(next, 1, 10)
                case SetValue.Unset => ()
            }
            match (value.metric) {
                case Some(metricPatch) => metric = Some(applyMetricPatch(metric, metricPatch))
                case None => ()
            }
            match (value.krOwner) {
                case SetValue.Value(next) => owner = next
                case SetValue.Unset => ()
            }
        case None => ()
    }
    match (base) {
        case None => if (patch.isNone()) {
            return None
        }
        case Some(_) => ()
    }
    Some(OkrData(period, confidence, metric: metric, krOwner: owner))
}

/**
 * `updateItem` semantics:
 * - only set fields are copied; `updatedAt` always refreshes;
 * - a status change also rewrites `completedAt`;
 * - the four data blocks merge shallowly onto the existing values.
 */
public func applyItemPatch(item: Item, patch: ItemPatch, timestamp: String, clock: Clock): Item {
    let nextStatus = match (patch.status) {
        case SetValue.Value(value) => value
        case SetValue.Unset => item.status
    }
    var completedAt = match (patch.completedAt) {
        case SetValue.Value(value) => value
        case SetValue.Unset => item.completedAt
    }
    match (patch.status) {
        case SetValue.Value(value) => if (value != item.status) {
            completedAt = if (value == ItemStatus.Done) {
                Some(timestamp)
            } else {
                None
            }
        }
        case SetValue.Unset => ()
    }
    Item(
        item.id,
        item.kind,
        takeString(patch.title, item.title),
        notes: takeString(patch.notes, item.notes),
        parentId: takeOptional(patch.parentId, item.parentId),
        order: takeInt(patch.order, item.order),
        status: nextStatus,
        tags: takeTags(patch.tags, item.tags),
        areaId: takeOptional(patch.areaId, item.areaId),
        createdAt: item.createdAt,
        updatedAt: timestamp,
        completedAt: completedAt,
        okr: applyOkrPatch(item.okr, patch.okr, clock),
        sop: match (patch.sop) {
            case Some(sopPatch) => Some(applySopPatch(item.sop, Some(sopPatch)))
            case None => item.sop
        },
        gtd: match (patch.gtd) {
            case Some(gtdPatch) => Some(applyGtdPatch(item.gtd, Some(gtdPatch), timestamp))
            case None => item.gtd
        },
        gantt: match (patch.gantt) {
            case Some(ganttPatch) => Some(applyGanttPatch(item.gantt, Some(ganttPatch)))
            case None => item.gantt
        },
        extras: item.extras,
        keyOrder: item.keyOrder
    )
}

func takeString(value: SetValue<String>, fallback: String): String {
    match (value) {
        case SetValue.Value(next) => next
        case SetValue.Unset => fallback
    }
}

func takeInt(value: SetValue<Int64>, fallback: Int64): Int64 {
    match (value) {
        case SetValue.Value(next) => next
        case SetValue.Unset => fallback
    }
}

func takeOptional(value: SetValue<?String>, fallback: ?String): ?String {
    match (value) {
        case SetValue.Value(next) => next
        case SetValue.Unset => fallback
    }
}

func takeTags(value: SetValue<Array<String>>, fallback: Array<String>): Array<String> {
    match (value) {
        case SetValue.Value(next) => next
        case SetValue.Unset => fallback
    }
}

func sameParent(left: ?String, right: ?String): Bool {
    match (left) {
        case Some(leftId) => match (right) {
            case Some(rightId) => leftId == rightId
            case None => false
        }
        case None => match (right) {
            case Some(_) => false
            case None => true
        }
    }
}

func renumberSiblings(
    index: WorkspaceIndex,
    parentId: ?String,
    movingId: String,
    insertOrder: ?Int64,
    updates: HashMap<String, Item>,
    insertMoved: Bool
): Unit {
    let siblings = ArrayList<Item>()
    for (child in childrenOfItems(index, parentId)) {
        if (child.id != movingId) {
            siblings.add(child)
        }
    }
    if (insertMoved) {
        let insertAt = match (insertOrder) {
            case Some(value) => clampInt(value, 0, siblings.size)
            case None => siblings.size
        }
        match (updates.get(movingId)) {
            case Some(moved) =>
                siblings.add(Item(
                    moved.id,
                    moved.kind,
                    moved.title,
                    notes: moved.notes,
                    parentId: parentId,
                    order: insertAt,
                    status: moved.status,
                    tags: moved.tags,
                    areaId: moved.areaId,
                    createdAt: moved.createdAt,
                    updatedAt: moved.updatedAt,
                    completedAt: moved.completedAt,
                    okr: moved.okr,
                    sop: moved.sop,
                    gtd: moved.gtd,
                    gantt: moved.gantt,
                    extras: moved.extras,
                    keyOrder: moved.keyOrder
                ), at: insertAt)
            case None => ()
        }
    }
    for (position in 0..siblings.size) {
        let sibling = siblings[position]
        // The moved node is rewritten even when its order happens to match, so
        // the caller's earlier placeholder (old order/parent) is replaced.
        if (sibling.order != position || (insertMoved && sibling.id == movingId)) {
            updates[sibling.id] = Item(
                sibling.id,
                sibling.kind,
                sibling.title,
                notes: sibling.notes,
                parentId: sibling.parentId,
                order: position,
                status: sibling.status,
                tags: sibling.tags,
                areaId: sibling.areaId,
                createdAt: sibling.createdAt,
                updatedAt: sibling.updatedAt,
                completedAt: sibling.completedAt,
                okr: sibling.okr,
                sop: sibling.sop,
                gtd: sibling.gtd,
                gantt: sibling.gantt,
                extras: sibling.extras,
                keyOrder: sibling.keyOrder
            )
        }
    }
}

func childrenOfItems(index: WorkspaceIndex, parentId: ?String): Array<Item> {
    let key = match (parentId) {
        case Some(value) => value
        case None => ROOT_KEY
    }
    itemsAt(index.children, key)
}

func quickCaptureGtd(context: ?String): GtdPatch {
    let patch = GtdPatch()
    patch.clarified = SetValue<Bool>.Value(false)
    patch.context = SetValue<?String>.Value(context)
    patch
}

func clarifyPatch(form: ClarifyFormState): ItemPatch {
    let patch = ItemPatch()
    patch.title = SetValue<String>.Value(form.title.trimAscii())
    patch.notes = SetValue<String>.Value(form.notes)
    patch.tags = SetValue<Array<String>>.Value(parseTags(form.tags))
    patch.areaId = SetValue<?String>.Value(if (form.areaId.isEmpty()) {
        None
    } else {
        Some(form.areaId)
    })
    let gantt = GanttPatch()
    gantt.end = SetValue<?String>.Value(if (form.dueDate.isEmpty()) {
        None
    } else {
        Some(form.dueDate)
    })
    patch.gantt = Some(gantt)
    let gtd = GtdPatch()
    gtd.clarified = SetValue<Bool>.Value(true)
    gtd.context = SetValue<?String>.Value(Some(resolveFormContext(form)))
    gtd.energy = SetValue<?Energy>.Value(Some(form.energy))
    gtd.waitingFor = SetValue<?String>.Value(if (form.delegated) {
        Some(form.waitingFor.trimAscii())
    } else {
        Some("")
    })
    let twoMinute = form.twoMinuteCandidate || match (form.estimateMin) {
        case Some(value) => value == 2
        case None => false
    }
    gtd.twoMinuteCandidate = SetValue<?Bool>.Value(Some(twoMinute))
    patch.gtd = Some(gtd)
    patch
}

/**
 * Which OKR period a view should open on, with the Web rule (`store.ts`):
 * the "current" quarter when the workspace has it, else the newest period,
 * else the current quarter itself.
 *
 * "Current" is the **anchor date**, not the host clock: in a parity run that is
 * `--today` / the workspace `updatedAt` date, so a snapshot taken on a different
 * day (or a fixture with several quarters) still opens the reference quarter.
 */
public func initialOkrPeriod(workspace: Workspace, today: String): String {
    let quarter = match (quarterOfDateKey(today)) {
        case Some(value) => value
        case None => ""
    }
    let periods = okrPeriods(workspace)
    for (period in periods) {
        if (period == quarter) {
            return quarter
        }
    }
    if (periods.isEmpty()) {
        quarter
    } else {
        periods[0]
    }
}

/** Clock-based variant; non-parity (a frozen anchor should be passed instead). */
public func initialOkrPeriod(workspace: Workspace, clock: Clock): String {
    initialOkrPeriod(workspace, localDateKey(clock.nowMillis()))
}
