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
| 事件流 | 前 800 个指针/键盘事件，CUI **Capture 阶段**在原树根记录：类型、`x/y`、**解码后的 button 与 `primary=`**、SDL 原始光标位、焦点/悬浮/按压 id、修饰键（上限 2026-10 由 200 提到 800，见 §26.4） | `ev#N …` |
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

---

## 17. 全控件可点击性：审计、加固与门禁（本轮）

§16 解决的是「输入框点不进」；本节解决「控件点不动」这一类同源问题，并把判据写成可复查的清单。

### 17.1 审计清单

逐路由的控件清单（类型 / 命中代码 file:line / 观测变化）落在 `docs/CLICK-AUDIT.md`：
侧栏、顶栏、命令面板、快速收集、GTD、OKR、日历、甘特、SOP、设置、仪表盘共 11 组、约 60 行条目，
每条标明 **[原生]**（CUI 内建）还是 **[自绘]**（Textura 画布 + hotspot）。清单由三条 grep 复跑：
`MouseDown(MouseButton.`、`addHotspot(`、`ButtonView(|IconButtonView(|SegmentedView(`。

### 17.2 通用加固：按钮码归一（`TEXTURA-CUI-P08`）

- 触摸后端把主键报成 `RawCode(0|1)`，CUI 内建控件只认 `Left`，于是「点不动但 hover 正常」。
  补丁在事件进入框架处（`cui.core.dispatchEventRecord`）**一次**归一 `RawCode(0|1) → Left`，
  内建与自绘控件共用同一判定；中间键/右键不变。
- 应用层仍统一走 `textura.ui.isPrimaryPointerButton`（`Left | RawCode(0) | RawCode(1)`），
  双保险；生产源码里 41 处 `MouseDown/MouseUp(MouseButton.Left` 直接匹配已全部替换。

### 17.3 抬手与命中矩形

- 抬手统一 `MouseUp(_, x, y)`：不再校验抬手事件的 button 字段，改由「按下时 `ctx.press(id)` +
  抬手落在同一矩形」触发，避免抬手码异常导致控件卡在按下态。
- 自绘控件的命中矩形在 layout/同帧 draw 计算并保存在控件实例；画布类（`PageCanvas`、
  `GanttBody`、`SopFrame`）每次 layout 刷新，`measure` 只做高度预演、不写回矩形。

### 17.4 源码门禁

`src/shell/pointer_gate_test.cj`：递归扫描 `src/` 下全部非测试 `.cj`，只要出现
`MouseDown(MouseButton.` 或 `MouseUp(MouseButton.` 就直接失败并打印 `文件:行号`；
另有一条用例钉住 `isPrimaryPointerButton` 的四种映射（`Left` / `RawCode(0)` / `RawCode(1)` 通过，
`RawCode(2)` 拒绝）。空扫描（根目录错、文件树读不到）也会失败，防止「零命中绿灯」。

### 17.5 主机回归（`src/shell/press_test.cj`）

| 用例 | 覆盖 | 断言 |
|---|---|---|
| `buttonPressCountsUnderEveryButtonCoding` | 自绘按钮 + 三种按钮码 | 三次主键各 +1 次点击，`RawCode(3)` 不触发 |
| `segmentedPressSelectsThePressedItem` | 自绘分段（按控件自身度量算命中点） | `RawCode(1)` 选中第 2 项，`Left` 回到第 1 项 |
| `dialogFooterButtonPressRunsThroughTheOverlay` | 弹层页脚按钮（overlay 派发 + 原生 `Button`） | `RawCode(0)` 抬手后回调执行一次 |

行选择由 `src/shell/sidebar_click_test.cj`（侧栏行按压 → 路由变化）覆盖；输入框由
`src/shell/input_focus_test.cj` 覆盖；浮层按钮的保存/取消语义由 `src/ui/prompt_test.cj` 覆盖。

### 17.6 真机矩阵

真机 8 项输入矩阵与「七路由 × 每路由 ≥3 控件」点击表见交付报告；本文件只记录可复跑的命令与
判据（截图 + `ev#` 里的 `focus`/`hover` 变化），不复制一次性截图路径。

---

## 18. 全屏 / 窗口缩放自适应（本轮）

### 18.1 症状与根因

真机上把窗口放大/全屏后，页面仍按启动时的尺寸排版：日历网格停在 900 高度、SOP 画布
不随窗口变高、甘特主体高度不变。根因在壳层：

```text
ShellHost.viewportWidth/Height   // 构造时捕获的 let（launch argv）
        ↓ 每帧
ViewContext(store, theme, today, viewportWidth, viewportHeight, …)
        ↓
calendarPageHeight(ctx.height) / SOP measure(windowHeight) / gantt pageBodyHeight(ctx.height)
```

窗口尺寸变化只更新了 `UiContext.viewportWidth/Height`（CUI `DesktopApp.stepFrame` 每帧从
`window.width/height` 拷贝），而 `ViewContext` 一直用构造时那一对旧值。

### 18.2 修法：每帧同步视口

- `ShellHost.viewportWidth/Height` 改为可变，新增 `syncViewport(width, height)`：值变化时
  返回 true，并对 0/负值夹到 1。
- 新增零尺寸 `ViewportSyncView`（`src/shell/appshell.cj`），声明在 shell 根 `ZStack` 里：
  `layout(ctx)` 把 `ctx.viewportWidth/Height` 写回 host；变化时 `ctx.requestFrame()`。
- `ViewContext` 在 build 阶段构造，所以**收到新尺寸的那一帧仍按旧尺寸画一次**，下一帧
  build 读到新值后所有页面重算。桌面连续 resize 无感；真机全屏切换会多一帧。
  > 更正（§19.5）：**「下一帧 build 会读到新值」这句当时是错的** —— 只更新字段不会让 CUI 的
  > build 作用域变脏，树根本不会重建。真正的补丁是 `viewportEpoch`（视口世代 + `buildShell`
  > 根依赖），见 §19。
- 视口来源：`UiContext.viewportWidth/Height`。OHOS 上 `SdlWindow` 创建后立刻
  `refreshSize()` 回读真实窗口（`third_party/cangjie-sdl/src/window.cj:153`），
  `SDL_EVENT_WINDOW_RESIZED` 时再次回读（`desktop_app.cj:829`）；XComponent surface 的
  尺寸就是窗口尺寸，因此**全屏时以 surface 为准**，启动参数只是请求值。
- 页面侧不需要新状态：`calendar.cj` 的 `calendarPageHeight(ctx.height)`、`sop.cj` 的
  `measure(windowHeight)`、`gantt.cj` 的 `pageBodyHeight(ctx.height)`、`gtd.cj` 的
  `pageWidth(ctx.width)` 都从每帧的 `ViewContext` 取值。

### 18.3 窄窗口断点（对齐 Web `@media`）

| 位置 | Web 规则 | 实现 |
|---|---|---|
| GTD 两栏 | `@media (max-width:1180px)` → 单列（gtd.css:941） | 页宽 < **892**（=1180−240−48）时单列；同时头栏动作组折到标题下方（避免「快速收集」被推出内容区） |
| GTD 流程条 | `@media (max-width:820px)` → 2 列 | 1024 视口仍 4 列（与 Web 一致），未改 |
| 设置两栏 | `@media (max-width:1180px)` → 单列（appshell.css:600） | `ctx.width ≤ 1180` 时 `VStack` 单列，两栏卡片内容由同一组闭包复用 |
| 甘特工具栏 | `@media (max-width:1180px)` 隐藏「已排期」、区间字号 12（gantt.css:1017） | `buildToolbar(compact:)`；1024 下三个右侧按钮不再越界 |
| 日历提示条 | `.cal-hint { flex-wrap: wrap }` | 放不下时正文折到第二行，`measure` 返回 2 行高 |
| SOP 检查器 | `.sop-inspector-body { overflow-y:auto }` | body 裁剪 + 滚轮滚动（`inspectorScroll`），字段不再画到运行历史卡上 |

### 18.4 两尺寸复核（Xvfb）

```bash
cd cangjie && source scripts/env.sh
./scripts/parity.sh --width 1440 --height 900 --out tools/parity/out-1440
./scripts/parity.sh --width 1024 --height 640 --out tools/parity/out-1024
```

`parity.sh` 本轮新增 `--width/--height`（默认仍是 1440×900，不影响门禁）。

| 检查项 | 1440×900 | 1024×640 |
|---|---|---|
| 侧栏宽度 | 240 | 240（`SIDEBAR_WIDTH`，未参与 flex） |
| 横向溢出 | 无 | 无（七个路由目视 + `narrow_layout_test` 断言语义矩形都在 1024 内） |
| 内容区宽度 | 1152 | 736（=1024−240−48） |
| 页面高度 | 由 `ctx.height` 推导（日历/SOP/甘特满高） | 同上，收到 640 后重算 |
| 1px 线 | 门禁 `ruleΔ ≤ 1.5px`，14/14 | 目视无错位/双线 |

结论：1024 下 GTD/设置折单列、甘特工具栏收紧、日历提示折行；SOP 检查器在 1024×640 下
需滚轮才能看到 Area 字段（与 Web `overflow-y:auto` 一致），不是裁切丢失。

### 18.5 两个选择器

**日历年 / 月**（`src/views/calendar/select.cj`）

