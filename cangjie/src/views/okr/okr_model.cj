package textura.views.okr

import std.collection.{ArrayList, HashMap}
import std.unicode.*
import std.sort.*
import cui.*
import textura.core.data.{Area, Edge, EdgeType, Item, ItemKind, ItemStatus, Metric, Workspace, areaById,
    childrenOf, currentQuarter, itemById, itemKindLabel, itemStatusLabel, itemsOfKind, objectivesOfPeriod,
    okrPeriods, parentPathText}
import textura.ui.{BadgeTone, ProgressTone}
import textura.views.okr.logic.{CivilDate, ConfidenceBucket, ExecutionVia, MetricDraft, OkrArea, OkrData, OkrEdge,
    OkrEdgeType, OkrItem, OkrItemKind, OkrItemStatus, OkrMetric, OkrSchedule, OkrSummary, OkrWorkspace, ObjectiveView,
    confidenceBucket, executionItemsOf, filterObjectives, formatMetric, formatNumber, formatSchedule, isKrBehind,
    metricProgress, metricToDraft, parseCivilDateKey, quarterElapsedPercent, quarterLabel, rollupProgress, summarize,
    unitSuffix}

/*
 * `core.data` → OKR 页数据的映射（`docs/OKR-LOGIC.md` §3 的映射表）。
 *
 * 领域事实只从 `core.data.Workspace` 读；派生数值（进度、落后、信心分布、执行项）全部走
 * `textura.views.okr.logic`，本文件只做类型映射与展示行组装。
 */

/** 一条执行项（KR 关联的项目/行动），带上 `core.data` 的完整条目用于展示。 */
class OkrExecEntry {
    let item: Item
    let via: ExecutionVia
    let edgeId: ?String

    init(item: Item, via: ExecutionVia, edgeId: ?String) {
        this.item = item
        this.via = via
        this.edgeId = edgeId
    }

    /** `GanttData.start/end` → 逻辑层的排期记录，供 `formatSchedule` 使用。 */
    func schedule(): ?OkrSchedule {
        match (item.gantt) {
            case Some(gantt) => Some(OkrSchedule(start: gantt.start, end: gantt.end))
            case None => None
        }
    }
}

/** 一张 KR 行需要的全部派生值。 */
class OkrKrEntry {
    let item: Item
    let progress: Int64
    let behind: Bool
    let confidence: Int64
    let owner: String
    let metric: ?OkrMetric
    let execs: Array<OkrExecEntry>

    init(item: Item, progress: Int64, behind: Bool, confidence: Int64, owner: String, metric: ?OkrMetric,
        execs: Array<OkrExecEntry>) {
        this.item = item
        this.progress = progress
        this.behind = behind
        this.confidence = confidence
        this.owner = owner
        this.metric = metric
        this.execs = execs
    }

    /** `.okr-kr-badges` 的「缺少抓手」：既没有指标，也没有执行项。 */
    func lacksGrip(): Bool {
        metric.isNone() && execs.size == 0
    }
}

/** 一张目标卡需要的全部派生值。 */
class OkrObjEntry {
    let item: Item
    let progress: Int64
    let confidence: Int64
    let krs: Array<OkrKrEntry>
    let allKrCount: Int64
    let area: ?Area

    init(item: Item, progress: Int64, confidence: Int64, krs: Array<OkrKrEntry>, allKrCount: Int64, area: ?Area) {
        this.item = item
        this.progress = progress
        this.confidence = confidence
        this.krs = krs
        this.allKrCount = allKrCount
        this.area = area
    }

    func hiddenKrCount(): Int64 {
        allKrCount - Int64(krs.size)
    }
}

/** 季度条 chip 上要显示的季度与目标数。 */
class OkrPeriodChip {
    let period: String
    let count: Int64
    let isCurrent: Bool
    let isActive: Bool

    init(period: String, count: Int64, isCurrent: Bool, isActive: Bool) {
        this.period = period
        this.count = count
        this.isCurrent = isCurrent
        this.isActive = isActive
    }
}

/** 一帧的页面数据快照（每帧从 store 重建，不跨帧缓存）。 */
class OkrPageData {
    let period: String
    let search: String
    let today: CivilDate
    let summary: OkrSummary
    let entries: Array<OkrObjEntry>
    let chips: Array<OkrPeriodChip>

