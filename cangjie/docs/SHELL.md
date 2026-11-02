# `textura.shell` — 应用外壳手册

本文件是 `cangjie/src/shell/**` 的契约与实现说明：布局几何、路由派发、状态机、快捷键、
浮层、持久化，以及与 Web 版 `src/app/AppShell.tsx` / `Sidebar.tsx` / `TopBar.tsx` /
`src/modules/appshell/**` 的逐项差异。

- 移植来源（只读）：`src/app/{AppShell,Sidebar,TopBar,routes,RouteErrorBoundary,RouteLoading}.tsx`、
  `src/styles/shell.css`、`src/modules/appshell/{appshell.css,QuickCapture.tsx,CommandPalette.tsx,
  ShortcutsDialog.tsx,useGlobalHotkeys.ts,captureParser.ts,fuzzy.ts,navigation.ts,workspaceIO.ts,
  importValidation.ts}`、`src/core/routeState.ts`。
- 依赖方向：`main -> shell -> views`，`shell -> ui -> core.data`（见 `docs/STRUCTURE.md` §2）。
- 颜色只从 `textura.ui` 令牌取；唯一例外是领域数据 `Area.color`（`#RRGGBB`，由 `chrome.cj`
  的 `hexColor` 解析）。尺寸用 `vp`，字号用 `fp`。

## 1. 目录与职责

| 文件 | 职责 |
|---|---|
| `appshell.cj` | `ShellHost`（导航/主题/撤销/面板/收集/导出/快捷键）、`buildShell` 根布局、侧栏数据装配、加载与错误屏分支 |
| `chrome.cj` | 外壳几何常量（每条注明 CSS 来源）、`themeByName`、发丝线、`hexColor`、字距绘制 |
| `routes.cj` | `Route` / `ROUTES` / `parseRoute` / `routeId`（冻结契约）＋ `routeLabel` / `routeMetaTitle` / `routeSubtitle` / `routeGlyph`（对齐 `src/app/routes.ts`） |
| `dispatch.cj` | `ViewRenderer` 契约、`viewRendererFor`、`renderRoute`（含路由错误卡兜底）、`placeholderView` |
| `sidebar.cj` | `SidebarView`：品牌标记、导航、领域、保存状态 footer |
| `topbar.cj` | `TopBarTitlesView` + 搜索框 + 主题按钮 |
| `capture_parser.cj` | 收集语法（`#标签` `@场景` `!能量` `/日期`）纯函数 |
| `fuzzy.cj` | 命令面板打分 / 排序 / 最近使用 / 高亮切片 |
| `palette.cj` | 命令面板浮层 + 命令表 |
| `capture.cj` | 快速收集浮层（解析预览、会话列表、撤销） |
| `shortcuts.cj` | 快捷键帮助浮层（6 组） |
| `notices.cj` | 右下角通知堆叠（tone 配色、自动消失） |
| `kbd.cj` | palette / capture / shortcut 三种 `kbd` 芯片 |
| `screens.cj` | 加载屏、工作区加载失败屏、路由渲染错误卡 |
| `runtime.cj` | 保存节流状态机、通知生命周期、收集会话、`$HOME/.textura/ui-prefs.json` 偏好 |

## 2. 布局几何（逐值对齐 `src/styles/shell.css`）

```
┌──────────────────────────── 1440 × 900（最小 1024 × 640） ───────────────────────────┐
│ sidebar 240（bg-subtle，右侧 1px border） │ topbar 56（bg，底部 1px border）          │
│                                          ├──────────────────────────────────────────┤
│  brand 56：30×30 墨底圆角 8 +          │ shell-content：唯一滚动区，padding 24     │
│    workflow 17px、Textura 15/680、      │   max-width 1280 由各视图自己的 .page 负责 │
│    织理 11/.18em                        │                                          │
│  scroll padding 16/12，nav 行高 34.25   │                                          │
│    （7px 内边距 + 13.5px×1.5），gap 2   │                                          │
│  gap 24 → 领域标题 11/600/.08em        │                                          │
│    行高 16.5 + 下内边距 8               │                                          │
│  area 行高 31.5（6px + 13px×1.5），gap 2 │                                          │
│  footer：1px border + 12/16 内边距，     │                                          │
│    两行 11.5px，gap 8                    │                                          │
└──────────────────────────────────────────┴──────────────────────────────────────────┘
```

