# 日历算法层（`textura.views.calendar.logic`）

本包是 Web 版日历纯函数层的仓颉移植：公历日序号、农历换算（含闰月、干支生肖、传统节日）、
二十四节气、月视图 6×7 网格、周视图 7 列、跨天条目区间与「第 n/m 天」标注、按日分桶与排序、
农历标签优先级、无障碍文案、条目展示映射。

对应源码（只读参照）：

- `src/modules/calendar/lunar.ts`（441 行）
- `src/modules/calendar/calendarLogic.ts`（357 行）
- `src/modules/calendar/itemDisplay.ts`（81 行）
- 测试真值：`src/modules/calendar/lunar.test.ts`（301 行）、`calendarLogic.test.ts`（308 行）
- 渲染管线参照：`CalendarPage.tsx`、`MonthGrid.tsx`、`WeekView.tsx`（只读，用于确认字段用途与裁剪规则）

## 1. 依赖边界

- 包名 `textura.views.calendar.logic`，目录 `cangjie/src/views/calendar/logic/`。
- **只依赖 `std`**：不 import `cui`，不 import `textura.core.data`，不 import 其它视图包。
- 不读系统时钟：`today` / `selected` 全部由调用方注入（`YYYY-MM-DD`）。
- 时区固定 Asia/Shanghai：日期一律是「北京时间日历日」的 `YYYY-MM-DD` 字符串或 `Ymd` 值类型；
  内部日历运算用整数日序号（1970-01-01 = 0），只在节气求解里出现浮点。
- 输出只有结构化数据与文本，不含颜色值：`areaColor` 原样透传，状态色以语义色调给出，
  由渲染层映射到 `textura.ui` 令牌。

## 2. 文件

| 文件 | 行 | 内容 |
|---|---|---|
| `ymd.cj` | 280 | `Ymd` 值类型、`days_from_civil` / `civil_from_days` 整数日历、日期键解析/格式化、星期 |
| `lunartable.cj` | 291 | `LUNAR_INFO` 表（1900–2100 每年一个编码）、月名/日名/干支/生肖字表、农历节日表 |
| `lunar.cj` | 364 | 大小月与闰月天数、农历↔公历双向换算、干支生肖、节日（含除夕、清明） |
| `solarterm.cj` | 271 | 二十四节气：太阳视黄经牛顿迭代 + ΔT，按北京时间取日期，年度缓存 |
| `label.cj` | 298 | 农历标签优先级、星期/月/周标题、无障碍标签、相对日期、选择器选项、面板自动展开 |
| `grid.cj` | 173 | 月网格 42 格（扁平 + 6×7 分行）、周区间、`shiftMonth` |
| `item.cj` | 437 | 输入记录 `CalItem`、条目区间、第 n 天、按日分桶、当日排序、展示映射 |
| `view.cj` | 370 | 面向渲染的 `DayCell` / `DayColumn` / `DayEntry`、`buildMonthView` / `buildWeekView` |
| `ymd_test.cj` | 110 | 日序号、星期、非法日期、跨月加天、`daysInMonth` 的 JS 语义 |
| `lunar_test.cj` | 509 | `lunar.test.ts` 全部断言 + 全区间摘要对拍 |
| `solartermtruth_test.cj` | 212 | 由 TS 输出生成的 201 年 × 24 节气黄金值（测试专用数据） |
| `label_test.cj` | 132 | 标签优先级、aria、相对日期、面板断点 |
| `grid_test.cj` | 208 | 月网格对齐（2 月 / 31 天 / 跨年）、周区间、标题 |
| `item_test.cj` | 329 | 分桶裁剪、排序、可见性、展示映射 |
| `view_test.cj` | 285 | 6×7 渲染模型、折叠计数、跨天「第 n/m 天」 |

合计生产代码 **2484 行**、测试 **1785 行**（117 个用例、474 条断言，仅 `cjpm test` 编译）。

## 3. 输入映射：`core.data.Item` → `CalItem`

`CalItem` 是只读投影，只保留日历需要的东西。映射由视图层完成，logic 不感知 `Item`：

