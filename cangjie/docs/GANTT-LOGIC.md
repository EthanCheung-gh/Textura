# 甘特算法层（`textura.views.gantt.logic`）

本包是 Web 版甘特纯函数层的仓颉移植：日/周/月三种缩放的刻度生成、日期 ↔ 像素双向映射、
两级表头分组、今天线位置、拖拽吸附与工期计算、任务条/依赖连线几何、行与列虚拟化窗口、
左侧树的分组行模型。

对应源码（只读参照）：

- `src/modules/gantt/scale.ts`（581 行）
- `src/modules/gantt/virtual.ts`（87 行）
- 测试真值：`src/modules/gantt/scale.test.ts`（398 行）、`src/modules/gantt/virtual.test.ts`（88 行）
- 几何/渲染分层参照：`GanttTimeline.tsx`、`GanttBar.tsx`、`GanttDependencies.tsx`、`GanttTree.tsx`（只读，用于确认单位与用途）

## 1. 依赖边界

- 包名 `textura.views.gantt.logic`，目录 `cangjie/src/views/gantt/logic/`。
- **只依赖 `std`**：不 import `cui`，不 import `textura.core.data`，不 import 其它视图包。
- 不读系统时钟（`today` / 拖拽增量全部由调用方注入），不持有 store，无副作用。
- 输出只有坐标与文本（不含颜色、字号），可直接驱动 Canvas 自绘或 CUI 布局。

## 2. 文件

| 文件 | 行 | 内容 |
|---|---|---|
| `logic.cj` | 31 | 包标记、几何契约版本、布局常量（`ROW_HEIGHT` / `HEADER_HEIGHT` / `BAR_HEIGHT` / `BAR_TOP_OFFSET` / `MILESTONE_WIDTH` / `UNGROUPED_ID`） |
| `numeric.cj` | 86 | `tsRound` / `tsRoundInt` / `tsFloorInt` / `tsCeilInt` / `isFiniteNumber` / `finiteOr` / `minF64` 等取整与夹取工具 |
| `dates.cj` | 306 | 儒略日整数运算、日期键解析/格式化、星期、周/月/季边界 |
| `model.cj` | 420 | 输入记录 `GanttRow`、缩放配置、全部输出记录（`BarRange` / `BarGeometry` / `TimelineColumn` / `Tick` / `Point` / `DepRect` / `BarRect` / `RowWindow` / 行模型） |
| `scale.cj` | 262 | `dateToX` / `xToKey` / `snapKey` / `barGeometry` / `moveBar` / `resizeBar` / `buildRange` / `visibleRange` / `totalWidth` / `formatRangeLabel` / `displayProgress` / `barRect` / `depRect` |
| `header.cj` | 249 | `buildHeader`（月/季分组 + 日/周/月列）、`headerTicks`、`columnWidths` |
| `virtual.cj` | 118 | `visibleRows` / `visibleColumns` / `rowWindow` |
| `rows.cj` | 423 | `isGanttable` / `rowDepth` / `buildRows`（分组、排序、折叠、未分组、汇总进度） |
| `deps.cj` | 94 | `dependencyPath`（依赖折线点序列） |
| `scale_test.cj` / `header_test.cj` / `rows_test.cj` / `virtual_test.cj` / `deps_test.cj` / `edge_test.cj` | 1359 | 单元测试（76 个用例、367 条断言），仅 `cjpm test` 编译 |

合计生产代码 **1989 行**、测试 **1359 行**。

## 3. 输入映射：`core.data.Item` → `GanttRow`

`GanttRow` 是只读投影，只保留算法需要的字段；`?T` 表示 TS 的可选值（`undefined` / `null`）。
映射由视图层完成，logic 不感知 `Item`：

| TS `Item` | `GanttRow` | 说明 |
|---|---|---|
| `id` | `id: String` | 原样 |
| `title` | `title: String` | 组头与任务条标签 |
| `kind` | `kind: GanttKind` | `ItemKind` 九值一一对应；分组/可排期判定用它 |
| `treeDepth(ws, id)` | `level: Int64` | 预计算的绝对深度（渲染缩进）；logic 用 `parentId` 重算 `rowDepth` 交叉校验 |
| `gantt.start` | `startDate: ?String` | **原始串**；内部按 `dateKey` 语义截前 10 字符 |
| `gantt.end` | `endDate: ?String` | 同上 |
| `gantt.progress` | `progress: ?Float64` | 缺省 `None`；`NaN` 仍可表达（按 0 展示） |
| `status` | `status: GanttStatus` | `ItemStatus` 八值一一对应 |
| `Area.color`（解析后） | `areaColor: String` | **只透传不解释**；用于任务条配色，logic 不参与选色 |
| `parentId` | `parentId: ?String` | `null` → `None`；分组归属与深度 |
| `order` | `order: Int64` | 组内/组间稳定次序 |
| `createdAt` | `createdAt: String` | 次序的最终 tie-break |