- 年份列表 1900–2100（与 `calendarLogic.ts:352` 一致）。旧实现打开时固定从 1900 开始，看不到
  当年；现在 `calSelectInitialScroll` 把当前值滚到窗口中间，2026 打开即可见并高亮。
- 月份 1–12 完整：可见行数 12（旧值 8，九月–十二月不可见），弹层高 12×26+8=320px，
  下方放不下时自动翻到字段上方。
- 主机测试：`src/views/calendar/select_test.cj`（月份 12 项、年份 201 项、默认窗口含今年、
  点击年字段后 open 且窗口含 2026）。

**SOP 领域（Area）**（`src/views/sop/sop_area_picker.cj`）

- 点击检查器的 Area 字段 → Overlay 弹出「未指定」+ `workspace.areas`（带领域色点），
  下方放不下时翻到上方并夹在窗口内。
- Up/Down 移动、Enter/Space 写回、Esc/Tab 关闭、滚轮移动、点击浮层外关闭。
- 写回 `store.updateItem(..., withAreaId(...))`，画布节点与列表的颜色标记立即更新。

### 18.6 真机全屏复测（待用户执行）

设备逻辑视口实测 **1930×1020**（§2）。`uinput` 无法稳定拖动窗口边缘，因此全屏复测需要手工：

1. 打开应用 → 任何路由（建议 SOP）→ 把窗口拖到最大/全屏；
2. 检查：侧栏仍 240；内容区右边缘贴住窗口（无横向滚动条）；日历网格/SOP 画布/甘特主体
   随窗口变高；滚动条只出现在内容区；
3. 退出全屏恢复原尺寸，再检查页面高度回到原值（证明两个方向都重新排版）。

### 18.7 本轮真机构建与阻塞项

- 交叉编译：`scripts/harmony/build_ohos.sh` 成功（`ELF 64-bit LSB shared object, ARM aarch64`，
  `SDL_AppInit/AppEvent/AppIterate/AppQuit` 导出，NEEDED 闭包完整）。
- 打包（最终 HEAD 源）：`rm -rf /tmp/cj-harmony/cangjie/harmony/entry/build` → `stage_libs.sh` →
  `assemble_hap.sh --no-sync` → `entry-default-signed.hap`（29 947 308 B，
  sha256 `099d35b6d71cbcb7…`），**`STATUS: installable`**，签名 profile 的
  `bundle-name=com.ethancheung.textura` 且 `device-ids` 含本机 UDID。
- 安装：`hdc install -r …entry-default-signed.hap` → `install bundle successfully`。
- **启动被锁屏阻塞**：首次 `aa start` 返回
  `10106102 The device screen is locked during the application launch, unlock screen failed`；
  解锁尝试只唤醒了屏幕，`uitest dumpLayout` 显示 `bundleName=com.ohos.sceneboard`，锁屏文案
  「使用指纹或密码解锁」。第二次 `aa start` 返回 `start ability successfully.` 且
  `pidof com.ethancheung.textura` = 31459（进程已起），但前台仍是锁屏，**无法截图/注入点击**。
  因此本轮**没有**拿到 SOP 描述 / Area 下拉 / 日历选择器 / OKR 关联执行项的真机截图。

解锁后的复跑命令（设备一侧）：

```bash
HDC=~/deveco-cli-stable/command-line-tools/sdk/default/openharmony/toolchains/hdc
$HDC shell aa start -a EntryAbility -b com.ethancheung.textura
# 截图（后缀必须是 .jpeg；拿到后转 PNG 入库）
$HDC shell snapshot_display -i 0 -f /data/local/tmp/shot.jpeg
$HDC file recv /data/local/tmp/shot.jpeg cangjie/docs/assets/harmony/
```

需要补的 4 张截图：SOP 描述可编辑（SOP 设置 → 描述 → 浮层）、Area 下拉（列表含
「未指定/产品/运营/个人」）、日历年份/月份（2026 与 1–12 全量）、OKR 关联执行项（多行候选 +
勾选 + 确认后 KR 行出现该执行项）。

---

## 19. 全屏 / 窗口缩放：surface 尺寸与「树的重建」（本轮修复）

### 19.1 四跳链路（哪一跳断了，屏幕上都是「窗口大了、页面没变」）

窗口从「启动尺寸」变成「最大化尺寸」，要经过四跳才变成一次重排：

```text
① ArkTS 侧 XComponent 的布局尺寸
        ↓ (SDL 创建/重建 EGL surface；OPENHARMONY_SyncSurfaceSize() 只在 buffer 几何变化时重建)
② SDL_EVENT_WINDOW_RESIZED  →  cangjie-sdl SdlWindow.refreshSize()
        ↓ 每帧
③ UiContext.viewportWidth/Height（DesktopApp 从 window.width/height 拷贝）
        ↓  零尺寸 ViewportSyncView（src/shell/appshell.cj）→ syncViewport() 写 epoch
④ ShellHost.viewportEpoch（CUI State）→ buildShell 根读它 → 树按新尺寸**重新描述**
        ↓
   ViewContext.width/height → 各页面重算高度/列宽
```

- ①② 是上一轮修的（§19.2/19.3：XComponent `width/height: 100%`）；
- ③ 是再上一轮修的（§18.2：`ViewportSyncView` + `syncViewport`）；
- ④ 是本轮加固的（§19.5）：**只更新字段不会让 CUI 重跑 build**，树会一直带着旧
  `ViewContext`，屏幕上就是「背景铺满（surface 大了）、内容仍按旧尺寸贴在左上、右下留白」。

### 19.2 根因：XComponent 没有跟着父容器长

```ts
Row().height('100%') {
  Column().width('100%') {          // ← 缺 height('100%')：Column 按内容（首帧 surface）定高
    XComponent({...}).id(...)       // ← 缺 width/height：surface 按启动请求建立一次
  }
}
```

→ surface 首帧按启动尺寸建立后**不再随窗口增长**；`OPENHARMONY_SyncSurfaceSize()` 读到的 buffer
几何没变，于是既不发 `WINDOW_RESIZED`，③ 也没有新值可拷。屏幕上的表现就是「窗口变大了，页面
还按启动尺寸排版」。

### 19.3 修法（`harmony/entry/src/main/ets/pages/Index.ets`）

```ts
Row() {
  Column() {
    XComponent({...}).id(SURFACE_ID)
      .width('100%').height('100%')   // ← 新增：surface 跟随窗口
      .focusable(true).defaultFocus(true).focusOnTouch(true)   // 原样保留
      .onFocus(...).onBlur(...)                               // 原样保留
  }.width('100%').height('100%')      // ← 新增 height
}.width('100%').height('100%')
  .onKeyEvent(...)                    // 原样保留（Tab 转发，§10.5/§10.6）
```

只动尺寸；`id`、`libraryname: 'SDL3'`、`type: SURFACE`、三个 focus 属性、`onKeyEvent` 全部保留。

### 19.4 诊断证据：`build#` 行与 `size` 行（`PROBE_COMPILED_ON=true` 的包）

两类行（口径见 `harmony/host/src/probe.cj`）。`size` 每秒一行，看整体；`build#` 只在「树的尺寸或
epoch 变了」时打一行，是事件证据：

```text
t=67   ctx first-frame vp=1930.000000x1021.000000 scale=1.000000 font=1.000000 driver=opengles2 super=1 …
t=111  build#2 size=1930x1021 epoch=1 viewport=1930x1021
t=111  size w=1930.000000 h=1021.000000 scale=1.000000 changes=0 viewport=1930x1021 built=1930x1021 epoch=1 builds=2
```

| 字段 | 含义 |
|---|---|
| `build#N` | 本次会话 `buildShell` 描述过树的总次数（`ShellHost.buildCount`） |
| `size=WxH` | **已提交的树**是按什么尺寸描述的（`ViewContext.width/height`，`ShellHost.builtViewport*`） |
| `epoch=` | 视口世代（`ShellHost.viewportEpoch`），每次真实 resize +1 |
| `viewport=WxH` | 宿主采纳的视口（`syncViewport` 的结果，布局数学的输入） |
| `w/h`、`changes` | 驱动此刻报的逻辑尺寸，以及本会话见过的不同尺寸个数（`0` = 启动后还没 resize 过） |

判据（缺一不可）：

| 现象 | 结论 |
|---|---|
| 最大化后 `w/h` 变大、`changes` 0→1 | ① ArkTS/surface 与 ② SDL 采纳都通了（否则看 §19.7） |
| `epoch` +1、`build#N` 变大 | ③→④ 通了：**树真的按新尺寸重建了**（不是只重排） |
| `size` == `viewport` | 这一帧的树已经用新尺寸描述完（`size` 落后 = 还差一帧，或重建根本没发生） |

本轮真机实测（诊断包，`t=111` 是启动第一帧）：`epoch` 从 0 变 1、`build#2`、`size == viewport`。
即启动时窗口尺寸（1440×900 请求 → 1930×1021 实际 surface）就走过一次「视口变化 → 重建」，说明
③→④ 这一跳在真机上是通的；`changes=0` 是因为启动后还没有第二次尺寸变化。

### 19.5 第四跳：视口 epoch（本轮加固，§18.2 的补丁不够）

