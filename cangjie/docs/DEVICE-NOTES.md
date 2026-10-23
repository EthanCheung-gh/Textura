# 真机输入、帧耗时与偏好落盘笔记（HarmonyOS）

本文件记录**只能真机回答**的问题：指针输入到没到、一帧到底多少钱、点击为什么没生效、
偏好文件为什么没写下去。构建链、启动链、安装与签名见 `HARMONY.md`；对拍判据见 `PARITY.md`。

测试设备：HUAWEI MateBook 14（`MNTXM-24A`，HarmonyOS 26 / API 26，应用窗口 buffer
**1930×1020**，`hdc` 目标 `192.168.0.3:36773`）。

> 本文件的两次自我修正，先写在前面，避免后来人重走：
> 1. **「每帧 256ms」是探针口径错误**（把 `step()` 尾部等待下一个事件的时间算进了帧成本）。
>    真实帧成本 4–7ms（热）/ 30–55ms（换路由）。见 §3。
> 2. **「点击无效」的根因在 store → CUI 的响应式桥缺失**，不在 SDL、不在按钮解码、不在坐标。
>    已在真机上修复并验证（§4）。同时纠正一条旧结论：本机的输入注入**是可用的**（§7），
>    之前判为「全局失效」是因为 `uitest uiInput click` 只注入了抬手事件。

---

## 1. 探针（`cangjie/harmony/host/src/probe.cj`）

宿主自带的可关闭诊断通道。**默认关闭**（`PROBE_COMPILED_ON = false` 且无开关文件时不写任何东西），
打开后提供四类证据：

| 证据 | 内容 | 行格式 |
|---|---|---|
| 事件流 | 前 200 个指针/键盘事件，CUI **Capture 阶段**在原树根记录：类型、`x/y`、**解码后的 button 与 `primary=`**、SDL 原始光标位、焦点/悬浮/按压 id、修饰键 | `ev#N …` |
| 帧耗时（墙钟） | 每 60 个宿主 `step()`：`drawn`（真画了）/`idle`（只空等）分开统计 avg/min/p95，`cost=` 是**帧自身成本**，附视口/缩放/后端/超采样/文本计数/`partial` | `step#N …` |
| 帧耗时（分段） | 每个统计窗口的**相位均值**：build / layout / event / semantics / begin / tree / resolve / present（纳秒→ms），外加 `events=`（每帧事件数）与 `partial=` | `phases …` |
| 偏好落盘 | 一次：解析出的 `ui-prefs.json` 路径、写入是否成功、当时的 route、失败原因 | `prefs path='…' wrote=… route='…' error='…'` |

输出双写：

* **文件** `<filesDir>/textura/diag.log`（启动后可见 `sandbox=/data/storage/el2/base/files/textura/`；
  从 shell 侧看是 `/data/app/el2/100/base/com.ethancheung.textura/files/textura/diag.log`，`0666`，
  `hdc shell cat` 可读）。这是**权威副本**，长交互不会被冲掉。
* **hilog**：`SDL_LogMessage`。实测本机不落到 hilog（`hilog` 里只有 SDL 自己经 `OH_LOG_Print` 打的
  `SDL/APP` 行），所以不要指望 `hilog | grep probe`；探针行与 hilog 的对齐靠时间戳。

### 1.1 开关为什么最终用编译期常量

探针按设计优先读开关文件：`<sandbox>/debug-input` 或 `/data/local/tmp/textura-debug-input`。
本机固件上**两条路都走不通**（app 进程 SELinux 域 `u:r:debug_hap:s0`，沙箱目录归 app uid）：

```text
$ hdc shell touch /data/app/el2/100/base/com.ethancheung.textura/files/textura/debug-input
touch: … Permission denied
$ hdc file send flag-test …/files/textura/debug-input
[Fail]Error opening file: permission denied
```

因此采集用 `PROBE_COMPILED_ON = true` 的构建进行，**源码默认值保持 `false`**（本轮出货构建验证过：不出新行）。
常规开关需要在宿主里再开一条操作员可达的通道（`aa start` 的 want 参数 → ArkTS → Cangjie），属新功能。

---

## 2. 首帧尺寸与密度（实测）

```text
t=64 ctx first-event vp=1930.000000x1020.000000 scale=1.000000 font=1.000000 \
     driver=opengles2 super=1 text=measure6/shape3/draw0
```

* 逻辑视口 = **1930×1020**，`displayScale = 1.0`，`fontScale = 1.0`，**超采样 1×**，后端 **opengles2**。
* 不存在「被当成 2880×1620 渲染」：XComponent buffer 与窗口逻辑尺寸 1:1。卡顿与像素预算无关。
* 布局常量仍是 Web 的 1440×900 设计值；真机只是画布更大，两侧留白由填充布局吸收，与 1440×900 对拍无关。

---

## 3. 帧耗时：口径修正（**重要，取代旧结论**）

### 3.1 旧数字错在哪

旧探针把「一次 `step()` 的墙钟时间」当作帧成本。但宿主模式的 `step()` 在帧尾会
`SDL_WaitEventTimeout` **等下一个事件**（桌面上限 250ms），于是——

```text
# 旧记录（会误导）
step#3240 drawn=14 drawnavg=255.970000ms min=254.020000ms p95=259.600000ms partial=false
```

其中约 250ms 是**空等**，真正干活的时间被淹没了。

### 3.2 现在的读法

CUI-P03 给宿主开了 `DesktopApp.lastFrameCost()`（分段纳秒），探针每个窗口打一行 `phases`。
同一次点击过程实测：

