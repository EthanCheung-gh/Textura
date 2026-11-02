# 今日聚合逻辑层（`textura.views.dashboard.logic`）

本包是「今日」视图的**纯函数聚合层**：Web 版 `src/modules/dashboard/today.ts` 的仓颉移植，
外加 `DashboardPage.tsx` 里内联的「当前季度 OKR 平均进度」。

- 目录：`cangjie/src/views/dashboard/logic/`，包名 `textura.views.dashboard.logic`。
- 只依赖 `std.collection` / `std.sort` / `std.deriving`；**不 import `cui`，也不 import `textura.core.data`**。
- 不读系统时钟、不读时区环境：所有「今天 / 现在」由调用方注入，时区固定按 `Asia/Shanghai`（UTC+08:00）算术处理。
- 依赖方向：视图包 `textura.views.dashboard` → `textura.views.dashboard.logic`（单向，逻辑层不反向依赖）。

## 1. 输入记录与领域模型的映射

调用方（视图包）负责把 `core.data` 的实体压平成记录类型；逻辑层只消费记录，不持有工作区。

### 1.1 `DashItem` ← `Item`

| `DashItem` 字段 | 类型 | Web 版来源 | 备注 |
|---|---|---|---|
| `id` | `String` | `Item.id` | 去重键 |
| `title` | `String` | `Item.title` | 面包屑末级 |
| `kind` | `DashKind` | `Item.kind` | 与 `ItemKind` 同名同序 |
| `status` | `DashStatus` | `Item.status` | 与 `ItemStatus` 同名同序 |
| `dueDate` | `?String` | `dateKey(item.gantt.end)` | `None` 表示「无日期」；非空时**未**校验是否合法 |
| `completedAt` | `?String` | `Item.completedAt` | 空串与 `None` 同义（JS 假值） |
| `updatedAt` | `String` | `Item.updatedAt` | 活动时间线回退值 |
| `createdAt` | `String` | `Item.createdAt` | 排序末级键 |
| `parentId` | `?String` | `Item.parentId` | 面包屑与 SOP/OKR 来源判定 |
| `order` | `Int64` | `Item.order` | 组内排序主键 |
| `areaColor` | `?String` | `Area.color`（经 `areaId` 查表） | 逻辑层只透传，不参与聚合 |
| `okrProgress` | `?Int64` | `rollupProgress(ws, id)` | 仅 `okrAverageProgress` 使用；缺失按 0 |

### 1.2 `SopRun` ← `Run` + 两次 `itemById`

| `SopRun` 字段 | Web 版来源 |
|---|---|
| `id` / `sopId` / `at` / `result` | `SopRunEntry` 同名字段 |
| `sopTitle` | `itemById(ws, run.sopId)?.title`；`None` = 该 SOP 已不存在 |
| `stepTitle` | `itemById(ws, run.stepId)?.title`；`None` = 该步骤已不存在 |

`buildActivity` 用它们复现 `title = sop ? sop.title : '未知 SOP'` 与
`detail = step ? \`${step.title} · ${resultLabel}\` : resultLabel` 两个分支。

## 2. 公开 API

### 记录与枚举（`model.cj` / `focus.cj` / `activity.cj` / `summary.cj`）

```cangjie
public enum DashKind { Objective | KeyResult | Project | Action | Sop | Step | Milestone | Note | Reference }
public enum DashStatus { Inbox | Next | Active | Waiting | Scheduled | Someday | Done | Dropped }
public enum RunResult { Pass | Fail | Skip }
public struct DashItem { /* 见 1.1 */ }
public struct SopRun { /* 见 1.2 */ }

public enum FocusBucket { Overdue | Today | Undated }
public enum FocusSource { SourceSop | SourceOkr }
public struct FocusEntry { item, bucket, due, daysLate, pathTitles, source }
public struct FocusCounts { overdue, today, undated }
public struct FocusPage { items, shown, total, remaining, hasMore }
public struct TodaySummaryInput { overdue, today, inbox, next }
public struct ActivityEntry { id, kind, at, title, detail, result }
public enum ActivityKind { Run | Completed }

public const FOCUS_PAGE_SIZE: Int64 = 100
public func kindLabel(kind: DashKind): String
public func runResultLabel(result: RunResult): String
public func isOpen(status: DashStatus): Bool
public func isDone(status: DashStatus): Bool
```

### 聚合函数

