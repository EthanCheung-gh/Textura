package textura.views.settings

import std.collection.*
import cui.*
import textura.ui.*

/*
 * Local text primitives for `textura.views.settings`.
 *
 * Why not plain `Label`: the settings page is a dense text page whose vertical
 * rhythm comes from CSS `line-height` (1.5 / 1.55 / 1.6 / 1.65 / 1.7) and from
 * flex `align-items: baseline` rows. `Label` uses the font's natural line height
 * and has no line-height modifier, so a 2-line note would be ~7px shorter than the
 * reference and every card below it would drift.
 *
 * `Paragraph` therefore wraps + draws text itself with explicit CSS half-leading:
 *
 *   line box top      = frame.y + i * (font-size * line-height)
 *   glyph draw offset = (line box - font natural height) / 2      (CSS half-leading)
 *
 * `KeyValueRow` / `AboutRow` reproduce `.settings-row` (baseline aligned label +
 * right-aligned mono value) and `.settings-about-list` (76px | 1fr grid).
 *
 * They are view-local on purpose: nothing else in the kit needs CSS line boxes
 * yet. If a second view needs them, promote them to `textura.ui` per AGENTS.md §4.
 */

/** `body { line-height: 1.5 }` (base.css:26). */
let LH_BODY: Float32 = 1.5
/** `.settings-card-desc { line-height: 1.55 }` (appshell.css:374). */
let LH_CARD_DESC: Float32 = 1.55
/** `.settings-about-list dd { line-height: 1.6 }` (appshell.css:508). */
let LH_ABOUT_DD: Float32 = 1.6
/** `.settings-note { line-height: 1.65 }` (appshell.css:428). */
let LH_NOTE: Float32 = 1.65
/** `.settings-warning { line-height: 1.7 }` (appshell.css:444). */
let LH_WARNING: Float32 = 1.7
/**
 * `.settings-row` baseline delta between the 11.5px mono value and the 12.5px UI label
 * (measured from `tools/parity/ref/settings-*.png`: value ink sits 1px below the label ink
 * and the DOM row box is 19.25 = 2 + 17.25).
 */
let VALUE_BASELINE_DROP: Float32 = 2.0

/**
 * Optical baseline nudge (logical px) for the small type sizes.
 *
 * CUI/SDL_ttf reports a 12.5px natural line height of 18.5 and draws CJK ink 4px below the
 * text origin, while Chromium's reference draws the same glyphs ~2.5px below the line-box
 * top for `.settings-row`-sized text. Without this correction every 11.5/12.5px line sits
 * 1.5px low (measured ink tops: rows 441 vs 439, notes 286 vs 285, dd 586 vs 585).
 * Larger sizes (13.5/22) already match, so they keep a zero nudge.
 */
func baselineNudge(sizePx: Float32): Float32 {
    if (sizePx <= 12.5) {
        -1.5
    } else {
        0.0
    }
}

/** `.settings-card-desc { max-width: 46ch }` — the ch unit is the "0" advance (appshell.css:376). */
func chWidth(ctx: UiContext, sizePx: Float32): Float32 {
    ctx.textWidth("0", pointSize: fpSize(ctx, sizePx), style: FontStyle(weight: cssWeight(400)))
}

func textStyleOf(weight: Int64): FontStyle {
    FontStyle(weight: cssWeight(weight))
}

func measureText(ctx: UiContext, text: String, sizePx: Float32, weight: Int64, family: ?String): Float32 {
    if (text.isEmpty()) {
        return 0.0
    }
    ctx.textWidth(text, pointSize: fpSize(ctx, sizePx), style: textStyleOf(weight), font: family)
}

/** Font natural line height (`textHeight`) — the "normal" line-height CSS half-leading starts from. */
func naturalLine(ctx: UiContext, sizePx: Float32, weight: Int64, family: ?String): Float32 {
    ctx.textHeight(pointSize: fpSize(ctx, sizePx), style: textStyleOf(weight), font: family)
}

/* ------------------------------------------------------------------ */
/* CSS-ish line breaking                                               */
/* ------------------------------------------------------------------ */

func isSpaceCode(code: UInt32): Bool {
    code == UInt32(32) || code == UInt32(9)
}

