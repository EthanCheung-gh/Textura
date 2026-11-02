package textura.views.dashboard

import cui.*
import std.collection.*
import textura.ui.*

/*
 * 文本与盒模型基元（今日视图自用绘制层）。
 *
 * 为什么不用 `Label`：网页的每一行都靠 CSS 行盒定位（`line-height: 1.5`，
 * `base.css:33`），而 CUI 的 `Label` 按字体自然行高排版，累计误差会到 5px 以上。
 * 这里把「行盒高度 / 基线位置 / 内边距」都按 CSS 的数值算出来，再交给
 * `textura.ui` 的 `textLeading` / `paintSpec` / `fillRound` 等公开基元绘制，
 * 令牌只从 `textura.ui` 取（`tokensOf`），不出现十六进制颜色。
 */

/**
 * 基线微调：按字号分段，等价于浏览器「把行内盒基线吸附到整数设备像素」的结果。
 *
 * 依据（参考图与快照逐块比对，墨水框 y 值）：
 *   - 11.5px（`.dash-stat-label` 202 / `.dash-stat-meta` 258 / `.dash-card-sub` 355）：未修正时
 *     本移植整行低 1px（203 / 259 / 356），故 11.5 档取 -1.5；
 *   - 11px（`.dash-sop-meta` 562、`.dash-activity-time` 719）：已对齐，取 -0.5；
 *   - 12–13.5px（`.dash-summary` 142、`.dash-okr-title` 403、`.dash-focus-title` 394）：已对齐，取 -0.5；
 *   - 22px h1（108）与 26px 数值（227）：已对齐，取 -0.5。
 * 只对 11.5 档多抬 1px，避免牵动已经对齐的其它字号。
 */
func baselineNudge(fontSize: Float32): Float32 {
    if (fontSize > 11.0 && fontSize < 11.75) {
        return -1.5
    }
    -0.5
}

/** `base.css:33 body { line-height: 1.5 }` —— 全站唯一的行高倍数。 */
let DASH_LINE_HEIGHT: Float32 = 1.5

/** 一个 1.5 倍行高的 CSS 行盒高度（`base.css:33`）。 */
func lineBoxHeight(ctx: UiContext, fontSize: Float32): Float32 {
    fpSize(ctx, fontSize) * DASH_LINE_HEIGHT
}

func weightStyle(weight: Int64): FontStyle {
    FontStyle(weight: cssWeight(mappedWeight(weight)))
}

/**
 * CSS 字重 → 可用字面。
 *
 * 系统只装了 Noto Sans CJK 的 Regular / Bold 两个面（`textura.ui` 注册的等价档），
 * 550/650 这类可变字重必须落到最近的字面：550 落 Regular（浏览器把 550 渲染得比 600 轻，
 * 与 Regular 的差距小于与 Bold 的差距），650 落 Bold。参考图上 h1（650）比 Regular 更黑、
 * 行标题（550）比 Bold 更淡，两条都用墨水密度核对过。
 */
func mappedWeight(weight: Int64): Int64 {
    if (weight >= 600) {
        return 700
    }
    if (weight >= 520) {
        return 500
    }
    weight
}

/**
 * CSS half-leading 规则下的基线位置：
 * `行盒顶 + (行高 - 内容高) / 2 + ascent`，与浏览器把字体内容盒垂直居中于 line box 一致。
 */
func baselineWithin(ctx: UiContext, boxTop: Float32, boxHeight: Float32, fontSize: Float32, weight: Int64): Float32 {
    let metrics = ctx.fontMetrics(pointSize: fpSize(ctx, fontSize), style: weightStyle(weight))
    boxTop + (boxHeight - (metrics.ascent + metrics.descent)) / 2.0 + metrics.ascent + baselineNudge(fontSize)
}

/** 单行文本的墨水宽度；`tracking` 复刻 CSS `letter-spacing`。 */
func advanceWidth(ctx: UiContext, text: String, fontSize: Float32, weight: Int64,
    tracking!: Float32 = 0.0, family!: ?String = None): Float32 {
    let raw = ctx.textWidth(text, pointSize: fpSize(ctx, fontSize), style: weightStyle(weight), font: family)
    if (tracking == 0.0) {
        return raw
    }
    let count = text.toRuneArray().size
    if (count <= 1) {
        raw
    } else {
        raw + tracking * Float32(count - 1)
    }
}