- 根布局：`HStack(spacing: 0) { SidebarView(width 240).fillHeight(); VStack { TopBar; ScrollView } }`，
  整体 `.background(tokens.color.bg)`；只有 `ScrollView(key: "shell-content")` 滚动。
- 内容可用宽度 = `1440 - 240（侧栏） - 24×2（内容 padding） = 1152`；滚动条**不占槽、不绘制**
  （overlay 语义，见 §2.1）。实测页面右边缘 1417px，参考图 1416px（1px 抗锯齿差）。
- 侧栏 active 项：`surface` 底 + `shadow-1` + 图标换 `accent` + 文本 600；hover 用 `surface-2`。
- GTD 导航项显示 `countByStatus(workspace)["inbox"]`，为 0 时不显示（`Sidebar.tsx:49`）。
- 领域计数 = `areaId == area.id && status ∉ {done, dropped}`。
- footer：`idle/saved → --ok`、`saving → --warn`、`error → --danger`；第二行 `${items} 条记录 · v${version}`。
- 顶栏：标题 16px/650（见 §7.1）、副标题 12px `text-faint`、基线对齐、间距 12；搜索框
  `flex: 0 1 320px; min-width: 180`（`TopBar.tsx` inline 样式），高 37；右侧 ghost `IconButton` 34×34，
  `sun`/`moon` 17px。
- 顶栏 55px 内容带 + 1px `Divider` = CSS 的 56px（border-box）。

### 2.1 内容滚动容器（CUI-P02）

Web 的 `.shell-content { overflow: auto }` 在参考图里使用 overlay 滚动条：内容始终占满 1152px，
滚动条浮在内容之上且截图中不可见。CUI 0.9.6 的 `ScrollView` 溢出时会固定预留
`6 + 2×2 = 10px` 槽（`third_party/CUI/src/core/scrolling.cj`），会把每个视图整体左移 10px。

处理：给 vendored CUI 打最小补丁 **CUI-P02-overlay-scrollbar**（见 `third_party/README.md`），
外壳使用：

```cangjie
ScrollView(key: "shell-content") { ... }
  .scrollBarVisible(false)      // 不预留槽、不画拇指
  .keyboardScroll(true)         // PageUp/PageDown/Home/End
  .revealFocusedOnFocus(true)   // Tab 键盘焦点进入视口
```

- 滚轮：沿用 CUI 每格 72 逻辑像素，到边界时事件继续冒泡；`scrollState` 外部偏移仍可用。
- 键盘：`PageUp/PageDown` = 0.9 视口（实测 200px 视口 → 180px），`Home` = 0，`End` = 最大偏移；
  按键先交给内容子树（文本框保留自己的 Home/End），未消费才滚动，到边界不再消费。
- Tab 聚焦：CUI 没有控件矩形 API，按焦点项在 `focusableIds()` 中的序号估算目标位置并滚动到可见；
  仅 `ctx.showFocusRing`（键盘聚焦）触发，鼠标点击聚焦不滚动。这是声明顺序≈视觉顺序的近似。
- 裁剪：沿用 CUI 的 spatial clip（滚动轴裁剪 + 交叉轴 paint overflow 保留），未改动。
- 不保留：滚动条拖拽（无拇指）、惯性/平滑滚动、滚动条 hover 态；快照与原 Web 参考图一致。

## 3. 路由与视图派发契约

```cangjie
// textura.shell
public type ViewRenderer = (ViewContext) -> Unit
public func viewRendererFor(route: Route): ViewRenderer
public func renderRoute(route: Route, viewCtx: ViewContext): Unit
```