```text
# 输入帧（悬停/指针移动，全帧重绘 1930×1020）
phases frames=16 build=0.010ms layout=0.040ms event=0.270ms semantics=0.000ms \
        begin=0.000ms tree=1.600ms resolve=0.000ms present=2.080ms events=2.25 partial=0
# 冷启动首帧（文字缓存全冷）
phases frames=2  build=0.000ms layout=11.260ms event=0.160ms semantics=0.040ms \
        begin=0.010ms tree=17.430ms resolve=0.000ms present=14.100ms
# 换路由（日历 → 含新内容 rebuild）
phases frames=2  build=0.010ms layout=0.040ms event=3.120ms semantics=0.030ms \
        begin=0.010ms tree=24.750ms resolve=0.000ms present=2.020ms events=3.50
```

结论：

| 场景 | 真实帧成本 |
|---|---|
| 指针移动 / 悬停（热缓存，全帧重绘） | **4–7ms**（tree 1.6–3.0 + present 2.1–2.8） |
| 路由切换（重建 + 新内容） | **30–55ms**（`costavg=29.98ms min=5.48ms p95=54.47ms`），主项是 `tree=24.75ms` |
| 冷启动首帧 | **43ms**（layout 11.3 + tree 17.4 + present 14.1） |
| 纯空等 step | 只剩等待时间（见 §3.3） |

也就是说：**「卡顿」不是 250ms 的重绘，而是**（a）点击根本不生效（界面冻在旧树上，§4），
（b）换路由那一下 30–55ms，以及（c）宿主把应用 UI 线程阻塞 250ms（§3.3）。

### 3.3 空转 CPU：宿主等待上限 250ms → 16ms

`step()` 跑在应用 UI 线程上（XComponent `OnFrame`）。CUI 的 `run()` 循环里「阻塞 250ms 等事件」是对的，
宿主模式里是错的：它把 UI 线程一起按住，排在其后的窗口系统操作全部延后。

| 设置 | 空转 step | 空转 CPU（`/proc/<pid>/stat` utime+stime 差值） | 系统 `OS_DfxWatchdog` 线程 |
|---|---|---|---|
| `MAX_EVENT_WAIT_MS = 250` | 250ms/步（4 步/s） | **≈23%** | **18.4%**（147 ticks / 8s） |
| `HOSTED_MAX_EVENT_WAIT_MS = 16`（改后） | 16ms/步（60 步/s） | **≈6%** | 消失（0） |

CUI 侧改动见 `third_party/README.md` 的 `CUI-P03-hosted-frame-cost`；桌面 `run()` 仍用 250ms，行为不变。

---

## 4. 点击链路：根因与修复（真机已验证）

### 4.1 现场证据（改前）

SDL 收到了按压、坐标也对、CUI 也把按压交给了侧栏：

```text
ev#2  MouseMove  x=60.00 y=128.00 down=false hover=''
ev#40 MouseDown  button=Left primary=true x=60.00 y=128.00 down=true hover='shell-nav-calendar'
ev#41 MouseMove  x=60.00 y=130.00 down=true  focus='shell-nav-calendar'   ← 焦点都落上了
```

`SidebarView.handle` 命中行 → `ctx.focus(...)` → `onNavigate` → `store.setRoute("calendar")` **都执行了**；
但 `$HOME/.textura/ui-prefs.json` 的 `route` 全程是 `dashboard`（且 mtime 不动），界面也一直是仪表盘。
而 `persistUi` 只在 `buildShell` 里调用 —— 它一次都没被再执行。

### 4.2 根因：store → CUI 的失效桥缺失

* `AppStore.ui` / `AppStore.state` 是 `core.data` 的 `StateCell`（**不依赖 cui**），写入不会让 CUI 的
  增量保留图变脏；CUI 只在**自己** `State` 的读依赖变化时才重建声明作用域。
* `buildRoot` → `composeChildren("Root", …)` 在作用域不脏时**根本不执行 body**，所以 `buildShell` 没重跑：
  旧树继续画，`onNavigate` 的写入只进 store。
* 悬浮能动，是因为 hover 是控件内部可变字段，`handle` 改了当帧 `draw` 就能看见，不依赖重建。

### 4.3 修法：`ShellHost.revision` + `armStoreBridge`

| 位置 | 作用 |
|---|---|
| `src/shell/appshell.cj` `ShellHost.revision: State<Int64>` | 全仓**唯一**被 shell 顶层读取的 CUI `State` |
| `buildShell` 第一行 `let _ = host.revisionToken()` | 在打开任何声明作用域之前建立依赖（顺序不能变） |
| `armStoreBridge(deliver)` | 订阅 `store.state` / `store.ui` / `store.notices` + `runtime.onVisualChange`，任一变更 → `revision += 1` |
| `src/shell/runtime.cj` `onVisualChange` | 自动保存相位（侧栏页脚 `正在保存…`）真变化时也失效 |
| `DesktopApp.deliver(action)`（CUI-P03） | 已在 UI 线程 → **当场**执行（同一输入帧内重绘，点击延迟 1 帧）；否则转 `post` |

桥是**全局**的：视图自己也直接读 store（dashboard/gtd/okr/calendar/gantt/sop/settings），
任何 store 写入都失效整个 shell，视图不需要各写一遍（OKR 原有的 `OkrStoreBridge` 仍在，二者不冲突）。

### 4.4 修后证据（本机注入 + 截图 + 文件）

```text
# 注入一次侧栏第 2 行（日历）的按压
ev#40 MouseDown button=Left primary=true x=60 y=128 hover='shell-nav-calendar'
phases frames=2 build=0.010ms layout=0.040ms event=3.120ms tree=24.750ms present=2.020ms   ← 真的重建重绘了
prefs path='…/.textura/ui-prefs.json' wrote=true route='calendar'
```

* `snapshot_display` 截图：顶栏标题变「日历 公历、农历与节气的日程概览」，内容区变月历网格，侧栏「日历」高亮。
* 再点 OKR 行 → `route='okr'`；**`aa force-stop` + 重启后直接开在 OKR**（首帧截图 + `prefs … route='okr'`）。
* 说明：点击 → 路由切换 → 顶栏标题与内容区**同时**变化，且偏好落盘并跨启动恢复。

