package textura.core.data

import std.collection.*
import std.convert.*
import std.fs.*

/**
 * Workspace <-> JSON, ported from `src/core/repo.ts`.
 *
 * Two paths, matching the Web build:
 * - `migrateWorkspace*` (strict) for imports: field normalization + reject
 *   parent/child cycles;
 * - `normalizeForLoad` for loading: same normalization but cycles are cut with a
 *   warning instead of failing, so dirty data never blanks the app.
 *
 * Serialization is byte-compatible with `JSON.stringify(workspace, null, 2)`:
 * object keys keep the order they had on disk (canonical order for fresh
 * objects), optional blocks are omitted when absent, and numbers use the
 * JavaScript shortest form.
 */

public let MAX_CORRECTION_ENTRIES: Int64 = 20

public class WorkspaceVersionError <: Exception {
    public let version: Int64

    public init(version: Int64) {
        super("工作区版本 ${version} 高于当前应用支持的版本 ${WORKSPACE_VERSION}，请升级 Textura 后再打开。")
        this.version = version
    }
}

public class NormalizationCorrection {
    public let itemId: ?String
    public let field: String
    public let from: String
    public let to: String

    public init(itemId: ?String, field: String, from: String, to: String) {
        this.itemId = itemId
        this.field = field
        this.from = from
        this.to = to
    }
}

public class CorrectionSummary {
    public let total: Int64
    public let entries: Array<NormalizationCorrection>

    public init(total: Int64, entries: Array<NormalizationCorrection>) {
        this.total = total
        this.entries = entries
    }

    public static func empty(): CorrectionSummary {
        CorrectionSummary(0, [])
    }
}

public func mergeCorrectionSummaries(first: CorrectionSummary, second: CorrectionSummary): CorrectionSummary {
    let merged = ArrayList<NormalizationCorrection>()
    for (entry in first.entries) {
        if (merged.size >= MAX_CORRECTION_ENTRIES) {
            break
        }
        merged.add(entry)
    }
    for (entry in second.entries) {
        if (merged.size >= MAX_CORRECTION_ENTRIES) {
            break
        }
        merged.add(entry)
    }
    CorrectionSummary(first.total + second.total, merged.toArray())
}

/** Result of a load; `freshInstall` drives empty-database seeding. */
public class LoadedWorkspace {
    public let workspace: Workspace
    public let freshInstall: Bool
    public let parentCycles: Array<Array<String>>
    public let corrections: CorrectionSummary

    public init(
        workspace: Workspace,
        freshInstall: Bool,
        parentCycles: Array<Array<String>>,
        corrections: CorrectionSummary
    ) {
        this.workspace = workspace
        this.freshInstall = freshInstall
        this.parentCycles = parentCycles
        this.corrections = corrections
    }
}

public class MigratedWorkspace {
    public let workspace: Workspace
    public let corrections: CorrectionSummary

    public init(workspace: Workspace, corrections: CorrectionSummary) {
        this.workspace = workspace
        this.corrections = corrections
    }
}

/* ------------------------------------------------------------------ */
/* Writing                                                             */
/* ------------------------------------------------------------------ */

/** Wraps a JSON value in `Some`, so field mappers stay one-liners. */
func someJson(value: JsonValue): ?JsonValue {
    Some(value)
}

func nullableJson(value: ?String): JsonValue {
    match (value) {
        case Some(text) => JsonString(text)
        case None => JsonNull
    }
}

func metricJson(metric: Metric): JsonValue {
    JsonObject([
        ("start", JsonFloat(metric.start)),
        ("target", JsonFloat(metric.target)),
        ("current", JsonFloat(metric.current)),
        ("unit", JsonString(metric.unit))
    ])
}

func okrJson(okr: OkrData): JsonValue {
    let entries = ArrayList<(String, JsonValue)>()
    entries.add(("period", JsonString(okr.period)))
    entries.add(("confidence", JsonInt(okr.confidence)))
    match (okr.metric) {
        case Some(metric) => entries.add(("metric", metricJson(metric)))
        case None => ()
    }
    match (okr.krOwner) {
        case Some(owner) => entries.add(("krOwner", JsonString(owner)))
        case None => ()
    }
    JsonObject(entries.toArray())
}

func checklistJson(checklist: Array<ChecklistEntry>): JsonValue {
    let entries = ArrayList<JsonValue>()
    for (entry in checklist) {
        entries.add(JsonObject([
            ("id", JsonString(entry.id)),
            ("text", JsonString(entry.text)),
            ("done", JsonBool(entry.done))
        ]))
    }
    JsonArray(entries.toArray())
}

