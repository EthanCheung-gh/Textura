package textura.ui

import cui.*

/*
 * Design tokens — a 1:1 transcription of the Web build's `src/styles/tokens.css`.
 *
 * Every CSS custom property becomes one strongly typed field; nothing in `textura.ui`,
 * `textura.shell` or `textura.views.*` may invent a colour or a spacing value. The Web
 * cascade chooses light/dark through `html[data-theme]`, so the port keeps two immutable
 * `ThemeTokens` values (`ThemeTokens.light()` / `ThemeTokens.dark()`) instead of a mutable
 * global. Views resolve the active set with `tokensOf(theme)`.
 *
 * Accessors mirror the CSS names: `--space-2` -> `tk.space.s2`, `--radius-md` ->
 * `tk.radius.md`, `--surface` -> `tk.color.surface`.
 */

/** Colour roles from `tokens.css` (light block lines 8-38, dark block lines 66-95). */
public struct TokenColors {
    // --bg / --bg-subtle / --surface / --surface-2 (tokens.css:8-11, 66-69)
    public let bg: Color
    public let bgSubtle: Color
    public let surface: Color
    public let surface2: Color
    // --border / --border-strong (tokens.css:12-13, 70-71)
    public let border: Color
    public let borderStrong: Color
    // --text / --text-muted / --text-faint (tokens.css:14-17, 72-75)
    public let text: Color
    public let textMuted: Color
    public let textFaint: Color
    // --accent / --accent-soft (tokens.css:18-19, 76-77)
    public let accent: Color
    public let accentSoft: Color
    // --accent-strong (+ hover / active / disabled) (tokens.css:21-24, 78-81)
    public let accentStrong: Color
    public let accentStrongHover: Color
    public let accentStrongActive: Color
    public let accentStrongDisabled: Color
    // --danger-strong (+ hover / active / disabled) (tokens.css:25-28, 82-85)
    public let dangerStrong: Color
    public let dangerStrongHover: Color
    public let dangerStrongActive: Color
    public let dangerStrongDisabled: Color
    // --text-on-strong (tokens.css:29, 86)
    public let textOnStrong: Color
    // --accent-ink / --ok-ink / --warn-ink / --danger-ink / --info-ink (tokens.css:30-34, 87-91)
    public let accentInk: Color
    public let okInk: Color
    public let warnInk: Color
    public let dangerInk: Color
    public let infoInk: Color
    // --ok / --warn / --danger / --info (tokens.css:35-38, 92-95)
    public let ok: Color
    public let warn: Color
    public let danger: Color
    public let info: Color

    public init(
        bg!: Color,
        bgSubtle!: Color,
        surface!: Color,
        surface2!: Color,
        border!: Color,
        borderStrong!: Color,
        text!: Color,
        textMuted!: Color,
        textFaint!: Color,
        accent!: Color,
        accentSoft!: Color,
        accentStrong!: Color,
        accentStrongHover!: Color,
        accentStrongActive!: Color,
        accentStrongDisabled!: Color,
        dangerStrong!: Color,
        dangerStrongHover!: Color,
        dangerStrongActive!: Color,
        dangerStrongDisabled!: Color,
        textOnStrong!: Color,
        accentInk!: Color,
        okInk!: Color,
        warnInk!: Color,
        dangerInk!: Color,
        infoInk!: Color,
        ok!: Color,
        warn!: Color,
        danger!: Color,
        info!: Color
    ) {
        this.bg = bg
        this.bgSubtle = bgSubtle
        this.surface = surface
        this.surface2 = surface2
        this.border = border
        this.borderStrong = borderStrong
        this.text = text
        this.textMuted = textMuted
        this.textFaint = textFaint
        this.accent = accent
        this.accentSoft = accentSoft
        this.accentStrong = accentStrong
        this.accentStrongHover = accentStrongHover
        this.accentStrongActive = accentStrongActive
        this.accentStrongDisabled = accentStrongDisabled
        this.dangerStrong = dangerStrong
        this.dangerStrongHover = dangerStrongHover
        this.dangerStrongActive = dangerStrongActive
        this.dangerStrongDisabled = dangerStrongDisabled
        this.textOnStrong = textOnStrong
        this.accentInk = accentInk
        this.okInk = okInk
        this.warnInk = warnInk
        this.dangerInk = dangerInk
        this.infoInk = infoInk
        this.ok = ok
        this.warn = warn
        this.danger = danger
        this.info = info
    }
}