`src/shell/store_bridge_test.cj`（headless，`WidgetTestHost`）固化了这条链：
store/ui/notice 写入后 `buildShell` 的 **body 执行次数 +1**、输入帧不触发重建、
`MouseDown(RawCode(0|1))` 也能导航、非主键不导航、`isPrimaryPointerButton` 映射表。

---

## 5. 输入合并与局部重绘：改动与取舍

### 5.1 输入合并（CUI-P03，`desktop_app.cj`）

* 旧行为：`waitForWork` 等到**一个**事件就返回 → 一帧处理一个事件 → N 个事件 N 次 build/layout/draw。
* 现在：等到事件后立刻把**已入队**的其余事件并入本帧（`mergeQueuedEvents`），
  `collectPendingEvents` 每帧上限 **`MAX_EVENTS_PER_FRAME = 64`**，超出的留在队列并
  `ctx.requestFrame()` 顺延到下一帧，不会把一帧拉成无界停顿。
* 真机效果：一次 `uitest fling` 的 5 个事件落在 **2 个绘制帧**里（改前是 5 帧）。

### 5.2 局部重绘（retained partial damage）为什么仍是 `partial=0`

CUI 原本的门槛是「只要本帧有输入事件就全帧」。现在改成 `canRepaintPartially`：
本帧**只有** `MouseMove`、且 focus / pressed / drag 拥有者跨帧未变（即输入只可能改变 hover）时，
允许走 retained 局部 damage。

但实测 `partial` 仍然恒 `false`，原因有两层，都是**故意不改**：

1. hover 是控件内部字段，不产生任何 retained damage 提示（没有 `RetainedSubtree` 边界给它记账），
   `takeRetainedFrameDamage` 拿到空提示就按全帧处理；
2. 内容区的卡片也有 hover 依赖。若只把侧栏包成可复用边界、只重绘侧栏，
   指针移到卡片上时会出现**陈旧高亮**——这是视觉回归，代价比收益大。

定量依据（§3.2）：全帧重绘只要 **4–7ms**，为省这点时间引入「谁的绘制依赖 hover」的建模不划算。
真要更进一步，正解是给 hover 引入 `State` + `RetainedSubtree` 边界，并**同时**把内容区的
hover 绘制纳入同一 damage 记账——那是一次结构性改造，不属于本轮。

---

## 6. 偏好文件不落盘（已修复）

**症状**：`ui-prefs.json` 的 mtime 永远停在首次安装那一刻，`route` 恒为 `dashboard`，
重启后总回到默认视图。

**根因**（探针一行定位）：

```text
prefs path='/data/storage/el2/base/files/textura/.textura/ui-prefs.json' wrote=false \
      route='dashboard' error='The input path `/data/storage/el2/base/files/textura/.textura` is already exists.'
```

`ShellPreferences.persist()` 把「建父目录」和「写文件」放在**同一个 try** 里，而
**Cangjie 1.2.0 的 `Directory.create` 在目录已存在时会抛异常**（`… is already exists.`）。
首跑目录不存在 → 建目录 + 写文件成功（所以曾出现一个 12:58 的文件）；此后目录已存在 →
`Directory.create` 抛 → 写文件根本没执行 → 异常被吞 → **每次写入静默失败**。

**修法**（`src/shell/runtime.cj`）：

* 建目录单独 try，吞掉「已存在」；**文件写入才是成败判据**；
* `persist()` 记录 `lastWriteOk` / `lastWriteError`（不再无声吞掉失败）；
* `persistUi` 失败时**不记「已持久化」**，下一帧重试（沙箱目录可能晚一帧就绪）；
* `ShellPreferences.load(path)` 新重载：宿主用**绝对路径**（`<sandbox>/.textura/ui-prefs.json`），
  HAP 进程没有可用的 `$HOME`，不该让偏好依赖它；`prepareSandbox()` 幂等补建 `.textura/`；
* 探针新增 `prefs … wrote=… error=…` 一行，这类问题下次一眼可见。

**修后证据**：

```text
t=95  prefs path='…/.textura/ui-prefs.json' wrote=true route='dashboard' error=''
# 点日历 → 点 OKR
$ hdc shell ls -l …/files/textura/.textura/
-rw-rw-rw- 1 20020258 20020258 56 2026-10-23 15:35 ui-prefs.json     ← mtime 刷新
$ hdc shell cat …/files/textura/.textura/ui-prefs.json
{ "route": "okr", "theme": "light", "recent": [] }
# aa force-stop + aa start 之后
t=96  prefs path='…/.textura/ui-prefs.json' wrote=true route='okr' error=''
截图：直接开在 OKR 视图
```

`src/shell/store_bridge_test.cj` 增加了两条：显式路径往返、不可写路径必须报错。

---

## 7. 本机输入注入方法（纠正「注入全局失效」的旧结论）

旧结论（`HARMONY.md` §7.1c 曾写「对任何窗口均失效」）是**方法错**，不是设备限制。可用做法：

| 目的 | 命令 | 说明 |
|---|---|---|
| 触摸（会变成鼠标事件） | `hdc shell uitest uiInput swipe <x1> <y1> <x2> <y2> <velocity>` | **可用**。SDD 的 openharmony 后端把 touch 转成 MouseMove/Down/Up |
| 鼠标（相对移动 + 点按） | `hdc shell uinput -M -m <dx> <dy>` / `-c 0` | **可用**。`-m` 是**相对位移**且**不接受负数**，所以只能往右下走 |
| 平滑移动（很多人踩） | `uinput -M -m x1 y1 x2 y2 <ms>` | 第二组参数会被忽略，实际只做一次相对移动 |
| `uitest uiInput click` | — | **不可用**：只注入了抬手（hilog: `pointer event action:4 … PA:up`），没有按下 |
| 零长度 swipe | `swipe 60 128 60 128 60` | 无事件（没有位移就不产生动作） |

**坐标换算（关键）**：`uitest` 的坐标是**屏幕坐标**，SDL 收到的是**窗口坐标**，两者差一个窗口原点。
本机窗口原点 = `(614, 242)`：