| TS `Item` / 派生素材 | `CalItem` | 说明 |
|---|---|---|
| `id` | `id: String` | 原样；同日去重与选择态比对用 |
| `title` | `title: String` | 卡片标题、当日排序的最终键 |
| `kind`（`ItemKind` 九值） | `kind: String` | 小写字符串原样：`objective` / `keyresult` / `project` / `action` / `sop` / `step` / `milestone` / `reference` / `note`；`kindIcon` / `routeForKind` 用它 |
| `status`（`ItemStatus` 八值） | `status: String` | 小写字符串原样；`dropped` 被过滤，`done` 保留；`statusLabel` / `statusTone` 用它 |
| `gantt.start` | `startDate: String` | **原始串**，缺省 `""`；内部按 `dateKey` 语义（去空白、取前 10 字符）裁剪 |
| `gantt.end` | `endDate: String` | 同上 |
| `Area.color`（按 `areaId` 解析后） | `areaColor: String` | **只透传不解释**；缺省 `""` 表示无领域，渲染层回退 `text-faint` 令牌 |
| `kind == "milestone"` | `isMilestone: Bool` | 由映射器一次算出，避免渲染层反复比较字符串 |

`Workspace.items`（经 `selectors.scheduledItemsInRange` 取区间）→ `Array<CalItem>`；
`edges` / `runs` / `okr` / `sop` / `gtd` 与本包无关。

视图层的典型调用：

```cangjie
let rows = buildMonthView(2026, 10, items, today, selected)   // 6 行 × 7 列 DayCell
let cols = buildWeekView(selected, items, today, selected)    // 7 列 DayColumn
```

## 4. 日期层（`ymd.cj`）

- `Ymd { year, month, day }` 是值类型，支持 `==` / `<` / `>=`、`key()`、`dayNumber()`、
  `weekday()`、`addingDays(n)`、`monday()`。
- 日序号以 1970-01-01 = 0 为基准，与 TS `Date.UTC(...) / 86400000` 完全一致；
  用 Howard Hinnant 的 `days_from_civil` / `civil_from_days` 纯整数算法，不做时区换算。
- `parseKey` 等价 TS `dayNumberFromKey`：严格 `^\d{4}-\d{2}-\d{2}$`、`month` 1..12、
  `day` 不超过当月天数；另外**年份 0000–0099 一律返回 `None`**，因为 JS `Date.UTC`
  会把 0..99 解释为 19xx，回读校验必然失败。
- `daysInMonth(year, month)` 复刻 `new Date(Date.UTC(year, month, 0)).getUTCDate()` 的语义：
  月份按 `year*12 + month - 1` 归一化，因此 `month = 0` → 上一年 12 月 31 天、
  `month = 13` → 次年 1 月 31 天。
- `dateKeyOf(raw)` 复刻 `core/utils.ts` 的 `dateKey`：去首尾空白，长度 ≥ 10 取前 10 字符，否则 `""`。

## 5. 农历表范围与来源

- 表 `LUNAR_INFO` 共 201 项，覆盖 **1900–2100**，从 `lunar.ts` **逐字搬运**（未重新推导、
  未重新标定任何一年的月序）。
- 每项编码：低 4 位 = 闰月月份（0 表示无闰月）；`0x10000` 位 = 闰月是否 30 天；
  `0x8000 … 0x10` 位 = 正月…腊月是否 30 天。
- 基准日 **1900-01-31 = 农历 1900 年正月初一**；支持范围是闭区间
  **1900-01-31 ～ 2100-12-31**（`LUNAR_MIN_KEY` / `LUNAR_MAX_KEY`），界外一律 `None`。
- `YEAR_START_DAYS`（202 项）在包初始化时由 `lunarYearDays` 前缀和算出，供农历年二分查找。
- 节气缓存按年惰性计算，用 `Mutex` 保护，避免并行测试下的数据竞争。

## 6. 节气算法（`solarterm.cj`）

完全按原实现移植，不引入新的星历表：