func sopJson(sop: SopData): JsonValue {
    let entries = ArrayList<(String, JsonValue)>()
    entries.add(("nodeType", JsonString(sopNodeTypeWire(sop.nodeType))))
    entries.add(("canvas", JsonObject([
        ("x", JsonFloat(sop.canvas.x)),
        ("y", JsonFloat(sop.canvas.y))
    ])))
    entries.add(("checklist", checklistJson(sop.checklist)))
    match (sop.owner) {
        case Some(owner) => entries.add(("owner", JsonString(owner)))
        case None => ()
    }
    match (sop.durationMin) {
        case Some(minutes) => entries.add(("durationMin", JsonInt(minutes)))
        case None => ()
    }
    JsonObject(entries.toArray())
}

func gtdJson(gtd: GtdData): JsonValue {
    let entries = ArrayList<(String, JsonValue)>()
    entries.add(("capturedAt", JsonString(gtd.capturedAt)))
    entries.add(("clarified", JsonBool(gtd.clarified)))
    match (gtd.context) {
        case Some(context) => entries.add(("context", JsonString(context)))
        case None => ()
    }
    match (gtd.energy) {
        case Some(energy) => entries.add(("energy", JsonString(energyWire(energy))))
        case None => ()
    }
    match (gtd.waitingFor) {
        case Some(waitingFor) => entries.add(("waitingFor", JsonString(waitingFor)))
        case None => ()
    }
    match (gtd.twoMinuteCandidate) {
        case Some(flag) => entries.add(("twoMinuteCandidate", JsonBool(flag)))
        case None => ()
    }
    JsonObject(entries.toArray())
}

func ganttJson(gantt: GanttData): JsonValue {
    JsonObject([
        ("start", nullableJson(gantt.start)),
        ("end", nullableJson(gantt.end)),
        ("progress", JsonFloat(gantt.progress))
    ])
}

/**
 * Emits an object using `orderHint` (the parsed key order) when available,
 * falling back to `canonical`. Keys the store added after parsing, and unknown
 * fields, are appended so nothing is ever dropped.
 */
func assembleJson(
    canonical: Array<String>,
    orderHint: Array<String>,
    fieldValue: (String) -> ?JsonValue,
    extras: Array<(String, JsonValue)>
): JsonValue {
    let extraMap = HashMap<String, JsonValue>()
    for ((key, value) in extras) {
        extraMap[key] = value
    }
    let emitted = HashMap<String, Bool>()
    let entries = ArrayList<(String, JsonValue)>()
    let order = if (orderHint.isEmpty()) {
        canonical
    } else {
        orderHint
    }
    for (key in order) {
        match (fieldValue(key)) {
            case Some(value) =>
                entries.add((key, value))
                emitted[key] = true
            case None => match (extraMap.get(key)) {
                case Some(value) =>
                    entries.add((key, value))
                    emitted[key] = true
                case None => ()
            }
        }
    }
    for (key in canonical) {
        match (emitted.get(key)) {
            case Some(_) => continue
            case None => ()
        }
        match (fieldValue(key)) {
            case Some(value) =>
                entries.add((key, value))
                emitted[key] = true
            case None => ()
        }
    }
    for ((key, value) in extras) {
        match (emitted.get(key)) {
            case Some(_) => continue
            case None =>
                entries.add((key, value))
                emitted[key] = true
        }
    }
    JsonObject(entries.toArray())
}

func itemField(item: Item, key: String): ?JsonValue {
    match (key) {
        case "id" => someJson(JsonString(item.id))
        case "kind" => someJson(JsonString(itemKindWire(item.kind)))
        case "title" => someJson(JsonString(item.title))
        case "notes" => someJson(JsonString(item.notes))
        case "parentId" => someJson(nullableJson(item.parentId))
        case "order" => someJson(JsonInt(item.order))
        case "status" => someJson(JsonString(itemStatusWire(item.status)))
        case "tags" =>
            let tags = ArrayList<JsonValue>()
            for (tag in item.tags) {
                tags.add(JsonString(tag))
            }
            someJson(JsonArray(tags.toArray()))
        case "areaId" => someJson(nullableJson(item.areaId))
        case "createdAt" => someJson(JsonString(item.createdAt))
        case "updatedAt" => someJson(JsonString(item.updatedAt))
        case "completedAt" => someJson(nullableJson(item.completedAt))
        case "okr" => match (item.okr) {
            case Some(okr) => someJson(okrJson(okr))
            case None => None
        }
        case "sop" => match (item.sop) {
            case Some(sop) => someJson(sopJson(sop))
            case None => None
        }
        case "gtd" => match (item.gtd) {
            case Some(gtd) => someJson(gtdJson(gtd))
            case None => None
        }
        case "gantt" => match (item.gantt) {
            case Some(gantt) => someJson(ganttJson(gantt))
            case None => None
        }
        case _ => None
    }
}