    init(period: String, search: String, today: CivilDate, summary: OkrSummary, entries: Array<OkrObjEntry>,
        chips: Array<OkrPeriodChip>) {
        this.period = period
        this.search = search
        this.today = today
        this.summary = summary
        this.entries = entries
        this.chips = chips
    }

    func hasQuery(): Bool {
        !search.trim().isEmpty()
    }

    func elapsedPercent(): Int64 {
        Int64(roundPercent(summary.elapsedPercent))
    }
}

/** `YYYY-MM-DD` → `CivilDate`；不可解析时退回 1970-01-01（不读系统时钟）。 */
func okrToday(key: String): CivilDate {
    match (parseCivilDateKey(key)) {
        case Some(value) => value
        case None => CivilDate(1970, 1, 1)
    }
}

/** 由「今天」推出所在季度，避免读系统时钟。 */
func quarterOfDate(today: CivilDate): String {
    let quarter = (today.month - 1) / 3 + 1
    "${today.year}-Q${quarter}"
}

func toOkrKind(kind: ItemKind): OkrItemKind {
    match (kind) {
        case ItemKind.Objective => OkrItemKind.Objective
        case ItemKind.KeyResult => OkrItemKind.KeyResult
        case ItemKind.Project => OkrItemKind.Project
        case ItemKind.Action => OkrItemKind.Action
        case ItemKind.Sop => OkrItemKind.Sop
        case ItemKind.Step => OkrItemKind.Step
        case ItemKind.Milestone => OkrItemKind.Milestone
        case ItemKind.Note => OkrItemKind.Note
        case ItemKind.Reference => OkrItemKind.Reference
    }
}

func toOkrStatus(status: ItemStatus): OkrItemStatus {
    match (status) {
        case ItemStatus.Inbox => OkrItemStatus.Inbox
        case ItemStatus.Next => OkrItemStatus.Next
        case ItemStatus.Active => OkrItemStatus.Active
        case ItemStatus.Waiting => OkrItemStatus.Waiting
        case ItemStatus.Scheduled => OkrItemStatus.Scheduled
        case ItemStatus.Someday => OkrItemStatus.Someday
        case ItemStatus.Done => OkrItemStatus.Done
        case ItemStatus.Dropped => OkrItemStatus.Dropped
    }
}

func toOkrEdgeType(edgeType: EdgeType): OkrEdgeType {
    match (edgeType) {
        case EdgeType.Okr => OkrEdgeType.Okr
        case EdgeType.Flow => OkrEdgeType.Flow
        case EdgeType.Depends => OkrEdgeType.Depends
        case EdgeType.Related => OkrEdgeType.Related
    }
}

/** `core.data.Metric` → 逻辑层 `OkrMetric`。 */
func toOkrMetric(metric: ?Metric): ?OkrMetric {
    match (metric) {
        case Some(value) => Some(OkrMetric(value.start, value.target, value.current, unit: value.unit))
        case None => None
    }
}

/** `docs/OKR-LOGIC.md` §3 的单条映射。 */
func toOkrItem(item: Item): OkrItem {
    let okr: ?OkrData = match (item.okr) {
        case Some(data) => Some(
            OkrData(
                data.period,
                Float64(data.confidence),
                metric: toOkrMetric(data.metric),
                krOwner: data.krOwner
            )
        )
        case None => None
    }
    OkrItem(
        item.id,
        toOkrKind(item.kind),
        item.title,
        notes: item.notes,
        parentId: item.parentId,
        order: item.order,
        status: toOkrStatus(item.status),
        tags: item.tags,
        areaId: item.areaId,
        createdAt: item.createdAt,
        okr: okr
    )
}

func buildOkrWorkspace(workspace: Workspace): OkrWorkspace {
    let items = ArrayList<OkrItem>()
    for (item in workspace.items) {
        items.add(toOkrItem(item))
    }
    let edges = ArrayList<OkrEdge>()
    for (edge in workspace.edges) {
        edges.add(OkrEdge(edge.id, edge.from, edge.to, toOkrEdgeType(edge.edgeType), label: edge.label))
    }
    let areas = ArrayList<OkrArea>()
    for (area in workspace.areas) {
        areas.add(OkrArea(area.id, area.name, color: area.color, order: area.order))
    }
    OkrWorkspace(items: items.toArray(), edges: edges.toArray(), areas: areas.toArray())
}

