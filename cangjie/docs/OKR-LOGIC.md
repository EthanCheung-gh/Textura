# OKR 逻辑层（`textura.views.okr.logic`）

Web 版 OKR 的派生计算从 `src/modules/okr/{okrMath,okrDisplay,metricDraft}.ts` 移植为纯仓颉包，
供后续 `textura.views.okr`（视图层）与 Dashboard / Gantt 的 OKR 摘要复用。

## 1. 边界与依赖

- 包名：`textura.views.okr.logic`，目录 `cangjie/src/views/okr/logic/`。
- 只依赖 `std.*`（`std.collection`、`std.convert`、`std.math`、`std.sort`、`std.unicode`）。
- **不 import `cui`，也不 import `textura.core.data`**：输入用本包自定义记录，视图 worker 负责映射。
- 不读系统时钟、不读时区数据库、不读环境变量：`today` 由调用方注入（`CivilDate`）。
- 不缓存、不持有全局可变状态：所有函数对相同输入返回相同结果（`executionItemsOf` 每次返回新数组）。

## 2. 文件与公开 API

| 文件 | 行数 | 主要内容 |
|---|---|---|
| `records.cj` | 298 | `OkrItemKind` / `OkrItemStatus` / `OkrEdgeType`、`OkrMetric`、`OkrData`、`OkrSchedule`、`OkrItem`、`OkrEdge`、`OkrArea`、`OkrWorkspace`、文本↔枚举映射 |
| `numbers.cj` | 305 | JS 数字语义：`isFiniteNumber`、`jsTrunc`、`jsRound`、`power10`、`roundTo`、`jsNumberToString`、`jsFixedNumberToString`、`roundScaledHalfAwayFromZero` |
| `quarter.cj` | 260 | `CivilDate`、`QuarterRange`、`daysInMonth`、`isValidCivilDate`、`daysFromCivil`、`calendarDaysBetween`、`parseCivilDateKey`、`quarterRange`、`quarterElapsedPercent`、`shiftQuarter`、`nextQuarter`、`quarterLabel` |
| `metric.cj` | 108 | `METRIC_RANGE_EPSILON`、`MetricProgressState`、`MetricProgressInfo`、`hasMetricRange`、`metricProgress`、`metricPercent` |
| `index.cj` | 132 | 包内 `OkrIndex`（byId / children / edgesFrom / areas / objectivesByPeriod）、公开 `childrenOf`、`objectivesOfPeriod` |
| `progress.cj` | 262 | `BEHIND_MARGIN_POINTS`、`isKrBehind`、`ConfidenceBucket`、`confidenceBucket`、`OkrSummary`、`rollupProgress`、`summarize` |
| `alignment.cj` | 359 | `ExecutionVia`、`ExecutionItemRef`、`executionItemsOf`、`ObjectiveView`、`matchesQuery`、`filterObjectives`、`OKR_KR_PAGE_SIZE`、`ObjectiveTablePage`、`paginateObjectiveKrs`、`OkrPaginationState`、`resolveOkrPageLimit`、`nextOkrPage`、`buildParentPathText` |
| `display.cj` | 175 | `BadgeTone`、`ProgressTone`、`statusTone`、`progressTone`、`formatNumber`、`unitSuffix`、`formatMetric`、`formatDateKeyMmDd`、`formatSchedule` |
| `metric_draft.cj` | 319 | `MetricField`（`UnitField`，文本 `"unit"`）、`METRIC_FIELDS`、`METRIC_NUMBER_FIELDS`、`EMPTY_METRIC`、`MetricDraft`、`metricToText`、`metricFieldValueText`、`metricToDraft`、`parseMetricNumber`、`MetricFlushDecision`、`pendingMetricPatch`、`flushMetricDrafts` |

TS ↔ 仓颉的关键命名差异：