/** Han / CJK punctuation / fullwidth forms break between characters (CSS `line-break: normal`). */
func isCjkCode(code: UInt32): Bool {
    (code >= UInt32(0x2E80) && code <= UInt32(0x9FFF)) || (code >= UInt32(0xF900) && code <= UInt32(0xFAFF)) || (code >=
        UInt32(0xFE30) && code <= UInt32(0xFE4F)) || (code >= UInt32(0xFF00) && code <= UInt32(0xFF60)) || (code >=
        UInt32(0xFFE0) && code <= UInt32(0xFFE6)) || (code >= UInt32(0x3000) && code <= UInt32(0x303F))
}

/** Punctuation that may not start a line (subset of UAX #14 used by the reference copy). */
func isClosingCode(code: UInt32): Bool {
    code == UInt32(0xFF0C) || code == UInt32(0x3002) || code == UInt32(0x3001) || code == UInt32(0xFF1B) || code ==
        UInt32(0xFF1A) || code == UInt32(0xFF01) || code == UInt32(0xFF1F) || code == UInt32(0xFF09) || code == UInt32(0xFF3D) ||
        code == UInt32(0x300B) || code == UInt32(0x300D) || code == UInt32(0x300F) || code == UInt32(0x3011) || code ==
        UInt32(0x3015) || code == UInt32(0x201D) || code == UInt32(0x2019) || code == UInt32(0x2026) || code == UInt32(0x00B7) ||
        code == UInt32(0x0025) || code == UInt32(0x002C) || code == UInt32(0x002E) || code == UInt32(0x003A) || code ==
        UInt32(0x003B) || code == UInt32(0x0021) || code == UInt32(0x003F) || code == UInt32(0x0029) || code == UInt32(0x005D)
}

/** Punctuation that may not end a line. */
func isOpeningCode(code: UInt32): Bool {
    code == UInt32(0xFF08) || code == UInt32(0x300A) || code == UInt32(0x300C) || code == UInt32(0x300E) || code ==
        UInt32(0x3010) || code == UInt32(0x3014) || code == UInt32(0x201C) || code == UInt32(0x2018) || code == UInt32(0x0028) ||
        code == UInt32(0x005B)
}

/**
 * Break opportunities: a space, every CJK rune, or (for `break-all` mono values) every rune.
 * Latin words stay whole so `localStorage` / `replaceWorkspace` never split mid-word.
 */
func splitAtoms(text: String, breakAll: Bool): Array<String> {
    let atoms = ArrayList<String>()
    let latin = StringBuilder()
    for (rune in text.runes()) {
        let code = UInt32(rune)
        if (isSpaceCode(code)) {
            if (latin.size > 0) {
                atoms.add(latin.toString())
                latin.reset()
            }
            atoms.add(" ")
            continue
        }
        if (breakAll) {
            if (latin.size > 0) {
                atoms.add(latin.toString())
                latin.reset()
            }
            atoms.add(rune.toString())
            continue
        }
        if (isCjkCode(code)) {
            if (latin.size > 0) {
                atoms.add(latin.toString())
                latin.reset()
            }
            atoms.add(rune.toString())
        } else {
            latin.append(rune)
        }
    }
    if (latin.size > 0) {
        atoms.add(latin.toString())
    }
    atoms.toArray()
}

/** First code point of an atom (atoms are either one rune or one Latin word). */
func firstCode(atom: String): UInt32 {
    for (rune in atom.runes()) {
        return UInt32(rune)
    }
    UInt32(0)
}

func trimTrailingSpaces(value: String): String {
    var end = value.size
    while (end > 0 && value[end - 1] == UInt8(32)) {
        end -= 1
    }
    if (end == value.size) {
        value
    } else {
        value[0..end]
    }
}

/**
 * Greedy wrap with the two CSS prohibitions the reference copy relies on:
 * no line starts with closing punctuation (`，）。…`) and no line ends with an
 * opening bracket. Closing punctuation is allowed to overflow the measure, which
 * is what Chrome does for `…（textura.theme），` (appshell.css:371-377).
 */
