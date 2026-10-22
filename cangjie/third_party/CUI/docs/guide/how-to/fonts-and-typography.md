# 字体配置、继承与渲染

文本选择、复制粘贴、字素边界和撤销规则见 [文本编辑指南](text-editing.md)。

一般应用只需 `import cui.*`。字体选择依次采用控件/片段显式族名、子树 TextStyle、`Fonts.setDefault`、平台 UI 字体；未知名称和无法打开的文件宽容回退，实际结果可通过 `Renderer.resolveFont` 查询。

## 应用默认与子树设置

```cangjie verify
package docexample
import cui.*
main(): Unit {
    Fonts.setDefault(FontRole.systemUI)
    let text = State<String>("AV office 仓颉")
    let app = DesktopApp(WindowSpec("字体设置", 800, 600))
    app.run {
        VStack(spacing: 12.vp) {
            Label("字体与输入").bold().fontSize(26.fp)
            TextField(text).width(400.vp)
            Button("保存", {=> ()})
            RichText([RichSpan.text("AV"), RichSpan.text(" office").italic()])
        }.textStyle(TextStyle(fontSize: 18.fp)).padding(24.vp)
    }
}
```

`Fonts.systemFamilyNames()` / `Fonts.systemFonts()` 显式加载完整目录，适合在字体选择器的加载动作中调用。默认字体和 `.fontFamily("Georgia")` 只定向查找所需字体；未知名称不会扫描整个系统。`Fonts.familyFaces("Cascadia Code")` 可直接查询该字体族的样式与设计轴。安装新字体后调用 `Fonts.refreshSystemFonts()`。使用 `Fonts.setSearchDirectories(["assets/fonts"])` 增加应用目录。当前仍不提供系统逐字符 fallback 服务。

## 随附字体、真实样式与 TTC

```cangjie verify
package docexample
import cui.*
main(): Unit {
    Fonts.registerFamily("Body", FontFamily(
        FontSource("assets/Body-Regular.ttf"),
        bold: FontSource("assets/Body-Bold.ttf"),
        italic: FontSource("assets/Body-Italic.ttf"),
        boldItalic: FontSource("assets/Body-BoldItalic.ttf"),
        fallbacks: [FontSource("assets/CJK.ttc", faceIndex: 1)]))
    Fonts.setDefault("Body")
}
```

注册本身不读取文件。旧 `Fonts.register(name, path)` 和路径版 `registerFamily` 继续可用；显式真实样式优先于文件名约定，最后按 synthesize 策略合成。真实 Italic 比机械倾斜更符合字体设计，但 fallback 字体也必须考虑样式覆盖。斜体默认采用带预算的整段纹理路径，修复 SDL_ttf 3.2.2 图集绘制时的拉伸和字间重叠；调用方继续使用 `.italic()`，无需手工增加字距。

## 诊断、恢复与缓存

用 `renderer.resolveFont(font: "Body", style: FontStyle(italic: true))` 检查实际 `faces`、`synthesizedStyle` 和 `warnings`；用 `fontCacheStats()` 观察配置数、文字纹理字节及栅格化次数。静态斜体／旋转文字复用纹理：单色字形仍可跨 RGB 复用，包含彩色字形时 RGB 参与缓存键；仅改变透明度均可复用。普通字形采用请求颜色，彩色 Emoji 保留自身调色板，两者一起应用透明度。

缺文件补齐后，重新注册同名同路径或调用 `Fonts.reload()` 即可重试。reload 同时使系统名称匹配、目录和文件元数据失效，下次按需查询，不立即扫描目录；已注册系统别名按原文件位置重读元数据，若安装位置改变则重新 registerSystem。需要替换正被缓存打开的字体文件时，先关闭测量会话，调用 `renderer.reloadFonts()` 立即释放缓存，再替换文件并调用 `Fonts.reload()`。会话固定创建时的字体图与比例，不因另一字体族、重新注册或缓存淘汰而改变；测量和 close 均应在 Renderer 所属线程执行。