| TS | 仓颉 | 说明 |
|---|---|---|
| `metricDraft.ts` 的 `'unit'` 字段 | `MetricField.UnitField` | `Unit` 是仓颉关键字；`metricFieldText()` 仍返回 `"unit"` |
| `via: 'edge' \| 'child'` | `ExecutionVia.Edge / Child` | `executionViaText()` 返回 TS 字面量 |
| `state: 'in-range'` 等 | `MetricProgressState.InRange` | `metricProgressStateText()` 返回 `"in-range"` |
| `BadgeTone` / `ProgressTone` 字符串 | 枚举 + `toText` 函数 | 视图层再映射到 `textura.ui` 令牌，本包不写颜色 |
| `confidence: Record<bucket, number>` | `OkrSummary.confidenceLow/Mid/High` + `confidenceOf(bucket)` | 避免 HashMap 键哈希 |

## 3. `core.data` → 本包记录映射表

映射在视图 worker 里做（例如 `func toOkrItem(item: core.data.Item): OkrItem`）。字段一一对应，除下列重命名：

| `core.data` | 本包 | 备注 |
|---|---|---|
| `Item.id` | `OkrItem.id` | |
| `Item.kind: ItemKind` | `OkrItem.kind: OkrItemKind` | 同名同序；`okrItemKindFromText("keyresult")` 等提供文本映射 |
| `Item.title` | `OkrItem.title` | 搜索与路径文本使用 |
| `Item.notes` | `OkrItem.notes` | 搜索使用 |
| `Item.parentId: ?String` | `OkrItem.parentId: ?String` | 父子关系、执行项合并、路径文本 |
| `Item.order: Int64` | `OkrItem.order: Int64` | 兄弟排序主键 |
| `Item.status: ItemStatus` | `OkrItem.status: OkrItemStatus` | `Done` 决定 `rollupProgress` 的完成度 |
| `Item.tags: Array<String>` | `OkrItem.tags` | 搜索使用 |
| `Item.areaId: ?String` | `OkrItem.areaId` | 搜索时取 `OkrArea.name` |
| `Item.createdAt: String` | `OkrItem.createdAt: String` | 排序次级键（`order` 相同时按字符串升序，等价 TS `localeCompare`） |
| `Item.updatedAt` / `completedAt` | —（不映射） | OKR 派生计算不读；缓存签名相关逻辑未移植 |
| `Item.okr.period` | `OkrData.period` | 空串视为「没有周期」（等价 TS 真值判断） |
| `Item.okr.confidence` | `OkrData.confidence: Float64` | 1..10，越界/NaN 由 `confidenceBucket` 夹紧 |
| `Item.okr.metric` | `OkrData.metric: ?OkrMetric` | `OkrMetric(start, target, current, unit)` |
| `Item.okr.krOwner` | `OkrData.krOwner: ?String` | 搜索使用；`None` 等价 TS `undefined` |
| `Item.gantt.start/end` | `OkrSchedule.start/end: ?String` | 只有 `display.formatSchedule` 读取 |
| `Edge.id/from/to/type/label` | `OkrEdge.id/fromId/toId/edgeType/label` | `from` 是仓颉关键字，改 `fromId` |
| `Area.id/name/color/order` | `OkrArea` 同名字段 | 只有 `name` 参与搜索 |
| `Workspace.items/edges/areas` | `OkrWorkspace` 同名字段 | `version` / `runs` / `updatedAt` 与 OKR 计算无关，不映射 |

## 4. 关键语义与边界规则

### 4.1 指标换算（`metricProgress` / `metricPercent`）

| 输入 | 状态 | percent | clamped |
|---|---|---|---|
| 无 metric | `Unset` | `None` | false |
| 任一字段非有限（NaN/±Inf） | `Invalid` | `None` | false |
| `\|target − start\| < 1e-9`（含 `target == start`、0 目标 0 起点） | `Flat` | `None` | false |
| 方向感知比率 `< 0`（正向低于 start / 负向高于 start） | `Under` | `Some(0)` | true |
| 比率 `> 1`（正向高于 target / 负向低于 target） | `Over` | `Some(100)` | true |
| `0 ≤ 比率 ≤ 1`（含等于 start / 等于 target） | `InRange` | `Some(round(比率×100))` | false |

