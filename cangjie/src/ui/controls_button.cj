package textura.ui

import cui.*

/*
 * Button + IconButton — 1:1 port of `.btn*` / `.icon-btn*` (src/ui/ui.css:5-158).
 *
 * CUI's own `Button` is a 38vp control with its own padding and a theme-derived surface, and
 * its class name also collides with anything a view can import, so the port draws the control
 * itself and exposes it as `ButtonView` behind `Ui.button(...)`.
 */

/** `.btn--primary|secondary|ghost|danger` (ui.css:35-103). Order matches the CSS blocks. */
public enum ButtonVariant {
    | Primary
    | Secondary
    | Ghost
    | Danger
}

/** `.btn--sm|md`, `.icon-btn--sm|md`, `.segmented--sm|md`. */
public enum ControlSize {
    | Sm
    | Md
}

/** `.icon-btn--ghost|secondary|danger` (ui.css:136-158). */
public enum IconButtonVariant {
    | Ghost
    | Secondary
    | Danger
}

private let TRANSPARENT: Color = Color.rgba(0, 0, 0, 0)
/** `.btn { gap: var(--space-2) }` (ui.css:10). */
private let BUTTON_GAP: Float32 = 8.0

/** `.btn--sm` / `.btn--md` box metrics (ui.css:19-29). */
struct ButtonMetrics {
    let height: Float32
    let paddingH: Float32
    let fontSize: Float32
    let iconSide: Float32

    init(height: Float32, paddingH: Float32, fontSize: Float32, iconSide: Float32) {
        this.height = height
        this.paddingH = paddingH
        this.fontSize = fontSize
        this.iconSide = iconSide
    }
}

func buttonMetrics(size: ControlSize): ButtonMetrics {
    match (size) {
        // .btn--sm { height: 28px; padding: 0 10px; font-size: 12.5px }
        case Sm => ButtonMetrics(28.0, 10.0, TextSize.controlSmall, 14.0)
        // .btn--md { height: 34px; padding: 0 14px; font-size: 13.5px }
        case Md => ButtonMetrics(34.0, 14.0, TextSize.bodyCompact, 16.0)
    }
}

/** Resolved colours for one button state. */
struct ButtonPaint {
    let fill: Color
    let border: Color
    let label: Color
    let elevated: Bool

    init(fill: Color, border: Color, label: Color, elevated: Bool) {
        this.fill = fill
        this.border = border
        this.label = label
        this.elevated = elevated
    }
}

private func buttonPaint(tokens: ThemeTokens, variant: ButtonVariant, hovered: Bool, pressed: Bool,
    disabled: Bool): ButtonPaint {
    let c = tokens.color
    match (variant) {
        case Primary =>
            // .btn--primary / :hover / :active / :disabled (ui.css:35-57); disabled keeps opacity 1.
            if (disabled) {
                ButtonPaint(c.accentStrongDisabled, c.accentStrongDisabled, c.textOnStrong, false)
            } else if (pressed) {
                ButtonPaint(c.accentStrongActive, c.accentStrongActive, c.textOnStrong, true)
            } else if (hovered) {
                ButtonPaint(c.accentStrongHover, c.accentStrongHover, c.textOnStrong, true)
            } else {
                ButtonPaint(c.accentStrong, c.accentStrong, c.textOnStrong, true)
            }
        case Secondary =>
            // .btn--secondary / :hover (ui.css:59-69); disabled falls back to button:disabled{opacity:.55}.
            if (disabled) {
                ButtonPaint(withOpacity(c.surface, 0.55), withOpacity(c.border, 0.55), withOpacity(c.text, 0.55), true)
            } else if (hovered || pressed) {
                ButtonPaint(c.surface2, c.borderStrong, c.text, true)
            } else {
                ButtonPaint(c.surface, c.border, c.text, true)
            }
        case Ghost =>
            // .btn--ghost / :hover (ui.css:71-80).
            if (disabled) {
                ButtonPaint(TRANSPARENT, TRANSPARENT, withOpacity(c.textMuted, 0.55), false)
            } else if (hovered || pressed) {
                ButtonPaint(c.surface2, TRANSPARENT, c.text, false)
            } else {
                ButtonPaint(TRANSPARENT, TRANSPARENT, c.textMuted, false)
            }
        case Danger =>
            // .btn--danger / :hover / :active / :disabled (ui.css:82-103); no box-shadow.
            if (disabled) {
                ButtonPaint(c.dangerStrongDisabled, c.dangerStrongDisabled, c.textOnStrong, false)
            } else if (pressed) {
                ButtonPaint(c.dangerStrongActive, c.dangerStrongActive, c.textOnStrong, false)
            } else if (hovered) {
                ButtonPaint(c.dangerStrongHover, c.dangerStrongHover, c.textOnStrong, false)
            } else {
                ButtonPaint(c.dangerStrong, c.dangerStrong, c.textOnStrong, false)
            }
    }
}

