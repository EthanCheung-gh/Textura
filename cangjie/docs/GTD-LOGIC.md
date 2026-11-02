# GTD 算法层（`textura.views.gtd.logic`）

本包是 Web 版 GTD 纯函数层的仓颉移植：收件箱排序、澄清状态机、下一步按场景分组、
等待项与等待天数、停滞项目判定、周回顾指标、计数与空态判定，以及全部行内变更
的「意图」描述。

对应源码（只读参照）：

- `src/modules/gtd/gtdLogic.ts`（722 行）
- `src/modules/gtd/gtdMutations.ts`（91 行）
- 测试真值：`src/modules/gtd/gtdLogic.test.ts`（594 行）、`src/modules/gtd/gtdListPerf.test.ts`（190 行）
- 澄清提交分支：`src/modules/gtd/ClarifyDialog.tsx` 的 `submit`（用于 `clarifyItem`）

## 1. 依赖边界

- 包名 `textura.views.gtd.logic`，目录 `cangjie/src/views/gtd/logic/`。
- **只依赖 `std`**：不 import `cui`，不 import `textura.core.data`，不 import 其它视图包。
- 不读系统时钟、不生成随机 id、不持有 store。所有「现在」与新建条目的 id 由调用方注入。
- 因此本包可以被任意 UI、测试或脚本直接复用，依赖闭包就是标准库。

## 2. 文件

| 文件 | 内容 |
|---|---|
| `gtd_item.cj` | `GtdKind` / `GtdStatus` / `Energy` / `GtdArea` / `GtdMetric` / `GtdItem` / `GtdWorkspace` 与判别函数 |
| `gtd_civil.cj` | 固定 Asia/Shanghai 的日期换算：`localDayKey`、`daysBetween`、`dayOffset`、`formatDateTime` 等 |
| `gtd_logic.cj` | 排序、分组、分页、面包屑索引、等待天数、停滞判定、项目健康度、周回顾、展示辅助 |
| `gtd_clarify.cj` | 澄清表单状态、校验、`buildClarifyPatch` / `buildClarifyNewItem` / `createClarifyForm` |
| `gtd_mutations.cj` | `GtdMutation` 意图枚举、`GtdPatch` / `GtdNewItem` 载荷、全部动作的意图序列 |
| `gtd_civil_test.cj` / `gtd_logic_test.cj` / `gtd_mutations_test.cj` / `gtd_perf_test.cj` | 单元测试（78 个用例） |
| `gtd_test_support_test.cj` | 测试专用构造器与摘要工具（仅 `cjpm test` 编译） |

## 3. 输入映射：`core.data.Item` → `GtdItem`

`GtdItem` 是只读投影，只保留算法需要的字段。UI / store 层负责转换；
`?T` 表示 TS 里的可选值，`Bool = false` 表示 TS 里的 `undefined` 语义。

| TS `Item` | `GtdItem` | 说明 |
|---|---|---|
| `id` | `id: String` | 原样 |
| `kind` | `kind: GtdKind` | `ItemKind` 九值一一对应 |
| `title` / `notes` | `title` / `notes` | 原样 |
| `parentId` | `parentId: ?String` | `null` → `None` |
| `order` | `order: Int64` | 原样 |
| `status` | `status: GtdStatus` | `ItemStatus` 八值一一对应 |
| `tags` | `tags: Array<String>` | 原样 |
| `areaId` | `areaId: ?String` | `null` → `None` |
| `createdAt` / `updatedAt` | 同名 `String` | 原样（ISO 时刻） |
| `completedAt` | `completedAt: ?String` | `null` → `None` |
| `gtd.capturedAt` | `capturedAt: ?String` | 收集时刻；等待天数基线 |
| `gtd.clarified` | `clarified: Bool` | 缺省 `false` |
| `gtd.context` | `context: ?String` | **未裁剪**原文；`contextOf()` 负责 trim + 空串归 `None` |
| `gtd.energy` | `energy: ?Energy` | `'low'/'medium'/'high'` → `Low/Medium/High`，缺省 `None` |
| `gtd.waitingFor` | `waitingFor: ?String` | 缺省 `None` |
| `gtd.twoMinuteCandidate` | `twoMinuteCandidate: Bool` | 缺省 `false` |
| `gantt.start` | `startDate: ?String` | **原始串**，聚合时用 `dateKey()` 截断 |
| `gantt.end` | `dueDate: ?String` | 同上 |
| `okr.metric` | `metric: ?GtdMetric` | `{start, target, current}`，仅 `rollupProgress` 使用 |