`Workspace.items` → `Array<GanttRow>`；`edges` / `areas` / `runs` 与本包无关（依赖连线由
调用方先用 `depRect` 建表，再把矩形交给 `dependencyPath`）。

## 4. 坐标系与单位

| 概念 | 约定 |
|---|---|
| 时间轴原点 | `range.start` 对应 `x = 0`，向右为正；单位是逻辑像素（`Float64`，DPR=1 时即 px） |
| 时间轴宽度 | `totalWidth(range, pxPerDay)`，**不是**视口宽度；视口裁剪用 `visibleRange` / `visibleColumns` |
| 行坐标 | 行号 `i` 的顶边 `y = i * ROW_HEIGHT`（36） |
| 任务条矩形 | `barRect(geometry, i)` → `y = i * 36 + 7`，`h = 22`，里程碑 `w = 16` |
| 依赖端点 | `depRect(geometry, i)` → `x1 = geometry.x`，`x2 = x + width`，`cy = i * 36 + 18` |
| 表头 | 两级共 `HEADER_HEIGHT = 52`；行区域滚动偏移需先扣掉表头（`scrollTop - 52`） |
| 窗口 | `WindowRange{start, end}` 与 `RowWindow{first, last}` 都是**排他上界**，可直接 `slice` |
| 日期 | 一律 `YYYY-MM-DD` 日期键；内部换成 `Int64` 天序号，**无时区、无毫秒、无时钟** |

## 5. 日期层（`dates.cj`）

- 天序号 = 1970-01-01 起算的公历天数（proleptic Gregorian），即 JDN − 2440588；
  `dayNumber(y, m, d)` / `civilFromDayNumber(n)` 互为逆运算（Hinnant 算法，支持负年份前的日期）。
- 日历差、星期、月初/月末/季度边界全部是整数运算，因此 **DST / 时区切换不可能造成列宽或拖拽偏移**
  （TS 的 `differenceInCalendarDays` 也是这个语义）。
- `weekdayOf(n)`：0 = 周日，对齐 `Date.prototype.getDay`（表头星期标签用）。
- `parseDateKey` 严格校验（月 1..12、日不超过当月长度）；`looksLikeDateKey` 只校验
  `YYYY-MM-DD` 形状（与 TS 正则 `/^\d{4}-\d{2}-\d{2}$/` 同义）；`dateKeyOf` 复刻
  `core/utils.dateKey`（trim 后取前 10 字符，不校验），因此 `gantt.start` 里的 ISO 时间戳
  会退化为日期。

## 6. 缩放与刻度规则（`buildRange` / `buildHeader`）

### 6.1 缩放配置（`zoomConfig`，与 TS `ZOOM_CONFIG` 逐字段一致）

| zoom | `pxPerDay` | `columnDays` | `snapDays` | `paddingBefore` | `paddingAfter` |
|---|---|---|---|---|---|
| `Day` | 40 | 1 | 1 | 7 | 14 |
| `Week` | 28 | 7 | 1 | 14 | 28 |
| `Month` | 12 | 7 | 1 | 30 | 60 |

### 6.2 时间轴总范围 `buildRange(rows, zoom, today)`

1. `today` 先吸附到天；`min = max = today`；
2. 逐条读 `itemRange`（缺一端按 1 天补；两端都缺跳过），取最早开始 / 最晚结束；
3. 两端按缩放留白：`start = min − paddingBefore`、`end = max + paddingAfter`；
4. 对齐：`Week` → 周一 / 周日；`Month` → 月初 / 月末；`Day` 不对齐；
5. `today` 恒在范围内（因为 `min/max` 的初值就是 `today`）。

`today` 是**必填参数**（不读系统时钟）；parity 的“今天”来自 `workspace.json.updatedAt` 或 `--today`。

### 6.3 两级表头 `buildHeader`

