# `textura.ui` 控件与令牌手册

本文件是 `cangjie/src/ui/**` 的契约文档：设计令牌、字体、基础控件、图标的尺寸/颜色/状态表，
每条都标注 Web 版 CSS 来源行号；末尾列出已知差异与 CUI 能力缺口。

- 移植来源（只读）：`src/styles/tokens.css`、`src/styles/base.css`、`src/ui/ui.css`、`src/ui/*.tsx`。
- 包名：`textura.ui`；依赖方向 `views/shell -> ui -> core.data`，`ui` 不 import `shell`/`views`。
- 陈列页：`cangjie/src/ui/kit_demo.cj` 的 `public func demo()`（1440×900 一屏同时给出 light 与 dark）。

## 0. 命名与调用约定（务必先读）

CUI 0.9.6 已经导出 `Button`、`IconButton`、`Badge`、`Modal`、`Divider`、`Tooltip`、`Icon`、
`IconName`。仓颉把 `import cui.*` 与 `import textura.ui.*` 视为**同级通配导入**，一旦
`textura.ui` 也导出同名符号，视图里任何裸 `Button(...)` 都会直接编译失败：

```text
error: ambiguous use of 'Button'
note: found imported candidate  (import cui.*)
note: found imported candidate  (import textura.ui.*)
```

（实测：`cjc 1.2.0`；即使用 `import textura.ui.{Button}` 显式导入也无法压过 `import cui.*`。）

因此控件入口统一挂在命名空间结构体 `Ui` 上，图标枚举改名为 `IconGlyph`：

| Web 版 | 仓颉移植 |
|---|---|
| `<Button variant size iconLeft iconRight block>` | `Ui.button(theme, label, onClick, variant:, size:, iconLeft:, iconRight:, block:, enabled:)` |
| `<IconButton variant size label>` | `Ui.iconButton(theme, glyph, onClick, variant:, size:, tooltip:, enabled:)` |
| `<Badge tone dot>` | `Ui.badge(theme, text, tone:, dot:)` |
| `<Progress value tone size showLabel>` | `Ui.progress(theme, value, tone:, size:, showLabel:)` |
| `<Segmented options value onChange size>` | `Ui.segmented(theme, items, selected, size:)` / `Ui.segmentedWithGlyphs(...)` |
| `<Field label hint error required>` | `Ui.field(theme, label:, hint:, error:, required:) { <控件> }` |
| `<TextInput>` / `<TextArea>` | `Ui.textInput(theme, bindable, key:, placeholder:, invalid:, enabled:)` / `Ui.textArea(...)` |
| `<Modal open onClose title description footer width>` | `Ui.modal(theme, presented, onDismiss, title:, description:, width:, footer:, body:)` |
| `<EmptyState icon title description action compact>` | `Ui.emptyState(theme, title, description:, glyph:, compact:, action:)` |
| `<Icon name size>` | `Ui.icon(theme, glyph, side:, color:)` |
| 分隔线（`1px solid var(--border)`） | `Ui.divider(theme, axis:, color:)` |
| `title={label}` 悬停提示 | `Ui.tooltip(theme, text) { ... }` |

**所有 `Ui.*` 的第一个参数都是 `theme: Theme`。** 原因有两条：构建期（`Label` 颜色、`Divider` 颜色、
`TextField` 的 `TextInputStyle`）拿不到 `UiContext`；以及同一棵树里要能同时渲染 light 与 dark
（`kit_demo` 就是左右双主题页）。控件内部用 `tokensOf(theme)` 取令牌，绝不硬编码 hex。

需要裸控件实例时用 `ButtonView` / `IconButtonView` / `BadgeView` / `ProgressView` /
`SegmentedView` / `ModalHost` / `IconView`（构造函数签名与 `Ui.*` 一致，首参 `tokens: ThemeTokens`）。

## 1. 设计令牌 `ThemeTokens`

`ThemeTokens` 把 `tokens.css` 的每个自定义属性落成一个强类型字段，并分组访问：

```cangjie
let tk = tokensOf(theme)          // 也可是 ThemeTokens.light() / ThemeTokens.dark()
let surface = tk.color.surface     // --surface
let gap = tk.space.s2              // --space-2 = 8
let radius = tk.radius.md          // --radius-md = 8
let ring = tk.metrics.focusRingWidth // --focus-ring 的可见强调带宽 = 2
```

| 访问器 | CSS 变量 | CSS 行号 |
|---|---|---|
| `color.bg` / `bgSubtle` | `--bg` / `--bg-subtle` | 8-9 / 66-67 |
| `color.surface` / `surface2` | `--surface` / `--surface-2` | 10-11 / 68-69 |
| `color.border` / `borderStrong` | `--border` / `--border-strong` | 12-13 / 70-71 |
| `color.text` / `textMuted` / `textFaint` | `--text` / `--text-muted` / `--text-faint` | 14-17 / 72-75 |
| `color.accent` / `accentSoft` | `--accent` / `--accent-soft` | 18-19 / 76-77 |
| `color.accentStrong`(+`Hover`/`Active`/`Disabled`) | `--accent-strong*` | 21-24 / 78-81 |
| `color.dangerStrong`(+`Hover`/`Active`/`Disabled`) | `--danger-strong*` | 25-28 / 82-85 |
| `color.textOnStrong` | `--text-on-strong` | 29 / 86 |
| `color.accentInk` / `okInk` / `warnInk` / `dangerInk` / `infoInk` | `--*-ink` | 30-34 / 87-91 |
| `color.ok` / `warn` / `danger` / `info` | `--ok` … `--info` | 35-38 / 92-95 |
| `radius.sm` / `md` / `lg` | `--radius-sm|md|lg` | 40-42 |
| `space.s1..s6` | `--space-1..6` | 47-52 |
| `metrics.sidebarWidth` / `topbarHeight` | `--sidebar-width` / `--topbar-height` | 58-59 |
| `metrics.focusRingWidth` / `focusRingGap` | `--focus-ring` 的两段（2px 强调 + 2px surface 间隔） | 60 / 100 |
| `metrics.borderWidth` | `border: 1px` 全仓约定 | `base.css` / `ui.css` 各条 |
| `shadow1` / `shadow1Contact` / `shadow2` | `--shadow-1`（两层）/ `--shadow-2` | 44-45 / 97-98 |

