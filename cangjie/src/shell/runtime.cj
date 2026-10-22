package textura.shell

import std.collection.*
import std.env.*
import std.fs.*
import cui.*
import textura.core.data.*

/*
 * Shell-side session state that is not part of `AppStore`:
 *
 *   - the throttled autosave state machine (`idle/saving/saved/error`),
 *   - notice lifetimes (the Web build dismisses toasts on a timer),
 *   - the quick-capture session list (undo the last captured item),
 *   - route/theme/palette-recent persistence (`localStorage` in the Web build).
 *
 * `core.data` has no timer and no storage beyond the workspace document, so these live
 * here. Nothing in this file reads the wall clock: deadlines run on `UiEvent.Frame`'s
 * elapsed milliseconds, and the parity CLI never mutates the workspace, so snapshots
 * stay byte-identical between runs.
 */

/** One row of "本次会话已收集" (QuickCapture.tsx). */
public class CaptureEntry {
    public let id: String
    public let title: String
    public let tags: Array<String>
    public let context: ?String
    public let energy: ?Energy
    public let date: ?String

    public init(id: String, title: String, tags: Array<String>, context: ?String, energy: ?Energy, date: ?String) {
        this.id = id
        this.title = title
        this.tags = tags
        this.context = context
        this.energy = energy
        this.date = date
    }
}

public let SAVE_IDLE: String = "idle"
public let SAVE_SAVING: String = "saving"
public let SAVE_SAVED: String = "saved"
public let SAVE_ERROR: String = "error"

/** `Sidebar.tsx` SAVE_LABELS. */
public func saveStateLabel(state: String): String {
    match (state) {
        case "idle" => "自动保存已开启"
        case "saving" => "正在保存…"
        case "saved" => "已保存"
        case "error" => "保存失败"
        case _ => "自动保存已开启"
    }
}

/** Web autosave debounce is 400ms (`store.ts`); the saved flash lasts 1.4s. */
public let SAVE_DEBOUNCE_MS: Int64 = 400
public let SAVE_FLASH_MS: Int64 = 1400
/** Toast lifetime used by the shell (the Web `notices` layer auto-dismisses). */
public let NOTICE_LIFETIME_MS: Int64 = 5000

/**
 * `localStorage` replacement for the desktop build:
 * `$HOME/.textura/ui-prefs.json` keeps the last route, theme and palette recents.
 * It is only written in interactive mode — `--snapshot` runs never touch it.
 */
public class ShellPreferences {
    public var route: String = ""
    public var theme: String = ""
    public var recent: Array<PaletteRecentRef> = []
    public let path: String

    private init(path: String) {
        this.path = path
    }

    public static func load(): ShellPreferences {
        let prefs = ShellPreferences(preferencesPath())
        try {
            let text = String.fromUtf8(File.readFrom(prefs.path))
            match (parseJson(text)) {
                case JsonValue.JsonObject(entries) =>
                    for ((key, value) in entries) {
                        match (key) {
                            case "route" =>
                                match (value) {
                                    case JsonValue.JsonString(text) => prefs.route = text
                                    case _ => ()
                                }
                            case "theme" =>
                                match (value) {
                                    case JsonValue.JsonString(text) => prefs.theme = text
                                    case _ => ()
                                }
                            case "recent" =>
                                match (value) {
                                    case JsonValue.JsonArray(rows) => prefs.recent = parseRecentRows(rows)
                                    case _ => ()
                                }
                            case _ => ()
                        }
                    }
                case _ => ()
            }
        } catch (_: Exception) {
            // Missing/corrupt preferences fall back to the CLI defaults.
        }
        prefs
    }

    public func persist(): Unit {
        let recentRows = ArrayList<JsonValue>()
        for (ref in recent) {
            recentRows.add(
                JsonValue.JsonObject([
                    ("type", JsonValue.JsonString(ref.refType)),
                    ("id", JsonValue.JsonString(ref.id))
                ])
            )
        }
        let document = JsonValue.JsonObject([
            ("route", JsonValue.JsonString(route)),
            ("theme", JsonValue.JsonString(theme)),
            ("recent", JsonValue.JsonArray(recentRows.toArray()))
        ])
        try {
            let parent = match (path.lastIndexOf("/")) {
                case Some(index) => path[0..index]
                case None => "."
            }
            if (!parent.isEmpty()) {
                Directory.create(parent, recursive: true)
            }
            File.writeTo(path, writeJson(document).toArray())
        } catch (_: Exception) {
            // Preferences are a convenience; a read-only HOME must not break the shell.
        }
    }
}

func preferencesPath(): String {
    match (getVariable("HOME")) {
        case Some(home) => "${home}/.textura/ui-prefs.json"
        case None => ".textura-ui-prefs.json"
    }
}

