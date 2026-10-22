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
 * Deliberately NOT done here:
 *   - No onKeyEvent / key handling in ArkTS. Keys must keep flowing ArkUI -> SDL -> CUI -> Cangjie,
 *     which is exactly what focus unlocks. An ArkTS key handler would swallow them (key events
 *     bubble, and the native callback is what feeds SDL_SendKeyboardKey) and would put product
 *     behaviour in the host page.
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
  }
}