`ViewportSyncView` + `syncViewport` 只做了「把 `ctx.viewportWidth/Height` 写进 host 字段 + 请求一帧」。
`ViewContext` 在 **build** 阶段构造，而 CUI 的增量引擎只在**被读过的 `State` 变化**时重跑 build
作用域；窗口尺寸变化既不脏任何 `State`，也不会让 build 重跑 —— 于是布局用新视口重排、页面高度却仍是
`ViewContext` 里的旧值。这和 §5（store → CUI 缺响应式桥）是同一种断法。

现在：

- `ShellHost.viewportEpoch: State<Int64>`，`syncViewport` 在尺寸真的变化时 +1；
- `buildShell` 的**最外层第一件事**读 `host.viewportToken()`，建立 build 依赖（和 store 的
  `revisionToken()` 并排）；
- `ViewportSyncView.layout` 写 epoch 后，CUI 的稳定化循环（`buildAndLayoutStable`）发现世代变了，
  **同一帧内**再描述一次树，第二遍读到新视口、写完即稳定（`MAX_STABILIZATION_PASSES=3`）；
- `host.noteBuild()` 在 `ViewContext` 构造处调用（内容区 fragment 内），记录
  `builtViewportWidth/Height` 与 `buildCount` —— 它是「这棵树是按什么尺寸描述的」的唯一证据，
  也是主机测试与探针共用的数字。

主机侧证据（`src/shell/viewport_test.cj`）：

| 用例 | 断言 |
|---|---|
| `windowResizedEventRebuildsTheShellForTheNewSize` | 注入 `UiEvent.WindowResized(2880,1620)` → `epoch` 0→1、`builtViewport` 2880×1620、`buildCount` 增长；同尺寸空闲帧**不再**重建；缩回 1440×900 → `epoch`=2 |
| `everyRouteUsesTheMaximisedWindow` | 七路由在 2880×1620 下都有节点越过启动窗口（1930×1020）的右边界，且无节点越出新窗口 |
| `shrinkingAfterAMaximisedWindowKeepsEveryRouteInside`（`narrow_layout_test.cj`） | 从 2880×1620 缩回 1024×640：`builtViewport` = 1024×640，七路由仍无横向溢出 |
| `windowResizeRebuildsTheViewsForTheNewHeight` | 1920×1200 / 1024×640 两个方向都重算页面高度 |

Xvfb 复核：`./scripts/parity.sh --width 2880 --height 1620 --out tools/parity/out-2880`（不入库）——
日历网格、甘特主体、SOP 画布都铺到右/下边缘（保留 24 内边距）；GTD 页按 Web `shell.css:262`
的 `.page { max-width: 1280px; margin: 0 auto }` 居中收窄，这是**参考实现的既有行为**，不是留白 bug。

### 19.6 仍需用户执行的一次最大化（本轮交付停在这里）

> 后续：这一跳的缺环已被定位为「ArkUI 从未把新尺寸告诉 SDL」，修法与真机数字见 **§24**（本节保留原始现场）。

诊断包已装（`PROBE_COMPILED_ON=true`，`entry-default-signed.hap` 30004675 B，
sha256 `062e10f1…`，`21423` 首次安装后 `pidof` 有值、`diag.log` 已开始写）。当前窗口是启动尺寸
1930×1021（`hidumper -s WindowManagerService -a '-a'` 里 `textura0` 一行），所以：

1. 解锁设备，把 Textura 窗口最大化/全屏（`uinput`/`uitest` 拖不动窗口边缘，只能手工）；
2. 读日志：

   ```bash
   HDC=~/deveco-cli-stable/command-line-tools/sdk/default/openharmony/toolchains/hdc
   $HDC shell "grep -E 'build#|size ' /data/app/el2/100/base/com.ethancheung.textura/files/textura/diag.log | tail -8"
   ```

3. 期望看到：`w/h` 变大、`changes` 0→1、`epoch` +1、`build#N` 变大、`size == viewport`；
   - `w/h` 没变、`changes=0` → 回到 §19.7（buffer 尺寸对照）；
   - `w/h` 变了、`build#` 与 `epoch` 没变 → 回到 §19.5（重建没发生，这是本轮要排除的）；
4. 目视：侧栏 240；内容区右/下贴边（GTD 居中收窄属正常）；缩回后页面高度回到原值。

### 19.7 若 `size` 仍不变：拿 buffer 尺寸和探针对照

```bash
HDC=~/deveco-cli-stable/command-line-tools/sdk/default/openharmony/toolchains/hdc
# 应用必须在前台（锁屏时既没有它的 surface，也没有截图）
$HDC shell hidumper -s RenderService -a 'surface' | grep -E "default-size|name ="
```

- 打印里 `default-size = [WxH]` 就是 **RenderService 侧 buffer 的像素尺寸**；
- 与探针 `size w=… h=…`（逻辑 px）按 `scale` 换算后比较：
  - **两者一致**、但 `w/h` 停在启动尺寸 → buffer 确实没变，问题在 ArkTS 布局（回到 19.3）；
  - **buffer 变大了、探针 `w/h` 没变** → SDL 采纳逻辑没跟上（`OPENHARMONY_SyncSurfaceSize()` 认为
    已同步）：这时才需要在 vendored SDL 侧打最小补丁，并在 `third_party/README.md` 登记。
- 旁证不用另开探针：SDL 补丁自己会 `SDL_Log` 一行（走 hilog）

  ```text
  PixCap surface sync: adopted surface size 2880x1620 px (window was 1930x1021)
  ```

  有这行 = ② 采纳成功；没有这行 = buffer 几何没被认出来。

### 19.8 签名：每轮设备构建前要重新指一次材料

仓库里提交的 `harmony/build-profile.json5` 指向**参考项目**的调试材料（`com.ethancheung.pixcapt`），
hvigor 会以 `00303074` 拒绝为本 bundle 签名，于是 `assemble_hap.sh` 回落 unsigned，而设备拒收
unsigned（`code:9568320 error: no signature file`）。本机的 Textura 材料在
`cangjie/harmony/.certs/textura-debug/`（gitignore，只在本地），每轮设备构建先跑一次：

```bash
cd cangjie
C=$PWD/harmony/.certs/textura-debug
PW="$(cat harmony/.certs/textura-debug/password.txt)"
./scripts/harmony/set_signing_material.sh \
  --store-file "$C/textura-debug.p12" --key-alias textura-debug \
  --cert "$C/TexturaDebug.cer" --profile "$C/TexturaProfileDebug.p7b" \
  --store-password "$PW" --key-password "$PW"
./scripts/harmony/assemble_hap.sh          # 必须带 sync：脚本读的是快照里的 build-profile.json5
```

`--store-file` 等必须是**绝对路径**（相对路径 hvigor 报 `00303107 Invalid storeFile`）。

### 19.9 主机回归数字

- `cjpm test`（整树）：除一条**既有**偶发崩溃外全绿；崩溃与本节无关，先记在这里：打包成
  1 s 级别的 `textura.shell` 套件里，`commandPaletteOpensOnCtrlKAndClosesOnEscape` 偶发
  `SIGSEGV`（GC 栈扫描栈帧时崩在 `textura.views.sop.logic.dgBarycenter`
  `dagre_layout.cj:1005`）。`git stash` 掉本轮改动后 **2/6** 复现，本轮改动后 **4/10**，
  属同一条既有问题（SOP 布局 + GC），不是 resize 改动引入的。
- `./scripts/parity.sh --theme both` + `./scripts/diff.sh --theme both`：**14/14 PASS**
  （窗口尺寸变化不影响 1440×900 基线）。

---

## 20. 原位编辑器：不再「下方又冒出一个一样的框」

### 20.1 症状与三个独立成因

用户在 SOP/OKR/GTD 里点一个字段，看到的是**两个框**：原位旧字段（画布画的）与叠加的真控件，而且
控件常常比画上去的盒子低一截、甚至大一圈。本轮定位到三个互不相干的原因，缺一不可：

| # | 成因 | 现象 |
|---|---|---|
| A | 焦点请求没被**武装**（`FocusRequest.request(key)` 没人调） | 点进去没有光标、打不进字、IME 锚点为空 → 4 条主机测试红 |
| B | 同一个控件被**发射两次** | 第二个副本排在第一个下面 → 直接就是「下面又冒出一个一样的框」 |
| C | 编辑器盒子 ≠ 画上去的盒子（高度分档/外层容器居中） | 两层文字 + 双边框，控件盖不住原字段 |

**B 的机理**（最隐蔽，`src/ui/ui.cj` 的 `Ui.prompt` / `Ui.inlineEditor`、`okr_dialogs.cj` 的搜索框
都踩过）：`style()` / `placeholder()` / `onSubmit()` 是控件自己的 setter（返回同一个控件、不发射
节点），而 `textStyle()` / `height()` / `width()` / `flex()` 是 **widget 修饰器**——每次调用都
`applyModifier(child, op)`，把一个包装节点**替换**父列表里的那个 child。于是：

```cangjie
let editor = TextField(draft, key: Some(key))   // 发射 1：TextField
editor.style(...)                                // setter，不发射
editor.textStyle(...)                            // 修饰器 → 替换成 M1（1 个 child）
editor.height(34.0)                              // 仍作用在**原来的** editor 上：
                                                 //   M1 已经在父列表里，替换失败 → **再追加一个 M2**
```

最终 portal 里是 `Stack(Vertical)[M1, M2]`：两个**同一个** `TextField`（同 id、同状态），第二个
排在第一个下面 46px（= 第一份的自然高度）。修法只有一条：**链在上一次调用的返回值上**
（`editor.textStyle(...).height(34.0)`），或者 `var w = ...; w = w.height(...)`。