/** `--radius-sm|md|lg` (tokens.css:40-42) — logical pixels. */
public struct TokenRadii {
    public let sm: Float32
    public let md: Float32
    public let lg: Float32

    public init(sm!: Float32, md!: Float32, lg!: Float32) {
        this.sm = sm
        this.md = md
        this.lg = lg
    }
}

/** `--space-1..6` (tokens.css:47-52) — logical pixels. */
public struct TokenSpace {
    public let s1: Float32
    public let s2: Float32
    public let s3: Float32
    public let s4: Float32
    public let s5: Float32
    public let s6: Float32

    public init(s1!: Float32, s2!: Float32, s3!: Float32, s4!: Float32, s5!: Float32, s6!: Float32) {
        this.s1 = s1
        this.s2 = s2
        this.s3 = s3
        this.s4 = s4
        this.s5 = s5
        this.s6 = s6
    }
}

/** Non-colour layout constants from `tokens.css:58-60` plus the focus-ring geometry. */
public struct TokenMetrics {
    /** `--sidebar-width: 240px`. */
    public let sidebarWidth: Float32
    /** `--topbar-height: 56px`. */
    public let topbarHeight: Float32
    /**
     * `--focus-ring: 0 0 0 2px var(--surface), 0 0 0 4px var(--accent)` measured as the
     * thickness of the visible accent band (the 2px surface band is just a gap).
     */
    public let focusRingWidth: Float32
    /** Distance from the element's border box to the start of the accent band. */
    public let focusRingGap: Float32
    /** `border: 1px` everywhere in `ui.css` / `base.css`. */
    public let borderWidth: Float32

    public init(
        sidebarWidth!: Float32,
        topbarHeight!: Float32,
        focusRingWidth!: Float32,
        focusRingGap!: Float32,
        borderWidth!: Float32
    ) {
        this.sidebarWidth = sidebarWidth
        this.topbarHeight = topbarHeight
        this.focusRingWidth = focusRingWidth
        this.focusRingGap = focusRingGap
        this.borderWidth = borderWidth
    }
}

/**
 * One CSS box-shadow layer. CUI draws no arbitrary multi-stop shadow, so `textura.ui`
 * reproduces `--shadow-1` / `--shadow-2` with `Renderer.fillRoundedRectSoft` using these
 * numbers (see `paint.cj`).
 */
public struct TokenShadow {
    public let offsetX: Float32
    public let offsetY: Float32
    public let blur: Float32
    public let spread: Float32
    public let color: Color

    public init(offsetX!: Float32, offsetY!: Float32, blur!: Float32, spread!: Float32, color!: Color) {
        this.offsetX = offsetX
        this.offsetY = offsetY
        this.blur = blur
        this.spread = spread
        this.color = color
    }
}

/**
 * The whole design system: colours, geometry, spacing and elevation for one theme.
 * `light()` and `dark()` are the only constructors views need.
 */
public struct ThemeTokens {
    public let name: String
    public let isDark: Bool
    public let color: TokenColors
    public let radius: TokenRadii
    public let space: TokenSpace
    public let metrics: TokenMetrics
    /** `--shadow-1` first layer: `0 1px 2px rgba(36, 32, 28, 0.06)` (tokens.css:44 / 97). */
    public let shadow1: TokenShadow
    /** `--shadow-1` second layer: `0 1px 0 rgba(36, 32, 28, 0.03)` (contact line). */
    public let shadow1Contact: TokenShadow
    /** `--shadow-2`: `0 10px 28px rgba(36, 32, 28, 0.14)` (tokens.css:45) / dark `0 12px 32px rgba(0, 0, 0, 0.5)`. */
    public let shadow2: TokenShadow