`GtdWorkspace { items, areas }` 对应 `Workspace` 的 `items` 与 `areas`
（`edges` / `runs` / `version` / `updatedAt` 与 GTD 算法无关，不投影）。
`core.data.Area → GtdArea{ id, name }`。

## 4. 时区与「今天」

- 时区固定 **Asia/Shanghai（UTC+8，无夏令时）**；`localDayKey` 先把 ISO 时刻换算成
  上海本地日历日，而不是截取字符串前 10 位。
- 没有任何系统时钟调用：`today` / `now` / `at` / `nowIso` 全部是参数。
- `dayOffset(days, fromKey)` 的 `fromKey` 必须是合法日期键，否则抛
  `IllegalArgumentException`（TS 的 `from` 是 `Date`，非法值不可能出现）。
- `weeklyReview(ws, today)` 的 `today` 非法时抛 `IllegalArgumentException`；
  其余展示类函数在 `today` 非法时退回 `daysBetween` 的 0 语义（详见 §8）。

## 5. 公开 API

### 5.1 模型与判别（`gtd_item.cj`）

```cangjie
public enum GtdKind { Objective | KeyResult | Project | Action | Sop | Step | Milestone | Note | Reference }
public enum GtdStatus { Inbox | Next | Active | Waiting | Scheduled | Someday | Done | Dropped }
public enum Energy { Low | Medium | High }
public class GtdArea / GtdMetric / GtdItem / GtdWorkspace
public func contextOf(item: GtdItem): ?String      // trim，空 → None
public func energyRank(item: GtdItem): Int64       // high=3 medium=2 low=1 缺省=0
public func isOpen(item: GtdItem): Bool            // 非 done/dropped
public func isClosed(item: GtdItem): Bool
public func nonEmpty(value: ?String): ?String
```

### 5.2 日期（`gtd_civil.cj`）

```cangjie
public func isValidDayKey(key: String): Bool
public func localDayKey(value: ?String): ?String          // ISO/日期键 → 上海日历日键
public func dateKey(value: ?String): ?String              // 截断前 10 位，不校验
public func dayOffset(days: Int64, fromKey: String): String
public func daysBetween(fromKey: String, toKey: String): Int64
public func formatMonthDay(value: ?String): String        // MM/dd，非法 → "—"
public func formatDateTime(value: ?String): String        // 上海 "yyyy-MM-dd HH:mm"，非法 → "—"
```

### 5.3 列表算法（`gtd_logic.cj`）