```text
screenX=674 screenY=370  →  x=60  y=128
```

所以要点侧栏第 N 行（窗口坐标 `(60, 72+36.25*N+18)`），就把 `x + 614`、`y + 242` 传给它。
例：日历行（窗口 `(60,128)`）→ `uitest uiInput swipe 674 370 674 375 150`。

另注意：偶发首次注入丢失（系统侧瞬时），重发一次即可；设备息屏会锁屏，先
`hdc shell power-shell wakeup`。

---

## 8. 修改前后对比（同一台设备）

| 指标 | 改前 | 改后 |
|---|---|---|
| 点击侧栏 | 永不切换（store 变了、界面不动、prefs 不写） | **点击生效**：顶栏标题 + 内容区同时变（日历 / OKR 均验证），prefs 落盘并跨启动恢复 |
| `step` 墙钟（`drawnavg`） | 256ms（含 250ms 空等） | 16–38ms（等待上限 16ms + 真帧 4–55ms） |
| 真实帧成本 `costavg` | 无该指标 | 悬停 4–7ms；换路由 `avg 29.98 / p95 54.47ms`；冷启动首帧 43ms |
| `partial`（局部重绘） | false | false（见 §5.2，故意保留全帧） |
| 一帧处理的事件数 | 1 | ≤64（突发合并，实测 5 事件 → 2 帧） |
| 空转 step / CPU | 250ms / 4 步/s，CPU ≈23%（含 `OS_DfxWatchdog` 18%） | 16ms / 60 步/s，CPU ≈6%，watchdog 消失 |
| `ui-prefs.json` | 只在首跑写过一次，之后静默失败 | 每次 route/theme 变化都写，重启后恢复 |
| 桌面 1440×900 对拍 | 14/14 | **14/14**（逐项数值不变，视觉零变化） |

---

## 9. 路由切换导致整页冻结（已修复，`TEXTURA-CUI-P04`）

### 9.1 症状与旧判断的修正

用户现场：点若干次侧栏之后界面「冻结」——所有控件点不动、滚轮不滚、需要重启应用。现场还报告
「侧栏只有 OKR / SOP / GTD 可点」。**本轮把两条都复现并给出了根因**，其中「只有三项可点」是
坐标换算错误造成的观察偏差（见 §7 的窗口原点：外框 `(614,177)` + 系统标题栏 66px ⇒ 内容原点
`(614,242)`，旧记录里的 `(614,242)` 才是点击应使用的原点），点对之后**七条路由都能切换**。

### 9.2 根因：构建提交阶段的 CUI 渲染节点二次回收

诊断包（`PROBE_COMPILED_ON=true`）在真机 `diag.log` 里给出直接证据：

```text
ev#44 MouseMove x=163 y=237 hover='shell-nav-gantt'
ev#45 MouseDown button=Left primary=true x=163 y=237 hover='shell-nav-gantt'
t=30475 fail route=gtd   error=IllegalStateException: Cannot inspect commands through a released scene node
t=30482 fail route=gantt error=IllegalStateException: Cannot inspect commands through a released scene node
…（此后每帧一次，直到进程结束；本轮实测共 1702 次）
```

链路：点击 → store 写入成功（`ui-prefs.json` 因为 `buildShell` 没跑完而**不落盘**）→ 该帧
`buildRoot → finishBuild → commitMountBuild → removeAutomaticMount → closeRenderNodes →
AutomaticRenderNode.close() → invalidatePaintCache()` 抛异常 → **之后每一帧都在同一处抛**。

两个放大因素：
1. 异常发生在 `finishBuild`（`body` 之外），`renderRoute` 的错误边界**够不到**它；
2. CUI 的 `UiFailureCollector` 把它收进宿主失败集合并继续循环，所以进程活着、界面死了、日志里也没有痕迹
   —— 这就是「静默冻结」。诊断包因此临时给 `DesktopApp` 加了 `hostedFailureListener`（见 §9.4 的说明）。

### 9.3 修法（`CUI-P04`，`third_party/CUI/src/core/automatic_render_node.cj`）

`removeAutomaticMount` 是「先关外层、再递归关内层」，内层节点仍持有指向已关闭父节点的 `parent`
链接，向上失效缓存时踩到已释放的 `ElementSceneNode`。补丁在 `invalidatePaintCache` 里
`if (closed) { return }`，并只向**未关闭**的父节点传播；新增只读 `isClosed()`。只跳过对已释放节点的
缓存操作，绘制指令不变 → 对拍 14/14 数值未变。

主机回归（`src/shell/route_switch_test.cj`）：修前 `routeSwitchSurvivesRepeatedVisits` 稳定 ERROR，
修后 PASSED。

### 9.4 真机复测（出货构建，探针关闭）

安装 `entry-default-signed.hap` 后按用户顺序注入点击（屏幕坐标 = 内容坐标 + `(614,242)`）：

| 步骤 | 注入 | `ui-prefs.json` 结果 |
|---|---|---|
| 今日 | `(674,331)` | `dashboard` |
| 日历 | `(674,367)` | `calendar` |
| 甘特 | `(674,477)` | `gantt` |
| 设置 | `(674,549)` | `settings` |
| OKR | `(674,404)` | `okr` |
| SOP | `(674,513)` | `sop` |
| GTD | `(674,440)` | `gtd` |
| 再次今日/日历/甘特 | 同上 | `dashboard` / `calendar` / `gantt` |

* 每一步都切换，**切换之后仍可继续点击**（冻结消失）；诊断包同一次会话里 `fail` 计数 **0**（修前 1702）。
* 内容区滚轮：`uinput -M -s -4` 后整屏取样像素变化 33 731（内容真的滚动）。
* 按钮：GTD 顶栏「快速收集」→ 弹出「收集到 GTD 收件箱」模态（遮罩 + 面板）。
* 已知注入噪声：`aa start` 之后**第一次**注入偶发丢失（系统侧瞬时），重发一次即可，与本应用无关。

