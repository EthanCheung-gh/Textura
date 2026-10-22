# Vendored 第三方依赖（只读）

本目录是 Textura 仓颉重写的可复现依赖副本。**不要在这里改源码**；需要补丁时先向协调者申请，并在本文件登记。

## Pin 版本

| 依赖 | 版本 / pin | 来源 | 说明 |
|---|---|---|---|
| CUI | 0.9.6 | PixCap-Cangjie `third_party/CUI` | 含补丁 `CUI-P01-hosted-frame-step`（`beginHostedRun` / `step` / `endHostedRun`）、`CUI-P02-overlay-scrollbar`（`ScrollView.scrollBarVisible`），见下文 |
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
