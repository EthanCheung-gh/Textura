package textura.views.dashboard

import std.collection.*
import textura.core.data.*
import textura.views.dashboard.logic as dash

/*
 * `core.data` → `textura.views.dashboard.logic` 的映射与页面级派生数据。
 *
 * 映射表见 `docs/DASHBOARD-LOGIC.md` 第 1 节：`Item` → `DashItem`、`SopRunEntry` → `SopRun`。
 * 「今天」一律来自 `ViewContext.today`（parity 锚点），「现在」来自 store 注入的 `Clock`
 * （parity 用 `FixedClock`），不读系统时钟。
 */

/** 统计卡的语气（`.dash-stat[data-tone]`，dashboard.css:107-125）。 */
enum StatTone {
    | Neutral
    | Accent
    | Ok
    | Warn
    | Danger
    | Info
}

/** OKR 概览的一行。 */
struct ObjectiveRow {
    let id: String
    let title: String
    let progress: Int64

    init(id: String, title: String, progress: Int64) {
        this.id = id
        this.title = title
        this.progress = progress
    }
}

/** SOP 快速启动的一行。 */
struct SopRow {
    let id: String
    let title: String
    let steps: Int64
    let lastRunResult: ?dash.RunResult
    let lastRunAt: ?String

    init(id: String, title: String, steps: Int64, lastRunResult: ?dash.RunResult, lastRunAt: ?String) {
        this.id = id
        this.title = title
        this.steps = steps
        this.lastRunResult = lastRunResult
        this.lastRunAt = lastRunAt
    }
}

/** 今日视图一帧所需的全部展示数据。 */
struct DashboardData {
    let eyebrow: String
    let title: String
    let summary: String
    let inboxCount: Int64
    let completedCount: Int64
    let okrPeriod: String
    let okrAverage: Int64
    let objectives: Array<ObjectiveRow>
    let focus: Array<dash.FocusEntry>
    let focusCounts: dash.FocusCounts
    let sops: Array<SopRow>
    let newestRunLabel: String
    let newestRunMeta: String
    let newestRunTone: StatTone
    let newestRunSopId: ?String
    let activity: Array<dash.ActivityEntry>
    let workspaceEmpty: Bool
    let nowIso: String

    init(
        eyebrow: String,
        title: String,
        summary: String,
        inboxCount: Int64,
        completedCount: Int64,
        okrPeriod: String,
        okrAverage: Int64,
        objectives: Array<ObjectiveRow>,
        focus: Array<dash.FocusEntry>,
        focusCounts: dash.FocusCounts,
        sops: Array<SopRow>,
        newestRunLabel: String,
        newestRunMeta: String,
        newestRunTone: StatTone,
        newestRunSopId: ?String,
        activity: Array<dash.ActivityEntry>,
        workspaceEmpty: Bool,
        nowIso: String
    ) {
        this.eyebrow = eyebrow
        this.title = title
        this.summary = summary
        this.inboxCount = inboxCount
        this.completedCount = completedCount
        this.okrPeriod = okrPeriod
        this.okrAverage = okrAverage
        this.objectives = objectives
        this.focus = focus
        this.focusCounts = focusCounts
        this.sops = sops
        this.newestRunLabel = newestRunLabel
        this.newestRunMeta = newestRunMeta
        this.newestRunTone = newestRunTone
        this.newestRunSopId = newestRunSopId
        this.activity = activity
        this.workspaceEmpty = workspaceEmpty
        this.nowIso = nowIso
    }
}

/** `DashboardPage.tsx:37-43` 的问候语。 */
func greetingFor(hour: Int64): String {
    if (hour < 5) {
        return "夜深了"
    }
    if (hour < 11) {
        return "早上好"
    }
    if (hour < 13) {
        return "中午好"
    }
    if (hour < 18) {
        return "下午好"
    }
    return "晚上好"
}

/** `format(now, 'yyyy年M月d日 EEEE', { locale: zhCN })`（DashboardPage.tsx:198）。 */
func eyebrowFor(nowMillis: Int64): String {
    let date = formatWithPattern(nowMillis, "yyyy年M月d日")
    // `dayOfWeek`: 0 = 周日 … 6 = 周六（core.data/date.cj:520-522）。
    let names: Array<String> = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
    let index = floorModInt(dayOfWeek(nowMillis), 7)
    date + " " + names[index]
}

func floorModInt(value: Int64, modulus: Int64): Int64 {
    let remainder = value % modulus
    if (remainder < 0) {
        remainder + modulus
    } else {
        remainder
    }
}