---

## 10. 键盘：到得了 CUI，但被系统输入法抢走字符键

### 10.1 证据链（诊断包 `diag.log`，Capture 阶段根监听）

```text
ev#3 KeyDown key=Escape
ev#5 KeyDown key=Scan(224) mods=64      ← 左 Ctrl
ev#6 KeyDown key=Letter(75) mods=64     ← Ctrl+K，修饰键正确
```

结论修正：`requestFocus`/`onFocus` 之外，**按键本身是能到 CUI 的**（Escape、Ctrl 都到）。此前「键盘全不可用」
的观察里至少混了两件事：

1. **方向/字符键被系统输入法接管**：SDL 窗口创建时就 `SDL_StartTextInput`（`cangjie-sdl/src/window.cj:137`）
   且永不停止，HarmonyOS 因此把系统输入法挂到 XComponent 上。注入 `K` 时系统弹出候选条（截图里出现
   「kk / 看看 / 开口 / 可靠…」），`diag.log` 里**只有 Ctrl 的 `Scan(224)`**，`Letter(75)` 不再出现。
2. **`Tab` 根本不产生事件**：`uinput -K -d 2049` 后 `diag.log` 无任何对应行——被 ArkUI 的焦点遍历吃掉。

### 10.2 修掉的软件侧 bug：字母键码大小写

`handleHotkey` 原来先 `asciiLower(code)` 再与**大写**常量比较：设备上报 `'K'` = 75，
`asciiLower(75)` = 107，永远不等于 75，于是 Ctrl+K / Ctrl+N / Ctrl+Z 全部静默失效（桌面 SDL 报小写 107，
`asciiLower(107)` = 107 也不等于 75，同样失效）。改为 `isLetterKey(code, letter)` 两侧都折叠
（`src/shell/appshell.cj`），一张表同时服务两种键码约定。

主机回归（`src/shell/keys_test.cj`，七条路由各跑一遍）：Ctrl+K 打开命令面板、Esc 关闭（并断言关闭后
侧栏点击仍有效）、`?` 开关快捷键弹层、Ctrl+N 开关快速收集、Tab / Shift+Tab 焦点前后移动。

### 10.3 真机键盘现状（出货构建）

| 键 | 到达 CUI | 生效 |
|---|---|---|
| `Esc` | 是 | **是**：关闭命令面板与「收集到 GTD 收件箱」模态（截图确认） |
| `Ctrl`（`Scan(224)`） | 是 | 修饰键位正确（`mods=64`） |
| `K`/`N`/`Z` | 修后**是**（P05 关掉常驻输入法） | **是**：Ctrl+K 开命令面板、Ctrl+N 开快速收集 |
| `Tab` / `Shift+Tab` | 修后**是**（P06 桥接） | **是**：焦点沿 `shell-search → UiIconButton → UiSegmented → UiButton` 移动 |
| 方向键 | 修后**是**（P06 桥接） | 是：交由 CUI 的视图/滚动处理 |
| 输入框里的中文 | 走系统输入法 | **是**：聚焦搜索框输入 `ni` 出现中文候选 |

### 10.4 已修：输入法抢字符键（`TEXTURA-CUI-P05`）

`SdlWindow` 建窗时调用一次 `SDL_StartTextInput` 且永不停止 → HarmonyOS 把系统输入法挂到 XComponent 上，
字母键全部进 IME（候选条出现），SDL 只收到 `Ctrl`（`Scan(224)`）。修法：窗口新增 `startTextInput()` /
`stopTextInput()`，CUI 在 `applyTextInputAnchor()` 里按「本帧是否有文本控件绘制了插入符」切换——
无输入框时停止文本输入，字符键回到应用；输入框聚焦时重新开启，输入法不受影响。
`SafeImeController.attach/hideTextInput` 同时维护 `TextInputState.attached`，供页面决定是否转发按键。

真机证据（同一台机器，出货包）：

| 操作 | 结果 |
|---|---|
| 无输入框按 `Ctrl+K` | 命令面板打开（截图：命令面板含搜索框与条目行） |
| `Esc` | 命令面板关闭（截图对比 115 908 取样像素变化） |
| `Ctrl+N` | 「收集到 GTD 收件箱」弹出（截图像素变化 119 555） |
| 聚焦顶栏搜索框输入 `ni` | 系统输入法候选条出现 `你/拟/呢/尼/妮…`，中文输入正常 |

### 10.5 已修：Tab 被 ArkUI 焦点遍历消费（`TEXTURA-CUI-P06`）

`Tab` 注入后 CUI 端**没有任何事件**（ArkUI 在 XComponent 的按键回调之前消费掉 Tab）。
修法：HAP 侧新增 NAPI 模块 `libtextura_keys.so`（`sendKey(scancode, down, mods)` → `SDL_PushEvent`），
页面根容器 `onKeyEvent` 只转发 Tab/Shift+Tab、方向键、Escape、Ctrl/Cmd+字母，普通字母不转发（留给输入法）；
ArkUI 只放行 KeyUp 的情况由页面补发一次完整按下-抬起。输入法已挂载时页面不再转发，避免重复投递。

真机证据（`diag.log` 的 `focus` 字段随每次 Tab 变化）：

```text
ev# KeyUp key=Tab focus='shell-search'
ev# KeyUp key=Tab focus='…:UiIconButton'
ev# KeyUp key=Tab focus='…:UiSegmented'
ev# KeyUp key=Tab focus='…:UiButton#2'
```

即 Tab 依次走过顶栏搜索框 → 主题切换按钮 → 设置页分段控件 → 设置页按钮，**焦点环真的在控件间移动**。

### 10.6 剩余工作（明确、可执行）