public func itemToJson(item: Item): JsonValue {
    assembleJson(ITEM_KEY_ORDER, item.keyOrder, {key => itemField(item, key)}, item.extras)
}

func edgeField(edge: Edge, key: String): ?JsonValue {
    match (key) {
        case "id" => someJson(JsonString(edge.id))
        case "from" => someJson(JsonString(edge.from))
        case "to" => someJson(JsonString(edge.to))
        case "type" => someJson(JsonString(edgeTypeWire(edge.edgeType)))
        case "label" => someJson(JsonString(edge.label))
        case _ => None
    }
}

public func edgeToJson(edge: Edge): JsonValue {
    assembleJson(EDGE_KEY_ORDER, edge.keyOrder, {key => edgeField(edge, key)}, edge.extras)
}

func areaField(area: Area, key: String): ?JsonValue {
    match (key) {
        case "id" => someJson(JsonString(area.id))
        case "name" => someJson(JsonString(area.name))
        case "color" => someJson(JsonString(area.color))
        case "order" => someJson(JsonInt(area.order))
        case _ => None
    }
}

public func areaToJson(area: Area): JsonValue {
    assembleJson(AREA_KEY_ORDER, area.keyOrder, {key => areaField(area, key)}, area.extras)
}

func runField(run: SopRunEntry, key: String): ?JsonValue {
    match (key) {
        case "id" => someJson(JsonString(run.id))
        case "sopId" => someJson(JsonString(run.sopId))
        case "stepId" => someJson(JsonString(run.stepId))
        case "at" => someJson(JsonString(run.at))
        case "result" => someJson(JsonString(runResultWire(run.result)))
        case "note" => someJson(JsonString(run.note))
        case _ => None
    }
}

public func runToJson(run: SopRunEntry): JsonValue {
    assembleJson(RUN_KEY_ORDER, run.keyOrder, {key => runField(run, key)}, run.extras)
}

func workspaceField(workspace: Workspace, key: String): ?JsonValue {
    match (key) {
        case "version" => someJson(JsonInt(workspace.version))
        case "items" =>
            let items = ArrayList<JsonValue>()
            for (item in workspace.items) {
                items.add(itemToJson(item))
            }
            someJson(JsonArray(items.toArray()))
        case "edges" =>
            let edges = ArrayList<JsonValue>()
            for (edge in workspace.edges) {
                edges.add(edgeToJson(edge))
            }
            someJson(JsonArray(edges.toArray()))
        case "areas" =>
            let areas = ArrayList<JsonValue>()
            for (area in workspace.areas) {
                areas.add(areaToJson(area))
            }
            someJson(JsonArray(areas.toArray()))
        case "runs" =>
            let runs = ArrayList<JsonValue>()
            for (run in workspace.runs) {
                runs.add(runToJson(run))
            }
            someJson(JsonArray(runs.toArray()))
        case "updatedAt" => someJson(JsonString(workspace.updatedAt))
        case _ => None
    }
}

public func workspaceToJson(workspace: Workspace): JsonValue {
    assembleJson(WORKSPACE_KEY_ORDER, workspace.keyOrder, {key => workspaceField(workspace, key)}, workspace.extras)
}

/** `JSON.stringify(workspace, null, 2)`, no trailing newline. */
public func workspaceToJsonText(workspace: Workspace): String {
    writeJson(workspaceToJson(workspace))
}

/**
 * The on-disk document: pretty JSON plus the trailing newline the parity
 * fixture (`tools/parity/workspace.json`) carries.
 */
public func encodeWorkspaceDocument(workspace: Workspace): String {
    workspaceToJsonText(workspace) + "\n"
}


/**
 * Key-order independent, single-line rendering of a workspace. Two documents
 * are semantically equal when this text matches; used by parity tests and by
 * semantic diffs (never written to disk).
 */
public func canonicalWorkspaceJsonText(workspace: Workspace): String {
    let items = ArrayList<Item>()
    for (item in workspace.items) {
        items.add(Item(
            item.id,
            item.kind,
            item.title,
            notes: item.notes,
            parentId: item.parentId,
            order: item.order,
            status: item.status,
            tags: item.tags,
            areaId: item.areaId,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            completedAt: item.completedAt,
            okr: item.okr,
            sop: item.sop,
            gtd: item.gtd,
            gantt: item.gantt
        ))
    }
    let edges = ArrayList<Edge>()
    for (edge in workspace.edges) {
        edges.add(Edge(edge.id, edge.from, edge.to, edge.edgeType, label: edge.label))
    }
    let areas = ArrayList<Area>()
    for (area in workspace.areas) {
        areas.add(Area(area.id, area.name, area.color, order: area.order))
    }
    let runs = ArrayList<SopRunEntry>()
    for (run in workspace.runs) {
        runs.add(SopRunEntry(run.id, run.sopId, run.stepId, run.at, run.result, note: run.note))
    }
    let stripped = Workspace(
        version: workspace.version,
        items: items.toArray(),
        edges: edges.toArray(),
        areas: areas.toArray(),
        runs: runs.toArray(),
        updatedAt: workspace.updatedAt
    )
    writeJsonCompact(workspaceToJson(stripped))
}

