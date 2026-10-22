# SOP 算法层 · `textura.views.sop.logic`

SOP 画布的**纯函数算法层**：DAG 自动布局、画布坐标补丁、初始适配（viewport）、
运行状态机与运行历史。语义与 Web 版 `src/modules/sop/*` 等价，带单元测试。

- 包名：`textura.views.sop.logic`，目录 `cangjie/src/views/sop/logic/`
- 依赖：`std.*` only。**不 import `cui`，不 import `textura.core.data`**
- 无状态、无副作用：不读系统时钟、不取随机数、不依赖 HashMap 迭代顺序
- 相同输入 → 相同坐标（`testLayoutIsStableAcrossRuns` 守护）
- 自动布局**逐模块移植 dagre 1.1.8**，与 `@dagrejs/dagre` 在 39 组 fixture × 2 组参数上
  **逐点一致（Δ=0）**，见 §5

## 1. 文件与职责

| 文件 | 行数 | 对应 Web 版 | 职责 |
|---|---|---|---|
| `model.cj` | 222 | `types.ts` + `core/model.ts` 子集 | `SopNode` / `SopEdge` / `SopPosition` / `SopRunEntry` / 枚举与 id 映射 |
| `layout.cj` | 331 | `layout.ts` | 公共外观：输入清洗、建 dagre 布局图、导出坐标/层号、`hasCycle`、`canvasPositionsToPatch` |
| `dagre_graph.cj` | 464 | graphlib | 插入序有向/无向/复合图（节点/边标签、邻接表、父子关系） |
| `dagre_layout.cj` | 1756 | dagre 布局流水线 | acyclic / nestingGraph / network-simplex / normalize / order / Brandes-Köpf / translate |
| `positions.cj` | 77 | `positions.ts` | 坐标补丁 → `updateItems` 载荷 |
| `fit.cj` | 241 | `fit.ts` | 包围盒、可读初始 viewport、`isWideLayout`、`PREVIEW_LAYOUT` |
| `run.cj` | 353 | `runLogic.ts` + `SopPage.tsx` 运行部分 | 起点/推进/分支/结束、统计、历史条目、会话状态机 |
| `perf.cj` | 142 | `perf.ts` | 运行高亮状态、节点视图数据、结构等价、状态差异集合 |
| `clock.cj` | 238 | `Date` / `nowIso` / `formatDateTime` | ISO 解析与格式化、Asia/Shanghai 展示、注入时钟的耗时计算 |

## 2. 记录与 Web 版字段映射

| Web 版 | 本包 | 说明 |
|---|---|---|
| `Item.id` | `SopNode.id` | 节点 id（= step 条目 id） |
| `Item.title` | `SopNode.title` | 节点标题 |
| `Item.sop.nodeType`（`'start'\|'action'\|'decision'\|'check'\|'end'\|'note'`） | `SopNode.nodeType: SopNodeType` | 枚举 + `nodeTypeId()` / `parseNodeType()` 双向映射 |
| `Item.sop.canvas.{x,y}` | `SopNode.canvasX` / `canvasY` | 节点左上角坐标 |
| `Item.sop.checklist[]` | `SopNode.checklist: Array<ChecklistEntry>` | `{id,text,done}` |
| `Item.sop.owner?` | `SopNode.owner: String` | 缺省 `""` |
| `Item.sop.durationMin?` | `SopNode.durationMin: ?Int64` | `null` → `None` |
| `Edge.{from,to,label}`（`type==='flow'`） | `SopEdge.{from,to,label}` | |
| `Edge.id` | `SopEdge.id`（可选） | 留空时 `edgeId()` 退化为 `from->to`；需要与 Web 版边 id 逐字一致时显式传入 |
| `SopRunEntry.{id,sopId,stepId,at,result,note}` | `SopRunEntry` 同名字段 | `result` 为 `RunResult` 枚举，`runResultId()` → `'pass'\|'fail'\|'skip'` |
| `RunSession.{currentId,visited,failed,startedAt,results}` | `RunSession` 同名字段 | 结构化值类型 |
| `Record<string,{x,y}>`（画布坐标表） | `HashMap<String, SopPosition>` | 只用于查表，不参与迭代输出 |

## 3. 公共 API

### 3.1 布局（`layout.cj`）

