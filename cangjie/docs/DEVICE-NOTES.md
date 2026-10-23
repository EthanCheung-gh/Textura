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

## 9. 卫生

* 探针源码默认关闭（`PROBE_COMPILED_ON = false`；出货构建实测 `diag.log` 不出新行）。
  真机现存安装包是**探针开启**的诊断包（便于现场复测），出货需按 `HARMONY.md` §7.1c 重编。
* `build-profile.json5` 用 `set_signing_material.sh` 临时指向 `.certs/textura-debug/`，**用完 `git checkout` 复原**；
  `.hap`、`.certs/`、`diag.log` 一律不提交。
* `diag.log` 只存在于设备沙箱，仓库里没有任何日志产物。