- 负增长目标（`target < start`）不用特判：比率符号自动反向，测试覆盖 `(5 → 2)` 三个方向。
- `hasMetricRange` 只看 `start` / `target` 是否有限与差值，不看 `current`（与 TS 一致）。
- 换算取整用 `roundTo(ratio * 100, digits: 1)` 的 `0` 位版本，即 `jsRound`（`.5` 向 +∞），不用整数除法。

### 4.2 时间进度（`quarterElapsedPercent`）

- 季度首日 0、末日 100，区间外夹紧；分母 `end − start` 为「日历日差」。
- `totalDays <= 0` 时（构造上不会出现，保留移植）：`elapsedDays >= 0 → 100`，否则 `0`。
- 周期无法匹配 `^(\d{4})-Q([1-4])$` 或日期非法 → `0`。
- 结果 `roundTo(..., digits: 1)`，与 TS 同容差（测试用 `0.05`）。

### 4.3 落后判定与信心

- `isKrBehind(progress, elapsed)`：`elapsed − progress ≥ 10`；任一非有限 → false（不抛异常）。
- `confidenceBucket`：先夹紧 1..10（NaN → 1），再 1–3 低 / 4–6 中 / 7–10 高；小数如 3.4 → 中、6.5 → 高。

### 4.4 进度滚动（`rollupProgress`，`core.data.selectors` 的移植）

- objective：KR 平均值；无 KR → 子项完成比。
- keyresult：有 metric 且 `target != start` → `(current−start)/(target−start)×100`；否则 done→100，再否则子项完成比。
- project/sop：子项完成比；其余：done→100，否则 0。
- 每层 `clamp(jsRound(value), 0, 100)`；NaN 会原样传播（与 TS 的 `Math.min/Math.max` 链一致），调用方需自行判断。
- 父子环用 `visiting` 集合保护（环内返回 0），不会无限递归。

### 4.5 对齐（`executionItemsOf`）

- 先按 `edges` 数组顺序取 `from == krId && type == okr` 的边目标，过滤非 project/action 与重复项；
- 再取 `parentId == krId` 的 project/action（按 `order`、`createdAt` 排序），跳过已出现的 id；
- 同一执行项同时命中两条路径时以 edge 为准（`edgeId` 保留，可解除关联）。

### 4.6 搜索与分页

- 搜索文本 = `title + " " + notes + " " + areaName + " " + krOwner + " " + tags…`，`trim` 后 `toLower` 再 `contains`；
  空查询命中所有目标且保留全部 KR。
- `paginateObjectiveKrs` 按 KR 行数（不是目标数）分页：预算用尽即停止；无 KR 的目标在预算内照常出现。
- `resolveOkrPageLimit`：key（季度+搜索词）变化回到 `pageSize`；`nextOkrPage` 在当前上限上加一页。

### 4.7 展示格式化

- `formatNumber`：非有限 → `—`；整数 → JS `String(x)`；其它 → `Number(x.toFixed(2))` 再 `String(...)`
  （`2.345 → "2.35"`、`0.125 → "0.13"`、`-0.001 → "0"`、`1234.5678 → "1234.57"`）。
- `unitSuffix`：`%` 紧跟数字，其余单位前加空格。
- `formatMetric`：`未设指标` / `2.1 → 3%` / `42 → 60 分`。
- `formatSchedule`：`02/01 – 03/15`（U+2013）、缺一端为 `—`、两端都空/无 gantt 为 `未排期`。
- `statusTone` / `progressTone` 与 `STATUS_TONE` 表逐项一致；`progressTone` 中 `behind` 优先于 `≥100`。

### 4.8 指标草稿（`pendingMetricPatch` / `flushMetricDrafts`）

