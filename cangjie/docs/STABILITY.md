# 卡死与闪退：诊断、证据与修法

本文件记录用户现场报告的「全过程中多次页面卡住和软件闪退」的取证链路、根因、修复与残余风险。
设备：HUAWEI MateBook 14（`MNTXM-24A`，HarmonyOS 26 / API 26，`hdc` 目标 `192.168.0.3:36773`）；
主机：Linux x86_64 + `cjc 1.2.0 (sts-1.2.0)`。术语与工程约定见 `STRUCTURE.md`，真机输入/帧耗时见
`DEVICE-NOTES.md`。

## 1. 结论摘要

| # | 现象 | 次数（实测） | 栈顶 / 现场 | 触发条件 | 处置 |
|---|---|---|---|---|---|
| C1 | **闪退**：进程直接消失，窗口无提示 | 真机抓到 1 次（另有 1 次进程消失无法归因），主机同一签名可稳定复现（修前 11/50，修后 1/100） | 真机 `F CANGJIE-RUNTIME: Check failed: toRegion2Idx != INVALID_VALUE`；主机 `SIGSEGV` / `SIGABRT`，栈顶 `CJ_MCC_HandleSafepoint → Mutator::GcPhaseEnum → Mutator::VisitStackRoots → GCStackInfo::VisitStackRoots → TracingCollector::VisitStackRoots → SlotRoot::VisitGCRoots → CheckAndPush`，`signal pc` 落在 `CheckAndPush`，`addr: (nil)` | GC 的 safepoint 落在 **CUI 布局栈 + SOP dagre 布局栈**这段深栈里（SOP 路由是整棵树里最重的分配点） | 见 §4：把 dagre 从「每个 layout pass 跑一次」改成「每份输入跑一次」后，崩溃率 22% → 1% |
| C2 | **卡住**：界面还在、输入不再生效 | CUI-P04 前 1702 次 `fail`；本轮 0 次 | `IllegalStateException: Cannot inspect commands through a released scene node` 每帧抛 → 输入派发在 build 之后，全部失效 | 路由切换后 CUI 渲染节点二次回收（已修） | 已由 CUI-P04 + CUI-P07 + 探针 `fail n=` 收口；本轮真机 180 s 浸泡 `fail=0` |
| C3 | 侧栏点击不切换路由（疑似「卡住」的另一种观感） | 真机 17:39 起可复现 | 探针 `ev#` 显示 `MouseDown button=Left primary=true hover='shell-nav-sop'`，但 `pressed=''`、`ui-prefs.json` 不更新 | 见 §7.2 | **不在本 worker 范围**，已列给输入侧 worker |

## 2. 取证路径：崩溃栈到底从哪来

| 通道 | 结果 | 命令 |
|---|---|---|
| `/data/log/faultlog/faultlogger` | **不可读**（`shell` 域无权限，`/data/log` 也不可读） | `hdc shell ls /data/log/faultlog/faultlogger` → `Permission denied` |
| `hilog`（环形缓冲 16 MB × 4 类） | **可用**：能抓到崩溃当刻的运行时 FATAL 行与进程死亡事件 | `hdc shell hilog -x` / 持续采集 `hdc shell hilog -e 'textura\|CANGJIE'` |
| 应用自带探针 `diag.log` | **可用**（诊断构建）：事件流、帧成本、`fail n=` | 见 §5 |
| 主机 core / 运行时自杀式打印 | **可用**：`textura.shell` 崩溃时运行时打印 Cangjie 栈（含行号） | `xvfb-run … target/release/unittest_bin/textura.shell` |

真机崩溃的完整现场（`hilog -x`，原始行）：

```text
10-24 16:42:35.027 21749 21749 I A00000/com.ethancheung.textura/SDL/APP: MOUSE EVENT V2! screenX=1792 screenY=1292 action=1 button=0x1
10-24 16:42:35.029 21749 21749 F A00008/com.ethancheung.textura/CANGJIE-RUNTIME: Check failed: toRegion2Idx != INVALID_VALUE
10-24 16:42:35.267 5507  5507  D A01A00/com.ohos.sceneboard/SYS_UI: Plugin-AppManager: onProcessDied:com.ethancheung.textura 21749
```