```cangjie
public let NO_CONTEXT = "无场景"
public let NO_CONTEXT_FILTER = "__none__"
public let PRESET_CONTEXTS = ["电脑", "电话", "外出", "会议", "深度工作"]
public let WAITING_WARN_DAYS: Int64 = 7
public let ESTIMATE_OPTIONS: Array<Int64> = [2, 15, 30, 60, 120]
public let LIST_PAGE_SIZE: Int64 = 100
public func energyLabel(energy: Energy): String

public func sortInboxItems(items: Array<GtdItem>): Array<GtdItem>
public func groupByContext(items: Array<GtdItem>): Array<ContextGroup>   // ContextGroup{context, items}
public func contextOrder(context: String): Int64
public func sortNextActions(items: Array<GtdItem>): Array<GtdItem>

public func paginateItems<T>(items: Array<T>, limit: Int64): PageSlice<T>
public class PageSlice<T> { items, shown, total, remaining, hasMore }
public class PaginationState { key, limit }
public func resolvePageLimit(state: PaginationState, key: String, pageSize!: Int64 = LIST_PAGE_SIZE): Int64
public func nextPage(state: PaginationState, key: String, pageSize!: Int64 = LIST_PAGE_SIZE): PaginationState

public class PathTitleIndex { paths, parents, parentText, pathOf(id), parentTextOf(id) }
public func buildPathTitleIndex(workspace: GtdWorkspace, items: Array<GtdItem>): PathTitleIndex

public class WaitingRow { item, days, overdue }
public func buildWaitingRows(items: Array<GtdItem>, today: String): Array<WaitingRow>

public class NextFilter { context, dueSoonOnly, areaId, search, today }
public func matchesSearch(item: GtdItem, search: String): Bool
public func filterNextActions(items: Array<GtdItem>, filter: NextFilter): Array<GtdItem>

public func isStuckProject(workspace: GtdWorkspace, projectId: String): Bool
public class ProjectHealth { project, total, done, open, next, progress, stuck }
public func projectHealth(workspace: GtdWorkspace): Array<ProjectHealth>
public func rollupProgress(workspace: GtdWorkspace, id: String): Int64

public func waitingSince(item: GtdItem): String
public func waitingDays(item: GtdItem, today: String): Int64
public func isWaitingOverdue(item: GtdItem, today: String, threshold!: Int64 = WAITING_WARN_DAYS): Bool

public class StaleArea { area, openCount, lastTouched }
public class WeeklyReviewStats { today, windowStart, inbox(+Count), inboxCleared(+Count), inboxProgress,
    completedThisWeek(+Count), overdue(+Count), stuckProjects(+Count), waitingOverdue(+Count),
    undatedTasks(+Count), staleAreas }
public func weeklyReview(workspace: GtdWorkspace, today: String): WeeklyReviewStats

public func relativeTimeLabel(value: ?String, now: String): String
public enum DeadlineTone { Danger | Accent | Muted }
public class DeadlineInfo { label, tone, date }
public func deadlineInfo(item: GtdItem, today: String): DeadlineInfo
public func appendTimestampedNote(notes: String, message: String, at: String): String
```

### 5.4 澄清表单（`gtd_clarify.cj`）

```cangjie
public enum ClarifyType { Next | Project | Reference | Note }
public class ClarifyFormState { clarifyType, title, notes, tags, areaId, context, customContext,
    energy, estimateMin, dueDate, delegated, waitingFor, someday, twoMinuteCandidate; patched(...) }
public class ClarifyErrors { title, waitingFor, status; isEmpty() }
public class ClarifyPatch { title, notes, tags, areaId, dueDate, clarified, context, energy,
    waitingFor, twoMinuteCandidate }
public func parseTags(input: String): Array<String>
public func resolveFormContext(form: ClarifyFormState): String
public func desiredKind(types: ClarifyType): GtdKind
public func isArchiveType(types: ClarifyType): Bool
public func clarifyTargetStatus(form: ClarifyFormState): GtdStatus
public func validateClarifyForm(form: ClarifyFormState): ClarifyErrors
public func buildClarifyPatch(form: ClarifyFormState): ClarifyPatch
public func buildClarifyNewItem(form, source: GtdItem, status: GtdStatus, newId: String, nowIso: String): GtdNewItem
public func buildClarifyNewItem(form, source: GtdItem, newId: String, nowIso: String): GtdNewItem  // status 取表单目标状态
public func createClarifyForm(item: GtdItem): ClarifyFormState
```

## 6. 变更意图（`gtd_mutations.cj`）

变更不直接改数据，而是返回可顺序应用的意图数组，由 UI / store 层落库：

