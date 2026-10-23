/*
 * The only page in the HAP. It exists to give SDL a single XComponent surface:
 * libraryname 'SDL3' makes the system load libSDL3.so, whose initializer registers the NAPI module
 * and takes over the surface. CUI draws the real UI inside this component.
 *
 * Keep this page free of product UI — everything visible is CUI's.
 *
 * Focus handling adapted from PixCap-Cangjie entry/src/main/ets/pages/Index.ets (read-only
 * reference). The reasoning below is kept because losing it re-breaks the keyboard silently.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { KeyCode } from '@kit.InputKit';
import { sendKey } from 'libtextura_keys.so';
import { TextInputState } from '../common/TextInputState';

const DOMAIN: number = 0x0000;
const TAG: string = 'Textura/FOCUS';

/* Must match the XComponent's .id() — FocusController.requestFocus() resolves by id. */
const SURFACE_ID: string = 'SDL_XComponent';

/*
 * Focus convergence schedule: each entry is a delay in ms counted from the *previous* attempt, so
 * the chain requests focus at 0, 80, 320, 920 and 2420 ms after startFocusConvergence() (the
 * delays accumulate: 0, +80, +240, +600, +1500). The first attempt usually runs before the
 * XComponent is on the tree (aboutToAppear fires ahead of the first layout), so requestFocus answers
 * 150003 and the later attempts are the ones that actually land. Bounded on purpose: a retry chain
 * that never ends would fight the system focus manager.
 */
const FOCUS_RETRY_DELAYS_MS: number[] = [0, 80, 240, 600, 1500];

/* SDL_Scancode values (SDL_scancode.h) for the keys this page forwards into SDL. */
const SDL_SCANCODE_A: number = 4;
const SDL_SCANCODE_Z: number = 29;
const SDL_SCANCODE_TAB: number = 43;
const SDL_SCANCODE_RIGHT: number = 79;
const SDL_SCANCODE_LEFT: number = 80;
const SDL_SCANCODE_DOWN: number = 81;
const SDL_SCANCODE_UP: number = 82;

/*
 * WHY THIS PAGE HAS FOCUS CODE (regression guard — read before touching it):
 *
 * ArkUI only delivers hardware key events to the *focused* component, and an XComponent is not
 * focusable by default. Without the configuration below the surface never enters the focus chain and
 * the whole keyboard path stays dead: SDL's HarmonyOS port registers a key callback
 * (OH_NativeXComponent_RegisterKeyEventCallback -> SDL_XComponent_DispatchKeyEventCallback ->
 * SDL_OpenHarmonyDispatchKeyEvent, which maps the OH keycode to an SDL scancode and calls
 * SDL_SendKeyboardKey) but the callback is never invoked. CUI's shortcuts then look "unimplemented"
 * while the handlers were fine all along: delivery was the missing piece.
 *
 * What is required for key delivery, and nothing more:
 *   .focusable(true)     - XComponent is not focusable by default; this opts the node into the
 *                          focus chain (FocusHub), which is the gate for key events.
 *   .defaultFocus(true)  - makes it the page's default focus leaf on first access, so it owns focus
 *                          from the first frame instead of the page root container.
 *   .focusOnTouch(true)  - a tap/click re-focuses the surface.
 *   requestSurfaceFocus()- explicit re-request on appear and on blur, because focus can be lost to
 *                          things this page does not control (window re-activation, system focus
 *                          moving back to the page root). A one-shot defaultFocus is not enough: it
 *                          only applies the first time the page is accessed.
 *
 * ONE exception to "no key handling here", forced by a device measurement: ArkUI consumes Tab for
 * its own focus traversal *before* the XComponent's key callback runs — a Tab injection produced no
 * event on the CUI side at all, while Escape and Ctrl arrived normally. The root therefore forwards
 * Tab (and only Tab) into SDL through the `textura_keys` NAPI bridge and returns true to stop the
 * traversal; every other key is left to ArkUI/SDL. See forwardKeyToSdl() and
 * entry/src/main/cpp/textura_keys.c.
 *
 * Deliberately NOT done here:
 *   - No other key handling in ArkTS. Keys must keep flowing ArkUI -> SDL -> CUI -> Cangjie, which is
 *     exactly what focus unlocks, and character keys must stay with the system input method.
 *   - No FocusController.activate(). Focus activation gates traversal and focus-box painting, not
 *     event routing, and forcing it on would paint the system focus box over the full-screen CUI
 *     surface. If a device run ever shows keys dying after a mouse click, that is the knob to
 *     revisit (activate(true, false)).
 */