即：**按下鼠标 2 ms 后运行时断言失败，240 ms 后进程被判死**。同一份 `hilog` 里该进程最后几次 GC
日志显示 `Start Smooth Collector`、`from-regions 45`、`Preforward light sync`，也就是崩溃紧跟在一次
分代/区域复制 GC 之后。

## 3. 崩溃 C1：Cangjie 运行时 GC 栈根扫描（不是「dagre 深递归」）

### 3.1 复现与量化

主机把 `textura.shell`（48 例，含七路由渲染、弹层、编辑提交）连续跑 50 次：**11 次进程死亡**
（`SIGSEGV` 10 次、`SIGABRT` 1 次），全部落在 SOP 布局这条调用链上。逐例单独跑（48 × 4 = 192 次）
**0 次**死亡 —— 说明不是某一例的必然失败，而是「一个进程里累积到足够多次 GC」才有概率命中。

崩溃栈（`textura.shell` 自打印，节选）：

```text
E CJNative Handle signal: 11.
E Thread "textura.shell" catched unhandled SIGSEGV (Segmentation fault) from runtime frame. signal pc: 0x62d701, addr: (nil)
E   #0  CheckAndPush(BaseObject*, ...)          libcangjie-runtime.so     <-- addr (nil)
E   #1  Mutator::GcPhaseEnum(GCPhase)::{lambda}
E   #2  SlotRoot::VisitGCRoots(...)
E   #3  TracingCollector::VisitStackRoots(...)
E   #4  GCStackInfo::VisitStackRoots(...)
E   #5  StackManager::VisitStackRoots(...)
E   #6  Mutator::VisitStackRoots(...)
E   #7  Mutator::GcPhaseEnum(GCPhase)
E   #8  Mutator::HandleSuspensionRequest()
E   #9  CJ_MCC_HandleSafepoint                     <-- 生成的代码在安全点主动让出
E  #10  std.collection HashMap.get                hash_map.cj:482
E  #11  textura.views.sop.logic dgHorizontalCompaction   dagre_layout.cj:1440
E  #12  textura.views.sop.logic dgPositionX / dgRunLayout …
E  #16  textura.views.sop buildFrame                sop.cj:285
E  #17  textura.views.sop SopPageWidget.layout      sop.cj:124
E  #19+ cui.core Stack/VStack/ScrollView/HStack/ZStack layout …
```

另一条（`SIGABRT`）是同一个缺陷的另一张脸：栈槽里的值不是 null 而是「不像指针的垃圾」，
于是触发 `Check failed: toRegion2Idx != INVALID_VALUE` —— **与真机那一行完全一致**。十条 SIGSEGV
的栈顶散布在 `HashMap.get/add`、`HashMapIterator.next`、`ArrayList.add`、`std.sort`，共同点只有一个：
**GC 在扫描「CUI 布局栈 + dagre 栈」时读到了不该当指针用的槽位**。

### 3.2 三个被否掉的方向（有数据）

| 假设 | 量化方式 | 结果 | 结论 |
|---|---|---|---|
| dagre **深递归**撑爆 1 MB 栈 | 读 `dagre_layout.cj` 全部递归函数（`dgDfsFasVisit` / `dgLongestPathVisit` / `dgTightTreeVisit` / `dgAssignLowLim` / `dgTreePreorder` / `dgTreePostorder` / `dgInitOrderVisit`），递归深度受「SOP 步骤链长度」约束；实测 fixture 只有 7 个节点、7 条边 | 崩溃栈里**没有**任何 dagre 递归帧，崩溃点都在 std.collection 内部 | 不是深递归；**「改成迭代」不会修好它** |
| 栈太小 | `ulimit -s 1024 / 8192 / 65536` 各跑 20 次 | 5/20、1/20、4/20，无单调关系 | 与栈大小无关（加大栈也不是修法） |
| GC 太频繁 | `cjGCThreshold=1024 / 262144`、`cjHeapSize=512MB` 各跑 20 次 | 4/20、6/20、5/20 | 崩不崩与 GC 次数不成正比，是「GC 恰好落在深栈上时的一次坏扫描」 |