/** `core.data.ItemStatus` → `.badge--*` 语气（`okrDisplay.ts` 的 STATUS_TONE）。 */
func okrStatusTone(status: ItemStatus): BadgeTone {
    match (status) {
        case ItemStatus.Inbox => BadgeTone.Neutral
        case ItemStatus.Next => BadgeTone.Info
        case ItemStatus.Active => BadgeTone.Accent
        case ItemStatus.Waiting => BadgeTone.Warn
        case ItemStatus.Scheduled => BadgeTone.Info
        case ItemStatus.Someday => BadgeTone.Neutral
        case ItemStatus.Done => BadgeTone.Ok
        case ItemStatus.Dropped => BadgeTone.Neutral
    }
}

/** `.progress-fill--*`：落后优先于 100%，0 与中间值各有语气（`okrDisplay.ts`）。 */
func okrProgressTone(progress: Int64, behind: Bool): ProgressTone {
    if (behind) {
        ProgressTone.Danger
    } else if (progress >= 100) {
        ProgressTone.Ok
    } else if (progress <= 0) {
        ProgressTone.Info
    } else {
        ProgressTone.Accent
    }
}

func confidenceTone(confidence: Int64): BadgeTone {
    match (confidenceBucket(Float64(confidence))) {
        case ConfidenceBucket.Low => BadgeTone.Danger
        case ConfidenceBucket.Mid => BadgeTone.Warn
        case ConfidenceBucket.High => BadgeTone.Ok
    }
}

func confidenceLabel(confidence: Int64): String {
    match (confidenceBucket(Float64(confidence))) {
        case ConfidenceBucket.Low => "低"
        case ConfidenceBucket.Mid => "中"
        case ConfidenceBucket.High => "高"
    }
}

/** 信心值夹紧到 1..10（`ConfidenceScale` 的 `active`）。 */
func clampConfidence(value: Int64): Int64 {
    min(max(value, 1), 10)
}

func okrStatusLabel(status: ItemStatus): String {
    itemStatusLabel(status)
}

func okrKindLabel(kind: ItemKind): String {
    itemKindLabel(kind)
}

/** 从 `Workspace` 组装一帧页面数据。 */
func buildOkrPageData(workspace: Workspace, periodSetting: String, search: String, todayKey: String): OkrPageData {
    let today = okrToday(todayKey)
    let fallbackPeriod = quarterOfDate(today)
    let period = if (periodSetting.isEmpty()) {
        fallbackPeriod
    } else {
        periodSetting
    }
    let okrWorkspace = buildOkrWorkspace(workspace)
    let summary = summarize(okrWorkspace, period, today)
    let elapsed = summary.elapsedPercent
    let views = filterObjectives(okrWorkspace, period, search)
    let entries = ArrayList<OkrObjEntry>()
    for (view in views) {
        match (itemById(workspace, view.objective.id)) {
            case Some(objective) => entries.add(buildObjEntry(workspace, okrWorkspace, view, objective, elapsed))
            case None => ()
        }
    }
    OkrPageData(period, search, today, summary, entries.toArray(), buildPeriodChips(workspace, period, fallbackPeriod))
}

func buildObjEntry(workspace: Workspace, okrWorkspace: OkrWorkspace, view: ObjectiveView, objective: Item,
    elapsedPercent: Float64): OkrObjEntry {
    let krs = ArrayList<OkrKrEntry>()
    for (krView in view.keyResults) {
        match (itemById(workspace, krView.id)) {
            case Some(kr) => krs.add(buildKrEntry(okrWorkspace, kr, elapsedPercent))
            case None => ()
        }
    }
    let allKrs = ArrayList<Item>()
    for (child in childrenOf(workspace, Some(objective.id))) {
        if (child.kind == ItemKind.KeyResult) {
            allKrs.add(child)
        }
    }
    let confidence = match (objective.okr) {
        case Some(data) => clampConfidence(data.confidence)
        case None => Int64(5)
    }
    let area: ?Area = match (objective.areaId) {
        case Some(id) => areaById(workspace, id)
        case None => None
    }
    OkrObjEntry(objective, Int64(roundPercent(rollupProgress(okrWorkspace, objective.id))), confidence,
        krs.toArray(), Int64(allKrs.size), area)
}