/* ------------------------------------------------------------------ */
/* Reading + normalization                                             */
/* ------------------------------------------------------------------ */

func asString(value: JsonValue, fallback!: String = ""): String {
    match (value) {
        case JsonString(text) => text
        case _ => fallback
    }
}

func asNonEmptyString(value: JsonValue, fallback: String): String {
    match (value) {
        case JsonString(text) => if (!text.trimAscii().isEmpty()) {
            text
        } else {
            fallback
        }
        case _ => fallback
    }
}

func asOptionalText(value: JsonValue): ?String {
    match (value) {
        case JsonString(text) => if (!text.trimAscii().isEmpty()) {
            Some(text)
        } else {
            None
        }
        case _ => None
    }
}

func asOptionalId(value: JsonValue): ?String {
    match (value) {
        case JsonString(text) => if (!text.trimAscii().isEmpty()) {
            Some(text)
        } else {
            None
        }
        case _ => None
    }
}

func asNumber(value: JsonValue, fallback: Float64): Float64 {
    match (value) {
        case JsonInt(number) => Float64(number)
        case JsonFloat(number) =>
            if (number != number) {
                fallback
            } else if (number > 1.7976931348623157e308 || number < -1.7976931348623157e308) {
                fallback
            } else {
                number
            }
        case JsonString(text) =>
            if (text.trimAscii().isEmpty()) {
                fallback
            } else {
                match (Float64.tryParse(text.trimAscii())) {
                    case Some(number) => number
                    case None => fallback
                }
            }
        case _ => fallback
    }
}

func asInteger(value: JsonValue, fallback: Int64): Int64 {
    roundHalfUp(asNumber(value, Float64(fallback)))
}

func clampNumber(value: JsonValue, lower: Float64, upper: Float64, fallback: Float64): Float64 {
    clampFloat(asNumber(value, fallback), lower, upper)
}

func asBool(value: JsonValue, fallback: Bool): Bool {
    match (value) {
        case JsonBool(flag) => flag
        case _ => fallback
    }
}

func asArray(value: JsonValue): Array<JsonValue> {
    match (value) {
        case JsonArray(items) => items
        case _ => []
    }
}

func objectEntries(value: JsonValue): Array<(String, JsonValue)> {
    match (value) {
        case JsonObject(entries) => entries
        case _ => []
    }
}

func isObject(value: JsonValue): Bool {
    match (value) {
        case JsonObject(_) => true
        case _ => false
    }
}

func member(object: JsonValue, key: String): ?JsonValue {
    for ((entryKey, entryValue) in objectEntries(object)) {
        if (entryKey == key) {
            return Some(entryValue)
        }
    }
    None
}

func memberOrNull(object: JsonValue, key: String): JsonValue {
    match (member(object, key)) {
        case Some(value) => value
        case None => JsonNull
    }
}

/** Keys of an object in document order, for `keyOrder` preservation. */
func keyOrderOf(value: JsonValue): Array<String> {
    let keys = ArrayList<String>()
    for ((key, _) in objectEntries(value)) {
        keys.add(key)
    }
    keys.toArray()
}

/** Unknown fields: everything not in `canonical`. */
func extrasOf(value: JsonValue, canonical: Array<String>): Array<(String, JsonValue)> {
    let known = HashMap<String, Bool>()
    for (key in canonical) {
        known[key] = true
    }
    let extras = ArrayList<(String, JsonValue)>()
    for ((key, entryValue) in objectEntries(value)) {
        match (known.get(key)) {
            case Some(_) => ()
            case None => extras.add((key, entryValue))
        }
    }
    extras.toArray()
}

func normalizeChecklist(value: JsonValue, itemIndex: Int64): Array<ChecklistEntry> {
    let entries = ArrayList<ChecklistEntry>()
    let raw = asArray(value)
    for (index in 0..raw.size) {
        let entry = raw[index]
        let id = asNonEmptyString(memberOrNull(entry, "id"), "chk_${itemIndex}_${index}")
        let text = asString(memberOrNull(entry, "text"))
        let done = asBool(memberOrNull(entry, "done"), false)
        entries.add(ChecklistEntry(id, text, done))
    }
    entries.toArray()
}

