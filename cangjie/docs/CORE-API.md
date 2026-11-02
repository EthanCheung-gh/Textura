# `textura.core.data` 公开 API（视图接入必读）

本文件列出 `cangjie/src/core/data/` 的**全部公开类型与函数**，供 7 个视图 worker 直接查阅。
包内实现对应 Web 版 `src/core/{model,repo,store,selectors,utils,fixtures,history}.ts` 与
`src/modules/{dashboard,gtd,okr,gantt,sop}` 里的纯函数层。

约定：

- 依赖：`std.*` only。**不 import `cui` / `textura.ui` / `textura.shell` / 任何 view**。
- 时间：一律用 `Int64` epoch 毫秒；显示时区固定 `Asia/Shanghai`（`LOCAL_OFFSET_MINUTES = 480`）。
  不要读系统时钟，用 `store.clock`、`ViewContext.today` 或注入 `FixedClock`。
- 颜色/尺寸：本包只包含**领域数据**（`Area.color` 调色板），不含设计令牌。
- 返回值里的 `Array` 属于内部索引缓存：**只读**，不要原地排序/修改。

---

## 1. 接入点（每个视图必须实现）

```cangjie
// textura.core.data
public class ViewContext {
    public let store: AppStore
    public let theme: String        // "light" | "dark"
    public let today: String        // "YYYY-MM-DD"，parity 下来自 workspace 锚点，不读系统时钟
    public let width: Int64
    public let height: Int64
    public let navigate: (String) -> Unit   // 视图内跳转，参数是 route id
}
```

每个视图包暴露 `public func render(ctx: ViewContext): Unit`，由 shell 在自己的 CUI 声明块内调用。
视图**不得 import shell**；需要跳转就用 `ctx.navigate("gtd")`。

最小骨架：

```cangjie
package textura.views.gtd

import cui.*
import textura.core.data.*
import textura.ui.*

public func render(ctx: ViewContext): Unit {
    let workspace = ctx.store.state.value()          // 同一事实来源
    let today = ctx.today
    let focus = buildTodayFocus(workspace, today)
    VStack(spacing: 12.vp) {
        Label("下一步 ${focus.size} 项")
        ForEach(focus, key: {entry => entry.item.id}) { entry =>
            Label(entry.item.title)                    // 只读快照
        }
    }
}
```

CUI 每帧重建界面，因此每帧读 `ctx.store.state.value()` 就是响应式；写操作走 `ctx.store.*`，
下一帧自动看到新数据。`AppStore` 另外提供 `revision()` / `subscribe()`，供 shell 需要显式钩子时使用。

---

## 2. `model.cj` — 领域模型（与 `model.ts` 逐字段对齐）

| 类型 | 说明 |
|---|---|
| `ItemKind` | `Objective` `KeyResult` `Project` `Action` `Sop` `Step` `Milestone` `Note` `Reference` |
| `ItemStatus` | `Inbox` `Next` `Active` `Waiting` `Scheduled` `Someday` `Done` `Dropped` |
| `Energy` | `Low` `Medium` `High` |
| `SopNodeType` | `Start` `Action` `Decision` `Check` `End` `Note` |
| `EdgeType` | `Okr` `Flow` `Depends` `Related` |
| `RunResult` | `Pass` `Fail` `Skip` |
| `NoticeTone` | `Info` `Success` `Error` |
| `Metric` | `start` `target` `current`(Float64) `unit` — `OkrData.metric` |
| `ChecklistEntry` | `id` `text` `done` — `SopData.checklist[]` |
| `CanvasPos` | `x` `y` — `SopData.canvas` |
| `OkrData` | `period` `confidence: Int64` `metric: ?Metric` `krOwner: ?String` |
| `SopData` | `nodeType` `canvas` `checklist` `owner: ?String` `durationMin: ?Int64` |
| `GtdData` | `capturedAt` `clarified` `context: ?String` `energy: ?Energy` `waitingFor: ?String` `twoMinuteCandidate: ?Bool` |
| `GanttData` | `start: ?String` `end: ?String` `progress: Float64`（`start`/`end` 是 `YYYY-MM-DD` 或 ISO） |
| `Item` | `id` `kind` `title` `notes` `parentId: ?String` `order: Int64` `status` `tags: Array<String>` `areaId: ?String` `createdAt` `updatedAt` `completedAt: ?String` `okr?` `sop?` `gtd?` `gantt?` |
| `Edge` | `id` `from` `to` `edgeType`（JSON 里叫 `type`）`label` |
| `Area` | `id` `name` `color` `order` |
| `SopRunEntry` | `id` `sopId` `stepId` `at` `result: RunResult` `note` |
| `Workspace` | `version: Int64` `items` `edges` `areas` `runs` `updatedAt` |