func parseRecentRows(rows: Array<JsonValue>): Array<PaletteRecentRef> {
    let refs = ArrayList<PaletteRecentRef>()
    for (row in rows) {
        match (row) {
            case JsonValue.JsonObject(entries) =>
                var refType = ""
                var id = ""
                for ((key, value) in entries) {
                    match (key) {
                        case "type" =>
                            match (value) {
                                case JsonValue.JsonString(text) => refType = text
                                case _ => ()
                            }
                        case "id" =>
                            match (value) {
                                case JsonValue.JsonString(text) => id = text
                                case _ => ()
                            }
                        case _ => ()
                    }
                }
                if (!refType.isEmpty() && !id.isEmpty() && Int64(refs.size) < RECENT_LIMIT) {
                    refs.add(PaletteRecentRef(refType, id))
                }
            case _ => ()
        }
    }
    refs.toArray()
}

/** Mutable per-run shell state shared by every builder in this package. */
public class ShellRuntime {
    public var elapsedMs: Int64 = 0
    public var savePhase: String = SAVE_IDLE
    public var saveDeadline: Int64 = -1
    public var savedUntil: Int64 = -1
    public var lastRevision: Int64 = 0
    public var lastPersistedRoute: String = ""
    public var lastPersistedTheme: String = ""
    /** Command-palette query of the previous build; a change resets the highlighted row. */
    public var paletteQueryMemory: String = ""
    public var captureSession: ArrayList<CaptureEntry> = ArrayList<CaptureEntry>()
    public let prefs: ShellPreferences
    private var noticeDeadlines: ArrayList<(String, Int64)> = ArrayList<(String, Int64)>()

    public init(prefs: ShellPreferences, store: AppStore) {
        this.prefs = prefs
        this.lastRevision = store.revision()
    }

    /** Called once per build: bootstraps the debounce when the workspace changed. */
    public func observeWorkspace(store: AppStore): Unit {
        let revision = store.revision()
        if (store.storeStatus() == StoreStatus.Ready && revision != lastRevision) {
            lastRevision = revision
            savePhase = SAVE_SAVING
            saveDeadline = elapsedMs + SAVE_DEBOUNCE_MS
        }
        if (store.saveStatus() == SaveState.Error) {
            savePhase = SAVE_ERROR
        }
    }

    /** Keeps one deadline per visible notice; drops rows that disappeared. */
    public func observeNotices(store: AppStore): Unit {
        let notices = store.notices.value()
        let next = ArrayList<(String, Int64)>()
        for (notice in notices) {
            var deadline = elapsedMs + NOTICE_LIFETIME_MS
            for ((id, at) in noticeDeadlines) {
                if (id == notice.id) {
                    deadline = at
                }
            }
            next.add((notice.id, deadline))
        }
        noticeDeadlines = next
    }

    /** True while the shell needs frame callbacks (autosave flash / toast lifetime). */
    public func needsTick(store: AppStore): Bool {
        if (savePhase == SAVE_SAVING || savePhase == SAVE_SAVED) {
            return true
        }
        !store.notices.value().isEmpty()
    }

    /** `FrameHandler` callback: advance the autosave state machine and expire notices. */
    public func tick(store: AppStore, info: FrameInfo): Unit {
        elapsedMs = Int64(info.elapsedMs)
        if (savePhase == SAVE_SAVING && elapsedMs >= saveDeadline) {
            if (store.save()) {
                savePhase = SAVE_SAVED
            } else {
                savePhase = SAVE_ERROR
            }
            savedUntil = elapsedMs + SAVE_FLASH_MS
        } else if (savePhase == SAVE_SAVED && elapsedMs >= savedUntil) {
            savePhase = SAVE_IDLE
        }
        let notices = store.notices.value()
        for ((id, deadline) in noticeDeadlines) {
            if (elapsedMs >= deadline) {
                var alive = false
                for (notice in notices) {
                    if (notice.id == id) {
                        alive = true
                    }
                }
                if (alive) {
                    store.dismissNotice(id)
                }
            }
        }
    }

    /** Persists route/theme changes and the palette recents list (interactive only). */
    public func persistUi(route: String, theme: String, enabled: Bool): Unit {
        if (!enabled) {
            return
        }
        if (route == lastPersistedRoute && theme == lastPersistedTheme) {
            return
        }
        lastPersistedRoute = route
        lastPersistedTheme = theme
        prefs.route = route
        prefs.theme = theme
        prefs.persist()
    }

    public func rememberRecent(ref: PaletteRecentRef, enabled: Bool): Unit {
        prefs.recent = pushRecentRef(ref, prefs.recent)
        if (enabled) {
            prefs.persist()
        }
    }
}
