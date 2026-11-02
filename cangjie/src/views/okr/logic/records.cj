package textura.views.okr.logic

/*
 * OKR 逻辑层的纯数据记录。
 *
 * 本包不依赖 `cui`，也不依赖 `textura.core.data`：视图 worker 负责把
 * `core.data.Item` / `Edge` / `Area` / `Workspace` 映射成这里的记录（映射表见
 * `cangjie/docs/OKR-LOGIC.md`）。字段语义与 Web 版 `src/core/model.ts` 对齐，
 * 只保留 OKR 派生计算真正读取的字段。
 */

/** 与 `core.data.ItemKind` 同名同序的领域种类。 */
public enum OkrItemKind <: Equatable<OkrItemKind> {
    | Objective
    | KeyResult
    | Project
    | Action
    | Sop
    | Step
    | Milestone
    | Note
    | Reference

    public operator func ==(that: OkrItemKind): Bool {
        okrItemKindText(this) == okrItemKindText(that)
    }

    public operator func !=(that: OkrItemKind): Bool {
        !(this == that)
    }
}

/** 与 `core.data.ItemStatus` 同名同序的条目状态。 */
public enum OkrItemStatus <: Equatable<OkrItemStatus> {
    | Inbox
    | Next
    | Active
    | Waiting
    | Scheduled
    | Someday
    | Done
    | Dropped

    public operator func ==(that: OkrItemStatus): Bool {
        okrItemStatusText(this) == okrItemStatusText(that)
    }

    public operator func !=(that: OkrItemStatus): Bool {
        !(this == that)
    }
}

/** 与 `core.data.EdgeType` 同名同序的边类型。 */
public enum OkrEdgeType <: Equatable<OkrEdgeType> {
    | Okr
    | Flow
    | Depends
    | Related

    public operator func ==(that: OkrEdgeType): Bool {
        okrEdgeTypeText(this) == okrEdgeTypeText(that)
    }

    public operator func !=(that: OkrEdgeType): Bool {
        !(this == that)
    }
}

/** TS 里的 `ItemKind` 小写字面量，用于映射表与测试。 */
public func okrItemKindText(kind: OkrItemKind): String {
    match (kind) {
        case OkrItemKind.Objective => "objective"
        case OkrItemKind.KeyResult => "keyresult"
        case OkrItemKind.Project => "project"
        case OkrItemKind.Action => "action"
        case OkrItemKind.Sop => "sop"
        case OkrItemKind.Step => "step"
        case OkrItemKind.Milestone => "milestone"
        case OkrItemKind.Note => "note"
        case OkrItemKind.Reference => "reference"
    }
}

public func okrItemStatusText(status: OkrItemStatus): String {
    match (status) {
        case OkrItemStatus.Inbox => "inbox"
        case OkrItemStatus.Next => "next"
        case OkrItemStatus.Active => "active"
        case OkrItemStatus.Waiting => "waiting"
        case OkrItemStatus.Scheduled => "scheduled"
        case OkrItemStatus.Someday => "someday"
        case OkrItemStatus.Done => "done"
        case OkrItemStatus.Dropped => "dropped"
    }
}

public func okrEdgeTypeText(edgeType: OkrEdgeType): String {
    match (edgeType) {
        case OkrEdgeType.Okr => "okr"
        case OkrEdgeType.Flow => "flow"
        case OkrEdgeType.Depends => "depends"
        case OkrEdgeType.Related => "related"
    }
}

/** 文本 -> 种类；未知文本返回 None（映射层负责报错，逻辑层不猜）。 */
public func okrItemKindFromText(text: String): ?OkrItemKind {
    match (text) {
        case "objective" => Some(OkrItemKind.Objective)
        case "keyresult" => Some(OkrItemKind.KeyResult)
        case "project" => Some(OkrItemKind.Project)
        case "action" => Some(OkrItemKind.Action)
        case "sop" => Some(OkrItemKind.Sop)
        case "step" => Some(OkrItemKind.Step)
        case "milestone" => Some(OkrItemKind.Milestone)
        case "note" => Some(OkrItemKind.Note)
        case "reference" => Some(OkrItemKind.Reference)
        case _ => None
    }
}

public func okrItemStatusFromText(text: String): ?OkrItemStatus {
    match (text) {
        case "inbox" => Some(OkrItemStatus.Inbox)
        case "next" => Some(OkrItemStatus.Next)
        case "active" => Some(OkrItemStatus.Active)
        case "waiting" => Some(OkrItemStatus.Waiting)
        case "scheduled" => Some(OkrItemStatus.Scheduled)
        case "someday" => Some(OkrItemStatus.Someday)
        case "done" => Some(OkrItemStatus.Done)
        case "dropped" => Some(OkrItemStatus.Dropped)
        case _ => None
    }
}