`Item` / `Edge` / `Area` / `SopRunEntry` / `Workspace` 额外有两个**只用于无损 JSON 往返**的字段：

- `keyOrder: Array<String>`：解析时记住的磁盘键序（新建对象为空 → 用 `model.ts` 声明序）；
- `extras: Array<(String, JsonValue)>`：未知字段原样保留，不会被丢弃。

**不要为某个视图给 `Item` 加字段**；派生数据放 selectors 或视图自己的 logic 包。

便利方法：`Item.isOpen()`、`Item.isDone()`、`Item.dueKey()`、`Item.startKey()`；
`Workspace.index()`（选择器索引，惰性构建并缓存）；`Workspace.withItems/withEdges/withAreas/withRuns/withUpdatedAt`；
`emptyWorkspace(clock)`（必须传 `Clock`，没有无参重载）。

常量 / 标签：

| API | 用途 |
|---|---|
| `WORKSPACE_VERSION` | 当前文档版本，`1` |
| `ITEM_KINDS` / `ITEM_STATUSES` | 枚举全集（顺序与 Web 一致） |
| `itemKindWire` / `parseItemKind` | `ItemKind` ↔ JSON 字符串 |
| `itemStatusWire` / `parseItemStatus` | `ItemStatus` ↔ JSON 字符串 |
| `energyWire` / `parseEnergy` | `Energy` ↔ JSON 字符串 |
| `sopNodeTypeWire` / `parseSopNodeType` | `SopNodeType` ↔ JSON 字符串 |
| `edgeTypeWire` / `parseEdgeType` | `EdgeType` ↔ JSON 字符串 |
| `runResultWire` / `parseRunResult` | `RunResult` ↔ JSON 字符串 |
| `noticeToneWire` | `NoticeTone` ↔ JSON 字符串 |
| `itemKindLabel` / `itemStatusLabel` / `energyLabel` / `runResultLabel` | 中文展示文案 |
| `ITEM_KEY_ORDER` / `EDGE_KEY_ORDER` / `AREA_KEY_ORDER` / `RUN_KEY_ORDER` / `WORKSPACE_KEY_ORDER` | 规范化键序 |

枚举都实现了 `==` / `!=`（Cangjie 无载荷枚举不自动比较），可直接写 `item.status == ItemStatus.Done`。

---

## 3. `json.cj` — JSON 编解码（无第三方依赖）

标准库没有 JSON，本包自带，目标是**与 `JSON.stringify(v, null, 2)` 字节兼容**。

| API | 用途 |
|---|---|
| `JsonValue` | `JsonNull` / `JsonBool` / `JsonInt` / `JsonFloat` / `JsonString` / `JsonArray` / `JsonObject(Array<(String, JsonValue)>)`（保序） |
| `JsonError <: Exception` | 语法错误，带 `position` |
| `parseJson(text)` | 解析；未知结构原样保留，重复键取首位置+末值 |
| `writeJson(value)` | 2 空格缩进美化输出，无尾随换行 |
| `writeJsonCompact(value)` | 单行输出（日志/诊断） |
| `quoteJsonString(text)` | 与 JS 相同的转义（不转义 `/`，非 ASCII 原样） |
| `formatJsonNumber(value)` | `1.0→"1"`、`2.1→"2.1"`、`1e21→"1e+21"`、非有限值 `null` |
| `repeatText(text, count)` | 字符串重复（标准库无 `String.repeat`） |

---

## 4. `codec.cj` — 工作区文档读写

| API | 用途 |
|---|---|
| `workspaceToJson(ws)` / `workspaceToJsonText(ws)` | 结构化 / 美化 JSON（无尾随换行） |
| `encodeWorkspaceDocument(ws)` | 落盘文本：美化 JSON + 尾随 `\n`（与 `tools/parity/workspace.json` 一致） |
| `canonicalWorkspaceJsonText(ws)` | **与键序无关**的单行语义文本（测试/语义 diff 用） |
| `normalizeWorkspaceWithCorrections(json, clock)` | 归一化 + 修正摘要 |
| `migrateWorkspace(json, clock)` / `migrateWorkspaceWithReport` | 导入路径：严格归一化，**父子环直接报错** |
| `normalizeForLoad(json, clock)` | 加载路径：归一化 + 切断父子环并记录，脏数据不白屏 |
| `parseWorkspaceText(text, clock)` | 解析 + 严格迁移（导入用） |
| `loadWorkspaceFromPath(path, clock)` | 读文件；文件缺失/为空 → `freshInstall = true` |
| `mergeCorrectionSummaries` / `cycleLabels` | 摘要合并、环的可读描述 |
| `LoadedWorkspace` | `workspace` `freshInstall` `parentCycles` `corrections` |
| `MigratedWorkspace` | `workspace` `corrections` |
| `CorrectionSummary` / `NormalizationCorrection` | `total` + 最多 20 条 `(itemId, field, from, to)` |
| `WorkspaceVersionError` | 文档版本高于当前应用时抛出 |