### 1.1 逐值核对表（light → dark）

浅色块 `tokens.css:5-61`，深色块 `tokens.css:63-101`；`TokenColors` 字段与值一一对应，**无缺项、无改值**。

| 令牌 | light hex / RGB | dark hex / RGB |
|---|---|---|
| `bg` | `#f6f2ec` 246,242,236 | `#1b1815` 27,24,21 |
| `bgSubtle` | `#efe9e0` 239,233,224 | `#211d19` 33,29,25 |
| `surface` | `#fffcf7` 255,252,247 | `#26221e` 38,34,30 |
| `surface2` | `#f4eee6` 244,238,230 | `#2f2a25` 47,42,37 |
| `border` | `#e3dace` 227,218,206 | `#3a342d` 58,52,45 |
| `borderStrong` | `#cfc3b3` 207,195,179 | `#4c443b` 76,68,59 |
| `text` | `#24201c` 36,32,28 | `#ece4da` 236,228,218 |
| `textMuted` | `#6a6057` 106,96,87 | `#b3a89b` 179,168,155 |
| `textFaint` | `#6f665c` 111,102,92 | `#a0958a` 160,149,138 |
| `accent` | `#c0663a` 192,102,58 | `#d97a4c` 217,122,76 |
| `accentSoft` | `#f4e2d6` 244,226,214 | `#3b2a22` 59,42,34 |
| `accentStrong` | `#b05a32` 176,90,50 | `#b05a32` 176,90,50 |
| `accentStrongHover` | `#a8542c` 168,84,44 | `#a8542c` 168,84,44 |
| `accentStrongActive` | `#9e4a25` 158,74,37 | `#9e4a25` 158,74,37 |
| `accentStrongDisabled` | `#807065` 128,112,101 | `#807065` 128,112,101 |
| `dangerStrong` | `#a8453a` 168,69,58 | `#b64c41` 182,76,65 |
| `dangerStrongHover` | `#923a30` 146,58,48 | `#a8453a` 168,69,58 |
| `dangerStrongActive` | `#7f322a` 127,50,42 | `#9a3d34` 154,61,52 |
| `dangerStrongDisabled` | `#8a6b64` 138,107,100 | `#8a6b64` 138,107,100 |
| `textOnStrong` | `#fffaf5` 255,250,245 | `#fffaf5` 255,250,245 |
| `accentInk` | `#8f4523` 143,69,35 | `#e7a37c` 231,163,124 |
| `okInk` | `#3f6542` 63,101,66 | `#97c09a` 151,192,154 |
| `warnInk` | `#7d5516` 125,85,22 | `#e3b975` 227,185,117 |
| `dangerInk` | `#8f372e` 143,55,46 | `#e59a8f` 229,154,143 |
| `infoInk` | `#3c5c78` 60,92,120 | `#a3c3dd` 163,195,221 |
| `ok` | `#4f7a52` 79,122,82 | `#7ba67e` 123,166,126 |
| `warn` | `#a8762a` 168,118,42 | `#d2a45c` 210,164,92 |
| `danger` | `#a8453a` 168,69,58 | `#d07366` 208,115,102 |
| `info` | `#4a6f8f` 74,111,143 | `#7fa4c4` 127,164,196 |
| `shadow1` | `0 1px 2px rgba(36,32,28,.06)` + `0 1px 0 rgba(36,32,28,.03)` | `0 1px 2px rgba(0,0,0,.4)` + `0 1px 0 rgba(0,0,0,.2)` |
| `shadow2` | `0 10px 28px rgba(36,32,28,.14)` | `0 12px 32px rgba(0,0,0,.5)` |
| `radius` / `space` / `metrics` | 两主题相同：4/8/14、4/8/12/16/24/32、240/56/2/2/1 | 同左 |

CSS 的 alpha 用 0-255 表示：`.06*255=15`、`.03*255=8`、`.14*255=36`、`.4*255=102`、
`.2*255=51`、`.5*255=128`。

`ThemeTokens.theme()` 把令牌映射到 CUI `Theme`（`bg/panel/panelEdge/text/mutedText/accent/
accentText/danger/field/fieldActive/panelRaised/accentSoft/shadow/radius/smallRadius/
controlRadius/borderWidth`），因此 CUI 内建 `Panel`/`Label().muted()`/`Divider`/`TextField`
与移植控件取色一致。`texturaLight()` / `texturaDark()` 只是 `ThemeTokens.light().theme()` 的
冻结入口。

### 1.2 主题反查：`tokensOf` 与显式传入

`Theme` 是不可变结构体、不带名字，所以「`Theme` → `ThemeTokens`」本质只能推断。本包的规则：