```cangjie
public enum GtdMutation {
    | ToggleDone(String)              // store.toggleDone(id)
    | DeleteItems(Array<String>)      // store.deleteItems(ids)
    | UpdateItem(String, GtdPatch)    // store.updateItem(id, patch)
    | SetStatus(String, GtdStatus)    // store.setStatus(id, status)
    | CreateItem(GtdNewItem)          // store.createItem(spec)，id 由调用方注入
    | Notify(String, NoticeTone)      // store.notify(message, tone)
}
public class GtdChange { mutations: Array<GtdMutation>, resultId: ?String, createdSpec(): ?GtdNewItem }
```

`GtdPatch` 用 `?T` 表示「不变」，用 `FieldUpdate<T>{ Keep | Clear | Set(v) }` 表示
`areaId` / `gantt.end` 这类**可空字段的三态**。`NoticeTone { Info | Success | Error }`。

各动作与 TS 调用序列一一对应（顺序即应用顺序）：

| 动作 | 意图序列 | TS 调用 |
|---|---|---|
| `completeInboxItem(item)` | `ToggleDone` → `Notify`(success) | `toggleDone` + `notify` |
| `deleteInboxItem(item)` | `DeleteItems` → `Notify`(info) | `deleteItems` + `notify` |
| `promoteItemToNext(item, newId, nowIso)`（action/project） | `UpdateItem{clarified}` → `SetStatus(next)` → `Notify` | `updateItem` + `setStatus` + `notify` |
| `promoteItemToNext(...)`（note/reference） | `CreateItem` → `UpdateItem{notes,clarified}` → `SetStatus(done)` → `Notify` | `createItem` + `updateItem` + `setStatus` + `notify` |
| `nudgeWaitingItem(item, at)` | `UpdateItem{notes}` → `Notify` | `updateItem` + `notify` |
| `createNextActionForProject(project, newId, nowIso)` | `CreateItem` → `Notify` | `createItem` + `notify` |
| `activateSomedayItem(item, newId, nowIso)` | 同 `promoteItemToNext` | 同 |
| `clarifyItem(item, form, newId, nowIso)` 归档类 | `UpdateItem{补丁+notes}` → `SetStatus(done)` → `Notify` | `updateItem` + `setStatus` + `notify` |
| `clarifyItem(...)` 新建 action | `CreateItem` → `UpdateItem{notes,clarified}` → `SetStatus(done)` → `Notify` | `createItem` + `updateItem` + `setStatus` + `notify` |
| `clarifyItem(...)` 升级 project | 同上（`kind=project`，文案不同） | 同上 |
| `clarifyItem(...)` 就地澄清 | `UpdateItem{完整补丁}` → `SetStatus(目标状态)` → `Notify` | `updateItem` + `setStatus` + `notify` |
| `notifyOnly(message, tone)` | `Notify` | `notify` |

`resultId` 对应 TS 动作的返回值（`promoteItemToNext` 返回 `item` 或 `created`）。

## 7. 澄清表单语义

- `parseTags`：逗号（`,`）、中文逗号（`，`）、空白（含全角空格）分隔；去掉前导 `#`；
  按首次出现去重。
- `clarifyTargetStatus`：归档类 → `done`；委派 → `waiting`；someday → `someday`；其余 → `next`
  （判定顺序与 TS 一致）。
- `validateClarifyForm`：标题必填；委派且非归档时必须填等待对象；「委派」与「某天」互斥（非归档类型）。
- `buildClarifyPatch`：`title` trim、`tags` 解析、`areaId`/`dueDate` 空串归 `None`、
  `twoMinuteCandidate = 候选 || estimateMin == 2`、`waitingFor` 仅在委派时保留 trim 值。
- `createClarifyForm`：自定义场景进 `customContext` 且 `context = "__custom__"`；
  预设场景留在 `context`；`estimateMin = 候选 ? 2 : None`。

## 8. 与 TS 的差异

**语义差异：零**（在 Asia/Shanghai 时区、合法日期键输入下）。以下全部是语言/类型层或
非法输入处理上的差异，逐条列明：

