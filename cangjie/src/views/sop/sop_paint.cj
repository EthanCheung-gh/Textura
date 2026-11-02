package textura.views.sop

import std.collection.*
import std.math.{floor}
import std.deriving.*
import cui.*
import textura.core.data.*
import textura.ui.*

/*
 * Small painting primitives shared by the four SOP regions.
 *
 * The page is drawn by custom widgets (one per region) so that every box matches
 * `sop.css` exactly: CUI stacks cannot express the CSS grid/flex mix used by the
 * SOP page, and the canvas needs absolute positioning anyway. Text, badges,
 * rounded boxes and icons reuse the `textura.ui` primitives so the palette and
 * type scale stay byte-identical with the ported control kit.
 */

/** Badge / badge-like pill tones (`Badge.tsx` -> `BadgeTone`). */
enum SopTone {
    | Neutral
    | Accent
    | Ok
    | Danger
    | Warn
    | Info
}

/** `.badge--<tone>` background (`color-mix(C p%, transparent)` -> `tint`). */
func toneBackground(tk: ThemeTokens, tone: SopTone): Color {
    let c = tk.color
    match (tone) {
        case SopTone.Neutral => return c.surface2
        case SopTone.Accent => return c.accentSoft
        case SopTone.Ok => return tint(c.ok, 12.0)
        case SopTone.Danger => return tint(c.danger, 12.0)
        case SopTone.Warn => return tint(c.warn, 14.0)
        case SopTone.Info => return tint(c.info, 12.0)
    }
}

func toneBorder(tk: ThemeTokens, tone: SopTone): Color {
    let c = tk.color
    match (tone) {
        case SopTone.Neutral => return c.border
        case SopTone.Accent => return tint(c.accent, 28.0)
        case SopTone.Ok => return tint(c.ok, 30.0)
        case SopTone.Danger => return tint(c.danger, 30.0)
        case SopTone.Warn => return tint(c.warn, 32.0)
        case SopTone.Info => return tint(c.info, 30.0)
    }
}

func toneText(tk: ThemeTokens, tone: SopTone): Color {
    let c = tk.color
    match (tone) {
        case SopTone.Neutral => return c.textMuted
        case SopTone.Accent => return c.accentInk
        case SopTone.Ok => return c.okInk
        case SopTone.Danger => return c.dangerInk
        case SopTone.Warn => return c.warnInk
        case SopTone.Info => return c.infoInk
    }
}

/** Pixel snapping for box edges: browser border boxes land on whole pixels (1px rules stay crisp). */
func snapPx(value: Float32): Float32 {
    Float32(Int64(floor(Float64(value) + 0.5)))
}

/** Advance width of `text` at `size`/`weight` (CSS px at font scale 1). */
func measureText(ctx: UiContext, text: String, size: Float32, weight: Int64): Float32 {
    textWidth(ctx, text, size, weight)
}

/**
 * Truncates `text` with an ellipsis so it fits `maxWidth` — the manual equivalent of
 * `text-overflow: ellipsis; white-space: nowrap` used by every SOP title.
 */
func ellipsize(ctx: UiContext, text: String, maxWidth: Float32, size: Float32, weight: Int64): String {
    if (text.isEmpty() || maxWidth <= 0.0) {
        return ""
    }
    if (measureText(ctx, text, size, weight) <= maxWidth) {
        return text
    }
    let ellipsis = "…"
    let ellipsisWidth = measureText(ctx, ellipsis, size, weight)
    let runes = text.toRuneArray()
    var count = runes.size
    while (count > 0) {
        count -= 1
        var candidate = ""
        for (index in 0..count) {
            candidate += runes[index].toString()
        }
        candidate += ellipsis
        if (measureText(ctx, candidate, size, weight) <= maxWidth) {
            return candidate
        }
    }
    let _ = ellipsisWidth
    return ellipsis
}

/** Left-aligned single line, vertically centred on `centerY` (CSS line-box centring). */
func paintText(
    ctx: UiContext,
    text: String,
    x: Float32,
    centerY: Float32,
    size: Float32,
    weight: Int64,
    color: Color
): Unit {
    textLeading(ctx, text, x, centerY, color, size, weight)
}

/** Right-aligned single line ending at `right`. */
func paintTextRight(
    ctx: UiContext,
    text: String,
    right: Float32,
    centerY: Float32,
    size: Float32,
    weight: Int64,
    color: Color
): Unit {
    textTrailing(ctx, text, right, centerY, color, size, weight)
}