1. **有令牌就显式传。** 这是权威路径，也是唯一对「改过色的主题」正确的路径。
   - `Ui.*` 的形参是 `Theme`，传 `tokens.theme()` 即可（往返无损：`bg/panel/mutedText/accent`
     四项都能对上，`tokensOf` 会返回同一个令牌集合）。
   - 需要完全绕过推断时用控件构造器，首参就是 `ThemeTokens`：
     `ButtonView(tokens, ...)`、`IconButtonView(tokens, ...)`、`BadgeView(tokens, ...)`、
     `ProgressView(tokens, ...)`、`SegmentedView(tokens, ...)`、`ModalHost(tokens, ...)`、
     `IconView(...)`（颜色显式给）。
   - `Ui` 内部统一走 `tokensOf(theme, explicit: ...)`；调用方也可以在需要时直接调
     `tokensOf(theme, explicit: tk)`。
2. **没有令牌才推断。** `tokensOf(theme)` 只有在 `bg`、`panel`、`mutedText`、`accent`
   **四项同时**等于某个已知调色板时才认作 Textura 主题（旧的「只看 `bg`」会把「同底色、
   换了强调色」的主题误判成标准 light）。都不匹配时按 Rec.601 感知亮度在 light/dark 之间选，
   仅为兜底 CUI 内建 `Theme.light()`/`Theme.dark()`（测试、孤立控件），不作为契约。

```cangjie
let tk = tokensOf(theme)                        // 便捷：标准 light/dark 主题够用
let tkExact = tokensOf(theme, explicit: myTk)   // 显式：改过色的自定义主题必须这样用
let again = tkExact.theme()                     // 令牌 -> Theme 往返无损
```

视图侧建议：`ViewContext` 里同时带 `Theme` 与 `ThemeTokens` 时，一律用后者，
`Ui.*` 传 `tokens.theme()`，避免任何推断。

## 2. 字体

| 角色 | 注册名 | 来源 |
|---|---|---|
| UI（`--font-ui`） | `Textura UI` | `/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc`，`faceIndex: 2`（SC）；Bold/Medium(500)/DemiLight(350) 面同族 |
| Mono（`--font-mono`） | `Textura Mono` | `/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf`，回退到 CJK SC 面（保证中日韩字符不出方框） |
| parity 默认 | `Noto Sans CJK SC` | `--font` 默认值，`main.cj` 调 `configureFonts(cli.font)` 时同时注册上面两个族 |

- `configureFonts(fontName)`（`main.cj` 已调用）＝ `registerTexturaFonts()` + `Fonts.setDefault(fontName)`。
- `configureTexturaFonts()` 把默认族切成 `Textura UI`（交互运行用，parity 快照仍用 parity 字体）。
- `fontUi()` / `fontMono()` 返回族名；`FONT_UI_PARITY` 是 parity 族名常量。
- 字号常量 `TextSize`（CSS px，用 `.fp` 使用）：

| 常量 | 值 | CSS 来源 |
|---|---|---|
| `display` | 20 | `base.css:41` h1 |
| `heading` | 16 | `base.css:47` h2 |
| `subheading` | 15 | `ui.css:493` `.modal-title` |
| `body` | 14 | `base.css:14` html、`base.css:54` h3、`ui.css:389` |
| `bodyCompact` | 13.5 | `ui.css:28` `.btn--md`、`ui.css:189` `.input` |
| `controlSmall` | 12.5 | `ui.css:22` `.btn--sm`、`ui.css:396`、`ui.css:498` |
| `label` | 12 | `ui.css:169`、`ui.css:421` |
| `caption` | 11.5 | `ui.css:229`、`ui.css:234` |
| `micro` | 11 | `ui.css:249` `.badge`、`ui.css:353` `.progress-label` |

## 3. 基础控件

共通：`vp()` / `fp()` 把令牌像素转成 CUI `Length`；`fpSize(ctx, px)` 把 CSS px 转成带
fontScale 的逻辑像素；`focusRing()` 复刻 `--focus-ring`（见 3.9）。

### 3.1 Button（`ButtonView`，`ui.css:5-113`）

| 尺寸档 | 高 | 左右内边距 | 字号 | 图标边长 |
|---|---|---|---|---|
| `ControlSize.Sm` | 28 | 10 | 12.5 | 14 |
| `ControlSize.Md` | 34 | 14 | 13.5 | 16 |

盒模型：`display:inline-flex; align-items:center; justify-content:center; gap:8px;
border-radius:8px; border:1px solid transparent; font-weight:550; white-space:nowrap`。
宽度＝内容宽 + 左右内边距；`block` 时等于可用宽度。图标与文字之间按 `gap: 8px` 排列。

| 变体 | 常态 | hover | active | disabled |
|---|---|---|---|---|
| `Primary` | bg/border `accentStrong`，text `textOnStrong`，`shadow-1` | `accentStrongHover` | `accentStrongActive` | `accentStrongDisabled`（opacity 保持 1） |
| `Secondary` | bg `surface`，border `border`，text `text`，`shadow-1` | border `borderStrong`，bg `surface2` | 同 hover | 整控件 55% 不透明 |
| `Ghost` | 透明，text `textMuted` | bg `surface2`，text `text` | 同 hover | 55% 不透明 |
| `Danger` | bg/border `dangerStrong`，text `textOnStrong`（无阴影） | `dangerStrongHover` | `dangerStrongActive` | `dangerStrongDisabled` |

CSS 行号：`.btn` 6-17；`.btn--sm` 19-23；`.btn--md` 25-29；`.btn--block` 31-33；
primary 35-57；secondary 59-69；ghost 71-80；danger 82-103；`.btn-icon` 105-113。
禁用整体透明来自 `base.css:71-74`。

```cangjie
Ui.button(theme, "保存", {=> save()}, variant: ButtonVariant.Primary)
Ui.button(theme, "新建", {=> add()}, variant: ButtonVariant.Primary, iconLeft: IconGlyph.Plus)
Ui.button(theme, "筛选", {=> filter()}, iconRight: IconGlyph.ChevronDown, size: ControlSize.Sm)
Ui.button(theme, "整行", {=> go()}, block: true, enabled: false)
```

