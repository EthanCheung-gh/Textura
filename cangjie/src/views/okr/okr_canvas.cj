package textura.views.okr

import std.collection.ArrayList
import cui.*
import textura.ui.*

/*
 * OKR 页的画布：一帧的绘制指令 + 子控件 + 命中区域。
 *
 * 页面用「手写 CSS 布局」而不是 CUI 的 VStack/HStack，原因有两条：
 *   1. `Label.measure` 最小 28vp 且额外 6vp（third_party/CUI/src/core/label.cj），
 *      okr.css 的行盒是「line-height × 字号」，堆 Label 会整体偏高；
 *   2. 本页的列宽/基线全部来自 okr.css 的固定值（例如 KR 进度条 `flex: 0 0 150px`、
 *      `--radius-lg: 14`、指标输入 78×28），需要逐像素定位。
 *
 * 交互控件：
 *   - Badge / Progress 用 `textura.ui` 的共享控件（无身份需求，直接给 frame）；
 *   - 按钮、分段控件、信心刻度、chip 用本页自绘 + `OkrHotspot` 命中区。
 *     原因：`textura.ui` 的 ButtonView 在「构建块之外」构造时拿不到唯一 id
 *     （`focusableControlIdentity` 退化为同一个 `UiButton`），而本页的所有子控件都在
 *     layout 阶段构造（构建阶段没有 UiContext，无法测量文字）。自绘 + 构造期登记焦点环，
 *     才能同时保证精确几何与键盘可达。
 *   - 文本输入用 CUI `TextField`（显式 key + 构造期登记的焦点 id）。
 */

/** `okr.css:5-8 .page.okr-page { max-width: 1080px }` */
let OKR_PAGE_MAX_W: Float32 = 1080.0
/** `tokens.css` 的 --space-1..4（两主题相同）。 */
let OKR_S1: Float32 = 4.0
let OKR_S2: Float32 = 8.0
let OKR_S3: Float32 = 12.0
let OKR_S4: Float32 = 16.0
/** `--radius-sm|md|lg`。 */
let OKR_R_SM: Float32 = 4.0
let OKR_R_MD: Float32 = 8.0
let OKR_R_LG: Float32 = 14.0
/** `.badge { padding: 2px 7px; font-size: 11px; line-height: 1.6; border: 1px }`
 *  → 11 × 1.6 + 2×2 + 2×1 = 23.6。 */
let OKR_BADGE_H: Float32 = 23.6
/** `.badge { padding: 0 7px }` 的水平内边距 + 边框。 */
let OKR_BADGE_CHROME: Float32 = 16.0

/** 一个可点击区域：`id` 同时是焦点 id（构造期登记，见 OkrPage.registerFocusOrder）。 */
class OkrHotspot {
    let id: String
    let rect: Rect
    let action: () -> Unit

    init(id: String, rect: Rect, action: () -> Unit) {
        this.id = id
        this.rect = rect
        this.action = action
    }
}

class PageCanvas {
    let tokens: ThemeTokens
    let theme: Theme
    let paint = OkrPaint()
    let children = ArrayList<Widget>()
    let childRects = ArrayList<Rect>()
    let hotspots = ArrayList<OkrHotspot>()
    /**
     * Height-only pass (`OkrPage.measure`): record geometry but construct no child widget.
     *
     * The page's intrinsic height has to be known before it is laid out — a page measured at height
     * 0 makes the hugging shell allocate nothing and the page never gets a real layout (see
     * `OkrPage.measure`). Running the normal layout code with this flag set reuses every row/height
     * formula while skipping the controls (which own `State`s and, for `TextField.autofocus`, a
     * frame subscriber) — those must be created exactly once, in the real layout pass.
     */
    let measureOnly: Bool

    init(tokens: ThemeTokens, theme: Theme, measureOnly!: Bool = false) {
        this.tokens = tokens
        this.theme = theme
        this.measureOnly = measureOnly
    }

    func color(): TokenColors {
        tokens.color
    }

    // ------------------------------------------------------------------ paint helpers

    /** 一条左对齐文字；返回 advance 宽。 */
    func text(ctx: UiContext, x: Float32, centerY: Float32, value: String, size: Float32, weight: Int64,
        color: Color, mono!: Bool = false, id!: String = "", hoverColor!: ?Color = None): Float32 {
        if (value.isEmpty()) {
            return 0.0
        }
        paint.texts.add(OkrTextOp(x, centerY, value, size, weight, color, mono: mono, id: id, hoverColor: hoverColor))
        okrTextW(ctx, value, size, weight, mono: mono)
    }

    /** 右对齐文字（先量宽再定位）。 */
    func textRight(ctx: UiContext, right: Float32, centerY: Float32, value: String, size: Float32, weight: Int64,
        color: Color, mono!: Bool = false, id!: String = "", hoverColor!: ?Color = None): Float32 {
        let width = okrTextW(ctx, value, size, weight, mono: mono)
        text(ctx, right - width, centerY, value, size, weight, color, mono: mono, id: id, hoverColor: hoverColor)
        width
    }

    /** 居中文字。 */
    func textCenter(ctx: UiContext, centerX: Float32, centerY: Float32, value: String, size: Float32, weight: Int64,
        color: Color, mono!: Bool = false, id!: String = "", hoverColor!: ?Color = None): Float32 {
        let width = okrTextW(ctx, value, size, weight, mono: mono)
        text(ctx, centerX - width / 2.0, centerY, value, size, weight, color, mono: mono, id: id, hoverColor: hoverColor)
        width
    }