1. **目标黄经**：小寒 285°，其后每个节气 +15°，到冬至 270°，共 24 个。
2. **初值**：`1 月 1 日 + (index × 15.2184 + 4.5) 天`。
3. **牛顿迭代**（最多 30 次）：`Δ = normalize(λ(jde) − target)`，`Δ > 180°` 时减去 360°，
   `|Δ| < 1e-8` 收敛；每步 `ms -= Δ / 0.98564736 × 86400000`（太阳日均行度折算）。
4. **太阳视黄经** λ(jde)：Meeus《Astronomical Algorithms》第 25 章低精度公式 ——
   平黄经 + 中心差（3 项正弦）+ 章动近似（`−0.00569 − 0.00478 sin Ω`），再叠加 5 项行星长周期摄动
   （系数 `0.00134 / 0.00154 / 0.002 / 0.00179 / 0.00178`）。
5. **ΔT**（TT − UT，秒）：Espenak–Meeus 分段多项式，覆盖 1900–2100；
   力学时 `jde = jd(UT) + ΔT / 86400`。
6. **取日期**：`floor((t + 8h) / 86400000)` → 日序号 → `YYYY-MM-DD`（北京时间日历日）。

`SolarTermInfo { name, dateKey }`；同一天出现两个节气时以先出现者为准（与 TS `Map` 覆盖语义一致，
实际在 1900–2100 从未发生：每年 24 个节气日互不相同）。

## 7. 月网格、周视图与渲染模型

- `buildMonthGrid(year, month)`：固定 **42 格**（6×7），周一为每列首日，含上下月补位；
  `inMonth` / `weekend`（周六、周日）/ `weekday`（0 = 周一）逐格给出；月份非法返回空数组。
- `buildMonthGridRows` 返回 6×7 分行视图，`buildMonthView` 进一步把条目与农历标签填入每格。
- `buildWeekView(anchorKey, ...)`：以 `anchorKey` 所在周的周一为首列，共 **7 列**。
- `DayCell`（月网格一格）：`ymd`、`inMonth`、`weekend`、`weekday`、`lunarText`、`lunarKind`、
  `isFestival`、`isSolarTerm`、`isToday`、`isSelected`、`items`（当日全部、已排序）、
  `visibleItems`（前 3 个）、`itemCount`、`overflowCount`、`ariaLabel`。
- **折叠规则**：月格最多显示 `MONTH_VISIBLE_ITEMS = 3` 个条目圆点，
  `overflowCount = max(0, itemCount − 3)`，渲染层显示 `+n`。
- `DayColumn`（周视图一列）：`ymd`、`weekday`、`weekend`、`lunarText`、`lunarKind`、
  `isToday`、`isSelected`、`ariaLabel`（`星期三 10月21日`）、`entries`。
- `DayEntry`（周视图一张卡片）：`item`、`dayIndex`（第几天，1 起；不在区间为 0）、
  `dayCount`（总天数）、`spanText`（`第 n/m 天` / `截止` / 空串）、`isDone`。

## 8. 条目区间、分桶与排序

- `itemSpan(item)`：`start = dateKey(startDate) ?? dateKey(endDate)`、`end` 反向对称；
  只有截止日的条目收敛为单日；**反向区间自动归一化**（交换 start/end）。
- `spanDayIndex(item, key)`：区间内返回 1..days，否则 0。
- `spanText(item, key)`：跨天 → `第 n/m 天`；单日且只有截止日 → `截止`；否则空串。
- `bucketItemsByDay(items, from, to)`：跨天条目落在每个覆盖日，只按 `[from, to]` 裁剪，
  `from > to` 自动交换，非法输入返回空表；每个桶内部调用 `sortDayItems`。
- `sortDayItems(items)`：**跨天优先 → 开始日期 → 标题**，完全相同时保持输入顺序（稳定排序）。
- `visibleItems(items)`：过滤 `dropped`，保留 `done`。
- `calendarItemsInRange(items, from, to)`：等价
  `visibleItems(scheduledItemsInRange(workspace, from, to))`，供没有 workspace 索引的调用方使用。

## 9. 展示映射（`itemDisplay.ts`）

