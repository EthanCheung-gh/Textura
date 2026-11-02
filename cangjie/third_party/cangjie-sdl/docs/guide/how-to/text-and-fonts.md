# 排版文字与选择字体

## 目标

基于[首个窗口](../getting-started/first-window.md)，加入右对齐数字、居中按钮标签、粗体标题和可选命名字体；度量与绘制使用完全相同的字符串、字号、样式和字体。完成后，中英文、数字和长文本都能得到可解释的对齐结果。

## 适用场景

适用于计算器读数、HUD、表格数值、按钮标签、标题和状态栏。系统 UI 字体适合普通工具，自带字体适合品牌或像素风，但要确保授权和字符覆盖。需要复杂段落换行、富文本或双向排版时，当前基础接口只提供单行绘制与度量，应用需建立更高层布局。

## 准备工作

先阅读[文字度量、字体与缓存](../concepts/text-font-cache.md)。保留首个窗口完整程序，在绘制阶段定义一次 `FontStyle`，并在 `textWidth` 与 `text` 中复用。若注册自定义字体，使用发布目录中的真实文件路径，并准备字体缺失时的系统回退视觉检查。

## 操作步骤

在场景中分别创建标题样式和读数样式。标题使用 `FontSizes.TITLE`；读数用 `FontSizes.DISPLAY` 调用 `textWidth`，再用“右边界减宽度”得到起始位置，并把同一个样式传给 `text`。按钮标签直接使用 `textCenter`，不需要手算水平位置或基线。

长读数可先测 `DISPLAY` 宽度，超出可用范围后改用 `TITLE` 或自定义较小字号；不要只缩放绘制而继续使用旧度量。需要命名字体时，通过 `Fonts.registerFamily` 注册主字体和按顺序尝试的回退字体，再在度量和绘制中都传 `font: Some("brand")`。注册应在首次渲染前完成，不要放进帧循环。

需要为长行找换行位置或把点击映射到光标时，用 `textMeasureSession` 固定字符串、字体、字号和样式，并在同一个资源块中调用 `fit` 与 `hitTest`。结果使用 UTF-8 字节偏移和字形簇安全边界，比逐个测量字符串前缀更快，也不会从中间拆开连字或从右向左文字。

## 确认结果

窗口应显示粗体标题、右对齐读数和居中按钮。把值换成 `"中文 12,480 ms"`，确认没有方框或切边；把窗口变窄，确认降级字号后仍在右边界内。调用同一测量两次并观察计数器时，measure 次数增加而 compute 不应重复增加，说明缓存命中。自定义字体路径故意写错一次，确认程序使用系统 UI 字体仍可读，并在日志中清楚记录回退。

## 常见错误

在 RenderPass 外提前测量或布局时，先调用 `renderer.prepareTextLayout(logicalWidth, logicalHeight)`，然后使用相同尺寸开启 RenderPass。该方法在布局前准备本帧实际 DPI／超采样比例与目标分配后备，使字体 hinting 度量和绘制一致；`endScene` 后或尺寸变化时重新准备。已经在 RenderPass 内测量和绘制的代码保持原写法。

测量 regular、绘制 bold 会导致右对齐漂移；`textWidth` 使用默认字体、`text` 使用命名字体也会错。把 `textHeight` 当多行布局高度会让行间距不足。每帧注册字体或清空纹理缓存会造成不必要工作；注册表变化会推进 `Fonts.revision()` 并使相关缓存自动失效。`fit` 只保证 UTF-8 码点安全和宽度适配，不负责语言断行规则；段落层仍要处理 UAX #14、组合字符、ZWJ 与标点禁则。headless 度量适合测试控制流，不应拿来承诺最终像素宽度；视觉验收必须在真实窗口中完成。

## 可以继续修改

创建同时启用粗体、斜体和删除线的 `FontStyle`，再通过 `textRotated` 绘制“已过期”状态标签。相同文字、字号、样式、字体、缩放和 RGB 复用旋转纹理；仅改变透明度无需重新生成。彩色 Emoji 保留自身颜色，同时应用请求透明度。

## 相关 API