当前每个 Renderer 最多缓存 24 个字体配置；同实际字号的自动 Emoji 后备共享不可变原生实例，彩色配置另按 COLR／CPAL 表去重计入 64 MiB 预算。该预算不限制当前单项请求或存活测量会话，也不是进程总内存上限。整段文字纹理最多 256 项、16 MiB，超预算单项临时绘制后释放。度量缓存限制字体族/字号桶及每代字节；字形文本缓存也有估算布局预算。仓颉字形图集单独限制为 16 MiB，可通过 glyphAtlasBytes／cachedGlyphs／glyphAtlasEvictions 观察；以上不包含其它 FreeType 内部对象和驱动开销。避免逐帧 reload；少量稳定字号能减少缓存淘汰后的字体重开成本，详见[资源实测与优化](../../emoji-resource-optimization-2026-09-08.md)。

长斜体或旋转文本超过 GPU 单张纹理上限时，整段 shaping 后分块上传，分块采样边缘保留邻接像素。256 的上限按实际纹理块计数，16 MiB 包含采样边缘；整段 CPU Surface 另有 16M 像素（64 MiB RGBA）上限，单字形图集槽含边缘不超过 2048 像素；超出时明确报错。

## 自定义控件

使用 `ctx.textSize()`、`ctx.textHeight()`、`ctx.textWidth()`、`ctx.text()` 与 `ctx.textMeasureSession()`，使测量、绘制和输入几何继承相同默认值。显式 pointSize 为已解析的逻辑像素；不要再次乘 displayScale 或 fontScale。`Renderer.fontMetrics()` 提供主字体基线度量，`textBounds(text)` 提供具体文字的保守栅格框；它们都不能替代尚未公开的精确 ink bounds/advance/cluster 布局对象。

DesktopApp 在布局前通过 `Renderer.prepareTextLayout` 准备本帧的 DPI／超采样比例，布局与绘制采用相同的字形 hinting 度量，避免贴合内容宽度的 Label 无故省略。自建 SDL 宿主也应先 prepareTextLayout，再测量／布局，最后使用相同逻辑尺寸开启 RenderPass 并绘制。

仓颉文字引擎通过官方 SDL_ttf 公开布局接口让横向 fallback 字形共用基线。`Renderer.textInkBounds` 提供排除行框留白的字形位图／装饰线矩形，`textCenter` 据此进行视觉居中；Headless 使用保守行框。内容型表单行用 `.hug()` 随字号确定高度，避免和画布等填充内容均分高度后压缩文字。详见[示例反馈修复记录](../../font-alignment-fixes-2026-09-06.md)。

RichText 按基线对齐混合字号，并合并相邻同视觉样式普通文本；支持 LF、CRLF、CR、NEL、Unicode 行／段分隔符，保留连续和末尾空行，CRLF 跨片段也只换一行。换行后的链接命中与绘制位置一致。跨颜色、链接、高亮的 shaping，以及完整段落级 bidi/复杂脚本布局仍是后续工作。

## 数值字重与独立继承

`FontWeight` 接受 1～1000 的整数，提供 normal(400)、medium(500)、semiBold(600)、bold(700) 等常量。`.bold()` 是 700 的快捷方式，`.bold(value: false)` 设置 400。Label、Button、RichSpan 可以直接设置；其它控件通过 Widget 的字体修饰器或 TextStyle 继承。

```cangjie verify
package docexample
import cui.*
main(): Unit {
    let ctx = UiContext(Renderer.headless(), Theme.light())
    let content = VStack {
        Label("继承 600 和斜体")
        Label("仅改为 350，仍然斜体").fontWeight(FontWeight(350))
        Label("仅取消斜体，仍然 600").italic(value: false)
        Button("保存", {=> ()}).fontWeight(FontWeight.medium)
        RichText([RichSpan.text("600 "), RichSpan.text("700").bold()])
    }.textStyle(TextStyle(fontFamily: FontRole.systemUI, fontWeight: FontWeight.semiBold, italic: true))
    println(content.measure(ctx, Size(600.0, 500.0)).h)
}
```

字重、倾斜、装饰分别继承；显式 `.fontStyle(FontStyle.regular)` 重置整组样式。同一 TextStyle 中先应用 fontStyle，再应用独立字段。静态字体按倾斜、字宽、数值字重匹配，400～500 区间采用 CSS 字重搜索顺序；没有精确字体面时返回近似字体，并在 resolveFont 中报告实际字重。多份应用静态字重文件可通过 `FontFamily(..., faces: [FontFaceDefinition(...)])` 注册。

## 变量字体与命名实例

