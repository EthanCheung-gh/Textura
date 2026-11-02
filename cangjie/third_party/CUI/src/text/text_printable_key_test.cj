package cui.text

import sdl.{EventKeyModifiers, FrameInfo, Key, Rect, Renderer, UiEvent, UiEventMetadata}
import cui.core.{buildRoot, dispatchFrameSubscribers, enableAutomaticComposition, frameSubscriberCount, State, StateStore,
    Theme, UiContext}

/*
 * Regression cover for TEXTURA-CUI-P10: a hardware keyboard can deliver a printable character as a
 * bare `KeyDown` with no `UiEvent.TextInput` behind it (HarmonyOS reports `Digit(52)` and then no
 * text at all, so every digit typed into a metric field was dropped). The editors now stage the
 * character for one frame and insert it only if the IME never speaks, so these tests pin both halves
 * of that contract: the character must arrive, and it must arrive exactly once.
 *
 * Frame times are explicit: the staging rule compares the capture frame with the frame that tries to
 * flush, so a test that reuses one timestamp never sees the character (that is the point — see
 * `printableKeyDigitReachesTheDraftOnTheFrameAfterThePress`).
 *
 * The first tests drive `Widget.handle` directly, which also exercises the `UiEvent.Frame` arm that
 * hosts which *broadcast* a frame event rely on. That arm is NOT how the device works: `DesktopApp`
 * hands the synthesized tick to `frameSubscriber` callbacks only, so `handle(UiEvent.Frame)` never
 * runs for a field there. The `...OnTheFrameTick...` tests below therefore go through
 * `WidgetTestHost`, whose frame loop dispatches the tick exactly like `DesktopApp.frame` does
 * (`dispatchFrameSubscribers`), and they assert the subscription only exists while a character waits.
 */

private func printableContext(): UiContext { UiContext(Renderer.headless(), Theme.light()) }

private func printableFrame(ctx: UiContext, elapsedMs: UInt64): Unit {
    ctx.frame = FrameInfo(elapsedMs, UInt64(16))
}

// Delivers one frame tick at `elapsedMs` the way the shell does: every widget under an
// `EventHandler` receives `UiEvent.Frame` once per rendered frame.
private func tickFrame(ctx: UiContext, widget: (UiContext, UiEvent) -> Bool, elapsedMs: UInt64): Bool {
    printableFrame(ctx, elapsedMs)
    widget(ctx, UiEvent.Frame(FrameInfo(elapsedMs, UInt64(16))))
}

private func pressWithModifiers(ctx: UiContext, widget: (UiContext, UiEvent) -> Bool, key: Key,
    modifiers: UInt16): Bool {
    ctx.beginEvent(UiEventMetadata(modifiers: EventKeyModifiers(raw: modifiers)))
    try {
        widget(ctx, UiEvent.KeyDown(key, false))
    } finally {
        ctx.endEvent()
    }
}

private func fieldHandler(field: TextField): (UiContext, UiEvent) -> Bool {
    {ctx, event => field.handle(ctx, event)}
}

private func areaHandler(area: TextArea): (UiContext, UiEvent) -> Bool {
    {ctx, event => area.handle(ctx, event)}
}

@Test
func printableKeyDigitReachesTheDraftOnTheFrameAfterThePress(): Unit {
    let ctx = printableContext()
    let body = State<String>("")
    let field = TextField(body, key: "printable-digit")
    field.layout(ctx, Rect(0.0, 0.0, 240.0, 40.0))
    ctx.focus("printable-digit")
    let handle = fieldHandler(field)
    printableFrame(ctx, UInt64(0))
    // The press is consumed and remembered, never written straight into the draft: an IME commit
    // for the very same press may still arrive later in the same event batch.
    @Expect(handle(ctx, UiEvent.KeyDown(Key.Digit(52), false)))
    @Expect(body.value, "")
    // The capture frame itself must not flush — that is the whole one-frame delay.
    @Expect(!tickFrame(ctx, handle, UInt64(0)))
    @Expect(body.value, "")
    // The next frame inserts through the same path `UiEvent.TextInput` uses.
    @Expect(!tickFrame(ctx, handle, UInt64(16)))
    @Expect(body.value, "4")
    // A second frame must not insert it again.
    @Expect(!tickFrame(ctx, handle, UInt64(32)))
    @Expect(body.value, "4")
}

