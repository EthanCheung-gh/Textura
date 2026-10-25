package textura.views.okr

import std.collection.ArrayList
import cui.*
import textura.ui.*

/*
 * OKR 页的自绘基元（文字 / 填充 / 描边 / 虚线 / 图标 / 分隔线）。
 *
 * 为什么整页自绘而不是堆 Label：
 *   CUI 的 `Label.measure` 返回 `max(28, lineHeight + 6)`（third_party/CUI/src/core/label.cj），
 *   即最小 28vp、并且在自然行高之外再加 6vp；而 okr.css 的行盒高度是
 *   「line-height × font-size」（例如 11px × 1.5 = 16.5vp）。用 Label 堆叠整体会偏高
 *   十几个像素，无法做到 1:1。因此视图自己计算行盒位置，按 CSS 的 line-height 居中绘制文字
 *   （CSS 的半行距也是把文本盒居中放进行盒，规则一致）。
 *
 * 交互控件仍然用 `textura.ui` 的共享控件（Badge / Progress / Button / IconButton /
 * Segmented / TextField）：本页只负责给它们精确 frame，控件按 ui.css 自行绘制。
 */

/** 文本整体的纵向微调（设备像素）：对齐 Chromium 的基线吸附。 */
let OKR_TEXT_DY: Float32 = -1.0
/*
 * 说明：曾试验过"同色低透明度补绘"来补偿 CUI/SDL_ttf 与 Chromium 的灰度抗锯齿覆盖率差
 * （实测参考图文字墨量高 6%~7%），但字形边缘形状本身不同，指标没有改善（96.42% → 96.41%），
 * 因此保留单次绘制，不在视图层伪造字重/颜色。
 */

/** 一条文字：左端 x + 行盒中心 y（CSS `line-height` 居中）。 */
class OkrTextOp {
    let x: Float32
    let centerY: Float32
    let text: String
    /** CSS font-size（px） */
    let size: Float32
    let weight: Int64
    let color: Color
    /** advance 宽（布局阶段已经量过；绘制与可见性判断都直接用它，不再重复测量） */
    let width: Float32
    /** `.mono` —— 使用 `--font-mono` 族 */
    let mono: Bool
    /** 可悬停区域的 id（空串表示不参与 hover 换色） */
    let id: String
    let hoverColor: ?Color

    init(
        x: Float32,
        centerY: Float32,
        text: String,
        size: Float32,
        weight: Int64,
        color: Color,
        width: Float32,
        mono!: Bool = false,
        id!: String = "",
        hoverColor!: ?Color = None
    ) {
        this.x = x
        this.centerY = centerY
        this.text = text
        this.size = size
        this.weight = weight
        this.color = color
        this.width = width
        this.mono = mono
        this.id = id
        this.hoverColor = hoverColor
    }

    /**
     * 这一条文字可能落笔的盒子，用于视口裁剪。
     *
     * 行盒高度取 `±size`（`drawText` 画的是 `height ≈ 1.3 × size` 的行、垂直居中在 `centerY`），
     * 宽度用布局阶段量到的 advance；两侧都留够，宁可多画一条也不裁掉半个字形。
     */
    func box(): Rect {
        Rect(x, centerY - size, width, size * 2.0)
    }
}

/*
 * 视口裁剪（CUI-P11 `UiContext.clipPaintBounds`）。
 *
 * 为什么需要它：OKR 是自绘画布，一整页（可能几十张卡片）就是一张 `draw` 的指令表，而滚动容器
 * `ScrollView` 只给了画布一个裁剪矩形。滚动时唯一变化的就是这个矩形——文档几何一点没动——但画布
 * 每帧都把整篇文档重新下发，视口外的部分被 backend 的 scissor 白白丢掉：滚动的成本因此按「文档
 * 长度」而不是「视口大小」增长，一页 150 条数据的 workspace 每帧要画 600 多条文字。
 *
 * 裁剪判据的保守性：`paintBounds` 之外还要再放宽 `OKR_CULL_MARGIN`。阴影（`--shadow-2`
 * blur 32 + offsetY 12 ⇒ 最多外溢 28px）、焦点环（outset 3px）、形状的 0.7px 抗锯齿边都在
 * 这个余量之内，所以「被跳过」的 op 与视口至少隔 32px，一个像素都不可能落在可见区。
 */
let OKR_CULL_MARGIN: Float32 = 32.0

