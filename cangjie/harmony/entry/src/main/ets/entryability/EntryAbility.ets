/*
 * The HAP side of the Textura CUI/SDL host chain.
 *
 * Shape adapted from PixCap-Cangjie entry/src/main/ets/entryability/EntryAbility.ets (read-only
 * reference) with everything product-specific removed: no capture, no export watcher, no clipboard.
 * What remains is the ordering that was proven on device:
 *
 *   1. requireCJLib('libtextura_host.so')  — starts the Cangjie runtime on this ArkTS thread and
 *      dlopen()s the host. MUST run before SDL touches SDL_AppInit, and MUST run here rather than
 *      from native code (see entry/src/main/cpp/host_bootstrap.c).
 *   2. sdl.provideArkTSObjects(...)        — hands SDL the ArkTS objects it needs; SDL then takes
 *      over the ability prototype (TakeOverUIAbility), loads pages/Index and drives the
 *      XComponent surface, which is what eventually calls SDL_AppInit in the Cangjie host.
 *
 * Deliberately absent:
 *   - onWindowStageCreate / window customization: SDL's TakeOverUIAbility replaces
 *     onWindowStageCreate on the ability prototype, so anything defined here never runs.
 *   - any ArkUI product UI: everything visible is drawn by CUI inside the XComponent.
 */

import { abilityAccessCtrl, AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { i18n } from '@kit.LocalizationKit';
import { inputMethod } from '@kit.IMEKit';
import { BusinessError } from '@kit.BasicServicesKit';
import pointer from '@ohos.multimodalInput.pointer';
import sdl from 'libSDL3.so';
import { requireCJLib } from 'libark_interop_loader.so';
import { TextInputState } from '../common/TextInputState';

const DOMAIN = 0x0000;
const TAG = 'Textura/HOST';

/* The Cangjie host library staged into entry/libs/arm64-v8a by scripts/harmony/stage_libs.sh. */
const CANGJIE_HOST_LIB = 'libtextura_host.so';

/*
 * Crash-proof stand-in for the IME controller handed to SDL.
 *
 * SDL's HarmonyOS port drives the IME controller through NAPI (attach / hideTextInput plus on/off
 * for insertText and deleteLeft). On the reference device those calls throw synchronously, and SDL
 * does not clear the pending NAPI exception, so the error escalates to a fatal JS error and the
 * process is killed. The Textura scaffold renders static text only, so every failure here stays a
 * logged warning; real text input needs an upstream-grade fix (newer SDL pin or an SDL-side patch)
 * and is out of scope for this round.
 */
class SafeImeController {
  private readonly controller: inputMethod.InputMethodController = inputMethod.getController();

  attach(showKeyboard: boolean, textConfig: ESObject, callback: ESObject): void {
    // A text control has focus: the IME owns character keys and Escape/Ctrl from here on
    // (pages/Index.ets stops forwarding them, because the native path works while the IME is up).
    TextInputState.attached = true;
    // Keep SDL's config: the page re-posts the caret with `updateCursor` as it moves (SDL cannot
    // tell HarmonyOS where the caret is — it has no SetTextInputArea implementation).
    TextInputState.config = textConfig;
    TextInputState.cursorKey = '';
    TextInputState.cursorLogCount = 0;
    try {
      this.controller.attach(showKeyboard, textConfig as inputMethod.TextConfig,
        callback as (error: BusinessError<void>) => void);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'IME attach failed (ignored): %{public}s', JSON.stringify(e));
    }
  }

  hideTextInput(callback: ESObject): void {
    // No text control focused any more: the page takes the navigation/shortcut keys back.
    TextInputState.attached = false;
    try {
      this.controller.hideTextInput(callback as () => void);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'IME hideTextInput failed (ignored): %{public}s', JSON.stringify(e));
    }
  }

  on(type: string, callback: ESObject): void {
    try {
      if (type === 'insertText') {
        this.controller.on('insertText', callback as (text: string) => void);
      } else if (type === 'deleteLeft') {
        this.controller.on('deleteLeft', callback as (length: number) => void);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'IME on(%{public}s) failed (ignored): %{public}s', type, JSON.stringify(e));
    }
  }

  off(type: string, callback: ESObject): void {
    try {
      if (type === 'insertText') {
        this.controller.off('insertText', callback as (text: string) => void);
      } else if (type === 'deleteLeft') {
        this.controller.off('deleteLeft', callback as (length: number) => void);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'IME off(%{public}s) failed (ignored): %{public}s', type, JSON.stringify(e));
    }
  }
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    /*
     * Boot the Cangjie runtime before anything touches the host library. The loader registers the
     * host ArkVM, starts the runtime, then dlopen()s libtextura_host.so (so its package
     * registration runs against a live runtime). Ordering matters: SDL's SDL_AppInit lands in the
     * host only after this returns.
     */
    try {
      requireCJLib(CANGJIE_HOST_LIB);
      hilog.info(DOMAIN, TAG, '%{public}s', 'Cangjie runtime started via requireCJLib');
    } catch (e) {
      // Not fatal for the build; the app will fail visibly at SDL_AppInit instead, and the C shim
      // reports the reason through SDL_Log -> hilog.
      hilog.error(DOMAIN, TAG, 'requireCJLib failed, Cangjie host will not start: %{public}s',
        JSON.stringify(e));
    }

    hilog.info(DOMAIN, TAG, '%{public}s', 'handing control from ArkTS to native SDL');
    try {
      // If this throws, the app will not start: SDL never receives the ArkTS objects it needs to
      // drive the lifecycle callbacks from C.
      sdl.provideArkTSObjects(
        this,
        abilityAccessCtrl.createAtManager(),
        i18n.System,
        pointer.setPointerVisibleSync,
        new SafeImeController()
      );
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'provideArkTSObjects failed, app will not start: %{public}s',
        JSON.stringify(e));
    }
  }
}