| 函数 | 输出 |
|---|---|
| `kindIcon(kind)` | `target` / `folder` / `clock` / `workflow` / `flag` / `link` / `edit` |
| `statusTone(status)` | `ok` / `warn` / `danger` / `info` / `accent` / `neutral` |
| `statusColorToken(status)` | 同上，缺省 `text-faint` |
| `statusLabel(status)` | 收件箱 / 下一步 / 进行中 / 等待中 / 已排期 / 将来 / 已完成 / 已放弃 |
| `routeForKind(kind)` | `gantt` / `sop` / `okr` / `gtd` |
| `areaColorOf(item)` | 原样透传 `areaColor`；空串表示回退 `text-faint` |

## 10. 公开 API

```cangjie
// ymd.cj —— 公历日期
public struct Ymd { public let year: Int64; public let month: Int64; public let day: Int64 }
public func isLeapYear(year: Int64): Bool
public func daysInMonth(year: Int64, month: Int64): Int64
public func floorDiv(a: Int64, b: Int64): Int64
public func dayNumberOf(year: Int64, month: Int64, day: Int64): Int64
public func ymdOf(dayNumber: Int64): Ymd
public func pad2(value: Int64): String
public func keyOf(year: Int64, month: Int64, day: Int64): String
public func parseKey(key: String): ?Ymd
public func isDateKeyShape(key: String): Bool
public func dayNumberOfKey(key: String): ?Int64
public func keyOfDayNumber(dayNumber: Int64): String
public func addDaysToKey(key: String, days: Int64): String
public func weekdayIndexMonday(dayNumber: Int64): Int64
public func weekdayOfKey(key: String): Int64

// lunartable.cj —— 数据表
public let LUNAR_INFO: Array<Int64>
public let LUNAR_MONTH_NAMES: Array<String>
public let LUNAR_DIGITS: Array<String>
public let HEAVENLY_STEMS: Array<String>
public let EARTHLY_BRANCHES: Array<String>
public let ZODIAC_ANIMALS: Array<String>
public let LUNAR_FESTIVALS: HashMap<String, String>

// lunar.cj —— 农历
public let LUNAR_MIN_KEY: String      // "1900-01-31"
public let LUNAR_MAX_KEY: String      // "2100-12-31"
public let YEAR_START_DAYS: Array<Int64>
public struct LunarDate { year, month, day, isLeap, monthName, dayName, ganzhiYear, zodiac, festival, solarTerm }
public struct Ganzhi { ganzhi, zodiac }
public func isLeapMonth(year: Int64): Int64
public func leapMonthDays(year: Int64): Int64
public func lunarMonthDays(year: Int64, month: Int64): Int64
public func lunarYearDays(year: Int64): Int64
public func inSupportedRange(dayNumber: Int64): Bool
public func lunarMonthName(month: Int64): String
public func lunarMonthName(month: Int64, isLeap: Bool): String
public func lunarDayName(day: Int64): String
public func ganzhiOfYear(lunarYear: Int64): Ganzhi
public func solarToLunar(dateKey: String): ?LunarDate
public func lunarToSolar(year: Int64, month: Int64, day: Int64): ?String
public func lunarToSolar(year: Int64, month: Int64, day: Int64, isLeap: Bool): ?String
public func festivalOf(dateKey: String): ?String

// solarterm.cj —— 二十四节气
public let SOLAR_TERM_NAMES: Array<String>
public struct SolarTermInfo { name, dateKey }
public func solarTermsOfYear(year: Int64): Array<SolarTermInfo>
public func solarTermOf(dateKey: String): ?String
public func solarTermFestivalOf(dateKey: String): ?String

// label.cj —— 文案
public let PANEL_BREAKPOINT: Int64            // 1180
public let WEEKDAY_LABELS / WEEKDAY_FULL_CN / MONTH_NAMES_CN: Array<String>
public enum CalendarViewMode { | Month | Week }
public enum LunarLabelKind { | Festival | Term | Lunar | NoLabel }
public struct LabelTone { kind, text }
public struct SelectOption { value, label }
public func shouldAutoOpenPanel(panelOpen: Bool, viewportWidth: Int64, userCollapsed: Bool): Bool
public func shouldAutoOpenPanel(panelOpen: Bool, viewportWidth: Int64, userCollapsed: Bool, breakpoint: Int64): Bool
public func weekdayLabel(key: String): String
public func monthLabel(year: Int64, month: Int64): String
public func weekLabel(key: String): String
public func lunarOf(key: String): ?LunarDate
public func lunarLabelOf(lunar: ?LunarDate): LabelTone
public func lunarLabelInfo(key: String): LabelTone
public func lunarLabel(key: String): String
public func lunarFullLabel(lunar: LunarDate): String
public func fullDateLabel(key: String): String
public func cellAriaLabelOf(key: String, lunar: ?LunarDate, today: String): String
public func cellAriaLabel(key: String, today: String): String
public func relativeDayLabel(key: String, today: String): String
public func monthOptions(): Array<SelectOption>
public func yearOptions(): Array<SelectOption>

// grid.cj —— 网格
public struct MonthCell { key, year, month, day, weekday, inMonth, weekend }
public struct WeekInfo { start: Ymd, end: Ymd, year, month, monthEnd }
public struct YearMonth { year, month }
public func shiftMonth(year: Int64, month: Int64, delta: Int64): YearMonth
public func buildMonthGrid(year: Int64, month: Int64): Array<MonthCell>
public func buildMonthGridRows(year: Int64, month: Int64): Array<Array<MonthCell>>
public func weekRange(key: String): WeekInfo
public func weekDays(key: String): Array<MonthCell>

// item.cj —— 条目
public struct CalItem { id, title, kind, status, startDate, endDate, areaColor, isMilestone }
public struct DayItemSpan { start: Ymd, end: Ymd, days: Int64 }
public func dateKeyOf(raw: String): String
public func itemSpan(item: CalItem): ?DayItemSpan
public func spanDayIndex(item: CalItem, key: String): Int64
public func spanText(item: CalItem, key: String): String
public func bucketItemsByDay(items: Array<CalItem>, from: String, to: String): HashMap<String, Array<CalItem>>
public func sortDayItems(items: Array<CalItem>): Array<CalItem>
public func visibleItems(items: Array<CalItem>): Array<CalItem>
public func calendarItemsInRange(items: Array<CalItem>, from: String, to: String): Array<CalItem>
public func isDoneItem(item: CalItem): Bool
public func statusLabel(status: String): String
public func statusTone(status: String): String
public func statusColorToken(status: String): String
public func kindIcon(kind: String): String
public func routeForKind(kind: String): String
public func areaColorOf(item: CalItem): String

// view.cj —— 渲染模型
public let MONTH_VISIBLE_ITEMS: Int64         // 3
public struct DayCell { ymd, inMonth, weekend, weekday, lunarText, lunarKind, isFestival, isSolarTerm,
                        isToday, isSelected, items, visibleItems, itemCount, overflowCount, ariaLabel }
public struct DayColumn { ymd, weekday, weekend, lunarText, lunarKind, isToday, isSelected, ariaLabel, entries }
public struct DayEntry { item, dayIndex, dayCount, spanText, isDone }
public func buildMonthView(year: Int64, month: Int64, items: Array<CalItem>, today: String,
                           selected: String): Array<Array<DayCell>>
public func buildMonthViewFlat(year: Int64, month: Int64, items: Array<CalItem>, today: String,
                               selected: String): Array<DayCell>
public func buildWeekView(anchorKey: String, items: Array<CalItem>, today: String,
                          selected: String): Array<DayColumn>
```