/**
 * `.btn` — inline-flex, centred, 8px gap, radius 8, 1px transparent border, weight 550
 * (ui.css:6-17). Optional left/right glyphs reproduce `iconLeft`/`iconRight`.
 */
public class ButtonView <: Widget {
    private let id: String
    private let tokens: ThemeTokens
    private let label: String
    private let variant: ButtonVariant
    private let size: ControlSize
    private let iconLeft: ?IconGlyph
    private let iconRight: ?IconGlyph
    private let block: Bool
    private let isEnabled: Bool
    private let onClick: () -> Unit
    private var frame = Rect.zero()

    public init(
        tokens: ThemeTokens,
        label: String,
        onClick: () -> Unit,
        variant!: ButtonVariant = ButtonVariant.Secondary,
        size!: ControlSize = ControlSize.Md,
        iconLeft!: ?IconGlyph = None,
        iconRight!: ?IconGlyph = None,
        block!: Bool = false,
        enabled!: Bool = true
    ) {
        this.id = focusableControlIdentity("UiButton")
        this.tokens = tokens
        this.label = label
        this.onClick = onClick
        this.variant = variant
        this.size = size
        this.iconLeft = iconLeft
        this.iconRight = iconRight
        this.block = block
        this.isEnabled = enabled
        emit(this)
    }

    /** Horizontal extent of the icon+label+icon row, in logical pixels. */
    private func contentWidth(ctx: UiContext): Float32 {
        let metrics = buttonMetrics(size)
        let fontSize = fpSize(ctx, metrics.fontSize)
        var width: Float32 = if (label.isEmpty()) {
            0.0
        } else {
            textWidth(ctx, label, fontSize, 550)
        }
        match (iconLeft) {
            case Some(_) =>
                if (width > 0.0) {
                    width += BUTTON_GAP
                }
                width += metrics.iconSide
            case None => ()
        }
        match (iconRight) {
            case Some(_) =>
                if (width > 0.0) {
                    width += BUTTON_GAP
                }
                width += metrics.iconSide
            case None => ()
        }
        width
    }

    public func measure(ctx: UiContext, available: Size): Size {
        let metrics = buttonMetrics(size)
        let availableWidth = max(0.0, available.w)
        if (block) {
            return Size(availableWidth, min(metrics.height, max(available.h, 0.0)))
        }
        let desired = contentWidth(ctx) + metrics.paddingH * 2.0
        Size(min(desired, availableWidth), min(metrics.height, max(available.h, 0.0)))
    }

    public func layout(ctx: UiContext, rect: Rect): Unit {
        frame = rect
        // Buttons built during build carry a build-order identity; publish it as an accessible
        // button so screen readers and tests can find/activate the same control a click does.
        // (`id == "UiButton"` means the control was constructed in layout, where ids are not
        // unique; registering those would collide across rows.)
        if (id != "UiButton") {
            ctx.registerSemantics(
                SemanticsNode(id, Semantics(label: label, role: SemanticsRole.Button, enabled: isEnabled), rect,
                    actions: [SemanticsAction.Activate]), perform: {action =>
                    match (action) {
                        case SemanticsAction.Activate =>
                            if (isEnabled) {
                                onClick()
                                true
                            } else {
                                false
                            }
                        case _ => false
                    }
                })
        }
    }