@Entry
@Component
struct Index {
  /* Set by onFocus; a pending retry chain stops as soon as the surface really holds focus. */
  private surfaceFocused: boolean = false;
  /* Whether the page forwarded a KeyDown whose KeyUp has not been forwarded yet. */
  private pressedByPage: boolean = false;
  private focusRetryTimer: number = -1;
  private focusRetryAttempt: number = 0;

  aboutToAppear(): void {
    this.startFocusConvergence('appear');
  }

  aboutToDisappear(): void {
    this.cancelFocusRetry();
  }

  /*
   * Start a bounded focus convergence run: walk FOCUS_RETRY_DELAYS_MS, waiting one delay before each
   * attempt, until onFocus reports success or the schedule is exhausted.
   */
  private startFocusConvergence(reason: string): void {
    this.cancelFocusRetry();
    this.focusRetryAttempt = 0;
    hilog.info(DOMAIN, TAG, 'textura-focus converge=%{public}s start', reason);
    this.armFocusRetry(reason);
  }

  /* Schedule the next attempt one delay from now; each call re-arms itself, so the delays are
   * relative and the absolute landing times are their running sum (see the header comment). */
  private armFocusRetry(reason: string): void {
    if (this.focusRetryAttempt >= FOCUS_RETRY_DELAYS_MS.length) {
      hilog.warn(DOMAIN, TAG, 'textura-focus converge=%{public}s exhausted focused=%{public}s',
        reason, this.surfaceFocused ? 'true' : 'false');
      return;
    }
    const delay = FOCUS_RETRY_DELAYS_MS[this.focusRetryAttempt];
    this.focusRetryTimer = setTimeout(() => {
      this.focusRetryTimer = -1;
      if (this.surfaceFocused) {
        return; // onFocus already reported success; stop the chain
      }
      this.requestSurfaceFocus(`${reason}#${this.focusRetryAttempt}`);
      this.focusRetryAttempt += 1;
      this.armFocusRetry(reason);
    }, delay);
  }

  private cancelFocusRetry(): void {
    if (this.focusRetryTimer !== -1) {
      clearTimeout(this.focusRetryTimer);
      this.focusRetryTimer = -1;
    }
  }