```cangjie
public let SOP_NODE_WIDTH = 200.0
public let SOP_NODE_HEIGHT = 60.0
public let SOP_NODE_SEP = 60.0        // dagre nodesep 默认
public let SOP_RANK_SEP = 90.0        // dagre ranksep 默认
public let SOP_LAYOUT_MARGIN = 24.0   // dagre marginx/marginy 默认

public struct LayoutOptions {         // 全部有默认值
    rankdir!: RankDir = TopDown       // TopDown | LeftRight
    nodeWidth! / nodeHeight! / nodesep! / ranksep! / margin!
}

layoutPositions(nodes: Array<SopNode>, edges: Array<SopEdge>, options!): HashMap<String, SopPosition>
layoutIds(ids: Array<String>, edges: Array<SopEdge>, options!): HashMap<String, SopPosition>
layoutRanks(nodes, edges, options!): Array<RankedNode>   // 按 (rank, order) 排序，供连线绘制
hasCycle(nodes, edges): Bool                             // 含自环；布局本身会反向回边
canvasPositionsToPatch(positions: Array<CanvasPosition>, current!: ?HashMap<String, SopPosition>): Array<CanvasPosition>
```

### 3.2 坐标补丁（`positions.cj`）

```cangjie
positionsToPatch(nodes: Array<CanvasPosition>, current!): Array<CanvasPosition>
canvasPatchesToUpdateItems(patches): Array<CanvasPatchUpdate>   // { id, patch.sop.canvas }
```

### 3.3 适配（`fit.cj`）

```cangjie
INITIAL_FIT_PADDING = 0.16, READABLE_MIN_ZOOM = 0.7, MAX_FIT_ZOOM = 1.0,
MIN_ZOOM = 0.25, FIT_MARGIN = 16.0, FIT_NODE_HEIGHT = 64.0
PREVIEW_LAYOUT = LayoutOptions(nodesep: 44, ranksep: 60, margin: 0)

boundsOfPositions(positions: HashMap<String,SopPosition>, nodeWidth!, nodeHeight!): ?FitBounds
boundsOfNodes(nodes: Array<SopNode>, nodeWidth!, nodeHeight!): ?FitBounds
computeReadableViewport(options: ReadableFitOptions): ReadableViewport
isWideLayout(bounds: ?FitBounds): Bool
```

### 3.4 运行（`run.cj`）

```cangjie
nextCandidates(stepId, edges): Array<SopEdge>
startStepId(steps, edges): ?String
advance(stepId, edges, choice!: ?String, visited!: Array<String>): AdvanceResult   // Next | Branch | End
summarizeResults(results): RunStats
elapsedMinutes(startIso, endIso): Int64
elapsedMinutesBetween(startMillis, endMillis): Int64

startSession(steps, edges, nowIso): ?RunSession
recordResult(session, edges, result, sopId, nowIso, note!, entryIdSequence!): RunOutcome
moveTo(session, stepId): RunSession
chooseBranch(options, choice): ?BranchOption
makeRunEntry(sopId, stepId, atIso, result, note!, idSequence!): SopRunEntry
isStaleSession(session, steps): Bool
runEndMessage(stats, elapsedMin): String
```

### 3.5 渲染辅助（`perf.cj`）

```cangjie
nodeStateFor(id, run: ?CanvasRunState): SopNodeState      // current > failed > visited > idle
sopNodeData(node, areaColor: ?String, run: ?CanvasRunState): SopNodeData
sameNodeData(left, right): Bool
nodeStateDiffs(nodes, before: ?CanvasRunState, after: ?CanvasRunState): Array<String>
```

### 3.6 时钟（`clock.cj`）

```cangjie
parseIsoMillis(iso): ?Int64                 // YYYY-MM-DDTHH:MM:SS[.fff][Z|±HH:MM|±HHMM]
isoFromMillis(millis): String               // 等价 new Date(ms).toISOString()
formatShanghaiDateTime(millis): String      // Asia/Shanghai（固定 UTC+8），yyyy-MM-dd HH:mm
formatShanghaiDateTimeIso(iso): String      // 非法输入 → "—"（与 formatDateTime 一致）
```

## 4. 自动布局算法

