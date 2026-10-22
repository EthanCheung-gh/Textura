# Textura 仓颉重写 · 工程结构与硬约束

本文件是后续所有并行 worker 的**硬约束**。任何越界修改都必须在协调者批准后更新本文件，再改代码。

## 1. 顶层边界

- 所有仓颉代码、依赖、工具、文档只放在 `cangjie/`。
- **不得修改 Web 版既有源码**：`src/`、`package.json`、`vite.config.ts`、`src-tauri/`、`docs/screenshots/`、`scripts/qa/` 只读。
- `cangjie/third_party/` 下的 CUI / cangjie-sdl 是 vendored 只读副本。除 CUI-P01（已含）外，不在本仓修改第三方源码；需要补丁时先记录到 `third_party/README.md` 并说明理由。
- 七个视图已全部实现（本轮起不再是占位）；`harmony/` 是完整的 HAP 打包链，但**未签名、未真机验证**，
  状态与风险登记在 `docs/HARMONY.md`。

## 2. 目录与包所有权

| 路径 | 包名 | 所有者/用途 | 允许依赖 |
|---|---|---|---|
| `src/main.cj` | `textura` | 入口、parity CLI、快照闭环 | `cui`、`textura.shell`、`textura.core.data`、`textura.ui` |
| `src/snapshot.cj` | `textura` | BMP→PNG 确定性编码 | 仅 `std.fs` |
| `src/core/data/` | `textura.core.data` | Item/Edge/Area/Run、Workspace、JSON 编解码、store、selectors、日期工具、fixtures、`ViewContext` | `std.*` only |
| `src/ui/` | `textura.ui` | 设计令牌、字体、基础控件、图标 | `cui`、`textura.core.data` |
| `src/shell/` | `textura.shell` | 侧栏/顶栏/路由/快速收集/命令面板/快捷键 | `cui`、`textura.ui`、`textura.core.data`、七个 view 包 |
| `src/views/dashboard/` | `textura.views.dashboard` | Dashboard 视图（后续 worker） | `cui`、`textura.ui`、`textura.core.*` |
| `src/views/gtd/` | `textura.views.gtd` | GTD 视图 | 同上 |
| `src/views/okr/` | `textura.views.okr` | OKR 视图 | 同上 |
| `src/views/calendar/` | `textura.views.calendar` | 日历视图 | 同上 |
| `src/views/gantt/` | `textura.views.gantt` | 甘特视图 | 同上 |
| `src/views/sop/` | `textura.views.sop` | SOP 视图 | 同上 |
| `src/views/settings/` | `textura.views.settings` | 设置视图 | 同上 |
| `src/core/core.cj`、`src/views/views.cj` | `textura.core` / `textura.views` | 目录层级包标记 | 无 |
| `third_party/cangjie-sdl/` | `sdl` | vendored SDL3 绑定 + `.sdl3` 宿主库 + `.sdl3-ohos` 鸿蒙库 | 只读 |
| `third_party/CUI/` | `cui` | vendored CUI 0.9.6 | 只读 |
| `assets/fonts/` | — | 字体说明与后续可嵌入字体 | — |
| `tools/parity/` | — | 参考图、workspace.json、diff.py、metrics.py、截图脚本 | — |
| `harmony/` | — | 鸿蒙工程（AppScope/entry/host）+ HAP 打包链，状态见 `docs/HARMONY.md` | — |

### 依赖方向（不得反向）

```
main -> shell -> views
  |        |       |
  |        +-> ui -+-> core.data
  +-------------------> core.data
```

- 视图之间**不得互相 import**；共享逻辑放 `core.data` / `ui`。
- 原 `core.algo` 已取消：日期/季度工具并入 `core.data`（`date.cj`），OKR/甘特/SOP 的派生逻辑并入
  `core.data` 的 `derive_*.cj`，避免视图反向依赖或各复制一份。
- `core.data` 不得 import `cui`、`ui`、`shell`、`views`（因此 store 用自带的 `StateCell`，不用 `cui.State`）。
- `ui` 不得 import `shell` / `views`。
- `views` 不得 import `shell`（避免与 shell 的派发形成环）。
- `main` 是唯一知道 CLI 与 `DesktopApp` 生命周期的地方；视图不读命令行、不写快照。

## 3. 公共契约冻结

以下内容视为公共契约，修改前必须由协调者批准并在本文件记录：

1. `textura.core.data` 的实体字段：`Item`、`Edge`、`Area`、`SopRunEntry`、`Workspace`。字段名与语义必须与 Web 版 `src/core/model.ts` 对齐；不得为某个视图私加字段。
2. `textura.core.data.inspectWorkspace` 的摘要语义：`byteCount`、`fnv1a64`、`anchorDate`。parity 依赖它。
2b. `textura.core.data.ViewContext` 的字段，以及每个视图的 `public func render(ctx: ViewContext): Unit` 形状。
3. `textura.ui` 的主题工厂 `texturaLight()` / `texturaDark()` 与令牌常量。视图不得硬编码十六进制颜色。
4. `textura.shell` 的 `Route` 枚举、`routeId`、`parseRoute`、`ROUTES`。
5. parity CLI（见 `docs/PARITY.md`）。新增参数必须向后兼容。
6. `textura.views.*` 当前暴露的 `bootstrapTitle()` / `bootstrapNote()`。视图 worker 可以替换实现，但在 shell 派发契约变更前不要改名/删除。

### 视图 worker 的接入口（已实现）

`textura.core.data` 导出 `ViewContext`，视图**不得 import shell**，只依赖这个结构：