## 11. 与 TS 的差异

逐函数对照 TS 后只有以下 4 处**表述层面**的差异，语义等价，没有期望值偏差：

1. **`statusColor` → `statusTone` / `statusColorToken`**
   TS 返回 CSS 变量名（`var(--ok)` 等）；仓颉渲染层没有 CSS，因此改为返回语义色调
   （`ok` / `warn` / `danger` / `info` / `accent` / `neutral`，缺省 `text-faint`），
   由渲染层映射到 `textura.ui` 令牌。色调与 TS 一一对应（测试逐条覆盖）。
2. **`sortDayItems` 的标题比较**
   TS 用 `localeCompare(b.title, 'zh-Hans-CN')`（ICU 拼音序）；本包用码点序，
   再以输入下标做稳定 tie-break。**首日排序（跨天优先 → 开始日期）与 TS 完全一致**，
   只有「同一天、同开始日、纯中文标题」的相对顺序可能与拼音序不同（例如「张」与「李」）。
   引入 ICU 拼音表超出本包范围；如需逐字一致，应由调用方在映射前预排序或注入比较器。
3. **`weekRange` 的非法输入回退**
   TS 返回 `{ start: key, end: key, year: 0, month: 0, monthEnd: 0 }`（把非法 key 原样带回）；
   本包返回 `start = end = Ymd(0, 0, 0)`，`year/month/monthEnd` 同样为 0，
   非法 key 不再出现在返回值里（`Ymd` 无法承载非法 key）。调用方本来就要先校验日期键。