交互：鼠标按下即 `ctx.press(id)` 取焦点，按钮内松开触发；键盘 Enter/Space 在获得焦点时触发；
指针位于按钮上换 `CursorShape.Interactive`；`focusableId()` 在 `enabled=false` 时返回 `None`
（禁用控件退出 Tab 遍历）。

### 3.2 IconButton（`IconButtonView`，`ui.css:116-158`）

| 尺寸档 | 盒 | 图标 |
|---|---|---|
| `Sm` | 26×26 | 16 |
| `Md` | 34×34 | 18 |

`border-radius: 8px; border: 1px solid transparent; color: var(--text-muted)`。

| 变体 | 常态 | hover |
|---|---|---|
| `Ghost` | 透明，`textMuted` | bg `surface2`，`text` |
| `Secondary` | bg `surface`，border `border`，`shadow-1` | border `borderStrong`，`text` |
| `Danger` | `danger` 图标 | bg `color-mix(danger 12%, transparent)` |

`tooltip:` 非空时，悬停调用 `ctx.showTooltip(text, frame)`（对应 Web 的 `title={label}`）。

```cangjie
Ui.iconButton(theme, IconGlyph.Search, {=> open()}, tooltip: "搜索")
Ui.iconButton(theme, IconGlyph.Trash, {=> drop()}, variant: IconButtonVariant.Danger, size: ControlSize.Sm)
```

### 3.3 Badge（`BadgeView`，`ui.css:243-298`）

高 = `11px × 1.6 + 2×2px ≈ 22`；内边距 `2px 7px`；`border-radius: 999px`（用 h/2）；1px 边框；
字重 550；可选 5×5 `currentColor` 圆点，与文字间距 5px。

| `BadgeTone` | 背景 | 边框 | 文字 |
|---|---|---|---|
| `Neutral` | `surface2` | `border` | `textMuted` |
| `Accent` | `accentSoft` | `color-mix(accent 28%)` | `accentInk` |
| `Ok` | `color-mix(ok 12%)` | `color-mix(ok 30%)` | `okInk` |
| `Warn` | `color-mix(warn 14%)` | `color-mix(warn 32%)` | `warnInk` |
| `Danger` | `color-mix(danger 12%)` | `color-mix(danger 30%)` | `dangerInk` |
| `Info` | `color-mix(info 12%)` | `color-mix(info 30%)` | `infoInk` |

`color-mix(… p%, transparent)` 用 `tint(color, p)` 实现（同色 + p% alpha，合成结果等价）。

```cangjie
Ui.badge(theme, "通过", tone: BadgeTone.Ok)
Ui.badge(theme, "今天到期", tone: BadgeTone.Warn, dot: true)
```

### 3.4 Progress（`ProgressView`，`ui.css:301-358`）

| 尺寸档 | 轨道高 |
|---|---|
| `Sm` | 5 |
| `Md` | 8 |

轨道：`border-radius: 999px; border: 1px solid border; background: surface2`；填充内缩 1px
（`overflow: hidden` + border），颜色按 `ProgressTone`：`Accent`=`accent`、`Ok`=`ok`、
`Warn`=`warn`、`Danger`=`danger`、`Info`=`info`。`showLabel` 时右侧 `NN%`（11px、`textMuted`、
最小宽 30、右对齐），行高取 label 行盒高度，轨道垂直居中。数值按 `Progress.tsx` 规则
`clamp(0,100)` 后四舍五入。

```cangjie
Ui.progress(theme, 62.0, tone: ProgressTone.Ok, showLabel: true)
Ui.progress(theme, 40.0, size: ControlSize.Sm)
```

### 3.5 Segmented（`SegmentedView`，`ui.css:405-448`）

托盘：`padding: 2px; gap: 2px; border: 1px solid border; border-radius: 8px; background: surface2`。
分段：`border-radius: 6px(=radius-md-2); font-size: 12px; font-weight: 550; color: textMuted`；
`Sm` 高 24 / 内边距 8，`Md` 高 28 / 内边距 10；图标与文字间距 5px。
选中项：`background: surface; color: text; box-shadow: shadow-1`；未选中 hover：`color: text`。

```cangjie
let mode = rememberState<Int64>("demo-mode") {1}
Ui.segmented(theme, ["全部", "进行中", "已完成"], mode)
Ui.segmentedWithGlyphs(theme,
    [SegmentedItem("列表", glyph: IconGlyph.Timeline),
     SegmentedItem("日历", glyph: IconGlyph.CalendarGrid)], mode, size: ControlSize.Sm)
```

**与 CUI `SegmentedControl` 的差异**：CUI 的选中段用 `accent` 填充 + `accentText` 文字、没有
内凹托盘、不能带图标，因此无法表达 Design 的「surface 药丸浮在凹槽上」；本移植按 CSS 自绘，
并与 Web 一致支持 `Left/Right` 切换。

### 3.6 Field / TextInput / TextArea（`ui.css:161-240`）

`Ui.field` 是 6px 纵向栈：`label`（12px/600/`textMuted`，`required` 追加 `*` 用 `accentInk`）→
控件 → `error`（11.5px/`danger`）或 `hint`（11.5px/`textFaint`）。

输入框：`min-height: 34px; padding: 7px 10px; border-radius: 8px; border: 1px solid border;
background: surface; font-size: 13.5px; placeholder: textFaint`；聚焦时边框换 `accent`；
禁用态 `background: surface2; color: textMuted`；错误态边框 `danger`（`ui.css:238-240`，
由 `Ui.textInput(..., invalid: true)` 提供）。
`TextArea`：同表面 + `min-height: 76px`（`ui.css:212-216`）。

