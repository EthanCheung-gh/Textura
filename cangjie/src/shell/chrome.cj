package textura.shell

import cui.*
import textura.ui.*

/*
 * Shell chrome geometry, straight from `src/styles/shell.css` / `tokens.css`.
 * Every number in this file cites the CSS rule it reproduces; the shell draws the chrome
 * itself (instead of stacking Labels) so the 1:1 geometry of the Web layout survives.
 */

/** `.shell { grid-template-columns: var(--sidebar-width) minmax(0, 1fr) }` (shell.css:2-8). */
public let SIDEBAR_WIDTH: Float32 = 240.0
/** `.topbar { height: var(--topbar-height) }` (shell.css:210-219). */
public let TOPBAR_HEIGHT: Float32 = 56.0
/** `border: 1px` everywhere (base.css / ui.css); tokens expose it as `metrics.borderWidth`. */
public let CHROME_BORDER: Float32 = 1.0
/** `.sidebar-scroll { padding: var(--space-4) var(--space-3) }` (shell.css:58-66). */
public let SIDEBAR_SCROLL_PAD_Y: Float32 = 16.0
public let SIDEBAR_SCROLL_PAD_X: Float32 = 12.0
/** `.sidebar-scroll { gap: var(--space-5) }` (shell.css:58-66). */
public let SIDEBAR_SCROLL_GAP: Float32 = 24.0
/** `.sidebar-link { padding: 7px var(--space-2); font-size: 13.5px }` (shell.css:83-94). */
public let NAV_ROW_PAD_Y: Float32 = 7.0
public let NAV_ROW_PAD_X: Float32 = 8.0
public let NAV_ROW_FONT: Float32 = 13.5
/** `.sidebar-nav { gap: 2px }` (shell.css:77-81). */
public let NAV_ROW_GAP: Float32 = 2.0
/** `.sidebar-area { padding: 6px var(--space-2); font-size: 13px }` (shell.css:139-147). */
public let AREA_ROW_PAD_Y: Float32 = 6.0
public let AREA_ROW_PAD_X: Float32 = 8.0
public let AREA_ROW_FONT: Float32 = 13.0
/** `.sidebar-areas { gap: 2px }` (shell.css:133-137). */
public let AREA_ROW_GAP: Float32 = 2.0
/** `.sidebar-section-title { font-size: 11px; 600; padding: 0 8px 8px }` (shell.css:68-75). */
public let SECTION_TITLE_FONT: Float32 = 11.0
public let SECTION_TITLE_PAD_BOTTOM: Float32 = 8.0
/** `.sidebar-footer { padding: 12px 16px; gap: 8px }` (shell.css:170-177). */
public let FOOTER_PAD_X: Float32 = 16.0
public let FOOTER_PAD_Y: Float32 = 12.0
public let FOOTER_GAP: Float32 = 8.0
/** `.storage-status { font-size: 11.5px }` (shell.css:179-185). */
public let STATUS_FONT: Float32 = 11.5
/** `.topbar { padding: 0 var(--space-5); gap: var(--space-4) }` (shell.css:210-219). */
public let TOPBAR_PAD_X: Float32 = 24.0
public let TOPBAR_GAP: Float32 = 16.0
/** `.topbar-title { font-size: 16px; font-weight: 650 }` (shell.css:228-233). */
public let TOPBAR_TITLE_FONT: Float32 = 16.0
/** `.topbar-subtitle { font-size: 12px }` (shell.css:235-239). */
public let TOPBAR_SUBTITLE_FONT: Float32 = 12.0
/** `.topbar-titles { gap: var(--space-3) }` (shell.css:221-226). */
public let TOPBAR_TITLES_GAP: Float32 = 12.0
/** `TopBar.tsx` inline `flex: 0 1 320px; minWidth: 180`. */
public let TOPBAR_SEARCH_WIDTH: Float32 = 320.0
/** `.topbar-actions { gap: var(--space-2) }` (shell.css:249-253). */
public let TOPBAR_ACTIONS_GAP: Float32 = 8.0
/** `.shell-content { padding: var(--space-5) }` (shell.css:255-260). */
public let CONTENT_PAD: Float32 = 24.0
/** `.page { max-width: 1280px }` (shell.css:262-268). */
public let PAGE_MAX_WIDTH: Float32 = 1280.0
/** `.notices { right: var(--space-5); bottom: var(--space-5); gap: var(--space-2) }` (shell.css:312-321). */
public let NOTICE_INSET: Float32 = 24.0
public let NOTICE_GAP: Float32 = 8.0
public let NOTICE_MIN_WIDTH: Float32 = 220.0
public let NOTICE_MAX_WIDTH: Float32 = 360.0
public let NOTICE_PAD_X: Float32 = 16.0
public let NOTICE_PAD_Y: Float32 = 12.0
public let NOTICE_FONT: Float32 = 13.0
public let NOTICE_TONE_WIDTH: Float32 = 3.0