- 数值字段为空或非法（`""`、`abc`、`Infinity`、`1e999`）→ 跳过，保留 store 旧值。
- 规范化后与 `lastCommitted` 或 store 当前值文本相同 → 跳过（`"42.0"` 与 `"42"` 视为相同）。
- 单位是文本字段：允许清空，提交前 `trim`。
- 多个字段待提交时合并成一个 `OkrMetric`，`fields` 顺序固定为 `start, current, target, unit`。
- `latest == None` 时基准是 `EMPTY_METRIC`（`start 0 / target 100 / current 0 / unit ""`）。

## 5. 浮点一致性策略

TS 侧依赖 JS 数字语义，仓颉默认行为不同，本包显式复刻：

| JS | 仓颉默认 | 本包实现 |
|---|---|---|
| `Number.isFinite` | 无 `isFinite()` 成员 | `isFiniteNumber`（`!isNaN && !isInf`） |
| `Math.round`（`.5` 取较大值） | `std.math.round` 是银行家舍入 | `jsRound`（`floor` + 半值判断，`0.49999999999999994 → 0`） |
| `String(number)`（最短往返、指数阈值） | `Float64.toString()` 是 `"%f"`（6 位小数） | `jsNumberToString`：1..17 位有效数字搜索 + ECMA-262 渲染规则 |
| `Number(x.toFixed(2))` | `format(".2")` 用 printf 舍入（精确 .5 时向偶） | `jsFixedNumberToString`：Dekker 残差判真 .5 → 远离零 |
| `Number(text)`（含 `0x/0o/0b`） | `Float64.tryParse` 不接受进制前缀 | `parseMetricNumber` 显式处理前缀，非有限 → `None` |
| `trim()` | `trimAscii()` 只去 ASCII 空白 | `std.unicode` 的 `String.trim()` |
| `toLowerCase()` | `toAsciiLower()` 只处理 ASCII | `std.unicode` 的 `String.toLower()` |

数值格式化交叉验证（`jsNumberToString` 与 `formatNumber` 对 JS 输出）：

- 固定边界用例 40 条（`0`、`-0`、`1/3`、`0.1+0.2`、`1e21`、`1e-7`、`1e308`、`5e-324`、`123456789012345678`、`1e15+0.5`…）：0 差异。
- 300 个伪随机 `Float64`（bit pattern 固定种子生成，覆盖 `1e-20..1e20`、`1e21` 区间、整数、分数、±小量）：0 差异。

## 6. 与 TS 的差异清单

语义差异：**无**。以下是环境性/接口性差异，均有明确理由且不影响计算结果：

1. `today` 必须注入：TS 的 `today: Date = new Date()` 默认值在仓颉侧改为必填 `CivilDate`（禁用系统时钟）。
   同一本地日历日下结果逐位相同；季度计算只用日历日差，与 DST/时区无关。
2. `roundTo(value, digits)` 的 `digits` 是 `Int64`；TS 允许小数位（`10 ** 0.5`）。实际调用点只有 0/1/2 位。
3. 年份 < 100 的季度串（如 `0050-Q1`）：JS `new Date(50, 0, 1)` 会被映射成 1950 年，本包按字面 50 年处理。
   季度串来自 UI 的 4 位年份，该分支不可达。
4. `dateKey` 取前 10 个字符：TS 按 UTF-16 码元，本包按 Rune（仅对首 10 字符含星平面字符的怪输入有别；
   日期键是 ASCII）。
5. `trim()` / `toLower()` 使用 Unicode 属性实现：JS `trim` 还会去掉 U+FEFF、但不去 U+0085，仓颉相反。
   仅在指标文本里出现这两个码点时才可观测。
6. `parseMetricNumber` 的 `0x/0o/0b` 字面量用 `Float64` 累加：超过 2^53 的超大进制字面量可能差几个 ulp
   （JS 走大数解析）；指标输入域内不可达。
7. `executionItemsOf` 不做引用缓存：TS 在内容不变时返回同一数组（供 React `memo` 跳过渲染）。
   纯函数包每次返回新数组，元素与顺序完全相同；视图层如需按签名缓存，应在自己包内实现。
