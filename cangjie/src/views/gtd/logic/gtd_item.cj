package textura.views.gtd.logic

import std.deriving.*
import std.unicode.*

/*
 * GTD 算法层的输入模型。
 *
 * 本包是纯函数层：不 import `cui`，也不 import `textura.core.data`。
 * UI / store 层负责把 `textura.core.data.Item` 映射为 `GtdItem`
 * （字段对照表见 docs/GTD-LOGIC.md），再把本包产出的意图应用到 workspace。
 *
 * 时间一律是字符串：ISO 时刻（`2026-10-14T17:01:00.000Z`）或日期键
 * （`YYYY-MM-DD`）。时区固定 Asia/Shanghai（UTC+8），本包不读系统时钟：
 * 所有「今天」由调用方注入。
 */

/** 与 `core.data.ItemKind` 一一对应。 */
@Derive[Equatable]
public enum GtdKind {
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

/** 与 `core.data.ItemStatus` 一一对应。 */
@Derive[Equatable]
public enum GtdStatus {
    | Inbox
    | Next
    | Active
    | Waiting
    | Scheduled
    | Someday
    | Done
    | Dropped
}

/** 能量档位；`None` 对应 TS 里 `gtd.energy` 未设置。 */
@Derive[Equatable]
public enum Energy {
    | Low
    | Medium
    | High
}

/** 周回顾「停滞领域」只需要领域身份与名称。 */
public class GtdArea {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        this.id = id
        this.name = name
    }
}

/** `okr.metric` 的纯数据投影，仅 `rollupProgress` 用来算 KR 进度。 */
public class GtdMetric {
    public let start: Float64
    public let target: Float64
    public let current: Float64

    public init(start: Float64, target: Float64, current!: Float64) {
        this.start = start
        this.target = target
        this.current = current
    }
}

/**
 * GTD 层的条目投影：只保留算法需要的字段。
 *
 * `context` / `energy` / `waitingFor` / `capturedAt` 对应 `item.gtd.*`；
 * `startDate` / `dueDate` 对应 `item.gantt.start` / `item.gantt.end`
 * 的原始字符串（未截断，聚合时用 `dateKey` 截断）。
 */
public class GtdItem {
    public let id: String
    public let kind: GtdKind
    public let title: String
    public let notes: String
    public let parentId: ?String
    public let order: Int64
    public let status: GtdStatus
    public let tags: Array<String>
    public let areaId: ?String
    public let createdAt: String
    public let updatedAt: String
    public let completedAt: ?String
    public let capturedAt: ?String
    public let clarified: Bool
    public let context: ?String
    public let energy: ?Energy
    public let waitingFor: ?String
    public let twoMinuteCandidate: Bool
    public let startDate: ?String
    public let dueDate: ?String
    public let metric: ?GtdMetric

    public init(
        id: String,
        kind: GtdKind,
        title: String,
        notes!: String = "",
        parentId!: ?String = None,
        order!: Int64 = 0,
        status!: GtdStatus = GtdStatus.Next,
        tags!: Array<String> = [],
        areaId!: ?String = None,
        createdAt!: String = "",
        updatedAt!: String = "",
        completedAt!: ?String = None,
        capturedAt!: ?String = None,
        clarified!: Bool = false,
        context!: ?String = None,
        energy!: ?Energy = None,
        waitingFor!: ?String = None,
        twoMinuteCandidate!: Bool = false,
        startDate!: ?String = None,
        dueDate!: ?String = None,
        metric!: ?GtdMetric = None
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
        this.capturedAt = capturedAt
        this.clarified = clarified
        this.context = context
        this.energy = energy
        this.waitingFor = waitingFor
        this.twoMinuteCandidate = twoMinuteCandidate
        this.startDate = startDate
        this.dueDate = dueDate
        this.metric = metric
    }
}

/** 工作区投影：`items` 保留输入顺序（TS 的 `ws.items` 顺序）。 */
public class GtdWorkspace {
    public let items: Array<GtdItem>
    public let areas: Array<GtdArea>

    public init(items!: Array<GtdItem> = [], areas!: Array<GtdArea> = []) {
        this.items = items
        this.areas = areas
    }
}

/** 裁剪后的场景名；空串与纯空白都视为「无场景」（null）。 */
public func contextOf(item: GtdItem): ?String {
    match (item.context) {
        case Some(raw) =>
            let trimmed = raw.trim()
            if (trimmed.isEmpty()) {
                None
            } else {
                Some(trimmed)
            }
        case None => None
    }
}

/** 能量排序权重：high=3、medium=2、low=1、未设置=0。 */
public func energyRank(item: GtdItem): Int64 {
    match (item.energy) {
        case Some(Energy.High) => 3
        case Some(Energy.Medium) => 2
        case Some(Energy.Low) => 1
        case None => 0
    }
}

/** 未完成、未放弃。 */
public func isOpen(item: GtdItem): Bool {
    item.status != GtdStatus.Done && item.status != GtdStatus.Dropped
}

/** 已完成或已放弃。 */
public func isClosed(item: GtdItem): Bool {
    item.status == GtdStatus.Done || item.status == GtdStatus.Dropped
}

/** 场景排序序号：预设场景按固定顺序，自定义 100，无场景 999。 */
public func contextOrder(context: String): Int64 {
    if (context == NO_CONTEXT) {
        return 999
    }
    for (index in 0..PRESET_CONTEXTS.size) {
        if (PRESET_CONTEXTS[index] == context) {
            return index
        }
    }
    100
}

/** 空串/`None` 都返回 `None`，便于 `areaId` 这类可选归属。 */
public func nonEmpty(value: ?String): ?String {
    match (value) {
        case Some(raw) =>
            let trimmed = raw.trim()
            if (trimmed.isEmpty()) {
                None
            } else {
                Some(trimmed)
            }
        case None => None
    }
}