| 仓颉 | Web 版对应 | 语义 |
|---|---|---|
| `buildTodayFocus(items, today: String): Array<FocusEntry>` | `buildTodayFocus(ws, today)` | 三段合并、去重、排序 |
| `countFocusBuckets(entries): FocusCounts` | `countFocusBuckets` | 分组计数 |
| `paginateFocus(entries, limit: Int64): FocusPage` | `paginateFocus` | 首屏分页 |
| `summarizeToday(input: TodaySummaryInput): String` | `summarizeToday` | 一句话摘要 |
| `completedThisWeek(items, nowIso: String, days!: Int64 = 7)` | `completedThisWeek(ws, now, days)` | 近 N 天完成 |
| `recentlyCompleted(items, limit!: Int64 = 5)` | `recentlyCompleted(ws, limit)` | 最近完成（不限窗口） |
| `averageProgress(values: Array<Int64>): Int64` | `DashboardPage` 内联 | `Math.round(mean)`，空集 0 |
| `okrAverageProgress(objectives: Array<DashItem>): Int64` | `DashboardPage` 内联 `okrAverage` | 当期目标平均进度 |
| `sortedRuns(runs): Array<SopRun>` | `sortedRuns` | `at` 倒序、同刻 `id` 升序 |
| `latestRun(runs): ?SopRun` | `latestRun` | 最近一次运行 |
| `latestRunFor(runs, sopId): ?SopRun` | `latestRunFor` | 指定 SOP 的最近运行 |
| `buildActivity(items, runs, limitPerSource!: Int64 = 5)` | `buildActivity(ws, limitPerSource)` | 运行 + 完成的时间线 |
| `relativeTime(iso: ?String, nowIso: String): String` | `relativeTime(iso)` | 中文相对时间（"前"/"内"） |
| `dateKeyOf(value: ?String): ?String` | `utils.dateKey` | 去空白 + 取前 10 字符 |
| `localDateKeyOf(value: String): ?String` | `format(date, 'yyyy-MM-dd')` | ISO → 本地日期键（UTC+8） |

## 3. 今日聚焦：合并顺序、去重、排序

### 3.1 三段合并（`buildTodayFocus`）

1. **超期**（`Overdue`）：`dueDate != None && dueDate < todayKey && isOpen(status)`，
   候选按 `byId` 插入序收集，再按 `dueDate` 升序**稳定**排序。
2. **今天到期**（`Today`）：`dueDate == todayKey && isOpen(status)`，保持 `byId` 插入序。
3. **无日期下一步**（`Undated`）：`status == Next && kind ∈ {Action, Project} && dueDate == None`，
   按 `(order, createdAt)` 升序**稳定**排序（输入序作为末级键）。

`today` 先经 `dateKeyOf` 归一化（`"2026-01-05T08:00:00"` → `"2026-01-05"`）；归一化失败时原样使用，
与 Web 版 `dateKey(today) ?? today` 一致。

`dueDate` 的比较是**字符串比较**（不是日期解析），因此 `"2025-02-30"` 这类非法日期键仍会进入超期桶，
与 Web 版 `end! < todayKey` 行为一致。

### 3.2 去重

- 去重键：`item.id`，去重集合按**推送顺序**累积。
- 优先级由推送顺序决定：**超期 > 今天到期 > 无日期**。同一条目只出现在第一个命中它的分组。
- 输入里同一 id 出现多行时，`DashIndex` 复现 `getWorkspaceIndex` 的 `Map.set` 语义：
  **值取最后一次出现，迭代位置取第一次出现**，因此旧行会被新行覆盖。

### 3.3 最终排序

比较器依次比较：

1. 分组权重：`Overdue(0) < Today(1) < Undated(2)`；
2. 仅 `Overdue`：`due` 升序；
3. `item.order` 升序；
4. `item.createdAt` 升序；
5. 输入序号升序（显式稳定化，等价 JS `Array.prototype.sort` 的稳定性保证）。

### 3.4 派生字段

| 字段 | 规则 |
|---|---|
| `due` | `dateKeyOf(item.dueDate)` |
| `daysLate` | 仅 `Overdue`：`max(1, today - due)` 的**日历日**差；`today`/`due` 非法日期时退回 1；其他分组恒为 0 |
| `pathTitles` | 祖先（根 → 直接父级）标题 + 自身标题；祖先链有环保护 |
| `source` | 自身 `Sop`/`Step` → `Sop`；自身 `Objective`/`KeyResult` → `OKR`；否则祖先里有 `Sop` → `Sop`；否则祖先里有 `Objective`/`KeyResult` → `OKR`；否则 `None` |

## 4. 分页语义

`paginateFocus(entries, limit)`：

- `total = entries.size`；`safeLimit = max(0, limit)`；`shown = min(safeLimit, total)`；
- `items` 恒为新数组（切片或全量拷贝，不与输入共享可变状态）；
- `remaining = total - shown`；`hasMore = shown < total`。