**C 的机理**：`fieldHeight()` 以前对多行字段强制 `≥ 92`，而检查器画的描述区是 92、检查项行只有
30；再加上编辑器外面套了一层 `VStack(hug)`，它给的内容高度比字段大 76px 并把字段居中，于是控件
整体下移 38px。现在的规则：

```text
anchor.h <  40                      → 单行高度（下限 28），不按多行撑高
multiline && anchor.h >= 40         → 用字段自身高度，最多 40vh（窗口太矮时才截）
其余                                 → 字段自身高度（下限 28）
```

并且 portal 的 body 直接是控件本身（不套 `VStack`），所以 `bounds == rect`。

### 20.2 编辑态不再绘制原字段

`editing` 为真时画布只留**背景**（位置/圆角不变），文字、边框、拖拽把手都交给真控件：

| 视图 | 字段 | 判据 |
|---|---|---|
| SOP 检查器（设置） | 名称 / 描述 / 默认负责人 | `sopFieldEditing(state, SopTitle/SopNotes/SopOwner)` |
| SOP 检查器（节点） | 标题 / 描述 / 负责人 / 预计耗时 / 检查项文本 | `NodeTitle/NodeNotes/NodeOwner/NodeDuration/CheckText` |
| SOP 检查器（连线） | 分支文案 | `EdgeLabel` |
| OKR 卡片 | 目标标题 / KR 标题 / 指标（起点·当前·目标·单位）/ 负责人 / 新增 KR | `okrFieldEditing(ui, kind, target, field:)` |
| GTD 行 | 截止日期盒 / `@场景` 盒 | `editing:` 参数（`gtd_next.cj` 传 `dateTarget/sceneTarget`） |

甘特检查器（标题/开始/结束/进度）、顶栏搜索、命令面板、快速收集**本来就是 build 期真控件**
（`Ui.textInput` / `TextField`），不叠 `Ui.inlineEditor`；本轮复查了全部 `Ui.inlineEditor` 调用点
（SOP/OKR/GTD 日期/GTD 场景共 4 处），没有误包。

### 20.3 门禁（`src/ui/inline_editor_test.cj`）

- 首帧聚焦、Enter 提交、Esc 取消、点外部提交、点字段内不结束；
- 插入符锚点落在字段内，且随输入右移（IME 候选窗跟着走，§21）；
- **几何**：`inlineEditorCoversTheFieldRectangle` 逐字段断言语义节点 bounds == 传入矩形
  （34px 单行 / 滚动后的 y / 92px 描述区 / 30px 检查项行）；
- **分档**：`inlineEditorKeepsAFieldAtItsOwnHeight` 断言 18→28、30→30（多行也不撑）、120→120。

`Ui.inlineEditor` 的焦点请求由**调用方**武装（`state.promptFocus.request(SOP_PROMPT_INPUT)`），
组件本身不重新武装——否则用户 Tab 走之后每帧都会把光标拽回来（与 `promptTabDoesNotSnapBackToTheEditor`
同一条约束）。

---

## 21. IME 候选窗跟随插入符（`TextConfig.cursorInfo` 桥）

系统输入法把候选条按 `TextConfig.cursorInfo`（**物理屏幕绝对坐标，单位 px**）摆放，而 SDL 的
openharmony 视频后端没有 `SetTextInputArea` 实现：CUI 每帧算好的 `UiContext.textInputAnchorRect`
经 `SDL_SetTextInputArea` 发出去是空操作，候选条就停在系统自己决定的位置（§10.3 的现场）。

链路（三处，各自只做一件事）：

1. **宿主**：`textura_ime_anchor(index)` 导出当前聚焦控件的插入符矩形（逻辑 px），
   `harmony/host/src/main.cj` 每帧更新；
2. **C 桥**：`entry/src/main/cpp/textura_keys.c` 的 `getImeAnchor()` 用 `dlsym` 取符号（不引入
   链接期依赖），越界/无锚点返回 `null`；
3. **ArkTS**：`Index.ets` 每 120ms 读一次，换算成屏幕 px（`windowRect.left/top` + `densityPixels`），
   矩形**变了才**重新 `controller.attach(true, {inputAttribute, cursorInfo})`——系统只在 attach 时
   读取光标位置，所以「跟随」= 重新 attach；矩形没变时零成本。

判据：光标在字段里左右移动时，候选条跟着走；`TextInputState.attached` 为假时整条链路直接返回
（没有输入框就没有锚点）。

---

## 22. 图标：三件套的生成与核对（本轮）

构图取自 Linux 版 `scripts/make_icon.py`（深墨圆角块 + 5×5 淡网格 + 四角纸白节点 + 中心陶土橙
节点与两条斜线），HarmonyOS 侧只做平台化拆分：`background` 满幅 `#201D1A`、`foreground` 透明底
且标记缩到 66% 居中、`startIcon` 是圆角块 + 标记的合成图。生成器与规则见 `docs/HARMONY.md` §5.6，
这里只记**核对方法**（图标是安装期资源，光看仓库文件不算验证）：

```bash
# 1) 三件套的尺寸/模式
python3 -c "from PIL import Image;[print(p, Image.open(p).size, Image.open(p).mode) for p in [
 'harmony/AppScope/resources/base/media/background.png',
 'harmony/AppScope/resources/base/media/foreground.png',
 'harmony/entry/src/main/resources/base/media/startIcon.png']]"

# 2) 打包后是否真的进了 HAP（背景/前景会被资源编译器降到 512×512，像素内容一致）
unzip -p harmony/out/entry-default-signed.hap resources/base/media/foreground.png > /tmp/fg.png
python3 -c "from PIL import Image;print(Image.open('/tmp/fg.png').size)"

# 3) 设备上肉眼确认（卸载重装才会刷新桌面缓存）
$HDC uninstall com.ethancheung.textura && $HDC install -r harmony/out/entry-default-signed.hap
$HDC shell snapshot_display -i 0 -f /data/local/tmp/shot.jpeg   # 桌面/任务栏
```

本轮实测：三张源图均 `1024×1024 RGBA`；HAP 内 `startIcon.png` 与源文件**逐字节相同**，
`background/foreground` 被降到 `512×512`（内容等比缩放，见上）。桌面图标的肉眼确认**需要设备
已解锁**（本轮设备停在锁屏，截图只有时钟），见 §23 的用户待办。

---

## 23. 本轮（surface / 原位编辑器 / 图标）的真机状态与待办

本轮完成的真机动作（设备 `192.168.0.3:36773`，HarmonyOS 26 / API 26）：

| 步骤 | 结果 |
|---|---|
| 诊断包（`PROBE_COMPILED_ON=true`）交叉编译 + 打包 | `entry-default-signed.hap` 30001437 B，sha256 `30555f26…`，`STATUS: installable` |
| `hdc uninstall` → `install -r` → `aa start` | `uninstall bundle successfully` / `install bundle successfully` / `start ability successfully`，`pidof` = 41951 |
| `diag.log` 的 `size` 行 | **存在**，每秒一行（§19.4 的样例）；`changes=0`（尚未发生 resize） |
| 出货包（`PROBE_COMPILED_ON=false`，含最终图标与编辑器修复） | `entry-default-signed.hap` 30005415 B，sha256 `7b2855e1…`，卸载重装后 `pidof` = 53329，沙箱里**没有** `diag.log`（探针确实关闭） |
| 图标三件套进包 | `startIcon.png` 逐字节一致；`background/foreground` 被资源编译器降到 512×512，内容为源图的精确 0.5 缩放（中心像素与 alpha 边界等比，见 §22） |

**本轮没做到的两件事，原因都是设备停在锁屏**（`power-shell wakeup` 只唤醒屏幕，界面仍是时钟）：

1. **最大化一次、看 `size` 行的 `changes` / `w/h` 是否变化**——`uinput` 拖不动窗口边缘，只能手工
   （修法与自动化的替代手段见 §24.2 / §24.5）；
2. **桌面/任务栏图标的肉眼确认**——锁屏期间 `snapshot_display` 只有锁屏时钟，
   `hidumper -s RenderService -a 'surface'` 也看不到应用的 surface（前台才有）。

解锁后按顺序做（两步都只需一次）：

```bash
HDC=~/deveco-cli-stable/command-line-tools/sdk/default/openharmony/toolchains/hdc
$HDC shell aa start -a EntryAbility -b com.ethancheung.textura
# ① 图标：桌面看一眼是否变成「深墨圆角块 + 网格 + 陶土橙节点」
$HDC shell snapshot_display -i 0 -f /data/local/tmp/icon.jpeg
# ② 最大化窗口一次，然后确认 size 行的 w/h 变大、changes 变 1
#    （诊断包才有 diag.log：把 probe.cj 的 PROBE_COMPILED_ON 改回 true 重出包）
$HDC shell "cat /data/app/el2/100/base/com.ethancheung.textura/files/textura/diag.log | grep size | tail -5"
```

---

## 24. ArkUI 主动推送：窗口尺寸与屏幕密度（本轮）

> 任务书里把这一节叫「§20」，但 §20 已被「原位编辑器」占用（§20.1–§20.3），所以追加为 **§24**；
> 引用点（§19.6、§23）已就地指向本节。