func normalizeOkr(value: JsonValue, clock: Clock): OkrData {
    let period = asNonEmptyString(memberOrNull(value, "period"), currentQuarter(clock))
    let confidence = asInteger(memberOrNull(value, "confidence"), 5)
    let clampedConfidence = clampInt(confidence, 1, 10)
    var metric: ?Metric = None
    match (member(value, "metric")) {
        case Some(rawMetric) => if (isObject(rawMetric)) {
            metric = Some(Metric(
                asNumber(memberOrNull(rawMetric, "start"), 0.0),
                asNumber(memberOrNull(rawMetric, "target"), 0.0),
                asNumber(memberOrNull(rawMetric, "current"), 0.0),
                asString(memberOrNull(rawMetric, "unit"))
            ))
        }
        case None => ()
    }
    let owner = asOptionalText(memberOrNull(value, "krOwner"))
    OkrData(period, clampedConfidence, metric: metric, krOwner: owner)
}

func normalizeSop(value: JsonValue, itemIndex: Int64): SopData {
    let nodeType = match (member(value, "nodeType")) {
        case Some(raw) => match (parseSopNodeType(asString(raw))) {
            case Some(parsed) => parsed
            case None => SopNodeType.Action
        }
        case None => SopNodeType.Action
    }
    let canvas = memberOrNull(value, "canvas")
    let x = asNumber(memberOrNull(canvas, "x"), 0.0)
    let y = asNumber(memberOrNull(canvas, "y"), 0.0)
    let checklist = normalizeChecklist(memberOrNull(value, "checklist"), itemIndex)
    let owner = asOptionalText(memberOrNull(value, "owner"))
    var duration: ?Int64 = None
    match (member(value, "durationMin")) {
        case Some(raw) =>
            if (raw != JsonNull) {
                duration = Some(maxInt64(0, asInteger(raw, 0)))
            }
        case None => ()
    }
    SopData(nodeType, canvas: CanvasPos(x, y), checklist: checklist, owner: owner, durationMin: duration)
}

func maxInt64(left: Int64, right: Int64): Int64 {
    if (left > right) {
        left
    } else {
        right
    }
}

func normalizeGtd(value: JsonValue, fallbackCapturedAt: String): GtdData {
    let capturedAt = asNonEmptyString(memberOrNull(value, "capturedAt"), fallbackCapturedAt)
    let clarified = asBool(memberOrNull(value, "clarified"), false)
    let context = asOptionalText(memberOrNull(value, "context"))
    var energy: ?Energy = None
    match (member(value, "energy")) {
        case Some(raw) => match (parseEnergy(asString(raw))) {
            case Some(parsed) => energy = Some(parsed)
            case None => ()
        }
        case None => ()
    }
    let waitingFor = asOptionalText(memberOrNull(value, "waitingFor"))
    var twoMinute: ?Bool = None
    match (member(value, "twoMinuteCandidate")) {
        case Some(raw) => match (raw) {
            case JsonBool(flag) => twoMinute = Some(flag)
            case _ => ()
        }
        case None => ()
    }
    GtdData(capturedAt, clarified, context: context, energy: energy, waitingFor: waitingFor, twoMinuteCandidate: twoMinute)
}

func asDateOrNull(value: JsonValue): ?String {
    match (value) {
        case JsonString(text) => if (!text.trimAscii().isEmpty()) {
            Some(text)
        } else {
            None
        }
        case _ => None
    }
}

func normalizeGantt(value: JsonValue): GanttData {
    GanttData(
        start: asDateOrNull(memberOrNull(value, "start")),
        end: asDateOrNull(memberOrNull(value, "end")),
        progress: clampNumber(memberOrNull(value, "progress"), 0.0, 100.0, 0.0)
    )
}