- 上层分组：
  - `Day` / `Week` → **月**：`key = yyyy-MM`；`label = yyyy年M月`（该年首月**或**首个分组）否则 `M月`；
  - `Month` → **季度**：`key = yyyy-Qn`；`label = yyyy Qn`。
  - 分组矩形一律 `clipRect` 裁剪到 `[range.start, range.end]`，所以首尾分组可能不满月/季。
- 下层列：
  - `Day`：每天一列，`key = 日期键`，`label = 日`，`sublabel = 日/一/…/六`，
    `weekend = 周六或周日`，`past = 该日 < today`；
  - `Week`：自 `range.start` 起每 7 天一列（**不**强制周一），`key = w-<start>`，`label = M/d`，
    末列按 `range.end` 截断，`past = 列末日 < today`；
  - `Month`：每月按 `1 / 8 / 15 / 22 / 29` 切段，末段对齐月末
    （闰年 2 月因此是 5 段，平年 4 段），`key = m-<y>-<m>-<day>`，`label = 起始日`，
    `past = 段末日 < today`。
- `width = totalWidth(range, pxPerDay)`；列 `x/width` 与 `range.start` 对齐累计，
  列宽之和恒等于 `width`（已测）。
- `headerTicks(header)` 把两级压平成 `Tick{ x, label, kind }` 流（先分组后列），
  `columnWidths(header)` 给出逐列宽度，可直接喂 `visibleColumns`。

**今天线**：`x = dateToX(today, range.start, pxPerDay)`。同一 `today` 在不同缩放下
时间轴起点不同，因此像素位置不同（`Day` 280 / `Week` 392 / `Month` 540，已测）；
`past` 标记以整列/整段为单位，不用像素位置。

## 7. 吸附与拖拽规则

- `snapKey(key, zoom)`：三种缩放 `snapDays = 1` → 清除时间、幂等。算法保留通用分支：
  粒度 `step > 1` 时按 **当月第几天 % step** 向回对齐（与 TS `snapDate` 同口径）。
- `tsRound(x) = floor(x + 0.5)`：这是 TS `Math.round` 的“半值向 +∞”语义
  （`Math.round(-2.5) === -2`），仓颉 `round` 是远离零取整，**不能直接用**。
  所有拖拽增量都走它：`+2.5 → +3`、`-2.5 → -2`、`-1.5 → -1`。
- `moveBar(bar, delta)`：整体平移，跨度不变；**不夹取**（拖到边界外由调用方决定是否回弹，
  `-100000` 天也能算，已测）。
- `resizeBar(bar, edge, delta)`：先归一化 `start <= end`；左边缘向右越过 `end` 夹到 `end`，
  右边缘向左越过 `start` 夹到 `start`；最小 1 天。
- `displayProgress(row)`：`status == Done → 100`（`toggleDone` 不回写 `gantt.progress`）；
  否则 `round` 后夹到 `0..100`；缺失 / `NaN` / `Inf` → 0。只用于展示，不改状态。
- `barGeometry(range, origin, pxPerDay)`：`days = 含首尾天数`（≥1），
  `width = max(pxPerDay, days * pxPerDay)`，`x = (start − origin) 天 × pxPerDay`。

## 8. 虚拟化（`virtual.cj`）

- `visibleRows(scrollTop, viewportH, rowH, buffer, total)`：
  `firstVisible = floor(top / height)`；`view == 0` 时窗口退化为
  `[firstVisible − buffer, firstVisible + buffer]`（保留锚点行，不返回空窗口），
  否则 `lastVisibleExclusive = ceil((top + view) / height)`；上下各加 `buffer`，
  再夹到 `[0, total]`。`total = None` 表示总行数未知（TS 的 `Infinity`），返回不封顶窗口。
- `visibleColumns(scrollLeft, viewportW, colWidths, buffer)`：按列宽累计，
  取第一个 `next > left` 的列与 `offset < right` 的最后列，两侧加 `buffer`；
  滚过末尾时 `firstVisible = count`，退化为末尾 `buffer` 列。
- `rowWindow(...)`：在 `visibleRows` 之上给出 `RowWindow{ first, last, offsetY }`，
  `offsetY = first * rowH`，Canvas 直接 `translate(0, offsetY)` 后按行号绘制。
- 0 宽/0 高视口、`rowH <= 0`、`scrollTop < 0`、`buffer < 0`、10k 行都在测试里钉住。

## 9. 左侧树 / 分组（`rows.cj`）