- [`Renderer`](../../api/sdl/Renderer.md)：文字度量、绘制、旋转、居中和缓存统计。
- [`FontStyle`](../../api/sdl/FontStyle.md)：文字样式组合。
- [`FontSizes`](../../api/sdl/FontSizes.md)：常用字号层级。
- [`Fonts`](../../api/sdl/Fonts.md)：命名字体注册。
- [`TextMeasureSession`](../../api/sdl/TextMeasureSession.md)：长串适配、范围测量与字形簇命中。

## 下一步

继续[Surface、Texture 与图片](../concepts/surface-texture-image.md)，把文字之外的位图资源纳入同一场景和生命周期。

## 字体族、系统发现与恢复

可直接使用系统目录元数据中的族名，也可通过 `Fonts.registerSystem` 建立应用别名。`Fonts.setDefault` 设置应用默认；`Renderer.withFontFamily` 设置同步作用域。随附字体用 `FontFamily(FontSource(...), bold: ..., italic: ..., boldItalic: ..., fallbacks: ...)` 显式注册真实样式与集合面号。

用 `Renderer.resolveFont` 查看实际字体与失败诊断，`fontMetrics` 查看基线度量，`textBounds` 查询具体字符串的保守栅格框。补齐缺失文件后重新注册或 `Fonts.reload()` 可以恢复；同路径替换前可关闭测量会话并用 `renderer.reloadFonts()` 立即释放缓存。

斜体采用整段 Surface 纹理路径；仅含彩色字形时 RGB 参与纹理缓存键，单色纹理跨 RGB 复用。透明度按次应用，缓存限制为 256 块/16 MiB。零绘制面积的文本安全跳过。不要通过增大字距补偿错误字形。API 细节见 [FontFamily](../../api/sdl/FontFamily.md)、[FontResolution](../../api/sdl/FontResolution.md) 与 [Renderer](../../api/sdl/Renderer.md)。

超过 GPU 单张纹理上限的文字在整段 shaping 后分块上传；采样边缘保留相邻像素，旋转时所有块使用同一整段中心。纹理预算按实际块计数并包含采样边缘；CPU Surface 另限 16M 像素（64 MiB RGBA）。

## 数值字重、设计轴和默认字体

`FontStyle(weight: FontWeight(625))` 请求数值字重；bold 对应 700。系统目录保留全部静态面及命名实例，按倾斜、字宽和字重顺序匹配。FontFamily 的 faces 参数支持附加静态 Medium/Semibold 文件。resolveFont 的 requestedWeight、faces[0].weight、source.variations、synthesizedStyle 和 warnings 区分请求、真实轮廓、近似和合成。

Fonts.setDefault(FontRole.systemUI) 使用平台 UI 角色，另有 sansSerif、serif、monospace。setSearchDirectories 增加应用目录；setFallbacks 配置全局缺字及随附保底字体。可用应用默认文件无需硬编码系统字体即可初始化。系统服务采用 Windows 设置与 DirectWrite、Linux fontconfig、macOS CoreText，仅在显式枚举时扫描目录；本轮仅 Windows 完成实机验证。

Fonts.supportsVariations() 检查官方 SDL_ttf 3.2+ 的支持版本。仓颉代码负责元数据与虚拟实例，不依赖扩展 DLL。轴通过 FontVariations 配置，传给 FontStyle 的 variations 参数。支持字体实际存在的轴，不自动设置 opsz。fontWeight 超范围钳制；显式未知或越界坐标报错。FontSource 的 instanceIndex 可固定命名实例，variations 可固定源坐标；固定源不被普通 fontWeight 自动重置。优先复用已有命名实例，其余坐标通过小型虚拟数据表打开；不会修改原文件或复制整份字库。

发布使用官方 SDL3／SDL3_ttf，见[运行库部署](deploy-native-runtime.md)。仅查询一个字体族时用 `Fonts.familyFaces(name)`；完整选择器由用户触发 `systemFamilyNames()`／`systemFonts()`，不要放在普通应用启动路径。