底层用 CUI `TextField` / `TextArea` 的 `TextInputStyle` 覆盖 padding/颜色/surface，
所以编辑、选区、IME、撤销等行为直接复用 CUI。

```cangjie
Ui.field(theme, label: "标题", required: true, hint: "必填，最多 80 字。") {
    Ui.textInput(theme, titleText, key: "form-title", placeholder: "事项标题")
}
Ui.field(theme, label: "备注", error: "不能为空。") {
    Ui.textInput(theme, noteText, key: "form-note", invalid: true)
}
Ui.field(theme, label: "描述") { Ui.textArea(theme, noteText, key: "form-desc") }
```

`key` 必须稳定且唯一：它同时是 CUI 焦点 id（`TextField(key:)` 原样使用），Tab 顺序与
`ctx.hasFocus` 查询都依赖它。

### 3.7 Modal（`ModalHost`，`ui.css:450-537`）

| 部件 | CSS | 实现 |
|---|---|---|
| 遮罩 | `rgba(26,22,18,0.42)`，`padding: 10vh 24px 24px`，内容顶对齐居中 | 全视口填充 `Color.rgba(26,22,18,107)` |
| 面板 | `width:520`（inline style），`max-width: calc(100vw-48px)`，`max-height: 80vh`，`border-radius:14`，`1px border`，`shadow-2` | `panelRect` = 顶部 `10vh`、水平居中；高度按内容 hug，超过 80vh 由 body 滚动 |
| 头部 | `padding: 16px 24px`，`align-items: flex-start`，底边框 1px | `HStack` + 标题 15/650、描述 12.5/`textMuted`、右下角取消…（关闭按钮 Ghost/Sm，图标 `close` 16） |
| 内容 | `padding: 24px`，`overflow-y: auto` | `ScrollView`，高度 = `min(内容高, 80vh - 头部 - 页脚 - 分隔线)` |
| 页脚 | `padding: 12px 24px`，右对齐，`border-top`，`background: surface2`，`border-radius: 0 0 14px 14px` | `Divider` + `HStack{Spacer; footer}` + `Corners.bottom(14)` 背景 |

行为：`Esc` 关闭、点击遮罩关闭（面板内按下不关闭）、打开期间用 CUI `Overlay` 阻断下层输入、
面板内事件广播给内容子树。遮罩动画（`modal-fade`/`modal-rise`）未移植。

```cangjie
let open = rememberState<Bool>("dialog") {false}
Ui.modal(theme, open, {=> open.value = false}, title: "新建事项",
    description: "覆盖遮罩、面板宽高、标题/关闭/内容/页脚。",
    footer: {=>
        Ui.button(theme, "取消", {=> open.value = false}, variant: ButtonVariant.Ghost)
        Ui.button(theme, "保存", {=> open.value = false}, variant: ButtonVariant.Primary)
    },
    body: {=> Ui.field(theme, label: "标题") { Ui.textInput(theme, titleText, key: "dlg-title") } })
```

### 3.8 EmptyState（`ui.css:361-402`）

纵向居中栈，`gap: 8px`，内边距 32（`compact` 时 16），`align-items: center`，文字居中：
- 图标盒 44×44、`border-radius: 14`、`background: surface2`、1px `border`、`textFaint` 图标、
  下外边距 4px；
- 标题 14px/600/`text`；
- 描述 12.5px、`textMuted`、最大宽 42ch（实现为 `maxWidth(420)`）、1.6 行高；
- 动作区 `margin-top: 8px`。

```cangjie
Ui.emptyState(theme, "收件箱是空的", description: "所有事项都已澄清。", glyph: IconGlyph.Inbox,
    action: {=> Ui.button(theme, "新建", {=> add()}, variant: ButtonVariant.Primary)})
Ui.emptyState(theme, "没有匹配结果", glyph: IconGlyph.Search, compact: true)
```

### 3.9 焦点环、分隔线、Tooltip

- `focusRing(ctx, tokens, rect, radius)`：`--focus-ring` = 2px `surface` 间隔 + 2px `accent` 带
  （`tokens.css:60`、`base.css:92-95`），实现为圆心在 rect 外 3px、宽 2px 的圆角描边；
  只在 `ctx.showFocusRing(id)` 为真（键盘聚焦）时绘制。
- `softFocusRing`（保留给自绘输入框）：`.input:focus` 的 `0 0 0 3px accent-soft`。
- `Ui.divider` → CUI `Divider`，默认色 `border`（等价 `1px solid var(--border)`），
  `axis: Axis.Vertical` 给竖线。
- `Ui.tooltip(theme, text) { ... }` → CUI `Tooltip`（悬停 500ms 后由宿主绘制气泡）。

## 4. 图标（`icons.cj` + `icon_path.cj`）

- 枚举 `IconGlyph`，30 个值，顺序与 `icons.tsx` 的 `IconName` 联合一致；
  `iconGlyphId(glyph)` 返回原 kebab 名，`iconGlyphFromId(id)` 反向查找，
  `ALL_ICON_GLYPHS` 为全量数组。
- 几何直接取自 `icons.tsx` 的 `<path d>` / `<circle>` / `<rect rx>` / `<g fill>`：
  24×24 网格、`strokeWidth 1.75`、`strokeLinecap/Linejoin: round`、`currentColor` → 传入令牌色。
  `icon_path.cj` 是一个小型 SVG `d` 展平器（`M/m L/l H/h V/v A/a Z/z` + 隐式 lineto，
  椭圆弧按 SVG F.6.5 端点参数转中心参数后折线采样）。