/** 本帧真正能落笔的区域（裁剪矩形外扩 `OKR_CULL_MARGIN`）；`None` = 没有被裁剪。 */
func okrPaintBounds(ctx: UiContext): ?Rect {
    match (ctx.clipPaintBounds()) {
        case Some(clip) => Some(Rect(clip.x - OKR_CULL_MARGIN, clip.y - OKR_CULL_MARGIN,
            clip.w + OKR_CULL_MARGIN * 2.0, clip.h + OKR_CULL_MARGIN * 2.0))
        case None => None
    }
}

/**
 * `true` 表示 `rect` 与可见区**严格分离**，可以整条跳过。
 *
 * 判据是严格不等式：仅仅贴住边界的 op 仍然会被画出来。这样「跳过」的边缘情况永远是保守的
 * ——最坏情况是多重画一条本来就落在 32px 余量里的 op，绝不会出现少画。
 */
func okrClipped(bounds: ?Rect, rect: Rect): Bool {
    match (bounds) {
        case Some(clip) => rect.right() < clip.x || rect.x > clip.right() || rect.bottom() < clip.y ||
            rect.y > clip.bottom()
        case None => false
    }
}

/** `background:` + `border-radius:`。 */
class OkrFillOp {
    let rect: Rect
    let radius: Float32
    let color: Color
    let id: String
    let hoverColor: ?Color

    init(rect: Rect, radius: Float32, color: Color, id!: String = "", hoverColor!: ?Color = None) {
        this.rect = rect
        this.radius = radius
        this.color = color
        this.id = id
        this.hoverColor = hoverColor
    }
}

/** `border: Npx solid ...`（描边画在盒内，与 CSS border-box 一致）。 */
class OkrStrokeOp {
    let rect: Rect
    let radius: Float32
    let width: Float32
    let color: Color

    init(rect: Rect, radius: Float32, width: Float32, color: Color) {
        this.rect = rect
        this.radius = radius
        this.width = width
        this.color = color
    }
}

/** `border: 1px dashed`；CUI 的 `Pen` 没有虚线样式，按 CSS 的 3px 实线 + 2px 空隙自绘。 */
class OkrDashOp {
    let rect: Rect
    let radius: Float32
    let color: Color

    init(rect: Rect, radius: Float32, color: Color) {
        this.rect = rect
        this.radius = radius
        this.color = color
    }
}

/** `.okr-area-dot { width: 7px; height: 7px; border-radius: 50% }`。 */
class OkrDotOp {
    let centerX: Float32
    let centerY: Float32
    let radius: Float32
    let color: Color

    init(centerX: Float32, centerY: Float32, radius: Float32, color: Color) {
        this.centerX = centerX
        this.centerY = centerY
        this.radius = radius
        this.color = color
    }
}

/**
 * 1px 分隔线（`.okr-kr-section` 的上边框、对齐视图的竖线/连接线）。
 * `x1/y1` 是左上角，`x2/y2` 是右下角（水平线高度 1、竖线宽度 1）。
 */
class OkrLineOp {
    let x1: Float32
    let y1: Float32
    let x2: Float32
    let y2: Float32
    let width: Float32
    let color: Color
    let dashed: Bool

    init(x1: Float32, y1: Float32, x2: Float32, y2: Float32, width: Float32, color: Color, dashed!: Bool = false) {
        this.x1 = x1
        this.y1 = y1
        this.x2 = x2
        this.y2 = y2
        this.width = width
        this.color = color
        this.dashed = dashed
    }
}

/** `icons.tsx` 的 24×24 描边图标（复用 `textura.ui` 的展平器）。 */
class OkrIconOp {
    let rect: Rect
    let glyph: IconGlyph
    let color: Color

    init(rect: Rect, glyph: IconGlyph, color: Color) {
        this.rect = rect
        this.glyph = glyph
        this.color = color
    }
}

/** chevron 描边（上/下）：Web 用 `rotate(90deg)` 旋转 chevron，CUI 图标集没有上下箭头。 */
class OkrChevronOp {
    let rect: Rect
    let up: Bool
    let color: Color

    init(rect: Rect, up: Bool, color: Color) {
        this.rect = rect
        this.up = up
        this.color = color
    }
}

/** `--shadow-1`。 */
class OkrShadowOp {
    let rect: Rect
    let radius: Float32

    init(rect: Rect, radius: Float32) {
        this.rect = rect
        this.radius = radius
    }
}

/** 键盘焦点环（`--focus-ring`）挂在整组控件外侧。 */
class OkrRingOp {
    let id: String
    let rect: Rect
    let radius: Float32

    init(id: String, rect: Rect, radius: Float32) {
        this.id = id
        this.rect = rect
        this.radius = radius
    }
}