```cangjie
// textura.core.data.store
public class ViewContext {
    public let store: AppStore      // 唯一事实来源：store.state.value()
    public let theme: String        // "light" | "dark"
    public let today: String        // "YYYY-MM-DD"；parity 下来自 workspace 锚点，不读系统时钟
    public let width: Int64
    public let height: Int64
    public let navigate: (String) -> Unit   // 视图内跳转，参数为 route id
}
```

每个视图包必须暴露：

```cangjie
public func render(ctx: ViewContext): Unit
```

由 shell 在自己的 CUI 声明块内调用（`render` 每帧执行，直接读 `ctx.store.state.value()` 即为响应式）。
视图内部的纯函数可以放在 `src/views/<name>/logic/`，但**领域事实只能从 `core.data` 读**，
写操作只能走 `ctx.store.*`。完整 API 见 `docs/CORE-API.md`。

### 视图派发契约（`textura.shell`）

```cangjie
public type ViewRenderer = (ViewContext) -> Unit
public func viewRendererFor(route: Route): ViewRenderer   // 该路由的内容槽渲染函数
public func renderRoute(route: Route, viewCtx: ViewContext): Unit
```

- `renderRoute` 在 `try/catch` 中调用 `viewRendererFor(route)(ctx)`；视图抛异常时替换为
  `RouteErrorBoundary` 恢复卡，外壳（侧栏/顶栏）保持可用。
- 每个 `case` 的目标是 `<view>.render`（七条路由都已落地）；新增路由才需要变更 `dispatch.cj`，
  切换/替换某视图实现不改契约。
- `ViewContext.width/height` 由 shell 传**窗口逻辑尺寸**（parity 为 1440×900），与 Web
  `window.innerWidth/Height` 同义；视图自行做响应式断点。
- 视图包不得 import `textura.shell`；跳转一律走 `ctx.navigate("<route id>")`。
- 原生崩溃（SIGSEGV 等）无法被 `renderRoute` 捕获；视图必须保证 `draw` 中的文本/字体参数有效。

### UI API 命名空间约定（`textura.ui`）

`cui.*` 与 `textura.ui.*` 是同级通配导入，若 `textura.ui` 再导出 `Button` / `Badge` /
`Modal` / `Icon` 等同名符号，视图里的裸调用会直接编译失败（实测 `cjc 1.2.0`）。因此：

- 控件入口统一挂在 `public struct Ui` 上：`Ui.button(...)`、`Ui.iconButton(...)`、
  `Ui.badge(...)`、`Ui.progress(...)`、`Ui.segmented(...)`、`Ui.field(...)` /
  `Ui.textInput(...)` / `Ui.textArea(...)`、`Ui.modal(...)`、`Ui.emptyState(...)`、
  `Ui.icon(...)`、`Ui.divider(...)`、`Ui.tooltip(...)`。所有入口第一个参数是 `theme: Theme`。
- 图标枚举为 `IconGlyph`（原 `IconName` 会与 CUI 冲突）；直接实例用 `IconView`，
  其余控件实例为 `ButtonView` / `IconButtonView` / `BadgeView` / `ProgressView` /
  `SegmentedView` / `ModalHost`。
- 颜色/尺寸/字号只从 `tokensOf(theme)` 取；视图与 shell 不写十六进制颜色。

在 shell 完成派发切换前，`bootstrapTitle()` / `bootstrapNote()` 仍需保留。

## 4. 每个视图的验收门槛

每个视图 worker 必须提交：

1. 该视图在 7 条路由中的 `ref/<route>-light.png` 与 `out/<route>-light.png` 对比结果（`tools/parity/diff.py` 输出）。
2. 两次独立运行的 CUI 截图逐像素一致（`diff.py` 自比或 `cmp`）。
3. 中文字形无缺字方框；1440×900 下无横向溢出。
4. 不改 Web 版源码、不改 `src/ui`/`src/core` 公共契约。
5. 若与参考图存在已知差异，必须写明原因与剩余差距，不能只报“通过”。

## 5. 字体与尺寸约定

- parity 固定字体族：`Noto Sans CJK SC`；系统文件 `/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc`（sha256 见 `assets/fonts/README.md`）。
- 窗口逻辑尺寸固定 1440×900；Xvfb 24 位色、DPR=1。
- 布局单位：间距/尺寸用 `vp`，文字与跟随字号的尺寸用 `fp`，设备像素级细节才用 `px`。
- 时区固定 `Asia/Shanghai`；parity 的“今天”来自 `workspace.json` 的 `updatedAt`（或 `--today`），不得读系统时钟。
- parity 运行时 store 必须用 `AppStore.forParity(anchorDate)` 构造（时钟与“今天”一起冻结，`ui.okrPeriod` 也按锚点季度选择）；
  交互运行才允许 `AppStore(clock: SystemClock())`。`nowIso()` / `emptyWorkspace()` 没有无参重载，读时钟必须显式注入 `Clock`。

## 6. 构建与运行入口

```bash
cd cangjie
source scripts/env.sh          # bash 或 zsh
./scripts/build.sh             # 增量构建 -> target/release/bin/textura
CLEAN=1 ./scripts/build.sh     # 从零完整构建
./scripts/parity.sh            # 7 条路由截图 -> tools/parity/out/
./scripts/diff.sh light        # 与参考图比对；超差返回非 0
```

不允许把 `target/`、`tools/parity/out/` 提交到 git。参考图 `tools/parity/ref/`、`workspace.json` 必须提交。

## 7. 代码风格

- 每个目录必须有 `.cj` 文件；Cangjie 不会扫描没有包文件的中间目录。
- 每个包文件第一行 `package <全名>`；公共 API 加 `public`。
- 写代码前加载 `cangjie-coding` 技能；语言/标准库问题再加载 `cangjie-language-basic`。
- 不凭记忆臆造 CUI API；先查 `third_party/CUI/docs/api` 与 `docs/guide`。
- 提交信息英文；文档中文。