| 项 | TS | 仓颉 | 影响 |
|---|---|---|---|
| 时区来源 | 运行环境本地时区（`date-fns` `parseISO`/`format`） | 固定 Asia/Shanghai | 产品约定即上海；在上海环境下逐位一致，其它时区的 TS 行为不可复现 |
| 「当前时刻」 | `currentDateKey()` / `new Date()` 默认参数 | 全部改为必填参数注入 | 无系统时钟依赖；调用方少传参数会编译失败（有意） |
| `today` 非法 | 静默退回系统时钟 | `weeklyReview` 抛 `IllegalArgumentException`；`waitingDays` / `filterNextActions` / `deadlineInfo` / `relativeTimeLabel` 退回 `daysBetween` 的 0 语义（TS `daysBetween` 对非法输入同样返回 0） | 仅非法输入路径 |
| 场景组名排序 | `localeCompare`（ICU 排序） | `String` 码位序 | 预设场景顺序、无场景末位、ISO 时间戳比较完全一致；**多个自定义场景之间的次序**在中文下可能与拼音序不同 |
| 大小写折叠 | `toLowerCase()` | `std.unicode.toLower()` | 同为完整 Unicode 折叠，一致 |
| `Math.round` | 四舍五入（half up） | `roundHalfUp`（正负同规则） | 一致（值域非负） |
| `waitingSince` | `capturedAt ?? updatedAt ?? createdAt` | 同上，但 `updatedAt` 为空串时落在 `createdAt` | 仅在 `updatedAt` 缺失的脏数据上更稳（TS 会得到空串 → 0 天） |
| `paginateItems` 的 `limit` | `Number`，接受 `NaN` / `2.9` | `Int64` | 类型上不可表达 `NaN`/小数；负值仍按 0（已测） |
| `DeadlineTone` | 字符串联合 | `enum` | 无语义差异 |
| `ENERGY_LABELS` | `Record<Energy, string>` | `energyLabel(energy)` | 无语义差异 |
| `ClarifyFormState.type` | `type` | `clarifyType` | `type` 是仓颉关键字 |
| `ClarifyErrors` | 任意可选字段对象 | `class ClarifyErrors` + `isEmpty()` | 无语义差异 |
| `buildClarifyNewItem` | 无 id（store 分配） | 增加 `newId` 参数 | 纯函数不生成随机 id；`notes` 文案引用该 id |
| `appendTimestampedNote` | `at: Date = new Date()` | `at: String` 必填 | 无系统时钟 |
| `relativeTimeLabel` | `now: Date = new Date()` | `now: String` 必填 | 同上 |
| `dailyReview` 的 `progress` | `number`（已四舍五入） | `Int64` | 一致 |

补充说明：

- 需求之外新增 `clarifyItem`（映射自 `ClarifyDialog.submit` 的四分支）与 `notifyOnly`，
  因为行内变更清单里包含「澄清」，且这两个纯函数是澄清流程落库所必需的。
- 索引复用：包内 `WorkspaceIndex`（id / children / descendants）在 `projectHealthIn`、
  `stuckProjectIn`、`rollupProgressIn` 之间共享，`weeklyReview` 只建一次索引；
  对外的 `projectHealth` / `isStuckProject` / `rollupProgress` 每次调用各建一次
  （TS 用 WeakMap 缓存）。5k 规模实测：`weeklyReview`（1000 项目 + 3000 收件箱）约 19 ms，
  `sortNextActions` 5k 约 0.14 s。

## 9. 测试与验证

### 9.1 用例（78 个，全绿）

