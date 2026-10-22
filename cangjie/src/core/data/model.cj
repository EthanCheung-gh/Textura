package textura.core.data

/**
 * The single domain model shared by every view.
 *
 * Field names, optionality and defaults mirror `src/core/model.ts` exactly.
 * Nothing here may be extended for one view's convenience: views differ only in
 * which fields they read.
 *
 * Two extra fields exist purely for lossless JSON handling (see `codec.cj`):
 * - `keyOrder` remembers the on-disk key order of a parsed document so a
 *   load/save round trip stays byte-identical;
 * - `extras` keeps unknown fields so a newer Web build's data is not dropped.
 */
public let WORKSPACE_VERSION: Int64 = 1

public enum ItemKind {
    | Objective
    | KeyResult
    | Project
    | Action
    | Sop
    | Step
    | Milestone
    | Note
    | Reference

    public operator func ==(right: ItemKind): Bool {
        itemKindWire(this) == itemKindWire(right)
    }

    public operator func !=(right: ItemKind): Bool {
        itemKindWire(this) != itemKindWire(right)
    }
}

public enum ItemStatus {
    | Inbox
    | Next
    | Active
    | Waiting
    | Scheduled
    | Someday
    | Done
    | Dropped

    public operator func ==(right: ItemStatus): Bool {
        itemStatusWire(this) == itemStatusWire(right)
    }

    public operator func !=(right: ItemStatus): Bool {
        itemStatusWire(this) != itemStatusWire(right)
    }
}

public enum Energy {
    | Low
    | Medium
    | High

    public operator func ==(right: Energy): Bool {
        energyWire(this) == energyWire(right)
    }

    public operator func !=(right: Energy): Bool {
        energyWire(this) != energyWire(right)
    }
}

public enum SopNodeType {
    | Start
    | Action
    | Decision
    | Check
    | End
    | Note

    public operator func ==(right: SopNodeType): Bool {
        sopNodeTypeWire(this) == sopNodeTypeWire(right)
    }

    public operator func !=(right: SopNodeType): Bool {
        sopNodeTypeWire(this) != sopNodeTypeWire(right)
    }
}

public enum EdgeType {
    | Okr
    | Flow
    | Depends
    | Related

    public operator func ==(right: EdgeType): Bool {
        edgeTypeWire(this) == edgeTypeWire(right)
    }

    public operator func !=(right: EdgeType): Bool {
        edgeTypeWire(this) != edgeTypeWire(right)
    }
}

public enum RunResult {
    | Pass
    | Fail
    | Skip

    public operator func ==(right: RunResult): Bool {
        runResultWire(this) == runResultWire(right)
    }

    public operator func !=(right: RunResult): Bool {
        runResultWire(this) != runResultWire(right)
    }
}

public enum NoticeTone {
    | Info
    | Success
    | Error

    public operator func ==(right: NoticeTone): Bool {
        noticeToneWire(this) == noticeToneWire(right)
    }

    public operator func !=(right: NoticeTone): Bool {
        noticeToneWire(this) != noticeToneWire(right)
    }
}

/** Wire name (what the JSON document stores) for a kind. */
public func itemKindWire(kind: ItemKind): String {
    match (kind) {
        case ItemKind.Objective => "objective"
        case ItemKind.KeyResult => "keyresult"
        case ItemKind.Project => "project"
        case ItemKind.Action => "action"
        case ItemKind.Sop => "sop"
        case ItemKind.Step => "step"
        case ItemKind.Milestone => "milestone"
        case ItemKind.Note => "note"
        case ItemKind.Reference => "reference"
    }
}

public func parseItemKind(value: String): ?ItemKind {
    match (value) {
        case "objective" => Some(ItemKind.Objective)
        case "keyresult" => Some(ItemKind.KeyResult)
        case "project" => Some(ItemKind.Project)
        case "action" => Some(ItemKind.Action)
        case "sop" => Some(ItemKind.Sop)
        case "step" => Some(ItemKind.Step)
        case "milestone" => Some(ItemKind.Milestone)
        case "note" => Some(ItemKind.Note)
        case "reference" => Some(ItemKind.Reference)
        case _ => None
    }
}