切页边界（测试钉住）：

| 输入 | 结果 |
|---|---|
| 0 条 | `shown=0, remaining=0, hasMore=false` |
| 99 / 100 条 + `limit=100` | 全渲染，`hasMore=false` |
| 101 条 + `limit=100` | `items=前 100`，`items[99]` 为第 100 条，`remaining=1, hasMore=true` |
| 150 条 + `limit=150/200` | 末页不足一页也全渲染，`remaining=0, hasMore=false` |
| `limit<=0` | `items=[]`，`hasMore = total>0` |

视图的「显示更多」= `limit += FOCUS_PAGE_SIZE`，与 `FocusList.tsx` 一致。

## 5. 完成窗口、OKR 平均进度、时间线

- **近 7 天完成**：`0 <= 今天 - 完成日 < days`（本地日历日差）。第 6 天含入、第 7 天排除；
  同一天更晚的时刻仍是 `diff = 0`（含）；完成时间晚于今天（`diff < 0`）排除；
  `completedAt` 为空串/`None`/非法时间一律排除；结果按 `completedAt` 倒序。
- **最近完成**：只判断 `completedAt` 非空，倒序后按 JS `slice(0, limit)` 截断。
- **OKR 平均进度**：`round(sum / count)`，空集为 0；调用方先用 `objectivesOfPeriod(ws, okrPeriod)`
  取当期目标并写入 `okrProgress`（季度过滤留在 `core.data`）。
- **最近活动**：`runs` 取最近 `limitPerSource` 条 + 完成记录取最近 `limitPerSource` 条，
  先 runs 后 completed 拼接，再按 `at` 倒序稳定排序（同刻时 runs 在前）。
- **相对时间**：逐行移植 `date-fns@4 formatDistance` + `zh-CN`：分钟取整、分档阈值
  （2/45/90 分钟、24 小时、2520 分钟≈1.75 天、30 天、2 个月、12 个月）、
  完整月数（含月末回退规则）与「前 / 内」后缀。非法或空输入返回 `—`。

## 6. 时区与「今天」

- 时区固定 `Asia/Shanghai`（1981 年后无夏令时，恒定 UTC+08:00），因此本地时间 = UTC+8 算术；
  不 import `std.time` 时区库，也不读 `TZ` 环境变量，结果与运行机器无关。
- `dateKeyOf`：字符串归一化，**不做**时区换算。
- `parseInstantMs`（内部）：支持 `YYYY-MM-DD`、`YYYY-MM-DD[T ]HH:mm[:ss[.SSS]]`、
  可选 `Z` / `±HH:MM` / `±HHMM`；无偏移的串按 +08:00 墙钟解释（等价 `new Date('...')` 在固定 +08:00 下）。
- `localDateKeyOf` / 完成窗口 / `daysLate` / `relativeTime` 都走本地日历日或本地时刻。

## 7. 与 TS 的差异

**语义差异为零**。下列条目是「实现形态」差异，逐条说明为什么不会产生行为分歧：

1. **`limit` 的类型**：Web 版 `paginateFocus` 用 `Number.isFinite` 拦截 `NaN`/`Infinity`；
   仓颉入参是 `Int64`，非有限值在编译期不可表示，因此该分支不存在。负数与 0 的处理一致。
2. **比较函数**：Web 版用 `localeCompare`，这里用字节序 `compareText`。被比较的全部是定宽 ISO 串
   （`YYYY-MM-DD`、`YYYY-MM-DDTHH:mm:ss`）与 ASCII id，两者排序结果一致；差分验证覆盖了同刻/同序/空串情形。
3. **`dateKeyOf` 的长度单位**：Web 版按 UTF-16 码元取前 10 个，这里按 Rune（码点）取前 10 个。
   仅当日期键前 10 位出现星评面之外字符才可能不同，日期串不可能出现。
4. **`relativeTime` 的入参解析**：Web 版 `new Date(iso)` 可解析非 ISO 串；这里只接受 ISO 子集，
   其余返回 `—`（与 Web 版非法输入的输出相同）。应用数据全部是 ISO 时间戳。
5. **「现在」的来源**：Web 版 `formatDistanceToNow` 读系统时钟；这里要求显式传入 `nowIso`
   （项目硬约束「不读系统时钟」）。给定同一时刻，输出逐字符相同。
6. **`okrAverageProgress` 的入参**：Web 版在 `DashboardPage` 内联计算 `objectivesOfPeriod` + `rollupProgress`；
   这里要求调用方把进度写进 `okrProgress`（数据索引留在 `core.data`）。取整规则一致（`Math.round` → `roundHalfUp`）。