序列化保证：

1. `tools/parity/workspace.json` 读入再写出**字节完全相同**（键序、缩进、数字格式、尾随换行）；
2. 未知字段透传（`extras` + `keyOrder`），不会丢；
3. 可选块（`okr`/`sop`/`gtd`/`gantt`）为空时整块省略，可空字段（`parentId`/`areaId`/`completedAt`/`gantt.start`/`gantt.end`）显式写 `null`。

---

## 5. `date.cj` — 日期时间（`Asia/Shanghai`）

| API | 用途 |
|---|---|
| `Clock` / `SystemClock` / `FixedClock(at)` | 可注入时钟；测试与 parity 用 `FixedClock` |
| `systemNowMillis()` | 唯一读系统时钟的底层函数 |
| `parseIsoMillis(text)` | 解析 `YYYY-MM-DD`、`YYYY-MM-DDTHH:mm:ss(.SSS)?`、`Z` / `±HH:MM`；缺失时区按 +08:00 |
| `isoFromMillis(ms)` | `Date#toISOString()` 等价（`...Z`，毫秒 3 位） |
| `localDateKey(ms)` / `localDateTimeKey(ms)` | 本地 `YYYY-MM-DD` / `YYYY-MM-DD HH:mm` |
| `nowIso(clock)` | 当前 UTC ISO（与 TS `nowIso()` 一致）。**没有无参重载**：读系统时钟必须显式传 `Clock` |
| `quarterOfDateKey(key)` | `YYYY-MM-DD` → `2026-Q1`；无法解析返回 `None` |
| `currentQuarter(ms)` / `currentQuarter(clock)` | `2026-Q1` |
| `quarterRange(period)` → `QuarterRange(start, end)` | 季度首末日；非法返回 `None` |
| `dayOffset(days, ms/clock)` | 相对偏移后的本地日期键 |
| `isoOffset(days, ms/clock)` | 相对偏移后的 UTC ISO |
| `addDaysToKey(key, days)` | 日期键加天数 |
| `daysBetween(fromISO, toISO)` | 日历天差（`to - from`） |
| `dateKey(value) -> ?String` | 截取前 10 字符（与原 TS `dateKey` 等价，注意是 UTC 前缀） |
| `parseDateKey(value) -> ?Int64` | 日期键 → 本地零点毫秒 |
| `formatDateKey(value, pattern = "MM/dd")` | 格式化，非法返回 `—` |
| `formatDateTime(value)` | `yyyy-MM-dd HH:mm`，非法返回 `—` |
| `formatWithPattern(ms, pattern)` | 支持 `yyyy yy MM M dd d HH H mm ss SSS` 与字面量 |
| `dayOfWeek(ms)` `startOfWeekKey` `endOfWeekKey` `startOfMonthKey` `endOfMonthKey` `yearOfKey` | 日历边界（周从周一开始） |
| `dayIndex(ms)` / `millisOfDay(ms)` | 本地日序号 / 日内毫秒 |
| `relativeDayLabel(iso, nowMs)` | 今天 / 昨天 / n 天前 / MM/dd |
| `relativeTimeText(iso, nowMs)` | 「约 2 小时前」式相对时间（近似 date-fns 文案） |
| `LOCAL_OFFSET_MINUTES` `MILLIS_PER_DAY` `MILLIS_PER_MINUTE` | 常量 |

---

## 6. `selectors.cj` — 核心选择器（`selectors.ts` 逐条移植）

索引类：`WorkspaceIndex`（`byId` `children` `byKind` `objectivesByPeriod` `byStatus` `edgesFrom` `edgesTo` `areas` `rollups` `paths` `descendants` `ancestors`），
通过 `workspace.index()` 取得（每个 `Workspace` 实例只构建一次）。