func normalizeItem(value: JsonValue, index: Int64, clock: Clock): Item {
    let timestamp = nowIso(clock)
    let kind = match (member(value, "kind")) {
        case Some(raw) => match (parseItemKind(asString(raw))) {
            case Some(parsed) => parsed
            case None => ItemKind.Note
        }
        case None => ItemKind.Note
    }
    let status = match (member(value, "status")) {
        case Some(raw) => match (parseItemStatus(asString(raw))) {
            case Some(parsed) => parsed
            case None => ItemStatus.Next
        }
        case None => ItemStatus.Next
    }
    let tags = ArrayList<String>()
    for (raw in asArray(memberOrNull(value, "tags"))) {
        let tag = asString(raw).trimAscii()
        if (!tag.isEmpty()) {
            tags.add(tag)
        }
    }
    let completedAt: ?String = match (member(value, "completedAt")) {
        case Some(JsonString(text)) => if (!text.trimAscii().isEmpty()) {
            Some(text)
        } else {
            None
        }
        case _ => None
    }
    var okr: ?OkrData = None
    match (member(value, "okr")) {
        case Some(raw) => if (isObject(raw)) {
            okr = Some(normalizeOkr(raw, clock))
        }
        case None => ()
    }
    var sop: ?SopData = None
    match (member(value, "sop")) {
        case Some(raw) => if (isObject(raw)) {
            sop = Some(normalizeSop(raw, index))
        }
        case None => ()
    }
    let createdAt = asNonEmptyString(memberOrNull(value, "createdAt"), timestamp)
    var gtd: ?GtdData = None
    match (member(value, "gtd")) {
        case Some(raw) => if (isObject(raw)) {
            gtd = Some(normalizeGtd(raw, createdAt))
        }
        case None => ()
    }
    var gantt: ?GanttData = None
    match (member(value, "gantt")) {
        case Some(raw) => if (isObject(raw)) {
            gantt = Some(normalizeGantt(raw))
        }
        case None => ()
    }
    Item(
        asNonEmptyString(memberOrNull(value, "id"), "i_recovered_${index}"),
        kind,
        asString(memberOrNull(value, "title"), fallback: "未命名条目"),
        notes: asString(memberOrNull(value, "notes")),
        parentId: asOptionalId(memberOrNull(value, "parentId")),
        order: asInteger(memberOrNull(value, "order"), index),
        status: status,
        tags: tags.toArray(),
        areaId: asOptionalId(memberOrNull(value, "areaId")),
        createdAt: createdAt,
        updatedAt: asNonEmptyString(memberOrNull(value, "updatedAt"), timestamp),
        completedAt: completedAt,
        okr: okr,
        sop: sop,
        gtd: gtd,
        gantt: gantt,
        extras: extrasOf(value, ITEM_KEY_ORDER),
        keyOrder: keyOrderOf(value)
    )
}

func normalizeEdge(value: JsonValue, index: Int64): Edge {
    let edgeType = match (member(value, "type")) {
        case Some(raw) => match (parseEdgeType(asString(raw))) {
            case Some(parsed) => parsed
            case None => EdgeType.Related
        }
        case None => EdgeType.Related
    }
    Edge(
        asNonEmptyString(memberOrNull(value, "id"), "edge_recovered_${index}"),
        asString(memberOrNull(value, "from")),
        asString(memberOrNull(value, "to")),
        edgeType,
        label: asString(memberOrNull(value, "label")),
        extras: extrasOf(value, EDGE_KEY_ORDER),
        keyOrder: keyOrderOf(value)
    )
}

func normalizeArea(value: JsonValue, index: Int64): Area {
    Area(
        asNonEmptyString(memberOrNull(value, "id"), "area_recovered_${index}"),
        asString(memberOrNull(value, "name"), fallback: "未命名领域"),
        asString(memberOrNull(value, "color"), fallback: "#C0663A"),
        order: asInteger(memberOrNull(value, "order"), index),
        extras: extrasOf(value, AREA_KEY_ORDER),
        keyOrder: keyOrderOf(value)
    )
}

func normalizeRun(value: JsonValue, index: Int64, clock: Clock): SopRunEntry {
    let result = match (member(value, "result")) {
        case Some(raw) => match (parseRunResult(asString(raw))) {
            case Some(parsed) => parsed
            case None => RunResult.Skip
        }
        case None => RunResult.Skip
    }
    SopRunEntry(
        asNonEmptyString(memberOrNull(value, "id"), "run_recovered_${index}"),
        asString(memberOrNull(value, "sopId")),
        asString(memberOrNull(value, "stepId")),
        asNonEmptyString(memberOrNull(value, "at"), nowIso(clock)),
        result,
        note: asString(memberOrNull(value, "note")),
        extras: extrasOf(value, RUN_KEY_ORDER),
        keyOrder: keyOrderOf(value)
    )
}

func normalizeWorkspace(value: JsonValue, clock: Clock): Workspace {
    if (!isObject(value)) {
        throw IllegalArgumentException("工作区数据不是对象")
    }
    let rawVersion = asNumber(memberOrNull(value, "version"), 0.0)
    let version = Int64(rawVersion)
    if (version > WORKSPACE_VERSION) {
        throw WorkspaceVersionError(version)
    }
    let items = ArrayList<Item>()
    let rawItems = asArray(memberOrNull(value, "items"))
    for (index in 0..rawItems.size) {
        items.add(normalizeItem(rawItems[index], index, clock))
    }
    let edges = ArrayList<Edge>()
    let rawEdges = asArray(memberOrNull(value, "edges"))
    for (index in 0..rawEdges.size) {
        edges.add(normalizeEdge(rawEdges[index], index))
    }
    let areas = ArrayList<Area>()
    let rawAreas = asArray(memberOrNull(value, "areas"))
    for (index in 0..rawAreas.size) {
        areas.add(normalizeArea(rawAreas[index], index))
    }
    let runs = ArrayList<SopRunEntry>()
    let rawRuns = asArray(memberOrNull(value, "runs"))
    for (index in 0..rawRuns.size) {
        runs.add(normalizeRun(rawRuns[index], index, clock))
    }
    Workspace(
        version: WORKSPACE_VERSION,
        items: items.toArray(),
        edges: edges.toArray(),
        areas: areas.toArray(),
        runs: runs.toArray(),
        updatedAt: asNonEmptyString(memberOrNull(value, "updatedAt"), nowIso(clock)),
        extras: extrasOf(value, WORKSPACE_KEY_ORDER),
        keyOrder: keyOrderOf(value)
    )
}