Web 版把节点/边交给 `@dagrejs/dagre` 1.1.8（`rankdir=TB`、`nodesep=60`、`ranksep=90`、
`marginx=marginy=24`，默认 `ranker=network-simplex` + barycenter 排序 + Brandes-Köpf 定位）。
仓颉侧**逐模块移植**了同一条流水线，而不是近似：

| 阶段 | 仓颉实现 | 说明 |
|---|---|---|
| 输入清洗 | `layout.cj: buildLayoutGraph` | 空/重复 id 丢弃（保留首次出现）；未知端点、自环、重复 `(from,to)` 丢弃（与 `layout.ts` 一致） |
| 边标签占位 | `makeSpaceForEdgeLabels` | `ranksep /= 2`、每条边 `minlen *= 2`、TB 下 `width += labeloffset(10)` |
| 去环 | `dgAcyclicRun` / `dgDfsFas` | DFS 回边反向（dagre `dfsFAS`），反向边带 `reversed` 标记 |
| 连接图 | `dgNestingRun` | 补 `_root` 哑节点连接所有节点（`nodeRankFactor = 1`），避免多分量打分退化 |
| 分层 | `dgNetworkSimplex` | simplify（合并平行边）→ longestPath 初值 → feasibleTree → low/lim → cut value → 换边迭代（与 dagre 完全相同的算法与 tie-break） |
| 去空层 | `dgRemoveEmptyRanks` / `dgNormalizeRanks` | `nodeRankFactor = 1` 时空层保留（这正是层间距为 `height + ranksep` 的原因） |
| 跨层边 | `dgNormalizeRun` | 每条长边插入 `width/height = 0` 的 **dummy 节点链**，`dummyChains` 记录链首 |
| 同层排序 | `dgOrderRun` | `initOrder`（DFS）→ 每层建**层图**（复合图，节点标签与主图共享）→ barycenter + resolveConflicts + sort → 4 轮上下扫描并用交叉计数择优（`lastBest < 4` 与 dagre 一致） |
| 坐标 | `dgPositionRun` | `positionY`（层高 + `ranksep`）+ **Brandes-Köpf**：type-1 冲突、verticalAlignment（median 对齐 + `prevIdx`/`align` 规则）、horizontalCompaction（块图两次扫描）、四种对齐（ul/ur/dl/dr）取最窄、`balance` 取中间两值均值 |
| 收尾 | `dgRemoveDummyNodes` / `dgCoordinateUndo` / `dgTranslateGraph` | 移除 dummy（不影响包围盒）→ LR 交换回 x/y → 平移使最小坐标 = `margin`（对应 dagre `translateGraph`） |

关键细节（与 dagre 逐条对齐，缺一不可）：

- **插入序语义**：`nodes()` / `edges()` / `inEdges()` / `outEdges()` / `predecessors()` 的顺序
  决定 network-simplex 与 barycenter 的平局结果，因此 `dagre_graph.cj` 用「有序数组 + 索引」
  而不是 `HashMap` 直接迭代（仓颉 `HashMap` 无序）。
- **节点标签共享**：层图/简化图与主图共享同一批 `DgNode` 对象，`order` 的写入才能双向可见
  （对应 dagre `setDefaultNodeLabel(v => g.node(v))`）；层图只按需创建「本层节点 + 相邻层邻居」。
- **dummy 参与分层、排序与定位**：宽度 0，间距用 `edgesep`（默认 20）而非 `nodesep`。
- **取整**：`floor(v + 0.5)`（= JS `Math.round`，`.5` 向 +∞），不用 `std.math.round`
  （远离零取整，负数半边不同）。
- **层号**：dagre 内部因 `minlen` 翻倍而使用 0,2,4…；对外 `layoutRanks().rank` 压缩为 0,1,2…，
  `order` 为层内次序。

## 5. 与 dagre 的对照（实测）

对照方法：同一组 fixture 分别用 dagre（`@dagrejs/dagre` 1.1.8，本仓 `node_modules`）与本包
`layoutIds` 计算，比较每个节点左上角坐标（`round(center - size/2)`）：

- 参数组 A：`rankdir=TB`、`nodesep=60`、`ranksep=90`、`margin=24`（`LayoutOptions()` 默认）
- 参数组 B：`PREVIEW_LAYOUT`（`nodesep=44`、`ranksep=60`、`margin=0`）