| API | 用途 |
|---|---|
| `itemById(ws, id)` / `areaById(ws, areaId)` | 单条查询 |
| `childrenOf(ws, parentId)` / `rootItems(ws)` | 直接子项 / 根级条目（按 `order`、`createdAt` 排序） |
| `descendantsOf(ws, id)` / `ancestorsOf(ws, id)` | 子孙（DFS）/ 祖先（最近优先），带环保护 |
| `findParentCycles(ws)` | 全部父子环，`['a','b','a']` 形式 |
| `itemsOfKind(ws, kind)` / `objectivesOfPeriod(ws, period)` / `okrPeriods(ws)` | 分类查询，周期倒序 |
| `rollupProgress(ws, id)` | 0..100 汇总进度（Objective=KR 均值；KR=metric 换算或子项完成比；Project/SOP=子项完成比；其余=done?100:0） |
| `inboxItems` `nextActions` `waitingItems` `somedayItems` | GTD 基础列表 |
| `scheduledRows(ws)` / `scheduledItemsInRange(ws, fromISO, toISO)` | 有日期条目 / 区间相交（边界包含、按 start 升序） |
| `overdueItems(ws, today)` / `dueTodayItems(ws, today)` | 超期 / 今天到期（仅未完成未放弃） |
| `edgeTargetsOf(ws, id, type)` / `edgeSourcesOf(ws, id, type)` | 出边目标 / 入边来源（去重） |
| `sopGraph(ws, sopId)` → `SopGraph(nodes, edges)` | SOP 步骤节点 + 两端都在节点集的 `flow` 边 |
| `countByStatus(ws)` | 状态计数（wire 名 → Int64） |
| `treeDepth(ws, id)` / `itemPathTitles(ws, id)` / `parentPathText(ws, id)` | 层级深度 / 根→自身标题 / 面包屑文本 |
| `countByStatus` `scheduledRows` `ScheduledRow` | 同上 |
| `buildWorkspaceIndex(ws)` | 显式构建索引（一般用 `workspace.index()` 即可） |

---

## 7. `derive_today.cj` — 仪表盘派生

| API | 用途 |
|---|---|
| `buildTodayFocus(ws, today)` → `Array<FocusEntry>` | 超期 + 今日到期 + 无日期下一步，按 id 去重（超期 > 今天 > 无日期）后排序 |
| `FocusEntry` | `item` `bucket` `due` `daysLate` `pathTitles` `source` |
| `FocusBucket` / `focusBucketWire` | `Overdue` / `Today` / `Undated` |
| `FocusSource` / `focusSourceWire` | `Plain` / `Sop` / `Okr` |
| `countFocusBuckets(entries)` → `FocusCounts(overdue, today, undated)` | 分组计数 |
| `paginateFocus(entries, limit)` → `FocusPage(items, shown, total, remaining, hasMore)` | 首屏分页 |
| `FOCUS_PAGE_SIZE` | 100 |
| `summarizeToday(overdue, today, inbox, next)` | 一句话摘要（与 Web 文案一致） |
| `completedThisWeek(ws, nowMs, days = 7)` | 近 N 天完成，完成时间倒序 |
| `recentlyCompleted(ws, limit = 5)` | 最近完成（不限窗口） |
| `sortedRuns(ws)` / `latestRun(ws)` / `latestRunFor(ws, sopId)` | 运行记录排序与最新一条 |
| `buildActivity(ws, limitPerSource = 5)` → `Array<ActivityEntry>` | runs + 完成记录合并，时间倒序 |
| `ActivityEntry` / `ActivityKind` / `activityKindWire` | 活动条目 |

---

## 8. `derive_gtd.cj` — GTD 派生