1. **让文本输入按焦点开关**：`cangjie-sdl` 增加 `SdlWindow.stopTextInput()/startTextInput()`，
   CUI 在 `applyTextInputAnchor()` 里按「有/无文本控件焦点」调用。这样输入法只在编辑框聚焦时占字符键，
   Ctrl+K 等快捷键才能到 CUI；桌面侧行为不变（默认仍然开启）。这是字符键与 Tab 之外的字母键的唯一正解，
   属第三方改动，需与 CUI-P04 同流程登记。
2. `Tab` 需要 ArkUI 焦点链（`Index.ets` 根容器 `focusable(true)` + `defaultFocus`）或 ArkTS→native 按键桥；
   本轮尚未实现，因为 §10.1 证明非字符键本来就能到 CUI。

---

## 11. 卫生

* 探针源码默认关闭（`PROBE_COMPILED_ON = false`；出货构建实测 `diag.log` 不出新行）。
  真机现存安装包是**探针开启**的诊断包（便于现场复测），出货需按 `HARMONY.md` §7.1c 重编。
* `build-profile.json5` 用 `set_signing_material.sh` 临时指向 `.certs/textura-debug/`，**用完 `git checkout` 复原**；
  `.hap`、`.certs/`、`diag.log` 一律不提交。
* `diag.log` 只存在于设备沙箱，仓库里没有任何日志产物。

---

## 12. 从别的路由进入 OKR 后整页空白（已修复）

### 12.1 现场与排除法

| 取证 | 结果 |
|---|---|
| `hdc shell date` | `2026-10-23` |
| 设备 `workspace.json` | 唯一 objective + 3 个 KR，`okr.period` **全部是 `2026-Q4`** |
| 直接 `aa start`（记住的 route=okr） | **正常显示**（Q4 目标卡齐全） |
| 从仪表盘/日历点侧栏进 OKR | 内容区**全白**，顶栏标题是 OKR |
| `ui-prefs.json` | 仍随点击变化（侧栏可点、没有整页冻结） |
| 诊断包 `fail` 计数 | **0**，没有异常被吞 |

所以「Q4 是空季度」不成立：Q4 有数据、空态卡也写好了。问题只在**切入那一刻之后**。

### 12.2 根因：`measure` 返回「上一次 layout 的内容高度」

`OkrPage.measure()` 原来返回字段 `contentHeight`，而它只在 `layout()` 末尾被写入：

```text
新 OkrPage 实例 --measure--> contentHeight = 0
        ↓
ScrollView.layout: child.measure(...) -> 0  ->  child.layout(Rect(..., 0))
        ↓
layoutPage 跑完，contentHeight 变成真实值，但父级这一帧只分了 0 高
        ↓
这一帧之后没有任何脏标记 -> 不会再 measure/layout -> 永久空白
```

首次启动能显示，是因为窗口尺寸变化额外触发了一次 measure→layout（第二次读到第一次写回的高度）。
全仓只有 OKR 是这种「measure 依赖上一次 layout」的自绘页面，其它视图都是声明式/填充布局，所以只有它白屏。

### 12.3 修法：`measureOnly` 高度预演

- `PageCanvas(measureOnly: true)`：跑同一套行高/列宽公式，但不构造子控件（`TextField` 会持有 `State`
  并注册焦点）、不提交草稿、不写 `focusTrack`；
- `OkrPage.measure()` 在高度未知或宽度变化时先跑一遍该预演，把真实内容高度交给父级；
  真正的 `layout()` 仍按原路径执行，交互与像素不变；
- 回归测试 `src/views/okr/okr_page_test.cj::measureReportsIntrinsicHeightBeforeAnyLayout`
  （把修复禁用 → 稳定 FAILED；恢复 → PASSED）。

### 12.4 修后证据（出货包，探针关闭）

- 仪表盘 → OKR：`~/.cache/textura-device/final-okr.jpeg`（页头 + 2026 Q4 季度条 + 1/3/29%/0 健康度 + 目标与 3 个 KR）；
- 日历 → OKR → 日历 → OKR → … 重复访问正常（同一会话内多次切入，`ship-*` 截图组）；
- SOP → OKR（最终包）正常：`~/.cache/textura-device/final-okr.jpeg`。

---

## 13. 甘特悬停/点击「慢半拍」：一次 hover 重建整个 shell（已修复）

### 13.1 根因

`GanttBody.handleMove` 在悬停行变化时执行 `rev.value += 1`，`handleDown/handleUp` 也各加一次。
`rev` 是在 `gantt.render()` 的作用域里被读取的（`let _ = rev.value`），而 `render` 运行在 shell body
作用域内 —— 于是**每跨一行都重建整个 shell**（真机重建级成本：`tree` 13.8–21.3ms、`costavg` 24.6–51.4ms，
与换路由同级）。而 `GanttBody.draw` 本来就每帧直接读 `state.hoverRow / gesture`，输入帧也必然会重绘，
这次重建完全多余。

### 13.2 修法

- 悬停、拖拽增量、按下/抬起不再递增 `rev`；只有折叠分组（真正改变行集合、需要重算 `rows`）才重建；
- 点击反馈新增 `GanttViewState.pressedRow`，在 `draw` 里按选中同色绘制（行底、左侧 accent 2px、任务条描边），
  反馈在按下那一帧就出现；`store.select` 到达后的持久选中态与它同色，**视觉零变化**；
- 回归测试 `src/shell/gantt_hover_test.cj`：同一帧内跨行 `MouseMove`，断言 `buildShell` 执行次数不变
  （把 `rev` 自增加回去 → 稳定 FAILED）。

### 13.3 数值

| 指标（同机、探针） | 修复前（每次跨行 = 一次 shell 重建） | 修复后（只重绘） |
|---|---|---|
| `phases build` | 重建帧 ≈ 2–5ms（整页作用域） | **0.01ms**（body 未执行） |
| `phases tree` | 13.8–21.3ms（重建级） | **6.4–6.7ms** |
| `phases present` | 2.0–2.6ms | **2.0–2.6ms** |
| `cost avg` | 24.6–51.4ms（同机重建级） | **8.9–9.4ms**（p95 12.7ms） |

