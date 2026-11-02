# CUI 0.9.6 实战手册（Textura 版）

> 本手册只记录**本仓已验证可用**的 CUI API 与踩坑。写新代码前先读对应 API 页：
> `third_party/CUI/docs/api/cui/...` 与 `third_party/CUI/docs/guide/...`。
> 不要凭记忆臆造 CUI API；CUI 0.9.6 的 vendored 副本没有 `examples/` 目录，
> 可运行的完整示例在 `docs/guide/tutorials/` 与 `docs/guide/how-to/`。

## 0. 心智模型

CUI 是声明式 GUI：传给 `app.run { ... }` 的闭包不是“初始化一次”，而是**每一帧重新描述界面**。控件实例每帧重建；跨帧数据必须放进 `State` / `rememberState` / 模型对象。`emit(this)` 把自定义组件加入当前声明块。布局、绘制、事件都在同一条 UI 线程上。

```cangjie
package textura

import cui.*

main(): Int64 {
    Fonts.setDefault("Noto Sans CJK SC")          // 必须在 DesktopApp 之前
    let app = DesktopApp(WindowSpec("织理 · Textura", 1440, 900), theme: texturaLight())
    app.run {
        let count = rememberState<Int64>("count") {0}
        VStack(spacing: 12.vp) {
            Label("织理 Textura")
            Button("点击计数：${count.value}", {=> count.value = count.value + 1})
        }.padding(24.vp)
    }
    0
}
```

## 1. DesktopApp / WindowSpec

```cangjie
let app = DesktopApp(
    WindowSpec("织理 · Textura", 1440, 900),
    theme: texturaLight(),        // Theme 是不可变值，构造时传入
    frameDelay!: UInt32(16),      // 无 vsync 时的最小帧间隔
    fontScale!: 1.0
)
app.setMinimumSize(960, 640)
app.run { /* 根界面 */ }
```

- `DesktopApp` 必须在程序原生主线程创建并运行；错误线程会拒绝。
- 窗口创建后先隐藏，字体初始化 + 首帧构建/布局/绘制完成后才 `show()`。
- `run()` 阻塞到窗口关闭；一个实例只能调用一次。
- `app.post { ... }` 从任意线程投递短动作到 UI 线程；`app.batch { ... }` 合并多次状态写。
- `app.requestClose()` 走可取消的关闭流程；`UiContext.requestClose()` 是直接退出。
- 快照模式：CUI 自己解析 `--snapshot <path>`，在第 48 帧后写 BMP 并退出。详见 `docs/PARITY.md`。
- 鸿蒙宿主：用 `app.beginHostedRun(body)` + 每帧 `app.step()` + `app.endHostedRun()`，不要用阻塞 `run()`（CUI-P01 补丁）。

## 2. State / DerivedState / 绑定

```cangjie
// 局部、跨构建保留；key 必须稳定且同级唯一
let count = rememberState<Int64>("gate-clicks") {0}
count.value = count.value + 1

// 显式模型状态（可被多个区域共享）
let name = State<String>("林一")
let canSubmit = derive(name, subscribed) { text, ok => !text.trimAscii().isEmpty() && ok }
println(canSubmit.get())

// 投影到模型字段（Binding），控件直接写回同一事实来源
let nameBinding = profile.project(
    get: {value => value.name},
    set: {value, next => Profile(next, value.subscribed)}
)
TextField(nameBinding)
```

规则：

- `State<T>` 是事实；`DerivedState<T>` 只计算、不保存第二份事实。
- `State.value` 赋值推进修订号并通知依赖；同一事件内的多次写入合并为一次通知。
- `rememberState` 适合局部展开/输入/临时选择；动态列表必须用稳定业务 key + `Keyed`/`ForEach`，不要用下标。
- 后台线程不能直接写 `State`；用 `app.post` 回 UI 线程。
- `remember<T> { ... }` 用于保留控制器/动画器等稳定对象。

## 3. 布局容器

### VStack / HStack

```cangjie
VStack(spacing: 12.vp) {
    Label("标题")
    HStack(spacing: 8.vp) {
        Button("取消", {=> ()})
        Button("保存", {=> ()}, role: ButtonRole.Primary)
    }.hug()
}.padding(24.vp)
```