/** Horizontally centred single line inside `rect`, vertically centred on `centerY`. */
func paintTextMid(
    ctx: UiContext,
    text: String,
    left: Float32,
    right: Float32,
    centerY: Float32,
    size: Float32,
    weight: Int64,
    color: Color
): Unit {
    if (text.isEmpty()) {
        return
    }
    let width = measureText(ctx, text, size, weight)
    textLeading(ctx, text, (left + right) / 2.0 - width / 2.0, centerY, color, size, weight)
}

/** Truncated left-aligned line constrained to `maxWidth`. */
func paintTextClipped(
    ctx: UiContext,
    text: String,
    x: Float32,
    centerY: Float32,
    maxWidth: Float32,
    size: Float32,
    weight: Int64,
    color: Color
): Unit {
    paintText(ctx, ellipsize(ctx, text, maxWidth, size, weight), x, centerY, size, weight, color)
}

/** Width of a badge with `text` (`padding: 2px 7px` + 1px border on each side). */
func badgeWidth(ctx: UiContext, text: String, font: Float32, padX: Float32, weight: Int64): Float32 {
    measureText(ctx, text, font, weight) + padX * 2.0 + 2.0
}

/** Paints a pill badge with its left edge at `x`, vertically centred on `centerY`. */
func paintBadge(
    ctx: UiContext,
    tk: ThemeTokens,
    text: String,
    x: Float32,
    centerY: Float32,
    tone: SopTone,
    font!: Float32 = SOP_BADGE_FONT,
    padX!: Float32 = SOP_BADGE_PAD_X,
    height!: Float32 = SOP_BADGE_H,
    dot!: Bool = false
): Float32 {
    let weight: Int64 = 550
    let dotSpace: Float32 = if (dot) {
        10.0
    } else {
        0.0
    }
    let width = badgeWidth(ctx, text, font, padX, weight) + dotSpace
    let rect = Rect(x, centerY - height / 2.0, width, height)
    fillRound(ctx, rect, height / 2.0, toneBackground(tk, tone))
    strokeRound(ctx, rect, height / 2.0, 1.0, toneBorder(tk, tone))
    let color = toneText(tk, tone)
    if (dot) {
        ctx.renderer.fillCircle(x + padX + 2.5, centerY, 2.5, color)
    }
    paintText(ctx, text, x + padX + dotSpace, centerY, font, weight, color)
    width
}

/** `1px solid` rounded box: `background` + `border` in one call pair. */
func paintBox(ctx: UiContext, rect: Rect, radius: Float32, fill: Color, border: Color, borderWidth!: Float32 = 1.0): Unit {
    fillRound(ctx, rect, radius, fill)
    strokeRound(ctx, rect, radius, borderWidth, border)
}

/** Vertical hairline (`border-left` / `border-top` of a 1px rule). */
func paintHLine(ctx: UiContext, x0: Float32, x1: Float32, y: Float32, color: Color): Unit {
    ctx.renderer.fill(Rect(x0, y, x1 - x0, 1.0), color)
}

func paintVLine(ctx: UiContext, y0: Float32, y1: Float32, x: Float32, color: Color): Unit {
    ctx.renderer.fill(Rect(x, y0, 1.0, y1 - y0), color)
}

/** `--shadow-1` under a rounded surface (`softShadow` feathering, ui/paint.cj). */
func paintShadow1(ctx: UiContext, tk: ThemeTokens, rect: Rect, radius: Float32): Unit {
    shadow1(ctx, tk, rect, radius)
}

/** `.btn--ghost` text button (ui.css:71) with an optional leading glyph. */
func paintGhostButton(
    ctx: UiContext,
    tk: ThemeTokens,
    label: String,
    rect: Rect,
    glyph!: ?IconGlyph = None,
    glyphSide!: Float32 = 13.0,
    color!: ?Color = None,
    enabled!: Bool = true
): Unit {
    let textColor = match (color) {
        case Some(value) => value
        case None => withOpacity(tk.color.textMuted, if (enabled) {
            1.0
        } else {
            0.55
        })
    }
    var cursor = rect.x
    if (rect.w > 0.0 && rect.h > 0.0) {
        let inner = contentWidth(ctx, label, glyph, glyphSide, SOP_BTN_SM_FONT)
        cursor = rect.x + max(0.0, (rect.w - inner) / 2.0)
    }
    cursor = paintButtonContent(ctx, label, glyph, glyphSide, cursor, rect, textColor)
    let _ = cursor
}

/** `.btn` content width: glyph + 8px gap + label (ui.css:5-33). */
func contentWidth(ctx: UiContext, label: String, glyph: ?IconGlyph, glyphSide: Float32, font: Float32): Float32 {
    var width = measureText(ctx, label, font, 550)
    match (glyph) {
        case Some(_) => width += glyphSide + 8.0
        case None => ()
    }
    width
}