### 5.1 结论

| 指标 | 修复前（旧近似实现） | 修复后（本版本） |
|---|---|---|
| 39 组 fixture × 2 参数组的逐点一致率 | 11/14 结构化 fixture 一致；24 组随机 DAG 中 23 组不一致 | **78/78 全一致（Δ=0）** |
| parity fixture（8 节点，PREVIEW_LAYOUT）最大 \|Δx\| | 122 | **0** |
| 随机 DAG（4–8 节点）最大 \|Δx\| / \|Δy\| | 620 / 300（部分图连分层都不同） | **0 / 0** |
| 残留差异 | — | **0（无残留）** |

### 5.2 parity fixture（真实 SOP 画布）

图：`cangjie/tools/parity/workspace.json` 的 `sop_onboarding`（7 个 step + 7 条 flow 边，
含回边 `step_remind → step_collect`）。评审所用的 8 节点版本 = 在节点集首位再放一个孤立节点
（无出/入边），用于验证「多分量 + 回边」组合。

`PREVIEW_LAYOUT`（dagre 与本实现相同）：

| 节点 | dagre | 本实现 |
|---|---|---|
| `step_extra`（孤立） | 0,0 | 0,0 |
| `step_start` | 244,0 | 244,0 |
| `step_welcome` | 244,120 | 244,120 |
| `step_collect` | 244,240 | 244,240 |
| `step_decision` | 132,360 | 132,360 |
| `step_check` | 122,480 | 122,480 |
| `step_remind` | 366,480 | 366,480 |
| `step_end` | 122,600 | 122,600 |

默认参数下同一张图为：`step_extra=24,24 step_start=284,24 step_welcome=284,174
step_collect=284,324 step_decision=164,474 step_check=154,624 step_remind=414,624
step_end=154,774`（两侧一致）。

### 5.3 随机 DAG（4–8 节点，24 组）

生成方式：`random.seed(20240917)`；每组随机排列 `n0..n{n-1}` 后以 0.34 概率连「前 → 后」的边，
保证无环。全部 24 组在两组参数下逐点一致。抽样：

| fixture | 边数 | dagre / 本实现（默认参数） |
|---|---|---|
| `rand00` | 2 | `n0=24,174 n1=24,24 n2=284,174 n3=284,24` |
| `rand05` | 3 | `n0=24,24 n1=284,24 n2=544,24 n3=804,24` |
| `rand23` | 7 | `n0=94,624 n1=404,474 n2=404,324 n3=414,174 n4=24,24 n5=404,24 n6=154,174` |

### 5.4 结构化图形（13 组）

`single` / `chain4` / `diamond` / `fanOut3` / `fanOut5` / `forest` / `sharedChild` /
`skipEdge`（跳层边）/ `cycle2` / `cycle3` / `cycleWithTail` / `longChain10` / `chain3`，
外加 `rankdir=LR`（`a=24,24 b=314,24 c=604,24`）——全部逐点一致，包括此前不一致的三类：

- `skipEdge`：dagre 把 `b` 下沉一层（`b=24,324`）并让 `d=284,324`——本实现一致（network-simplex 生效）；
- `cycle3` / `cycleWithTail`：回边反向后的跨层边插入 dummy，`a/c` 的 x=94——本实现一致（BK 生效）。

> 回归锁定：`layout_dagre_test.cj` 里 80 条 `assertDagreLayout`（39 组 fixture × 2 参数组 +
> LR + parity），期望值由真实 dagre 生成后写死；任一处坐标漂移都会直接报错并打印 fixture 名。
> 复现脚本（不在仓库内，仅用于生成期望值）：
> `node -e "…dagre.layout(graph)…"`，参数与 §5 完全一致。

## 6. 运行状态机

`RunResult = Pass | Fail | Skip`，`SopRunEntry` 逐条落历史。状态迁移与 Web 版一致：

