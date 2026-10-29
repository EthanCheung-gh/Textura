# Vendored 第三方依赖（只读）

本目录是 Textura 仓颉重写的可复现依赖副本。**不要在这里改源码**；需要补丁时先向协调者申请，并在本文件登记。

## Pin 版本

| 依赖 | 版本 / pin | 来源 | 说明 |
|---|---|---|---|
| CUI | 0.9.6 | PixCap-Cangjie `third_party/CUI` | 含补丁 `CUI-P01-hosted-frame-step`（`beginHostedRun` / `step` / `endHostedRun`）、`CUI-P02-overlay-scrollbar`（`ScrollView.scrollBarVisible`）、`CUI-P03-hosted-frame-cost`（`lastFrameCost` / `deliver` / 宿主事件等待上限）、`CUI-P04-released-scene-node`（路由切换冻结）、`CUI-P05-text-input-on-focus`（输入法抢字符键）、`CUI-P06-arkts-key-bridge`（HAP 侧 Tab 转发）、`CUI-P07-hosted-failure-accessor`（宿主逐帧取帧失败，诊断用）、`CUI-P08-pointer-button-normalization`（触摸后端的按键码归一）、`CUI-P09-host-window-push`（宿主推送窗口尺寸与屏幕密度）、`CUI-P10-printable-key-fallback`（只有 `KeyDown`、没有 `TextInput` 的可打印字符）、`CUI-P11-paint-clip-accessor`（自绘画布读取逻辑裁剪矩形）、`CUI-P12-phase-prefix-observation`（滚轮滚动后不重排/不重画），见下文 |
| cangjie-sdl | 0.9.6，pin `98edeb79cb6d58b7c8ed86d8d6b5342dca4291a6` | PixCap-Cangjie `third_party/cangjie-sdl` | Cangjie SDL3/SDL3_ttf 绑定；`cjpm.toml` 的 `[ffi.c]` 指向 `./.sdl3`；含补丁 `SDL-P01-host-window-push`（`setSizeInPixels` / `setDisplayScaleOverride`），见下文 |
| SDL3（宿主 x86_64） | 3.5.0，源码 ref `6defbc0129b5ba90bab3f6c67bbc1e9329e24ff1` | 由 PixCap `third_party/SDL` 源码本机构建 | 见 `.sdl3/libSDL3.so`；`libSDL3.so.0` 为同名符号链接 |
| SDL3_ttf（宿主 x86_64） | 3.2.2，vendored FreeType，Harfbuzz/PlutoSVG 关闭 | 由 PixCap `third_party/SDL_ttf` 源码本机构建 | 见 `.sdl3/libSDL3_ttf.so`；`libSDL3_ttf.so.0` 为符号链接 |
| SDL3 / SDL3_ttf（OHOS） | 与 PixCap 阶段一致 | PixCap `.sdl3` 的 aarch64-linux-ohos 产物 | 见 `.sdl3-ohos/`，鸿蒙阶段使用，宿主构建不要指向它 |

## 目录说明

- `CUI/cjpm.toml` 的 sdl 依赖已改为 `sdl = { path = "../cangjie-sdl" }`，不指向上游 git。
- `cangjie-sdl/.sdl3/`：**宿主 x86_64** 库（当前 Linux 构建使用）。
- `cangjie-sdl/.sdl3-ohos/`：PixCap 的 **aarch64-linux-ohos** 库（鸿蒙阶段使用）。
- `SDL_ttf/build/libSDL3_ttf.so.aarch64-ohos`：PixCap 原始 OHOS 构建产物，保留作对照；它不是 x86_64，不能给宿主用。

## 为什么宿主库要自己构建

`file` 验证结果：

```text
third_party/SDL_ttf/build/libSDL3_ttf.so: ELF 64-bit LSB shared object, ARM aarch64
```

任务描述里说它是 Linux x86_64 宿主构建，实际是 aarch64-ohos。因此本仓从 SDL_ttf 3.2.2 源码用 vendored FreeType 重新构建了 x86_64 版本。复现命令见 `docs/BUILD.md` 第 7 节。

## CUI 补丁

`CUI-P01-hosted-frame-step` 已包含在源码里，位置 `CUI/src/desktop/desktop_app.cj`。它把阻塞的 `run()` 循环拆成宿主可逐帧驱动的 `beginHostedRun` / `step` / `endHostedRun`，供鸿蒙 XComponent `OnFrame` 使用。不要删除或重命名这些方法。

### CUI-P08-pointer-button-normalization（本仓新增，最小补丁）

- 位置：`CUI/src/core/pointer_buttons.cj`（新增 `normalizePointerButton`）+
  `CUI/src/core/event_sequence.cj`（`dispatchEventRecord` 入口归一）。
