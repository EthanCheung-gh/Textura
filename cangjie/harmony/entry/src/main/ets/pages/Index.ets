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
import { inputMethod } from '@kit.IMEKit';
import { display, window } from '@kit.ArkUI';
import { sendKey, getImeAnchor, setSurfaceSize, setDisplayDensity } from 'libtextura_keys.so';
import { TextInputState } from '../common/TextInputState';

const DOMAIN: number = 0x0000;
const TAG: string = 'Textura/FOCUS';

/* Must match the XComponent's .id() — FocusController.requestFocus() resolves by id. */
const SURFACE_ID: string = 'SDL_XComponent';

/*
 * Surface push debounce (docs/DEVICE-NOTES.md §24).
 *
 * `onAreaChange` fires on every layout pass — a resize during a window drag can produce dozens of
 * them — and each accepted push resizes the SDL window, which sends a resize event and re-lays the
 * page out. 32ms (two frames at 60Hz) coalesces a burst into one push without a visible lag, and the
 * identical-size check in front of it makes a repeat free.
 */
const SURFACE_PUSH_DEBOUNCE_MS: number = 32;

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
 * IME caret sync period. HarmonyOS takes the caret position only as `TextConfig.cursorInfo` at
 * attach time (there is no "move the candidate window" call), so following the caret means
 * re-attaching while the rectangle changes. 120ms is fast enough to look continuous and slow
 * enough that an unchanged caret costs nothing (the rectangle is compared first).
 */