```cangjie verify
package docexample
import sdl.*
main(): Unit {
    Fonts.setDefault(FontRole.systemUI)
    Fonts.setSearchDirectories(["assets/fonts"])
    Fonts.registerFamily("Brand", FontFamily(FontSource("assets/Brand-Regular.ttf"),
        faces: [FontFaceDefinition(FontSource("assets/Brand-Medium.ttf"), weight: FontWeight.medium),
                FontFaceDefinition(FontSource("assets/Brand-Semibold.ttf"), weight: FontWeight.semiBold)]))
    let emphasis = FontStyle(weight: FontWeight(625), italic: true)
    println("${emphasis.weight.value}, variable support=${Fonts.supportsVariations()}")
}
```

可选的 Fonts.setMetadataCache(path) 持久保存目录元数据，省去重复文件元数据解析；应用需准备父目录。refreshSystemFonts(force: true) 强制重建，缓存写入失败不影响字体绘制。

当前字体文件解析支持 SFNT（TTF、OTF、TTC、OTC）；非 SFNT 文件不在本轮支持范围。具体资源预算及虚拟实例的映射开销见[缓存说明](../concepts/text-font-cache.md)。字体刷新与仍存活的旧测量会话使用不同的文件映射，新配置不会误用旧文件内容。


## 按需 Emoji 后备

绘制／测量包含 Emoji 候选字符的字符串时，自动将平台 Emoji 字体加入缺字后备链。Windows 定向查询 Segoe UI Emoji，Linux 依次尝试 Noto Color Emoji、Noto Emoji、Twemoji Mozilla，macOS 查询 Apple Color Emoji；不触发完整字体目录扫描。`FontRole.emoji` 可显式选择该角色。

按完整 Emoji 字素选择字体，主字体及显式后备优先；显式 VS16 请求 Emoji 外观时优先尝试彩色字体，VS15 不触发该替换。选择成功后，相邻同字体片段合并交给 SDL 公共 API 整形，度量、命中和绘制复用片段结果，避免 SDL_ttf 3.2.2 在 ZWJ 簇内拆分后备的缺陷。不存在的字形或合字仍受实际字体覆盖限制，不能保证所有旗帜或最新序列都呈现彩色。自动 Emoji 面使用常规字重与倾斜，不继承合成样式／变量轴。彩色像素使用字体调色板及调用透明度，普通文字颜色照常生效。

合并片段时会扣除各片段为高字形预留的顶部空间，再按字体基线对齐，避免 Emoji 在同行偏低。`fontMetrics().ascent` 是字体度量；独立文本的实际基线还可能包含其簇行原点偏移。通常应将同行混排作为完整字符串传给 `text`，由共享布局处理，不给 Emoji 设置固定垂直偏移。

普通文字不打开 Emoji 后备；含 Emoji 与普通文本分别使用不可变字体配置，纳入共同的 24 配置 LRU。同一 Renderer 的同实际字号自动 Emoji 后备共享原生实例，减少切换主字体族时的重复加载。彩色配置另有 64 MiB COLR／CPAL 表预算；它不是进程总内存上限，存活测量会话仍固定其字体。候选查询最多保存 256 条、128 KiB UTF-8 文本；字体重载清空按需发现状态。不引入 native 补丁或复制整个字体文件。

优先使用少量稳定字号、复用测量会话，避免逐帧注册或 reload。首次使用 Emoji 仍需加载平台彩色字体数据；不要把这部分开销误认为每个 Emoji 都复制一份字体。校准优先复用已有字体，必要的大型辅助字体在本次绘制结束后释放；具体预算与生命周期见[缓存说明](../concepts/text-font-cache.md)。

文本处理工具可直接使用 [sdl.text 字素边界函数](../../api/sdl/text/functions.md)，与后备和 CangjieGUI 编辑器共享 Unicode 17 规则。`👩🏽‍💻` 为一个字素；两个独立表情可写为 `👩🏽 💻`。普通文本保持原有快速路径，不创建 Emoji 字素映射。栅格纹理保留校准后越过左／上边界的实际像素，并携带原点偏移，斜体与旋转绘制无需应用手工补偿。
