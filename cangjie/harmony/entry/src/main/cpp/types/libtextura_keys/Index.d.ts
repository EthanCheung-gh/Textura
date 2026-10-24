/*
 * The ArkTS-facing surface of libtextura_keys.so (TEXTURA-CUI-P05 + the IME anchor bridge).
 *
 * Two things cross here, both because ArkUI owns the information and CUI needs it:
 *
 *   sendKey       keys ArkUI consumes before the XComponent sees them (today: Tab / arrows /
 *                 Ctrl+letter), forwarded into SDL's event queue.
 *   getImeAnchor  the focused text control's caret rectangle, in logical pixels, read from the
 *                 Cangjie host (`textura_ime_anchor`). SDL has no `SDL_SetTextInputArea`
 *                 implementation on HarmonyOS, so the page passes this to the IME as
 *                 `TextConfig.cursorInfo` and the candidate window follows the field.
 *
 * See entry/src/main/cpp/textura_keys.c.
 */
export const sendKey: (scancode: number, down: boolean, mods: number) => boolean;

/** `[x, y, width, height]` in logical pixels, or null when no text control has a caret. */
export const getImeAnchor: () => number[] | null;