const IME_ANCHOR_TICK_MS: number = 120;

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
 * The other thing this page does is *measure*: ArkUI owns the XComponent, so `onAreaChange` is the only
 * place that knows how big the surface really is, and the openharmony video backend never adopts a
 * size change on its own. The measured size (vp -> px) and `densityPixels` are pushed into the host
 * through the same NAPI module (onSurfaceAreaChanged / pushDisplayDensity, docs/DEVICE-NOTES.md §24).
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
  /* IME caret bridge (see syncImeAnchor): timer, cached controller and window geometry. */
  private imeTimer: number = -1;
  private imeController: inputMethod.InputMethodController | null = null;
  private densityPixels: number = 1;
  private windowLeft: number = 0;
  private windowTop: number = 0;
  /* Last surface layout the page measured, in vp; -1 until the first onAreaChange. */
  private areaWidthVp: number = -1;
  private areaHeightVp: number = -1;
  /* Pending and last accepted push, in pixels (see pushSurfaceSize). */
  private pendingWidthPx: number = -1;
  private pendingHeightPx: number = -1;
  private pushedWidthPx: number = -1;
  private pushedHeightPx: number = -1;
  private pushedDensity: number = -1;
  private surfacePushTimer: number = -1;

  aboutToAppear(): void {
    this.startFocusConvergence('appear');
    this.startImeAnchorSync();
    // Ahead of the first frame: the host applies the pushed density when it creates its SDL window,
    // so the very first frame is already laid out for this screen instead of 1x (docs §24.3).
    this.pushDisplayDensity();
  }

  aboutToDisappear(): void {
    this.cancelFocusRetry();
    this.stopImeAnchorSync();
    if (this.surfacePushTimer !== -1) {
      clearTimeout(this.surfacePushTimer);
      this.surfacePushTimer = -1;
    }
  }

  /*
   * Surface size + display density push (docs/DEVICE-NOTES.md §24).
   *
   * WHY the page has to do this: ArkUI owns the XComponent, and SDL's openharmony video backend keeps
   * the size it adopted when the window was created. Maximising the window changed the ArkUI layout
   * while `SDL_GetWindowSize` kept answering the launch size (1930x1020), so CUI laid the whole shell
   * out for 1930x1020 in the top-left of a 2880x1620 window — background everywhere else (§19.6).
   *
   * Two values, one path:
   *   - the XComponent's laid-out area, converted vp -> px (SDL counts pixels on this backend);
   *   - `display.getDefaultDisplaySync().densityPixels`, which the backend under-reports as 1.0, so
   *     the host installs it as the window's content scale and the dp layout is rasterized at the
   *     panel's real density (§24.3).
   *
   * The NAPI calls only store the numbers in the Cangjie host; the host applies them to SDL from its
   * frame thread. Calling SDL from this thread would race SDL's event pump.
   */
  private onSurfaceAreaChanged(area: Area): void {
    const widthVp: number = Number(area.width);
    const heightVp: number = Number(area.height);
    // A teardown-time layout can report 0x0; resizing the window to nothing would collapse the UI.
    if (!(widthVp > 0) || !(heightVp > 0)) {
      return;
    }
    // Layout passes that do not change the surface (a sibling repaint, a theme flip) cost nothing.
    if (widthVp === this.areaWidthVp && heightVp === this.areaHeightVp) {
      return;
    }
    this.areaWidthVp = widthVp;
    this.areaHeightVp = heightVp;
    this.pendingWidthPx = Math.round(this.getUIContext().vp2px(widthVp));
    this.pendingHeightPx = Math.round(this.getUIContext().vp2px(heightVp));
    hilog.info(DOMAIN, TAG, 'textura-size area vp=%{public}dx%{public}d px=%{public}dx%{public}d',
      Math.round(widthVp), Math.round(heightVp), this.pendingWidthPx, this.pendingHeightPx);
    this.armSurfacePush();
  }

  /* (Re)starts the 32ms window: a burst of layout passes ends in exactly one push. */
  private armSurfacePush(): void {
    if (this.surfacePushTimer !== -1) {
      clearTimeout(this.surfacePushTimer);
    }
    this.surfacePushTimer = setTimeout(() => {
      this.surfacePushTimer = -1;
      this.pushSurfaceSize();
    }, SURFACE_PUSH_DEBOUNCE_MS);
  }

  private pushSurfaceSize(): void {
    // Density first: the host converts the pixel size with whatever density is in force.
    this.pushDisplayDensity();
    const width: number = this.pendingWidthPx;
    const height: number = this.pendingHeightPx;
    if (width <= 0 || height <= 0) {
      return;
    }
    if (width === this.pushedWidthPx && height === this.pushedHeightPx) {
      return;
    }
    const push: ((pixelWidth: number, pixelHeight: number) => boolean) | undefined = setSurfaceSize;
    if (push === undefined) {
      return;
    }
    let accepted: boolean = false;
    try {
      accepted = push(width, height);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'textura-size push failed (ignored)');
      return;
    }
    // Only a push the host accepted is remembered; a rejected one is retried on the next layout
    // change instead of being assumed applied.
    if (accepted) {
      this.pushedWidthPx = width;
      this.pushedHeightPx = height;
    }
    hilog.info(DOMAIN, TAG, 'textura-size push px=%{public}dx%{public}d accepted=%{public}s',
      width, height, accepted ? 'true' : 'false');
  }

  /*
   * Pushes `densityPixels` when it differs from the last accepted value. 1x panels keep 1.0, which is
   * exactly what the desktop build reports, so the 1440x900 parity baseline is untouched.
   */
  private pushDisplayDensity(): void {
    let density: number = this.densityPixels;
    try {
      density = display.getDefaultDisplaySync().densityPixels;
      this.densityPixels = density;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'textura-density unavailable, keeping %{public}s', density.toFixed(3));
    }
    if (!(density > 0)) {
      return;
    }
    if (this.pushedDensity > 0 && Math.abs(density - this.pushedDensity) < 0.0005) {
      return;
    }
    const push: ((value: number) => boolean) | undefined = setDisplayDensity;
    if (push === undefined) {
      return;
    }
    let accepted: boolean = false;
    try {
      accepted = push(density);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'textura-density push failed (ignored)');
      return;
    }
    if (accepted) {
      this.pushedDensity = density;
    }
    hilog.info(DOMAIN, TAG, 'textura-density push density=%{public}s accepted=%{public}s',
      density.toFixed(3), accepted ? 'true' : 'false');
  }

  /*
   * IME candidate-window anchoring (docs/DEVICE-NOTES.md §21).
   *
   * The system IME positions its candidate bar from `TextConfig.cursorInfo`, "absolute coordinate of
   * the physical screen, unit is px". SDL cannot supply it: the openharmony video backend has no
   * `SetTextInputArea` implementation, so `SDL_SetTextInputArea` — which CUI calls on every caret
   * move — is a no-op here and the bar stayed wherever the system decided.
   *
   * CUI still computes the right rectangle every frame (`UiContext.textInputAnchorRect`), the host
   * republishes it as `textura_ime_anchor(index)` and this page polls it through the NAPI module,
   * converts logical px to screen px (window origin + display density) and re-attaches the IME with
   * the same `inputAttribute` SDL used. Unchanged rectangles are skipped, so an idle field is free.
   */
  private startImeAnchorSync(): void {
    this.resolveWindowGeometry();
    this.imeTimer = setInterval(() => this.syncImeAnchor(), IME_ANCHOR_TICK_MS);
  }

  private stopImeAnchorSync(): void {
    if (this.imeTimer !== -1) {
      clearInterval(this.imeTimer);
      this.imeTimer = -1;
    }
  }

  /* One-shot: the caret rectangle is window-relative, the IME wants screen-relative px. */
  private async resolveWindowGeometry(): Promise<void> {
    try {
      this.densityPixels = display.getDefaultDisplaySync().densityPixels;
    } catch (e) {
      this.densityPixels = 1;
      hilog.warn(DOMAIN, TAG, 'ime: display density unavailable, assuming 1');
    }
    try {
      const win = await window.getLastWindow(getContext(this));
      const rect = win.getWindowProperties().windowRect;
      this.windowLeft = rect.left;
      this.windowTop = rect.top;
      // The window manager's own answer, next to the surface area the page measures: a window that
      // is larger than the pushed surface size means ArkUI and SDL still disagree (docs §24.5).
      hilog.info(DOMAIN, TAG, 'textura-geometry window=%{public}d,%{public}d %{public}dx%{public}d' +
        ' density=%{public}s', rect.left, rect.top, rect.width, rect.height, this.densityPixels.toFixed(3));
    } catch (e) {
      this.windowLeft = 0;
      this.windowTop = 0;
      hilog.warn(DOMAIN, TAG, 'ime: window rect unavailable, anchoring window-relative');
    }
  }

  private imeControllerOrNull(): inputMethod.InputMethodController | null {
    if (this.imeController === null) {
      try {
        this.imeController = inputMethod.getController();
      } catch (e) {
        return null;
      }
    }
    return this.imeController;
  }

  private syncImeAnchor(): void {
    if (!TextInputState.attached) {
      TextInputState.cursorKey = '';
      return;
    }
    const read: (() => number[] | null) | undefined = getImeAnchor;
    if (read === undefined) {
      return;
    }
    let anchor: number[] | null = null;
    try {
      anchor = read();
    } catch (e) {
      return;
    }
    if (anchor === null || anchor.length !== 4) {
      return;
    }
    const key: string = `${anchor[0]},${anchor[1]},${anchor[2]},${anchor[3]},` +
      `${Math.round(this.windowLeft)},${Math.round(this.windowTop)}`;
    if (key === TextInputState.cursorKey) {
      return;
    }
    const controller = this.imeControllerOrNull();
    const base: inputMethod.TextConfig | null = TextInputState.config as inputMethod.TextConfig | null;
    if (controller === null || base === null) {
      return;
    }
    TextInputState.cursorKey = key;
    const density = this.densityPixels;
    const cursorInfo: inputMethod.CursorInfo = {
      left: Math.round(this.windowLeft + anchor[0] * density),
      top: Math.round(this.windowTop + anchor[1] * density),
      width: Math.max(1, Math.round(anchor[2] * density)),
      height: Math.max(1, Math.round(anchor[3] * density))
    };
    const next: inputMethod.TextConfig = {
      inputAttribute: base.inputAttribute,
      cursorInfo: cursorInfo
    };
    try {
      controller.attach(true, next).catch((error: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'ime: re-attach failed code=%{public}d', error.code ?? -1);
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'ime: re-attach threw (ignored)');
    }
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
          // The surface must track the window, not the launch size: SDL creates its EGL surface
          // from the XComponent's size on the first frame, and `OPENHARMONY_SyncSurfaceSize()`
          // only re-creates it when the *buffer geometry* it reads from this component changed.
          // With no width/height the component was sized once at start-up, so growing the window
          // (maximise / fullscreen) left the surface at the old size and SDL never emitted
          // WINDOW_RESIZED — the page kept laying out for the launch size (docs/DEVICE-NOTES §19).
          .width('100%')
          .height('100%')
          // ...and the backend still does not adopt a later size on its own, so the measured area is
          // pushed into SDL through the NAPI bridge (docs/DEVICE-NOTES §24).
          .onAreaChange((_old: Area, area: Area) => this.onSurfaceAreaChanged(area))
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
      // Both axes: the Column is the surface's only parent, so a missing height here stops the
      // XComponent from ever being taller than its first-frame content (see the comment above).
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    // TEXTURA-CUI-P05 key bridge: key events bubble to this root, which is the only place Tab can be
    // seen before ArkUI's focus traversal consumes it. Returning true stops the traversal, so CUI
    // owns the focus ring; every other key falls through untouched.
    .onKeyEvent((event: KeyEvent) => this.forwardKeyToSdl(event))
  }
}