/** 逐字形绘制，用于表达 CSS `letter-spacing`（CUI 没有字距 API）。 */
func drawTracked(ctx: UiContext, text: String, x: Float32, baseline: Float32, fontSize: Float32, weight: Int64,
    color: Color, tracking: Float32): Unit {
    if (text.isEmpty()) {
        return
    }
    let size = fpSize(ctx, fontSize)
    let style = weightStyle(weight)
    let metrics = ctx.fontMetrics(pointSize: size, style: style)
    var cursor = x
    for (rune in text.toRuneArray()) {
        let piece = String([rune])
        ctx.text(piece, cursor, baseline - metrics.ascent, color, pointSize: size, style: style)
        cursor += ctx.textWidth(piece, pointSize: size, style: style) + tracking
    }
}

/** 在 `[boxTop, boxTop + boxHeight]` 行盒里左对齐、按基线绘制一行文本。 */
func drawLine(ctx: UiContext, text: String, x: Float32, boxTop: Float32, boxHeight: Float32, fontSize: Float32,
    weight: Int64, color: Color, tracking!: Float32 = 0.0, family!: ?String = None): Unit {
    if (text.isEmpty()) {
        return
    }
    let baseline = baselineWithin(ctx, boxTop, boxHeight, fontSize, weight)
    if (tracking == 0.0) {
        let metrics = ctx.fontMetrics(pointSize: fpSize(ctx, fontSize), style: weightStyle(weight), font: family)
        ctx.text(text, x, baseline - metrics.ascent, color, pointSize: fpSize(ctx, fontSize),
            style: weightStyle(weight), font: family)
    } else {
        drawTracked(ctx, text, x, baseline, fontSize, weight, color, tracking)
    }
}

/** 同上，但右端对齐到 `right`。 */
func drawLineTrailing(ctx: UiContext, text: String, right: Float32, boxTop: Float32, boxHeight: Float32,
    fontSize: Float32, weight: Int64, color: Color): Unit {
    let width = advanceWidth(ctx, text, fontSize, weight)
    drawLine(ctx, text, right - width, boxTop, boxHeight, fontSize, weight, color)
}

/** 直接给基线：`.dash-stat-value` 里数值与单位按 `align-items: baseline`（dashboard.css:82-83）对齐。 */
func drawAtBaseline(ctx: UiContext, text: String, x: Float32, baseline: Float32, fontSize: Float32, weight: Int64,
    color: Color): Unit {
    if (text.isEmpty()) {
        return
    }
    let size = fpSize(ctx, fontSize)
    let style = weightStyle(weight)
    let metrics = ctx.fontMetrics(pointSize: size, style: style)
    ctx.text(text, x, baseline - metrics.ascent, color, pointSize: size, style: style)
}

/**
 * `text-overflow: ellipsis` 的等价物：宽度不够时按 Rune 截断并追加 `…`。
 * 用于 `.dash-focus-title` / `.dash-okr-title` / `.dash-sop-title` 等单行省略号规则。
 */
func ellipsize(ctx: UiContext, text: String, maxWidth: Float32, fontSize: Float32, weight: Int64): String {
    if (maxWidth <= 0.0) {
        return String()
    }
    if (advanceWidth(ctx, text, fontSize, weight) <= maxWidth) {
        return text
    }
    let ellipsis = "…"
    let ellipsisWidth = advanceWidth(ctx, ellipsis, fontSize, weight)
    if (maxWidth <= ellipsisWidth) {
        return String()
    }
    let runes = text.toRuneArray()
    let kept = ArrayList<Rune>()
    var width: Float32 = 0.0
    for (rune in runes) {
        let piece = String([rune])
        let next = width + advanceWidth(ctx, piece, fontSize, weight)
        if (next + ellipsisWidth > maxWidth) {
            break
        }
        kept.add(rune)
        width = next
    }
    String(kept.toArray()) + ellipsis
}

/**
 * 把带 alpha 的颜色合成到不透明底色上，得到不透明结果。
 *
 * 用途：像 `.dash-activity-icon` 那样「1px 淡边框 + 淡底色」的圆形要先铺不透明底色再叠淡色；
 * 直接叠两层半透明会把底色算两遍（参考图实测：叠两次的圆点是 40% 而不是 12%）。
 */