    public func draw(ctx: UiContext): Unit {
        let metrics = buttonMetrics(size)
        let radius = tokens.radius.md
        let hovered = isEnabled && ctx.isHovered(id)
        let pressed = isEnabled && ctx.isPressed(id)
        let paint = buttonPaint(tokens, variant, hovered, pressed, !isEnabled)
        if (paint.elevated) {
            shadow1(ctx, tokens, frame, radius)
        }
        fillRound(ctx, frame, radius, paint.fill)
        strokeRound(ctx, frame, radius, tokens.metrics.borderWidth, paint.border)
        // Content row, centred like flex `justify-content: center`.
        let fontSize = fpSize(ctx, metrics.fontSize)
        let centerY = frame.centerY()
        var x = frame.centerX() - contentWidth(ctx) / 2.0
        match (iconLeft) {
            case Some(glyph) =>
                paintSpec(ctx, glyph, Rect(x, centerY - metrics.iconSide / 2.0, metrics.iconSide, metrics.iconSide),
                    paint.label)
                x += metrics.iconSide + BUTTON_GAP
            case None => ()
        }
        if (!label.isEmpty()) {
            let labelWidth = textWidth(ctx, label, fontSize, 550)
            textLeading(ctx, label, x, centerY, paint.label, fontSize, 550)
            x += labelWidth + BUTTON_GAP
        }
        match (iconRight) {
            case Some(glyph) =>
                paintSpec(ctx, glyph, Rect(x, centerY - metrics.iconSide / 2.0, metrics.iconSide, metrics.iconSide),
                    paint.label)
            case None => ()
        }
        if (isEnabled && ctx.showFocusRing(id)) {
            focusRing(ctx, tokens, frame, radius)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        if (!isEnabled) {
            return false
        }
        match (event) {
            case UiEvent.MouseMove(_, _) => claimHoverIfInside(ctx, event, frame, id, CursorShape.Interactive)
            // `isPrimaryPointerButton` also accepts a backend that cannot name the button
            // (`RawCode(0|1)`); see its doc comment in `ui.cj`.
            case UiEvent.MouseDown(button, x, y) =>
                if (isPrimaryPointerButton(button) && frame.contains(x, y)) {
                    ctx.focus(id, viaKeyboard: false)
                    ctx.press(id)
                    return true
                }
            case UiEvent.MouseUp(button, x, y) =>
                if (isPrimaryPointerButton(button) && ctx.isPressed(id)) {
                    ctx.clearPress()
                    if (frame.contains(x, y)) {
                        onClick()
                        return true
                    }
                }
            case UiEvent.KeyDown(key, isRepeat) =>
                // Button.md: Enter and Space both activate while focused.
                if (ctx.hasFocus(id) && !isRepeat) {
                    match (key) {
                        case Key.Enter | Key.Space =>
                            onClick()
                            return true
                        case _ => ()
                    }
                }
            case _ => ()
        }
        false
    }

    public func focusableId(): ?String {
        if (isEnabled) {
            Some(id)
        } else {
            None
        }
    }
}

/**
 * `.icon-btn` — a square icon-only button (ui.css:116-158): 26x26 (sm) / 34x34 (md), radius 8,
 * 1px transparent border, `color: var(--text-muted)`. The Web component always renders
 * `title={label}`; the port shows the same string through CUI's tooltip when `tooltip` is set.
 */
public class IconButtonView <: Widget {
    private let id: String
    private let tokens: ThemeTokens
    private let glyph: IconGlyph
    private let variant: IconButtonVariant
    private let size: ControlSize
    private let tooltip: ?String
    private let isEnabled: Bool
    private let onClick: () -> Unit
    private var frame = Rect.zero()

    public init(
        tokens: ThemeTokens,
        glyph: IconGlyph,
        onClick: () -> Unit,
        variant!: IconButtonVariant = IconButtonVariant.Ghost,
        size!: ControlSize = ControlSize.Md,
        tooltip!: ?String = None,
        enabled!: Bool = true
    ) {
        this.id = focusableControlIdentity("UiIconButton")
        this.tokens = tokens
        this.glyph = glyph
        this.onClick = onClick
        this.variant = variant
        this.size = size
        this.tooltip = tooltip
        this.isEnabled = enabled
        emit(this)
    }