> 说明：本机 `uinput -M -m` 不产生 SDL 移动事件，`uinput -M -g` / `uitest swipe` 的起点映射不稳定，
> 无法稳定复现「纯 hover 前后各一次」的对照；上表「修复前」是**同一台设备同一类重建**的实测成本，
> 「修复后」是修复包上跨行 hover 帧的实测值；重建次数差异由主机回归测试给出确定性证明。

---

## 14. `Esc` 被投递两次（已修复）

- `harmony/entry/src/main/ets/pages/Index.ets` 的 ArkTS 键桥同时转发了 `Escape`，而 XComponent 的原生
  按键回调本来就能送达 Escape（§10.1：`ev#3 KeyDown key=Escape`）——一次按键变成两次 KeyDown，
  第一次关掉浮层、第二次作用在下一层。
- 修法：`sdlScancodeFor()` 删除 `KEYCODE_ESCAPE` 分支与 `SDL_SCANCODE_ESCAPE` 常量，只保留
  Tab/Shift+Tab、方向键、Ctrl/Cmd+字母（这些是 ArkUI 会吞掉的键）。
- 回归：`src/shell/keys_test.cj::arktsKeyBridgeForwardsOnlyKeysArkUiSwallows` 直接读 `Index.ets`，
  断言转发表里没有 `KEYCODE_ESCAPE`、且 Tab/方向键/字母仍在（两边都发会立即红）。
- 真机：单次注入 Escape 关闭快速收集弹层，路由不变（`~/.cache/textura-device/after-esc1.jpeg`）。
  本机 `uitest uiInput keyEvent 2070` 的按键状态会残留（偶发把窗口最小化），因此「一次按键只关闭一层」
  的重复投递由源码门禁 + §10.1 的旧证据共同约束。

---

## 15. 快速收集弹层不自动聚焦（已修复）

### 15.1 为什么 `TextField.autofocus()` 不行

1. 它的「已聚焦」闩锁 `localState("TextField:<id>:autofocused")` 按控件 id **记住整个会话**，
   第二次打开必然不再聚焦；
2. 更根本：`textura.ui.ModalHost` 在 **layout** 阶段才调用 `body()` 构造弹层内容，此时 CUI 没有活动的
   state store，`TextField` 的 `registerFocusable` 不会进入焦点图；下一帧焦点图提交时 `ctx.focus(id)`
   被判定为无效并清空 —— 所以连**第一次**打开也留不住光标（主机回归测试修复前两次都是空）。

### 15.2 修法

> 本节是快速收集的**单点**修复；其根因已在 §16 统一解决（`ModalHost` 整个弹层改为 build 期构建），
> `capture.cj` 里「预先构造再 emit」的特例已删除。

- 输入框改为在 **build 阶段**构造（`buildQuickCapture` 里按 `open` 预建，弹层 body 只 `emit` 它），
  焦点 id 正常进入焦点图；
- `ShellHost` 监听 `ui.quickCaptureOpen` 的开关边沿（任何视图都可以直接写 store 打开弹层，不能只挂在
  shell 的 `openCapture()` 上），置一次性 `pendingFocus`：打开 → `capture-input`，关闭 → 打开前的
  `ctx.focusId`，空则回落到 `shell-nav-<当前路由>`；
- 零尺寸 `FocusRequestView` 在 `layout(ctx, rect)` 里消费一次请求；目标可能在稍后的 layout 才注册，
  因此最多重试 3 帧（`ctx.requestFrame()`），绝不每帧抢焦点；
- 删除 `TextField.autofocus()` 的会话闩锁用法。

### 15.3 真机证据（出货包）

- GTD「快速收集」按钮打开：输入框边框变成 accent 色并出现光标 ——
  `~/.cache/textura-device/final-focus2-zoom.png`（放大图）；
- 关闭后焦点回到打开前的控件/当前侧栏行（主机回归
  `quickCaptureFocusesItsInputOnEveryOpen` 断言 `shell-nav-dashboard`）；
- 视图直接写 store 打开弹层的路径由 `quickCaptureOpenedFromAViewFocusesItsInput` 覆盖。

---

## 16. 控件在 layout 阶段构造 → 焦点图里没有它（本轮全量修复）

### 16.1 症状与共同点

用户实测：快速收集、命令面板、GTD 澄清、SOP 检查器、甘特检查器、OKR 的输入框「点不进」，
顶栏搜索当时未确认。共同点不是控件、不是坐标，而是**控件被构造的时机**：

| 位置 | 构造时机 | 结果 |
|---|---|---|
| 顶栏搜索 | build（`buildTopBar`） | 正常（§10.3 已证） |
| 快速收集 / 命令面板 / GTD 澄清 / OKR 弹层 / 设置弹层 | **layout**（`ModalHost` 在 `layout` 里调 `body()`） | 焦点 id 不在焦点图 |
| SOP 检查器 | 从不（只有 `paintInputBox` 画出来的「输入框」） | 没有控件可点 |
| OKR 卡片 | **layout**（`PageCanvas.addChild` 在布局期造 `TextField`） | 焦点 id 不在焦点图 |
| 甘特检查器 | build（真实 `Ui.textInput`） | 本应正常，见 §16.5 |

根因链条（CUI）：`registerFocusable(id)` 只在**构建块内**生效（`third_party/CUI/src/core/ui_build.cj`）；
`TextField` 在 `layout` 阶段构造时 `activeStateStore == None`，登记被静默丢弃。点击时
`TextField.pressAt` 仍然调用 `ctx.focus(id)`，但 `focusTargetForKey(id)` 为 `None`，下一帧
`adoptFocusSnapshot → synchronizeFocusedTarget` 判定 id 无效并 `clearFocus()`：没有焦点环、
没有插入符、`applyTextInputAnchor()` 看到「无文本控件」于是 `stopTextInput()`，字符键回到应用，
所以也打不进字。