### 24.1 断点定位：第五跳（页面 → SDL）从来没有存在过

§19 的四跳（XComponent 尺寸 → SDL surface → CUI 视口 → 树重建）在启动时是通的：首帧
`build#2 size=1930x1020 epoch=1`。但**最大化窗口**这条路里没有任何一跳是「ArkUI 把新尺寸告诉 SDL」——
ArkUI 只改自己的布局，SDL 的 openharmony 视频后端在**建窗时**采纳一次 surface 尺寸后就不再采纳后来的变化
（`window->w/h` 只能由 `SDL_SetWindowSize` 或驱动回调写）。于是探针永远是启动尺寸：

```text
t=62   ctx first-frame vp=1930.000000x1020.000000 scale=1.000000 font=1.000000 driver=opengles2 …
t=111  build#2 size=1930x1020 epoch=1 viewport=1930x1020
t=12293 size w=1930.000000 h=1020.000000 scale=1.000000 changes=0 viewport=1930x1020 built=1930x1020 epoch=1 builds=2
```

同一时刻窗口管理器里的窗口是 `textura0 [ 0 0 2880 1620 ]`（`hidumper -s WindowManagerService -a '-a'`），
即**窗口 2880×1620、SDL 认为 1930×1020**，屏幕上就是「内容贴左上、右/下空白」。用户看到的大片空白不是布局
`max-width` 造成的，是 surface 比窗口小。

同一条日志还暴露出第二个断点：`scale=1.000000`。这台机器 `display.getDefaultDisplaySync().densityPixels = 1.75`，
而 openharmony 后端报 pixel density 1.0，于是 CUI 把 **像素当逻辑单位**排版，1.75× 屏上所有控件与字号都偏小。

### 24.2 修法：页面测量，宿主在自己的线程上应用

链路（五个位置，每个只做一件事）：

```text
XComponent.onAreaChange(area)                       ets/pages/Index.ets
   ├─ vp2px(area) ──32ms 去抖──► setSurfaceSize(pxW, pxH)      ─┐
   └─ display.getDefaultDisplaySync().densityPixels ───────────┤  libtextura_keys.so（NAPI，textura_keys.c）
                                                               │  只写两个标量，不调用 SDL
                                                               ▼
                          textura_push_surface_size / textura_push_display_density   harmony/host/src/display_push.cj
                                                               │  （@C 导出，NAPI 侧 dlsym，与 §21 同套路）
                                                               ▼
                          applyDisplayPush(app)  ← 每帧 SDL_AppIterate 开头（帧线程！）
                                                               ▼
                          DesktopApp.applyHostWindow(pxW, pxH, density)   CUI-P09
                                                               ▼
              setDisplayScaleOverride(density)  →  scale = userScale×density, pixelDensity = 1
              setSizeInPixels(pxW, pxH)          →  SDL_SetWindowSize + refreshSize   SDL-P01
                                                               ▼
                         window.width/height = 像素 / 密度  →  CUI 视口 → epoch → 树重建（§19.5）
```

为什么不让 NAPI 直接调 `SDL_SetWindowSize`：NAPI 调用落在 ArkUI 线程，而 SDL 的视频子系统只允许帧线程
访问（跨线程改窗口会跟事件泵抢状态）。所以 C 桥只写标量，真正碰 SDL 的是 `SDL_AppIterate`。

为什么密度先于尺寸：逻辑尺寸 = 像素 ÷ 密度，密度装晚了会用旧比例算一遍、再重排一遍。

密度公式（`queryWindowDisplayMetrics` 的覆盖分支）：

| 量 | 覆盖前（后端值） | 覆盖后 |
|---|---|---|
| `scale`（逻辑 = 像素/scale） | 1.0 | `userScale × density` = 1.75 |
| `pixelDensity` | 1.0 | 1.0（保持 1，使 `UiContext.displayScale = scale × pixelDensity = density`） |
| `renderScale`（绘制放大） | 1.0 | 1.75 |
| 逻辑窗口尺寸 | 像素值本身 | 像素 / 1.75 |

`density <= 0` 不进覆盖分支 ⇒ 桌面构建与 1440×900 基线逐像素不变。

### 24.3 去抖与防回环

`onAreaChange` 每一轮布局都会触发（窗口拖拽时每帧一次），而每次采纳都会让 SDL 改窗口、发 resize、再重排，
再触发 `onAreaChange`。三层闸门：

1. **页面**：面积（vp）与上次相同直接返回；变化则记 pending 并**重置 32ms 定时器**，一串布局只推一次
   （`SURFACE_PUSH_DEBOUNCE_MS`）；
2. **页面**：像素尺寸与上次**被宿主接受**的值相同不推（被拒的推送不记账，下次布局变化会重试）；
3. **宿主**：`DisplayPushLog.accept()` 比较像素尺寸与「密度千分位」，相同返回 `None`；
4. **SDL 侧**：`setSizeInPixels` 发现 `SDL_GetWindowSize` 已经是目标值就跳过 `SDL_SetWindowSize`，
   但**总是**回读一次尺寸（后端可能自己采纳过，缓存必须跟上）。

### 24.4 密度生效证据（真机，`192.168.0.3:36773`，窗口 1930×1085 px）

```text
t=79   ctx first-frame vp=1930.000000x1020.000000 scale=1.000000 font=1.000000 driver=opengles2 super=1
t=117  push size=1930x1020 density=1750per1000 logical=1103x583
t=230  build#3 size=1102x582 epoch=2 viewport=1102x582
t=1115 size w=1102.000000 h=582.000000 scale=1.750000 changes=1 viewport=1102x582 built=1102x582 epoch=2 builds=3
```

- `scale` 1.0 → **1.75**：密度真的进了 CUI；
- `w/h` 1930×1020 → **1102×582**（= 1930÷1.75、1020÷1.75）：布局改用密度无关单位；
- `changes` 0 → **1**、`epoch` 1 → **2**、`builds` 2 → **3**、`size == viewport`：**树按新尺寸重建了**，
  不是只重排（§19.5 的判据）；
- 同时解释了一个旧 bug：IME 候选窗定位（§21）把逻辑 px × `densityPixels`，在 `scale=1` 时这是错的
  （同一坐标被放大了 1.75×），现在逻辑单位与密度自洽，锚点换算正确。

### 24.5 尺寸推送的真机验证：一半已证，一半待解锁

本轮用临时钩子（**已从提交源码移除**）在 `aboutToAppear` 里调用 `window.resize(1600, 900)` / `window.resize(1100, 582)`，
让真机自己制造一次真实的 surface 变化，读数如下：

```text
t=4099  push size=1600x835 density=1750per1000 logical=914x477
t=4121  size w=1102.000000 h=582.000000 scale=1.750000 changes=1 viewport=1102x582 built=1102x582 epoch=2 builds=3
t=12131 push size=1100x517 density=1750per1000 logical=629x295
```

**已证**：`window.resize` 改窗口 → XComponent 面积真的跟着变（1600×835、1100×517 px，扣掉 65px 标题栏）
→ `onAreaChange` → 32ms 去抖 → NAPI → 宿主 → `applyHostWindow` 全部走通（`push` 行就是宿主收到并采纳的
记录）。顺带确认 `window.resize()` 在这台机器上按**像素**而非 vp 生效。

**未证**：`size w/h` 没有跟着变，说明 `SDL_SetWindowSize` 之后 `SDL_GetWindowSize` 仍报旧值。两种可能，
新加的 `adopted=` 字段就是用来分开它们的（诊断包已装）：

| `push` 行 | 结论 |
|---|---|
| `adopted=915x478`（≈ 新像素÷1.75） | SDL **采纳了**，只是旧代码的「相同尺寸短路」没回读缓存 —— 已经在 `setSizeInPixels` 里改成总是回读，重跑即修好 |
| `adopted=1102x582`（旧值） | 后端拒绝了 `SDL_SetWindowSize`；此时改用「只写 `window->w/h` + 发 `SDL_EVENT_WINDOW_RESIZED`」的兜底路径（`SDL_SyncWindow`/驱动回调，需要新增一个 cangjie-sdl 内部入口） |

设备当前**停在锁屏**（`SCBScreenLock13` 可见），`aa start` 被系统拒绝：
`10106102 The device screen is locked during the application launch`（开发模式下不允许自动解锁），
所以这一段只能等用户解锁后跑一次。解锁后**不需要手工最大化**：装着的诊断包会在启动 4s / 12s 各做一次
自动 resize，日志直接给出结论；想再看最大化，就手工最大化一次，读同一批行。

```bash
HDC=~/deveco-cli-stable/command-line-tools/sdk/default/openharmony/toolchains/hdc
# 1) 解锁后启动（诊断包：entry-probe-signed.hap，probe 编译开启）
$HDC shell aa start -a EntryAbility -b com.ethancheung.textura
sleep 20
$HDC shell "grep -E 'push|build#|size ' /data/app/el2/100/base/com.ethancheung.textura/files/textura/diag.log | tail -12"
# 2) 期望：push size 随窗口变、adopted 等于 push÷density、size/epoch/build# 跟着变
# 3) 看完换回出货包（probe 关闭、无自动 resize）
$HDC install -r cangjie/harmony/out/entry-default-signed.hap
```

### 24.6 输入坐标映射

不变式：**CUI 的坐标始终是逻辑单位，进入 SDL 时才乘 `scale`。** 密度改动只改 `scale`，所以：