| 文件 | 用例数 | 覆盖 |
|---|---|---|
| `gtd_logic_test.cj` | 34 | `groupByContext`（空场景/稳定组序）、`sortNextActions`、`sortInboxItems`、`isStuckProject`（含孙级）、`waitingDays`/超 7 天、`localDayKey`（UTC 截断陷阱）、7 天窗口、`relativeTimeLabel`、`weeklyReview`（三项指标 + 空工作区 100% + 停滞领域 + 非法 today）、`filterNextActions`、澄清表单全部映射、`deadlineInfo`、`appendTimestampedNote`、`projectHealth`、`rollupProgress` |
| `gtd_civil_test.cj` | 9 | civil-from-days 闰日/跨年、`dayOffset` 跨月跨年、`daysBetween` 方向与非法输入、跨年 UTC→上海、`formatMonthDay`/`formatDateTime`、等待天数跨月/跨年阈值 |
| `gtd_mutations_test.cj` | 16 | 8 个动作的全部意图序列、`newId`/`nowIso` 注入后的载荷、澄清四分支、`Notify` 文案、`resultId` |
| `gtd_perf_test.cj` | 19 | 分页（0/99/100/101/负数/不改输入）、分页状态 key 重置、面包屑索引（含重复 id/缺失 id）、分组+排序+分页组合、`buildWaitingRows`、**1k / 5k 规模**的排序判序、分组守恒、分页计数、并列键稳定性、1000 层深链路径索引、1000 项目 + 3000 收件箱的周回顾 |

`gtdLogic.test.ts` 的 24 个 `it` 与 `gtdListPerf.test.ts` 的 8 个 `it` 全部逐条对应，
断言内容一致；唯一替换是「今天」由固定锚点 `2026-10-21` 注入，而不是读系统时钟，
因此日期断言与跑测机器时区无关。`gtdLogic.test.ts` 里「与 dashboard `completedThisWeek`
逐日对齐」的两处交叉断言只保留 GTD 侧结果（dashboard 包尚未就绪）。

### 9.2 如何验证

共享工作树里其它视图包仍在并行改动，`cjpm build` 可能被无关包（例如重复的
`core.data.Workspace` 定义）阻断。本包只依赖 `std`，因此用隔离最小工程验证：

```bash
# 1) 整体快照（需要全仓可编译时）
rsync -a --delete --exclude target --exclude 'tools/parity/out' \
  /home/ethan/CodeRepo/sandbox/Textura/cangjie/ /tmp/cj-logic-gtd/
cd /tmp/cj-logic-gtd && source scripts/env.sh && cjpm build -i -o textura && cjpm test

# 2) 隔离工程（只含本包，无 CUI 依赖）
mkdir -p /tmp/cj-gtd-logic-iso/src/views/gtd/logic
cd /tmp/cj-gtd-logic-iso
printf '[package]\ncjc-version = "1.2.0"\nname = "textura"\nversion = "0.1.0"\noutput-type = "static"\n' > cjpm.toml
printf 'package textura\n\npublic let HARNESS_ROOT: Int64 = 1\n' > src/root.cj
printf 'package textura.views\n\npublic let HARNESS_VIEWS: Int64 = 1\n' > src/views/views.cj
printf 'package textura.views.gtd\n\npublic let HARNESS_GTD: Int64 = 1\n' > src/views/gtd/gtd.cj
rsync -a --delete /home/ethan/CodeRepo/sandbox/Textura/cangjie/src/views/gtd/logic/ src/views/gtd/logic/
source /tmp/cj-logic-gtd/scripts/env.sh && cjpm build && cjpm test
```

隔离工程只包含本包源码（`std` 依赖闭包）；另用一个只含 `src/views/gtd/**` 的模块工程
（保留父包 `gtd.cj`）验证过子包自动发现与测试运行，结果同样 78/78。

最近一次结果（工具链 `cjc 1.2.0 (cjnative)`）：`cjpm build success`，
`cjpm test` → `TOTAL: 78, PASSED: 78, FAILED: 0`；5k 排序用例约 0.14 s，
1000 层深链路径索引约 1.0 s，1000 项目 + 3000 收件箱的周回顾约 19 ms。

## 10. 后续

- GTD 视图（`textura.views.gtd`）接入时，需要一层 `core.data.Item ↔ GtdItem` 适配与
  `GtdMutation` 执行器（把意图映射到 store 动作）。
- `GtdNewItem.id` 的分配策略由 store 决定（例如 `uid("act")`），本包只接收。
- 活动场景/搜索高亮等纯展示逻辑未纳入本包（TS 也没有）。