- 现象：桌面 SDL 后端把主键报成 `MouseButton.Left`，而触摸驱动的后端（鸿蒙 XComponent 上的手指）
  报 `MouseButton.RawCode(0)`（SDL 的"无按键信息"）或 `RawCode(1)`（左键真实码）。CUI 内建控件的
  协议写死 `Left`，于是按钮/分段/输入框/下拉全部"点不动"，而 hover 与滚轮正常 —— 最难定位的一类输入 bug。
- 改动：事件进入框架时**一次**归一：`RawCode(0|1)` → `Left`（`MouseDown`/`MouseUp` 都做），
  中间键/右键/滚轮轴原样保留。`DesktopApp` 与 `WidgetTestHost` 共用 `dispatchEventRecord`，所以
  真机路径与主机测试走同一条归一；应用层 `textura.ui.isPrimaryPointerButton` 仍接受原始码，双保险。
- 影响：不改变桌面行为（本来就是 `Left`）；不改变布局与像素。门禁测试
  `src/shell/pointer_gate_test.cj` 禁止生产源码再直接匹配 `MouseButton.Left`。
- 上游同步提示：升级 CUI 时需重新应用本补丁（与 CUI-P01..P07 同流程），并在本表登记版本。

### CUI-P07-hosted-failure-accessor（本仓新增，只读诊断出口）

- 位置：`CUI/src/desktop/desktop_app.cj`（`DesktopApp.takeHostedFailure()`）。
- 背景：宿主模式把每帧的可恢复异常收进 `UiFailureCollector` 后继续循环，只在 `endHostedRun()` 才重新抛出。
  一帧固定抛异常时，输入（在 build/layout 之后派发）全部失效，现象是「窗口活着但冻住」，而会话进行中
  没有任何出口能看到真实异常（CUI-P04 的问题就是这样被静默了 1702 帧）。
- 改动：新增一个只读方法，取走（并清空）自上次调用以来的失败，返回原始异常或 `UiAggregateException`。
  不做任何额外收集、不改变帧行为；只有诊断调用方（`harmony/host/src/probe.cj` 的 `probeFailure`，探针关闭时
  不执行）会调用它。
- 不改变渲染结果：不注册监听、不影响 `step()`/`endHostedRun()` 的失败语义；1440×900 对拍 14/14 不变。
- 上游同步提示：升级 CUI 时需重新应用本补丁（与 CUI-P01/P02/P03 同流程），并在本表登记版本。

### CUI-P05-text-input-on-focus（本仓新增，最小补丁，含 cangjie-sdl 绑定扩展）

- 位置：`cangjie-sdl/src/window.cj`（新增 `SdlWindow.startTextInput()` / `stopTextInput()`）+
  `CUI/src/desktop/desktop_app.cj`（`applyTextInputAnchor()` 按焦点开关文本输入）。
- 现象（真机）：`Ctrl+K`/`Ctrl+N`/`Ctrl+Z` 等含字母的快捷键无效，而 `Escape`、`Ctrl` 能到 CUI。
  `diag.log` 只有 `Scan(224)`、没有 `Letter(75)`；屏幕上出现系统输入法候选条。
- 根因：`SdlWindow` 在**建窗时**调用一次 `SDL_StartTextInput` 且永不停止。HarmonyOS 上「文本输入已开启」
  意味着系统输入法接管窗口的字符键，字母全部进 IME，SDL 的键事件拿不到；本应用并没有聚焦任何输入框。
- 改动：窗口仍默认开启（桌面行为不变），CUI 在每帧结束时按「本帧是否有文本控件报告了插入符」
  （`ctx.textInputAnchorRect()`，即 `TextField/TextArea` 有焦点并绘制了光标）切换：
  有 → `startTextInput()`（输入法可正常出候选），无 → `stopTextInput()`（字符键交回应用）。
  两侧都用 `SdlException` 兜底，失败时保持原状态，不影响帧。
- 实测：真机上无输入框时 `K` 不再进输入法（候选条消失，`Ctrl+K` 打开命令面板、`Ctrl+N` 打开快速收集）；
  聚焦顶栏搜索框后输入 `ni`，系统输入法候选条正常出现（你/拟/呢/尼…），中文输入未被破坏。
- 上游同步提示：升级 cangjie-sdl/CUI 时需重新应用本补丁，并在本表登记版本。

### CUI-P09-host-window-push（本仓新增，最小补丁，含 cangjie-sdl 绑定扩展 SDL-P01）