    public init(
        name: String,
        isDark: Bool,
        color: TokenColors,
        radius: TokenRadii,
        space: TokenSpace,
        metrics: TokenMetrics,
        shadow1: TokenShadow,
        shadow1Contact: TokenShadow,
        shadow2: TokenShadow
    ) {
        this.name = name
        this.isDark = isDark
        this.color = color
        this.radius = radius
        this.space = space
        this.metrics = metrics
        this.shadow1 = shadow1
        this.shadow1Contact = shadow1Contact
        this.shadow2 = shadow2
    }

    /** Warm-paper light theme — `tokens.css:5-61`. */
    public static func light(): ThemeTokens {
        ThemeTokens(
            "light",
            false,
            TokenColors(
                bg: Color.rgb(246, 242, 236),
                bgSubtle: Color.rgb(239, 233, 224),
                surface: Color.rgb(255, 252, 247),
                surface2: Color.rgb(244, 238, 230),
                border: Color.rgb(227, 218, 206),
                borderStrong: Color.rgb(207, 195, 179),
                text: Color.rgb(36, 32, 28),
                textMuted: Color.rgb(106, 96, 87),
                textFaint: Color.rgb(111, 102, 92),
                accent: Color.rgb(192, 102, 58),
                accentSoft: Color.rgb(244, 226, 214),
                accentStrong: Color.rgb(176, 90, 50),
                accentStrongHover: Color.rgb(168, 84, 44),
                accentStrongActive: Color.rgb(158, 74, 37),
                accentStrongDisabled: Color.rgb(128, 112, 101),
                dangerStrong: Color.rgb(168, 69, 58),
                dangerStrongHover: Color.rgb(146, 58, 48),
                dangerStrongActive: Color.rgb(127, 50, 42),
                dangerStrongDisabled: Color.rgb(138, 107, 100),
                textOnStrong: Color.rgb(255, 250, 245),
                accentInk: Color.rgb(143, 69, 35),
                okInk: Color.rgb(63, 101, 66),
                warnInk: Color.rgb(125, 85, 22),
                dangerInk: Color.rgb(143, 55, 46),
                infoInk: Color.rgb(60, 92, 120),
                ok: Color.rgb(79, 122, 82),
                warn: Color.rgb(168, 118, 42),
                danger: Color.rgb(168, 69, 58),
                info: Color.rgb(74, 111, 143)
            ),
            TokenRadii(sm: 4.0, md: 8.0, lg: 14.0),
            TokenSpace(s1: 4.0, s2: 8.0, s3: 12.0, s4: 16.0, s5: 24.0, s6: 32.0),
            TokenMetrics(sidebarWidth: 240.0, topbarHeight: 56.0, focusRingWidth: 2.0, focusRingGap: 2.0, borderWidth: 1.0),
            TokenShadow(offsetX: 0.0, offsetY: 1.0, blur: 2.0, spread: 0.0, color: Color.rgba(36, 32, 28, 15)),
            TokenShadow(offsetX: 0.0, offsetY: 1.0, blur: 0.0, spread: 0.0, color: Color.rgba(36, 32, 28, 8)),
            TokenShadow(offsetX: 0.0, offsetY: 10.0, blur: 28.0, spread: 0.0, color: Color.rgba(36, 32, 28, 36))
        )
    }