| API | 用途 |
|---|---|
| `NO_CONTEXT` `NO_CONTEXT_FILTER` `PRESET_CONTEXTS` `WAITING_WARN_DAYS` `LIST_PAGE_SIZE` | 常量 |
| `currentDateKey(clock)` / `localDayKey(value)` | 本地日期键（`localDayKey` 会先解析时区） |
| `contextOf(item)` / `energyRank(item)` | 场景 / 能量排序权重 |
| `sortInboxItems(items)` | 收件箱按 `gtd.capturedAt` 倒序 |
| `groupByContext(items)` → `Array<ContextGroup(context, items)>` | 场景分组：预设顺序 → 自定义字典序 → 无场景最后。分组按**首次出现顺序**收集（不用 `HashMap` 迭代序），再稳定排序，与 `views/gtd/logic` 实现一致 |
| `sortNextActions(items)` | 截止日期升序 → 能量降序 → 创建时间 |
| `matchesSearch(item, search)` / `NextFilter` / `filterNextActions(items, filter)` | 搜索与筛选（场景、近期截止、领域） |
| `isStuckProject(ws, projectId)` | 停滞项目判定（无子项 / 无 next / 全完成都算「不算停滞」的规则与 Web 一致） |
| `projectHealth(ws)` → `Array<ProjectHealth(project,total,done,open,next,progress,stuck)>` | 项目健康度 |
| `waitingSince(item)` / `waitingDays(item, today)` / `isWaitingOverdue(item, today, threshold = 7)` | 等待天数 |
| `weeklyReview(ws, today)` → `WeeklyReviewStats` | 周回顾：收件箱清零进度、本周完成、超期、停滞项目、等待超期、无日期任务、久未触碰领域 |
| `StaleArea` / `WeeklyReviewStats` | 上述结果类型 |
| `deadlineInfo(item, today)` → `DeadlineInfo(label, tone, date)` | 截止日期文案与语气（`Danger`/`Accent`/`Muted`） |
| `appendTimestampedNote(notes, message, atMs)` | 追加带时间戳的备注行 |
| `ClarifyFormState` / `ClarifyErrors` / `ClarifyType` | 澄清表单状态与校验结果 |
| `resolveFormContext` `desiredKind` `isArchiveType` `clarifyTargetStatus` `validateClarifyForm` `createClarifyForm` | 澄清表单纯函数 |

---

## 9. `derive_okr.cj` — OKR 派生

| API | 用途 |
|---|---|
| `quarterElapsedPercent(period, todayMs)` | 季度已过百分比（首日 0、末日 100） |
| `isKrBehind(progress, elapsedPercent)` | 落后时间进度 ≥ 10 个点 |
| `BEHIND_MARGIN_POINTS` | 10.0 |
| `confidenceBucket(n)` → `ConfidenceBucket` | 1–3 低 / 4–6 中 / 7–10 高 |
| `hasMetricRange(metric)` / `metricProgressInfo(metric)` / `metricPercent(metric)` | 指标换算状态（`Unset`/`Invalid`/`Flat`/`Under`/`InRange`/`Over`） |
| `MetricProgressInfo` | `state` `percent: ?Float64` `clamped` |
| `summarizeOkr(ws, period, todayMs)` → `OkrSummary` | 目标数、KR 数、平均进度、落后 KR、信心分布、时间进度 |
| `executionItemsOf(ws, krId)` → `Array<ExecutionItemRef(item, via, edgeId)>` | KR 的执行项（okr 边 + parentId，边优先） |
| `ExecutionLink` | `Edge` / `Child` |
| `filterObjectives(ws, period, query)` → `Array<ObjectiveView>` / `matchesOkrQuery` | 目标 + 过滤后的 KR |
| `shiftQuarter(period, delta)` / `nextQuarter` / `quarterLabel` | 季度位移与展示 |
| `roundTo(value, digits)` | 定点四舍五入 |

---

## 10. `derive_gantt.cj` — 甘特派生

| API | 用途 |
|---|---|
| `GanttZoom` / `ganttZoomWire` / `parseGanttZoom` | `Day` / `Week` / `Month` |
| `zoomConfig(zoom)` → `ZoomConfig(paddingBefore, paddingAfter, columnDays)` | 适配窗口留白（像素宽度属视图） |
| `BarRange(start, end)` / `normalizeBar(start, end)` / `itemRange(item)` | 任务条区间（缺一端按一天） |
| `displayProgress(item)` | 甘特展示进度（`done` 恒 100，其余夹紧 0..100） |
| `buildRange(items, zoom, today)` | 时间轴范围（覆盖全部 bars + today，周/月对齐） |
| `isGanttableItem(item)` / `GANTTABLE_KINDS` | 可显示条目（project/action/milestone，排除 inbox/someday/dropped） |
| `buildGanttRows(ws, collapsed)` → `Array<GanttRow>` | 左侧行模型：project/SOP 分组 + 组内条目 + 「未分组」 |
| `GanttRow` / `GanttRowKind` / `ganttRowKindWire` | 行类型（`kind` `id` `title` `item` `depth` `groupId` `count` `start` `end` `progress` `collapsed`） |
| `UNGROUPED_ID` | `"__ungrouped"` |
| `dependencyEdges(ws)` | 全部 `depends` 边（画依赖箭头用） |
| `diffDaysKey(from, to)` / `snapDateKey(key, zoom)` | 日期差 / 吸附 |

