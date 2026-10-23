# Vendored 第三方依赖（只读）

本目录是 Textura 仓颉重写的可复现依赖副本。**不要在这里改源码**；需要补丁时先向协调者申请，并在本文件登记。

## Pin 版本

| 依赖 | 版本 / pin | 来源 | 说明 |
|---|---|---|---|
| CUI | 0.9.6 | PixCap-Cangjie `third_party/CUI` | 含补丁 `CUI-P01-hosted-frame-step`（`beginHostedRun` / `step` / `endHostedRun`）、`CUI-P02-overlay-scrollbar`（`ScrollView.scrollBarVisible`）、`CUI-P03-hosted-frame-cost`（`lastFrameCost` / `deliver` / 宿主事件等待上限）、`CUI-P04-released-scene-node`（路由切换冻结）、`CUI-P05-text-input-on-focus`（输入法抢字符键）、`CUI-P06-arkts-key-bridge`（HAP 侧 Tab 转发），见下文 |
| cangjie-sdl | 0.9.6，pin `98edeb79cb6d58b7c8ed86d8d6b5342dca4291a6` | PixCap-Cangjie `third_party/cangjie-sdl` | Cangjie SDL3/SDL3_ttf 绑定；`cjpm.toml` 的 `[ffi.c]` 指向 `./.sdl3` |
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

## 上游文档

- CUI API：`CUI/docs/api/cui/**`
- CUI 指南：`CUI/docs/guide/**`（tutorials / how-to / concepts）
- SDL 绑定 API：`cangjie-sdl/docs/api/**`
- 注意：CUI 0.9.6 的 vendored 副本**没有 `examples/` 目录**；任务描述中的 50 个示例在本工作区不存在。
