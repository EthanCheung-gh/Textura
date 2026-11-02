package cui.text

import sdl.Key
import cui.core.{localState, registerFrameSubscriber, State, UiContext}

/*
 * TEXTURA-CUI-P10 — printable characters that arrive as a bare `KeyDown`.
 *
 * `TextField`/`TextArea` insert text in exactly one place: `UiEvent.TextInput`, i.e. the event a
 * platform emits *after* its IME has interpreted a key press. On HarmonyOS a hardware keyboard
 * delivers `KeyDown(Digit(52))` and then no `TextInput` at all when the IME does not own the key
 * (digits), so the character was lost while letters — which the IME does handle — still arrived
 * through `TextInput`. No `Key.Digit`/`Key.Space` arm existed in either editor's key handler, so
 * there was nothing else to fall back to.
 *
 * The fallback has to be safe on every platform, so it is deferred by one frame instead of inserting
 * immediately: SDL emits `SDL_EVENT_KEY_DOWN` and `SDL_EVENT_TEXT_INPUT` for the same press, but the
 * pair can straddle a frame boundary when an IME is in the middle (a remote IME, a soft keyboard,
 * a host bridge). Inserting on the key press would then produce the character twice, and no desktop
 * test would ever see it. Instead:
 *
 *   1. the press itself only stages the character (`stage`) and consumes the event;
 *   2. a `UiEvent.TextInput`/`UiEvent.TextEditing` for that press supersedes it (`cancel`);
 *   3. the next frame's tick inserts whatever is still staged (`flush`) — same `actions().insert`
 *      path as `inputText`, so undo grouping, selection replacement and IME isolation are unchanged.
 *
 * Scope: `Key.Digit`, `Key.Letter` and `Key.Space` with no modifier held. Modifier chords stay on
 * their existing paths — `Ctrl/Cmd/Alt+Letter` is a command (`Ctrl+A`), and `Shift` changes the
 * character itself (`Shift+1` is `!`, not `1`) while `Key.Digit` still reports the unshifted code, so
 * a shifted press is left alone rather than guessed at. `Key.Letter` carries SDL's *uppercase* ASCII
 * code (that is what makes the `Ctrl+letter` table readable) and staging only happens with no
 * modifier held, so a staged letter is inserted in lowercase — the only case a plain press can mean
 * once `Shift` is excluded. Caps Lock is invisible to the key event; an uppercase letter that never
 * produces `TextInput` would therefore arrive lowercase, which is accepted because the IME path wins
 * the race whenever it exists.
 */

private let PRINTABLE_ASCII_LIMIT: UInt8 = 128
private let LETTER_UPPER_A: UInt8 = 65
private let LETTER_UPPER_Z: UInt8 = 90
private let LETTER_CASE_OFFSET: UInt8 = 32

// The character a bare key press stands for, or `None` for keys this fallback must not synthesize.
internal func printableKeyText(key: Key): ?String {
    match (key) {
        case Key.Digit(code) => printableAscii(code)
        case Key.Letter(code) where code >= LETTER_UPPER_A && code <= LETTER_UPPER_Z =>
            printableAscii(code + LETTER_CASE_OFFSET)
        case Key.Letter(code) => printableAscii(code)
        case Key.Space => Some(" ")
        case _ => None
    }
}

private func printableAscii(code: UInt8): ?String {
    if (code >= PRINTABLE_ASCII_LIMIT) {
        None
    } else {
        Some(String.fromUtf8([code]))
    }
}