public func itemStatusWire(status: ItemStatus): String {
    match (status) {
        case ItemStatus.Inbox => "inbox"
        case ItemStatus.Next => "next"
        case ItemStatus.Active => "active"
        case ItemStatus.Waiting => "waiting"
        case ItemStatus.Scheduled => "scheduled"
        case ItemStatus.Someday => "someday"
        case ItemStatus.Done => "done"
        case ItemStatus.Dropped => "dropped"
    }
}

public func parseItemStatus(value: String): ?ItemStatus {
    match (value) {
        case "inbox" => Some(ItemStatus.Inbox)
        case "next" => Some(ItemStatus.Next)
        case "active" => Some(ItemStatus.Active)
        case "waiting" => Some(ItemStatus.Waiting)
        case "scheduled" => Some(ItemStatus.Scheduled)
        case "someday" => Some(ItemStatus.Someday)
        case "done" => Some(ItemStatus.Done)
        case "dropped" => Some(ItemStatus.Dropped)
        case _ => None
    }
}

public func energyWire(energy: Energy): String {
    match (energy) {
        case Energy.Low => "low"
        case Energy.Medium => "medium"
        case Energy.High => "high"
    }
}

public func parseEnergy(value: String): ?Energy {
    match (value) {
        case "low" => Some(Energy.Low)
        case "medium" => Some(Energy.Medium)
        case "high" => Some(Energy.High)
        case _ => None
    }
}

public func sopNodeTypeWire(nodeType: SopNodeType): String {
    match (nodeType) {
        case SopNodeType.Start => "start"
        case SopNodeType.Action => "action"
        case SopNodeType.Decision => "decision"
        case SopNodeType.Check => "check"
        case SopNodeType.End => "end"
        case SopNodeType.Note => "note"
    }
}

public func parseSopNodeType(value: String): ?SopNodeType {
    match (value) {
        case "start" => Some(SopNodeType.Start)
        case "action" => Some(SopNodeType.Action)
        case "decision" => Some(SopNodeType.Decision)
        case "check" => Some(SopNodeType.Check)
        case "end" => Some(SopNodeType.End)
        case "note" => Some(SopNodeType.Note)
        case _ => None
    }
}

public func edgeTypeWire(edgeType: EdgeType): String {
    match (edgeType) {
        case EdgeType.Okr => "okr"
        case EdgeType.Flow => "flow"
        case EdgeType.Depends => "depends"
        case EdgeType.Related => "related"
    }
}

public func parseEdgeType(value: String): ?EdgeType {
    match (value) {
        case "okr" => Some(EdgeType.Okr)
        case "flow" => Some(EdgeType.Flow)
        case "depends" => Some(EdgeType.Depends)
        case "related" => Some(EdgeType.Related)
        case _ => None
    }
}

public func runResultWire(result: RunResult): String {
    match (result) {
        case RunResult.Pass => "pass"
        case RunResult.Fail => "fail"
        case RunResult.Skip => "skip"
    }
}

public func parseRunResult(value: String): ?RunResult {
    match (value) {
        case "pass" => Some(RunResult.Pass)
        case "fail" => Some(RunResult.Fail)
        case "skip" => Some(RunResult.Skip)
        case _ => None
    }
}

public func noticeToneWire(tone: NoticeTone): String {
    match (tone) {
        case NoticeTone.Info => "info"
        case NoticeTone.Success => "success"
        case NoticeTone.Error => "error"
    }
}

public let ITEM_KINDS: Array<ItemKind> = [
    ItemKind.Objective, ItemKind.KeyResult, ItemKind.Project, ItemKind.Action, ItemKind.Sop,
    ItemKind.Step, ItemKind.Milestone, ItemKind.Note, ItemKind.Reference
]