    /**
     * 盒模型坐标对齐到设备像素：浏览器在绘制 1px 边框时会把边框盒吸附到整像素，
     * CUI 不做这层吸附，小数坐标会让 1px 线变成 2px 的半透明线（parity 会整行差异）。
     */
    func snap(rect: Rect): Rect {
        let left = Float32(Int64(rect.x + 0.5))
        let top = Float32(Int64(rect.y + 0.5))
        let right = Float32(Int64(rect.right() + 0.5))
        let bottom = Float32(Int64(rect.bottom() + 0.5))
        Rect(left, top, max(0.0, right - left), max(0.0, bottom - top))
    }

    /** 取整到设备像素（与 CSS 边框吸附一致）。 */
    func snapValue(value: Float32): Float32 {
        Float32(Int64(value + 0.5))
    }

    func fill(rect: Rect, radius: Float32, color: Color, id!: String = "", hoverColor!: ?Color = None): Unit {
        paint.fills.add(OkrFillOp(snap(rect), radius, color, id: id, hoverColor: hoverColor))
    }

    /** `border: 1px` 在 CSS 里占满整像素行；描边中心内缩半个线宽才不会出现半像素灰边。 */
    func stroke(rect: Rect, radius: Float32, color: Color): Unit {
        let width = tokens.metrics.borderWidth
        let frame = snap(rect).inset(width / 2.0)
        paint.strokes.add(OkrStrokeOp(frame, max(0.0, radius - width / 2.0), width, color))
    }

    func dashed(rect: Rect, radius: Float32, color: Color): Unit {
        paint.dashes.add(OkrDashOp(snap(rect), radius, color))
    }

    func shadow(rect: Rect, radius: Float32): Unit {
        paint.shadows.add(OkrShadowOp(snap(rect), radius))
    }

    func dot(centerX: Float32, centerY: Float32, radius: Float32, color: Color): Unit {
        paint.dots.add(OkrDotOp(centerX, centerY, radius, color))
    }

    func hLine(x1: Float32, x2: Float32, y: Float32, color: Color, dashed!: Bool = false): Unit {
        let top = snapValue(y)
        paint.lines.add(OkrLineOp(x1, top, x2, top + 1.0, tokens.metrics.borderWidth, color, dashed: dashed))
    }

    func vLine(x: Float32, y1: Float32, y2: Float32, color: Color, dashed!: Bool = false): Unit {
        let left = snapValue(x)
        paint.lines.add(OkrLineOp(left, y1, left + 1.0, y2, tokens.metrics.borderWidth, color, dashed: dashed))
    }

    func chevron(rect: Rect, up: Bool, color: Color): Unit {
        paint.chevrons.add(OkrChevronOp(rect, up, color))
    }

    func icon(rect: Rect, glyph: IconGlyph, color: Color): Unit {
        paint.icons.add(OkrIconOp(rect, glyph, color))
    }

    func focusRingFor(id: String, rect: Rect, radius: Float32): Unit {
        paint.rings.add(OkrRingOp(id, rect, radius))
    }

    // ------------------------------------------------------------------ children

    /** 加入一个子控件并立即给它 frame（控件按 ui.css 自绘）。 */
    func addChild(ctx: UiContext, widget: Widget, rect: Rect): Rect {
        let snapped = snap(rect)
        if (measureOnly) {
            // Height-only pass: the caller already fixed this row's height; constructing a control
            // here would create a second, discarded owner of the same focus id and `State`s.
            return snapped
        }
        widget.layout(ctx, snapped)
        children.add(widget)
        childRects.add(snapped)
        snapped
    }

    /** `textura.ui` 徽章：宽度按其自身测量，高度用 CSS 的 23.6（border-box）。 */
    func badge(ctx: UiContext, x: Float32, y: Float32, text: String, tone: BadgeTone, dot!: Bool = false): Float32 {
        if (measureOnly) {
            // The returned width only advances a horizontal cursor; no row height depends on it.
            return 0.0
        }
        let widget = BadgeView(tokens, text, tone: tone, dot: dot)
        let measured = widget.measure(ctx, Size(10000.0, OKR_BADGE_H))
        addChild(ctx, widget, Rect(x, y, measured.w, OKR_BADGE_H))
        measured.w
    }

    /** `textura.ui` 进度条（无标签）；返回轨道矩形。 */
    func progress(ctx: UiContext, rect: Rect, value: Float32, tone: ProgressTone, size: ControlSize): Rect {
        if (measureOnly) {
            return rect
        }
        let widget = ProgressView(tokens, value, tone: tone, size: size)
        addChild(ctx, widget, rect)
        rect
    }

    func addHotspot(id: String, rect: Rect, action: () -> Unit): Unit {
        hotspots.add(OkrHotspot(id, rect, action))
    }

    func draw(ctx: UiContext): Unit {
        paint.draw(ctx, tokens)
    }

    /** 子控件画在自绘层之上（徽章/进度条/输入框都落在自己的 frame 内，不与其他元素重叠）。 */
    func drawChildren(ctx: UiContext): Unit {
        for (child in children) {
            child.draw(ctx)
        }
    }
}