主机证据（修复前的 `clickOnCaptureInputFocusesIt` 手工排查）：点击输入框矩形后
`testHost.context.focusId == ""`；而「build 期构造 + `FocusRequestView` 自动聚焦」能留住光标。

### 16.2 修法 A：`ModalHost` 改为 build 期构建（一处修好所有弹层）

`textura.ui` 无法自己开一个嵌套构建块（`buildChild` 是 CUI 模块内的 `protected`），
因此弹层改成**两个协作节点**（`src/ui/modal.cj`、`src/ui/ui.cj` 的 `Ui.modal`）：

| 节点 | 作用 |
|---|---|
| `ModalHost`（零尺寸，`participatesInLayout=false` + `needsDetachedLayout`） | 量出面板矩形，注册**遮罩层**：scrim、圆角/阴影/描边、Esc、点遮罩关闭、Tab 焦点限制 |
| `Portal(owner, placement: frame.resolve)` | CUI 的公开浮层节点：body 在 **build 期**构建（控件因此正常登记焦点），按面板矩形布局、绘制在遮罩之上 |

`ModalFrame` 是两者的共享上下文：头部/正文/脚部分别测量，`min(自然高度, 80vh)` 决定面板高度，
正文用 `.flex()` 吃掉剩余高度并在超出时滚动 —— 视觉与几何和改造前逐项一致。
遮罩层先注册（z 序在下）、正文层后注册（在上），CUI 事件自顶向下派发：正文先收事件，
没消费的（Esc / 遮罩点击）才落到 `ModalHost`，页面永远收不到 —— 与「弹层阻断下层」语义一致。

影响面：`Ui.modal` 的全部调用点（快速收集、命令面板、快捷键弹层、GTD 澄清/选择/日期、
OKR 六个弹层、设置页四个弹层）一次性恢复可点击可输入，无需各自改动。

### 16.3 修法 B：画布视图改用统一编辑浮层 `Ui.prompt`

SOP 检查器与 OKR 卡片是自绘画布，布局在 `layout`/`draw` 阶段完成，行内控件天生拿不到焦点。
因此新增通用编辑器（`Ui.prompt`，`src/ui/ui.cj`）：标题 + 单行/多行 `TextField` + 取消/保存 +
Enter 提交 + Esc 取消 + 初值 + 校验错误。点击画布上的「输入框外观」打开它，提交写回 `ctx.store`。

**为什么用编辑浮层而不是内联输入框**：CUI 只在 build 阶段把控件登记进焦点图，画布的行内输入框
在 layout 阶段构造，点击后焦点下一帧被清空；浮层在 build 阶段声明，输入框就是普通可聚焦控件。

覆盖清单：

| 视图 | 字段 | 提交 |
|---|---|---|
| SOP | 流程名称、默认负责人（SOP 设置态） | `updateItem` title / `SopPatch.owner` |
| SOP | 步骤标题、负责人、预计耗时（分钟）、检查项文本、连线分支文案 | `updateItem` title / `SopPatch.owner` / `SopPatch.durationMin` / `SopPatch.checklist` / `updateEdge(label)` |
| OKR | 目标标题、KR 标题 | `updateItem` title |
| OKR | 指标 起点/当前/目标/单位 | `pendingMetricPatch` + `setMetric`（无法解析则留在浮层并提示） |
| OKR | 负责人、新增关键结果 | `OkrPatch.krOwner` / `createKeyItem`（默认信心 5） |
| 甘特 | 标题、开始/结束日期、进度 ±5% | 已是 build 期真实控件，保持不变 |
| 日历 | 快速添加输入框 | 已是 build 期真实控件，保持不变 |
| GTD | 澄清弹层各字段、日期弹层 | 走 `Ui.modal`，随修法 A 恢复 |

### 16.4 修法 C：焦点生命周期

- `textura.ui.FocusRequest` + `FocusOnceView`（`src/ui/focus.cj`）：打开编辑器时 `request(id)`，
  layout 里**一次性** `ctx.focus(id)`；第一帧无条件生效，之后只在「没有任何控件持有焦点」时重试
  （最多 3 帧），任何别的控件拿到焦点即视为用户接管、立即停止 —— 绝不每帧抢。
- 关闭时 `release()` 把焦点交还打开前的控件（`request` 时记下的 `ctx.focusId`）；没有则回落到
  调用方的兜底（shell 是 `shell-nav-<当前路由>`）。
- 弹层内 Tab 在正文的焦点停靠点之间循环（`ModalHost` 消费 Tab），不会跑到遮罩下面的页面。
- 输入法：CUI-P05 的「有插入符才 `startTextInput`」逻辑未改；因为焦点现在真的落到输入框，
  插入符会画出来，输入法随之打开。

### 16.5 回归门禁

- `src/shell/input_focus_test.cj::everyVisibleTextfieldFocusesWhenClicked`：遍历全部 7 条路由，
  从语义树里取出**每个** `TextField` 的矩形，逐个「移动+按下+抬起」，断言
  `ctx.focusId == 该 id`；并固定要求 `shell-search` / `gantt-title` / `calendar-quick-input`
  都在被枚举到的集合里（甘特检查器默认收起，测试会先打开并选中一行，避免「空集合绿灯」）。
- `paletteSearchFocusesWhenClicked`、`quickCaptureAutofocusesOnOpen`：命令面板点搜索框即聚焦；
  快速收集打开即聚焦、关闭回到侧栏行。
- `src/ui/prompt_test.cj`：`Ui.prompt` 打开即聚焦、Enter 保存、Esc 取消、Tab 后不抢回焦点。
- `src/views/sop/sop_prompt_test.cj`：检查器标题/耗时经浮层写回 store，空标题被拦下且浮层不关。
- 弹层叠层数从 1 变 2（遮罩 + 正文），`commandPaletteOpensOnCtrlKAndClosesOnEscape` 与
  `closedOverlaysLeaveNoLayerBehind` 已按新结构更新为 `+2 / 0`。