public let ITEM_STATUSES: Array<ItemStatus> = [
    ItemStatus.Inbox, ItemStatus.Next, ItemStatus.Active, ItemStatus.Waiting,
    ItemStatus.Scheduled, ItemStatus.Someday, ItemStatus.Done, ItemStatus.Dropped
]

public func itemKindLabel(kind: ItemKind): String {
    match (kind) {
        case ItemKind.Objective => "目标"
        case ItemKind.KeyResult => "关键结果"
        case ItemKind.Project => "项目"
        case ItemKind.Action => "行动"
        case ItemKind.Sop => "SOP"
        case ItemKind.Step => "步骤"
        case ItemKind.Milestone => "里程碑"
        case ItemKind.Note => "笔记"
        case ItemKind.Reference => "资料"
    }
}

public func itemStatusLabel(status: ItemStatus): String {
    match (status) {
        case ItemStatus.Inbox => "收件箱"
        case ItemStatus.Next => "下一步"
        case ItemStatus.Active => "进行中"
        case ItemStatus.Waiting => "等待中"
        case ItemStatus.Scheduled => "已排期"
        case ItemStatus.Someday => "将来"
        case ItemStatus.Done => "已完成"
        case ItemStatus.Dropped => "已放弃"
    }
}

public func energyLabel(energy: Energy): String {
    match (energy) {
        case Energy.Low => "低"
        case Energy.Medium => "中"
        case Energy.High => "高"
    }
}

public func runResultLabel(result: RunResult): String {
    match (result) {
        case RunResult.Pass => "通过"
        case RunResult.Fail => "失败"
        case RunResult.Skip => "跳过"
    }
}

/* ------------------------------------------------------------------ */
/* Nested value objects                                                */
/* ------------------------------------------------------------------ */

public class Metric {
    public let start: Float64
    public let target: Float64
    public let current: Float64
    public let unit: String

    public init(start: Float64, target: Float64, current: Float64, unit: String) {
        this.start = start
        this.target = target
        this.current = current
        this.unit = unit
    }
}

public class ChecklistEntry {
    public let id: String
    public let text: String
    public let done: Bool

    public init(id: String, text: String, done: Bool) {
        this.id = id
        this.text = text
        this.done = done
    }
}

public class CanvasPos {
    public let x: Float64
    public let y: Float64

    public init(x: Float64, y: Float64) {
        this.x = x
        this.y = y
    }
}

public class OkrData {
    public let period: String
    public let confidence: Int64
    public let metric: ?Metric
    public let krOwner: ?String

    public init(period: String, confidence: Int64, metric!: ?Metric = None, krOwner!: ?String = None) {
        this.period = period
        this.confidence = confidence
        this.metric = metric
        this.krOwner = krOwner
    }
}

public class SopData {
    public let nodeType: SopNodeType
    public let canvas: CanvasPos
    public let checklist: Array<ChecklistEntry>
    public let owner: ?String
    public let durationMin: ?Int64

    public init(
        nodeType: SopNodeType,
        canvas!: CanvasPos = CanvasPos(0.0, 0.0),
        checklist!: Array<ChecklistEntry> = [],
        owner!: ?String = None,
        durationMin!: ?Int64 = None
    ) {
        this.nodeType = nodeType
        this.canvas = canvas
        this.checklist = checklist
        this.owner = owner
        this.durationMin = durationMin
    }
}

public class GtdData {
    public let capturedAt: String
    public let clarified: Bool
    public let context: ?String
    public let energy: ?Energy
    public let waitingFor: ?String
    public let twoMinuteCandidate: ?Bool

    public init(
        capturedAt: String,
        clarified: Bool,
        context!: ?String = None,
        energy!: ?Energy = None,
        waitingFor!: ?String = None,
        twoMinuteCandidate!: ?Bool = None
    ) {
        this.capturedAt = capturedAt
        this.clarified = clarified
        this.context = context
        this.energy = energy
        this.waitingFor = waitingFor
        this.twoMinuteCandidate = twoMinuteCandidate
    }
}

public class GanttData {
    public let start: ?String
    public let end: ?String
    public let progress: Float64