8. `summarize` / `rollupProgress` 每次调用重建索引（TS 用 `WeakMap` 按 workspace 身份缓存）。
   对不可变 workspace 结果相同，仅性能差异。

## 7. 测试

| 文件 | 用例数 | 断言数 | 覆盖 |
|---|---|---|---|
| `quarter_test.cj` | 11 | 56 | `quarterElapsedPercent`（首日/末日/区间内/夹紧/非法周期/闰年）、`quarterRange`、日期校验、`shiftQuarter` / `nextQuarter` / `quarterLabel` |
| `metric_test.cj` | 10 | 54 | `metricPercent`、`metricProgress`、`hasMetricRange`：线性换算、夹紧、0 目标、负增长、epsilon、NaN、取整 |
| `numbers_test.cj` | 5 | 36 | `jsRound` / `roundTo` / `power10` / `jsFixedNumberToString` / `isFiniteNumber` / `jsTrunc` |
| `progress_test.cj` | 12 | 56 | `isKrBehind`、`confidenceBucket`、`summarize`、`rollupProgress`（越界夹紧、NaN 传播、完成比取整、父子环） |
| `alignment_test.cj` | 18 | 74 | `executionItemsOf`、`matchesQuery`、`filterObjectives`、分页与分页状态、`buildParentPathText` |
| `display_test.cj` | 9 | 74 | tone 映射、`formatNumber`、`jsNumberToString`（含 1e308 / 5e-324 / 7÷3 长尾）、单位、指标摘要、排期、日期键 |
| `metric_draft_test.cj` | 12 | 68 | `metricDraft.test.ts` 全部 6 条 + 无基准值、去重、长小数规范化、`parseMetricNumber` |
| **合计** | **77** | **418** | `okrMath.test.ts` 28 条、`metricDraft.test.ts` 6 条断言全部逐条移植；另补 `okrListPerf.test.ts` 分页/路径文本的值级断言 |

验证方式（共享工作树在他包未就绪时不可用，用隔离最小工程）：

```bash
# 1) 主方式：完整快照（其它包编译通过时）
rsync -a --delete --exclude target --exclude 'tools/parity/out' \
  /home/ethan/CodeRepo/sandbox/Textura/cangjie/ /tmp/cj-logic-okr/
cd /tmp/cj-logic-okr && source scripts/env.sh && cjpm build -i -o textura && cjpm test

# 2) 隔离最小工程（本包只用 std，可独立验证）
mkdir -p /tmp/okr-logic-proj/src/views/okr/logic
# cjpm.toml: name = "textura"; src/textura.cj: package textura
# src/views/views.cj: package textura.views; src/views/okr/okr.cj: package textura.views.okr
cp cangjie/src/views/okr/logic/*.cj /tmp/okr-logic-proj/src/views/okr/logic/
cd /tmp/okr-logic-proj && source /home/ethan/CodeRepo/sandbox/Textura/cangjie/scripts/env.sh && cjpm test
```

最近一次结果：`TOTAL: 77, PASSED: 77, FAILED: 0`（隔离工程，连续两次一致）。

## 8. 视图层接入建议

```cangjie
// textura.views.okr（视图包，不在本包范围内）
let items = workspace.items |> map(toOkrItem)              // 按第 3 节映射
let okrWorkspace = OkrWorkspace(items: items, edges: edges, areas: areas)
let summary = summarize(okrWorkspace, "2026-Q1", CivilDate(2026, 2, 14))
let rows = paginateObjectiveKrs(filterObjectives(okrWorkspace, "2026-Q1", query), limit)
let info = metricProgress(item.okr?.metric)                 // flat/over/under 提示
let tone = progressTone(summary.averageProgress, isKrBehind(progress, summary.elapsedPercent))
```

- 颜色/字号/间距仍由 `textura.ui` 提供；本包只给 `BadgeTone` / `ProgressTone` 枚举与文本。
- 需要行级缓存（`executionItemsOf` / `buildParentPathText`）时，在视图包内按 `workspace` 内容签名记忆化。