- 分组根：`parentId == None` 且 `kind ∈ {Project, Sop}` 且 `status ∉ {Inbox, Someday, Dropped}`。
- 可排期条目：`kind ∈ {Project, Action, Milestone}` 且 `status ∉ {Inbox, Someday, Dropped}`
  （`step` 不进甘特）。
- 组的保留条件：组内可排期后代 ≥ 1，或组根自身有日期。
- 组排序：有日期的组优先 → `order` 升序 → `createdAt` 升序（稳定排序）。
- 组内排序：有 `start` 的在前按升序，无日期在后；再 `order` → `createdAt`（稳定排序）。
- 深度：`depth = max(1, rowDepth(member) − rowDepth(root))`；未分组行 `depth = max(1, rowDepth(row))`。
- 组头进度：`Project` / `Sop` → 直接子项 done 比例（`done / total × 100`，四舍五入并夹到 0..100）；
  其余 → `done ? 100 : 0`。
- 未分组：未进入任何已展示组的可排期条目（且祖先不在分组里）合成 `UNGROUPED_ID = "__ungrouped"`，
  标题 `未分组`，进度是该批 `displayProgress` 的平均值（四舍五入），永远排最后。
- `collapsed` 命中的分组只输出组头（`collapsed = true`），计数/区间/进度照常保留。
- 环形父子关系有保护：不会死循环，也不会丢行（全部落到未分组）。

## 10. 依赖连线（`deps.cj`）

`dependencyPath(fromRect, toRect, blockers, width) -> Array<Point>`：`from` 依赖 `to`
（`to` 是前置），点序列等价于 TS 的 SVG `M/L` 命令序列。

1. 过滤“中间行”遮挡条：`min(cy) + 2 < cy < max(cy) − 2`；
   `blocked(x)` = 任一遮挡条满足 `x1 − 2 ≤ x ≤ x2 + 2`。
2. `gap = fromRect.x1 − toRect.x2 ≥ 8`：在 `[gap/2, +6, −6]` 三个通道里取第一个
   未被遮挡且严格位于两端之间的竖直通道 → 4 点折线。
3. `0 ≤ gap < 8` 且起点未被遮挡 → 直接竖向连接（2 点）。
4. 其余（依赖方在前置左侧、或通道被挡）：绕行到行间空隙
   （`startY ± 18` / `endY ∓ 18`），通道候选为
   `[endX−8, endX−16, startX+8, startX+16, endX−28]` + 每条遮挡条的 `x1−10 / x2+10`，
   取第一个在 `(2, width−2)` 内且未被遮挡者，否则退化到 `max(4, endX−8)` → 6 点折线。

`blockers` 可以传全部可见任务条：与端点同行的条会被第 1 步过滤，等价于 TS 的引用相等判断。

## 11. 输出契约（Canvas 自绘）

```cangjie
Tick{ x, label, kind }            // kind ∈ {Group, Column}；宽度/星期/是否过去从 TimelineHeader 取
BarRect{ x, y, w, h }             // barRect(geometry, rowIndex, milestone:)
RowWindow{ first, last, offsetY } // last 排他；offsetY = first * rowHeight
BarGeometry{ start, end, x, width, days }
TimelineHeader{ groups, columns, width }
Point{ x, y }                     // 依赖折线顶点
```

颜色、字体、圆角、进度填充都不在 logic 里：`areaColor` / `status` 只是透传给渲染层。

## 12. 与 TS 的差异

**语义差异：零**（合法日期键输入下，所有刻度、吸附、几何、窗口、分组结果逐字段一致）。
以下是语言/类型层或**非法输入**处理上的差异，逐条列明：

