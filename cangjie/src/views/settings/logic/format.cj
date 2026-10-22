package textura.views.settings.logic

import textura.core.data.*

/*
 * Pure helpers for the settings page. Ported from
 * `src/modules/appshell/{importValidation.ts,workspaceIO.ts}` and the local
 * `formatSize()` in `SettingsPage.tsx:21-25`.
 *
 * Everything here is side-effect free so the view can call it during the
 * declarative build (once per frame) without touching the store or the disk.
 */

/** `ImportSummary` of `importValidation.ts:13-19` (the confirmation dialog table). */
public struct ImportSummary {
    public let items: Int64
    public let areas: Int64
    public let edges: Int64
    public let runs: Int64
    public let version: Int64

    public init(items!: Int64, areas!: Int64, edges!: Int64, runs!: Int64, version!: Int64) {
        this.items = items
        this.areas = areas
        this.edges = edges
        this.runs = runs
        this.version = version
    }

    /** `importSummary.items === 0 && areas === 0 && runs === 0` (empty-file warning). */
    public func isEmptyWorkspace(): Bool {
        items == 0 && areas == 0 && runs == 0
    }

    /** "30 条记录 · 3 个领域 · 3 条 SOP 运行记录" — `SettingsPage.tsx:400-401`. */
    public func countsText(): String {
        "${items} 条记录 · ${areas} 个领域 · ${runs} 条 SOP 运行记录"
    }
}

/** Result of validating an import document before the destructive confirmation. */
public struct ImportParse {
    public let workspace: ?Workspace
    public let error: String

    public init(workspace!: ?Workspace, error!: String) {
        this.workspace = workspace
        this.error = error
    }

    public func ok(): Bool {
        match (workspace) {
            case Some(_) => true
            case None => false
        }
    }
}

/** `summarizeImport()` — `importValidation.ts:48-55`. */
public func summarizeImport(workspace: Workspace): ImportSummary {
    ImportSummary(
        items: Int64(workspace.items.size),
        areas: Int64(workspace.areas.size),
        edges: Int64(workspace.edges.size),
        runs: Int64(workspace.runs.size),
        version: workspace.version
    )
}

/** `parseImportText()` — `importValidation.ts:34-45`, strict (cycles are errors). */
public func parseImportText(text: String, clock: Clock): ImportParse {
    var parsed: ?JsonValue = None
    try {
        parsed = Some(parseJson(text))
    } catch (_: JsonError) {
        return ImportParse(workspace: None, error: "文件不是合法的 JSON")
    } catch (error: Exception) {
        return ImportParse(workspace: None, error: error.message)
    }
    let value = match (parsed) {
        case Some(item) => item
        case None => return ImportParse(workspace: None, error: "文件不是合法的 JSON")
    }
    if (!isWorkspaceShape(value)) {
        return ImportParse(workspace: None, error: "不是 Textura 工作区文件：缺少 items / areas / runs 等集合字段")
    }
    try {
        let migrated = migrateWorkspaceWithReport(value, clock)
        ImportParse(workspace: Some(migrated.workspace), error: "")
    } catch (error: Exception) {
        ImportParse(workspace: None, error: error.message)
    }
}

/**
 * `isWorkspaceShape()` — `importValidation.ts:22-31`.
 *
 * `parseWorkspaceText` is deliberately forgiving (`{"foo":1}` becomes an empty
 * workspace), so a destructive import requires at least one collection field and
 * correct types for every field that is present.
 */
public func isWorkspaceShape(value: JsonValue): Bool {
    match (value) {
        case JsonObject(fields) =>
            var present: Int64 = 0
            var typesOk = true
            for ((key, field) in fields) {
                if (key == "items" || key == "edges" || key == "areas" || key == "runs") {
                    present += 1
                    match (field) {
                        case JsonArray(_) => ()
                        case _ => typesOk = false
                    }
                } else if (key == "version") {
                    match (field) {
                        case JsonInt(_) => ()
                        case JsonFloat(_) => ()
                        case _ => typesOk = false
                    }
                } else if (key == "updatedAt") {
                    match (field) {
                        case JsonString(_) => ()
                        case _ => typesOk = false
                    }
                }
            }
            present > 0 && typesOk
        case _ => false
    }
}

/** `formatSize()` — `SettingsPage.tsx:21-25` (`B` below 1024, one decimal of KB above). */
public func formatSize(bytes: Int64): String {
    if (bytes < 0) {
        return "—"
    }
    if (bytes < 1024) {
        return "${bytes} B"
    }
    let tenths = roundHalfUp(Float64(bytes) / 1024.0 * 10.0)
    "${tenths / 10}.${tenths % 10} KB"
}

/** Parent directory of a path, used for the "数据目录" row (`dirname` equivalent). */
public func parentDirectory(path: String): String {
    match (path.lastIndexOf("/")) {
        case Some(index) =>
            if (index <= 0) {
                "/"
            } else {
                path[0..index]
            }
        case None => ""
    }
}

/** `defaultExportName()` — `workspaceIO.ts:13-15`, driven by the injected clock. */
public func exportFileName(clock: Clock): String {
    "textura-workspace-${formatWithPattern(clock.nowMillis(), "yyyyMMdd-HHmm")}.json"
}

/** Import drop-box used by the desktop fallback: `<workspace dir>/textura-import.json`. */
public func importFileName(): String {
    "textura-import.json"
}

/** `formatDateTime()` for the last-write row; invalid values render as "—". */
public func lastWriteText(updatedAt: String): String {
    formatDateTime(Some(updatedAt))
}

/** Byte size of the document that `store.save()` would write (UTF-8, pretty JSON + "\n"). */
public func documentBytes(workspace: Workspace): Int64 {
    Int64(encodeWorkspaceDocument(workspace).toArray().size)
}