- 默认主轴对齐 `Start`、交叉轴 `Stretch`，所以子控件会横向拉满。
- **VStack/HStack 自身默认 `flexible = true`**：放进 `Panel` 等有剩余高度的容器时，它会吸收全部剩余空间，导致兄弟被挤扁、出现大间隙。需要“正好包住内容”时链 `.hug()`（等价 `flexible(false)`）。
- `.flex()` 是按权重分配剩余空间；`.fillWidth()` 是使用父级已给的宽度。两者不同。
- `Spacer()` 吸收剩余空间；不要滥用，否则相关内容会被推散。
- `.width(240.vp)` 在可伸缩的 `HStack` 里可能被父级拉伸覆盖；对整行加 `.hug()` 或给行固定高度。

### ZStack（不是 Stack）

```cangjie
ZStack {
    VStack { /* 背景内容 */ }
    Modal(confirming, onDismiss: {=> cancel()}) { /* 对话框 */ }
    ToastLayer(toaster)
}
```

靠后声明者在上。CUI 没有名为 `Stack` 的类型；叠层用 `ZStack`。

### Grid

```cangjie
Grid(3) {
    Label("A"); Label("B"); Label("C")
    Label("D"); Label("E"); Label("F")
}
```

固定列数、等宽单元格，按声明顺序行主序填充；`columns` 必须为正。

### ScrollView / LazyColumn / LazyList

```cangjie
// 普通子树超出视口
ScrollView(key: "settings-scroll") {
    VStack(spacing: 12.vp) { /* ... */ }
}

// 固定行高、上千项
LazyColumn(1000, 48.0, spacing: 8.0, id: "inbox") { index =>
    HStack(spacing: 12.vp) {
        Label("#${index}").muted().width(70.vp)
        Label("第 ${index} 封邮件").flex()
    }.padding(8.vp)
}

// 可变行高、需要稳定业务 key
LazyList.measured(messages, estimatedHeight: 72.0, key: {message => message.id}) { message =>
    Label(message.title)
}
```

- `ScrollView` 只提供滚动/裁剪，不减少构建节点；大列表用 Lazy 系列。
- Lazy 行的选择/草稿等状态必须按业务 id 提到外层；行滚出视口会卸载。
- 自测量行不要 `.fillHeight()` 或裸 `Spacer`（无有限 intrinsic height）。

## 4. Panel、文本、字体

```cangjie
Panel {
    VStack(spacing: 8.vp) {
        Label("本周焦点").fontSize(22.fp).bold()
        Label("次要说明").muted()
        Label("等宽数字").fontFamily("Noto Sans Mono CJK SC")
    }.hug().fillWidth()
}.hug().fillWidth()
```

- `Panel` 默认 12vp 内容内边距、主题面板表面/描边/圆角；`flexible = true`，通常要 `.hug()`。
- `Label(text, muted!: Bool, align!: TextAlign, color!: ?Color, fontSize!: ?Length)`。
- 链式：`.bold()`、`.italic()`、`.fontWeight(FontWeight(600))`、`.fontSize(18.fp)`、`.fontFamily("...")`、`.textStyle(TextStyle(...))`。
- 字体继承：控件显式族名 > 子树 `TextStyle` > `Fonts.setDefault` > 平台 UI 字体。
- CJK 必须显式设默认字体，否则默认 UI 字体可能没有中文字形，显示方框：

```cangjie
Fonts.setDefault("Noto Sans CJK SC")
```

Linux 下 `Fonts.setDefault("Noto Sans CJK SC")` 通过 fontconfig 定向解析；也可以用 TTC 明确指定 SC face：

```cangjie
Fonts.registerFamily("Textura UI", FontFamily(
    FontSource("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", faceIndex: 2)
))
Fonts.setDefault("Textura UI")
```

`NotoSansCJK-Regular.ttc` 的 face 顺序：0 JP、1 KR、2 SC、3 TC、4 HK；SC 是 **2**。

- 字体角色：`FontRole.systemUI` / `sansSerif` / `serif` / `monospace` / `emoji`。
- 缺字 fallback：`Fonts.setFallbacks([...])`；未知族名会宽容回退，但不要依赖它做 CJK 兜底。