- 颜色默认 `theme.text`（`currentColor`），尺寸默认 18（`icons.tsx` 的 `size = 18`），
  笔画宽随尺寸缩放（`1.75 × size/24`，与浏览器 viewBox 缩放一致；小于 1 时钳到 1）。

| `IconGlyph` | id | 绘制方式 |
|---|---|---|
| `Folder` | folder | path（含 A 弧） |
| `Home` | home | 3 path |
| `Target` | target | 2 圆（描边）+ 1 实心点 |
| `Inbox` | inbox | 2 path（含 A 弧） |
| `Timeline` | timeline | 4 path |
| `Workflow` | workflow | 3 rect(1.5) + 1 path |
| `Search` | search | 1 圆 + 1 path |
| `Plus` | plus | 1 path |
| `ChevronLeft` / `ChevronRight` / `ChevronDown` | chevron-* | 1 path |
| `Close` | close | 1 path |
| `Settings` | settings | 1 path + 2 圆 |
| `Sun` | sun | 1 圆 + 1 path |
| `Moon` | moon | 1 path（2 段椭圆弧） |
| `Check` | check | 1 path |
| `Cross` | x | 1 path |
| `Play` | play | 1 path（闭合三角） |
| `Grip` | grip | 6 实心点 |
| `ZoomIn` / `ZoomOut` | zoom-in / zoom-out | 1 圆 + 1 path |
| `Link` | link | 2 path（各 2 段圆弧） |
| `Calendar` | calendar | 1 rect(2) + 1 path |
| `CalendarGrid` | calendar-grid | 1 rect(2) + 1 path + 6 实心点 |
| `Tag` | tag | 1 path（含 A 弧）+ 1 圆 |
| `Flag` | flag | 1 path |
| `Clock` | clock | 1 圆 + 1 path |
| `Trash` | trash | 2 path |
| `Edit` | edit | 2 path |
| `More` | more | 3 实心点 |

**CUI 内建映射**：CUI/sdl 的 `IconName` 只有 15 个（NewDocument/OpenFolder/Save/SaveAs/Copy/
Paste/Refresh/Trash/Brush/Calendar/Clock/Process/Calculator/ChevronLeft/ChevronRight），其中
`Trash`、`Calendar`、`Clock`、`ChevronLeft`、`ChevronRight` 看似同名，但网格、笔画宽度和
细节与 Design 的 SVG 不同（例如 sdl 的 calendar 无圆角矩形 + 无 3 短竖线）。为了像素一致，
**全部 30 个图标都按原 SVG 自绘，没有使用 CUI 内建图标**；`drawIcon` 的 `strokeFor()` 在
24vp 以上会把笔画加到 2.2，也与本移植策略不同。

### 4.1 图标 id 对照表（TS `IconName` ↔ `IconGlyph`）

查表方式：TS 侧写 `icon: 'calendar-grid'` → 仓颉侧用 `IconGlyph.CalendarGrid`；
若手上只有字符串（例如从 JSON/配置来），用 `iconGlyphFromId("calendar-grid")`，返回
`Option<IconGlyph>`，**不要假设字符串一定有效**。反查用 `iconGlyphId(glyph)`。

| # | `IconName`（icons.tsx） | `IconGlyph`（`textura.ui`） | 字符串 id |
|---:|---|---|---|
| 1 | `folder` | `IconGlyph.Folder` | `folder` |
| 2 | `home` | `IconGlyph.Home` | `home` |
| 3 | `target` | `IconGlyph.Target` | `target` |
| 4 | `inbox` | `IconGlyph.Inbox` | `inbox` |
| 5 | `timeline` | `IconGlyph.Timeline` | `timeline` |
| 6 | `workflow` | `IconGlyph.Workflow` | `workflow` |
| 7 | `search` | `IconGlyph.Search` | `search` |
| 8 | `plus` | `IconGlyph.Plus` | `plus` |
| 9 | `chevron-left` | `IconGlyph.ChevronLeft` | `chevron-left` |
| 10 | `chevron-right` | `IconGlyph.ChevronRight` | `chevron-right` |
| 11 | `chevron-down` | `IconGlyph.ChevronDown` | `chevron-down` |
| 12 | `close` | `IconGlyph.Close` | `close` |
| 13 | `settings` | `IconGlyph.Settings` | `settings` |
| 14 | `sun` | `IconGlyph.Sun` | `sun` |
| 15 | `moon` | `IconGlyph.Moon` | `moon` |
| 16 | `check` | `IconGlyph.Check` | `check` |
| 17 | `x` | `IconGlyph.Cross` | `x` |
| 18 | `play` | `IconGlyph.Play` | `play` |
| 19 | `grip` | `IconGlyph.Grip` | `grip` |
| 20 | `zoom-in` | `IconGlyph.ZoomIn` | `zoom-in` |
| 21 | `zoom-out` | `IconGlyph.ZoomOut` | `zoom-out` |
| 22 | `link` | `IconGlyph.Link` | `link` |
| 23 | `calendar` | `IconGlyph.Calendar` | `calendar` |
| 24 | `calendar-grid` | `IconGlyph.CalendarGrid` | `calendar-grid` |
| 25 | `tag` | `IconGlyph.Tag` | `tag` |
| 26 | `flag` | `IconGlyph.Flag` | `flag` |
| 27 | `clock` | `IconGlyph.Clock` | `clock` |
| 28 | `trash` | `IconGlyph.Trash` | `trash` |
| 29 | `edit` | `IconGlyph.Edit` | `edit` |
| 30 | `more` | `IconGlyph.More` | `more` |