func overColor(base: Color, top: Color): Color {
    let alpha = Float32(Int64(top.a)) / 255.0
    let rest = 1.0 - alpha
    Color.rgb(
        Int64(Float32(Int64(top.r)) * alpha + Float32(Int64(base.r)) * rest + 0.5),
        Int64(Float32(Int64(top.g)) * alpha + Float32(Int64(base.g)) * rest + 0.5),
        Int64(Float32(Int64(top.b)) * alpha + Float32(Int64(base.b)) * rest + 0.5)
    )
}

/* ------------------------------------------------------------------ */
/* 徽章（`.badge`，ui.css:243-298；与 textura.ui 的 BadgeView 同几何）  */
/* ------------------------------------------------------------------ */

/** `.badge` 的三色组合（ui.css:264-298）。 */
struct BadgeSkin {
    let fill: Color
    let border: Color
    let ink: Color

    init(fill: Color, border: Color, ink: Color) {
        this.fill = fill
        this.border = border
        this.ink = ink
    }
}

func badgeSkin(tokens: ThemeTokens, tone: BadgeTone): BadgeSkin {
    let c = tokens.color
    match (tone) {
        case BadgeTone.Neutral =>
            // .badge--neutral { background: surface-2; border: border; color: text-muted }
            BadgeSkin(c.surface2, c.border, c.textMuted)
        case BadgeTone.Accent =>
            // .badge--accent { background: accent-soft; border: color-mix(accent 28%); color: accent-ink }
            BadgeSkin(c.accentSoft, tint(c.accent, 28.0), c.accentInk)
        case BadgeTone.Ok =>
            BadgeSkin(tint(c.ok, 12.0), tint(c.ok, 30.0), c.okInk)
        case BadgeTone.Warn =>
            BadgeSkin(tint(c.warn, 14.0), tint(c.warn, 32.0), c.warnInk)
        case BadgeTone.Danger =>
            BadgeSkin(tint(c.danger, 12.0), tint(c.danger, 30.0), c.dangerInk)
        case BadgeTone.Info =>
            BadgeSkin(tint(c.info, 12.0), tint(c.info, 30.0), c.infoInk)
    }
}

/**
 * `.badge`（ui.css:243-254）的盒模型：
 * `padding: 2px 7px` + `border: 1px` + `line-height: 1.6 × 11px`，
 * 因此高 = 11 × 1.6 + 2×2 + 2×1 = 23.6、宽 = 文字宽 + 7×2 + 2×1。
 * 参考图实测：`今天到期` 药丸 60 宽 / 23 高，`失败` 37 宽 —— 漏掉边框会窄、矮 2px。
 */
func badgePillHeight(ctx: UiContext): Float32 {
    fpSize(ctx, 11.0) * 1.6 + 4.0 + 2.0 * tokensBorderPx()
}

func badgePillWidth(ctx: UiContext, text: String): Float32 {
    advanceWidth(ctx, text, 11.0, 550) + 7.0 * 2.0 + 2.0 * tokensBorderPx()
}

/** `border: 1px`（tokens.css / base.css 全域约定）。 */
func tokensBorderPx(): Float32 {
    1.0
}

/** 画一个右端对齐到 `right`、垂直居中于 `centerY` 的徽章，返回药丸矩形。 */
func drawBadgeTrailing(ctx: UiContext, tokens: ThemeTokens, text: String, tone: BadgeTone, right: Float32,
    centerY: Float32): Rect {
    let width = badgePillWidth(ctx, text)
    let height = badgePillHeight(ctx)
    let rect = Rect(right - width, centerY - height / 2.0, width, height)
    paintBadge(ctx, tokens, rect, text, tone)
    rect
}

/** 画一个左端对齐到 `left`、垂直居中于 `centerY` 的徽章，返回药丸矩形。 */
func drawBadgeLeading(ctx: UiContext, tokens: ThemeTokens, text: String, tone: BadgeTone, left: Float32,
    centerY: Float32): Rect {
    let width = badgePillWidth(ctx, text)
    let height = badgePillHeight(ctx)
    let rect = Rect(left, centerY - height / 2.0, width, height)
    paintBadge(ctx, tokens, rect, text, tone)
    rect
}

