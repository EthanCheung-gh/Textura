package cui.core

import sdl.{MouseButton, UiEvent}
/*
 * TEXTURA-CUI-P08 — normalize the pointer button codings of a primary press.
 *
 * CUI's control protocols match `MouseButton.Left` literally (button, segmented control, field,
 * combo box, every built-in). The desktop SDL backend reports exactly that, but a pointer
 * backend driven by touch — the HarmonyOS port under a finger — delivers
 * `MouseButton.RawCode(0)` (SDL's "no button information") or `MouseButton.RawCode(1)` (the
 * left button's real code). A handler that only matches `Left` then does nothing while hover
 * and scrolling keep working, which is the hardest kind of input bug to see
 * (docs/DEVICE-NOTES.md §1, §4.4).
 *
 * Rewriting the event once, where it enters the framework, keeps every control — built-in and
 * application-defined — on the same contract. `textura.ui.isPrimaryPointerButton` still accepts
 * the raw codes as well, so application code that matches on the button value keeps working
 * even if this normalization is ever removed.
 *
 * Only the primary codes are folded: middle (2), right (3) and the wheel axes stay untouched,
 * so a secondary click can never activate a control.
 */
public func normalizePointerButton(event: UiEvent): UiEvent {
    match (event) {
        case UiEvent.MouseDown(MouseButton.RawCode(code), x, y) =>
            if (code == 0 || code == 1) {
                UiEvent.MouseDown(MouseButton.Left, x, y)
            } else {
                event
            }
        case UiEvent.MouseUp(MouseButton.RawCode(code), x, y) =>
            if (code == 0 || code == 1) {
                UiEvent.MouseUp(MouseButton.Left, x, y)
            } else {
                event
            }
        case _ => event
    }
}
