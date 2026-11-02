package textura.ui

import cui.*

/*
 * Painting helpers shared by every ported control.
 *
 * CUI exposes the primitives (fill / fillRoundedRect / strokeRoundedRect / strokeLine /
 * fillCircle + TextRenderer) but no box-shadow and no CSS `outline`; the helpers below
 * reproduce the three CSS idioms the Web kit relies on, each mapped to the CSS rule that
 * produced it:
 *
 *   --focus-ring / :focus-visible   -> `focusRing()`      (2px accent band, 2px offset)
 *   .input:focus box-shadow         -> `softFocusRing()`  (3px accent-soft band, flush)
 *   --shadow-1 / --shadow-2         -> `softShadow()`     (feathered rounded halo)
 *   color-mix(in srgb, C p%, ...)   -> `tint()`           (same colour at p% alpha)
 */

/** Resolves an `fp` size (CSS px at font scale 1) to logical pixels. */
public func fpSize(ctx: UiContext, cssPixels: Float32): Float32 {
    max(1.0, ctx.resolve(Length(cssPixels, LengthUnit.Fp)))
}

/** Token pixels (already resolved) as a CUI length in `vp`. */
public func vp(value: Float32): Length {
    Length(value, LengthUnit.Vp)
}

/** A CSS px size as a CUI length in `fp`. */
public func fp(value: Float32): Length {
    Length(value, LengthUnit.Fp)
}

/** CSS numeric font weight -> CUI `FontWeight`. Values outside 1..1000 are clamped. */
public func cssWeight(value: Int64): FontWeight {
    FontWeight(min(max(value, 1), 1000))
}

/**
 * `color-mix(in srgb, color p%, transparent)`: mixing with `transparent` in sRGB keeps the
 * colour and scales the alpha, which compositing reproduces exactly.
 */
public func tint(color: Color, percent: Float32): Color {
    color.withAlpha(Int64(clampF32(percent, 0.0, 100.0) * 2.55))
}

/** Multiplies a colour's alpha — used for `button:disabled { opacity: .55 }` (base.css:73). */
public func withOpacity(color: Color, opacity: Float32): Color {
    color.withAlpha(Int64(clampF32(Float32(Int64(color.a)) * opacity, 0.0, 255.0)))
}

/** Solid rounded fill (`background:` + `border-radius:`). */
public func fillRound(ctx: UiContext, rect: Rect, radius: Float32, color: Color): Unit {
    if (rect.w <= 0.0 || rect.h <= 0.0 || color.a == 0) {
        return
    }
    ctx.renderer.fillRoundedRect(rect, max(0.0, radius), color)
}

/** Solid square fill. */
public func fillRect(ctx: UiContext, rect: Rect, color: Color): Unit {
    if (rect.w <= 0.0 || rect.h <= 0.0 || color.a == 0) {
        return
    }
    ctx.renderer.fill(rect, color)
}

/**
 * `border: 1px solid ...` with `border-radius`. The CSS border is painted inside the border
 * box, so the stroke centre sits half a pixel inside the frame.
 */
public func strokeRound(ctx: UiContext, rect: Rect, radius: Float32, width: Float32, color: Color): Unit {
    if (rect.w <= 0.0 || rect.h <= 0.0 || color.a == 0 || width <= 0.0) {
        return
    }
    ctx.renderer.strokeRoundedRect(rect, max(0.0, radius), Pen(width: width, color: color))
}

/**
 * `--focus-ring` / `:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px }`
 * (tokens.css:60, base.css:92). The two CSS box-shadow layers leave a 2px `--surface` gap and
 * then a 2px accent band; only the accent band paints over the page background, so drawing a
 * 2px stroke centred 3px outside the frame reproduces it.
 */
public func focusRing(ctx: UiContext, tokens: ThemeTokens, rect: Rect, radius: Float32): Unit {
    let gap = tokens.metrics.focusRingGap
    let width = tokens.metrics.focusRingWidth
    let outset = gap + width / 2.0
    ctx.renderer.strokeRoundedRect(
        rect.inset(-outset),
        radius + outset,
        Pen(width: width, color: tokens.color.accent)
    )
}