func paintBadge(ctx: UiContext, tokens: ThemeTokens, rect: Rect, text: String, tone: BadgeTone): Unit {
    let skin = badgeSkin(tokens, tone)
    let radius = rect.h / 2.0
    fillRound(ctx, rect, radius, skin.fill)
    strokeRound(ctx, rect, radius, tokens.metrics.borderWidth, skin.border)
    let size = fpSize(ctx, 11.0)
    let metrics = ctx.fontMetrics(pointSize: size, style: weightStyle(550))
    ctx.text(text, rect.centerX() - advanceWidth(ctx, text, 11.0, 550) / 2.0,
        rect.centerY() - (metrics.ascent + metrics.descent) / 2.0, skin.ink, pointSize: size,
        style: weightStyle(550))
}

/* ------------------------------------------------------------------ */
/* 进度条（`.progress`，ui.css:301-358；sm 档轨道高 5）                  */
/* ------------------------------------------------------------------ */

/** 画 `.progress--sm` 轨道 + 填充；`value` 已 clamp 到 0..100。 */
func drawMeterSm(ctx: UiContext, tokens: ThemeTokens, rect: Rect, value: Float32, tone: ProgressTone): Unit {
    let c = tokens.color
    // .progress--sm { height: 5px } (ui.css:317-323)
    let height: Float32 = min(5.0, rect.h)
    let track = Rect(rect.x, rect.centerY() - height / 2.0, max(0.0, rect.w), height)
    let radius = height / 2.0
    fillRound(ctx, track, radius, c.surface2)
    strokeRound(ctx, track, radius, tokens.metrics.borderWidth, c.border)
    let innerWidth = max(0.0, track.w - tokens.metrics.borderWidth * 2.0)
    let fillWidth = innerWidth * clampF32(value, 0.0, 100.0) / 100.0
    if (fillWidth > 0.0) {
        let ink = match (tone) {
            case ProgressTone.Accent => c.accent
            case ProgressTone.Ok => c.ok
            case ProgressTone.Warn => c.warn
            case ProgressTone.Danger => c.danger
            case ProgressTone.Info => c.info
        }
        fillRound(ctx, Rect(track.x + tokens.metrics.borderWidth, track.y + tokens.metrics.borderWidth, fillWidth,
            max(0.0, height - tokens.metrics.borderWidth * 2.0)), max(0.0, radius - tokens.metrics.borderWidth), ink)
    }
}

/* ------------------------------------------------------------------ */
/* 卡片表面（`.dash-card`，dashboard.css:142-150）                      */
/* ------------------------------------------------------------------ */

/** `.dash-card`：surface + 1px border + `--radius-lg` + `--shadow-1`。 */
func paintCardSurface(ctx: UiContext, tokens: ThemeTokens, rect: Rect): Unit {
    shadow1(ctx, tokens, rect, tokens.radius.lg)
    fillRound(ctx, rect, tokens.radius.lg, tokens.color.surface)
    strokeRound(ctx, rect, tokens.radius.lg, tokens.metrics.borderWidth, tokens.color.border)
}

/** `.dash-onboarding`：`border-style: dashed; border-color: border-strong`（dashboard.css:511-516）。 */
func paintDashedCardSurface(ctx: UiContext, tokens: ThemeTokens, rect: Rect): Unit {
    shadow1(ctx, tokens, rect, tokens.radius.lg)
    fillRound(ctx, rect, tokens.radius.lg, tokens.color.surface)
    ctx.renderer.strokeRoundedRectDashed(rect, tokens.radius.lg,
        Pen(width: tokens.metrics.borderWidth, color: tokens.color.borderStrong), dash: 4.0, gap: 3.0)
}

/* ------------------------------------------------------------------ */
/* `.dash-card-head`（dashboard.css:152-159）                          */
/* ------------------------------------------------------------------ */

/** `padding: 16px 16px 12px` + 1px 底边框（dashboard.css:157-158）。 */
let CARD_HEAD_PAD_TOP: Float32 = 16.0
let CARD_HEAD_PAD_BOTTOM: Float32 = 12.0

/**
 * 卡片头部高度：内容 67.5（16 + 13.5 行盒 20.25 + 2 + 11.5 行盒 17.25 + 12）向下取整 + 1px 分隔线。
 *
 * 取整方向由参考图钉住：卡片上边框在 313、分隔线在 381 → 头部（含分隔线）恰好 68。
 * 浏览器把这条 1px 边框吸附到 381..382，用 ceil 会落到 382 而整体下移一行。
 */