- 每个视图包暴露 `public func render(ctx: ViewContext): Unit`，**不得 import `textura.shell`**；
  需要跳转用 `ctx.navigate("gtd")`。
- `renderRoute` 在 `try/catch` 内调用视图：视图抛异常时换成 `RouteErrorBoundary` 的恢复卡
  （620px、8vh、3px danger 左边、返回今日/重新加载/查看数据目录），外壳不白屏。
  原生崩溃（SIGSEGV）无法被捕获，见 §7.8。
- `ViewContext.width/height` 传**窗口逻辑尺寸**（1440×900），与 Web 的 `window.innerWidth`
  语义一致；视图自己做响应式断点。
- 当前派发状态（2026-10-23）：

| 路由 | 派发目标 | 状态 |
|---|---|---|
| dashboard | `dashboard.render` | 真实视图 |
| calendar | `calendar.render` | 真实视图 |
| okr | `okr.render` | 真实视图 |
| gtd | `gtd.render` | 真实视图 |
| gantt | `gantt.render` | 真实视图 |
| sop | `sop.render` | 真实视图 |
| settings | `settings.render` | 真实视图 |

视图落地后只需把 `dispatch.cj` 对应 `case` 从 `placeholderView(...)` 换成
`{viewCtx => <view>.render(viewCtx)}`，共享代码形状不变。

## 4. 状态机

### 4.1 保存状态（`Sidebar` 四态）

| 状态 | 触发 | 圆点 | 文案 |
|---|---|---|---|
| `idle` | 初始 / `saved` 显示 1.4s 后 | `--ok` | 自动保存已开启 |
| `saving` | `store.state.revision()` 变化后 | `--warn` | 正在保存… |
| `saved` | 防抖 400ms 到期且 `store.save()` 成功 | `--ok` | 已保存 |
| `error` | `store.save()` 失败或 `store.saveStatus() == Error` | `--danger` | 保存失败 |

- `ShellRuntime.observeWorkspace` 每帧比较 `state.revision()`；变化即进入 `saving` 并记
  `elapsed + 400ms` 的截止时间。
- 只要处于 `saving/saved` 或存在通知，`buildShell` 用 `FrameHandler` 包住界面续帧；
  其余时间纯事件驱动。计时来自 `UiEvent.Frame.elapsedMs`，**不读系统时钟**。
- parity 快照不修改工作区 → 永远 `idle`，两次运行逐像素一致。

### 4.2 通知（toast）

- 来源：`AppStore.notify(...)`，最多 4 条；`ShellRuntime` 为每条记 `elapsed + 5000ms` 的截止时间。
- 到点调用 `store.dismissNotice(id)`；`FrameHandler` 在通知存续期间保持续帧。
- 位置与配色见 §5.4。

### 4.3 主题与路由持久化

- 事实来源：`AppStore.ui`（`route` / `theme` 等）。
- 主题切换立即生效：`buildShell` 每帧按 `ui.theme` 取 `texturaLight()/texturaDark()` 的令牌重绘，
  包括自绘外壳、`Ui.*` 控件与弹窗。
- 路由切换：侧栏点击 / 命令面板 / `ctx.navigate` 写 `store.setRoute`，下一帧重建。
- 持久化（对应 `routeState.ts` 的 localStorage）：`$HOME/.textura/ui-prefs.json`
  （`{"route","theme","recent":[…]}`），**仅交互模式**写；`--snapshot` 运行既不读也不写，
  保证截图确定性。优先级：显式 `--route/--theme` > 记忆 > 默认 `dashboard/light`。
- 主题/路由无变化时不写文件（`ShellRuntime.persistUi` 去抖）。

### 4.4 工作区加载

- `main.cj` 在 `app.run` 前同步 `store.load(path)`；`--workspace` 缺省为 `textura-workspace.json`。
- `store.storeStatus() == Loading` → 加载屏（34px 旋转环 + 「正在织理工作区…」）。
- 加载抛异常 → 全窗错误屏（加粗标题 + 原因 + 重试按钮），不进入外壳。

## 5. 浮层