## 5. 常用控件（CUI 真名）

| 需求 | CUI 类型 | 备注 |
|---|---|---|
| 按钮 | `Button(title, onClick, role: ButtonRole.Primary/Normal/Danger)` | Enter/Space 也触发 |
| 图标按钮 | `IconButton(icon: IconName, label!: ?String, onClick!)` | 图标集见 `IconName` |
| 徽章 | `Badge(text, kind: BadgeKind.Success/Neutral/...)` | 固定高 22 |
| 进度 | `ProgressBar(value: Observable<Float32>, lower, upper)` / `ProgressRing` | 传 `State<Float32>` 即可 |
| 分段 | `SegmentedControl(items: Array<String>, selected: Bindable<Int64>, key!)` | 不是 `Segmented` |
| 输入 | `TextField(text: Bindable<String>, key!: ?String)` | 还有 `TextArea`/`ComboBox` |
| 空状态 | 无内建 `EmptyState` | 用 `Panel` + `Label` 在 `textura.ui` 封装 |

```cangjie
Badge("构建通过", kind: BadgeKind.Success)
ProgressBar(progress)                       // progress: State<Float32>
SegmentedControl(["全部", "进行中", "完成"], segment)
```

## 6. Canvas 自绘

```cangjie
CanvasWidget(
    { renderer, frame =>
        renderer.strokeLine(
            frame.x + 10.0, frame.y + 10.0,
            frame.right() - 10.0, frame.bottom() - 10.0,
            Pen(width: 2.0, color: Color.rgb(33, 114, 229))
        )
        renderer.fillCircle(markerX.value, markerY.value, 7.0, Color.rgb(246, 112, 52))
    },
    onEvent: { event, frame =>
        match (event) {
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    markerX.value = x
                    markerY.value = y
                    return true
                }
            case _ => ()
        }
        false
    }
).flex()
```

- `CanvasWidget(onDraw: (Renderer, Rect) -> Unit, onEvent!: (UiEvent, Rect) -> Bool)`，从 `cui.*` 可直接用。
- `frame` 是绝对坐标矩形；绘制与 `frame.contains(x,y)` 命中使用同一个矩形。
- 跨帧数据放 `State`；不要在 `onDraw` 里改状态（会形成重建循环）。
- 只消费真正属于自己的事件；拖出边界后的 MouseUp 要结束手势，普通外部事件返回 `false`。
- 自定义 `Widget` 需要 `emit(this)`、`measure`、`layout`、`draw`、`handle`，并按需实现 `focusableId` / `pointerEventScope` / `paintOutset`。

## 7. 事件、焦点、快捷键

```cangjie
EventHandler(onEvent: {event =>
    match (event) {
        case UiEvent.KeyDown(Key.Delete, _) => model.requestDelete()
        case _ => false
    }
}) {
    VStack { /* 内容 */ }
}
```

- `EventHandler` 先于子树收到事件，返回 `true` 表示消费；新代码优先用 `EventListener` + `EventPhase.Capture/Target/Bubble` + `EventOutcome`。
- `UiEvent.KeyDown(key, isRepeat)` 的第二个值不是 Ctrl/Shift；组合键从 `ctx.eventModifiers()` 读事件时刻快照。
- 焦点：`ctx.focus(id)`、`ctx.hasFocus(id)`、`ctx.showFocusRing(id)`、`ctx.focusNext()`；Tab 按声明顺序走。
- 指针点击取得焦点通常不显示焦点环；键盘取得才显示。
- 自定义控件布局时调用 `ctx.registerSemantics(...)` 提供无障碍语义，语义动作复用同一业务函数。
- 业务选择存业务 id，不要用“当前焦点行号”代替。

## 8. Modal / Toast / 浮层

```cangjie
let toaster = Toaster()
let confirming = State<Bool>(false)

app.run {
    ZStack {
        VStack { Button("删除", {=> confirming.value = true}, role: ButtonRole.Danger) }
        Modal(confirming, onDismiss: {=> confirming.value = false}) {
            VStack(spacing: 12.vp) {
                Label("确定删除？").bold()
                HStack(spacing: 8.vp) {
                    Button("取消", {=> confirming.value = false})
                    Button("确认", {=> doDelete(); toaster.show("已删除", kind: ToastKind.Success)})
                }.hug()
            }.padding(8.vp)
        }
        ToastLayer(toaster)
    }
}
```