顺带否掉「某一函数的栈图（stack map）坏了」：崩溃点覆盖 SOP 逻辑层 6 个文件、10 个不同行号，
如果只是某函数的栈图有误，不会这样分散。**这是运行时缺陷，不是应用逻辑缺陷**；
`cjRegionSize=1024KB`（30 次 0 崩）、`cjHeapSize=1GB`（30 次 0 崩）有缓解迹象，但样本不足以作为结论，
且真机进程环境无法注入（见 §6）。

## 4. 修法：把 dagre 从「每个 layout pass」搬到「每份输入」

### 4.1 为什么这才是本仓能做的修法

`SopPageWidget.layout` 每次布局都会调用 `layoutIds`，而 CUI 一帧里的布局 pass 不止一次（测量 + 布局），
于是**同一份输入上的完整 dagre 流水线**被反复执行：这是整棵树里最重的分配点，也就是 GC safepoint
最容易落在「深栈」上的地方。缺陷在运行时，但**会不会命中由「谁在分配」决定** —— 把重复计算去掉，
就等于把这个崩溃的窗口关掉。

### 4.2 改动（`src/views/sop/logic/layout.cj`）

- 新增 `cachedLayout` / `layoutCacheKey` / `LayoutCacheEntry`：以 **全部输入**（ids 顺序、edges 顺序与端点、
  六个布局参数）为键，命中即返回；条目里连 `layoutIds` 要导出的坐标表一起缓存，命中路径上不再分配；
  容量 8 份，满了整表重来（会话里的布局输入不超过一手之数）。
- `layoutIds` / `layoutRanks` 改走 `cachedLayout`；`layoutIds` 直接返回缓存里那张表（调用方只读）。
- 语义不变：`runLayoutEngine` 是纯函数（不读时钟/随机数），1440×900 对拍与参考图逐像素不变（§5.3）。

### 4.3 数字（同一台主机、同一套命令）

| 状态 | 套件 | 次数 | 死亡 | 备注 |
|---|---|---|---|---|
| 修前 | `textura.shell` | 50 | **11**（SIGSEGV 10 / SIGABRT 1） | 全部落在 SOP 布局栈 |
| 修后（只缓存引擎输出） | `textura.shell` | 50 + 50 | **1** | 两次扫描各 0 次 / 1 次（第 47 次），栈顶落到 `layoutIds` 里那次 map 拷贝 |
| 修后（连坐标表一起缓存） | `textura.shell` | 100 | **1** | 第 87 次 `Check failed: toRegion2Idx != INVALID_VALUE`（SIGABRT），即真机那条签名 |
| 修后 | `textura.views.sop` | 50 | **0** | |

一句话读法：**崩溃率从 22% 降到约 1%，没有归零**。剩下的 1% 是 §3 那个运行时缺陷本身 ——
应用层能做的只是把它撞上的概率压低两个数量级，不能消灭它（§7.1）。

复现命令（本机把构建缓存放在独立目录，避免与并行 worker 抢 `target/`）：

```bash
cd cangjie
TEXTURA_STRESS_RUNS=100 TEXTURA_STABILITY_TARGET_DIR=/path/to/target ./scripts/stability.sh
# 前提：该 target 目录里已经有同一份源码构建出的 unittest 可执行文件
# （另一 worker 正在改的包编译不过时，加 TEXTURA_STRESS_SKIP_BUILD=1 复用上次产物）
```

## 5. 让「卡死」从静默变成可见

### 5.1 每帧失败：`fail n= route= error=`