### 5.1 命令面板（`CommandPalette`，640px）

- 搜索行：`surface-2` 底、1px `border`、radius 8、高 41、9/12 内边距；搜索图标 16px；
  透明 `TextField`（`key: palette-search`，14px）；右侧 `Esc` kbd 芯片。
- 结果区：`max-height: 360px` 滚动；行网格 `18px / 1fr / auto`、gap 12、7/8 内边距；
  active 行 = `surface-2` 药丸 + 2px `accent` 内嵌条；标签 13px、hint 11px 右对齐；
  命中片段用 `accent-soft` 底 + `accent` 文字。
- 分组：最近使用 / 命令 / 条目 / 领域；标题 10.5px/600 + .08em 字距 + `text-faint`。
- 键盘：`↑/↓` 跳过禁用项循环；`Enter` 执行；`Tab`/`⇧Tab` 跳分组；`Esc` 关闭。
- 命令表与 `CommandPalette.tsx` 一致：新建 SOP / 目标 / KR、快速收集、切换主题、撤销、重做、
  导出工作区、打开设置、前往 7 个视图。条目结果按 `fuzzy.ts` 打分（标题 > 标签 > 祖先路径），
  最近使用写回 prefs。

### 5.2 快速收集（`QuickCapture`，560px）

- 标题「收集到 GTD 收件箱」；正文 12px 栈：标签、15px 输入（`key: capture-input`，44.5 高）、
  解析预览 chips（标签 accent / 场景 info / 能量 warn / 到期 ok）、语法提示（`<code>` 芯片 + 11.5px 说明）、
  会话区（顶部 1px 分隔、标题 + 数量、空态文案或行列表、垃圾桶撤销）。
- 行为：`Enter` 收集并保持打开（清空输入）；`⌘/Ctrl+Enter` 收集并关闭；`Esc` 关闭；
  `#/@/!//` 语法见 `capture_parser.cj`，日期以 `ViewContext.today`（parity 锚点）为基准。
- 提交生成 `kind=action, status=inbox`，`tags`、`gtd.context`、`gtd.energy`、`gantt.end` 一并写入；
  会话内撤销会 `deleteItems` 并通知。

### 5.3 快捷键帮助（`ShortcutsDialog`，600px）

- 6 组：全局 / 命令面板 / 快速收集 / GTD / SOP / 甘特；每组标题 12.5/650 + 11px 作用域，
  表格键位列 168px，键帽为 10.5px mono、`surface-2`、1px border（底边 2px）、radius 4；
  行间 1px 分隔，行内上下 5px；底部一条 11.5px 说明。

### 5.4 通知（toast）

- 位置：右下角，`right/bottom: 24px`，列向 gap 8，最早的在最上方（容器底对齐，故堆叠向上生长）。
- 卡片：宽 220–360（按文本自适应），padding 12/16，1px `border`，radius 8，`--shadow-2`，
  13px 文本；左侧 3px tone 条（success `--ok` / error `--danger` / info `--info`）。
- 自动消失 5s；容器与卡片都不吃指针事件。

### 5.5 路由错误卡（`RouteErrorBoundary`）

- 视图抛异常时替换内容区：620px 卡、上边距 8vh、padding 32、radius 14、`shadow-1`、3px danger 左边；
  文案「视图渲染失败 / 这个视图暂时无法显示 / 工作区数据仍在…」+ 异常文本 + 三个动作按钮。

## 6. 快捷键表