4. **`lunarMonthName` / `lunarToSolar` 的默认参数**
   TS 用 `isLeap = false` 默认值；仓颉不支持位置参数默认值，改为**重载**
   （3 参 / 4 参版本），调用点写法与 TS 完全相同。

节气日期、农历全部字段（月/日/闰/月名/日名/干支/生肖/节日/节气）、
干支与生肖切换、春节/中秋/端午/除夕、大小月与闰月天数、6×7 网格首末格、
周区间、标题文案、aria 文案、相对日期、分桶结果与顺序、折叠计数 —
**均与 TS 逐条一致**，证据见第 12 节。

## 12. 测试与验证

工具链：`cjc 1.2.0 (cjnative)`。

### 12.1 用例（117 个，全绿）

| 测试类 | 用例 | 断言 | 覆盖 |
|---|---|---|---|
| `YmdTest` | 9 | 48 | 日序号基准、往返、星期、非法键（含 0000–0099）、跨月加天、`daysInMonth` 的 `Date.UTC(y,m,0)` 语义 |
| `LunarTest` | 27 | 131 | `lunar.test.ts` 全部断言 + 闰月表 + 全区间摘要 |
| `GridTest` | 16 | 76 | 42 格对齐、周一起始、周末列、跨年、闰年 2 月 29 天、平年 2 月整 4 行、31 天月份的网格能容纳 6 行、周区间、标题 |
| `ItemTest` | 27 | 100 | 分桶裁剪、边界日、反向区间交换、稳定排序、可见性、展示映射 |
| `LabelTest` | 19 | 41 | 标签优先级（节日 > 节气 > 农历日）、清明、闰月月名、aria、相对日期、面板断点 |
| `ViewTest` | 19 | 78 | 6×7 渲染模型、`overflowCount`、跨天条目每天出现、`第 n/m 天`、`截止` |

### 12.2 覆盖的边界

- **支持范围**：`1900-01-31`（首日 = 正月初一）、`1900-01-30`（界外 `None`）、
  `2099-12-31`、`2100-12-31`（末日 = 农历 2100 年腊月初一）、`2101-01-01`（界外）。
- **闰月**：2023 闰二月（29 天，03-22 ～ 04-19，`lunarToSolar(2023, 2, 30, true)` 为 `None`）、
  2023-03-21 仍是二月三十（非闰）、2025 闰六月、不存在的闰月返回 `None`。
- **节气**：2026 六个代表节气的具体日期；每年 24 个、名称与日期互不重复、按时间升序；
  1900 / 1950 / 2000 / 2050 / 2100 两个世纪端点；1900-01-31 之前的节气按约定返回 `None`。
- **网格**：2026-10（31 天）、2027-01（跨年）、2024-02（闰年 29 天）、2026-02（平年 28 天）、
  2027-02（28 天且 2/1 就是周一，整月正好 4 行）、2026-05（31 天，网格首格 04-27、末格 06-07）。
- **跨天条目**：`第 1/3 天` ～ `第 3/3 天`；跨月条目被区间裁剪；只有截止日显示 `截止`；
  区间外与无日期条目被忽略；`from > to` 自动交换。
- **折叠计数**：2 / 3 / 5 个条目分别得到 `overflowCount` 0 / 0 / 2。

### 12.3 TS 对拍（比逐条用例更强）

除逐条移植断言外，另用只读 TS 源码生成黄金值，对拍范围超出测试用例本身：