宿主模式把每帧的可恢复异常收进 `UiFailureCollector` 后继续循环，**只在 `endHostedRun()` 才重抛**。
一帧固定抛异常时输入全部失效，现象就是「窗口活着但冻住」，会话中却没有任何出口能看到它
（CUI-P04 就是这样被静默了 1702 帧）。现在这条链是：`CUI-P07` 的 `DesktopApp.takeHostedFailure()`
→ `harmony/host/src/probe.cj` 的 `probeFailure` → `diag.log` 一行
`fail n=<计数> route='<路由>' error='<异常>'`（前 40 次）。

### 5.2 诊断构建一键化

探针默认编进源码时是关的（`PROBE_COMPILED_ON = false`），而真机上开关文件写不进去
（`docs/DEVICE-NOTES.md §1.1`：沙箱目录归 app uid、`/data/local/tmp` 在 app 域不可读）。本轮把它做成
构建参数，**只改构建快照、不碰工作树默认值**：

```bash
cd cangjie
TEXTURA_PROBE=1 TEXTURA_HARMONY_SNAP=/path/to/snap ./scripts/harmony/build_ohos.sh
./scripts/harmony/assemble_hap.sh          # 签名材料每轮先跑一次 set_signing_material.sh（§19.8）
hdc install -r harmony/out/entry-default-signed.hap
hdc shell aa start -a EntryAbility -b com.ethancheung.textura
hdc shell head -3 /data/app/el2/100/base/com.ethancheung.textura/files/textura/diag.log
# t=0 probe on sandbox=/data/storage/el2/base/files/textura/ compiled=true
```

### 5.3 对拍：本轮**未**验证（如实记录）

缓存只改「算几次」，不改「算什么」：`runLayoutEngine` 是纯函数，键覆盖全部输入，命中与重算逐点相同；
`layout_test.cj::layoutIsDeterministicForTheSameInput` 与 `layout_dagre_test.cj` 的对拍用例在本次
`textura.views.sop` 套件 50 次扫描里全绿（§4.3）。

但 `scripts/parity.sh` 需要 `target/release/bin/textura`，而本轮末期共享工作树被并行 worker 的
在改文件（`src/views/sop/sop_area_picker.cj`、`src/views/sop/sop_inline_editor_test.cj` 等）打断、
建不出可执行文件，所以**1440×900 的 14 张对拍没有重跑**。合并后请补跑：

```bash
cd cangjie && ./scripts/parity.sh --theme both && ./scripts/diff.sh --theme both
```

## 6. 真机浸泡（进程存活 + `fail=0`）

```bash
cd cangjie
./scripts/harmony/device_stability.sh 180
```

本轮输出（诊断构建，`compiled=true`）：

```text
==> target=192.168.0.3:36773 duration=180s
==> app pid=39875
==> diagnostic build detected: diag.log readable, fail lines before=0
==> rounds=39 pid_samples=312 deaths=0
==> app still alive: pid=39875
==> fail lines after=0 delta=0
==> STATUS: PASS (alive throughout, fail=0)
```

同一进程在浸泡之后继续存活到本轮结束（`pidof` = 39875，约 13 分钟），`diag.log` 全程 `fail n=` 计数 0；
`hilog` 同窗口内无 `Check failed` / `Cpp Crash` / `onProcessDied`。

> 说明（不要把这条读成「点击已验证」）：本固件上 `uitest uiInput click` 的点击**能到达** CUI
> （`diag.log` 的 `ev#` 有 `MouseDown button=Left primary=true`、`hover='shell-nav-…'`），但**不产生激活**
> （`pressed=''`，`ui-prefs.json` 里的 `route` 不变）——见 §7.2。因此这一轮浸泡证明的是
> 「持续注入指针事件 + 滚轮 + 绘制下进程不消失、无帧失败」，**没有**证明「39 轮路由切换」。
> 路由切换本身由主机套件覆盖（`routeSwitchSurvivesRepeatedVisits`、`everyRouteUsesTheMaximisedWindow`、
> `everyRouteFillsTheDensityScaledExternalScreen` 等，见 §4.3 的 100 次）。

## 7. 残余风险与需要别人配合的事