    public init(start!: ?String = None, end!: ?String = None, progress!: Float64 = 0.0) {
        this.start = start
        this.end = end
        this.progress = progress
    }
}

/* ------------------------------------------------------------------ */
/* Entities                                                            */
/* ------------------------------------------------------------------ */

/** Key order used when the item was not parsed from a document. */
public let ITEM_KEY_ORDER: Array<String> = [
    "id", "kind", "title", "notes", "parentId", "order", "status", "tags", "areaId",
    "createdAt", "updatedAt", "completedAt", "okr", "sop", "gtd", "gantt"
]

public class Item {
    public let id: String
    public let kind: ItemKind
    public let title: String
    public let notes: String
    public let parentId: ?String
    public let order: Int64
    public let status: ItemStatus
    public let tags: Array<String>
    public let areaId: ?String
    public let createdAt: String
    public let updatedAt: String
    public let completedAt: ?String
    public let okr: ?OkrData
    public let sop: ?SopData
    public let gtd: ?GtdData
    public let gantt: ?GanttData
    public let extras: Array<(String, JsonValue)>
    public let keyOrder: Array<String>

    public init(
        id: String,
        kind: ItemKind,
        title: String,
        notes!: String = "",
        parentId!: ?String = None,
        order!: Int64 = 0,
        status!: ItemStatus = ItemStatus.Next,
        tags!: Array<String> = [],
        areaId!: ?String = None,
        createdAt!: String = "",
        updatedAt!: String = "",
        completedAt!: ?String = None,
        okr!: ?OkrData = None,
        sop!: ?SopData = None,
        gtd!: ?GtdData = None,
        gantt!: ?GanttData = None,
        extras!: Array<(String, JsonValue)> = [],
        keyOrder!: Array<String> = []
    ) {
        this.id = id
        this.kind = kind
        this.title = title
        this.notes = notes
        this.parentId = parentId
        this.order = order
        this.status = status
        this.tags = tags
        this.areaId = areaId
        this.createdAt = createdAt
        this.updatedAt = updatedAt
        this.completedAt = completedAt
        this.okr = okr
        this.sop = sop
        this.gtd = gtd
        this.gantt = gantt
        this.extras = extras
        this.keyOrder = keyOrder
    }

    public func isOpen(): Bool {
        status != ItemStatus.Done && status != ItemStatus.Dropped
    }

    public func isDone(): Bool {
        status == ItemStatus.Done
    }

    /** Due date key (`gantt.end`), or None. */
    public func dueKey(): ?String {
        match (gantt) {
            case Some(value) => dateKey(value.end)
            case None => None
        }
    }

    public func startKey(): ?String {
        match (gantt) {
            case Some(value) => dateKey(value.start)
            case None => None
        }
    }
}

public let EDGE_KEY_ORDER: Array<String> = ["id", "from", "to", "type", "label"]

public class Edge {
    public let id: String
    public let from: String
    public let to: String
    public let edgeType: EdgeType
    public let label: String
    public let extras: Array<(String, JsonValue)>
    public let keyOrder: Array<String>

    public init(
        id: String,
        from: String,
        to: String,
        edgeType: EdgeType,
        label!: String = "",
        extras!: Array<(String, JsonValue)> = [],
        keyOrder!: Array<String> = []
    ) {
        this.id = id
        this.from = from
        this.to = to
        this.edgeType = edgeType
        this.label = label
        this.extras = extras
        this.keyOrder = keyOrder
    }
}

public let AREA_KEY_ORDER: Array<String> = ["id", "name", "color", "order"]

public class Area {
    public let id: String
    public let name: String
    public let color: String
    public let order: Int64
    public let extras: Array<(String, JsonValue)>
    public let keyOrder: Array<String>

    public init(
        id: String,
        name: String,
        color: String,
        order!: Int64 = 0,
        extras!: Array<(String, JsonValue)> = [],
        keyOrder!: Array<String> = []
    ) {
        this.id = id
        this.name = name
        this.color = color
        this.order = order
        this.extras = extras
        this.keyOrder = keyOrder
    }
}