- `Modal(presented: Bindable<Bool>, onDismiss!, initialFocus!, dismissOnEscape!, dismissOnBackdrop!, body!)`：阻止背景交互，Tab 限制在对话框内。
- `Toaster()` 只创建一次；`Toaster.show(message, kind: ToastKind, durationMs)`；必须同时声明 `ToastLayer(toaster)`，否则没有可见承载。
- 自定义浮层优先 `Portal(owner, open, placement, blocksInput, body)`；底层用 `Overlay(handleEvent, render, owner)`。
- 不要为 Modal 承诺“自动聚焦到某个按钮”，当前普通按钮没有 autofocus API；需要时用 `initialFocus` 指定内部 key。

## 9. 主题令牌

```cangjie
func texturaLight(): Theme {
    Theme(
        bg: Color.rgb(246, 242, 236),
        panel: Color.rgb(255, 252, 247),
        panelEdge: Color.rgb(227, 218, 206),
        text: Color.rgb(36, 32, 28),
        mutedText: Color.rgb(106, 96, 87),
        accent: Color.rgb(192, 102, 58),
        accentText: Color.rgb(255, 250, 245),
        danger: Color.rgb(168, 69, 58),
        field: Color.rgb(244, 238, 230),
        fieldActive: Color.rgb(255, 252, 247)
    )
}
```

- `Theme` 是不可变 struct；**没有运行时 `setTheme` / `with`**。换主题 = 构造新值并在 `DesktopApp` 创建时传入，或重启应用。
- 语义角色：`bg`、`panel`、`panelEdge`、`text`、`mutedText`、`accent`、`accentText`、`danger`、`field`、`fieldActive`、`panelRaised`、`accentSoft`、`shadow`、`radius`、`smallRadius`、`controlRadius`、`borderWidth`。
- 业务视图只读令牌，不硬编码颜色；`textura.ui` 的 `texturaLight()` / `texturaDark()` 是唯一入口。
- 控件表面：`theme.panelSurface()`、`raisedSurface()`、`fieldSurface(active)`、`buttonSurface(role)`、`selectedSurface()`。

## 10. 尺寸单位与修饰器顺序

| 单位 | 含义 | 用途 |
|---|---|---|
| `vp` | 虚拟像素，随显示缩放 | 尺寸、间距、圆角 |
| `fp` | 在显示缩放外再考虑字体缩放 | 文字与跟随字号的尺寸 |
| `px` | 物理像素 | 设备像素级细线/图像 |

修饰器**从内向外**包：`Label(...).padding(12.vp).background(color)` 的背景包含 padding；反过来背景只包文字。`fillWidth`/`fillHeight` 与 `flex` 不同；`visible(false)` 移出布局/绘制/事件；`enabled(false)` 保留位置但阻止交互。

## 11. 快照与性能

- CUI 内建：`--snapshot <path>`（第 48 帧后 `Renderer.captureBmp` 并退出）、`--profile`（每 60 帧输出阶段耗时）。
- `Renderer.captureBmp` 只写 BMP；`Renderer.readRectRgbaToFile` 是 PixCap 补丁，可读 RGBA，但绘制录制期间会拒绝。
- 本仓 `src/snapshot.cj` 用纯仓颉把 BMP 转 PNG；PNG 用 stored deflate，字节确定、文件大。
- `FrameHandler(onFrame: {info => ...})` 每帧回调并请求续帧；不需要逐帧时不要挂。
- `--cui-force-full-retained` / `--cui-disable-retained-damage` 只用于差分排错；`app.lastFrameUsedPartialDamage()` 可查真实局部重绘。

## 12. 踩坑清单（本仓实测）