/*
 * Per-control staging slot for one frame of pending printable text. The slot lives in retained state
 * (`localState`) because widgets are rebuilt every frame: a plain field would be reset by the very
 * rebuild that renders the frame in which the character has to be inserted.
 *
 * `pendingFrame` records the frame the character was captured in; `flush` refuses to insert while
 * still in that frame, which is what gives the IME its one-frame head start.
 *
 * The "next frame" arrives through a one-frame frame subscription, not through `UiEvent.Frame` in
 * `handle`: `DesktopApp` dispatches the synthesized frame tick to `frameSubscriber` callbacks only,
 * so `handle(UiEvent.Frame)` never runs on a field (it is reachable only from hosts that broadcast a
 * frame event down the tree, e.g. `WidgetTestHost` or an `EventHandler` above a test body). `arm`
 * therefore registers the subscription on every build in which a character is waiting — which keeps
 * `frameSubscriberCount` at zero for a resting UI and leaves CUI's retained partial-damage rule
 * untouched — and `handle(UiEvent.Frame)` stays as the second, idempotent trigger for those hosts.
 */
internal class PrintableKeyFallback {
    // Control identity used for the focus and IME ownership checks (the id events are routed by).
    private let id: String
    private let pending: State<String>
    private let pendingFrame: State<UInt64>
    // The editor's own insert path (`TextEditorActions.insert`); set by `arm` on every build.
    private var insertPath: ?(UiContext, String) -> Bool = None
    private var editable = false

    init(statePrefix: String, id: String) {
        this.id = id
        this.pending = localState<String>("${statePrefix}:pendingPrintable") {""}
        this.pendingFrame = localState<UInt64>("${statePrefix}:pendingPrintableFrame") {UInt64(0)}
    }

    /*
     * Wires the editor's insert path and arms the frame tick for as long as something is staged.
     * Reading the slot here is also what makes the retained graph rebuild this control after `stage`
     * writes it — without that read the subscription would never be re-created for the frame that has
     * to insert the character.
     */
    func arm(editable: Bool, insert: (UiContext, String) -> Bool): Unit {
        this.editable = editable
        this.insertPath = insert
        if (!pending.value.isEmpty()) {
            registerFrameSubscriber({ctx, _ => flush(ctx)})
        }
    }

    // Whether this control may stand in for the platform at all: it owns the focus, it can be
    // edited, no composition is in flight, and no modifier turns the press into something else.
    private func stages(ctx: UiContext, editable: Bool): Bool {
        if (!editable || !ctx.hasFocus(id)) {
            return false
        }
        if (ctx.imeComposition(id).isSome()) {
            return false
        }
        let modifiers = ctx.eventModifiers()
        !modifiers.command && !modifiers.alt && !modifiers.shift
    }

    /** Stages `key` for the next frame; returns false when the press is not this fallback's business. */
    func stage(ctx: UiContext, editable: Bool, key: Key): Bool {
        let text = match (printableKeyText(key)) {
            case Some(value) => value
            case None => return false
        }
        if (!stages(ctx, editable)) {
            return false
        }
        // Appending (rather than replacing) matters for injected or very fast input: two presses can
        // land in the same frame, and both characters have to survive.
        pending.value += text
        pendingFrame.value = ctx.frame.elapsedMs
        // No frame is promised otherwise: the capture frame is already rendering, and the insert
        // happens in the frame after this one.
        ctx.requestFrame()
        true
    }

    /** Drops the staged character because the IME produced text for the same press. */
    func cancel(): Unit {
        pending.value = ""
    }

    /*
     * Runs on the frame tick. Inserts the staged text when the capture frame is over and the control
     * still owns the edit; otherwise drops it. Inserting needs no `requestFrame()`: the tick runs
     * before the frame's rebuild and draw, so the character is painted in this same frame.
     */
    func flush(ctx: UiContext): Unit {
        let staged = pending.value
        if (staged.isEmpty()) {
            return
        }
        if (ctx.frame.elapsedMs <= pendingFrame.value) {
            // Still the capture frame. The frame requested by `stage` will bring us back here.
            return
        }
        pending.value = ""
        if (!editable || !ctx.hasFocus(id)) {
            return
        }
        if (ctx.imeComposition(id).isSome()) {
            // The IME took the press over after all; it commits the text itself.
            return
        }
        match (insertPath) {
            case Some(insert) =>
                let _ = insert(ctx, staged) // cjcheck-ignore: ignore-result # a rejected insert (read-only or NUL) simply drops the staged character
            case None => ()
        }
    }
}