    /** Ink-on-charcoal dark theme — `tokens.css:63-101`. */
    public static func dark(): ThemeTokens {
        ThemeTokens(
            "dark",
            true,
            TokenColors(
                bg: Color.rgb(27, 24, 21),
                bgSubtle: Color.rgb(33, 29, 25),
                surface: Color.rgb(38, 34, 30),
                surface2: Color.rgb(47, 42, 37),
                border: Color.rgb(58, 52, 45),
                borderStrong: Color.rgb(76, 68, 59),
                text: Color.rgb(236, 228, 218),
                textMuted: Color.rgb(179, 168, 155),
                textFaint: Color.rgb(160, 149, 138),
                accent: Color.rgb(217, 122, 76),
                accentSoft: Color.rgb(59, 42, 34),
                accentStrong: Color.rgb(176, 90, 50),
                accentStrongHover: Color.rgb(168, 84, 44),
                accentStrongActive: Color.rgb(158, 74, 37),
                accentStrongDisabled: Color.rgb(128, 112, 101),
                dangerStrong: Color.rgb(182, 76, 65),
                dangerStrongHover: Color.rgb(168, 69, 58),
                dangerStrongActive: Color.rgb(154, 61, 52),
                dangerStrongDisabled: Color.rgb(138, 107, 100),
                textOnStrong: Color.rgb(255, 250, 245),
                accentInk: Color.rgb(231, 163, 124),
                okInk: Color.rgb(151, 192, 154),
                warnInk: Color.rgb(227, 185, 117),
                dangerInk: Color.rgb(229, 154, 143),
                infoInk: Color.rgb(163, 195, 221),
                ok: Color.rgb(123, 166, 126),
                warn: Color.rgb(210, 164, 92),
                danger: Color.rgb(208, 115, 102),
                info: Color.rgb(127, 164, 196)
            ),
            TokenRadii(sm: 4.0, md: 8.0, lg: 14.0),
            TokenSpace(s1: 4.0, s2: 8.0, s3: 12.0, s4: 16.0, s5: 24.0, s6: 32.0),
            TokenMetrics(sidebarWidth: 240.0, topbarHeight: 56.0, focusRingWidth: 2.0, focusRingGap: 2.0, borderWidth: 1.0),
            TokenShadow(offsetX: 0.0, offsetY: 1.0, blur: 2.0, spread: 0.0, color: Color.rgba(0, 0, 0, 102)),
            TokenShadow(offsetX: 0.0, offsetY: 1.0, blur: 0.0, spread: 0.0, color: Color.rgba(0, 0, 0, 51)),
            TokenShadow(offsetX: 0.0, offsetY: 12.0, blur: 32.0, spread: 0.0, color: Color.rgba(0, 0, 0, 128))
        )
    }

    /**
     * The CUI `Theme` for this token set. CUI's theme roles are a subset of Textura's
     * tokens; the mapping keeps CUI built-ins (Panel, Label, Divider, TextField) on the
     * same palette as the ported controls.
     */
    public func theme(): Theme {
        Theme(
            bg: color.bg,
            panel: color.surface,
            panelEdge: color.border,
            text: color.text,
            mutedText: color.textMuted,
            accent: color.accent,
            accentText: color.textOnStrong,
            danger: color.danger,
            field: color.surface2,
            fieldActive: color.surface,
            panelRaised: color.surface,
            accentSoft: color.accentSoft,
            shadow: shadow2.color,
            radius: radius.lg,
            smallRadius: radius.sm,
            controlRadius: radius.md,
            borderWidth: metrics.borderWidth
        )
    }
}

/** Warm-paper light theme (#f6f2ec) — the frozen public entry point. */
public func texturaLight(): Theme {
    ThemeTokens.light().theme()
}

/** Ink-on-charcoal dark theme — the frozen public entry point. */
public func texturaDark(): Theme {
    ThemeTokens.dark().theme()
}

/** Channel-wise colour equality (`Color` has no `==` operator in CUI 0.9.6). */
public func sameColor(left: Color, right: Color): Bool {
    left.r == right.r && left.g == right.g && left.b == right.b && left.a == right.a
}

/** Light token set. */
public func lightTokens(): ThemeTokens {
    ThemeTokens.light()
}

/** Dark token set. */
public func darkTokens(): ThemeTokens {
    ThemeTokens.dark()
}

