/*
 * Shared "is the system input method attached to the surface?" flag (TEXTURA-CUI-P05).
 *
 * SDL drives the IME through the `SafeImeController` handed to it in EntryAbility.onCreate: it calls
 * attach() when application text input starts (a text control has focus) and hideTextInput() when it
 * stops. CUI starts/stops text input from focus, so this flag is an exact "is a text field focused"
 * signal for the page.
 *
 * The page uses it to decide who owns a key: while the IME is attached, character keys and the
 * Escape/Ctrl keys belong to the system (they already reach SDL natively); while it is detached, the
 * XComponent is not in ArkUI's focus chain, so the page must forward the navigation and shortcut keys
 * itself (see pages/Index.ets).
 */
export class TextInputState {
  static attached: boolean = false;
  /*
   * The `TextConfig` SDL passed to `attach` (TEXTURA-CUI-P06 follow-up).
   *
   * SDL's HarmonyOS backend never implements `SDL_SetTextInputArea` (the openharmony video driver
   * ignores `window->text_input_rect`), so the only way to tell the system IME where the caret is,
   * is `TextConfig.cursorInfo` at attach time. The page keeps the config SDL used and re-attaches
   * with a fresh `cursorInfo` whenever CUI's caret rectangle moves (see pages/Index.ets).
   */
  static config: ESObject | null = null;
  /** Last cursorInfo handed to the IME, so an unchanged caret costs no extra attach. */
  static cursorKey: string = '';
}