@Test
func printableKeyDigitIsNotDoubledWhenTextInputArrivesInTheSameFrame(): Unit {
    let ctx = printableContext()
    let body = State<String>("")
    let field = TextField(body, key: "printable-ime")
    field.layout(ctx, Rect(0.0, 0.0, 240.0, 40.0))
    ctx.focus("printable-ime")
    let handle = fieldHandler(field)
    printableFrame(ctx, UInt64(0))
    @Expect(handle(ctx, UiEvent.KeyDown(Key.Digit(52), false)))
    @Expect(handle(ctx, UiEvent.TextInput("4")))
    @Expect(body.value, "4")
    for (elapsedMs in [UInt64(0), UInt64(16), UInt64(32)]) {
        @Expect(!tickFrame(ctx, handle, elapsedMs))
        @Expect(body.value, "4")
    }
    // One character, one undo step: a double insert would leave text behind after a single undo.
    field.undo()
    @Expect(body.value, "")
}

@Test
func printableKeyIsIgnoredWhileTheImeComposes(): Unit {
    let ctx = printableContext()
    let body = State<String>("")
    let field = TextField(body, key: "printable-composing")
    field.layout(ctx, Rect(0.0, 0.0, 240.0, 40.0))
    ctx.focus("printable-composing")
    let handle = fieldHandler(field)
    printableFrame(ctx, UInt64(0))
    @Expect(handle(ctx, UiEvent.TextEditing("4", 0, 1)))
    @Expect(ctx.imeComposition("printable-composing").isSome(), true)
    // The IME owns the keystroke while it is composing: no fallback, no draft change.
    @Expect(!handle(ctx, UiEvent.KeyDown(Key.Digit(52), false)))
    for (elapsedMs in [UInt64(0), UInt64(16), UInt64(32)]) {
        @Expect(!tickFrame(ctx, handle, elapsedMs))
        @Expect(body.value, "")
    }
    // The IME's own commit is what reaches the draft.
    @Expect(handle(ctx, UiEvent.TextInput("4")))
    @Expect(body.value, "4")
}

@Test
func printableKeyModifiedPressesStayShortcuts(): Unit {
    let ctx = printableContext()
    let body = State<String>("abc")
    let field = TextField(body, key: "printable-shortcut")
    field.layout(ctx, Rect(0.0, 0.0, 240.0, 40.0))
    ctx.focus("printable-shortcut")
    let handle = fieldHandler(field)
    printableFrame(ctx, UInt64(0))
    // Ctrl+A still selects all, and never stages an 'A'.
    @Expect(pressWithModifiers(ctx, handle, Key.Letter(65), UInt16(0x40)))
    @Expect(field.selectedText(), "abc")
    @Expect(body.value, "abc")
    // Ctrl+digit is not text either.
    @Expect(!pressWithModifiers(ctx, handle, Key.Digit(52), UInt16(0x40)))
    // Shift+digit produces a different glyph than the logical keycode says ('!' vs '1'), so the
    // fallback stays out of it rather than inserting the wrong character.
    @Expect(!pressWithModifiers(ctx, handle, Key.Digit(49), UInt16(0x01)))
    for (elapsedMs in [UInt64(0), UInt64(16), UInt64(32)]) {
        @Expect(!tickFrame(ctx, handle, elapsedMs))
        @Expect(body.value, "abc")
    }
}

@Test
func printableKeyNeedsFocusAndEditable(): Unit {
    let ctx = printableContext()
    // Read-only: focus is allowed, typing is not.
    let readOnlyText = State<String>("42")
    let readOnly = TextField(readOnlyText, key: "printable-read-only", editable: false)
    readOnly.layout(ctx, Rect(0.0, 0.0, 240.0, 40.0))
    ctx.focus("printable-read-only")
    let readOnlyHandle = fieldHandler(readOnly)
    printableFrame(ctx, UInt64(0))
    @Expect(!readOnlyHandle(ctx, UiEvent.KeyDown(Key.Digit(55), false)))
    @Expect(!tickFrame(ctx, readOnlyHandle, UInt64(16)))
    @Expect(readOnlyText.value, "42")
    // Editable but unfocused: the keystroke belongs to whoever owns the focus.
    let unfocusedText = State<String>("")
    let unfocused = TextField(unfocusedText, key: "printable-unfocused")
    unfocused.layout(ctx, Rect(0.0, 0.0, 240.0, 40.0))
    ctx.clearFocus()
    let unfocusedHandle = fieldHandler(unfocused)
    printableFrame(ctx, UInt64(0))
    @Expect(!unfocusedHandle(ctx, UiEvent.KeyDown(Key.Digit(55), false)))
    @Expect(!tickFrame(ctx, unfocusedHandle, UInt64(16)))
    @Expect(unfocusedText.value, "")
}