/**
 * 一帧的绘制指令集合；顺序即绘制顺序（阴影 → 填充 → 描边 → 虚线 → 点 → 线 → 图标 → 文字）。
 *
 * **跨帧复用**：`OkrPage` 把同一个 `OkrPaint` 记在 `remember` 里，每次 layout 交给 `PageCanvas`
 * 复用，由它先 `clear()` 再按本帧几何重填。容器（连同已经长到全量的底层数组）因此不再每帧新建：
 * 光标闪烁这类「只重绘、不改内容」的帧原本要重新分配 10 个 `ArrayList` 及其扩容数组，现在只是把
 * 长度归零。
 */
class OkrPaint {
    let shadows = ArrayList<OkrShadowOp>()
    let fills = ArrayList<OkrFillOp>()
    let strokes = ArrayList<OkrStrokeOp>()
    let dashes = ArrayList<OkrDashOp>()
    let dots = ArrayList<OkrDotOp>()
    let lines = ArrayList<OkrLineOp>()
    let icons = ArrayList<OkrIconOp>()
    let chevrons = ArrayList<OkrChevronOp>()
    let texts = ArrayList<OkrTextOp>()
    let rings = ArrayList<OkrRingOp>()

    /** 清空全部指令，保留容器已分配的容量（跨帧复用时的唯一入口）。 */
    func clear(): Unit {
        shadows.clear()
        fills.clear()
        strokes.clear()
        dashes.clear()
        dots.clear()
        lines.clear()
        icons.clear()
        chevrons.clear()
        texts.clear()
        rings.clear()
    }

    /** 指令总条数（测试与诊断用：跨帧复用后它必须等于「一次 layout 产生的条数」）。 */
    func opCount(): Int64 {
        shadows.size + fills.size + strokes.size + dashes.size + dots.size + lines.size + icons.size +
            chevrons.size + texts.size + rings.size
    }

    func draw(ctx: UiContext, tokens: ThemeTokens): Unit {
        // Viewport culling. The only thing that changes while a wheel scrolls this page is the
        // `ScrollView`'s clip, not the document geometry, so every op the clip has scrolled out is
        // released here instead of being pushed into the renderer and thrown away by its scissor —
        // the whole reason a scroll step used to cost the same as painting the entire document.
        // `okrPaintBounds` inflates the clip by `OKR_CULL_MARGIN`, so nothing that can paint into
        // the viewport (shadow halo, focus ring, anti-aliasing fringe) is ever skipped.
        let bounds = okrPaintBounds(ctx)
        for (op in shadows) {
            if (okrClipped(bounds, op.rect)) {
                continue
            }
            shadow1(ctx, tokens, op.rect, op.radius)
        }
        for (op in fills) {
            if (okrClipped(bounds, op.rect)) {
                continue
            }
            fillRound(ctx, op.rect, op.radius, opColor(ctx, op.id, op.color, op.hoverColor))
        }
        for (op in strokes) {
            if (okrClipped(bounds, op.rect)) {
                continue
            }
            strokeRound(ctx, op.rect, op.radius, op.width, op.color)
        }
        for (op in dashes) {
            if (okrClipped(bounds, op.rect)) {
                continue
            }
            dashedRoundRect(ctx, op.rect, op.radius, op.color)
        }
        for (op in dots) {
            if (okrClipped(bounds, Rect(op.centerX - op.radius, op.centerY - op.radius, op.radius * 2.0,
                op.radius * 2.0))) {
                continue
            }
            ctx.renderer.fillCircle(op.centerX, op.centerY, op.radius, op.color)
        }
        for (op in lines) {
            if (okrClipped(bounds, Rect(op.x1, op.y1, op.x2 - op.x1, op.y2 - op.y1))) {
                continue
            }
            drawLine(ctx, op)
        }
        for (op in icons) {
            if (okrClipped(bounds, op.rect)) {
                continue
            }
            paintSpec(ctx, op.glyph, op.rect, op.color)
        }
        for (op in chevrons) {
            if (okrClipped(bounds, op.rect)) {
                continue
            }
            drawChevron(ctx, op)
        }
        for (op in texts) {
            if (okrClipped(bounds, op.box())) {
                continue
            }
            drawText(ctx, op)
        }
        for (op in rings) {
            if (okrClipped(bounds, op.rect)) {
                continue
            }
            if (ctx.showFocusRing(op.id)) {
                focusRing(ctx, tokens, op.rect, op.radius)
            }
        }
    }
}