- 位置：`CUI/src/desktop/desktop_app.cj`（新增 `DesktopApp.applyHostWindow()`）+
  `cangjie-sdl/src/window.cj`（新增 `SdlWindow.setSizeInPixels()` / `setDisplayScaleOverride()`，
  并在 `queryWindowDisplayMetrics()` 里接受覆盖值）。见 `docs/DEVICE-NOTES.md` §24。
- 现象（真机）：窗口最大化后 UI 仍按启动尺寸 1930×1020 排版贴在左上，右侧/下方大片空白；且整机
  `densityPixels = 1.75`，而 openharmony 后端报 pixel density 1.0，于是 1.75× 屏上所有控件/字号都按像素排，
  视觉上偏小。
- 根因：ArkUI 持有 XComponent surface，openharmony 视频后端在**建窗时**采纳一次尺寸后不再采纳后来变化；
  且该后端不报真实屏幕密度。
- 改动：宿主（ArkTS 页面）把自己的实测结果推给 CUI —— `applyHostWindow(pxW, pxH, density)` 先装密度
  （`setDisplayScaleOverride` 让 `scale = userScale × density`、`pixelDensity = 1`，于是逻辑尺寸 = 像素/密度、
  绘制按密度放大、`UiContext.displayScale` 同步），再用**像素**尺寸 `setSizeInPixels` 调 `SDL_SetWindowSize`
  并回读（相同尺寸不重复调用）。密度为 0 时完全走原路径，桌面行为与像素不变。
- 影响：桌面路径（`density ≤ 0` 不进入覆盖分支）像素不变，1440×900 对拍 14/14；只有宿主推过密度才生效。
- 上游同步提示：升级 CUI 时需重新应用本补丁（与 CUI-P01/P04 同流程），升级 cangjie-sdl 需重新应用
  SDL-P01，并在本文件登记。

### CUI-P10-printable-key-fallback（本仓新增，最小补丁）

> 编号说明：任务书写的是「第 9 个补丁、登记 CUI-P09」，但 `CUI-P09` 已被上一轮的
> `host-window-push` 占用并已提交，本补丁按顺序登记为 `CUI-P10`。

- 位置：`CUI/src/text/text_printable_key.cj`（新增 `PrintableKeyFallback` / `printableKeyText`）+
  `CUI/src/text/text_field.cj`、`CUI/src/text/text_area.cj`（键处理、取消、`arm` 各接一处）+
  `CUI/src/text/text_printable_key_test.cj`（11 个用例，其中 3 个走真实帧 tick 订阅路径）。
- 现象（真机）：OKR 指标「当前」框已聚焦（`focus='okr-prompt-input'`），硬件键盘按 `4`/`2` 时
  `diag.log` 只有 `KeyDown key=Digit(52)` / `Digit(50)`，**没有任何 `TextInput text='4'`**，草稿不变；
  而按字母 `a` 会被系统输入法接管（弹候选条），空格提交后草稿变成 `啊`。
- 根因：两个编辑器只在 `UiEvent.TextInput`（输入法对一次按键的解释结果）里插入文本；
  `Key.Digit` / `Key.Space` 在两个 `handleKey()` 里根本没有分支，`Key.Letter` 只走快捷键表。
  于是「输入法不解释的键」（数字、空格、未挂输入法时的字母）既没有 `TextInput`、也没有键分支，
  字符被静默丢掉。见 `docs/DEVICE-NOTES.md` §27。
- 为什么不能只在应用层修：应用层的 `TextField` / `TextArea` 只是把 `Bindable<String>` 交给 CUI，
  文本插入完全发生在框架的 `UiEvent.TextInput` → `TextEditorActions.insert` 这一条路径上；
  应用层既拿不到 `KeyDown(Digit)`（CUI 已经把它派发给控件并返回 false，应用层再插会在别的平台重复插入），
  也没有 `ux` 级入口能区分「键已被输入法吃掉的平台」和「键需要应用兜底的平台」。
  任何应用层补丁都只能针对某一个字段写一次性处理，`ComboBox` 内嵌的 `TextField`、SOP 描述的多行
  `TextArea`、错误提示框里的输入框都得各写一遍，且下一次新增文本控件就会重新漏。这是框架契约的缺口。
- 为什么是「延迟一拍」而不是立即插入：SDL 对同一次按键先发 `SDL_EVENT_KEY_DOWN`、再发
  `SDL_EVENT_TEXT_INPUT`，但在输入法介入（软键盘、远程输入法、宿主桥）时两者可以跨帧到达。
  立即插入会在这些平台上双插入，而桌面主机（按键与 `TextInput` 同批到达）永远测不出来。
  因此按下时只把字符记进 `pendingPrintable`（每控件一份、放 `localState` 里以跨帧重建存活）
  并 `requestFrame()`；同帧内到达的 `TextInput` / `TextEditing` 会清空它（输入法优先）；
  下一帧仍存在时才用与 `inputText` 完全相同的 `actions().insert()` 写进草稿
  （撤销合并、选区替换、IME 隔离规则都不变）。