func wrapText(
    ctx: UiContext,
    text: String,
    limit: Float32,
    sizePx: Float32,
    weight: Int64,
    family: ?String,
    breakAll: Bool
): Array<String> {
    let lines = ArrayList<String>()
    if (text.isEmpty()) {
        return []
    }
    if (measureText(ctx, text, sizePx, weight, family) <= limit) {
        return [text]
    }
    let atoms = splitAtoms(text, breakAll)
    var current = ""
    var currentLast: ?UInt32 = None
    for (atom in atoms) {
        if (atom == " ") {
            if (current.isEmpty()) {
                continue
            }
            current += atom
            currentLast = Some(UInt32(32))
            continue
        }
        let atomCode = firstCode(atom)
        if (current.isEmpty()) {
            current = atom
            currentLast = Some(atomCode)
            continue
        }
        // UAX #14 subset: a closing mark never starts a line, an opening mark never ends one.
        if (isClosingCode(atomCode)) {
            current += atom
            currentLast = Some(atomCode)
            continue
        }
        let allowOverflow = match (currentLast) {
            case Some(code) => isOpeningCode(code)
            case None => false
        }
        if (allowOverflow || measureText(ctx, trimTrailingSpaces(current + atom), sizePx, weight, family) <= limit) {
            current += atom
            currentLast = Some(atomCode)
        } else {
            lines.add(trimTrailingSpaces(current))
            current = atom
            currentLast = Some(atomCode)
        }
    }
    if (!current.isEmpty()) {
        lines.add(trimTrailingSpaces(current))
    }
    lines.toArray()
}

/** Line height (CSS px) for one line of a paragraph. */
func lineBoxHeight(sizePx: Float32, multiplier: Float32): Float32 {
    sizePx * multiplier
}

func drawTextLines(
    ctx: UiContext,
    lines: Array<String>,
    x: Float32,
    top: Float32,
    width: Float32,
    sizePx: Float32,
    lineHeightPx: Float32,
    weight: Int64,
    ink: Color,
    alignment: TextAlign,
    family: ?String
): Unit {
    let size = fpSize(ctx, sizePx)
    let lineHeight = fpSize(ctx, lineHeightPx)
    let halfLeading = (lineHeight - naturalLine(ctx, sizePx, weight, family)) / 2.0
    var index: Int64 = 0
    for (line in lines) {
        if (!line.isEmpty()) {
            let lineWidth = measureText(ctx, line, sizePx, weight, family)
            let drawX = match (alignment) {
                case TextAlign.Trailing => x + width - lineWidth
                case TextAlign.Center => x + (width - lineWidth) / 2.0
                case _ => x
            }
            ctx.text(line, drawX, top + Float32(index) * lineHeight + halfLeading + baselineNudge(sizePx), ink,
                pointSize: size, style: textStyleOf(weight), font: family)
        }
        index += 1
    }
}

/* ------------------------------------------------------------------ */
/* Paragraph                                                           */
/* ------------------------------------------------------------------ */

/** A paragraph with an explicit CSS line-height, optional `max-width` and `break-all`. */
class Paragraph <: Widget {
    private let text: String
    private let sizePx: Float32
    private let lineHeightPx: Float32
    private let weight: Int64
    private let ink: Color
    private let alignment: TextAlign
    private let family: ?String
    private let maxWidthPx: Float32
    private let maxCh: Float32
    private let breakAll: Bool
    private var frame = Rect.zero()

    init(
        text: String,
        sizePx!: Float32,
        lineHeightPx!: Float32,
        ink!: Color,
        weight!: Int64 = 400,
        alignment!: TextAlign = TextAlign.Leading,
        family!: ?String = None,
        maxWidthPx!: Float32 = 1000000.0,
        maxCh!: Float32 = 0.0,
        breakAll!: Bool = false
    ) {
        this.text = text
        this.sizePx = sizePx
        this.lineHeightPx = lineHeightPx
        this.weight = weight
        this.ink = ink
        this.alignment = alignment
        this.family = family
        this.maxWidthPx = maxWidthPx
        this.maxCh = maxCh
        this.breakAll = breakAll
        emit(this)
    }