func toDashKind(kind: ItemKind): dash.DashKind {
    match (kind) {
        case ItemKind.Objective => dash.DashKind.Objective
        case ItemKind.KeyResult => dash.DashKind.KeyResult
        case ItemKind.Project => dash.DashKind.Project
        case ItemKind.Action => dash.DashKind.Action
        case ItemKind.Sop => dash.DashKind.Sop
        case ItemKind.Step => dash.DashKind.Step
        case ItemKind.Milestone => dash.DashKind.Milestone
        case ItemKind.Note => dash.DashKind.Note
        case ItemKind.Reference => dash.DashKind.Reference
    }
}

func toDashStatus(status: ItemStatus): dash.DashStatus {
    match (status) {
        case ItemStatus.Inbox => dash.DashStatus.Inbox
        case ItemStatus.Next => dash.DashStatus.Next
        case ItemStatus.Active => dash.DashStatus.Active
        case ItemStatus.Waiting => dash.DashStatus.Waiting
        case ItemStatus.Scheduled => dash.DashStatus.Scheduled
        case ItemStatus.Someday => dash.DashStatus.Someday
        case ItemStatus.Done => dash.DashStatus.Done
        case ItemStatus.Dropped => dash.DashStatus.Dropped
    }
}

func toDashResult(result: RunResult): dash.RunResult {
    match (result) {
        case RunResult.Pass => dash.RunResult.Pass
        case RunResult.Fail => dash.RunResult.Fail
        case RunResult.Skip => dash.RunResult.Skip
    }
}

/** `.dash-stat`/徽章共用的语气映射：`fail` → 危险、`skip` → 警告、`pass` → 成功。 */
func toneForResult(result: ?dash.RunResult): StatTone {
    match (result) {
        case Some(dash.RunResult.Fail) => StatTone.Danger
        case Some(dash.RunResult.Skip) => StatTone.Warn
        case Some(dash.RunResult.Pass) => StatTone.Ok
        case None => StatTone.Neutral
    }
}

/** `Area.color`（经 `areaId` 查表）；逻辑层只透传，不参与聚合。 */
func areaColorOf(workspace: Workspace, areaId: ?String): ?String {
    match (areaId) {
        case Some(id) => match (areaById(workspace, id)) {
            case Some(area) => Some(area.color)
            case None => None
        }
        case None => None
    }
}

/** `Item` → `DashItem`（docs/DASHBOARD-LOGIC.md §1.1）。 */
func toDashItems(workspace: Workspace): Array<dash.DashItem> {
    let mapped = ArrayList<dash.DashItem>()
    for (item in workspace.items) {
        mapped.add(dash.DashItem(
            item.id,
            item.title,
            kind: toDashKind(item.kind),
            status: toDashStatus(item.status),
            dueDate: item.dueKey(),
            completedAt: item.completedAt,
            updatedAt: item.updatedAt,
            createdAt: item.createdAt,
            parentId: item.parentId,
            order: item.order,
            areaColor: areaColorOf(workspace, item.areaId),
        ))
    }
    mapped.toArray()
}

/** `SopRunEntry` + 两次 `itemById` → `SopRun`（docs/DASHBOARD-LOGIC.md §1.2）。 */
func toSopRuns(workspace: Workspace): Array<dash.SopRun> {
    let mapped = ArrayList<dash.SopRun>()
    for (run in workspace.runs) {
        let sopTitle: ?String = match (itemById(workspace, run.sopId)) {
            case Some(item) => Some(item.title)
            case None => None
        }
        let stepTitle: ?String = match (itemById(workspace, run.stepId)) {
            case Some(item) => Some(item.title)
            case None => None
        }
        mapped.add(dash.SopRun(
            run.id,
            run.sopId,
            run.at,
            result: toDashResult(run.result),
            sopTitle: sopTitle,
            stepTitle: stepTitle
        ))
    }
    mapped.toArray()
}

/**
 * 「现在」的取值顺序：`workspace.updatedAt` → 注入时钟。
 *
 * `updatedAt` 是工作区的逻辑当前时刻：`core.data` 每次写操作都用 `nowIso(clock)` 重新盖章
 * （store.cj:903 `mutate`），因此它在交互运行中恒等于「现在」；parity 场景下它是参考图冻结的
 * 锚点 `2026-03-16T10:00:00+08:00`（docs/PARITY.md §3）。用注入时钟的**日期**（本地零点）
 * 会得到 2026-03-16T00:00+08:00，相对时间就会从「1 天前」漂成「大约 14 小时前」——
 * 这是把今日锚点当成「现在」的典型错误，参考图的 SOP 卡与活动流都用后者。
 */
