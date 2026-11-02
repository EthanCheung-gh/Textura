/*
 * The ArkTS-facing surface of libtextura_keys.so (TEXTURA-CUI-P05, the IME anchor bridge and the
 * surface/density push).
 *
 * Four things cross here, all because ArkUI owns the information and CUI/SDL need it:
 *
 *   sendKey            keys ArkUI consumes before the XComponent sees them (today: Tab / arrows /
 *                      Ctrl+letter), forwarded into SDL's event queue.
 *   getImeAnchor       the focused text control's caret rectangle, in logical pixels, read from the
 *                      Cangjie host (`textura_ime_anchor`). SDL has no `SDL_SetTextInputArea`
 *                      implementation on HarmonyOS, so the page passes this to the IME as
 *                      `TextConfig.cursorInfo` and the candidate window follows the field.
 *   setSurfaceSize     the XComponent's visible size in pixels. The openharmony video backend keeps
 *                      the size it adopted at window creation, so maximising the window left the
 *                      shell laid out for the launch size (docs/DEVICE-NOTES.md §24).
 *   setDisplayDensity  `display.getDefaultDisplaySync().densityPixels`; the backend reports 1.0
 *                      whatever the panel is, so the page supplies the real factor.
 *
 * See entry/src/main/cpp/textura_keys.c.
 */
export const sendKey: (scancode: number, down: boolean, mods: number) => boolean;

/** `[x, y, width, height]` in logical pixels, or null when no text control has a caret. */
export const getImeAnchor: () => number[] | null;

/**
 * Pushes the surface size the page measured, in **pixels** (vp × density, not vp).
 * Returns whether the host accepted the request; the page debounces and ignores a `false`.
 */
export const setSurfaceSize: (pixelWidth: number, pixelHeight: number) => boolean;

/**
 * Pushes the display's `densityPixels` (1.0 = 1x panel). Returns whether the host accepted it.
 */
export const setDisplayDensity: (density: number) => boolean;