### 7.1 残余风险：C1 只是「把窗口关掉」，缺陷还在运行时

- 触发条件是「GC 的 safepoint 落在很深的 Cangjie 栈上」。本仓最深的栈是 CUI 布局递归 + 视图计算，
  本轮把 SOP 的重复计算去掉了；**如果将来有人在 layout 里加更重的分配**（大列表逐帧构造、
  在 `layout` 里跑图算法），同一崩溃会以新的栈顶回来。
- 兜底建议（按代价排序）：
  1. **升级/上报 `sts-1.2.0` 运行时**：把 §3.1 的栈与 §2 的真机 `hilog` 行交给工具链侧，
     要求 `CheckAndPush` 对 null 槽位短路、`SlotRoot::VisitGCRoots` 过滤非法指针。
  2. 若必须留在本版本：真机进程里注入 `cjRegionSize=1024KB`（或 `cjHeapSize=1GB`）有缓解迹象
     （主机 30 次 0 崩），但**尚未证明可行**：`cjRegionSize`/`cjHeapSize` 由运行时在
     `CJLibInit` 读环境变量，而 HAP 进程的环境由 `requireCJLib` 之前的 ArkTS 侧决定，
     本仓没有可靠注入点。要做就得在 `entry/src/main/ets` 的启动链里 `setenv` 后再 `requireCJLib`，
     属于新的宿主改动，需要单独评审。
  3. 保留 `scripts/stability.sh` 作为回归闸门：修前 22%、修后约 1% 的崩溃率都能在 100 次内暴露；
      **闸门当前会以约 1% 的概率报红，这是运行时的真实残余，不是脚本噪声**，请连同 `stability-logs/`
      `#0` 那一行一起看。

### 7.2 需要其它 worker 处理的事（本 worker 未改这些文件）

1. **侧栏点击不激活**（真机可复现）：`diag.log` 显示 `MouseDown button=Left primary=true` 且
   `hover='shell-nav-sop'`，但 `pressed=''`、`ui-prefs.json` 的 `route` 不更新、界面不切换。
   主机的路由切换用例全绿，所以差异在「真机按下 → 激活」这一段的实现（疑似自定义导航行只用了 hover，
   没有把 press 记到 `pressed` 上，或 `MouseUp` 的 hover 已被重建清空）。`src/shell/**` 归输入侧 worker。
2. **`cjpm test` 整树编译不过**（与稳定性无关，但挡住了全树回归）：
   - `src/views/dashboard/logic/today_test.cj` / `today_extra_test.cj` 用了 `orEmpty`（在 `support.cj` 里，但
     测试文件看不到）；`src/views/gtd/logic/gtd_civil_test.cj` 用了 `daysFromCivil` / `civilFromDays`
     （现在在 `textura.core.data.date`，测试文件缺 import）。共 12 处错误。
   - 本轮的主机闸门因此只跑 `src/shell` + `src/views/sop` 两个包（`TEXTURA_STRESS_PATHS` 可配）。
3. **`src/views/sop/*.cj` 正在被改**（`SopViewState` 缺 `areaAnchor` / `areaPopup` / `areaHover`，
   `paintSopAreaPicker` 未定义），构建期间红过两次；本 worker 的 `stability.sh` 支持
   `TEXTURA_STRESS_SKIP_BUILD=1` 复用它上一次的产物。
4. `SopPageWidget.layout` → `buildFrame` → `layoutIds`：视图层仍然每帧调用；本轮在逻辑层做了缓存兜底，
   更彻底的做法是视图层按数据版本号记忆（`src/views/sop/sop.cj` 归 SOP 视图 worker）。
## 8. 2026-10-28 真机复验：三条缓解路线全部被证伪

本轮目标只有一个：让 OKR 页底「新增关键结果」prompt 打开后「不动任何东西等 90s ×3」不崩。
三条路线都实现并跑到真机，**全部失败**。失败结论本身就是资产——不要让下一个接手的人重做。