/**
 * `.input:focus { border-color: accent; box-shadow: 0 0 0 3px var(--accent-soft) }`
 * (ui.css:201-205): a flush 3px band starting at the border box.
 */
public func softFocusRing(ctx: UiContext, tokens: ThemeTokens, rect: Rect, radius: Float32): Unit {
    let width: Float32 = 3.0
    ctx.renderer.strokeRoundedRect(
        rect.inset(-width / 2.0),
        radius + width / 2.0,
        Pen(width: width, color: tokens.color.accentSoft)
    )
}

/**
 * One CSS box-shadow layer, drawn as a feathered rounded halo. `blur` becomes the feather
 * width and half of it the outset, which is the usual Gaussian-to-feather approximation.
 */
public func softShadow(ctx: UiContext, rect: Rect, radius: Float32, shadow: TokenShadow): Unit {
    if (shadow.color.a == 0 || rect.w <= 0.0 || rect.h <= 0.0) {
        return
    }
    let feather = max(shadow.blur, 1.0)
    let outset = shadow.blur / 2.0 + shadow.spread
    let base = rect.shift(shadow.offsetX, shadow.offsetY).inset(-outset)
    ctx.renderer.fillRoundedRectSoft(base, radius + outset, shadow.color, feather: feather)
}

/** `--shadow-1`: the drop layer plus the 0 1px 0 contact line (tokens.css:44). */
public func shadow1(ctx: UiContext, tokens: ThemeTokens, rect: Rect, radius: Float32): Unit {
    softShadow(ctx, rect, radius, tokens.shadow1)
    softShadow(ctx, rect, radius, tokens.shadow1Contact)
}

/** Available width for text after horizontal padding. */
public func innerWidth(rect: Rect, horizontalPadding: Float32): Float32 {
    max(0.0, rect.w - horizontalPadding * 2.0)
}

/** Advance width of `text` at `sizePx` with the given CSS weight. */
public func textWidth(ctx: UiContext, text: String, sizePx: Float32, weight: Int64): Float32 {
    ctx.textWidth(text, pointSize: sizePx, style: FontStyle(weight: cssWeight(weight)))
}

/** Ink height of a single line — used for vertical centring. */
public func textInkHeight(ctx: UiContext, sizePx: Float32, weight: Int64): Float32 {
    ctx.textHeight(pointSize: sizePx, style: FontStyle(weight: cssWeight(weight)))
}

/** Draws `text` optically centred inside `rect` (single line). */
public func textCentered(
    ctx: UiContext,
    text: String,
    rect: Rect,
    color: Color,
    sizePx: Float32,
    weight: Int64,
    family!: ?String = None
): Unit {
    if (text.isEmpty()) {
        return
    }
    ctx.textCenter(text, rect, color, pointSize: sizePx, style: FontStyle(weight: cssWeight(weight)), font: family)
}

/** Draws `text` left-aligned at `x`, vertically centred on `centerY`. */
public func textLeading(
    ctx: UiContext,
    text: String,
    x: Float32,
    centerY: Float32,
    color: Color,
    sizePx: Float32,
    weight: Int64,
    family!: ?String = None
): Unit {
    if (text.isEmpty()) {
        return
    }
    let h = textInkHeight(ctx, sizePx, weight)
    ctx.text(text, x, centerY - h / 2.0, color, pointSize: sizePx, style: FontStyle(weight: cssWeight(weight)),
        font: family)
}

/** Draws `text` right-aligned so it ends at `right`, vertically centred on `centerY`. */
public func textTrailing(
    ctx: UiContext,
    text: String,
    right: Float32,
    centerY: Float32,
    color: Color,
    sizePx: Float32,
    weight: Int64,
    family!: ?String = None
): Unit {
    if (text.isEmpty()) {
        return
    }
    let w = textWidth(ctx, text, sizePx, weight)
    textLeading(ctx, text, right - w, centerY, color, sizePx, weight, family: family)
}