---

## 11. `derive_sop.cj` — SOP 派生

| API | 用途 |
|---|---|
| `sopList(ws)` → `Array<SopSummary(sop, stepCount, runCount, latestRun, completion)>` | SOP 列表与汇总 |
| `sopSteps(ws, sopId)` | 流程内步骤（flow 顺序） |
| `recentRunsFor(ws, sopId, limit = 10)` | 该 SOP 的运行历史（新→旧） |
| `sopRunTally(ws, sopId)` → `SopRunTally(pass, fail, skip)` | 结果计数 |

---

## 12. `store.cj` — `AppStore`（唯一事实来源）

```cangjie
public class AppStore {
    public let state: StateCell<Workspace>      // 工作区事实
    public let ui: StateCell<UiState>           // route/theme/okrPeriod/ganttZoom/gtdContext/search/…
    public let notices: StateCell<Array<Notice>>// 最多 4 条
    public let selectedId: StateCell<?String>
    public let clock: Clock
}
```

> **与 Web 版的差异（有意）**：Web 用 `zustand` + `State<Workspace>`；这里用 `StateCell<T>`（`value()` / `set()` /
> `revision()` / `subscribe()`），因为 `core.data` 不允许依赖 `cui`（见 `STRUCTURE.md` §2）。CUI 每帧重建，
> 视图每帧读 `state.value()` 即是响应式；需要显式通知的 shell 用 `subscribe()`。

### 构造：parity 与交互两条路径（禁止静默读系统时钟）

```cangjie
// 1) parity / 快照：时钟与「今天」都冻结在工作区锚点上
public static func forParity(anchorDate: String): AppStore   // anchor 不可解析时抛 IllegalArgumentException

// 2) 交互运行：调用方显式给出时钟（没有默认值）
public init(clock!: Clock, todayOverride!: ?String = None)
```

- `main.cj` 的规则：`--today` > `workspace.updatedAt` 的日期 → `AppStore.forParity(anchor)`；
  有 workspace/`--today` 但锚点不可解析时用 `AppStore(clock: FixedClock(0))`（确定性，绝不回落墙上时钟）；
  只有在完全没有 parity 意图的交互启动时才用 `AppStore(clock: SystemClock())`。
- `anchorToday()`：有 `todayOverride`（parity / `--today`）就用它，否则用注入时钟的本地日期。
  **不会**再回落到「工作区 `updatedAt`」，避免打开旧文件时把旧季度当成当前季度。
- `setTodayOverride(today)`：运行中改锚点（并重算 `ui.okrPeriod`）。
- `initialOkrPeriod(workspace, today)`：打开哪个 OKR 周期，规则与 `store.ts` 一致——
  「当前」季度（= **锚点日期**所在季度）在周期列表中就选它，否则取最新周期，列表为空则用锚点季度。
  另有 `initialOkrPeriod(workspace, clock)` 供非 parity 场景使用。

读取：

| API | 用途 |
|---|---|
| `state.value()` / `workspace()` / `revision()` | 当前工作区 / 修订号 |
| `storeStatus()` / `saveStatus()` / `error()` / `savedBytes()` / `path()` | 状态与诊断 |
| `anchorToday()` | 「今天」：parity 为 `todayOverride`（`--today` / workspace 锚点），交互运行为注入时钟的本地日期 |
| `setTodayOverride(today)` | 冻结/解冻「今天」，并同步重算 `ui.okrPeriod` |
| `ui.value()` | `UiState`（`route` `theme` `okrPeriod` `ganttZoom` `gtdContext` `search` `inspectorOpen` `paletteOpen` `quickCaptureOpen` `shortcutsOpen`） |
| `selectedId.value()` / `selected()` | 选中条目 |
| `canUndo()` / `canRedo()` / `historySteps()` / `historyLimit()` | 历史栈（上限 80） |

生命周期与持久化：

| API | 用途 |
|---|---|
| `load(path)` | 读文件；空库首装自动播种演示数据；修正摘要 / 父子环通知 |
| `loadFromText(text)` | 从内存文档加载（测试、粘贴导入） |
| `reload()` | 重新读 `path()` |
| `save()` / `saveTo(path)` | **原子写**（`<path>.tmp` → rename）；失败写错误通知并返回 `false` |
| `exportDocument()` | 导出文本（美化 JSON + 尾随换行） |
| `importDocument(text)` | 严格导入（环 → 报错不落库），返回错误信息或 `None` |