| 当前状态 | 事件 | 结果 |
|---|---|---|
| 无会话 | `startSession` 且存在起点 | 会话：`currentId=起点`、`visited=[起点]`、`failed=[]`、`results=[]`、`startedAt=注入的 now` |
| 无会话 | `startSession` 且画布为空 | `None`（视图提示「先添加一个开始节点」） |
| 任意 | `recordResult(result)` | 先写 `entry`（`id, sopId, stepId, at, result, note`），`results += result`；`result==Fail` 时 `failed += currentId` |
| 当前步骤 0 条出边 | `recordResult` | `RunOutcome.Finished(session, entry, stats, elapsedMin)` → 结束运行 |
| 1 条出边 | `recordResult` | `RunOutcome.Advanced(...)` → `moveTo(to)`，`visited` 去重追加 |
| ≥2 条出边，未选 | `recordResult` | `RunOutcome.Branching(options)`：`options` 按「未访问优先」稳定排序，label 缺省 `""` |
| ≥2 条出边，`chooseBranch` 命中 | `chooseBranch` + `moveTo` | 进入选中目标；不追加 `results` |
| ≥2 条出边，`chooseBranch` 未命中 | `chooseBranch` → `None` | 保持分支面板（Web 版 `setBranch(null)` 前不会前进） |
| 运行中 | `isStaleSession` | 当前步骤被删除 → `true`，视图安全退出 |

补充语义（与 Web 版逐条一致）：

- **可重复 pass**：`visited` 是去重集合，回边可以再次经过同一步骤；`results` 每次追加。
- **fail 不阻断**：`fail` 与 `pass`/`skip` 一样沿出边前进，失败只进 `failed` 与历史。
- **failed 可重复**：同一步骤多次失败会在 `failed` 里出现多次（Web 版数组语义）。
- **完成时间**：`elapsedMinutesBetween(startedAt, now)`，`Math.round` 到分钟、负数截 0；
  `now` 由调用方注入，不读系统时钟。
- **历史 id**：`makeRunEntry(..., idSequence)` → `run_<seq>`（Web 版是 `run_<random10>`；
  这里改为调用方给序号，保证 parity 可重复；需要兼容旧数据时直接构造 `SopRunEntry`）。
- **提示文案**：`runEndMessage(stats, elapsedMin)` 与 Web 版 `finishRun` 逐字一致：
  `流程结束：通过 {pass} / 未通过 {fail} / 跳过 {skip}，耗时 {min} 分钟`。

## 7. 时钟与时区

- 所有 API 都用**调用方注入**的 `now`（ISO 字符串或 epoch 毫秒），与 `docs/STRUCTURE.md`
  「不读系统时钟」一致；parity 的「今天」仍由 `workspace.json` / `--today` 提供。
- `parseIsoMillis` 支持 `Z`、`±HH:MM`、`±HHMM` 与缺省毫秒；非法输入 `None`（对应 `Number.isNaN`）。
  无时区后缀的字符串按 UTC 解释（Web 版按浏览器本地时区，宿主为 Asia/Shanghai 时二者相差 8 小时；
  parity 一律使用带 `Z` 的 ISO，故不触发该分支）。
- 展示固定 `Asia/Shanghai`（1991 年后无夏令时，按 UTC+8 计算，无需 tzdata）。

## 8. 测试

共 **64** 个用例（`cjpm test`，布局相关 17 个），断言逐条移植自 Web 版四个测试文件，并补充边界：

| 文件 | 用例 | 覆盖 |
|---|---|---|
| `layout_dagre_test.cj` | 4（80 条坐标断言） | dagre 逐点回归：parity7 / parity8（含孤立节点与回边）+ 24 组随机 DAG + 13 组结构化图形，每组在默认参数与 `PREVIEW_LAYOUT` 下各断言一次，外加 `rankdir=LR` |
| `layout_test.cj` | 13 | `layout.test.ts` 全部 4 条 + 稳定性 + 压缩层号 + 环检测 + 50 节点长链 + 120 节点规模回归 + 空/重复 id + `canvasPositionsToPatch` + `jsRound` |
| `fit_test.cj` | 10 | `fit.test.ts` 全部 5 条 + 包围盒 + `isWideLayout` + `PREVIEW_LAYOUT`/`FIT_NODE_HEIGHT` 常量 |
| `positions_test.cj` | 5 | `positions.test.ts` 全部 5 条 |
| `run_test.cj` | 21 | `runLogic.test.ts` 全部 12 条 + 会话状态机（起点、历史条目、可重复 pass、分支、fail 继续、结束统计、stale） |
| `perf_test.cj` | 5 | `nodeStateFor` 优先级、状态差异集合、`sopNodeData`、`sameNodeData`、检查项计数 |
| `clock_test.cj` | 6 | ISO 解析/往返、时区偏移、Asia/Shanghai 展示、注入时钟耗时四舍五入 |

