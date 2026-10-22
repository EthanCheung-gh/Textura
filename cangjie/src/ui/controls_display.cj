package textura.ui

import cui.*

/*
 * Badge / Progress / SegmentedControl — 1:1 port of `.badge*`, `.progress*`, `.segmented*`
 * (src/ui/ui.css:242-448).
 *
 * All three are custom widgets because CUI's counterparts differ in geometry: `Badge` is a
 * fixed 22vp pill with a 36-alpha tint, `ProgressBar` has no label column, and
 * `SegmentedControl` is a text-only control without the 2vp inset tray or the active pill
 * shadow that Design's segmented control uses.
 */

/** `.badge--neutral|accent|ok|warn|danger|info` (ui.css:264-298). */
public enum BadgeTone {
    | Neutral
    | Accent
    | Ok
    | Warn
    | Danger
    | Info
}

/**
 * `.badge` — `padding: 2px 7px; border-radius: 999px; font-size: 11px; font-weight: 550;
 * line-height: 1.6; border: 1px solid transparent; gap: 5px` (ui.css:243-254).
 * Optional `dot` renders the 5x5 `currentColor` dot (ui.css:256-262).
 */
public class BadgeView <: Widget {
    private let tokens: ThemeTokens
    private let text: String
    private let tone: BadgeTone
    private let dot: Bool
    private var frame = Rect.zero()

    public init(tokens: ThemeTokens, text: String, tone!: BadgeTone = BadgeTone.Neutral, dot!: Bool = false) {
        this.tokens = tokens
        this.text = text
        this.tone = tone
        this.dot = dot
        emit(this)
    }

    /** Badge height: 11px * 1.6 line-height + 2 * 2px padding = 21.6 -> 22 logical pixels. */
    private func pillHeight(ctx: UiContext): Float32 {
        fpSize(ctx, TextSize.micro) * 1.6 + tokens.space.s1
    }

    private func fontSize(ctx: UiContext): Float32 {
        fpSize(ctx, TextSize.micro)
    }