| 对拍项 | 范围 | 结果 |
|---|---|---|
| 二十四节气日期 | **1900–2100 全部 201 年 × 24 个 = 4824 条** | 逐条一致 |
| 农历逐日换算 | **1900-01-31 ～ 2100-12-31 共 73384 天**，字段含 月/日/闰/月名/日名/干支/生肖/节日/节气 | 摘要一致（`379894082`） |
| 春节（正月初一） | 1900–2100 共 201 个日期 | 摘要一致（`488893810`） |
| 往返一致性 | 2000-01-01 ～ 2050-12-31 共 **18628 天** `solarToLunar → lunarToSolar` | 0 失败 |

节气黄金值已固化为 `solartermtruth_test.cj`（测试专用数据，由 TS 输出生成，不手工修改），
因此精度回归会在 `cjpm test` 里直接暴露，不依赖 Node 环境。

### 12.4 如何验证

共享工作树里其它包仍在并行改动，`cjpm build` / `cjpm test` 会被**无关包**阻断
（当前 `textura.ui` 存在 `theme.cj` 与 `tokens.cj` 的重复声明与结构体初始化错误，
与本包无关）。本包只依赖 `std`，因此用隔离最小工程验证：

```bash
# 0) 快照（不要在工作树里跑 cjpm）
rsync -a --delete --exclude target --exclude 'tools/parity/out' \
  /home/ethan/CodeRepo/sandbox/Textura/cangjie/ /tmp/cj-logic-calendar/

# 1) 隔离工程（只含本包；Cangjie 不扫描没有包文件的中间目录，故补两级标记文件）
mkdir -p /tmp/cj-logic-iso/src/views/calendar
cd /tmp/cj-logic-iso
printf '[package]\ncjc-version = "1.2.0"\nname = "textura"\nversion = "0.1.0"\noutput-type = "executable"\n' > cjpm.toml
printf 'package textura\n\nmain() {\n    println("calendar logic iso")\n}\n' > src/root.cj
printf 'package textura.views\n' > src/views/views.cj
printf 'package textura.views.calendar\n' > src/views/calendar/calendar.cj
rsync -a --delete /home/ethan/CodeRepo/sandbox/Textura/cangjie/src/views/calendar/logic/ src/views/calendar/logic/
cd /tmp/cj-logic-iso && source /tmp/cj-logic-calendar/scripts/env.sh \
  && cjpm build && cjpm test
```

最近一次结果：`cjpm build success`（无警告），
`cjpm test` → `TOTAL: 117, PASSED: 117, SKIPPED: 0, ERROR: 0, FAILED: 0`。

另外单独用 `cjc` 在真实工作树快照里编译本包，确认它在仓库目录结构下自洽：

```bash
cd /tmp/cj-logic-calendar && source scripts/env.sh
cjc --output-type=staticlib -O2 -p src/views/calendar/logic -o /tmp/cjlogic   # 成功，无警告
```

`cjpm test` 会扫描 `src` 下所有子包，因此即使 `src/views/calendar/calendar.cj`
尚未 import 本包，本包的 117 个用例也会被编译和执行；等视图 worker 接线后
`cjpm build` 才会把本包纳入常规构建。

## 13. 未完成 / 后续

- **视图渲染层**（`textura.views.calendar` 的 CUI 布局、月/周切换、点击与键盘导航、
  日程面板、条目卡片）不在本包范围；本包只提供结构化数据与文本。
  接线时把 `DayCell.visibleItems` 画成圆点、`overflowCount` 画成 `+n`、
  `DayEntry.spanText` 画成副标题即可。
- **拼音序标题排序**：见第 11 节第 2 条。若页面上同一天有多条纯中文单日条目且要求与
  Web 版顺序完全一致，需要额外的拼音表或由调用方预排序。
- **农历表上限**：`LUNAR_INFO` 只到 2100 年，与 TS 一致；超出范围时月格只显示公历。
- `sortDayItems` 每次重建装饰数组（O(n log n) + 一次分配）；单日条目规模是十几条量级，
  不是热点，若将来需要可把比较器与下标复用。