@Test
func printableKeySuccessiveDigitsKeepTheirOrder(): Unit {
    let ctx = printableContext()
    let body = State<String>("")
    let field = TextField(body, key: "printable-sequence")
    field.layout(ctx, Rect(0.0, 0.0, 240.0, 40.0))
    ctx.focus("printable-sequence")
    let handle = fieldHandler(field)
    printableFrame(ctx, UInt64(0))
    @Expect(handle(ctx, UiEvent.KeyDown(Key.Digit(52), false)))
    @Expect(!tickFrame(ctx, handle, UInt64(0)))
    @Expect(!tickFrame(ctx, handle, UInt64(16)))
    @Expect(body.value, "4")
    @Expect(handle(ctx, UiEvent.KeyDown(Key.Digit(50), false)))
    @Expect(!tickFrame(ctx, handle, UInt64(16)))
    @Expect(!tickFrame(ctx, handle, UInt64(32)))
    @Expect(body.value, "42")
    // Both digits were typed in one undo group, like a run of `TextInput` events.
    field.undo()
    @Expect(body.value, "")
}

@Test
func printableKeyDigitsArriveInOneBatchAsOneEdit(): Unit {
    let ctx = printableContext()
    let body = State<String>("")
    let field = TextField(body, key: "printable-batch")
    field.layout(ctx, Rect(0.0, 0.0, 240.0, 40.0))
    ctx.focus("printable-batch")
    let handle = fieldHandler(field)
    printableFrame(ctx, UInt64(0))
    // An injected burst can put both presses in one frame; neither may be lost.
    @Expect(handle(ctx, UiEvent.KeyDown(Key.Digit(52), false)))
    @Expect(handle(ctx, UiEvent.KeyDown(Key.Digit(50), false)))
    @Expect(!tickFrame(ctx, handle, UInt64(0)))
    @Expect(!tickFrame(ctx, handle, UInt64(16)))
    @Expect(body.value, "42")
}

/*
 * End-to-end cover for the numeric keypad. The SDL binding decodes a keypad press to the *same*
 * `Key.Digit` the main number row produces (`SDL_SCANCODE_KP_1..KP_0`, `SDLK_KP_1..KP_0`), so a
 * keypad digit reaches a field through exactly this path and nothing in CUI has to know about the
 * keypad. `55` is ASCII `7`, i.e. what a keypad 7 press carries.
 */
@Test
func keypadDigitReachesTheDraftThroughThePrintableKeyFallback(): Unit {
    let ctx = printableContext()
    let body = State<String>("")
    let field = TextField(body, key: "printable-keypad")
    field.layout(ctx, Rect(0.0, 0.0, 240.0, 40.0))
    ctx.focus("printable-keypad")
    let handle = fieldHandler(field)
    printableFrame(ctx, UInt64(0))
    @Expect(handle(ctx, UiEvent.KeyDown(Key.Digit(55), false)))
    @Expect(body.value, "")
    @Expect(!tickFrame(ctx, handle, UInt64(0)))
    @Expect(body.value, "")
    @Expect(!tickFrame(ctx, handle, UInt64(16)))
    @Expect(body.value, "7")
    @Expect(!tickFrame(ctx, handle, UInt64(32)))
    @Expect(body.value, "7")
}

@Test
func printableKeyDigitsAndSpaceReachTheMultilineArea(): Unit {
    let ctx = printableContext()
    let body = State<String>("")
    let area = TextArea(body, key: "printable-area")
    area.layout(ctx, Rect(0.0, 0.0, 240.0, 120.0))
    ctx.focus("printable-area")
    let handle = areaHandler(area)
    printableFrame(ctx, UInt64(0))
    @Expect(handle(ctx, UiEvent.KeyDown(Key.Digit(52), false)))
    @Expect(!tickFrame(ctx, handle, UInt64(0)))
    @Expect(!tickFrame(ctx, handle, UInt64(16)))
    @Expect(body.value, "4")
    // Space has its own `Key` variant but the same hole: nothing in the editors handled it, so a
    // bare space press was dropped exactly like a digit.
    @Expect(handle(ctx, UiEvent.KeyDown(Key.Space, false)))
    @Expect(!tickFrame(ctx, handle, UInt64(16)))
    @Expect(!tickFrame(ctx, handle, UInt64(32)))
    @Expect(body.value, "4 ")
    @Expect(handle(ctx, UiEvent.KeyDown(Key.Digit(50), false)))
    @Expect(!tickFrame(ctx, handle, UInt64(32)))
    @Expect(!tickFrame(ctx, handle, UInt64(48)))
    @Expect(body.value, "4 2")
    // The IME path still owns the frame it shares with the press.
    @Expect(handle(ctx, UiEvent.KeyDown(Key.Digit(55), false)))
    @Expect(handle(ctx, UiEvent.TextInput("7")))
    @Expect(!tickFrame(ctx, handle, UInt64(48)))
    @Expect(!tickFrame(ctx, handle, UInt64(64)))
    @Expect(body.value, "4 27")
}