- 鼠标：`window.cj` 的 `scaleEventRecord` 用 `scale` 把 SDL 的窗口像素坐标除成逻辑坐标，和布局同一套单位；
  探针的 `ev# … mouse=… raw=…` 两列在密度生效后仍应成 1.75 倍关系（`raw/mouse = 1.75`），成 1.0 就说明
  有一条路径没走统一的 `scale`；
- 窗口尺寸：`SDL_GetWindowSize`（像素）÷ `scale` = 逻辑宽高，和 `ctx.viewportWidth` 同源，不存在第二套换算；
- 真机复核办法（解锁后）：注入点击侧栏第 2/3 项能切路由，点搜索框能聚焦——若坐标错位，先看 `raw` 与
  `mouse` 的比例再查 `scale`。

### 24.7 主机门禁与两尺寸布局复核

`src/shell/display_push_test.cj`（新增，7 例）：

| 用例 | 断言 |
|---|---|
| `densityOneKeepsTheViewportInPixels` | 密度 1.0 时 1440/900/2880 逐像素不变（基线的护栏） |
| `densityShrinksTheLogicalViewportProportionally` | 2880×1620 @1.125 → 2560×1440；@1.5/@2.0 同样按比例；1930@1.5 → 1287 |
| `degenerateDensityAndSizeFallBackToPixels` | 密度 0/负/NaN 不做除法；像素 0 → 逻辑 1（不塌） |
| `pushIsAppliedOnceAndOnlyWhenItChanges` | 首次采纳；重复不采纳；只改尺寸、只改密度各采纳一次；缩回起点也采纳 |
| `repeatedDensityIsComparedInThousandths` | 1.125 与 1.1250001 视为相同；1.126 算变化 |
| `unusablePushesAreIgnoredInsteadOfCollapsingTheWindow` | 0×0 / 负尺寸 / 0 密度 / NaN 都不采纳，且不污染后续比较 |
| `everyRouteFillsTheDensityScaledExternalScreen` | 七路由在 2560×1440（2880×1620 @1.125）下无越界，且有节点越过启动窗口的 1930 边界 |

`cjpm test`：**632 例，0 失败**（含既有用例；§19.9 记的 `commandPaletteOpensOnCtrlK` 偶发崩溃本轮未复现）。
`./scripts/parity.sh --theme both` + `./scripts/diff.sh --theme both`：**14/14 PASS**（1440×900 基线不变，
结构与视觉门限全过）。

七路由布局复核（Xvfb，`tools/parity/out-2880` / `out-2560` / `out-1930`，不入库）：

| 尺寸 | 结论 |
|---|---|
| 2880×1620（纯逻辑 px） | 日历/甘特/SOP 画布铺到右/下边缘（24 内边距）；GTD 按 Web `max-width:1280` 居中；无溢出 |
| 2560×1440（= 2880×1620 @1.125 外接屏） | 同上，右侧无越界 |
| 1930×1020（启动窗口） | 同 §18.4，无溢出 |

> 说明：2880 **逻辑** px 不是设备上的实际逻辑宽度。设备密度 1.75，最大化后逻辑宽度 = 2880÷1.75 ≈ **1645**，
> 只有 GTD 的 1280 上限仍然生效（左右各留 ~180），其余路由铺满。「大片空白」在密度生效后不再出现。

### 24.8 本轮包与待办

| 包 | 用途 | 大小 / sha256 前 8 位 |
|---|---|---|
| `harmony/out/entry-probe-signed.hap` | **诊断包（已装）**：probe 编译开启 + 启动 4s/12s 自动 resize | 30031865 B / `431d62d2` |
| `harmony/out/entry-default-signed.hap` | **出货包**：probe 关闭、无自动 resize、无临时钩子 | 30025396 B / `19ac3d41` |

待用户：解锁（开发模式不允许自动解锁）→ `aa start` → 读 §24.5 的 `push` / `size` 行 → 若 `adopted=` 仍是旧值，
按 24.5 的表格切到兜底路径；随手最大化一次确认 `size` 行与截图（本轮设备全程锁屏，
`snapshot_display` 只有锁屏时钟，**没有**本应用的截图，不做任何「已目视确认」的声明）。

---

## 25. 原位编辑器：坐标契约、跨帧锚点与关闭路径（本轮）

### 25.1 现场与三个根因

用户现场：**OKR 点输入框后，真控件出现在应用左上角（不是原字段位置），原位置字段消失，而且消不掉。**

真机复现（出货前的旧包，`192.168.0.3:36773`，全屏 2880×1620 / 密度 1.75）：

| 视图 | 注入 | 观察 |
|---|---|---|
| OKR | 点 KR 的「指标」框 | 编辑器（占位「例如 42」+ 红字「不能为空。」）出现在**窗口左上角**，压在侧栏「织理 Textura」标题上；原字段被画成编辑态 |
| GTD | 点「下一步」行的日期盒 | 编辑器（占位 `YYYY-M…`）同样出现在左上角；日期盒变空白 |
| SOP | 点检查器「描述」 | 编辑器**正好贴在字段上**，有插入符，输入法工具条出现 |

三条互相独立的成因（SOP 只踩不到前两条，所以它是好的）：

1. **矩形没有跨帧**（坐标问题）。`OkrUiState()` / `GtdState()` 每帧重建（只有 CUI `State` 被
   `rememberState` 复用），而 `promptRect` / `dateRect` / `sceneRect` 是普通字段：点击写进去的值
   在下一帧 build 时就是 `Rect.zero()`，`resolve()` 又用 6px 人造边距把它夹到 `(6,6)` —— 正好压在侧栏上。
   SOP 的 `SopViewState` 由 `remember<SopViewState>` 持有，所以同一份代码在 SOP 上是好的。
2. **焦点请求同样没有跨帧**。`promptFocus` / `dateFocus` / `sceneFocus` 也是每帧新建的 `FocusRequest()`：
   编辑器打开了却 `ctx.focusId == ""`，没有插入符、没有输入法、字符键回到页面。用户看到的是
   「点进去打不进字」，提交时草稿还是空值 → 校验拒绝 → 看起来「关不掉」。
3. **关闭路径不完整**。只有「Esc / 点外部提交」两条，且提交被拒时编辑器留在原地（没有错误提示以外的出口）；
   没有 backdrop 拦截、Tab 会跑到页面控件上、失焦不提交、字段滚出窗口后编辑器仍停在原处。

### 25.2 坐标契约（窗口绝对坐标）

`Ui.inlineEditor(theme, draft, anchor, open, key!, …)` 的锚点是**窗口绝对坐标**，与 `Ui.modal`
的面板矩形同一空间：

```text
x 已含：侧栏 240 + 内容区内边距 24 = 264（1fr 内容区从 264 开始）
y 已含：顶栏 56 + 内容区内边距 24 = 80
滚动：ScrollView 在 layout 子节点前已减去 scrollOffset，所以画布拿到的矩形本身就是滚动后的绝对位置
```

视图不需要做任何换算：它们从 CUI 的 `layout(ctx, rect)` 里拿到的 `rect` 已经是绝对坐标，
`inspectorRects` / `PageCanvas` / GTD 行内盒的公式原样保留即可。

规则（写进代码注释，违反即真机左上角）：

- **每帧重建的状态壳（`OkrUiState`、`GtdState`）不得持有锚点与焦点请求**。它们必须来自
  `inlineAnchor("…")`（`remember<InlineAnchor>`）与 `remember<FocusRequest>("…")`；
  由 `remember<状态壳>` 持有的视图（SOP）可以直接 `InlineAnchor(State<Int64>(0))`。
- **矩形未就绪时绝不按 (0,0) 打开**：`InlineAnchor.ready()` 为假时 `Ui.inlineEditor` 只注册关闭层、
  不建控件；视图在 `layout` 里写回矩形后 `InlineAnchor.revision`（CUI `State`）变化 →
  构建作用域重新描述 → 编辑器在字段就绪的那一帧出现。
- **每帧写回**：字段画出来的地方（`paintOkrField` / 标题热点 / `GtdDateBox.layout` /
  `SopPageWidget.layout` 的 `trackSopPrompt`）在编辑态下 `anchor.update(rect)`，
  于是滚动、resize、同页其它编辑改变行高时编辑器跟着字段走（写入幂等，矩形不变不递增修订号）。

### 25.3 关闭路径（全部可独立生效）

| 入口 | 行为 | 实现 |
|---|---|---|
| `Esc` | **无条件取消**（不写回）。值非法、矩形异常都有效 | `InlineEditFrame.handleOverlay`，第一条分支 |
| 点 backdrop（任意页面空白处） | 提交；校验拒绝则留在原地并显示错误行（与 Web 一致） | 全窗口**透明** backdrop（`InlineEditorHost` 注册的 overlay，在编辑器下层）；主键按下总是被消费，页面热点收不到 |
| 点字段自己 | 只把插入符放回去，不结束编辑 | 同上，`fieldRect.contains` 分支 |
| `Enter` | 提交（多行字段是 `Ctrl/Cmd+Enter`，单 `Enter` 换行） | `TextField.onSubmit` / `TextArea` 前的 `EventHandler` |
| 失焦 | 提交 | `observeFocus`：**同时挂在 layout 与事件上**——CUI 保留图会跳过未变化子树的 layout，只挂 layout 会漏 |
| `Tab` / `Shift+Tab` | 吞掉并保焦，**不逃出编辑器**（出口是 Esc / Enter / 点外部） | `handleOverlay` |
| 字段滚出窗口 | **取消**（不提交）：滚动不是确认动作，取消不改数据，也不会让控件浮在无关内容上 | `observeViewport`（与窗口求交，一次只触发一次） |
| 关闭后焦点 | `FocusRequest.release()` 交还打开前的控件；若原本没有任何控件持有焦点（GTD 行内盒不 `focus`），shell 兜底把焦点放到 `shell-nav-<当前路由>` | `src/ui/focus.cj`、`ShellHost.applyFocusRequest` |