func cardHeadHeight(ctx: UiContext): Float32 {
    let content = CARD_HEAD_PAD_TOP + lineBoxHeight(ctx, 13.5) + 2.0 + lineBoxHeight(ctx, 11.5) +
    CARD_HEAD_PAD_BOTTOM
    Float32(Int64(content)) + 1.0
}

/** 设备像素吸附（DPR=1）：四舍五入到整数逻辑像素，等价浏览器的绘制边吸附。 */
func snapToPixel(value: Float32): Float32 {
    Float32(Int64(value + 0.5))
}

/**
 * 画卡片头部左半部分（图标 + 标题 + 副标题）与底部 1px 分隔线。
 * `rect` 是卡片内容盒（`.dash-card` 的 1px 边框由 `cardShell` 的 padding 表达）。
 * 调用方随后自行补画右半部分（计数 / 链接），返回列表内容的起始 y。
 */
func paintCardHead(ctx: UiContext, tokens: ThemeTokens, rect: Rect, glyph: IconGlyph, title: String,
    sub: String): Float32 {
    let pad = tokens.space.s4
    let contentTop = rect.y + CARD_HEAD_PAD_TOP
    let titleBox = lineBoxHeight(ctx, 13.5)
    // `.dash-card-title { display:flex; align-items:center; gap: 8px }`（dashboard.css:161-168）
    let iconSide: Float32 = 15.0
    let iconRect = Rect(rect.x + pad, contentTop + titleBox / 2.0 - iconSide / 2.0, iconSide, iconSide)
    paintSpec(ctx, glyph, iconRect, tokens.color.textFaint)
    let titleX = rect.x + pad + iconSide + tokens.space.s2
    drawLine(ctx, title, titleX, contentTop, titleBox, 13.5, 650, tokens.color.text)
    let subTop = contentTop + titleBox + 2.0
    drawLine(ctx, sub, rect.x + pad, subTop, lineBoxHeight(ctx, 11.5), 11.5, 400, tokens.color.textFaint)
    // `border-bottom: 1px solid var(--border)`（dashboard.css:158）
    let lineY = rect.y + cardHeadHeight(ctx) - 1.0
    ctx.renderer.fill(Rect(rect.x, lineY, max(0.0, rect.w), tokens.metrics.borderWidth), tokens.color.border)
    rect.y + cardHeadHeight(ctx)
}

/** `.dash-link`（dashboard.css:187-197）：12px、accent 色、`padding: 2px 4px`。 */
func drawCardLink(ctx: UiContext, tokens: ThemeTokens, rect: Rect, text: String, hovered: Bool): Unit {
    // `padding: 2px 4px` → 文字从盒子左内边距开始（dashboard.css:187-193）
    let textX = rect.x + 4.0
    drawLine(ctx, text, textX, rect.y, rect.h, 12.0, 400, tokens.color.accent)
    if (hovered) {
        // `.dash-link:hover { text-decoration: underline }`：CUI 无下划线，改画 1px 下划线。
        let width = advanceWidth(ctx, text, 12.0, 400)
        let metrics = ctx.fontMetrics(pointSize: fpSize(ctx, 12.0), style: weightStyle(400))
        let underlineY = baselineWithin(ctx, rect.y, rect.h, 12.0, 400) + max(metrics.descent * 0.35, 1.0)
        ctx.renderer.fill(Rect(textX, underlineY, width, 1.0), tokens.color.accent)
    }
}

/** `.dash-link` 的盒子：12px 行盒 + `padding: 2px 4px`。 */
func cardLinkSize(ctx: UiContext, text: String): Size {
    Size(advanceWidth(ctx, text, 12.0, 400) + 8.0, lineBoxHeight(ctx, 12.0) + 4.0)
}

/** `.dash-card-count`（dashboard.css:180-185）：11.5px、`text-faint`。 */
func drawCardCount(ctx: UiContext, tokens: ThemeTokens, rect: Rect, text: String): Unit {
    drawLineTrailing(ctx, text, rect.right(), rect.y, rect.h, 11.5, 400, tokens.color.textFaint)
}
