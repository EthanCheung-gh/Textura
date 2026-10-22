package textura.ui

import cui.*

/*
 * Font registration and the type scale.
 *
 * The Web build uses `--font-ui` (system UI stack) and `--font-mono`; on the parity host the
 * UI stack resolves to Noto Sans CJK SC. The port registers two stable family names so that
 * views never depend on fontconfig ordering:
 *
 *   - `Textura UI`   -> /usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc, faceIndex 2 (SC)
 *                       plus Bold/Medium/DemiLight faces for CSS weights 600+/550/350.
 *   - `Textura Mono` -> /usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf
 *                       with the CJK face as fallback, so mixed CJK/code text has no tofu.
 *
 * Font sizes below mirror `src/styles/base.css` and `src/ui/ui.css` px values 1:1; they are
 * emitted as `fp` so user font scaling still applies.
 */

/** Registered UI family name. Parity target: Noto Sans CJK SC. */
public let FONT_UI: String = "Textura UI"
/** Registered monospace family name. */
public let FONT_MONO: String = "Textura Mono"
/** Family the Web build's `--font-ui` resolves to on the parity host. */
public let FONT_UI_PARITY: String = "Noto Sans CJK SC"

/** Noto Sans CJK collection; face 2 is the Simplified Chinese face (0 JP, 1 KR, 2 SC, 3 TC, 4 HK). */
public let UI_FONT_PATH: String = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
public let UI_FONT_BOLD_PATH: String = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
public let UI_FONT_MEDIUM_PATH: String = "/usr/share/fonts/opentype/noto/NotoSansCJK-Medium.ttc"
public let UI_FONT_DEMILIGHT_PATH: String = "/usr/share/fonts/opentype/noto/NotoSansCJK-DemiLight.ttc"
public let UI_FONT_FACE_INDEX: Int64 = 2

/** System monospace face used for `--font-mono`; falls back to the CJK face for Han glyphs. */
public let MONO_FONT_PATH: String = "/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf"

/**
 * Type scale in logical pixels, transcribed from CSS.
 *
 * Every entry names the CSS rule it comes from so a reviewer can diff the two tables.
 */
public struct TextSize {
    /** `base.css:41` h1 `font-size: 20px`. */
    public static let display: Float32 = 20.0
    /** `base.css:47` h2 `font-size: 16px`. */
    public static let heading: Float32 = 16.0
    /** `ui.css:493` `.modal-title` `font-size: 15px`. */
    public static let subheading: Float32 = 15.0
    /** `base.css:14` html base `14px`; also `base.css:54` h3, `ui.css:389` `.empty-state-title`. */
    public static let body: Float32 = 14.0
    /** `ui.css:28` `.btn--md` and `ui.css:189` `.input`. */
    public static let bodyCompact: Float32 = 13.5
    /** `ui.css:22` `.btn--sm`, `ui.css:396` `.empty-state-description`, `ui.css:498` `.modal-description`. */
    public static let controlSmall: Float32 = 12.5
    /** `ui.css:169` `.field-label`, `ui.css:421` `.segmented-item`. */
    public static let label: Float32 = 12.0
    /** `ui.css:229` `.field-hint`, `ui.css:234` `.field-error`. */
    public static let caption: Float32 = 11.5
    /** `ui.css:249` `.badge`, `ui.css:353` `.progress-label`. */
    public static let micro: Float32 = 11.0
}

/** Family name for UI text (`--font-ui`). */
public func fontUi(): String {
    FONT_UI
}

/** Family name for monospace text (`--font-mono`, `.mono`). */
public func fontMono(): String {
    FONT_MONO
}

/**
 * Registers `Textura UI` / `Textura Mono`. Safe to call before any window exists; it only
 * records the mapping (CUI resolves families through fontconfig on first use).
 *
 * Missing optional faces are skipped: `Fonts.registerFamily` is forgiving about a path that
 * cannot be opened, and the regular face alone still renders every glyph.
 */
public func registerTexturaFonts(): Unit {
    Fonts.registerFamily(
        FONT_UI,
        FontFamily(
            FontSource(UI_FONT_PATH, faceIndex: UI_FONT_FACE_INDEX),
            bold: FontSource(UI_FONT_BOLD_PATH, faceIndex: UI_FONT_FACE_INDEX),
            fallbacks: [FontSource(UI_FONT_PATH, faceIndex: 1)],
            faces: [
                FontFaceDefinition(
                    FontSource(UI_FONT_MEDIUM_PATH, faceIndex: UI_FONT_FACE_INDEX),
                    weight: FontWeight(500)
                ),
                FontFaceDefinition(
                    FontSource(UI_FONT_DEMILIGHT_PATH, faceIndex: UI_FONT_FACE_INDEX),
                    weight: FontWeight(350)
                )
            ]
        )
    )
    Fonts.registerFamily(
        FONT_MONO,
        FontFamily(
            FontSource(MONO_FONT_PATH),
            fallbacks: [FontSource(UI_FONT_PATH, faceIndex: UI_FONT_FACE_INDEX)]
        )
    )
}

/**
 * Called by `main.cj` before `DesktopApp` is created. `fontName` keeps the parity contract
 * (`--font` defaults to `Noto Sans CJK SC`); the Textura families are registered first so a
 * view can opt into them by name.
 */
public func configureFonts(fontName: String): Unit {
    registerTexturaFonts()
    Fonts.setDefault(fontName)
}

/** Sets the default UI family to `Textura UI` (for interactive runs, not parity snapshots). */
public func configureTexturaFonts(): Unit {
    registerTexturaFonts()
    Fonts.setDefault(FONT_UI)
}