### 8.1 运行时 GC 参数注入（`cjRegionSize` / `cjHeapSize` / `cjGCThreshold`）

- 桌面验证：`env cjRegionSize=999999999 ./h` 会让运行时打印
  `Unsupported cjRegionSize parameter ... Valid range [4KB, 2048KB]`，说明参数名与读取方式正确。
- 真机实现（HAP 侧）：新增 `libtextura_env.so` NAPI 模块，`EntryAbility.onCreate` 里先
  `setenv("cjRegionSize","1024KB",1)` 再 `requireCJLib`；模块 import 提到
  `libark_interop_loader.so` 之前；另在 `AppScope/app.json5` 写 `appEnvironments`
  （已确认该字段进了 HAP 的 `module.json`）。
- 结果：**四种变体都无效**。
  - `hilog` 有 `Textura/HOST: runtime env read-back: 999999999|applied=...`（setenv 与同模块 getenv 自洽）；
  - 但 13ms 后运行时仍打印 `Region size: 64(KB)`、`Heap size: 524288(KB)`，且非法值
    `999999999` 没有触发 `Unsupported cjRegionSize` 警告。
  - 结论：**真机 HAP 进程里，Cangjie runtime 的 `getenv` 看不到 ArkTS/NAPI 侧设置的进程环境变量**
    （疑似 libc/namespace 隔离；`libcangjie-runtime.so` 的 `getenv` 是 `UND`，没有本地 `environ`）。
  - `appEnvironments` 同理无效，不要再用它做运行时调参。

### 8.2 页面级 `RetainedSubtree` 缓存

- 改动：`src/views/okr/okr.cj` 用 `RetainedSubtree("okr-page-root", UInt64(storeRevision),
  cachePaint: true)` 包住 OKR 页，让光标闪烁帧命中 build/layout/paint 缓存。
- 门槛：根包 `cjpm test` **704/704**；`parity.sh`/`diff.sh --theme both` **14/14**。
- 真机：prompt 第 1 轮就崩（pid 4493 → 5473 → 5622，两次 `toRegion2Idx != INVALID_VALUE`）。
- 结论：缓存没有改变触发面；对运行时缺陷无效。

### 8.3 关闭光标闪烁（CUI-P13）

- 改动：`TextInputStyle.caretBlink`（默认 `true`）+ `paintCaret` 关闭时只画常亮光标、不调
  `requestFrameAt`；OKR prompt 传 `caretBlink: false`。
- 门槛：根包 **704/704**；CUI 包 967 通过 + 1 个既有 unicode 夹具 ERROR。
- 真机：prompt 打开后 **10s 内**崩（pid 16684，`toRegion2Idx`）。
- 结论：**「空闲出帧」不是充分触发条件**；打开 prompt 这个动作本身（布局、IME 会话、编辑器
  初始化）已经足够把 GC 推到坏落点。

### 8.4 最小复现（`cangjie/tools/runtime-repro/`）

按 HANDOFF 要求写了独立程序：96 层递归 + 每层 `ArrayList`/`HashMap`/字符串分配 + 栈底 4096 条
字符串 + 单进程 300 轮；另加每层 `malloc`/`free` FFI 帧。

| 版本 | 次数 | 崩溃 |
|---|---|---|
| 纯仓颉分配 | 200 | 0 |
| 每层 FFI 帧 | 200 | 0 |

**没有复现**。这把缺陷范围收窄为「需要 CUI/SDL 参与的真实栈」，而不是「任意深栈 + 高频 GC」。

### 8.5 本轮结论

- 应用层已没有可用的规避手段：GC 参数改不了、缓存和降帧都无效。
- 可复现材料仍是 `scripts/stability.sh`（`textura.shell`，修后约 1/100），`#0` 行可直接交上游。
- 设备已恢复为基线包（`sha256 476437783a1f0242ebeb969437f850af45b32dae53d5622512aa1e2a143f8218`，
  30,118,784 B）；工作树只有本文件、`docs/HANDOFF.md` 与新增的 `tools/runtime-repro/`。