private let PRINTABLE_HOST_RECT: Rect = Rect(0.0, 0.0, 480.0, 320.0)

/*
 * The frame pipeline the device actually runs, minus the pixel work: build (retained graph on, so the
 * per-build subscription really is the only way to reach the tick), events, `frameSubscriber` tick.
 * `WidgetTestHost` cannot be imported here (it depends on this package), so the two framework entry
 * points it uses are called directly — `buildRoot` and `dispatchFrameSubscribers`.
 */
private class PrintableFrameLoop {
    let store = StateStore()
    let ctx = UiContext(Renderer.headless(), Theme.light())
    var field: ?TextField = None
    private let body: State<String>

    init(body: State<String>) {
        this.body = body
        enableAutomaticComposition(store)
    }

    // One build, the way `stepFrame`/`reflectStateChanges` run it after every event.
    func build(): Unit {
        let _ = buildRoot(
            {
                =>
                    let field = TextField(body, key: "printable-tick")
                    field.layout(ctx, PRINTABLE_HOST_RECT)
                    this.field = Some(field)
            },
            store
        )
    }

    // One synthesized frame tick: `DesktopApp` hands it to `frameSubscriber` callbacks only.
    func tick(elapsedMs: UInt64): Unit {
        ctx.frame = FrameInfo(elapsedMs, UInt64(16))
        build()
        dispatchFrameSubscribers(store, ctx, ctx.frame)
        build() // the reflect pass after the tick
    }

    func press(key: Key): Bool {
        match (field) {
            case Some(value) => value.handle(ctx, UiEvent.KeyDown(key, false))
            case None => false
        }
    }

    func typeText(value: String): Bool {
        match (field) {
            case Some(field) => field.handle(ctx, UiEvent.TextInput(value))
            case None => false
        }
    }

    func subscribers(): Int64 {
        frameSubscriberCount(store)
    }
}

@Test
func printableKeyFlushesOnTheFrameTickSubscription(): Unit {
    let text = State<String>("")
    let loop = PrintableFrameLoop(text)
    loop.ctx.frame = FrameInfo(UInt64(0), UInt64(16))
    loop.build()
    loop.ctx.focus("printable-tick")
    // A resting UI owns no frame subscription, so CUI's retained partial-damage rule
    // (`frameSubscriberCount != 0`) is untouched by this patch.
    @Expect(loop.subscribers(), Int64(0))
    // Capture frame: the press is staged, not inserted, and it arms exactly one subscription.
    @Expect(loop.press(Key.Digit(52)))
    @Expect(text.value, "")
    // The frame tick of the capture frame must not insert: that is the IME's head start.
    loop.tick(UInt64(0))
    @Expect(loop.subscribers(), Int64(1))
    @Expect(text.value, "")
    // The next frame's tick inserts the character. Nothing here dispatches `UiEvent.Frame`.
    loop.tick(UInt64(16))
    @Expect(text.value, "4")
    @Expect(loop.subscribers(), Int64(0))
    // And no frame after that inserts it again.
    loop.tick(UInt64(32))
    @Expect(text.value, "4")
    @Expect(loop.subscribers(), Int64(0))
}

@Test
func printableKeyFrameTickDoesNotDoubleInsertAnImeCommit(): Unit {
    let text = State<String>("")
    let loop = PrintableFrameLoop(text)
    loop.ctx.frame = FrameInfo(UInt64(0), UInt64(16))
    loop.build()
    loop.ctx.focus("printable-tick")
    // The IME answers for the same press: its text wins and the staged character is dropped.
    @Expect(loop.press(Key.Digit(52)))
    @Expect(loop.typeText("4"))
    @Expect(text.value, "4")
    for (elapsedMs in [UInt64(0), UInt64(16), UInt64(32)]) {
        loop.tick(elapsedMs)
        @Expect(text.value, "4")
        @Expect(loop.subscribers(), Int64(0))
    }
}

@Test
func printableKeyFrameTickKeepsSuccessiveDigitsInOrder(): Unit {
    let text = State<String>("")
    let loop = PrintableFrameLoop(text)
    loop.ctx.frame = FrameInfo(UInt64(0), UInt64(16))
    loop.build()
    loop.ctx.focus("printable-tick")
    @Expect(loop.press(Key.Digit(52)))
    loop.tick(UInt64(0))
    loop.tick(UInt64(16))
    @Expect(text.value, "4")
    @Expect(loop.press(Key.Digit(50)))
    loop.tick(UInt64(16))
    loop.tick(UInt64(32))
    @Expect(text.value, "42")
}