    /** `.icon-btn--sm { width: 26px; height: 26px }` / `--md { 34px }` (ui.css:126-134). */
    private func boxSide(): Float32 {
        match (size) {
            case Sm => 26.0
            case Md => 34.0
        }
    }

    /** Glyph size: 16 for the small box, 18 for the regular one (icons.tsx default). */
    private func glyphSide(): Float32 {
        match (size) {
            case Sm => 16.0
            case Md => 18.0
        }
    }

    public func measure(_: UiContext, available: Size): Size {
        let side = boxSide()
        Size(min(side, max(available.w, 0.0)), min(side, max(available.h, 0.0)))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        let radius = tokens.radius.md
        let hovered = isEnabled && ctx.isHovered(id)
        let pressed = isEnabled && ctx.isPressed(id)
        var fill = TRANSPARENT
        var border = TRANSPARENT
        var tintColor = c.textMuted
        var elevated = false
        match (variant) {
            case Ghost =>
                // .icon-btn--ghost:hover { background: surface-2; color: text } (ui.css:136-139)
                if (hovered || pressed) {
                    fill = c.surface2
                    tintColor = c.text
                }
            case Secondary =>
                // .icon-btn--secondary / :hover (ui.css:141-150)
                fill = c.surface
                border = if (hovered || pressed) {
                    c.borderStrong
                } else {
                    c.border
                }
                tintColor = if (hovered || pressed) {
                    c.text
                } else {
                    c.textMuted
                }
                elevated = true
            case Danger =>
                // .icon-btn--danger / :hover { background: color-mix(danger 12%, transparent) } (ui.css:152-158)
                tintColor = c.danger
                if (hovered || pressed) {
                    fill = tint(c.danger, 12.0)
                }
        }
        if (!isEnabled) {
            fill = withOpacity(fill, 0.55)
            border = withOpacity(border, 0.55)
            tintColor = withOpacity(tintColor, 0.55)
        }
        if (elevated) {
            shadow1(ctx, tokens, frame, radius)
        }
        fillRound(ctx, frame, radius, fill)
        strokeRound(ctx, frame, radius, tokens.metrics.borderWidth, border)
        let side = min(frame.w, min(frame.h, glyphSide()))
        let glyphRect = Rect(frame.centerX() - side / 2.0, frame.centerY() - side / 2.0, side, side)
        paintSpec(ctx, glyph, glyphRect, tintColor)
        if (isEnabled && ctx.showFocusRing(id)) {
            focusRing(ctx, tokens, frame, radius)
        }
        match (tooltip) {
            case Some(text) =>
                if (hovered) {
                    ctx.showTooltip(text, frame)
                }
            case None => ()
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        if (!isEnabled) {
            return false
        }
        match (event) {
            case UiEvent.MouseMove(_, _) => claimHoverIfInside(ctx, event, frame, id, CursorShape.Interactive)
            // `isPrimaryPointerButton` also accepts a backend that cannot name the button
            // (`RawCode(0|1)`); see its doc comment in `ui.cj`.
            case UiEvent.MouseDown(button, x, y) =>
                if (isPrimaryPointerButton(button) && frame.contains(x, y)) {
                    ctx.focus(id, viaKeyboard: false)
                    ctx.press(id)
                    return true
                }
            case UiEvent.MouseUp(button, x, y) =>
                if (isPrimaryPointerButton(button) && ctx.isPressed(id)) {
                    ctx.clearPress()
                    if (frame.contains(x, y)) {
                        onClick()
                        return true
                    }
                }
            case UiEvent.KeyDown(key, isRepeat) =>
                // Button.md: Enter and Space both activate while focused.
                if (ctx.hasFocus(id) && !isRepeat) {
                    match (key) {
                        case Key.Enter | Key.Space =>
                            onClick()
                            return true
                        case _ => ()
                    }
                }
            case _ => ()
        }
        false
    }

    public func focusableId(): ?String {
        if (isEnabled) {
            Some(id)
        } else {
            None
        }
    }
}