/** hover 换色只在 `id` 被悬停时生效（`title` 悬停、chip hover 等）。 */
func opColor(ctx: UiContext, id: String, color: Color, hoverColor: ?Color): Color {
    match (hoverColor) {
        case Some(candidate) => if (id.isEmpty() || !ctx.isHovered(id)) {
            color
        } else {
            candidate
        }
        case None => color
    }
}

func drawText(ctx: UiContext, op: OkrTextOp): Unit {
    if (op.text.isEmpty()) {
        return
    }
    let color = opColor(ctx, op.id, op.color, op.hoverColor)
    let pointSize = fpSize(ctx, op.size)
    let style = FontStyle(weight: cssWeight(op.weight))
    let family: ?String = if (op.mono) {
        Some(fontMono())
    } else {
        None
    }
    let height = ctx.textHeight(pointSize: pointSize, style: style, font: family)
    // Chromium 在 DPR=1 时把文本基线吸附到整像素；这里把文本盒顶边吸附，避免 FreeType
    // 在亚像素位置渲染出与浏览器不同的抗锯齿。
    ctx.text(op.text, op.x, op.centerY - height / 2.0 + OKR_TEXT_DY, color, pointSize: pointSize, style: style,
        font: family)
}

func drawLine(ctx: UiContext, op: OkrLineOp): Unit {
    // 1px 规则线用整数矩形填充（`strokeLine` 的 1vp 笔宽会跨 3 行做抗锯齿）
    if (op.x1 == op.x2) {
        if (!op.dashed) {
            ctx.renderer.fill(Rect(op.x1, op.y1, 1.0, op.y2 - op.y1), op.color)
        } else {
            var y = Float32(Int64(op.y1 + 0.5))
            while (y < op.y2) {
                let step = min(Float32(3.0), op.y2 - y)
                ctx.renderer.fill(Rect(op.x1, y, 1.0, step), op.color)
                y += 5.0
            }
        }
        return
    }
    if (!op.dashed) {
        ctx.renderer.fill(Rect(op.x1, op.y1, op.x2 - op.x1, 1.0), op.color)
        return
    }
    var x = Float32(Int64(op.x1 + 0.5))
    while (x < op.x2) {
        let step = min(Float32(3.0), op.x2 - x)
        ctx.renderer.fill(Rect(x, op.y1, step, 1.0), op.color)
        x += 5.0
    }
}

/** CSS `dashed` 圆角矩形：四边按 3 实 2 空推进，圆角段留空。 */
func dashedRoundRect(ctx: UiContext, rect: Rect, radius: Float32, color: Color): Unit {
    if (rect.w <= 0.0 || rect.h <= 0.0) {
        return
    }
    let pen = Pen(width: 1.0, color: color)
    let inset: Float32 = 0.5
    let left = rect.x + inset
    let right = rect.right() - inset
    let top = rect.y + inset
    let bottom = rect.bottom() - inset
    let corner = min(radius, min(rect.w / 2.0, rect.h / 2.0))
    // 相位与整像素吸附：Chrome 的 1px dashed 是 3px 实线 + 2px 空隙，从圆角结束处起算
    let startX = Float32(Int64((left + corner) + 0.5))
    let endX = Float32(Int64((right - corner) + 0.5))
    let startY = Float32(Int64((top + corner) + 0.5))
    let endY = Float32(Int64((bottom - corner) + 0.5))
    drawDashedSpan(ctx, startX, top, endX, top, pen)
    drawDashedSpan(ctx, startX, bottom, endX, bottom, pen)
    drawDashedSpan(ctx, left, startY, left, endY, pen)
    drawDashedSpan(ctx, right, startY, right, endY, pen)
}

func drawDashedSpan(ctx: UiContext, x1: Float32, y1: Float32, x2: Float32, y2: Float32, pen: Pen): Unit {
    let vertical = x1 == x2
    let length = if (vertical) {
        y2 - y1
    } else {
        x2 - x1
    }
    var travelled: Float32 = 0.0
    while (travelled < length) {
        let dash = min(Float32(3.0), length - travelled)
        if (vertical) {
            ctx.renderer.strokeLine(x1, y1 + travelled, x2, y1 + travelled + dash, pen)
        } else {
            ctx.renderer.strokeLine(x1 + travelled, y1, x1 + travelled + dash, y2, pen)
        }
        travelled += 5.0
    }
}