| 项 | TS | 仓颉 | 影响 |
|---|---|---|---|
| 非法日期键 | `parseISO` 得到 Invalid Date → `format` 抛 `RangeError`，几何得 `NaN` | `Option` 降级：`itemRange` → `None`（条目当作无排期）、`dateToX` → 0、`xToKey` → `origin` | 只有非法输入路径不同；合法输入零差异。新增 `isDateKey` / `looksLikeDateKey` 供调用方前置校验 |
| `today` 默认值 | `new Date()` 默认参数 | **必填参数** | 不读系统时钟（工程硬约束）；少传会编译失败（有意） |
| `Math.round` | 内建 half-up | `tsRound = floor(x + 0.5)` | 逐位一致（含负数、`.5`） |
| `pxPerDay <= 0` | 除零得 `Infinity` → 无效日期 | 返回 `origin` | 配置表保证 `px > 0`，不可达 |
| 超大 `x` | `Math.floor` 结果无界 | 天数夹到 `±2e9` 再格式化 | 超出 0000..9999 年的格式化本就无意义 |
| `total` 未知 | `Number.POSITIVE_INFINITY` | `None` | 类型层差异，语义一致 |
| `sublabel` | `string \| undefined` | `?String` | 一致 |
| `dependencyPath` 返回 | SVG path 字符串 | `Array<Point>` | 同一组顶点；`M/L` 线段数量与顺序一致（含重复点，如相邻行） |
| `itemRange(item)` | 读 `item.gantt?.start/end` | 读 `GanttRow.startDate/endDate` | 见 §3 映射表 |
| `buildRows(ws)` | 从 `Workspace` 取 item 并调 `descendantsOf` / `treeDepth` / `rollupProgress` | 输入 `Array<GanttRow>`，包内自建索引重算 | 结果一致（`rollupProgress` 只覆盖甘特用到的 project/sop 分支）；`level` 仅作外部交叉校验 |
| `localeCompare` | ICU 排序 | `String` 码位序 | ISO 时间戳（ASCII）下等价；非 ASCII `createdAt` 会有差异（业务不产生） |
| 枚举/记录 | 字符串联合 + 接口 | `enum` / `struct`（`@Derive[Equatable]`） | 无语义差异 |
| `Record<GanttZoom, ZoomConfig>` | 对象查表 | `zoomConfig(zoom)` | 无语义差异 |
| `barGeometry` 字段 | `BarGeometry extends BarRange` | 扁平 `BarGeometry{ start, end, ... }` | 无语义差异 |

## 13. 测试与验证

### 13.1 用例（76 个，全绿）

| 文件 | 用例 | 覆盖 |
|---|---|---|
| `scale_test.cj` | 21 | `buildRange`（默认留白 / 覆盖条目 / 跨年）、`dateToX` ↔ `xToKey` 60 天往返、DST 无关、负坐标、`snapKey`（三种缩放 + 幂等）、`resizeBar`（左右边缘 / 小数 / 跨年）、`itemRange`（缺端 / 反向 / 全缺）、`barGeometry`、`moveBar`、`displayProgress`（done 全覆盖 / 四舍五入 / 缺失 NaN / 夹取且不改输入）、`visibleRange`、`formatRangeLabel` |
| `header_test.cj` | 12 | 日/周/月三种列切分与周末/`past` 标记、季度分组、跨年分组与跨年列、闰年 2 月（5 段）与平年（4 段）、闰日星期、三档缩放的 today 线位置、切缩放后 today 线位移、末列截断、刻度压平、列宽求和 = 总宽 |
| `rows_test.cj` | 5 | 分组与组内排序、深度、汇总区间与汇总进度、收件箱/`step` 排除、折叠标记、`UNGROUPED` 计数与次序、`level` 与重算深度一致、父子环保护 |
| `virtual_test.cj` | 16 | `virtual.test.ts` 的 11 条断言 + 0 高/0 宽视口 + 10k 行窗口（顶/中/底/越界 + 跨度上界）+ `rowWindow.offsetY` + 未知总行数 |
| `deps_test.cj` | 11 | 依赖折线 10 个分支（半 gap 通道 / 相邻竖连 / 绕行 / 遮挡条 / 向上 / 宽度约束 / 遮挡条边缘通道 / 退化通道 / 同行忽略）+ `depRect`/`barRect` 契约 |
| `edge_test.cj` | 11 | 儒略日往返（含 1970 前）、日历差（闰年/跨年）、星期、周/月/季边界、非法日期键降级、`tsRound` 半值规则、拖到边界外、0 宽视口、年尾 `buildRange`、`zoomConfig` 与常量 |

`scale.test.ts` 的 21 个 `it`、`virtual.test.ts` 的 11 个 `it` **逐条**对应（断言内容一致），
`buildRows` / `buildHeader` 的 `it` 拆到 `rows_test.cj` / `header_test.cj`。
额外补充（任务要求）：跨年、2 月/闰年、缩放切换后 today 线位置、拖到边界外、0 宽视口、10k 行虚拟化。

### 13.2 如何验证

共享工作树里其它包仍在并行改动，`cjpm build` / `cjpm test` 会被无关包阻断
（实测先后被 `textura.views.okr.logic`、`textura.views.sop.logic`、`textura.views.gtd.logic`、
`textura.ui` 的编译错误挡住；`cjpm` 会编译 `src` 下所有包，与本包无关）。
本包只依赖 `std`，因此用隔离工程与剪枝快照验证：