1. **继承的 `WAYLAND_DISPLAY` 会让 SDL3 选 Wayland**，在 Xvfb 下 `window.show()` 进入 GTK/libdecor/libglycin 并 SIGSEGV。解法：`unset WAYLAND_DISPLAY; export SDL_VIDEODRIVER=x11`。
2. **中文字形方框**：CUI 默认系统 UI 字体可能无 CJK。解法：`Fonts.setDefault("Noto Sans CJK SC")`，且必须在 `DesktopApp` 之前。
3. **VStack/HStack 默认 `flexible = true`**：放进 Panel 后吸收全部剩余高度，按钮被压成一条线、页面上出现巨大空隙。解法：给栈/面板 `.hug()`。
4. **修饰器顺序**：`.background` 在 `.padding` 前只包内容，在后才包内边距；不要凭直觉写。
5. **`cjpm build` 默认产物叫 `main`**。解法：`cjpm build -o textura`（`scripts/build.sh` 已封装）。
6. **`cjpm build` 每次重编 CUI/SDL，约 2 分钟**。解法：`cjpm build -i`；依赖变更/换 SDK 后先 `cjpm clean`。
7. **仓颉整数默认溢出抛 `OverflowException`**（FNV 乘法踩到）。解法：`std.overflow.wrappingMul`。
8. **`ArrayList` 的方法是 `add`，不是 `append`**。
9. **`Byte(...)` 不是构造器**：字面量用 `UInt8(0x42)`；`Array<Byte>` 与 `Array<UInt8>` 是同一底层类型。
10. **多行字符串必须以换行开头**：`"""` 后不能直接跟内容，否则编译错误。
11. **`if (let Some(x) <- opt)` 在 1.2.0 的某些上下文不通过**；用 `match (opt) { case Some(x) => ... case None => ... }` 最稳。
12. **闭包不能捕获可变局部变量**（编译错误 “lambda capturing mutable variables needs to be called directly”）。解法：用 `State<T>`/`rememberState` 或类的字段。
13. **`getCommandLine()` 需要 `import std.env.*`**。
14. **CUI 只写 BMP**：不要假设 `--snapshot out.png` 直接得到 PNG；本仓在 `app.run` 后转换。
15. **BMP 是 bottom-up、32bpp BI_BITFIELDS**；PNG chunk 长度/CRC/Adler 都是大端，zlib stored block 的 LEN/NLEN 是小端。写 PNG 编码器时最容易在这里出错（本仓第一版就因大端写反导致 “Truncated File Read”）。
16. **`--snapshot` 参数必须分成两个 argv**；`cjpm run --run-args="--route=x"` 会把 `=` 拆开，直接跑构建产物。
17. **CUI 没有内建 `Stack`、`EmptyState`、`Progress`、`Segmented`**：对应 `ZStack`、自封装、`ProgressBar/ProgressRing`、`SegmentedControl`。
18. **CUI 0.9.6 vendored 副本没有 `examples/`**；以 `docs/guide/tutorials`、`docs/guide/how-to` 和 `third_party/cangjie-sdl/examples` 为准。
19. **PixCap 的 `libSDL3_ttf.so` 是 aarch64-ohos**，不能当宿主库；宿主用本仓 `.sdl3/` 的 x86_64 构建。
20. **快照两次一致 ≠ 跨机器一致**：字体 hinting、FreeType、SDL 版本都会改变抗锯齿；parity 只承诺同机同栈逐像素，跨机器用 `diff.py` 容差。

## 13. 参考入口

- 第一个窗口：`third_party/CUI/docs/guide/getting-started/first-window.md`
- 状态：`docs/guide/concepts/state-and-binding.md`
- 布局/滚动：`docs/guide/concepts/layout-and-scrolling.md`
- 单位/修饰器：`docs/guide/concepts/modifiers-and-units.md`
- 自绘：`docs/guide/how-to/custom-canvas.md`
- 自定义 Widget：`docs/guide/how-to/custom-widget.md`
- 字体：`docs/guide/how-to/fonts-and-typography.md`
- 主题：`docs/guide/how-to/theme-an-app.md`
- Modal/Toast：`docs/guide/how-to/modal-and-toast.md`
- 虚拟化：`docs/guide/how-to/virtualize-large-data.md`
- 快照/性能：`docs/guide/how-to/snapshot-and-profile.md`
- API 索引：`docs/api/cui/index.md`、`docs/api/cui/core/index.md`、`docs/api/cui/controls/index.md`