/**
 * Resolves the token set for a CUI `Theme`.
 *
 * `Theme` is immutable and carries no name, so a reverse lookup can only guess. Two rules keep
 * that guess safe:
 *
 * 1. `explicit` wins outright. Any caller that already holds the `ThemeTokens` (views receive
 *    them from `ViewContext`, `kit_demo` builds them per column) must pass them here — that is
 *    the authoritative path, and the only one that stays correct for a recoloured theme.
 * 2. Without `explicit`, a theme is recognised as Textura only when *four* roles match a known
 *    palette (`bg`, `panel`, `mutedText`, `accent`). A theme that merely shares `bg` with the
 *    Light set but tweaks the accent is therefore not mis-tagged; it falls through to the
 *    luminance fallback, which simply picks the closer of the two palettes.
 *
 * The fallback exists for CUI's built-in `Theme.light()` / `Theme.dark()` (used by isolated
 * widgets and tests). It is a heuristic, not a contract: code that cares about exactness passes
 * `explicit` (or uses the `*View(tokens, ...)` constructors directly).
 */
public func tokensOf(theme: Theme, explicit!: ?ThemeTokens = None): ThemeTokens {
    match (explicit) {
        case Some(tokens) => return tokens
        case None => ()
    }
    let light = ThemeTokens.light()
    let dark = ThemeTokens.dark()
    if (themeMatches(light, theme)) {
        return light
    }
    if (themeMatches(dark, theme)) {
        return dark
    }
    // Foreign palette: pick by perceived luminance (Rec. 601 weights, integer maths).
    let luminance = Int64(theme.bg.r) * 299 + Int64(theme.bg.g) * 587 + Int64(theme.bg.b) * 114
    if (luminance < 128 * 1000) {
        return dark
    }
    light
}

/** True when `theme` is exactly a Textura palette (four roles must all agree). */
private func themeMatches(tokens: ThemeTokens, theme: Theme): Bool {
    sameColor(theme.bg, tokens.color.bg) &&
    sameColor(theme.panel, tokens.color.surface) &&
    sameColor(theme.mutedText, tokens.color.textMuted) &&
    sameColor(theme.accent, tokens.color.accent)
}

// ---------------------------------------------------------------------------
// Legacy flat constants. They are kept so existing call sites keep compiling; new
// code must use `ThemeTokens`. Each value is the corresponding light-theme token.
// ---------------------------------------------------------------------------

public let PAPER: Color = ThemeTokens.light().color.bg
public let PAPER_SUBTLE: Color = ThemeTokens.light().color.bgSubtle
public let SURFACE: Color = ThemeTokens.light().color.surface
public let SURFACE_2: Color = ThemeTokens.light().color.surface2
public let BORDER: Color = ThemeTokens.light().color.border
public let BORDER_STRONG: Color = ThemeTokens.light().color.borderStrong
public let INK: Color = ThemeTokens.light().color.text
public let INK_MUTED: Color = ThemeTokens.light().color.textMuted
public let ACCENT: Color = ThemeTokens.light().color.accent
public let ACCENT_SOFT: Color = ThemeTokens.light().color.accentSoft
public let DANGER: Color = ThemeTokens.light().color.danger
public let ON_ACCENT: Color = ThemeTokens.light().color.textOnStrong

public let DARK_BG: Color = ThemeTokens.dark().color.bg
public let DARK_BG_SUBTLE: Color = ThemeTokens.dark().color.bgSubtle
public let DARK_SURFACE: Color = ThemeTokens.dark().color.surface
public let DARK_SURFACE_2: Color = ThemeTokens.dark().color.surface2
public let DARK_BORDER: Color = ThemeTokens.dark().color.border
public let DARK_INK: Color = ThemeTokens.dark().color.text
public let DARK_INK_MUTED: Color = ThemeTokens.dark().color.textMuted
public let DARK_ACCENT: Color = ThemeTokens.dark().color.accent
public let DARK_ACCENT_SOFT: Color = ThemeTokens.dark().color.accentSoft