/** Draws glyph + label starting at `x` and returns the cursor after the label. */
func paintButtonContent(
    ctx: UiContext,
    label: String,
    glyph: ?IconGlyph,
    glyphSide: Float32,
    x: Float32,
    rect: Rect,
    color: Color
): Float32 {
    var cursor = x
    let centerY = rect.y + rect.h / 2.0
    match (glyph) {
        case Some(value) =>
            paintSpec(ctx, value, Rect(cursor, centerY - glyphSide / 2.0, glyphSide, glyphSide), color)
            cursor += glyphSide + 8.0
        case None => ()
    }
    paintText(ctx, label, cursor, centerY, SOP_BTN_SM_FONT, 550, color)
    cursor + measureText(ctx, label, SOP_BTN_SM_FONT, 550)
}

/** `.btn--secondary` (ui.css:59): surface fill, 1px border, radius 8, shadow-1. */
func paintSecondaryButton(
    ctx: UiContext,
    tk: ThemeTokens,
    label: String,
    rect: Rect,
    glyph!: ?IconGlyph = None,
    glyphSide!: Float32 = 13.0,
    enabled!: Bool = true
): Unit {
    paintShadow1(ctx, tk, rect, SOP_RADIUS_CTRL)
    paintBox(ctx, rect, SOP_RADIUS_CTRL, tk.color.surface, tk.color.border)
    let color = withOpacity(tk.color.text, if (enabled) {
        1.0
    } else {
        0.55
    })
    let inner = contentWidth(ctx, label, glyph, glyphSide, SOP_BTN_SM_FONT)
    let cursor = rect.x + max(0.0, (rect.w - inner) / 2.0)
    let _ = paintButtonContent(ctx, label, glyph, glyphSide, cursor, rect, color)
}

/** `.btn--primary` (ui.css:35): accent-strong fill, `--text-on-strong` label. */
func paintPrimaryButton(
    ctx: UiContext,
    tk: ThemeTokens,
    label: String,
    rect: Rect,
    glyph!: ?IconGlyph = None,
    glyphSide!: Float32 = 13.0,
    enabled!: Bool = true
): Unit {
    let fill = if (enabled) {
        tk.color.accentStrong
    } else {
        tk.color.accentStrongDisabled
    }
    paintShadow1(ctx, tk, rect, SOP_RADIUS_CTRL)
    paintBox(ctx, rect, SOP_RADIUS_CTRL, fill, fill)
    let inner = contentWidth(ctx, label, glyph, glyphSide, SOP_BTN_SM_FONT)
    let cursor = rect.x + max(0.0, (rect.w - inner) / 2.0)
    let _ = paintButtonContent(ctx, label, glyph, glyphSide, cursor, rect, tk.color.textOnStrong)
}

/** `.btn--danger` (ui.css:82): danger-strong fill, no shadow. */
func paintDangerButton(
    ctx: UiContext,
    tk: ThemeTokens,
    label: String,
    rect: Rect,
    glyph!: ?IconGlyph = None,
    glyphSide!: Float32 = 13.0,
    enabled!: Bool = true
): Unit {
    let fill = if (enabled) {
        tk.color.dangerStrong
    } else {
        tk.color.dangerStrongDisabled
    }
    paintBox(ctx, rect, SOP_RADIUS_CTRL, fill, fill)
    let inner = contentWidth(ctx, label, glyph, glyphSide, SOP_BTN_SM_FONT)
    let cursor = rect.x + max(0.0, (rect.w - inner) / 2.0)
    let _ = paintButtonContent(ctx, label, glyph, glyphSide, cursor, rect, tk.color.textOnStrong)
}

/** `.icon-btn--sm` 26x26 ghost square (`ui.css:116-158`). */
func paintIconButton(
    ctx: UiContext,
    tk: ThemeTokens,
    glyph: IconGlyph,
    rect: Rect,
    tone!: SopTone = SopTone.Neutral,
    enabled!: Bool = true
): Unit {
    let color = match (tone) {
        case SopTone.Danger => withOpacity(tk.color.danger, if (enabled) {
            1.0
        } else {
            0.55
        })
        case _ => withOpacity(tk.color.textMuted, if (enabled) {
            1.0
        } else {
            0.55
        })
    }
    let side: Float32 = 15.0
    paintSpec(ctx, glyph, Rect(rect.x + (rect.w - side) / 2.0, rect.y + (rect.h - side) / 2.0, side, side), color)
}

/** `.icon-btn--sm` width/height (`ControlSize.Sm`). */
func iconSmRect(x: Float32, centerY: Float32): Rect {
    Rect(x, centerY - SOP_ICON_SM / 2.0, SOP_ICON_SM, SOP_ICON_SM)
}