  /*
   * Move focus onto the surface now. FocusController.requestFocus is the synchronous transfer (the
   * global focusControl.requestFocus only applies on the next frame) and it throws 150001 (not
   * focusable), 150002 (unfocusable ancestor) or 150003 (not on the tree / does not exist) — the
   * retry schedule is what turns those startup-time answers into a landed focus.
   */
  private requestSurfaceFocus(reason: string): void {
    try {
      this.getUIContext().getFocusController().requestFocus(SURFACE_ID);
      hilog.info(DOMAIN, TAG, 'textura-focus request=%{public}s ok=true', reason);
    } catch (e) {
      const be = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'textura-focus request=%{public}s ok=false err=%{public}d:%{public}s',
        reason, be.code ?? -1, be.message ?? JSON.stringify(e));
    }
  }

  /*
   * Translates an ArkUI key code into the SDL_Scancode SDL3 uses on the wire; -1 means "leave it".
   *
   * Only the keys ArkUI would otherwise keep for itself are mapped: Tab/Shift+Tab (CUI's focus
   * ring), the four arrows (same-layer navigation) and Ctrl/Cmd+letter (global hotkeys).
   *
   * Escape is deliberately NOT mapped. It already reaches CUI through the XComponent's native key
   * callback (measured on device: `ev#3 KeyDown key=Escape`), so forwarding it here delivered the
   * same press twice — one Esc closed the top layer and the duplicate immediately closed/undid the
   * next one. Any key ArkUI lets through must stay out of this table.
   */
  private sdlScancodeFor(keyCode: number): number {
    if (keyCode === KeyCode.KEYCODE_TAB) {
      return SDL_SCANCODE_TAB;
    }
    if (keyCode === KeyCode.KEYCODE_DPAD_UP) {
      return SDL_SCANCODE_UP;
    }
    if (keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
      return SDL_SCANCODE_DOWN;
    }
    if (keyCode === KeyCode.KEYCODE_DPAD_LEFT) {
      return SDL_SCANCODE_LEFT;
    }
    if (keyCode === KeyCode.KEYCODE_DPAD_RIGHT) {
      return SDL_SCANCODE_RIGHT;
    }
    if (keyCode >= KeyCode.KEYCODE_A && keyCode <= KeyCode.KEYCODE_Z) {
      return SDL_SCANCODE_A + (keyCode - KeyCode.KEYCODE_A);
    }
    return -1;
  }

  /*
   * Forwards the keys ArkUI keeps for its own focus traversal into SDL's queue.
   *
   * WHY: an XComponent only receives hardware keys through
   * OH_NativeXComponent_RegisterKeyEventCallback, and ArkUI consumes Tab for focus traversal before
   * that callback can run. On device a Tab injection produced no `ev# KeyDown` line at all, so CUI's
   * focus ring (Tab / Shift+Tab) could not be driven from the keyboard, while Escape and Ctrl reached
   * CUI natively. Everything else is returned unhandled so ArkUI and the IME keep working normally —
   * character keys must stay with the system input method.
   *
   * SDL scancodes are the stable wire format: CUI decodes `Key` from the scancode
   * (cangjie-sdl keyFromScancode), so Tab = 43 and the Shift bit rides in SDL_Keymod.
   */
  private forwardKeyToSdl(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down && event.type !== KeyType.Up) {
      return false;
    }
    // A focused text control owns the keyboard: the IME gets the characters *and* Escape/Ctrl still
    // reach SDL natively in that state, so forwarding would deliver those keys twice.
    if (TextInputState.attached) {
      return false;
    }
    const scancode: number = this.sdlScancodeFor(event.keyCode);
    if (scancode < 0) {
      return false;
    }
    let shift = false;
    let ctrl = false;
    try {
      shift = event.getModifierKeyState !== undefined ? event.getModifierKeyState(['shift']) : false;
      ctrl = event.getModifierKeyState !== undefined ? event.getModifierKeyState(['ctrl']) : false;
    } catch (e) {
      shift = false;
      ctrl = false;
    }
    // A bare letter belongs to the system input method: forwarding it would double-deliver text and
    // could fire the shell's single-letter view shortcuts while the user is typing. Only the
    // modifier combinations (Ctrl/Cmd+K, +N, +Z) are taken over, and those are exactly the ones the
    // IME would otherwise swallow.
    if (scancode >= SDL_SCANCODE_A && scancode <= SDL_SCANCODE_Z && !ctrl) {
      return false;
    }
    // SDL_KMOD_LSHIFT|SDL_KMOD_RSHIFT and SDL_KMOD_LCTRL|SDL_KMOD_RCTRL.
    let mods: number = 0;
    if (shift) {
      mods = mods | 0x0003;
    }
    if (ctrl) {
      mods = mods | 0x00c0;
    }
    // The NAPI export is typed optional by the ArkTS compiler; keep the call explicit so a missing
    // library degrades to "key not forwarded" instead of a crash on the UI thread.
    const forward: ((scancode: number, down: boolean, mods: number) => boolean) | undefined = sendKey;
    let delivered: boolean = false;
    if (forward !== undefined) {
      if (event.type === KeyType.Down) {
        delivered = forward(scancode, true, mods);
        this.pressedByPage = true;
      } else if (this.pressedByPage) {
        // Normal case: the page saw the matching Down and completes the press with the Up.
        delivered = forward(scancode, false, mods);
        this.pressedByPage = false;
      } else {
        // ArkUI consumed the Down for its own focus traversal and only let the Up through (measured
        // on device: every Tab arrived as `ev# KeyUp key=Tab`). Synthesize the whole press so CUI
        // sees the KeyDown its focus ring reacts to.
        delivered = forward(scancode, true, mods);
        const released: boolean = forward !== undefined ? forward(scancode, false, mods) : false;
        delivered = delivered && released;
      }
    }
    if (!delivered) {
      hilog.warn(DOMAIN, TAG, 'textura-key forward=tab delivered=false');
    }
    return true; // consumed: ArkUI must not also move focus
  }

  build() {
    Row() {
      Column() {
        XComponent({ id: SURFACE_ID, type: XComponentType.SURFACE, libraryname: 'SDL3' })
          .id(SURFACE_ID)
          // Keyboard delivery (see the header comment): without these the XComponent is never in
          // the focus chain and SDL's key callback is never called.
          .focusable(true)
          .defaultFocus(true)
          .focusOnTouch(true)
          .onFocus(() => {
            this.surfaceFocused = true;
            this.cancelFocusRetry();
            hilog.info(DOMAIN, TAG, '%{public}s', 'textura-focus event=onFocus');
          })
          .onBlur(() => {
            this.surfaceFocused = false;
            hilog.info(DOMAIN, TAG, '%{public}s', 'textura-focus event=onBlur refocus=true');
            // Focus can be taken away by the system; take it back so keys keep working.
            this.startFocusConvergence('blur');
          })
      }
      .width('100%')
    }
    .height('100%')
    // TEXTURA-CUI-P05 key bridge: key events bubble to this root, which is the only place Tab can be
    // seen before ArkUI's focus traversal consumes it. Returning true stops the traversal, so CUI
    // owns the focus ring; every other key falls through untouched.
    .onKeyEvent((event: KeyEvent) => this.forwardKeyToSdl(event))
  }
}