public let RUN_KEY_ORDER: Array<String> = ["id", "sopId", "stepId", "at", "result", "note"]

public class SopRunEntry {
    public let id: String
    public let sopId: String
    public let stepId: String
    public let at: String
    public let result: RunResult
    public let note: String
    public let extras: Array<(String, JsonValue)>
    public let keyOrder: Array<String>

    public init(
        id: String,
        sopId: String,
        stepId: String,
        at: String,
        result: RunResult,
        note!: String = "",
        extras!: Array<(String, JsonValue)> = [],
        keyOrder!: Array<String> = []
    ) {
        this.id = id
        this.sopId = sopId
        this.stepId = stepId
        this.at = at
        this.result = result
        this.note = note
        this.extras = extras
        this.keyOrder = keyOrder
    }
}

public let WORKSPACE_KEY_ORDER: Array<String> = ["version", "items", "edges", "areas", "runs", "updatedAt"]

/**
 * The whole document. Instances are immutable by design: every store write
 * builds a new `Workspace`, which is what lets `index()` cache safely and lets
 * every view read the same fact source.
 */
public class Workspace {
    public let version: Int64
    public let items: Array<Item>
    public let edges: Array<Edge>
    public let areas: Array<Area>
    public let runs: Array<SopRunEntry>
    public let updatedAt: String
    public let extras: Array<(String, JsonValue)>
    public let keyOrder: Array<String>
    private var cachedIndex: ?WorkspaceIndex = None

    public init(
        version!: Int64 = WORKSPACE_VERSION,
        items!: Array<Item> = [],
        edges!: Array<Edge> = [],
        areas!: Array<Area> = [],
        runs!: Array<SopRunEntry> = [],
        updatedAt!: String = "",
        extras!: Array<(String, JsonValue)> = [],
        keyOrder!: Array<String> = []
    ) {
        this.version = version
        this.items = items
        this.edges = edges
        this.areas = areas
        this.runs = runs
        this.updatedAt = updatedAt
        this.extras = extras
        this.keyOrder = keyOrder
    }

    public func isEmpty(): Bool {
        items.isEmpty() && edges.isEmpty() && areas.isEmpty() && runs.isEmpty()
    }

    /** Cached selector index; see `selectors.cj`. */
    public func index(): WorkspaceIndex {
        match (cachedIndex) {
            case Some(value) => value
            case None =>
                let built = buildWorkspaceIndex(this)
                cachedIndex = built
                built
        }
    }

    public func withItems(next: Array<Item>): Workspace {
        Workspace(version: version, items: next, edges: edges, areas: areas, runs: runs, updatedAt: updatedAt, extras: extras, keyOrder: keyOrder)
    }

    public func withEdges(next: Array<Edge>): Workspace {
        Workspace(version: version, items: items, edges: next, areas: areas, runs: runs, updatedAt: updatedAt, extras: extras, keyOrder: keyOrder)
    }

    public func withAreas(next: Array<Area>): Workspace {
        Workspace(version: version, items: items, edges: edges, areas: next, runs: runs, updatedAt: updatedAt, extras: extras, keyOrder: keyOrder)
    }

    public func withRuns(next: Array<SopRunEntry>): Workspace {
        Workspace(version: version, items: items, edges: edges, areas: areas, runs: next, updatedAt: updatedAt, extras: extras, keyOrder: keyOrder)
    }

    public func withUpdatedAt(next: String): Workspace {
        Workspace(version: version, items: items, edges: edges, areas: areas, runs: runs, updatedAt: next, extras: extras, keyOrder: keyOrder)
    }
}

/**
 * An empty workspace; `updatedAt` comes from the injected clock.
 *
 * There is no zero-argument overload on purpose: reading the host clock here would
 * make parity documents depend on when the snapshot ran.
 */
public func emptyWorkspace(clock: Clock): Workspace {
    Workspace(updatedAt: nowIso(clock))
}