仓颉代码直接解析 SFNT 元数据，并通过官方 SDL_ttf 的公开 IOStream／命名实例接口设置连续坐标；`Fonts.supportsVariations()` 用于查询能力。Cascadia Code 的 200、350、600、700 使用真实轮廓，625 则通过 wght 轴插值，无需再合成加粗。

```cangjie verify
package docexample
import cui.*
main(): Unit {
    let label = Label("AV office 012345").fontFamily("Cascadia Code").fontWeight(FontWeight(625)).italic()
    for (face in Fonts.familyFaces("Cascadia Code")) {
        if (face.familyName == "Cascadia Code") {
            println("${face.styleName}: ${face.weight.value}, instance=${face.source.instanceIndex}")
            for (axis in face.axes()) { println("${axis.tag}: ${axis.minimum}..${axis.maximum}") }
        }
    }
    // 对于确实具有 wdth、opsz 轴的字体，可以进一步设置：
    let axes = FontVariations([FontVariation("wdth", 90.0), FontVariation("opsz", 18.0)])
    let custom = Label("Optical size").fontFamily("My Variable Font").fontVariations(axes)
}
```

`fontWeight` 超过变量字体 wght 范围时钳制到边界并提供诊断；显式未知轴、重复 tag、非有限值或越界坐标会报错。支持任意合法设计轴，包括 wdth、ital、slnt、opsz，但不会替字体创造不存在的轴，也不会自动按字号改变 opsz。显式 variations 中的 wght 优先；之后调用 fontWeight/bold 会清除先前的显式 wght。

使用 `FontSource(path, faceIndex: 0, instanceIndex: 6)` 可固定一个命名实例；实例编号必须来自该字体的枚举结果，不能假定其它字体的 6 也表示 Bold。`FontSource(..., variations: ...)` 可固定源坐标。固定实例/源 wght 不会被普通 fontWeight 自动重置；需要动态字重时注册基础文件即可。

## 默认字体与平台边界

可用的应用默认文件能直接引导渲染器，不再要求机器上存在固定路径的系统字体。其后按需尝试平台 UI 字体、常见字体路径及配置的随附字体；只查询已经由应用显式加载的目录，不为启动或失败恢复扫描全量字体。全部不可用时报告明确错误。`Fonts.setFallbacks([FontSource("assets/CJK.ttc")])` 同时配置全局缺字链及随附保底字体。

| 角色/平台 | 选择方式 |
| --- | --- |
| `FontRole.systemUI` | Windows 消息字体设置＋DirectWrite；Linux fontconfig；macOS CoreText UI 字体 |
| sansSerif / serif / monospace | 定向平台匹配或平台常用字体；仅复用已显式加载的目录 |
| Windows | 系统与用户安装字体，可访问的 DirectWrite 文件字体及本地化别名 |
| Linux | fontconfig 配置、XDG 和系统/用户字体目录 |
| macOS | CoreText 文件字体及系统/用户字体目录 |

本轮在 Windows 实机验证；Linux/macOS 提供了实现，仍需对应平台构建和实机验收。私有内存字体、远程字体、多文件字体以及无可访问文件的系统 UI 字体可能无法交给 SDL_ttf，届时使用后备。发布使用官方 SDL3／SDL3_ttf，无需补丁或 native/ 扩展构建。已有命名实例直接复用；任意坐标使用官方 SDL 内存流：字库主体按只读映射共享，只为重写的字体表和末尾不足 64 KiB 的数据分配私有映射页，常见每实例约 128 KiB、上限 320 KiB；不按字重复制整份字库。首次创建同一元数据版本的虚拟实例会计算源文件校验和，后续实例复用。单文件映射限 1 GiB，元数据单文件限 8 MiB；异常或超限会进入后备／诊断流程。目录按规范化真实路径去重。Fonts.setMetadataCache(path) 可启用持久元数据缓存；文件大小/修改时间变化使条目失效，损坏缓存自动重建，refreshSystemFonts(force: true) 可强制重建。缓存父目录由应用准备，默认不开启；安装变更通知尚未接入。

连续改变设计轴仍需生成新轮廓，不能依赖缓存消除所有开销。优先使用固定或少数离散字重；交互预览按合适步长／频率更新。fonts 示例使用步长 25 的字重滑杆，精确 `FontWeight(479)`、自定义轴坐标和命名实例 API 保持可用。