    /** Measure cap: the smaller of the offered width, an explicit px cap and a `ch` cap. */
    private func limitFor(ctx: UiContext, available: Float32): Float32 {
        var limit = max(available, 0.0)
        if (maxCh > 0.0) {
            limit = min(limit, chWidth(ctx, sizePx) * maxCh)
        }
        limit = min(limit, maxWidthPx)
        max(1.0, limit)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        let limit = limitFor(ctx, available.w)
        let full = measureText(ctx, text, sizePx, weight, family)
        let lineHeight = fpSize(ctx, lineHeightPx)
        if (full <= limit) {
            Size(min(full, max(available.w, 1.0)), lineHeight)
        } else {
            let lines = wrapText(ctx, text, limit, sizePx, weight, family, breakAll)
            Size(min(limit, max(available.w, 1.0)), lineHeight * Float32(lines.size))
        }
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let limit = limitFor(ctx, frame.w)
        let lines = wrapText(ctx, text, limit, sizePx, weight, family, breakAll)
        drawTextLines(ctx, lines, frame.x, frame.y, frame.w, sizePx, lineHeightPx, weight, ink, alignment, family)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/* ------------------------------------------------------------------ */
/* Note box / warning block                                            */
/* ------------------------------------------------------------------ */

/**
 * `.settings-note` — `padding: 12px; border: 1px dashed var(--border); radius 8;
 * background: surface-2; 11.5px/1.65; color: text-faint` (appshell.css:422-430).
 * Chrome's 1px dashed pattern is 3px on / 2px off (measured on the reference PNG).
 */
class NoteBox <: Widget {
    private let tokens: ThemeTokens
    private let text: String
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, text: String) {
        this.tokens = tokens
        this.text = text
        emit(this)
    }

    private func innerWidth(rect: Rect): Float32 {
        max(1.0, rect.w - 24.0 - tokens.metrics.borderWidth * 2.0)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        let width = max(1.0, available.w)
        let limit = max(1.0, width - 24.0 - tokens.metrics.borderWidth * 2.0)
        let lines = wrapText(ctx, text, limit, TextSize.caption, 400, Option<String>.None, false)
        let height = Float32(lines.size) * lineBoxHeight(TextSize.caption, LH_NOTE) + 24.0 +
            tokens.metrics.borderWidth * 2.0
        Size(width, height)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let colour = tokens.color
        let width = tokens.metrics.borderWidth
        fillRound(ctx, frame, tokens.radius.md, colour.surface2)
        ctx
            .renderer
            .strokeRoundedRectDashed(frame.inset(width / 2.0), tokens.radius.md, Pen(width: width, color: colour.border),
                dash: 3.0, gap: 2.0)
        let lines = wrapText(ctx, text, innerWidth(frame), TextSize.caption, 400, Option<String>.None, false)
        drawTextLines(ctx, lines, frame.x + width + 12.0, frame.y + width + 12.0, innerWidth(frame), TextSize.caption,
            lineBoxHeight(TextSize.caption, LH_NOTE), 400, colour.textFaint, TextAlign.Leading, Option<String>.None)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/**
 * `.settings-warning` — `12.5px/1.7; color: text; border-left: 3px solid danger;
 * padding-left: 12px` (appshell.css:442-448). Used inside the destructive modals.
 */
class WarningText <: Widget {
    private let tokens: ThemeTokens
    private let text: String
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, text: String) {
        this.tokens = tokens
        this.text = text
        emit(this)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        let width = max(1.0, available.w)
        let limit = max(1.0, width - 15.0)
        let lines = wrapText(ctx, text, limit, TextSize.controlSmall, 400, Option<String>.None, false)
        Size(width, Float32(lines.size) * lineBoxHeight(TextSize.controlSmall, LH_WARNING))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let colour = tokens.color
        let rule: Float32 = 3.0
        fillRect(ctx, Rect(frame.x, frame.y, rule, frame.h), colour.danger)
        let lines = wrapText(ctx, text, max(1.0, frame.w - 15.0), TextSize.controlSmall, 400, Option<String>.None, false)
        drawTextLines(ctx, lines, frame.x + 15.0, frame.y, frame.w - 15.0, TextSize.controlSmall,
            lineBoxHeight(TextSize.controlSmall, LH_WARNING), 400, colour.text, TextAlign.Leading, Option<String>.None)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/* ------------------------------------------------------------------ */
/* Rows                                                                */
/* ------------------------------------------------------------------ */

/**
 * Middle ellipsis for single-line values, keeping the tail (the file name) readable.
 *
 * The Web build lets `.settings-row-value` wrap (`word-break: break-all`, appshell.css:406-413)
 * because its two values are short (`localStorage`, `textura.workspace.v1`). A desktop
 * workspace path is unbounded, and a wrapped row grows by 17.25px and pushes every card below
 * it, so the port truncates instead — the reference card geometry then holds for any path
 * length (see docs/SETTINGS-VIEW.md).
 */
func ellipsizeMiddle(
    ctx: UiContext,
    text: String,
    limit: Float32,
    sizePx: Float32,
    weight: Int64,
    family: ?String
): String {
    if (measureText(ctx, text, sizePx, weight, family) <= limit) {
        return text
    }
    let runes = text.toRuneArray()
    if (runes.size <= 2) {
        return text
    }
    let marker = "…"
    let budget = max(0.0, limit - measureText(ctx, marker, sizePx, weight, family))
    var head: Int64 = 0
    var tail: Int64 = runes.size - 1
    var lastFit = ""
    // Grow the tail first (file name), then the head, alternating while the run still fits.
    var takeTail = true
    while (head <= tail) {
        let candidate = middleSlice(runes, head, tail, marker)
        if (measureText(ctx, candidate, sizePx, weight, family) > budget) {
            break
        }
        lastFit = candidate
        if (takeTail) {
            tail -= 1
        } else {
            head += 1
        }
        takeTail = !takeTail
    }
    if (lastFit.isEmpty()) {
        marker
    } else {
        lastFit
    }
}

/** `head..<head` prefix + `…` + `tail..<end` suffix. */
func middleSlice(runes: Array<Rune>, head: Int64, tail: Int64, marker: String): String {
    let sb = StringBuilder()
    var index: Int64 = 0
    while (index < head) {
        sb.append(runes[index])
        index += 1
    }
    sb.append(marker)
    index = tail
    while (index < runes.size) {
        sb.append(runes[index])
        index += 1
    }
    sb.toString()
}

/**
 * `.settings-row` (appshell.css:393-413): `display: flex; align-items: baseline;
 * justify-content: space-between; gap: 16px; font-size: 12.5px` with a mono
 * 11.5px value capped at `max-width: 68%` and right aligned.
 *
 * Baseline alignment is why the row is taller than its label line box: the 11.5px
 * value is pushed down until its baseline matches, so the row measures 19.25px
 * (reference PNG: rows at 436.4 / 461.7 / 486.9 / 512.2, pitch 25.25).
 */
class KeyValueRow <: Widget {
    private let tokens: ThemeTokens
    private let label: String
    private let value: String
    private var frame = Rect.zero()
    private var truncated: Bool = false

    init(tokens: ThemeTokens, label: String, value: String) {
        this.tokens = tokens
        this.label = label
        this.value = value
        emit(this)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        let _ = ctx
        let width = max(1.0, available.w)
        let labelLine = lineBoxHeight(TextSize.controlSmall, LH_BODY)
        let valueLine = lineBoxHeight(TextSize.caption, LH_BODY)
        // `.settings-row { align-items: baseline }`: the 11.5px mono value is pushed 2px down so
        // its baseline matches the 12.5px label, so the row box is 19.25 tall. The 2px is the
        // measured Chromium baseline delta between `--font-mono` (11.5) and the UI font (12.5)
        // on the parity host (reference rows sit at 436.4 / 461.7 / 486.9 / 512.2, pitch 25.25).
        // The value is always one line (ellipsized), so the row height is content-independent.
        Size(width, max(labelLine, VALUE_BASELINE_DROP + valueLine))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let colour = tokens.color
        let labelLine = fpSize(ctx, lineBoxHeight(TextSize.controlSmall, LH_BODY))
        let valueLine = fpSize(ctx, lineBoxHeight(TextSize.caption, LH_BODY))
        let labelNatural = naturalLine(ctx, TextSize.controlSmall, 400, Option<String>.None)
        let valueNatural = naturalLine(ctx, TextSize.caption, 400, Some(fontMono()))
        let labelHalf = (labelLine - labelNatural) / 2.0
        let valueHalf = (valueLine - valueNatural) / 2.0
        ctx.text(label, frame.x, frame.y + labelHalf + baselineNudge(TextSize.controlSmall), colour.textMuted,
            pointSize: fpSize(ctx, TextSize.controlSmall), style: textStyleOf(400))
        let labelWidth = measureText(ctx, label, TextSize.controlSmall, 400, Option<String>.None)
        let valueLimit = min(frame.w * 0.68, max(1.0, frame.w - labelWidth - tokens.space.s4))
        let shown = ellipsizeMiddle(ctx, value, valueLimit, TextSize.caption, 400, Some(fontMono()))
        truncated = shown != value
        drawTextLines(ctx, [shown], frame.x, frame.y + VALUE_BASELINE_DROP + valueHalf, frame.w, TextSize.caption,
            lineBoxHeight(TextSize.caption, LH_BODY), 400, colour.text, TextAlign.Trailing, Some(fontMono()))
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        // A truncated value still has to be readable: hovering shows the full text (the Web
        // build relies on `word-break` wrapping, which would change the card height here).
        if (!truncated) {
            return false
        }
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (frame.contains(x, y)) {
                    ctx.showTooltip(value, frame)
                }
            case _ => ()
        }
        false
    }
}

/**
 * `.settings-about-list` (appshell.css:492-509): a `76px | 1fr` grid with
 * `gap: 8px 12px`, `align-items: baseline`, `dt` in `text-faint` and `dd` with
 * `line-height: 1.6`.
 */
class AboutRow <: Widget {
    private let tokens: ThemeTokens
    private let label: String
    private let value: String
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, label: String, value: String) {
        this.tokens = tokens
        this.label = label
        this.value = value
        emit(this)
    }

    private func valueWidth(rect: Rect): Float32 {
        max(1.0, rect.w - 76.0 - 12.0)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        let width = max(1.0, available.w)
        let lines = wrapText(ctx, value, max(1.0, width - 88.0), TextSize.controlSmall, 400, Option<String>.None, false)
        let valueLine = lineBoxHeight(TextSize.controlSmall, LH_ABOUT_DD)
        let labelLine = lineBoxHeight(TextSize.controlSmall, LH_BODY)
        // Both cells use the UI font, so the baselines differ only by the half-leading of the
        // two line heights: `dd` (1.6) is 0.625 taller, so its box starts 0.625 above `dt`.
        let shift = max(0.0, (valueLine - labelLine) / 2.0)
        Size(width, max(labelLine + shift, valueLine * Float32(lines.size)))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let colour = tokens.color
        let labelLine = fpSize(ctx, lineBoxHeight(TextSize.controlSmall, LH_BODY))
        let labelNatural = naturalLine(ctx, TextSize.controlSmall, 400, Option<String>.None)
        let labelHalf = (labelLine - labelNatural) / 2.0
        let valueLine = lineBoxHeight(TextSize.controlSmall, LH_ABOUT_DD)
        let valueHalf = (fpSize(ctx, valueLine) - naturalLine(ctx, TextSize.controlSmall, 400, Option<String>.None)) /
            2.0
        let shift = max(0.0, (valueLine - labelLine) / 2.0)
        ctx.text(label, frame.x, frame.y + shift + labelHalf + baselineNudge(TextSize.controlSmall), colour.textFaint,
            pointSize: fpSize(ctx, TextSize.controlSmall), style: textStyleOf(400))
        let lines = wrapText(ctx, value, valueWidth(frame), TextSize.controlSmall, 400, Option<String>.None, false)
        drawTextLines(ctx, lines, frame.x + 88.0, frame.y + valueHalf, valueWidth(frame), TextSize.controlSmall,
            valueLine, 400, colour.text, TextAlign.Leading, Option<String>.None)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/* ------------------------------------------------------------------ */
/* Shared visual helpers                                               */
/* ------------------------------------------------------------------ */

/**
 * `border-bottom: 1px solid var(--border)` snapped to a whole pixel row.
 *
 * CSS paints borders on device-pixel rows (card heads land on y=251.4 and are painted on row
 * 251), while CUI's `Divider` keeps the fractional frame and paints row 252 for the same box.
 * Snapping here removes a 1px band on every card head.
 */
class Hairline <: Widget {
    private let tokens: ThemeTokens
    private var frame = Rect.zero()

    init(tokens: ThemeTokens) {
        this.tokens = tokens
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(max(available.w, 0.0), tokens.metrics.borderWidth)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        fillRect(ctx, Rect(frame.x, Float32(Int64(frame.y)), frame.w, tokens.metrics.borderWidth), tokens.color.border)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/** `--shadow-1` as two CUI shadow layers (tokens.css:44), used behind cards. */
func cardShadow(tokens: ThemeTokens): Array<Shadow> {
    [
        Shadow(color: tokens.shadow1.color, offsetY: tokens.shadow1.offsetY, offsetX: tokens.shadow1.offsetX,
            blur: tokens.shadow1.blur, spread: tokens.shadow1.spread),
        Shadow(color: tokens.shadow1Contact.color, offsetY: tokens.shadow1Contact.offsetY,
            offsetX: tokens.shadow1Contact.offsetX, blur: tokens.shadow1Contact.blur,
            spread: tokens.shadow1Contact.spread)
    ]
}