- 「下一帧」走 **`frameSubscriber` 而不是 `UiEvent.Frame`**（这条是踩出来的，别再改回去）：
  `DesktopApp.stepFrame()` 只把合成帧 tick 派发给 `frameSubscriber` 回调
  （`dispatchFrameSubscribers`），**从不把 `UiEvent.Frame` 派发进控件树**——树里的 Frame 广播
  只在宿主主动 `broadcastEvent` 时才发生；`Portal.handle` 更是直接返回 `false` 不向子树转发，
  而 OKR/GTD/SOP 的原位编辑器与顶栏搜索框正是走这条渲染/事件路径。
  第一版补丁把 flush 挂在 `handle(UiEvent.Frame)` 上，主机测试全绿、真机完全无效。
  现在的做法：`PrintableKeyFallback.arm()` 在**每次 build** 读取暂存槽（这个读是保留图的依赖，
  `stage` 写槽后该控件才会重建），**仅当槽非空**时为这一两帧 `registerFrameSubscriber` 注册一次。
  `registerFrameSubscriber` 注册进的是本次 build 的 `FrameSubscriptionRegistry`（每次 build 清空，
  见 `core/frame_subscription.cj`），所以不会泄漏；静止时 `frameSubscriberCount == 0`，
  `canRepaintPartially` 的 retained 局部重绘策略不被破坏。`handle(UiEvent.Frame)` 保留为幂等的
  第二触发点，供会广播帧事件的宿主（`WidgetTestHost`、`EventHandler` 包住的自定义壳）使用。
- 范围：无修饰键的 `Key.Digit` / `Key.Letter` / `Key.Space`。`Ctrl/Cmd/Alt+字母` 仍是命令
  （`Ctrl+A` 不会被当成字符）；`Shift` 组合不在本轮范围 —— `Key.Digit` 报的是未加 Shift 的码
  （`Shift+1` 是 `!` 不是 `1`），凭空插入会写错字符，故保持原状。`Key.Letter` 带的是**大写**
  ASCII（这是 `Ctrl+letter` 表可读的原因），而暂存只在无修饰键时发生，所以兜底按小写插入；
  Caps Lock 对键事件不可见，若某次大写字母始终没有 `TextInput` 会以小写入稿，接受这个偏差，
  因为只要输入法在，同帧的 `TextInput` 一定先赢。
- 验证：主机 `cjpm test`（CUI 包 962 项：961 通过 + 1 个既有的 `unicode17OfficialGraphemeBreakConformance`
  ERROR——缺 `.dev/unicode/GraphemeBreakTest.txt` 夹具，与本补丁无关；根包 687/687）与
  `scripts/parity.sh/diff.sh --theme both` 14/14 全绿。新用例先红后绿：把实现换回第一版
  （只有 `handle(UiEvent.Frame)`）时，走订阅路径的
  `printableKeyFlushesOnTheFrameTickSubscription` / `printableKeyFrameTickKeepsSuccessiveDigitsInOrder`
  稳定 FAIL（`text.value` 仍为空、`subscribers()` 为 0），修后 PASS。
- 如何在屏幕上验证：
  1. 出货包装机，进 OKR，点 KR 的「当前」框（出现橙色描边 + 值全选）；
  2. `hdc shell uinput -K -d 2004 -u 2004`（键 `4`）再 `2002`（键 `2`）；
  3. 框内应立刻显示 `42`（不是 `47`、不是空）——这就是「裸键兜底」生效；
  4. `uinput -K -d 2054 -u 2054`（Enter）后卡片显示 42，且点击侧栏其它项仍然立刻响应；
  5. 反向验证输入法路径没被破坏：聚焦顶栏搜索框输入 `ni`，候选条照常出现、空格提交后中文进框
     （说明同帧 `TextInput` 仍然优先，没有双插入）。
- 上游同步提示：升级 CUI 时需重新应用本补丁（新增 1 个文件 + 两个编辑器各 4 处改动），并在本文件登记。

### CUI-P12-phase-prefix-observation（本仓新增，最小补丁）

- 位置：`CUI/src/core/state_phase_dependency.cj`（`reuseCommittedPrefix` 内补 4 行索引维护）+
  `CUI/src/core/state_phase_dependency_storage_test.cj`（回归用例）、
  `CUI/src/testing/scroll_wheel_host_test.cj`（3 个宿主帧用例）。