/**
 * `.input` box (ui.css:181): 1px border, radius 8, surface fill, 13.5px text,
 * `padding: 7px 10px`.
 *
 * `editing` 为真时只留背景：这个字段正被原位编辑器（真 `TextField`）压着，控件会自己画
 * 文字与焦点边框；画布再画一遍就是「两层文字 + 双边框」。
 */
func paintInputBox(ctx: UiContext, tk: ThemeTokens, rect: Rect, value: String, placeholder: String,
    editing!: Bool = false): Unit {
    if (editing) {
        fillRound(ctx, rect, SOP_RADIUS_CTRL, tk.color.surface)
        return
    }
    paintBox(ctx, rect, SOP_RADIUS_CTRL, tk.color.surface, tk.color.border)
    let text = if (value.isEmpty()) {
        placeholder
    } else {
        value
    }
    let color = if (value.isEmpty()) {
        tk.color.textFaint
    } else {
        tk.color.text
    }
    paintTextClipped(ctx, text, rect.x + SOP_INPUT_PAD_X, rect.y + rect.h / 2.0, rect.w - SOP_INPUT_PAD_X * 2.0,
        SOP_INPUT_FONT, 400, color)
}

/** `.textarea` box: same surface, `min-height: 76px`, wrapped text at line-height 1.55. */
func paintTextAreaBox(ctx: UiContext, tk: ThemeTokens, rect: Rect, value: String, placeholder: String,
    editing!: Bool = false): Unit {
    if (editing) {
        // 原位编辑器接管：只留背景（见 `paintInputBox`），拖拽把手也归控件自己。
        fillRound(ctx, rect, SOP_RADIUS_CTRL, tk.color.surface)
        return
    }
    paintBox(ctx, rect, SOP_RADIUS_CTRL, tk.color.surface, tk.color.border)
    let text = if (value.isEmpty()) {
        placeholder
    } else {
        value
    }
    let color = if (value.isEmpty()) {
        tk.color.textFaint
    } else {
        tk.color.text
    }
    let lineHeight: Float32 = 20.9 // 13.5px * line-height 1.55
    var lineIndex = 0
    let contentWidthLimit = rect.w - SOP_INPUT_PAD_X * 2.0
    for (line in wrapText(ctx, text, contentWidthLimit, SOP_INPUT_FONT, 400)) {
        let centerY = rect.y + 7.0 + lineHeight * Float32(lineIndex) + lineHeight / 2.0
        paintText(ctx, line, rect.x + SOP_INPUT_PAD_X, centerY, SOP_INPUT_FONT, 400, color)
        lineIndex += 1
    }
    // `.textarea` resize grip (bottom-right corner, chrome detail of the browser control).
    let grip = tk.color.borderStrong
    ctx.renderer.strokeLine(rect.right() - 11.0, rect.bottom() - 5.0, rect.right() - 5.0, rect.bottom() - 11.0,
        Pen(width: 1.0, color: grip))
    ctx.renderer.strokeLine(rect.right() - 7.0, rect.bottom() - 5.0, rect.right() - 5.0, rect.bottom() - 7.0,
        Pen(width: 1.0, color: grip))
}

/** Greedy line breaking for CJK / latin mixed text (approximates the browser's text wrap). */
func wrapText(ctx: UiContext, text: String, maxWidth: Float32, size: Float32, weight: Int64): Array<String> {
    let lines = ArrayList<String>()
    if (text.isEmpty() || maxWidth <= 0.0) {
        return lines.toArray()
    }
    var current = ""
    for (rune in text.toRuneArray()) {
        let piece = rune.toString()
        let candidate = current + piece
        if (!current.isEmpty() && measureText(ctx, candidate, size, weight) > maxWidth) {
            lines.add(current)
            current = piece
        } else {
            current = candidate
        }
    }
    if (!current.isEmpty()) {
        lines.add(current)
    }
    lines.toArray()
}

/** `.progress--sm`: 1px border track + 5px fill bar (ui.css:301-358). */
func paintProgress(ctx: UiContext, tk: ThemeTokens, rect: Rect, percent: Float32, color: Color): Unit {
    fillRound(ctx, rect, rect.h / 2.0, tk.color.surface2)
    strokeRound(ctx, rect, rect.h / 2.0, 1.0, tk.color.border)
    let clamped = clampF32(percent, 0.0, 100.0)
    let inner = rect.w - 2.0
    let fillWidth = inner * clamped / 100.0
    if (fillWidth > 0.5) {
        fillRound(ctx, Rect(rect.x + 1.0, rect.y + 1.0, fillWidth, rect.h - 2.0), (rect.h - 2.0) / 2.0, color)
    }
}