「无法消除」的两种现场都已覆盖：矩形异常（`ready()` 为假）时 Esc 仍有效；值非法的提交被拒后
Esc / 点 backdrop 仍可关闭（backdrop 会把同一次拒绝再报一遍错误，属预期）。

### 25.4 主机门禁（`cjpm test` 652 例全绿）

| 用例 | 断言 |
|---|---|
| `src/ui/inline_editor_test.cj`（15 例，含新增 6） | 零矩形不打开；矩形晚一帧写入则在字段就绪那帧出现；锚点移动后编辑器跟随；字段离开窗口→取消；Tab 保焦；失焦提交；`bounds == 字段矩形`（含内容区偏移 264/80、滚动后的 y、34/92/30px 三种高度分档） |
| `src/views/okr/okr_inline_editor_test.cj`（6 例） | 画布真实 hotspot 点击 → 编辑器 bounds == 字段矩形（指标 78×28、标题按 28/72 下限），x ≥ 264 / y ≥ 80；换字段跟随；单位字段 Enter 写回 store；非法值 + backdrop 留下错误、Esc 关闭 |
| `src/views/sop/sop_inline_editor_test.cj`（3 例） | 检查器「名称」→ bounds == `inspectorRects().nameInput`；检查器滚 40px → 编辑器同期上移 40px；Esc 不写回 |
| `src/views/gtd/gtd_inline_editor_test.cj`（4 例） | 日期盒在 layout 写回绝对矩形（含 300/200 容器偏移，124×30）、非编辑态不写；`openDateEditor` → bounds == 该矩形且拿到焦点；Enter 写回 `gantt.end`；Esc 不写 |
| `src/shell/inline_editor_audit_test.cj`（1 例，七路由） | 每条路由至少一个文本控件，且全部 `x ≥ 240`、不越窗（「跑到左上角/压侧栏」的静态判据） |

对拍：`./scripts/parity.sh --theme both` + `./scripts/diff.sh --theme both` → **14/14 PASS**
（`ruleΔ ≤ 1.5px`、`shift (0,0)`、`edge ≥ 90%`）；编辑态不参与对拍，静态像素无变化。

### 25.5 本轮真机状态

- 交叉编译：`scripts/harmony/build_ohos.sh` 成功；`set_signing_material.sh`（绝对路径 + store/key
  两份密码）→ `assemble_hap.sh`（带 sync）→ `entry-default-signed.hap` **30 051 755 B**，
  sha256 `f8b153df918f6a4e…`，`STATUS: installable`。
- `hdc uninstall` → `install -r` → 两者都成功；**`aa start` 被锁屏阻塞**
  （`10106102 The device screen is locked … unlock screen failed`，开发模式不允许自动解锁），
  且本轮设备的锁屏带密码/指纹，注入无法通过，因此**没有**做逐字段点击审计，不做任何「已目视确认」的声明。
- 探针：源码默认 `PROBE_COMPILED_ON = false`（§1），本轮出货包沿用该默认；卸载重装后沙箱尚未被创建
  （应用没起来过），所以 `diag.log` 不存在——「探针关闭」由源码默认值 + 上一轮同口径实测共同约束。

待用户解锁后按顺序复测（每项三点：**贴在字段上 / Esc 或点外部可关 / 提交后值写回界面**）：

1. **OKR**：侧栏 OKR → 点 KR「当前」输入框（编辑器应压在框上）→ 输入 `42` 回车 → 该数字变 42；
   再点「单位」→ Esc（不应写回）；再点负责人 / 新增 KR / 目标标题各一次。
2. **SOP**：侧栏 SOP → 点检查器「描述」（应压住 92px 描述区，光标在里面）→ 输入后 Ctrl+Enter 保存；
   点步骤节点 → 标题 / 描述 / 负责人 / 预计耗时 / 检查项 / 连线「分支文案」各点一次；Esc 应能关。
3. **GTD + 日历**：侧栏 GTD → 「下一步」首行的日期盒与 `@场景` 盒各点一次（编辑器应压在盒上，
   日期写 `2026-11-05` 回车后行内显示日期）→ 侧栏日历 → 顶部快速添加输入框（原生 `TextField`，
   确认无叠加、可直接输入回车添加）。

```bash
HDC=~/deveco-cli-stable/command-line-tools/sdk/default/openharmony/toolchains/hdc
$HDC shell aa start -a EntryAbility -b com.ethancheung.textura
$HDC shell snapshot_display -i 0 -f /data/local/tmp/shot.jpeg   # 后缀必须是 .jpeg
$HDC file recv /data/local/tmp/shot.jpeg ~/.cache/textura-device/
```

---

## 26. 收敛三组并行修复 + IME 关闭后的指针输入（本轮）

本轮把三个并行 worker 未提交的改动（原位编辑器焦点/去抖、SOP Area 浮层与分割线、SOP dagre 布局记忆）
收敛成可出货状态，并处理新报的现场：**提交一次编辑之后，指针事件整体失效**。

### 26.1 保留了什么（三组改动，均不回退）

| 组 | 文件 | 语义 |
|---|---|---|
| 焦点/去抖/全选 | `src/ui/inline_editor.cj`、`src/ui/ui.cj`、`src/views/{okr,gtd,sop}/*` | 一帧「无焦点主」不算失焦（`INLINE_BLUR_FRAMES=2`）；打开时全选（`selectAllOnOpen`），槽位型字段（指标数字、日期）第一个字符替换原值；提交后焦点按 `FocusRequest.release()` 交还原字段；GTD 日期统一 `YYYY-MM-DD` + 校验 + 非法不关闭 |
| SOP 设置 | `src/views/sop/sop_area_picker.cj`、`sop.cj`、`sop_inspector.cj`、`sop_model.cj` | Area 浮层改在 **layout** 登记（draw 登记会在下一帧被 `clearActiveOverlay` 清掉 → 收不到事件、点击穿透画布、锚点退化 (0,0) 跑到侧栏）；浮层消费所有指针事件；字段矩形跨帧刷新（`syncSopAreaAnchor`），字段不可见即关闭；检查器分隔线改用 `inspectorRects()` 算出的 `checklistRuleY`（不再从加号按钮反推 5.5px） |
| dagre 布局记忆 | `src/views/sop/logic/layout.cj` | 按输入记忆布局结果，崩溃率 22% → ~1%（运行时 `toRegion2Idx` 缺陷仍在，见该文件注释） |

### 26.2 去抖：一帧「没有焦点主」不是失焦

CUI 只在**本次 build** 里重新认领焦点 id：只要某个 `State` 让子树重新描述，那一帧 `focusId` 会是空串，
`observeFocus` 的旧实现当场提交。真机后果是两个一起出现的坏体验——编辑在用户敲字时被静默结束，
值被校验拒绝时编辑器留在原地**但已经没有焦点**，之后的字符全落到页面上。

现在的判定：

| 一帧的状态 | 行为 |
|---|---|
| `focusId == 编辑器 key` | 记 `sawFocus`，清去抖计数 |
| 焦点为空、去抖计数 < `INLINE_BLUR_FRAMES`(2) | **不提交**：`ctx.focus(key)` 把插入符要回来 + 请求下一帧（重建窗口，不是失焦） |
| 焦点交给了**别的控件**（`focusId` 非空且不是自己） | 同一帧提交（Web 的「点别处 = 完成」） |
| 焦点为空且持续 2 帧以上 | 提交 |
| Esc / Enter / 点 backdrop / 字段滚出窗口 | 取消 / 提交 / 提交 / 取消（§25.3，未变） |

`InlineEditorHost` 另外用 `subscribeFrame` 每帧跑一次 `observeFocus`：保留图会跳过「本帧没变化」子树的
layout，只挂 layout 会漏掉重建期间丢失的焦点。

两条**过时断言**按新语义重写（没有删用例，也没有放宽范围）：

| 用例 | 旧断言 | 新断言 | 原因 |
|---|---|---|---|
| `ui/inline_editor_test.cj::inlineEditorCommitsWhenFocusLeaves` | `clearFocus()` 之后第一个事件就写回 | 焦点**交给另一个真实存在的控件**时同一帧写回（用例里加了第二个原位编辑器当交接目标；CUI 每帧会丢弃「画不出控件」的焦点 id，交接对象必须在焦点图里） | 空焦点现在被判定为重建窗口，不再等于失焦 |
| `ui/inline_editor_test.cj::inlineEditorKeepsTheEditWhenAFrameHasNoFocusOwner`（新增） | — | 空焦点一帧：不提交、不取消、`focusId` 回到编辑器、后续字符仍进草稿 | 钉住 §26.2 的真机根因 |
| `views/sop/sop_area_picker_test.cj::areaPopupAnchorFollowsTheScrolledField` | 1440×900 下 `inspectorScroll=40` → 弹层上移 40 | 用 560px 矮窗口，先滚到「还能回滚 40px」处让 Area 字段进入 body，再滚 40px；断言弹层同期上移 40px + 锚点等于字段矩形 | 1440×900 下 SOP 设置内容正好放得下，`inspectorMaxScroll == 0`，`clampInspectorScroll` 把 40 夹回 0——旧断言只测到夹取逻辑，字段本来就不动 |