    private func textWidthValue(ctx: UiContext): Float32 {
        textWidth(ctx, text, fontSize(ctx), 550)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        // padding 2px 7px (ui.css:246) + dot 5px + gap 5px (ui.css:246-258)
        var width = textWidthValue(ctx) + 7.0 * 2.0
        if (dot) {
            width += 5.0 + 5.0
        }
        Size(min(width, max(available.w, 0.0)), min(pillHeight(ctx), max(available.h, 0.0)))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        var fill = c.surface2
        var border = c.border
        var ink = c.textMuted
        match (tone) {
            case Neutral =>
                // .badge--neutral { background: surface-2; border-color: border; color: text-muted }
                ()
            case Accent =>
                // .badge--accent { background: accent-soft; border: color-mix(accent 28%); color: accent-ink }
                fill = c.accentSoft
                border = tint(c.accent, 28.0)
                ink = c.accentInk
            case Ok =>
                // .badge--ok { background: color-mix(ok 12%); border: color-mix(ok 30%); color: ok-ink }
                fill = tint(c.ok, 12.0)
                border = tint(c.ok, 30.0)
                ink = c.okInk
            case Warn =>
                // .badge--warn { background: color-mix(warn 14%); border: color-mix(warn 32%); color: warn-ink }
                fill = tint(c.warn, 14.0)
                border = tint(c.warn, 32.0)
                ink = c.warnInk
            case Danger =>
                // .badge--danger { background: color-mix(danger 12%); border: 30%; color: danger-ink }
                fill = tint(c.danger, 12.0)
                border = tint(c.danger, 30.0)
                ink = c.dangerInk
            case Info =>
                // .badge--info { background: color-mix(info 12%); border: 30%; color: info-ink }
                fill = tint(c.info, 12.0)
                border = tint(c.info, 30.0)
                ink = c.infoInk
        }
        fillRound(ctx, frame, frame.h / 2.0, fill)
        strokeRound(ctx, frame, frame.h / 2.0, tokens.metrics.borderWidth, border)
        let fontSizeValue = fontSize(ctx)
        var contentWidth = textWidthValue(ctx)
        if (dot) {
            // .badge-dot 5px wide + `gap: 5px` from `.badge` (ui.css:246, 256-262)
            contentWidth += 10.0
        }
        var x = frame.centerX() - contentWidth / 2.0
        if (dot) {
            let radius: Float32 = 2.5
            ctx.renderer.fillCircle(x + radius, frame.centerY(), radius, ink)
            x += 10.0
        }
        textLeading(ctx, text, x, frame.centerY(), ink, fontSizeValue, 550)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/** `.progress-fill--accent|ok|warn|danger|info` (ui.css:332-350). */
public enum ProgressTone {
    | Accent
    | Ok
    | Warn
    | Danger
    | Info
}

/**
 * `.progress-row` + `.progress` (ui.css:300-358): a pill track with a 1px border and an inset
 * fill, optionally followed by a right-aligned `NN%` label with `min-width: 30px`.
 */
public class ProgressView <: Widget {
    private let tokens: ThemeTokens
    private let value: Float32
    private let tone: ProgressTone
    private let size: ControlSize
    private let showLabel: Bool
    private var frame = Rect.zero()

    public init(
        tokens: ThemeTokens,
        value: Float32,
        tone!: ProgressTone = ProgressTone.Accent,
        size!: ControlSize = ControlSize.Md,
        showLabel!: Bool = false
    ) {
        this.tokens = tokens
        // Progress.tsx clamps to 0..100 and rounds.
        let safe: Float32 = if (value.isNaN()) {
            0.0
        } else {
            clampF32(value, 0.0, 100.0)
        }
        this.value = Float32(Int64(safe + 0.5))
        this.tone = tone
        this.size = size
        this.showLabel = showLabel
        emit(this)
    }

    /** `.progress--sm { height: 5px }` / `--md { height: 8px }` (ui.css:317-323). */
    private func barHeight(): Float32 {
        match (size) {
            case Sm => 5.0
            case Md => 8.0
        }
    }

    /** `.progress-label { font-size: 11px; min-width: 30px; text-align: right }` (ui.css:352-358). */
    private func labelWidth(ctx: UiContext): Float32 {
        if (!showLabel) {
            return 0.0
        }
        max(30.0, textWidth(ctx, "100%", fpSize(ctx, TextSize.micro), 400))
    }

    public func measure(ctx: UiContext, available: Size): Size {
        // The row is as tall as the taller of the track and the label line box (11px * 1.6).
        let rowHeight = if (showLabel) {
            max(barHeight(), fpSize(ctx, TextSize.micro) * 1.6)
        } else {
            barHeight()
        }
        Size(max(available.w, 0.0), min(rowHeight, max(available.h, rowHeight)))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        let height = barHeight()
        let labelSpace = labelWidth(ctx)
        let gap: Float32 = if (showLabel) {
            tokens.space.s2
        } else {
            0.0
        }
        let track = Rect(frame.x, frame.centerY() - height / 2.0,
            max(Float32(0.0), frame.w - labelSpace - gap), height)
        let radius = height / 2.0
        fillRound(ctx, track, radius, c.surface2)
        strokeRound(ctx, track, radius, tokens.metrics.borderWidth, c.border)
        // `.progress-fill { height: 100%; border-radius: inherit }` inside a bordered,
        // overflow-hidden track: the fill covers the padding box.
        let innerWidth = max(Float32(0.0), track.w - tokens.metrics.borderWidth * 2.0)
        let fillWidth = innerWidth * value / 100.0
        if (fillWidth > 0.0) {
            let color = match (tone) {
                case Accent => c.accent
                case Ok => c.ok
                case Warn => c.warn
                case Danger => c.danger
                case Info => c.info
            }
            fillRound(
                ctx,
                Rect(track.x + tokens.metrics.borderWidth, track.y + tokens.metrics.borderWidth, fillWidth,
                    max(0.0, height - tokens.metrics.borderWidth * 2.0)),
                max(0.0, radius - tokens.metrics.borderWidth),
                color
            )
        }
        if (showLabel) {
            // `font-variant-numeric: tabular-nums` has no CUI equivalent; digits use the
            // proportional face, which is the documented Progress deviation.
            textTrailing(ctx, "${Int64(value)}%", frame.right(), frame.centerY(), c.textMuted,
                fpSize(ctx, TextSize.micro), 400)
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/** One entry of a segmented control (`SegmentedOption` in Segmented.tsx). */
public struct SegmentedItem {
    public let label: String
    public let glyph: ?IconGlyph
    public let title: String

    public init(label: String, glyph!: ?IconGlyph = None, title!: String = "") {
        this.label = label
        this.glyph = glyph
        this.title = title
    }
}

/**
 * `.segmented` (ui.css:405-448): 2px inset tray on `surface-2`, 1px border, 8px radius, 1..n
 * items with a 2px gap; the active item is a `surface` pill with `--shadow-1`.
 *
 * Deviation from CUI's `SegmentedControl`: CUI paints the *selected* segment in the theme
 * accent with `accentText` and has no tray inset, so it cannot express Design's
 * "surface pill on a recessed track" look; the port keeps the CSS geometry.
 */
public class SegmentedView <: Widget {
    private let id: String
    private let tokens: ThemeTokens
    private let items: Array<SegmentedItem>
    private let selection: Bindable<Int64>
    private let size: ControlSize
    private var frame = Rect.zero()

    public init(
        tokens: ThemeTokens,
        items: Array<SegmentedItem>,
        selection: Bindable<Int64>,
        size!: ControlSize = ControlSize.Md
    ) {
        this.id = focusableControlIdentity("UiSegmented")
        this.tokens = tokens
        this.items = items
        this.selection = selection
        this.size = size
        emit(this)
    }

    /** `.segmented { padding: 2px; gap: 2px }` (ui.css:405-413). */
    private func trayPadding(): Float32 {
        2.0
    }

    private func itemGap(): Float32 {
        2.0
    }

    /** `.segmented--sm .segmented-item { height: 24px; padding: 0 8px }` / md 28px/10px. */
    private func itemMetrics(): ButtonMetrics {
        match (size) {
            case Sm => ButtonMetrics(24.0, 8.0, TextSize.label, 14.0)
            case Md => ButtonMetrics(28.0, 10.0, TextSize.label, 14.0)
        }
    }

    private func itemWidth(ctx: UiContext, item: SegmentedItem): Float32 {
        let metrics = itemMetrics()
        let fontSize = fpSize(ctx, metrics.fontSize)
        var width = textWidth(ctx, item.label, fontSize, 550)
        match (item.glyph) {
            case Some(_) => width += metrics.iconSide + 5.0
            case None => ()
        }
        width + metrics.paddingH * 2.0
    }

    public func measure(ctx: UiContext, available: Size): Size {
        var width = trayPadding() * 2.0 + tokens.metrics.borderWidth * 2.0
        var index = 0
        for (item in items) {
            if (index > 0) {
                width += itemGap()
            }
            width += itemWidth(ctx, item)
            index += 1
        }
        let height = itemMetrics().height + trayPadding() * 2.0 + tokens.metrics.borderWidth * 2.0
        Size(min(width, max(available.w, 0.0)), min(height, max(available.h, 0.0)))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        let radius = tokens.radius.md
        let metrics = itemMetrics()
        let fontSize = fpSize(ctx, metrics.fontSize)
        let border = tokens.metrics.borderWidth
        fillRound(ctx, frame, radius, c.surface2)
        strokeRound(ctx, frame, radius, border, c.border)
        let active = selection.value
        var x = frame.x + border + trayPadding()
        let itemHeight = metrics.height
        let itemY = frame.centerY() - itemHeight / 2.0
        let innerRadius = max(0.0, radius - 2.0)
        var index = 0
        for (item in items) {
            let width = itemWidth(ctx, item)
            let itemRect = Rect(x, itemY, width, itemHeight)
            let hovered = ctx.isHovered("${id}:${index}")
            if (index == active) {
                // .segmented-item.is-active { background: surface; color: text; box-shadow: shadow-1 }
                shadow1(ctx, tokens, itemRect, innerRadius)
                fillRound(ctx, itemRect, innerRadius, c.surface)
            }
            let ink = if (index == active || hovered) {
                c.text
            } else {
                c.textMuted
            }
            var contentWidth = textWidth(ctx, item.label, fontSize, 550)
            match (item.glyph) {
                case Some(_) => contentWidth += metrics.iconSide + 5.0
                case None => ()
            }
            var textX = itemRect.centerX() - contentWidth / 2.0
            match (item.glyph) {
                case Some(glyph) =>
                    paintSpec(ctx, glyph, Rect(textX, itemRect.centerY() - metrics.iconSide / 2.0, metrics.iconSide,
                        metrics.iconSide), ink)
                    textX += metrics.iconSide + 5.0
                case None => ()
            }
            textLeading(ctx, item.label, textX, itemRect.centerY(), ink, fontSize, 550)
            x += width + itemGap()
            index += 1
        }
        if (ctx.showFocusRing(id)) {
            focusRing(ctx, tokens, frame, radius)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(_, _) =>
                var index = 0
                while (index < items.size) {
                    claimHoverIfInside(ctx, event, itemFrameAt(ctx, index), "${id}:${index}", CursorShape.Interactive)
                    index += 1
                }
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    ctx.focus(id, viaKeyboard: false)
                    var index = 0
                    while (index < items.size) {
                        if (itemFrameAt(ctx, index).contains(x, y)) {
                            selection.value = index
                            return true
                        }
                        index += 1
                    }
                }
            case UiEvent.KeyDown(key, isRepeat) =>
                if (ctx.hasFocus(id) && !isRepeat) {
                    // Left/Right walk the options, matching the Web group's arrow-key habit.
                    match (key) {
                        case Key.Left =>
                            selection.value = max(0, selection.value - 1)
                            return true
                        case Key.Right =>
                            selection.value = min(items.size - 1, selection.value + 1)
                            return true
                        case _ => ()
                    }
                }
            case _ => ()
        }
        false
    }

    public func focusableId(): ?String {
        Some(id)
    }

    /** Item rectangles are recomputed from the laid-out frame; no state is cached between phases. */
    private func itemFrameAt(ctx: UiContext, index: Int64): Rect {
        let metrics = itemMetrics()
        let border = tokens.metrics.borderWidth
        var x = frame.x + border + trayPadding()
        var offset = 0
        while (offset < items.size) {
            let width = itemWidth(ctx, items[offset])
            if (offset == index) {
                return Rect(x, frame.centerY() - metrics.height / 2.0, width, metrics.height)
            }
            x += width + itemGap()
            offset += 1
        }
        Rect.zero()
    }
}