- 现象（真机）：**启动即 OKR 时，滚轮滚动后画面不刷新**（像卡住、没有滚动感）；切到别的页签再切回来，
  才看到滚动后的页面。
- 主机定位（Xvfb + SDL opengl + 真字体 + `XTest` 滚轮注入，1645×920，150 条数据，改前 trace）：
  - 滚轮事件确实到达 `ScrollView.handle`（`dy=-1`、指针在裁剪区内），`scrollByWheel` 逐格推进偏移
    `0 → 72 → 144 → …`；
  - 但同一段 trace 里 `ScrollView.layout` / `OkrPage.layout` **一次都没再跑**（8 次全部发生在启动期），
    子画布矩形不变 ⇒ 自绘画布按旧坐标重放；
  - 改前截图差分 **0 像素**：不只是「没重画」，而是「什么都没动」；
  - 决定性一行：`stateSet id=<offset> listeners=0` —— 滚轮写入时偏移 State **没有任何监听者**，
    于是这次写入只请求了一帧，没有让任何保留阶段失效。
- 根因：`PhaseStateDependencies` 的「committed prefix 复用」把已提交的边直接塞进 pending 前沿，
  **没有**登记进 `pendingSources` 去重索引。一旦某轮 trace 在复用若干读之后才分叉，`commit()` 走
  reconcile（`closeRemovedDependencies`）并信任该索引，那些**仍在 pending 里的边**被判为「已移除」而关闭观察；
  而 committed 前沿保留的正是同一个（已关闭的）对象，下一轮 `reuseDependency` 命中它、不会再开观察，
  该阶段从此对这一批 State 永久失聪。滚动容器刚好满足触发条件：外壳每次 layout 都会写入一个状态
  （视口同步），使每轮都走 reconcile；滚动偏移又在同一次 layout 里被读 ⇒ 被误关 ⇒ 滚轮写入不再触发布局。
- 为什么不能只在 OKR 里 `ctx.requestFrame()`：`requestFrame()` 只保证「来一帧」，不动布局缓存；
  OKR 的指令表是在 `layout` 里按 `rect.y` 生成的，布局缓存命中就重放旧坐标，结果是「有帧、没变化」。
  这也不是 OKR 独有：任何在 layout 里读状态的保留子树（Lazy 行、检查器、输入框）在同样的时序下都会失聪，
  所以补丁落在 CUI 的失效传播里。
- 改动：`reuseCommittedPrefix` 在把边加入 pending 前沿之后，同步登记到 `pendingSources`（若已存在）。
  不新增状态、不改任何布局/绘制语义；索引依旧只是「pending 前沿的成员表」，只是不再漏项。
- 验证：新用例 `prefixReusedReadsStayObservedWhenTheTraceDivergesLater` 先红（9 条前缀复用的读里 8 条
  `listenerSlotCount()==0`，写入不再触发失效）后绿；根包 `cjpm test` 700/700；CUI 包 `cjpm test`
  966 通过 + 1 个既有 `unicode17OfficialGraphemeBreakConformance` ERROR（缺 `.dev/unicode` 夹具，与本补丁无关）；
  `scripts/parity.sh`/`diff.sh --theme both` **14/14**，`okr-light`/`okr-dark` 与改前**逐字节相同**
  （`c7929df4…` / `30d82a8e…`）。同一 Xvfb 装置上改前滚轮后像素差 0、改后 347,811 像素（23%），
  再滚一次又差 256,203 像素，且点击同路由的页签不再改变画面。
- 已知边界：滚轮仍是一格 `CUI_SCROLL_WHEEL_STEP`（72 逻辑像素）的**瞬时**位移，不是惯性/动画滚动；
  本轮只修「不动」，滚动动画另议。
- 上游同步提示：升级 CUI 时需重新应用本补丁（单文件、单函数、4 行），并在本表登记版本。

### CUI-P11-paint-clip-accessor（本仓新增，只读访问器）

- 位置：`CUI/src/core/spatial_clip.cj`（`extend UiContext` 新增 `public func clipPaintBounds(): ?Rect`）。
- 背景：「启动即 OKR、鼠标滚轮滚动明显卡顿」在主机侧的量化显示，同一个文档下 OKR 每帧向渲染器
  提交 **606 次文字绘制**（第二名页面 161–237 次），绘制树走查 **22–23ms/帧**，而 `build` 0.2ms、
  `layout` 0.05ms —— 瓶颈不在排版重算，而在**绘制量按文档长度增长**：OKR 是自绘画布，一整页
  （几十张卡片）是一张 `draw` 指令表，滚动容器只给了它一个裁剪矩形，视口外的部分每帧照样下发、
  再由 backend 的 scissor 丢掉。