### 26.3 门禁（本轮实测）

| 项 | 结果 |
|---|---|
| `cjpm build -j` | `cjpm build success`（41 warnings，全部是既有的 unused） |
| `cjpm test` | **670 / 670 PASSED**，13 个测试包，`SKIPPED: 0, ERROR: 0`（`textura.core.data` 106、`shell` 117、`views.okr` 48、`views.sop` 21、`views.gtd` 9、`ui` 19、`views.sop.logic` 64、`views.gtd.logic` 78、`views.calendar.logic` 76、其余见日志） |
| `scripts/parity.sh --theme both` + `scripts/diff.sh --theme both` | **14/14 PASS**（`ruleΔ ≤ 1.5px`、`shift (0,0)`、`edge ≥ 90%`、blur SSIM ≥ 0.95、ΔRGB≤32 ≥ 95%）；SOP 分割线/浮层改动**没有**改变静态像素（sop-light `diff 9.02% / SSIM 0.9538`，与上一轮同口径；浮层是打开态，不参与对拍） |

`.arts/`（DevEco 本地工作区配置）已加入仓库根 `.gitignore`；`.hap`、`harmony/.certs/`、
`harmony/out/`、`build-profile.json5` 仍按既有规则不入库（`build-profile.json5` 由
`set_signing_material.sh` 生成，含机器相关的密文密码）。仓库里没有 scratch 测试文件，
`src/` 的生产代码没有调试 `println`（只有 `main.cj` 的 CLI 输出）。

### 26.4 「提交后丢指针」：现场、已排除项与已加的取证（**真机未验证**）

**现场（SOP worker 提交编辑后实测）**：完成一次编辑提交（Enter / 点外部）后，指针事件**整体**消失——
点主题按钮、点侧栏行、点下一个输入框都没有反应；**键盘仍有效**（Tab 仍能移动焦点）；ArkUI 窗口本身正常
（画面在动、帧在跑）。

**推论（按「指针按位置路由、按键按焦点路由」这一条区分）**：

- 画面与帧正常 ⇒ CUI 树、store、宿主帧循环都没坏；
- Tab 有效 ⇒ 按键路径活着（而 Tab 恰好是本页在 `TextInputState.attached == false` 时**自己**用
  NAPI 桥转发进 SDL 的，所以它不能证明 XComponent 仍持有 ArkUI 焦点）；
- 指针整体失效 ⇒ 缺的是「按位置」的那条链：XComponent 节点不在 ArkUI 的命中/焦点链里，或它的
  布局矩形变成了非真实值（`OPENHARMONY_SyncSurfaceSize`，§19）。

**已排除**（读码 + 主机用例）：

| 假设 | 结论 |
|---|---|
| CUI 的透明 backdrop 在提交后仍然登记、把指针吃掉（键盘不受影响，症状一样） | 浮层栈每帧 `clearActiveOverlay`，`open == false` 时不登记；`ui/inline_editor_test.cj` 与 `views/sop/sop_area_picker_test.cj` 的关闭路径用例全绿 |
| `leftMouseDown` 卡在 true（MouseUp 被浮层吃掉） | `DesktopApp.completePointer` 在派发后无条件清 `leftMouseDown`/`dragId`/`pressedId`，与谁消费无关 |
| 宿主的指针解码（`RawCode(0/1)` vs `Left`） | 真机 `ev#` 行实测 `MouseDown button=Left primary=true`，且 `textura.ui.isPrimaryPointerButton` 是唯一解码点（`pointer_gate_test.cj` 有源码门禁） |
| 宿主侧有「IME 期间不派发指针」的闸门 | `harmony/host/src/*.cj` 里没有任何 IME 相关的指针分支 |

**已加（低风险、健康时为空操作、带日志）**。`harmony/entry/src/main/ets/pages/Index.ets`：

1. IME 轮询（120ms）里检测 `TextInputState.attached` 的 true→false 边沿 → `onImeDetached()`；
2. `onImeDetached()`：`requestSurfaceFocus('ime-detached')`（+120ms 再试一次，`150003` 在面板退场时是正常噪声）
   ——把 XComponent 重新放回 ArkUI 焦点链；
3. 强制重推一次测量到的 surface 尺寸（`repushSurfaceSize()`：先清「已推送」缓存，再 `pushSurfaceSize()`）
   ——IME 期间键盘避让若让 ArkUI 重排过，SDL/缓冲几何不会停在旧尺寸；
4. 三个日志点：`textura-ime event=detached surfaceFocused=…`、`textura-focus request=ime-detached ok=…`、
   `textura-size repush px=…`。

**没有做的事（等证据）**：`inputMethod.getController().stopInputSession()`。`hideTextInput()` 只收面板、
不断会话，会话残留是「输入法窗口继续吃触摸」这一假设的核心，但它同时可能打断下一次 `attach`
（§21 的候选窗跟随就是靠反复 `attach` 实现的）。在没有真机日志之前不做这一步，避免把「指针失效」
换成「文本输入整体失效」。

**取证方案（解锁后，按顺序）**：

1. `TEXTURA_PROBE=1 scripts/harmony/build_ohos.sh && scripts/harmony/assemble_hap.sh`（诊断包，
   探针只编进快照，工作树默认仍是 `PROBE_COMPILED_ON = false`）；事件上限已从 200 提到 **800**
   ——上一轮 65 秒就用完了 200 条，真出现问题的时刻日志已经瞎了；
2. 装包 → 打开 → 复现一次「提交编辑后点侧栏」；
3. `hdc shell 'grep -nE "ev#|ime|repush|focus" <sandbox>/textura/diag.log'`：
   - **点侧栏后有 `ev#` 行** ⇒ 事件到了 CUI，问题在树里（浮层/命中），与 IME 无关；
   - **没有任何 `ev#` 行**，但同时间段有 `size`/`step` 行 ⇒ 事件没进 SDL：看 `textura-ime event=detached`
     与 `textura-focus request=ime-detached ok=`；`ok=false` 或 `surfaceFocused=false` 就坐实「焦点被收走」；
   - **有 `ev#` 但 `x/y` 全是 0 或越界** ⇒ 坐标/表面尺寸问题，对照同期 `size w=… h=…` 行。
4. 若 `ok=false`：把 `stopInputSession()` 加进 `SafeImeController.hideTextInput` 的收尾（同样带日志），
   重测「提交后立刻点下一个输入框」。

### 26.5 本轮真机状态：**被锁屏阻塞，未做任何逐项验收**

- 交叉编译：`scripts/harmony/build_ohos.sh` 成功（`libtextura_host.so` 17 437 520 B，
  `ELF 64-bit LSB shared object, ARM aarch64`，导出 `SDL_AppInit/Iterate/Event/Quit` + `textura_host_ready/error`）。
- 签名：`set_signing_material.sh --store-file/--cert/--profile`（绝对路径，store/key 两份密码，
  profile 的 `bundleName` 与 `com.ethancheung.textura` 一致，UDID `35381726910894F7…` 在白名单）→
  `assemble_hap.sh`（带 sync）→ `entry-default-signed.hap` **30 077 068 B**，
  sha256 `aba6b7a9b12ee2a976f8df3295f60b7532c0cf24af6228d666014333fbb8dc6e`，`STATUS: installable`。
- `hdc uninstall` → `hdc install -r` **成功**；`aa start` **失败**：
  `Error Code:10106102 The device screen is locked during the application launch, unlock screen failed`
  （开发者模式不允许自动解锁）。设备当前停在锁屏（需密码/指纹），`snapshot_display` 只能拍到锁屏/息屏，
  `uitest uinput` 注入无法穿过锁屏。**因此本轮的 OKR/GTD/SOP 逐项验收、提交后指针复测、七路由稳定性采样
  一项都没有做**，不做任何「已目视确认」的声明。
- 探针：出货包 `PROBE_COMPILED_ON = false`（§1），所以新包里没有 `diag.log`；上面的取证方案要重新出诊断包。

**解锁后按序复测（每项都要 `ev#` 或截图）**：

1. **OKR**：点 KR「当前」→ 输入 `42`（应**全选替换**，不是 `4742`）→ Enter 写回 → 立刻点「单位」/侧栏/主题按钮，必须立即响应；
2. **GTD**：日期盒 placeholder（未点/点击后都应是 `YYYY-MM-DD`）→ 输入 `2026-11-05` 写回 → 输入 `2026-13-01`
   报错且 Esc 可关；
3. **SOP**：Area 展开在字段下方 → 点选一行写回 → 再点字段/Esc/点外部都能关 → 点两个不同输入框不跳节点 →
   分隔线不与类型 chips 重叠（给前后像素 y）→ 保存后立刻点下一个输入框可输入；
4. **稳定性**：七路由轮一遍 + 开关弹层，3 分钟内 `pidof com.ethancheung.textura` 不消失；
   诊断包同会话 `fail n=` 计数为 0。