| 快捷键 | 作用 | 作用域 |
|---|---|---|
| `⌘/Ctrl + K` | 打开/关闭命令面板 | 全局 |
| `⌘/Ctrl + N`（含 `⇧ + N`） | 打开快速收集 | 全局 |
| `⌘/Ctrl + Z` | 撤销工作区修改 | 全局，GTD/SOP 视图内交给视图，输入框内交给编辑框 |
| `⌘/Ctrl + ⇧ + Z` | 重做 | 同上 |
| `?`（`⇧ + /`） | 快捷键帮助 | 全局，输入框内不触发 |
| `Esc` | 关闭最上层浮层 | 全局/弹窗 |
| `↑` `↓` | 移动命令面板高亮 | 命令面板 |
| `Enter` | 执行命令面板选中项 | 命令面板 |
| `Tab` / `⇧ + Tab` | 命令面板切换分组 | 命令面板 |
| `Enter` | 收集并继续下一条 | 快速收集 |
| `⌘/Ctrl + Enter` | 收集并关闭 | 快速收集 |
| `Enter` / `Space` | 激活侧栏导航项 | 侧栏（键盘焦点） |

实现：`ShellHost.handleHotkey` 用 `EventHandler` 包住整棵树，修饰键从
`ctx.eventModifiers()` 读取（事件时刻快照）。输入框判定为近似实现：焦点 id 是
`shell-search` / `capture-input` / `palette-search`，或以 `-input/-search/-note/-title` 结尾。

## 7. 与 Web 版的差异（逐项）

1. **顶栏标题字号**：任务描述写「20px/650」，但 `src/styles/shell.css:228-233` 与参考图实测
   （「今日」墨迹宽 29px、高 16px）都是 **16px/650**。实现按源码，`TopBar.tsx` 的
   `subtitle` 12px 亦同。
2. **通知位置**：任务描述写「右上堆叠」，源码 `src/styles/shell.css:312-321` 是
   `right: 24px; bottom: 24px`（右下），实现遵循源码与参考图。
3. **字重**：CSS 550/600/620/650/680 是可变字重；`Textura UI` 只注册 Regular/Medium(500)/
   DemiLight(350)/Bold，600 以上取 Bold，视觉差异被合并（与 `docs/UI-KIT.md` §6.2 同因）。
4. **字距**：CUI 无 `letter-spacing` API，品牌名/品牌副标/分组标题/眉标按逐字定位实现
   （`textTracked`）；其余单行文本不带字距。
5. **主题切换**：CUI `Theme` 是不可变值，`DesktopApp` 构造后不能替换。外壳每帧按
   `ui.theme` 取令牌重绘（自绘 chrome、`Ui.*` 控件、弹窗一致），原生滚动条等 CUI 内建
   chrome 仍停留在启动主题；重启后完全一致。
6. **弹窗页脚对齐**：`Ui.modal` 的 footer 由 `ModalHost` 以 `Spacer` 右对齐，「Enter 继续收集」
   提示无法像 Web 的 `margin-right:auto` 贴左，当前与按钮同组靠右。
7. **持久化位置**：Web 用 `localStorage`；桌面用 `$HOME/.textura/ui-prefs.json`，且只在交互模式读写。
   `--snapshot` 完全忽略记忆值，保证跨机器/跨会话的截图确定性。
8. **SOP 视图渲染崩溃（已由 SOP worker 修复）**：曾出现 `paintEdgeLabel → textLeading → Renderer.text`
   的原生 SIGSEGV（`text_glyph_atlas.cj:180`）；当前 `--route sop` 的 light/dark 快照均正常退出。
9. **导出工作区**：Web 走 Tauri 原生保存对话框；桌面版没有 Rust 命令，命令面板导出写到
   工作区同目录的 `textura-workspace-YYYYMMDD-HHmm.json` 并通知路径。
10. **导入**：`workspaceIO.ts` / `importValidation.ts` 的 Tauri 文件选择在桌面版没有等价入口；
    `core.data` 的 `store.importDocument` 已具备严格校验能力，设置页后续可接。
11. **动画**：`--transition`、`modal-fade/modal-rise`、加载环旋转在快照里不参与；加载环为静态近似。
12. **滚动条**：内容区使用 overlay 语义（CUI-P02）：不预留槽、不绘制拇指，内容宽度与 Web 的
    1152 一致；保留滚轮（72/格）、`PageUp/PageDown/Home/End` 与 Tab 聚焦滚动；不保留滚动条拖拽、
    惯性滚动与滚动条 hover 视觉。其他 CUI `ScrollView`（弹窗正文、命令面板结果）仍使用默认滚动条。

