package textura.shell

import cui.*
import textura.ui.*

/*
 * `src/app/TopBar.tsx` + `shell.css` `.topbar*`:
 *
 *   `.topbar { height: 56px; padding: 0 24px; gap: 16px; border-bottom: 1px }`
 *   titles row: 16px/650 title + 12px faint subtitle, baseline-aligned, 12px apart
 *   search: `flex: 0 1 320px; min-width: 180` (TopBar.tsx inline style)
 *   one ghost icon button (34x34) toggling sun/moon
 *
 * The 55px content band + 1px rule reproduces the CSS border-bottom inside the 56px box,
 * which is what keeps the reference title baseline at y≈28.
 */

/** Baseline-aligned title/subtitle cluster. */
public class TopBarTitlesView <: Widget {
    private let tokens: ThemeTokens
    private let title: String
    private let subtitle: String
    private var frame = Rect.zero()

    public init(tokens: ThemeTokens, title: String, subtitle: String) {
        this.tokens = tokens
        this.title = title
        this.subtitle = subtitle
        emit(this)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        let titleSize = fpSize(ctx, TOPBAR_TITLE_FONT)
        let subSize = fpSize(ctx, TOPBAR_SUBTITLE_FONT)
        let width = textWidth(ctx, title, titleSize, 650) + TOPBAR_TITLES_GAP + textWidth(ctx, subtitle, subSize, 400)
        Size(min(width, max(available.w, 0.0)), max(available.h, 0.0))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func isFlexible(): Bool {
        false
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        let titleSize = fpSize(ctx, TOPBAR_TITLE_FONT)
        let subSize = fpSize(ctx, TOPBAR_SUBTITLE_FONT)
        // `align-items: baseline`: the 12px run sits on the 16px run's baseline.
        textLeading(ctx, title, frame.x, frame.centerY(), c.text, titleSize, 650)
        let subtitleX = frame.x + textWidth(ctx, title, titleSize, 650) + TOPBAR_TITLES_GAP
        textLeading(ctx, subtitle, subtitleX, frame.centerY() + 1.0, c.textFaint, subSize, 400)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/** `.input` styling for the topbar search (ui.css:181-210) at the measured 37px height. */
func topBarSearchStyle(tokens: ThemeTokens): TextInputStyle {
    let c = tokens.color
    TextInputStyle(
        lineHeight: vp(20.25),
        padding: LengthInsets(Length(10.0, LengthUnit.Vp), Length(7.0, LengthUnit.Vp)),
        textColor: c.text,
        placeholderColor: c.textFaint,
        cursorColor: c.accent,
        surface: SurfaceStyle(c.surface, border: c.border, radius: tokens.radius.md,
            borderWidth: tokens.metrics.borderWidth),
        focusedSurface: SurfaceStyle(c.surface, border: c.accent, radius: tokens.radius.md,
            borderWidth: tokens.metrics.borderWidth)
    )
}

/**
 * Topbar row. `searchText` must be a stable binding (the shell passes the remembered
 * search state); the theme button is a ghost `IconButtonView`.
 */
public func buildTopBar(
    theme: Theme,
    title: String,
    subtitle: String,
    searchText: Bindable<String>,
    themeGlyph: IconGlyph,
    themeTooltip: String,
    onToggleTheme: () -> Unit
): Unit {
    let tokens = tokensOf(theme)
    VStack(spacing: vp(0.0)) {
        HStack(spacing: vp(TOPBAR_GAP), flexible: false) {
            TopBarTitlesView(tokens, title, subtitle).fillHeight()
            Spacer()
            TextField(searchText, key: "shell-search")
                .style(topBarSearchStyle(tokens))
                .placeholder("搜索…")
                .textStyle(TextStyle(fontSize: fp(13.5)))
                .width(TOPBAR_SEARCH_WIDTH)
                .height(37.0)
            IconButtonView(tokens, themeGlyph, onToggleTheme, variant: IconButtonVariant.Ghost,
                size: ControlSize.Md, tooltip: themeTooltip)
        }
            .crossAxisAlignment(CrossAxisAlignment.Center)
            .padding(TOPBAR_PAD_X, 0.0)
            .height(TOPBAR_HEIGHT - CHROME_BORDER)
            .fillWidth()
        Divider().foregroundColor(tokens.color.border)
    }.hug().fillWidth()
}