`x` 在仓颉里叫 `Cross`（`x` 是单字母、易与坐标/temp 名冲突）；`iconGlyphId` 仍返回 `"x"`，
字符串层与 TS 完全一致。

**侧栏路由图标**（来源 `src/app/routes.ts`，已提供强类型常量，避免字符串拼错后拿到空图标）：

| 路由 | `routes.ts` 的 `icon` | 仓颉常量 | 值 |
|---|---|---|---|
| `dashboard` | `home` | `ROUTE_GLYPH_DASHBOARD` | `IconGlyph.Home` |
| `calendar` | `calendar-grid` | `ROUTE_GLYPH_CALENDAR` | `IconGlyph.CalendarGrid` |
| `okr` | `target` | `ROUTE_GLYPH_OKR` | `IconGlyph.Target` |
| `gtd` | `inbox` | `ROUTE_GLYPH_GTD` | `IconGlyph.Inbox` |
| `gantt` | `timeline` | `ROUTE_GLYPH_GANTT` | `IconGlyph.Timeline` |
| `sop` | `workflow` | `ROUTE_GLYPH_SOP` | `IconGlyph.Workflow` |
| `settings` | `settings` | `ROUTE_GLYPH_SETTINGS` | `IconGlyph.Settings` |

> 修正记录：bootstrap 里的 `ICON_DASHBOARD` 曾写作 `"layout-dashboard"`，该 id 在
> `icons.tsx` 中并不存在（`iconGlyphFromId` 返回 `None`），而 `routes.ts` 用的是 `home`。
> 现已改为 `"home"`，并补上 `ROUTE_GLYPH_*` 强类型常量；其余 `ICON_*` 字符串也逐一核对为
> 真实 id（`calendar-grid` / `target` / `inbox` / `timeline` / `workflow` / `settings`）。

**全量自检结果**（脚本比对 `src/ui/icons.tsx` 与 `cangjie/src/ui/icons.cj`）：

- `IconName` 联合类型 30 项；`PATHS` 的键集合同为 30 项，且与联合类型**完全一致**（同序）。
- `iconGlyphId()` 的 30 个返回值与联合类型**逐项相等、同序**：无遗漏、无多余、无重复。
- `IconGlyph` 枚举 30 项 = `ALL_ICON_GLYPHS` 30 项（同序）；每个枚举值都有 `glyphSpec()` 分支，
  无「有枚举无几何」或「有几何无枚举」的情况。
- `ICON_*` 字符串常量 7 个，全部可在 `iconGlyphFromId` 命中。

```cangjie
Ui.icon(theme, IconGlyph.CalendarGrid)                     // 18vp，theme.text
Ui.icon(theme, IconGlyph.Target, side: 20.0, color: tk.color.textMuted)
let glyph = IconView(IconGlyph.Inbox, side: 16.0)           // 直接实例（不再包一层 Ui）
if (current == IconGlyph.CalendarGrid) { /* IconGlyph 实现了 == / != */ }
```

## 5. 陈列页 `kit_demo.cj`

`public func demo(): Unit` 在一屏里给出左右两栏：左栏用 `ThemeTokens.light()`，右栏用
`ThemeTokens.dark()`，覆盖字体层级、Button 全变体/尺寸/禁用/block/图标位、IconButton、
Badge 六色 + 圆点、Progress 五色 + label + sm、Segmented 三形态、Field/Input/TextArea/错误态/
只读、EmptyState（含动作与 compact）、30 个图标网格，并用一个 `Ui.modal` 验证弹窗。
页面不接入 `ROUTES`，由 shell worker 决定入口。

`demo()` 需要由一个根视图调用。仓库内 `main.cj` 目前仍渲染 gate 页，shell 接入前可照下面的
最小独立工程验证（不修改共享树、也不需要临时改 `main.cj`）：

```bash
# 1) 只装 textura.ui 的探针工程（CUI 走仓库内 vendored 副本）
ROOT=~/.cache/textura-kit
mkdir -p $ROOT/src/ui
rsync -a cangjie/third_party/ $ROOT/third_party/
cp cangjie/src/ui/*.cj $ROOT/src/ui/
printf '%s\n' '[package]' 'cjc-version = "1.2.0"' 'name = "textura"' \
  'version = "0.1.0"' 'output-type = "executable"' 'compile-option = "-O2"' '' \
  '[dependencies]' 'cui = { path = "third_party/CUI" }' > $ROOT/cjpm.toml
cat > $ROOT/src/main.cj <<'CJ'
package textura

import cui.*
import textura.ui.*

main(): Int64 {
    configureFonts("Noto Sans CJK SC")
    let app = DesktopApp(WindowSpec("Textura 控件陈列", 1440, 900), theme: texturaLight())
    app.run { demo() }
    0
}
CJ

# 2) 构建 + 截图
cd $ROOT
source <repo>/cangjie/scripts/env.sh
export LD_LIBRARY_PATH="$PWD/third_party/cangjie-sdl/.sdl3:${LD_LIBRARY_PATH:-}"
cjpm build -j 4 -o textura
unset WAYLAND_DISPLAY
xvfb-run -a -s "-screen 0 1440x900x24" ./target/release/bin/textura --snapshot $ROOT/kit.bmp
python3 -c "from PIL import Image; Image.open('$ROOT/kit.bmp').convert('RGB').save('$ROOT/kit.png')"
```

实测（2026-10-22，1440×900，DPR=1，Noto Sans CJK SC）：

- 上述独立工程 `cjpm build` 通过：全项目只含 `textura.ui` + CUI，**`textura.ui` 零 error、
  零 warning**（因此本包源码本身是可从零编译的）。