/** CSS `line-height: 1.5` on `body` (base.css:14-25). */
public func lineBox(fontSize: Float32): Float32 {
    fontSize * 1.5
}

/** `html[data-theme="dark"]` -> dark tokens; anything else stays on the warm paper theme. */
public func themeByName(name: String): Theme {
    if (name == "dark") {
        texturaDark()
    } else {
        texturaLight()
    }
}

/** `1px solid var(--border)` as an integer-aligned hairline. */
public func paintRule(ctx: UiContext, x: Float32, y: Float32, width: Float32, color: Color): Unit {
    if (width <= 0.0) {
        return
    }
    ctx.renderer.fill(Rect(x, y, width, CHROME_BORDER), color)
}

/** Rounded fill + 1px stroke, the two CSS declarations most chrome boxes use together. */
public func paintBox(ctx: UiContext, rect: Rect, radius: Float32, fill: Color, border: Color): Unit {
    fillRound(ctx, rect, radius, fill)
    strokeRound(ctx, rect, radius, CHROME_BORDER, border)
}

/** `#RRGGBB` (domain `Area.color`) -> `Color`; unparsable input falls back to the accent. */
public func hexColor(value: String, fallback: Color): Color {
    let text = value.trimAscii()
    if (text.size != 7 || !text.startsWith("#")) {
        return fallback
    }
    let digits = "0123456789abcdef"
    match (hexPair(text, 1, digits)) {
        case Some(red) =>
            match (hexPair(text, 3, digits)) {
                case Some(green) =>
                    match (hexPair(text, 5, digits)) {
                        case Some(blue) => return Color.rgb(red, green, blue)
                        case None => return fallback
                    }
                case None => return fallback
            }
        case None => return fallback
    }
}

func hexPair(text: String, start: Int64, digits: String): ?Int64 {
    match (hexDigit(text[start], digits)) {
        case Some(high) =>
            match (hexDigit(text[start + 1], digits)) {
                case Some(low) => return Some(high * 16 + low)
                case None => return None
            }
        case None => return None
    }
}

func hexDigit(value: UInt8, digits: String): ?Int64 {
    var index = 0
    let lower = if (value >= UInt8(65) && value <= UInt8(90)) {
        value + UInt8(32)
    } else {
        value
    }
    while (index < 16) {
        if (digits[index] == lower) {
            return Some(Int64(index))
        }
        index += 1
    }
    None
}

/**
 * CSS `letter-spacing` + a single line of text. CUI has no tracking API, so each rune is
 * placed by hand; `extra` is `letter-spacing * fontSize` in logical pixels.
 */
public func textTracked(
    ctx: UiContext,
    text: String,
    x: Float32,
    centerY: Float32,
    color: Color,
    sizePx: Float32,
    weight: Int64,
    extra: Float32
): Unit {
    if (text.isEmpty()) {
        return
    }
    if (extra <= 0.0) {
        textLeading(ctx, text, x, centerY, color, sizePx, weight)
        return
    }
    var cursor = x
    for (rune in text.toRuneArray()) {
        let piece = String([rune])
        textLeading(ctx, piece, cursor, centerY, color, sizePx, weight)
        cursor += textWidth(ctx, piece, sizePx, weight) + extra
    }
}

/** Advance width of a tracked run, used to centre/reflow the brand block. */
public func trackedWidth(ctx: UiContext, text: String, sizePx: Float32, weight: Int64, extra: Float32): Float32 {
    if (extra <= 0.0) {
        return textWidth(ctx, text, sizePx, weight)
    }
    var width: Float32 = 0.0
    let runes = text.toRuneArray()
    var index = 0
    while (index < runes.size) {
        width += textWidth(ctx, String([runes[index]]), sizePx, weight)
        if (index + 1 < runes.size) {
            width += extra
        }
        index += 1
    }
    width
}