- 为什么应用层自己做不到：`ScrollView` 的裁剪矩形存在 `UiContext` 的**逻辑** `spatialClip` 里
  （`visibleBounds` / `paintBounds`），两个读取入口 `currentSpatialVisibility()` /
  `currentSpatialPaintBounds()` 都是 `cui.core` 包内可见；应用层唯一能拿到的是
  `renderer.clipRect()`，那是**后端**状态（`SDL_GetRenderClipRect`），在 retained 子树录制命令
  期间并不反映嵌套的 `pushClip`，用它做裁剪判断会在"录制"和"直接绘制"两条路径上给出不同的矩形
  —— 正是会漏画的用法。
- 改动：只增加一个只读方法，返回 `currentSpatialPaintBounds()`（无裁剪时为 `None`）。不改任何绘制
  行为、不新增状态、不改变帧时序；不调用方等于什么都没发生。调用方是
  `src/views/okr/okr_ops.cj` 的视口裁剪（外扩 32px，见该文件注释）。
- 验证：1440×900 对拍 **14/14**（`okr-light`/`okr-dark` 与改前**逐字节相同**：
  `c7929df4…` / `30d82a8e…`）；150 条数据、1645×920（文档 3369px > 视口 864px，裁剪必然生效）下
  改前改后截图仍逐字节相同，而 `tree` 从 23.3ms/帧降到 7.7ms/帧、文字绘制 606 → 169 次/帧。
- 上游同步提示：升级 CUI 时需重新应用本补丁（单文件、单方法），并在本表登记版本。

### CUI-P06-arkts-key-bridge（本仓新功能，HAP 侧）

- 位置：`harmony/entry/src/main/cpp/textura_keys.c`（新 NAPI 模块 `textura_keys`）+
  `harmony/entry/src/main/ets/pages/Index.ets`（根容器 `onKeyEvent` 转发）+ `ets/common/TextInputState.ets`。
- 现象（真机）：`Tab` 注入后 `diag.log` 里**没有任何事件**——ArkUI 的焦点遍历在 XComponent 的
  `OH_NativeXComponent_RegisterKeyEventCallback` 之前就把 Tab 消费了，CUI 的 Tab 走焦永远不可用。
- 改动：根容器只把应用需要的键转发进 SDL 队列（`sendKey(scancode, down, mods)` → `SDL_PushEvent`，
  事件结构按 SDL3 `SDL_KeyboardEvent` 手工布局，`SDL_PushEvent` 运行时 `dlsym`，不引入 SDL 头文件依赖）：
  Tab/Shift+Tab、四个方向键、Escape、Ctrl/Cmd+字母；**普通字母不转发**（必须留给输入法）。
  ArkUI 吞掉 KeyDown、只放行 KeyUp 的场景由页面补发一次完整按下-抬起。
  `TextInputState`（由 `SafeImeController.attach/hideTextInput` 维护）保证「输入法已挂载」时页面不再转发，
  避免与原生路径重复投递。
- 实测：真机 `ev# KeyUp key=Tab` 且 `focus='shell-search'` → `UiIconButton` → `UiSegmented` → `UiButton#2`，
  即焦点沿声明顺序在真实控件间移动；Ctrl+K/Ctrl+N/Esc 全部生效。
- 上游同步提示：本补丁在 HAP 侧，不在 CUI 内；升级 CUI 不受影响，但升级 SDL 时需复核
  `SDL_KeyboardEvent` 布局与 `SDL_PushEvent` 符号。

### CUI-P04-released-scene-node（本仓新增，最小补丁）

- 位置：`CUI/src/core/automatic_render_node.cj`（`AutomaticRenderNode`）。
- 现象（真机必现「整页冻结」）：在某个视图内切换路由后，该帧在**构建提交阶段**抛
  `IllegalStateException: Cannot inspect commands through a released scene node`，此后**每一帧**都在同一处抛。
  因为输入派发在 build/layout 之后，事件再也不被处理：所有控件点不动、滚轮不动、画面停在旧路由，
  而进程仍以 60 步/秒空转。桌面 `WidgetTestHost` 可稳定复现（`src/shell/route_switch_test.cj`：
  `dashboard→…→甘特→…→再进甘特`）。
- 根因：`removeAutomaticMount` 先关外层自动组合的渲染节点、再递归关闭嵌套挂载。嵌套子节点仍持有指向
  **已关闭**父节点的 `parent` 链接；`close() → invalidatePaintCache() → parent.invalidatePaintCache()`
  会走到已释放的 `ElementSceneNode` 上调用 `hasCommands()`，`ensureAlive` 抛异常。
  异常发生在 `finishBuild`/`commitMountBuild`（body 之外），`renderRoute` 的 `try/catch` 边界够不到它，
  CUI 的 `UiFailureCollector` 只是把它收进宿主失败集合，于是「静默冻结」。