func buildKrEntry(okrWorkspace: OkrWorkspace, kr: Item, elapsedPercent: Float64): OkrKrEntry {
    let progress = Int64(roundPercent(rollupProgress(okrWorkspace, kr.id)))
    let confidence = match (kr.okr) {
        case Some(data) => clampConfidence(data.confidence)
        case None => Int64(5)
    }
    let owner = match (kr.okr) {
        case Some(data) => match (data.krOwner) {
            case Some(value) => value
            case None => ""
        }
        case None => ""
    }
    let metric: ?OkrMetric = match (kr.okr) {
        case Some(data) => toOkrMetric(data.metric)
        case None => None
    }
    OkrKrEntry(kr, progress, isKrBehind(Float64(progress), elapsedPercent), confidence, owner, metric, [])
}

/** 执行项：`executionItemsOf`（边优先、再层级子项），再映射回 `core.data.Item`。 */
func buildExecEntries(workspace: Workspace, okrWorkspace: OkrWorkspace, krId: String): Array<OkrExecEntry> {
    let result = ArrayList<OkrExecEntry>()
    for (ref in executionItemsOf(okrWorkspace, krId)) {
        match (itemById(workspace, ref.item.id)) {
            case Some(item) => result.add(OkrExecEntry(item, ref.via, ref.edgeId))
            case None => ()
        }
    }
    result.toArray()
}

/** 季度条：已有季度倒序，当前季度不存在时补进来（`OkrPage.tsx` 的 periodOptions）。 */
func buildPeriodChips(workspace: Workspace, period: String, fallbackPeriod: String): Array<OkrPeriodChip> {
    let existing = ArrayList<String>()
    for (value in okrPeriods(workspace)) {
        existing.add(value)
    }
    var hasPeriod = false
    for (value in existing) {
        if (value == period) {
            hasPeriod = true
        }
    }
    if (!hasPeriod) {
        existing.add(period)
    }
    sort(existing, lessThan: {left, right => left > right}, stable: true)
    let chips = ArrayList<OkrPeriodChip>()
    for (value in existing) {
        chips.add(
            OkrPeriodChip(
                value,
                Int64(objectivesOfPeriod(workspace, value).size),
                value == fallbackPeriod,
                value == period
            )
        )
    }
    chips.toArray()
}

/** KR 状态下拉的选项（`KR_STATUS_OPTIONS`）。 */
let OKR_KR_STATUSES: Array<ItemStatus> = [
    ItemStatus.Next,
    ItemStatus.Active,
    ItemStatus.Waiting,
    ItemStatus.Scheduled,
    ItemStatus.Done,
    ItemStatus.Dropped
]

/**
 * 链接执行项弹窗的候选池（`LinkItemsDialog.tsx` 的 `candidates`）。
 *
 * 全部项目 + 行动，排除 `dropped`（已放弃的条目不该再被关联），按「父级路径 → 标题」
 * 排序，让同一目标/项目下的执行项连续出现（Web 版依赖创建顺序，这里给出稳定顺序）。
 */
func okrLinkCandidates(workspace: Workspace): Array<Item> {
    let pool = ArrayList<Item>()
    for (item in itemsOfKind(workspace, ItemKind.Project)) {
        if (item.status != ItemStatus.Dropped) {
            pool.add(item)
        }
    }
    for (item in itemsOfKind(workspace, ItemKind.Action)) {
        if (item.status != ItemStatus.Dropped) {
            pool.add(item)
        }
    }
    sort(pool, lessThan: {left, right =>
        let leftPath = parentPathText(workspace, left.id)
        let rightPath = parentPathText(workspace, right.id)
        if (leftPath != rightPath) {
            leftPath < rightPath
        } else {
            left.title < right.title
        }
    }, stable: true)
    pool.toArray()
}

/** 指标摘要文本（`formatMetric`）。 */
func metricText(metric: ?OkrMetric): String {
    formatMetric(metric)
}