/* ------------------------------------------------------------------ */
/* Correction reporting                                                */
/* ------------------------------------------------------------------ */

func jsonTextOf(value: JsonValue): String {
    writeJsonCompact(value)
}

func jsonValuesEqual(left: JsonValue, right: JsonValue): Bool {
    let leftNumber = match (left) {
        case JsonInt(_) => true
        case JsonFloat(_) => true
        case _ => false
    }
    let rightNumber = match (right) {
        case JsonInt(_) => true
        case JsonFloat(_) => true
        case _ => false
    }
    if (leftNumber && rightNumber) {
        return asNumber(left, 0.0) == asNumber(right, 0.0)
    }
    jsonTextOf(left) == jsonTextOf(right)
}

class CorrectionCollector {
    var total: Int64 = 0
    let entries: ArrayList<NormalizationCorrection>

    init() {
        this.entries = ArrayList<NormalizationCorrection>()
    }

    func record(itemId: ?String, field: String, from: JsonValue, to: JsonValue): Unit {
        if (jsonValuesEqual(from, to)) {
            return
        }
        total += 1
        if (entries.size < MAX_CORRECTION_ENTRIES) {
            entries.add(NormalizationCorrection(itemId, field, jsonTextOf(from), jsonTextOf(to)))
        }
    }

    func summary(): CorrectionSummary {
        CorrectionSummary(total, entries.toArray())
    }
}

/**
 * Records fields that existed in the document but were normalized, plus
 * accidentally dropped blocks. Mirrors `collectCorrections` in `repo.ts`.
 */
func collectCorrections(
    raw: JsonValue,
    normalized: JsonValue,
    itemIds: Array<String>
): CorrectionSummary {
    let collector = CorrectionCollector()
    let rawItems = asArray(memberOrNull(raw, "items"))
    let normalizedItems = asArray(memberOrNull(normalized, "items"))
    for (index in 0..normalizedItems.size) {
        if (index >= rawItems.size) {
            continue
        }
        let rawItem = rawItems[index]
        let nextItem = normalizedItems[index]
        let itemId: ?String = if (index < itemIds.size) {
            Some(itemIds[index])
        } else {
            None
        }
        for (key in ITEM_KEY_ORDER) {
            match (member(rawItem, key)) {
                case None => ()
                case Some(from) =>
                    let to = memberOrNull(nextItem, key)
                    let isBlock = key == "okr" || key == "sop" || key == "gtd" || key == "gantt"
                    if (isBlock) {
                        if (isObject(from) && isObject(to)) {
                            diffNested(collector, itemId, key, from, to)
                        } else if (!jsonValuesEqual(from, to)) {
                            collector.record(itemId, key, from, to)
                        }
                    } else if (!jsonValuesEqual(from, to)) {
                        collector.record(itemId, key, from, to)
                    }
            }
        }
    }
    diffCollection(collector, raw, normalized, "edges", EDGE_KEY_ORDER)
    diffCollection(collector, raw, normalized, "areas", AREA_KEY_ORDER)
    diffCollection(collector, raw, normalized, "runs", RUN_KEY_ORDER)
    collector.summary()
}

func diffNested(
    collector: CorrectionCollector,
    itemId: ?String,
    prefix: String,
    from: JsonValue,
    to: JsonValue
): Unit {
    for ((key, fromValue) in objectEntries(from)) {
        match (member(to, key)) {
            case None => collector.record(itemId, "${prefix}.${key}", fromValue, JsonNull)
            case Some(toValue) => if (isObject(fromValue) && isObject(toValue)) {
                diffNested(collector, itemId, "${prefix}.${key}", fromValue, toValue)
            } else if (!jsonValuesEqual(fromValue, toValue)) {
                collector.record(itemId, "${prefix}.${key}", fromValue, toValue)
            }
        }
    }
}