public func okrEdgeTypeFromText(text: String): ?OkrEdgeType {
    match (text) {
        case "okr" => Some(OkrEdgeType.Okr)
        case "flow" => Some(OkrEdgeType.Flow)
        case "depends" => Some(OkrEdgeType.Depends)
        case "related" => Some(OkrEdgeType.Related)
        case _ => None
    }
}

/** 指标四元组，等价于 TS 的 `OkrData['metric']`。 */
public struct OkrMetric <: Equatable<OkrMetric> {
    public let start: Float64
    public let target: Float64
    public let current: Float64
    public let unit: String

    public init(start: Float64, target: Float64, current: Float64, unit!: String = "") {
        this.start = start
        this.target = target
        this.current = current
        this.unit = unit
    }

    public operator func ==(that: OkrMetric): Bool {
        start == that.start && target == that.target && current == that.current && unit == that.unit
    }

    public operator func !=(that: OkrMetric): Bool {
        !(this == that)
    }
}

/** 等价于 TS 的 `OkrData`。`krOwner` 用 `?String` 表示可选。 */
public struct OkrData <: Equatable<OkrData> {
    public let period: String
    public let confidence: Float64
    public let metric: ?OkrMetric
    public let krOwner: ?String

    public init(
        period: String,
        confidence: Float64,
        metric!: ?OkrMetric = None,
        krOwner!: ?String = None
    ) {
        this.period = period
        this.confidence = confidence
        this.metric = metric
        this.krOwner = krOwner
    }

    public operator func ==(that: OkrData): Bool {
        period == that.period && confidence == that.confidence && metric == that.metric && krOwner == that.krOwner
    }
}

/** 甘特排期片段，等价于 TS `GanttData` 的 `start` / `end`（仅展示用）。 */
public struct OkrSchedule <: Equatable<OkrSchedule> {
    public let start: ?String
    public let end: ?String

    public init(start!: ?String = None, end!: ?String = None) {
        this.start = start
        this.end = end
    }

    public operator func ==(that: OkrSchedule): Bool {
        start == that.start && end == that.end
    }
}

/** 等价于 TS 的 `Item`（只含 OKR 派生计算读取的字段）。 */
public class OkrItem {
    public let id: String
    public let kind: OkrItemKind
    public let title: String
    public let notes: String
    public let parentId: ?String
    public let order: Int64
    public let status: OkrItemStatus
    public let tags: Array<String>
    public let areaId: ?String
    public let createdAt: String
    public let okr: ?OkrData

    public init(
        id: String,
        kind: OkrItemKind,
        title: String,
        notes!: String = "",
        parentId!: ?String = None,
        order!: Int64 = 0,
        status!: OkrItemStatus = OkrItemStatus.Next,
        tags!: Array<String> = [],
        areaId!: ?String = None,
        createdAt!: String = "",
        okr!: ?OkrData = None
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
        this.okr = okr
    }
}

/** 等价于 TS 的 `Edge`（字段名用 `fromId` / `toId`，避开仓颉关键字）。 */
public class OkrEdge {
    public let id: String
    public let fromId: String
    public let toId: String
    public let edgeType: OkrEdgeType
    public let label: String

    public init(
        id: String,
        fromId: String,
        toId: String,
        edgeType: OkrEdgeType,
        label!: String = ""
    ) {
        this.id = id
        this.fromId = fromId
        this.toId = toId
        this.edgeType = edgeType
        this.label = label
    }
}

/** 等价于 TS 的 `Area`（OKR 搜索会用到 `name`）。 */
public class OkrArea {
    public let id: String
    public let name: String
    public let color: String
    public let order: Int64

    public init(id: String, name: String, color!: String = "", order!: Int64 = 0) {
        this.id = id
        this.name = name
        this.color = color
        this.order = order
    }
}

/** 等价于 TS 的 `Workspace`（`runs` / `version` / `updatedAt` 与 OKR 计算无关）。 */
public class OkrWorkspace {
    public let items: Array<OkrItem>
    public let edges: Array<OkrEdge>
    public let areas: Array<OkrArea>

    public init(items!: Array<OkrItem> = [], edges!: Array<OkrEdge> = [], areas!: Array<OkrArea> = []) {
        this.items = items
        this.edges = edges
        this.areas = areas
    }
}