## 8. Parity 验收（2026-10-23，1440×900，DPR=1，Noto Sans CJK SC）

命令（快照内执行，`~/.cache/cj-shell`）：

```bash
unset WAYLAND_DISPLAY
xvfb-run -a -s "-screen 0 1440x900x24" ./target/release/bin/textura \
  --workspace tools/parity/workspace.json --route dashboard --theme light \
  --width 1440 --height 900 --snapshot shots/dashboard-light.png
```

外壳区域口径：`x < 240`（侧栏）或 `y < 56`（顶栏）。加权 SSIM 按面积
（240×900 与 1200×56）合并；另加 1px 高斯模糊后的 SSIM，用于抵消跨引擎文字抗锯齿差异。

| 主题 | 侧栏原始 SSIM | 顶栏原始 SSIM | 外壳加权原始 SSIM | 外壳 ΔRGB≤32 | 侧栏 blur1 | 顶栏 blur1 | 外壳加权 blur1 SSIM |
|---|---:|---:|---:|---:|---:|---:|---:|
| light | 0.9797 | 0.9589 | **0.9748** | **98.32%** | 0.9940 | 0.9913 | **0.9934** |
| dark | 0.9791 | 0.9569 | **0.9738** | **98.39%** | 0.9936 | 0.9915 | **0.9931** |

整图（真实视图；CUI-P02 生效后，内容宽度已恢复为 1152）：

| 路由 | light 原始 SSIM | light blur1 | light ΔRGB≤32 | dark 原始 SSIM | dark blur1 | dark ΔRGB≤32 |
|---|---:|---:|---:|---:|---:|---:|
| dashboard | 0.9605 | 0.9879 | 97.29% | 0.9611 | 0.9883 | 97.53% |
| calendar | 0.9625 | 0.9868 | 97.93% | 0.9647 | 0.9875 | 98.04% |
| okr | 0.9273 | 0.9710 | 96.41% | 0.9346 | 0.9737 | 96.61% |
| gtd | 0.9009 | 0.9653 | 95.69% | 0.9052 | 0.9681 | 96.19% |
| gantt | 0.9668 | 0.9851 | 98.39% | 0.9678 | 0.9871 | 98.46% |
| sop | 0.8883 | 0.9532 | 96.24% | 0.8865 | 0.9543 | 96.47% |
| settings | 0.9182 | 0.9587 | 95.54% | 0.9205 | 0.9609 | 95.95% |

整图数值只作参考：内容区由各视图 worker 负责，外壳部分是上表。
7 条路由全部切到真实视图（`--route` 直接渲染，不依赖交互），light/dark 均正常退出。

确定性：dashboard 两次独立运行 `sha256` 一致（light `65946bce…`、dark `33aeedbc…`）；
其余路由各跑一遍均 exit 0（内容由各视图 worker 继续调整）。

构建：上述数值来自共享工作树的完整快照（`~/.cache/cj-shell`，`rsync` 后 `cjpm build` 成功，
外壳零 warning）；各视图包由对应 worker 并行维护。

### 8.1 CUI-P02 前后的内容宽度

| 项目 | 修复前（CUI 默认槽） | 修复后（CUI-P02） | 参考图 |
|---|---:|---:|---:|
| 内容可用宽度 | 1142（1200 − 10 槽 − 48 padding） | **1152** | 1152 |
| 页面右边缘像素 | ≈1406 | **1417** | 1416 |
| dashboard light 原始 SSIM | 0.9085 | **0.9605** | — |
| dashboard light ΔRGB≤32 | 96.30% | **97.29%** | — |

滚动容器行为实测（headless `WidgetTestHost` 200px 视口、800px 内容）：
`PageDown → 180`、再按 → `360`、`End → 600`、`Home → 0`；滚轮仍按 72/格，
到边界事件继续冒泡。Tab 聚焦滚动为按焦点序号的近似实现，实际桌面窗口中以键盘 Tab 验证。