func diffCollection(
    collector: CorrectionCollector,
    raw: JsonValue,
    normalized: JsonValue,
    name: String,
    keys: Array<String>
): Unit {
    let rawList = asArray(memberOrNull(raw, name))
    let normalizedList = asArray(memberOrNull(normalized, name))
    for (index in 0..normalizedList.size) {
        if (index >= rawList.size) {
            continue
        }
        for (key in keys) {
            match (member(rawList[index], key)) {
                case None => ()
                case Some(from) =>
                    let to = memberOrNull(normalizedList[index], key)
                    if (!jsonValuesEqual(from, to)) {
                        collector.record(None, "${name}[${index}].${key}", from, to)
                    }
            }
        }
    }
}

/* ------------------------------------------------------------------ */
/* Entry points                                                        */
/* ------------------------------------------------------------------ */

public func normalizeWorkspaceWithCorrections(value: JsonValue, clock: Clock): MigratedWorkspace {
    let workspace = normalizeWorkspace(value, clock)
    let normalizedJson = workspaceToJson(workspace)
    let itemIds = ArrayList<String>()
    for (item in workspace.items) {
        itemIds.add(item.id)
    }
    let corrections = collectCorrections(value, normalizedJson, itemIds.toArray())
    MigratedWorkspace(workspace, corrections)
}

/** Strict import path: normalization + parent-cycle rejection. */
public func migrateWorkspaceWithReport(value: JsonValue, clock: Clock): MigratedWorkspace {
    let migrated = normalizeWorkspaceWithCorrections(value, clock)
    let cycles = findParentCycles(migrated.workspace)
    if (!cycles.isEmpty()) {
        throw IllegalArgumentException("数据中存在父子环：${cycleLabels(migrated.workspace, cycles)}，请修复后重试")
    }
    migrated
}

public func migrateWorkspace(value: JsonValue, clock: Clock): Workspace {
    migrateWorkspaceWithReport(value, clock).workspace
}

public func cycleLabels(workspace: Workspace, cycles: Array<Array<String>>): String {
    let out = StringBuilder()
    for (index in 0..cycles.size) {
        if (index > 0) {
            out.append("；")
        }
        for (position in 0..cycles[index].size) {
            if (position > 0) {
                out.append(" → ")
            }
            let id = cycles[index][position]
            let title = match (itemById(workspace, id)) {
                case Some(item) => if (item.title.isEmpty()) {
                    id
                } else {
                    item.title
                }
                case None => id
            }
            out.append(title)
        }
    }
    out.toString()
}

/**
 * Load path: normalization, then cut every parent cycle by detaching one node,
 * keeping the original parent ids for diagnostics. Mirrors `normalizeForLoad`.
 */
public func normalizeForLoad(value: JsonValue, clock: Clock): LoadedWorkspace {
    let migrated = normalizeWorkspaceWithCorrections(value, clock)
    let cycles = findParentCycles(migrated.workspace)
    if (cycles.isEmpty()) {
        return LoadedWorkspace(migrated.workspace, false, cycles, migrated.corrections)
    }
    let cutIds = HashMap<String, Bool>()
    for (cycle in cycles) {
        if (cycle.size >= 2) {
            cutIds[cycle[cycle.size - 2]] = true
        }
    }
    let items = ArrayList<Item>()
    for (item in migrated.workspace.items) {
        match (cutIds.get(item.id)) {
            case Some(_) =>
                items.add(Item(
                    item.id,
                    item.kind,
                    item.title,
                    notes: item.notes,
                    parentId: None,
                    order: item.order,
                    status: item.status,
                    tags: item.tags,
                    areaId: item.areaId,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt,
                    completedAt: item.completedAt,
                    okr: item.okr,
                    sop: item.sop,
                    gtd: item.gtd,
                    gantt: item.gantt,
                    extras: item.extras,
                    keyOrder: item.keyOrder
                ))
            case None => items.add(item)
        }
    }
    LoadedWorkspace(migrated.workspace.withItems(items.toArray()), false, cycles, migrated.corrections)
}

/** Parses and strictly migrates an imported document. */
public func parseWorkspaceText(text: String, clock: Clock): Workspace {
    migrateWorkspace(parseJson(text), clock)
}

/**
 * Reads a workspace document. A missing file is a fresh install (the store then
 * seeds demo data); an unreadable/duplicate-cycle file still loads, repaired.
 */
public func loadWorkspaceFromPath(path: String, clock: Clock): LoadedWorkspace {
    var text = ""
    try {
        text = String.fromUtf8(File.readFrom(path))
    } catch (_: Exception) {
        return LoadedWorkspace(emptyWorkspace(clock), true, [], CorrectionSummary.empty())
    }
    if (text.trimAscii().isEmpty()) {
        return LoadedWorkspace(emptyWorkspace(clock), true, [], CorrectionSummary.empty())
    }
    let loaded = normalizeForLoad(parseJson(text), clock)
    LoadedWorkspace(loaded.workspace, false, loaded.parentCycles, loaded.corrections)
}