```bash
# 0) 快照（不要在工作树里跑 cjpm）
rsync -a --delete --exclude target --exclude 'tools/parity/out' \
  /home/ethan/CodeRepo/sandbox/Textura/cangjie/ /tmp/cj-logic-gantt/

# 1) 隔离工程（只含本包；Cangjie 不扫描没有包文件的中间目录，故补两级标记文件）
mkdir -p /tmp/cj-gantt-iso/src/views/gantt/logic
cd /tmp/cj-gantt-iso
printf '[package]\ncjc-version = "1.2.0"\nname = "textura"\nversion = "0.1.0"\noutput-type = "executable"\n' > cjpm.toml
printf 'package textura\n\nmain(): Unit {\n    println("gantt logic iso")\n}\n' > src/main.cj
printf 'package textura.views\n' > src/views/views.cj
printf 'package textura.views.gantt\n' > src/views/gantt/gantt.cj
rsync -a --delete /home/ethan/CodeRepo/sandbox/Textura/cangjie/src/views/gantt/logic/ src/views/gantt/logic/
source /tmp/cj-logic-gantt/scripts/env.sh && cjpm build && cjpm test
```

最近一次结果（工具链 `cjc 1.2.0 (cjnative)`）：`cjpm build success`（无警告），
`cjpm test` → `TOTAL: 76, PASSED: 76, FAILED: 0`。

### 13.3 真实工程布局验证（剪除未就绪的兄弟包）

更强的证据是在**真实 `cjpm.toml`（`name = "textura"`、`-O2`）与真实目录布局**下验证本包。
在 `/tmp` 快照里只移除尚在并行开发的兄弟包（`src/ui`、`src/shell`、`src/core`、
其它 `src/views/<name>`），把 `src/main.cj` 换成最小入口即可：

```bash
cd /tmp/cj-logic-gantt
rm -rf src/ui src/shell src/core src/snapshot.cj \
       src/views/okr src/views/sop src/views/gtd src/views/dashboard \
       src/views/calendar src/views/settings
printf 'package textura.views\n' > src/views/views.cj   # 中间目录包标记
# src/main.cj 换成：调用 buildRange/buildHeader/dateToX 并打印
source scripts/env.sh && cjpm build -i -o textura && ./target/release/bin/textura && cjpm test
```

输出 `2026-06-08..2026-06-29 cols=22 width=880` / `todayX=280`（与 TS 一致），
`cjpm test` → `TOTAL: 76, PASSED: 76, FAILED: 0`。`src/views/gantt/gantt.cj`（父包）与本包
同树共存，无需任何改动。

### 13.4 TS 差分抽样（一次性，不提交）

为了确认日期数学（闰年、月末、季度、跨世纪）与取整规则没有隐性偏差，另用
esbuild 把只读的 `scale.ts` / `virtual.ts` 打成 ESM，JS 生成 800 组随机输入
（1887–2079 年、三档缩放、随机 px / 滚动偏移 / 缓冲 / 总行数），把 TS 结果与仓颉结果
逐字段比对：`weekday`、`diffDays`、日历边界、`buildRange`（90 组）、`buildHeader` 全量签名
（60 组，含每个分组的 key/label/x/width 与每一列的 key/x/width/label/past）、
`dateToX`、`xToKey`、`moveBar`/`resizeBar`（80 组）、`visibleRows`（80 组）、
`visibleColumns`（60 组）——**全部一致**。该用例文件是生成物，只存在于 `/tmp` 隔离工程中，
未提交（仓颉侧的边界由 `edge_test.cj` 覆盖）。

## 14. 未完成 / 后续

- 视图渲染层（`textura.views.gantt` 的 Canvas/CUI 绘制、滚动容器、拖拽手势、依赖命中测试）
  不在本包范围；本包只提供几何与刻度。
- 依赖连线的**箭头绘制 / 高亮样式**（`marker`、`is-hot`、`gantt-dep-joint` 圆点）属于渲染层，
  本包只给折线顶点；调用方用末点与倒数第二点求方向角即可。
- 行虚拟化固定行高；若将来支持可变行高（分组行加高），`visibleRows` 需要新增前缀和版本。
- `buildRows` 每次重建行索引；10k 行规模下是毫秒级，若成为热点可把索引作为参数复用。