7. **`SopRun` 的标题注入**：Web 版在 `buildActivity` 内部 `itemById`；这里由调用方解析好传入。
   缺失条目的两个分支（`未知 SOP`、只显示结果）完全保留。
8. **时区实现**：Web 版依赖运行环境 `TZ`；这里固定 +08:00 算术。项目已把 `TZ` 钉成 `Asia/Shanghai`，
   因此在项目环境下等价（若有夏令时的时区，跨换季边界才会有差异，本项目不涉及）。

## 8. 测试与验证

### 8.1 用例

| 文件 | 用例数 | 断言数 | 覆盖 |
|---|---|---|---|
| `today_test.cj` | 9 | 29 | `today.test.ts` 全部断言（合并/去重/超期天数/面包屑/来源/摘要/7 天/活动/最新运行） |
| `today_paging_test.cj` | 4 | 21 | `todayPaging.test.ts` 全部断言（0/99/100/101 条、非法 limit） |
| `today_extra_test.cj` | 12 | 60 | 空库、全超期、同日多处去重、7 天窗口边界、分页末页、排序稳定性、非法日期回退、时区换算、OKR 平均 |
| `relative_test.cj` | 4 | 9 | 41 条 `date-fns` 实测向量（过去 20 / 未来 18 / 月末 3）+ 回退断言 |
| 合计 | **29** | **119** | |

`relative_test.cj` 的期望值来自 Web 版依赖的 `date-fns@4`：
`formatDistance(new Date(iso), new Date(now), { addSuffix: true, locale: zhCN })`，`TZ=Asia/Shanghai` 实测。

### 8.2 运行方式（共享工作树不跑 cjpm）

```bash
# 1) 快照验证（项目整体可构建时）
rsync -a --delete --exclude target --exclude 'tools/parity/out' \
  /home/ethan/CodeRepo/sandbox/Textura/cangjie/ /tmp/cj-logic-dashboard/
cd /tmp/cj-logic-dashboard && source scripts/env.sh && cjpm build -i -o textura && cjpm test

# 2) 隔离最小工程（其它包未就绪时）：只放本包 + 上级包标记
#    cjpm.toml(name=textura, executable) + src/main.cj(package textura)
#    + src/views/views.cj(package textura.views) + src/views/dashboard/dashboard.cj
#    + src/views/dashboard/logic/*.cj
cd /tmp/cj-logic-only && source <repo>/cangjie/scripts/env.sh && cjpm build && cjpm test
```

本轮结果：

- 隔离最小工程：`cjpm build` 成功；`cjpm test` **29/29 PASSED，0 FAILED**。
- 共享工作树快照：本包编译产物 `textura.views.dashboard.logic.cjo/.a` 正常生成；
  整树 `cjpm build` / `cjpm test` 当前被 `textura.ui`（`theme.cj` 与 `tokens.cj` 重复声明
  `SURFACE_2/BORDER/INK/...`，以及 `controls_button.cj` 调用参数错误）阻塞——属其他 worker 的在建范围，
  与本包无关。
- 差分验证（本轮临时脚本，不提交）：用 esbuild 把 `src/modules/dashboard/today.ts` 打成 ESM，
  与仓颉实现吃同一份随机数据集（120+ 条目：多层父链、父子环、非法日期键、带时间的 `end`、
  UTC/本地/空串 `completedAt`、大量同 `order`/`createdAt` 并列；8 条含同刻的运行记录；62 个相对时间样本），
  比较 focus 行（id/bucket/due/daysLate/path/source）、计数、7 天窗口、最近完成、活动、最新运行、
  `latestRunFor`、摘要与相对时间。5 个随机种子下输出**逐字节一致**（114–128 行）。

## 9. 未完成项 / 集成注意

1. **视图接线未做**（不在本包写入范围）：`textura.views.dashboard` 仍需把 `Item`/`Run` 映射成
   `DashItem`/`SopRun`（见第 1 节），并把 `today`/`now` 从 `ViewContext` 注入。
2. `areaColor`、`okrProgress` 已按规划放进记录，但当前聚合函数只用到 `okrProgress`；
   `areaColor` 留给后续渲染层，不参与排序。
3. `greetingFor(hour)`（`DashboardPage.tsx` 的「早上好」文案）与 SOP 卡片的步骤计数
   （`sopGraph(...).nodes.length`）仍属视图/数据层职责，本包未包含。
4. 项目整体构建的门禁（`cjpm build`、parity 截图）要等 `textura.ui` 修好后才能跑通；
   本包的证据是隔离工程 + 差分比对。