- 三次独立运行 `sha256` 相同：`e7ddd1220a80…0256f956`（`det-1.bmp` = `det-2.bmp` = `kit.bmp`）。
- 中文无缺字方框；弹窗、禁用态、错误态、图标网格均按 CSS 尺寸渲染。
- 图标 id 运行时自检（探针首页写文件输出）：7 个 `ICON_*` 全部命中、7 个 `ROUTE_GLYPH_*` 值正确、
  `ALL_ICON_GLYPHS` 共 30 项且 id↔glyph 往返 0 处不一致、`ICON_DASHBOARD` == `IconGlyph.Home`、
  `"layout-dashboard"` 被正确拒绝。

> 限制：**整仓** `cjpm build`（含 `CLEAN=1`）当前会被 `src/views/calendar/logic`（其他 worker
> 的在建文件，缺 `std.collection` 导入与 `Int64.parse`）挡住，与本包无关；`textura.ui` 的
> 编译证据以上面的独立工程为准。

## 6. 已知差异（与 Web 版逐项对照）

1. **命名**：控件入口是 `Ui.button(...)` 等，图标枚举是 `IconGlyph`，`Icon` → `Ui.icon`/`IconView`。
   原因见第 0 节（通配导入歧义，实测报错）。
2. **字重**：CSS 550/600/620/650 是可变字重；`Textura UI` 只注册 Regular/Medium(500)/
   DemiLight(350)/Bold，550 取 Medium，600 以上取 Bold。视觉上 600/620/650 之间的差异被合并。
3. **`letter-spacing: -0.01em`**（`base.css:43`，h1）：CUI 无字距 API，未实现。
4. **`line-height`（1.5 / 1.6 / 1.55）**：CUI 文本按字体自然行高排版，没有行距倍数；
   单行控件（按钮、徽章、进度标签）用字形度量居中，多行文本用 Label 自然行高。
   Badge 高度按 `11 × 1.6 + 4` 计算，与浏览器一致。
5. **`font-variant-numeric: tabular-nums`**（`.progress-label`）：无对应 API，数字用比例字宽。
6. **过渡动画**（`transition: .12s/.2s`、`modal-fade`/`modal-rise`）：未移植，状态切换为瞬变。
   因此 hover/active 截图与 Web 的中间帧不可比。
7. **输入聚焦**：`.input:focus` 的 `border-color: accent` 已实现；3px `--accent-soft` 光晕
   未绘制（CUI `TextInputStyle.focusedSurface` 只有填色/边框/阴影，没有外扩光环）。
8. **弹窗焦点陷阱**：CUI 的 `enterModalFocus` 是 `protected`，自定义浮层无法复用，
   因此 `Tab` 仍可能离开弹窗（Esc/遮罩/输入阻断已实现）。
9. **滚动条、`::selection`**：`base.css:97-122` 属于宿主 chrome，未移植。
10. **`--font-mono` 栈**（`ui-monospace, SFMono…`）：CUI 不能表达字体回退栈，
    改注册 `Textura Mono` = Noto Sans Mono + CJK 回退面。
11. **图标笔画宽**：任务描述里写的是 1.5，但 `icons.tsx` 实际是 `strokeWidth={1.75}`，
    移植以源码为准（并随尺寸缩放）。
12. **`.select`**（`ui.css:218-226`，`appearance: none` + CSS 三角）：Web 版 `Select` 未在
    本轮移植范围内（视图未使用），如需使用先用 CUI `Dropdown` + `BorderRadius` 近似。

## 7. CUI 能力缺口（哪些必须自绘）

| 缺口 | 影响 | 本移植的处理 |
|---|---|---|
| `Button` 固定 38vp 高、最小宽 72、按 `ButtonRole` 取主题色 | 无法表达 28/34 高、10/14 内边距、550 字重 | `ButtonView` 自绘 |
| `IconButton` 34vp 方形、`Badge` 22vp 药丸（36 alpha 底色）、`ProgressBar` 无标签列、`SegmentedControl` 强调色选中 | 与 CSS 尺寸/配色不符 | 各自自绘（`IconButtonView`/`BadgeView`/`ProgressView`/`SegmentedView`） |
| 无 `EmptyState` | — | 用 `VStack`/`Label`/`IconView` 组合 |
| 无 box-shadow 绘制 API（只有 `SurfaceStyle.shadow` 双色 + `.shadow()` 修饰器） | `--shadow-1/2` 无法 1:1 | `softShadow()` 用 `Renderer.fillRoundedRectSoft` 羽化近似，参数取自令牌 |
| 无 `outline` / `outline-offset` | 焦点环 | `focusRing()` 手绘圆角描边 |
| 无 `color-mix()` | Badge/IconButton 的淡色 | `tint(color, p)` = 同色 p% alpha |
| 无 SVG path 渲染 | 图标 | 自写 `d` 展平器 + 线/圆/圆角矩形笔触 |
| 容器默认 `flexible = true` | 栈吸收剩余高度（页脚/头部被撑高） | 每处显式 `.hug()`；弹窗头部/页脚再加 `crossAxisAlignment` |
| `spacing:` 只接受 `Length` | 令牌是 Float32 | `vp(value)` / `fp(value)` 辅助函数 |
| `Color` 无 `==` | 主题反查 | `sameColor()` 逐通道比较 |
| `Modal` 尺寸/配色不可覆盖、`enterModalFocus` protected | 弹窗几何与焦点陷阱 | 自注册 `Overlay`（公开 API）+ 自绘面板；焦点陷阱缺（见第 6 节） |
| 结构体需显式 `init` 才能用命名/位置参数构造 | 令牌结构体 | 每个令牌结构体都写了 `init` |