写操作（每次都会记录撤销快照并生成新的 `Workspace`）：

| API | 用途 |
|---|---|
| `createItem(NewItemInput)` | 新建（按 kind 补默认 `okr`/`sop`/`gtd`/`gantt`） |
| `updateItem(id, ItemPatch)` / `updateItems(Array<ItemPatchTarget>)` | 打补丁（顶层字段 + 四个数据块浅合并） |
| `deleteItems(ids)` | 级联删除子孙、相关边与运行记录 |
| `moveItem(id, parentId, order)` | 改父级 + 同级重排（禁止移到自身子孙下） |
| `toggleDone(id)` / `setStatus(id, status)` | 完成/状态（自动维护 `completedAt`） |
| `createEdge(from, to, edgeType, label)` / `updateEdge(id, label)` / `deleteEdge(id)` | 依赖/关联边（同 `(from,to,type)` 去重） |
| `addDependency(from, to, label)` / `removeDependency(from, to)` | 甘特依赖快捷方式 |
| `linkOkr(krId, itemId)` | 建 `okr` 边（KR ↔ 执行项） |
| `createArea(name)` / `updateArea(id, name, color)` / `deleteArea(id)` | 领域（删除时把 `areaId` 置空） |
| `logRun(sopId, stepId, result, note)` | SOP 运行记录 |
| `quickCapture(title, context)` | 快速收集：`inbox` 状态的 action |
| `clarify(id, form)` | 澄清表单落库（校验失败返回 `ClarifyErrors`，不写库） |
| `reschedule(id, start, end)` / `setDueDate(id, due)` / `setProgress(id, progress)` | 改期 / 截止 / 进度 |
| `setMetric(id, start, target, current, unit)` / `setMetricCurrent(id, current)` / `setConfidence(id, n)` / `setOkrPeriod(id, period)` | OKR 指标与信心 |
| `undo()` / `redo()` | 撤销 / 重做 |
| `select(id)` | 选中 |
| `notify(message, tone)` / `dismissNotice(id)` / `clearNotices()` | 通知 |
| `setUi({state => ...})` / `setRoute` / `setTheme` / `toggleTheme` / `setSearch` / `setOkrPeriod` / `setGanttZoom` / `setGtdContext` | UI 状态 |

补丁类型（`SetValue<T>` = `Unset` | `Value(T)`，`Unset` 表示「不改」）：

- `ItemPatch`：`withTitle` `withNotes` `withParentId` `withOrder` `withStatus` `withTags` `withAreaId`
  `withOkr` `withSop` `withGtd` `withGantt`，以及快捷 `withProgress` `withDueDate` `withGanttRange`。
- `OkrPatch`（`period` `confidence` `metric` `krOwner`）、`MetricPatch`（`start` `target` `current` `unit`）、
  `SopPatch`（`nodeType` `canvasX` `canvasY` `checklist` `owner` `durationMin`）、
  `GtdPatch`（`capturedAt` `clarified` `context` `energy` `waitingFor` `twoMinuteCandidate`）、
  `GanttPatch`（`start` `end` `progress`）。
- `NewItemInput(kind, title, notes, parentId, status, tags, areaId, order, okr, sop, gtd, gantt)`。

路由辅助（纯函数，shell 的 `Route` 仍是权威）：`ROUTE_IDS` `isRouteId` `routeFromSearch` `itemIdFromSearch` `resolveInitialRoute`。

---

## 13. `fixtures.cj` — 空库播种

| API | 用途 |
|---|---|
| `buildDemoWorkspace(clock)` / `createSeedWorkspace(clock)` | 30 条 items、12 条 edges、3 个 areas、3 条 runs；日期全部相对注入时钟 |

在 `FixedClock(2026-03-16T10:00:00+08:00)` 下播种，语义与 `tools/parity/workspace.json` **完全一致**（测试覆盖）。

---

## 14. `inspect.cj` — parity 摘要（冻结契约）

| API | 用途 |
|---|---|
| `inspectWorkspace(path)` → `WorkspaceDigest` | `byteCount` + FNV-1a64（原始字节）+ `anchorDate` |
| `WorkspaceDigest.describe()` | `bytes=…, fnv1a64=…, anchor=…`（parity CLI 输出格式） |
| `extractAnchorDate(text)` | 取最后一个 `"updatedAt"` 的日期部分 |

`fnv1a64` 的实现在 `utils.cj`，用 `std.overflow.wrappingMul`（仓颉整数溢出默认抛异常）。