func referenceNowIso(ctx: ViewContext, workspace: Workspace): String {
    match (parseIsoMillis(workspace.updatedAt)) {
        case Some(_) => workspace.updatedAt
        case None => isoFromMillis(ctx.store.clock.nowMillis())
    }
}

/** 一帧的完整展示数据：只读 store，不写。 */
func loadDashboardData(ctx: ViewContext): DashboardData {
    let workspace = ctx.store.state.value()
    let nowIso = referenceNowIso(ctx, workspace)
    let nowMillis = match (parseIsoMillis(nowIso)) {
        case Some(value) => value
        case None => ctx.store.clock.nowMillis()
    }
    let today = ctx.today
    let items = toDashItems(workspace)
    let runs = toSopRuns(workspace)
    let period = ctx.store.ui.value().okrPeriod

    let focus = dash.buildTodayFocus(items, today)
    let counts = dash.countFocusBuckets(focus)
    let inbox = inboxItems(workspace)
    let completed = dash.completedThisWeek(items, nowIso)

    // DashboardPage.tsx:62-75：当期目标 + rollupProgress，再取平均。
    let objectives = ArrayList<ObjectiveRow>()
    let objectiveInputs = ArrayList<dash.DashItem>()
    for (objective in objectivesOfPeriod(workspace, period)) {
        let progress = rollupProgress(workspace, objective.id)
        objectives.add(ObjectiveRow(objective.id, objective.title, progress))
        objectiveInputs.add(dash.DashItem(
            objective.id,
            objective.title,
            kind: dash.DashKind.Objective,
            status: toDashStatus(objective.status),
            dueDate: objective.dueKey(),
            completedAt: objective.completedAt,
            updatedAt: objective.updatedAt,
            createdAt: objective.createdAt,
            parentId: objective.parentId,
            order: objective.order,
            areaColor: areaColorOf(workspace, objective.areaId),
            okrProgress: Some(progress)
        ))
    }
    let okrAverage = dash.okrAverageProgress(objectiveInputs.toArray())

    let sops = ArrayList<SopRow>()
    var sopCount = 0
    for (sop in itemsOfKind(workspace, ItemKind.Sop)) {
        if (sopCount >= 4) {
            break
        }
        sopCount += 1
        let lastRun = dash.latestRunFor(runs, sop.id)
        let result: ?dash.RunResult = match (lastRun) {
            case Some(run) => Some(run.result)
            case None => None
        }
        let at: ?String = match (lastRun) {
            case Some(run) => Some(run.at)
            case None => None
        }
        sops.add(SopRow(sop.id, sop.title, sopGraph(workspace, sop.id).nodes.size, result, at))
    }

    let newestRun = dash.latestRun(runs)
    let newestRunSopId: ?String = match (newestRun) {
        case Some(run) => Some(run.sopId)
        case None => None
    }
    let newestRunLabel = match (newestRun) {
        case Some(run) => dash.runResultLabel(run.result)
        case None => "—"
    }
    let newestRunMeta = match (newestRun) {
        case Some(run) =>
            let sopTitle = match (itemById(workspace, run.sopId)) {
                case Some(item) => item.title
                case None => "未知 SOP"
            }
            sopTitle + " · " + dash.relativeTime(run.at, nowIso)
        case None => "还没有运行记录"
    }
    let newestRunResult: ?dash.RunResult = match (newestRun) {
        case Some(run) => Some(run.result)
        case None => None
    }

    DashboardData(
        eyebrowFor(nowMillis),
        greetingFor(millisOfDay(nowMillis) / 3600000) + "，今天推进什么？",
        dash.summarizeToday(dash.TodaySummaryInput(counts.overdue, counts.today, inbox.size, counts.undated)),
        inbox.size,
        completed.size,
        period,
        okrAverage,
        objectives.toArray(),
        focus,
        counts,
        sops.toArray(),
        newestRunLabel,
        newestRunMeta,
        toneForResult(newestRunResult),
        newestRunSopId,
        dash.buildActivity(items, runs, limitPerSource: 5),
        workspace.items.size == 0 && workspace.runs.size == 0,
        nowIso
    )
}

/** 条目跳转的视图（src/modules/appshell/navigation.ts `routeForItemKind`）。 */
func routeForKind(kind: dash.DashKind): String {
    match (kind) {
        case dash.DashKind.Objective | dash.DashKind.KeyResult => "okr"
        case dash.DashKind.Sop | dash.DashKind.Step => "sop"
        case dash.DashKind.Project | dash.DashKind.Action | dash.DashKind.Milestone => "gantt"
        case dash.DashKind.Note | dash.DashKind.Reference => "gtd"
    }
}