- 改动（1 个守卫 + 1 个只读助手 + 关闭时清链接）：
  - `invalidatePaintCache` 开头 `if (closed) { return }`：已释放的节点没有缓存可失效；
  - 向父节点传播前判 `!value.isClosed()`：已关闭的祖先由组合变更本身标脏，跳过它既安全也充分；
  - 新增 `func isClosed(): Bool`；`close()` 末尾清 `parent`（原本就有）。
- 不改变渲染结果：只跳过对已释放节点的缓存操作，绘制指令与尺寸完全不变；
  1440×900 对拍 `--theme both` 仍 14/14（数值未变）。
- 实测：修前 `routeSwitchSurvivesRepeatedVisits` 稳定 ERROR，修后 PASSED；真机出货包七路由依次/重复切换、
  滚动、按钮、弹层均正常，`diag.log` 中 `fail` 计数 0（诊断包实测 1702 次/修前 → 0/修后）。
- 上游同步提示：升级 CUI 时需重新应用本补丁（与 CUI-P01/P02/P03 同流程），并在本表登记版本。

### CUI-P03-hosted-frame-cost（本仓新增，最小补丁）

- 位置：`CUI/src/desktop/desktop_app.cj`、`CUI/src/desktop/frame_profiler.cj`、`CUI/src/core/frame_scheduler.cj`、`CUI/src/cui.cj`。
- 背景：鸿蒙宿主要回答两个问题——「一帧到底贵在哪」和「store 的写入怎么落到 UI 线程」，而 CUI 0.9.6 都没有出口：
  `FrameProfiler` 只认桌面命令行 `--profile`（HAP 没有 argv），`DesktopApp.post` 只能"排队到下一帧"，
  没有"已经在 UI 线程就当场执行"的通道。
- 改动（1 个公开类 + 2 个公开方法 + 3 处行为分支 + 1 处内部枚举值）：
  - 新增公开类 `HostedFrameCost`（`cui.desktop`，并由 `cui.cj` 再导出）：上一次**真正绘制**的帧的分段纳秒耗时
    （build / layout / event / semantics / begin / tree / resolve / present）、该帧事件数与是否走 retained 局部
    damage。每个绘制帧用 8 次 `PerformanceClock` 读取填充（与一帧的成本相比不可测）；未绘制的 step 归零，
    不会重复上报上一帧的数字。
  - 新增 `DesktopApp.lastFrameCost()`：宿主侧诊断入口，替代"用 step 墙钟猜帧成本"（墙钟里含着等待下一个事件的时间）。
  - 新增 `DesktopApp.deliver(action)`：在 UI 线程上以一次视觉失效执行 `action`——当前线程就是帧调度器的 owner
    时**当场**执行（同一个输入帧内完成重绘，点击延迟 1 帧而不是 2 帧），否则转 `post` 排到下一帧边界。
    配合 `FrameScheduler.ownsCurrentThread()`（新增的 protected 只读判定，不抛异常）。
  - 宿主模式的事件等待上限：`waitForWork` 在 `beginHostedRun` 之后把 `MAX_EVENT_WAIT_MS`（250ms）换成
    `HOSTED_MAX_EVENT_WAIT_MS`（16ms），`eventWaitTimeout` 多一个 `cap` 参数。桌面 `run()` 仍是 250ms，行为不变。
    原因与实测见 `docs/DEVICE-NOTES.md` §3：宿主 tick 跑在应用 UI 线程上（XComponent `OnFrame`），
    阻塞 250ms 会拖住排在后面的窗口系统操作，实测空转期有系统 `OS_DfxWatchdog` 线程吃掉 18% CPU。
  - 保留原判定不变：`retainedDamageEnabled`、`--cui-disable-retained-damage`、`--cui-force-full-retained`、
    `--profile` 的语义与输出格式都未改；`FrameProfileSample` 仍由 `frameProfileTimestamp(profiler)` 计时。
- 不改变渲染结果：三个新增出口只读或只影响"何时绘制/何时执行"，不改任何绘制指令；1440×900 对拍 14/14 不变。
- 上游同步提示：升级 CUI 时需重新应用本补丁（与 CUI-P01/P02 同流程），并在本表登记版本。

### CUI-P02-overlay-scrollbar（本仓新增，最小补丁）

