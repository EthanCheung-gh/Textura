package textura.views.dashboard.logic

import std.deriving.*

/** 仪表盘读取的 `ItemKind`（与 Web 版 `core/model.ItemKind` 同名同序）。 */
@Derive[Equatable]
public enum DashKind {
    | Objective
    | KeyResult
    | Project
    | Action
    | Sop
    | Step
    | Milestone
    | Note
    | Reference
}

/** 仪表盘读取的 `ItemStatus`（与 Web 版 `core/model.ItemStatus` 同名同序）。 */
@Derive[Equatable]
public enum DashStatus {
    | Inbox
    | Next
    | Active
    | Waiting
    | Scheduled
    | Someday
    | Done
    | Dropped
}

/** SOP 运行结果。 */
@Derive[Equatable]
public enum RunResult {
    | Pass
    | Fail
    | Skip
}

/**
 * 今日视图的条目输入。
 *
 * 这是纯逻辑层的记录类型，不是领域实体：调用方（视图包）负责把 `core.data.Item`
 * 映射进来。`dueDate` 对应 `item.gantt.end`，`okrProgress` 对应 `rollupProgress`。
 */
public struct DashItem {
    public let id: String
    public let title: String
    public let kind: DashKind
    public let status: DashStatus
    /** 已归一化的结束日期键；`null`/短于 10 字符都表示「无日期」。 */
    public let dueDate: ?String
    public let completedAt: ?String
    public let updatedAt: String
    public let createdAt: String
    public let parentId: ?String
    public let order: Int64
    public let areaColor: ?String
    public let okrProgress: ?Int64

    public init(
        id: String,
        title: String,
        kind!: DashKind = DashKind.Action,
        status!: DashStatus = DashStatus.Next,
        dueDate!: ?String = None,
        completedAt!: ?String = None,
        updatedAt!: String = "",
        createdAt!: String = "",
        parentId!: ?String = None,
        order!: Int64 = 0,
        areaColor!: ?String = None,
        okrProgress!: ?Int64 = None
    ) {
        this.id = id
        this.title = title
        this.kind = kind
        this.status = status
        this.dueDate = dueDate
        this.completedAt = completedAt
        this.updatedAt = updatedAt
        this.createdAt = createdAt
        this.parentId = parentId
        this.order = order
        this.areaColor = areaColor
        this.okrProgress = okrProgress
    }
}

/**
 * 一次 SOP 运行的展示输入。
 *
 * `sopTitle`/`stepTitle` 由调用方按 `itemById` 解析后注入：`None` 表示对应条目已不存在，
 * 与 Web 版 `itemById(...) ?? null` 的分支一一对应。
 */
public struct SopRun {
    public let id: String
    public let sopId: String
    public let sopTitle: ?String
    public let stepTitle: ?String
    public let at: String
    public let result: RunResult

    public init(
        id: String,
        sopId: String,
        at: String,
        result!: RunResult = RunResult.Pass,
        sopTitle!: ?String = None,
        stepTitle!: ?String = None
    ) {
        this.id = id
        this.sopId = sopId
        this.at = at
        this.result = result
        this.sopTitle = sopTitle
        this.stepTitle = stepTitle
    }
}

/** `KIND_LABELS` 的仓颉版本。 */
public func kindLabel(kind: DashKind): String {
    match (kind) {
        case Objective => "目标"
        case KeyResult => "关键结果"
        case Project => "项目"
        case Action => "行动"
        case Sop => "SOP"
        case Step => "步骤"
        case Milestone => "里程碑"
        case Note => "笔记"
        case Reference => "资料"
    }
}

/** `RUN_RESULT_LABELS` 的仓颉版本。 */
public func runResultLabel(result: RunResult): String {
    match (result) {
        case Pass => "通过"
        case Fail => "失败"
        case Skip => "跳过"
    }
}

/** `utils.isOpen`：非 done / dropped。 */
public func isOpen(status: DashStatus): Bool {
    status != DashStatus.Done && status != DashStatus.Dropped
}

/** `utils.isDone`。 */
public func isDone(status: DashStatus): Bool {
    status == DashStatus.Done
}