---

## 15. `utils.cj` — 杂项

`fnv1a64(bytes|text)` `plural` `clampInt` `clampFloat` `roundHalfUp` `percent` `areaPalette` `AREA_PALETTE`
`uid(prefix, random)`（`prefix_xxxxxxxxxx`，**可复现**：显式传 `Random`）`uid(prefix)`（共享 PRNG，
**不可复现**，仅工具/测试用；`AppStore` 一律走带 `random` 的重载）`cloneWorkspace` `compareText` `trimmed` `isEmptyText`
`parseTags`（逗号/空格/`#`）`joinTags` `childCompletion`。

---

## 16. 与 Web 版的已知行为差异

| 差异 | 原因 |
|---|---|
| `AppStore.state` 是 `StateCell<Workspace>` 而非 `cui.State` | `core.data` 不得依赖 `cui`（`STRUCTURE.md` §2）；CUI 每帧重建，无需外部订阅即可响应 |
| `AppStore` 的 `clock` 是必填参数，parity 走 `AppStore.forParity(anchorDate)` | Web 版默认 `new Date()`；parity 必须冻结时钟，「当前季度」若取墙上时钟会与参考图不一致且跨天漂移 |
| `nowIso()` / `emptyWorkspace()` 没有无参重载 | 同上：任何读系统时钟的地方都必须显式传 `Clock`（或显式调用 `systemNowMillis()`） |
| 自动保存没有 400ms 防抖定时器 | core 内没有事件循环；`save()` 是显式调用，shell/视图按需节流 |
| `localeCompare()` 换成 UTF-8 字节序 | 标准库无 ICU 排序；领域中参与排序的字符串（ISO 时间、id、`YYYY-Qn`）都是 ASCII，结果一致 |
| `new Date(iso)` 的极端宽松解析未复刻 | 只接受 ISO 日期/时间（带可选 `Z`/`±HH:MM`）；非法输入返回 `None` 而不是 `Invalid Date` |
| 浮点数打印只在 `|v| < 1e9` 走高精度最短表示 | 工作区数值（进度/指标/canvas）都在该区间；更大数量级退化为科学计数法 |
| 备份/恢复、Tauri IPC 命令不复刻 | 桌面重写没有 Rust 侧命令；`save` 用临时文件 + rename 保证原子性，环修复副本写在 `<path>.repaired.json` |
| 通知不会自动消失 | 定时器属 UI；视图可用 `notice.at` + `ctx.today` 自行过滤 |

---

## 17. Parity 基线与锚点验证（2026-10-23 实测）

基线数值已汇总到两处，本节不再维护独立数字：`docs/PARITY.md §6`（结论表）与
`docs/PARITY-RESULTS.md`（14 张全量指标 + 残差定位）。当前实测（同一二进制、同一 workspace、
Xvfb 1440×900、DPR=1）：

| 项 | 值（2026-10-23 最终实测） |
|---|---|
| dashboard-light 两次独立运行 sha256 | `65946bce68b417ed0e284377c49e94c6c6c4341c0d2bf4777ec73590faecc8c1`（14/14 逐字节一致） |
| dashboard-light vs `ref/` | 7.04% 像素不同、ΔRGB mean 2.69 / max 220、≤32 97.29%、原始 SSIM 0.9605、**模糊 SSIM 0.9878 → PASS** |
| `tools/parity/workspace.json` 摘要 | `bytes=19498, fnv1a64=11907718152030072567, anchor=2026-03-16` |
| 读→写往返 | 字节完全相同（`workspace.json` 19498 B 不变） |

> 本表早期记录的 `1b93e7e4…` / 9.02% / SSIM 0.9085 对应视图仍在并行开发的中间状态，已被上面的最终值取代；
> `0dabfccf…` / 46.40% / 0.7502 是 bootstrap 占位面板时代的数字，两者都不要再引用。

锚点（`today`）链路验证：

1. `--workspace … --today 2026-03-16` 与 `--today 2026-11-05` 渲染出的 GTD 截图**不同** → 视图确实用的是冻结锚点，不是墙上时钟；
2. `AppStore.forParity("2026-03-16")` 的单元测试覆盖：时钟在 2026-Q4、锚点在 2026-Q1 时，
   `ui.okrPeriod` 取 2026-Q1（锚点优先），写入的 `updatedAt` 取冻结时钟；
3. `initialOkrPeriod` 的回退顺序（锚点季度 → 最新周期 → 锚点季度）与 `store.ts` 一致，单独用例覆盖。