/** 文字 advance 宽（CSS px 入参）。 */
/** chevron 在 24 网格上是 (6,9)-(12,15)-(18,9)，strokeWidth 1.75；`up` 为垂直镜像。 */
func drawChevron(ctx: UiContext, op: OkrChevronOp): Unit {
    let side = min(op.rect.w, op.rect.h)
    let pen = Pen(width: max(1.0, 1.75 * side / 24.0), color: op.color)
    let x0 = op.rect.x + side * 6.0 / 24.0
    let x1 = op.rect.x + side * 12.0 / 24.0
    let x2 = op.rect.x + side * 18.0 / 24.0
    let yOuter = if (op.up) {
        op.rect.y + side * 15.0 / 24.0
    } else {
        op.rect.y + side * 9.0 / 24.0
    }
    let yTip = if (op.up) {
        op.rect.y + side * 9.0 / 24.0
    } else {
        op.rect.y + side * 15.0 / 24.0
    }
    ctx.renderer.strokeLine(x0, yOuter, x1, yTip, pen)
    ctx.renderer.strokeLine(x1, yTip, x2, yOuter, pen)
    // 圆角连接：与 `strokeLinecap: round` 观感一致
    ctx.renderer.fillCircle(x1, yTip, pen.width / 2.0, op.color)
}

func okrTextW(ctx: UiContext, text: String, size: Float32, weight: Int64, mono!: Bool = false): Float32 {
    if (text.isEmpty()) {
        return 0.0
    }
    let family: ?String = if (mono) {
        Some(fontMono())
    } else {
        None
    }
    ctx.textWidth(text, pointSize: fpSize(ctx, size), style: FontStyle(weight: cssWeight(weight)), font: family)
}

/** 单行文本按 `maxWidth` 截断并补 U+2026（CSS `text-overflow: ellipsis`）。 */
func ellipsize(ctx: UiContext, text: String, size: Float32, weight: Int64, maxWidth: Float32,
    mono!: Bool = false): String {
    if (okrTextW(ctx, text, size, weight, mono: mono) <= maxWidth) {
        return text
    }
    let runes = text.toRuneArray()
    var keep = runes.size
    while (keep > 0) {
        let candidate = String(runes[0..keep]) + "…"
        if (okrTextW(ctx, candidate, size, weight, mono: mono) <= maxWidth) {
            return candidate
        }
        keep -= 1
    }
    "…"
}

/** 逐字换行（CSS `line-height: 1.5` 的多行文本）。 */
func wrapText(ctx: UiContext, text: String, size: Float32, weight: Int64, maxWidth: Float32): Array<String> {
    let lines = ArrayList<String>()
    if (text.isEmpty() || maxWidth <= 0.0) {
        return lines.toArray()
    }
    let runes = text.toRuneArray()
    var start = 0
    while (start < runes.size) {
        var end = start + 1
        var lastFit = start
        while (end <= runes.size) {
            let candidate = String(runes[start..end])
            if (okrTextW(ctx, candidate, size, weight) > maxWidth && end > start + 1) {
                break
            }
            lastFit = end
            end += 1
        }
        lines.add(String(runes[start..lastFit]))
        start = lastFit
    }
    lines.toArray()
}

/** `#RRGGBB` → `Color`（`Area.color` 是领域数据，不是设计令牌）。 */
func hexColor(text: String, fallback: Color): Color {
    let runes = text.toRuneArray()
    if (runes.size != 7 || runes[0] != r'#') {
        return fallback
    }
    var values = Array<Int64>(3, repeat: 0)
    var index = 0
    while (index < 3) {
        let high = hexDigit(runes[1 + index * 2])
        let low = hexDigit(runes[2 + index * 2])
        if (high < 0 || low < 0) {
            return fallback
        }
        values[index] = high * 16 + low
        index += 1
    }
    Color.rgb(values[0], values[1], values[2])
}

func hexDigit(rune: Rune): Int64 {
    let code = Int64(UInt32(rune))
    let zero = Int64(UInt32(r'0'))
    let lowerA = Int64(UInt32(r'a'))
    let upperA = Int64(UInt32(r'A'))
    if (code >= zero && code <= zero + 9) {
        return code - zero
    }
    if (code >= lowerA && code <= lowerA + 5) {
        return code - lowerA + 10
    }
    if (code >= upperA && code <= upperA + 5) {
        return code - upperA + 10
    }
    -1
}

/** `Math.round` 语义的 0..100 取整（进度条与百分数文案共用）。 */
func roundPercent(value: Float64): Float64 {
    if (value.isNaN()) {
        return 0.0
    }
    let clamped = min(max(value, 0.0), 100.0)
    Float64(Int64(clamped + 0.5))
}

/** 两位补零（`.okr-kr-index` 的 `01`）。 */
func pad2(value: Int64): String {
    if (value < 10) {
        "0${value}"
    } else {
        "${value}"
    }
}