补充边界（题目要求）：空图、单节点、菱形分叉、环（检测 + 反向布局）、50/120 节点长图、
fit 到 0 尺寸（container/bounds 都为 0 仍返回有限 viewport）、空/重复 id、
`Math.round` 负数半边。

布局性能（宿主 `cjc 1.2.0`，单次 `layoutIds`）：

| 规模 | 边数 | 耗时 | 峰值 RSS |
|---|---|---|---|
| 50 节点链 | 49 | < 10 ms | ~20 MB |
| 120 节点（每节点 ≤2 条边、含跳层边） | ~160 | ~0.15 s | ~45 MB |
| 300 节点（同上模式） | ~400 | ~0.5 s | ~105 MB |

（旧实现曾在 200 节点上 OOM：层图每层复制全图节点；现改为按需创建邻居节点 + 共享标签。）

验证命令（不要在共享工作树跑 `cjpm`，用快照）：

```bash
rsync -a --delete --exclude target --exclude 'tools/parity/out' \
  /home/ethan/CodeRepo/sandbox/Textura/cangjie/ /tmp/cj-logic-sop/
cd /tmp/cj-logic-sop && source scripts/env.sh && cjpm build -i -o textura && cjpm test
```

**当前状态**：整模块 `cjpm build` / `cjpm test` 仍被 `textura.ui` 的既有编译错误阻断
（`src/ui/controls_*.cj`、`theme.cj`，其它 worker 正在改；本包不 import `cui`/`textura.ui`，
报错文件全部落在 `src/ui/`）。因此本包用「快照目录 + 隔离最小工程」验证（快照内容与仓库一致）：

```bash
# 只保留 textura / textura.views / textura.views.sop 三个包标记 + 本包
# /tmp/cj-logic-sop-iso/cjpm.toml: name = "textura", output-type = "static"
rsync -a /tmp/cj-logic-sop/src/views/sop/logic/ /tmp/cj-logic-sop-iso/src/views/sop/logic/
cd /tmp/cj-logic-sop-iso && source /tmp/cj-logic-sop/scripts/env.sh && cjpm test
# Summary: TOTAL: 64 | PASSED: 64, ERROR: 0, FAILED: 0
```

## 9. 未完成 / 后续

- **坐标已与 dagre 逐点一致（残留 Δ=0）**，不再有需要「调参逼近」的已知偏差；布局 worker
  直接使用本包坐标即可（`PREVIEW_LAYOUT` 与默认参数都与 dagre 相同）。
- **边路由（折线/箭头交点）不在本包**：只输出节点左上角坐标与 `layoutRanks` 的分层/次序信息。
  dagre 的 `normalize.undo` 产出的折线点、`assignNodeIntersects` 的矩形交点仍由画布 worker 负责
  （本包在收尾阶段已移除 dummy，不保留折线）。
- **未移植的 dagre 分支**（本仓数据不可达，故不移植，行为上等价于 dagre 的对应分支被裁掉）：
  `compound` 子图（`parentDummyChains` 的实际分组、`borderTop/Bottom`、`addBorderSegments`）、
  自环 `selfEdges`（Web 版在 `layout.ts` 里已过滤）、边标签代理 `edge-label`（Web 版
  `setDefaultEdgeLabel(() => ({}))`，边宽高恒为 0）、`rankdir=BT/RL`（Web 版只用 TB/LR）、
  `acyclicer="greedy"`、`ranker="tight-tree"|"longest-path"`、`align` 指定对齐方向。
  若后续需要这些能力，可按字段在 `dagre_layout.cj` 内补齐，接口已经留好。
- `perf.ts` 的**对象引用复用**在值语义下没有对应物，改为 `nodeStateDiffs`（只报状态变化的 id）；
  若画布需要「节点数据缓存」，按 `sameNodeData` + 该 id 列表实现即可。
- `SopEdge.id` 可选：不与 Web 版边 id 对齐时 `viaEdgeId` 形如 `from->to`。