- 位置：`CUI/src/core/scrolling.cj`（`ScrollView`）。
- 背景：CUI 的垂直 `ScrollView` 在内容溢出时固定预留 `6 + 2×2 = 10px` 滚动条槽，且没有关闭开关；Web 参考图的 `.shell-content` 使用 overlay 滚动条（无槽），内容可用宽度是
  `1440 - 240（侧栏） - 48（内容 padding） = 1152`。槽宽会让每个视图整体左移 10px，直接拉低视图 parity。
- 改动（1 个公开字段组 + 3 个公开方法 + 5 处分支判断）：
  - 新增私有字段 `showScrollBar`（默认 `true`）、`keyboardScrollEnabled` / `revealFocusedEnabled`（默认 `false`）；
  - 新增 `public func scrollBarVisible(visible: Bool)`：`false` 时不预留槽、不绘制拇指、不处理拇指拖拽；
  - 新增 `public func keyboardScroll(enabled: Bool)`：`PageUp/PageDown`（0.9 视口）、`Home/End`；
    按键先交给内容子树（文本框保留自己的 Home/End），未被消费时才滚动，到边界不消费以便继续冒泡；
  - 新增 `public func revealFocusedOnFocus(enabled: Bool)`：键盘焦点（`ctx.showFocusRing`）变化时，
    按焦点项在 `focusableIds()` 中的序号把目标估算到内容区中部并保证可见；CUI 没有控件矩形 API，
    这是声明顺序≈视觉顺序的近似，鼠标点击聚焦不触发；
  - `layout` 只在 `scrollBarVisible(true)` 且内容溢出时扣除 `scrollBarGutter()`；
  - `draw`/`handle` 仅在显示滚动条时绘制拇指或处理按下/拖拽。
- 保持不变：裁剪（含 spatial clip 与 cross-axis paint overflow）、滚轮每格 72 逻辑像素、
  到边界时冒泡、焦点转发、`scrollState(value)`；三个新开关默认值都不改变既有调用行为。
- 使用方：`textura.shell` 的 `<div class="shell-content">` 等价容器
  `ScrollView(key: "shell-content").scrollBarVisible(false).keyboardScroll(true).revealFocusedOnFocus(true)`。
- 上游同步提示：升级 CUI 时需重新应用本补丁（与 CUI-P01 同流程），并在本表登记版本。

### SDL-P02-openharmony-clipboard-double-free（本仓新增，最小补丁）

> 编号说明：`SDL-P01` 是 cangjie-sdl **绑定**侧补丁（`setSizeInPixels`）；本补丁落在 SDL **C 源码**
> （`third_party/SDL`），按 SDL 补丁序列登记为 `SDL-P02`，补丁文件在
> `cangjie-sdl/patches/sdl-openharmony-clipboard-double-free.patch`。

- 位置：`third_party/SDL/src/video/openharmony/SDL_openharmonyclipboard.c`
  （`OPENHARMONY_GetClipboardText`，删两处 `OH_UdmfRecord_Destroy(udmfrec)`）。
- 现象（真机）：OKR 编辑页用 `uitest uiInput text "…"` 注入文字（走系统粘贴板）时进程 SIGTRAP 秒崩；
  `faultlog/faultlogger` 的 `Reason: SIGTRAP`，栈落在 `free()` ← `OH_UdmfRecord_Destroy` ←
  `OPENHARMONY_GetClipboardText` ← `SDL_GetClipboardText`。
- 根因：`OH_UdmfData_GetRecord(data, 0)` 返回的是 **data 借用的 record**（所有权不转移），
  SDL 却在成功路径（以及 `udspt` 创建失败分支）里 `OH_UdmfRecord_Destroy(udmfrec)`，
  随后 `OH_UdmfData_Destroy(udmfdata)` 再释放一次 → double free。
- 改动：只删这两处 `OH_UdmfRecord_Destroy`，保留 `OH_UdmfData_Destroy`（由它释放 record）；
  `SetClipboardText` 不动（本轮只修 Get）。
- 产物：`.sdl3-ohos/libSDL3.so` 重编，build-id `524b3237…b8bc4`，
  sha256 `dac9e725…a562`（详见 `docs/HARMONY.md` §1、§8）。
- 上游同步提示：升级 SDL pin 时先确认上游是否已修；重新执行
  `PixCap-Cangjie/scripts/build_ohos_deps.sh sdl` 并把产物拷回 `.sdl3-ohos/`（桌面 `.sdl3/` 不换）。

## 上游文档

- CUI API：`CUI/docs/api/cui/**`
- CUI 指南：`CUI/docs/guide/**`（tutorials / how-to / concepts）
- SDL 绑定 API：`cangjie-sdl/docs/api/**`
- 注意：CUI 0.9.6 的 vendored 副本**没有 `examples/` 目录**；任务描述中的 50 个示例在本工作区不存在。
