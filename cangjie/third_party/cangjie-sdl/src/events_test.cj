package sdl

@Test
func pageNavigationKeysDecodeFromNativeScancodes(): Unit {
    match (keyFromScancode(75)) { case Key.PageUp => @Expect(true); case _ => @Fail("PageUp was not decoded") }
    match (keyFromScancode(78)) { case Key.PageDown => @Expect(true); case _ => @Fail("PageDown was not decoded") }
}

@Test
func keyFromScancodeMapsLettersAndControls(): Unit {
    match (keyFromScancode(SDL_SCANCODE_A)) {
        case Key.Letter(value) => @Expect(value, UInt8(65))
        case _ => @Fail("A scancode should map to Key.Letter.")
    }

    match (keyFromScancode(SDL_SCANCODE_ESCAPE)) {
        case Key.Escape => @Expect(true)
        case _ => @Fail("Escape scancode should map to Key.Escape.")
    }

    match (keyFromScancode(SDL_SCANCODE_HOME)) {
        case Key.Home => @Expect(true)
        case _ => @Fail("Home scancode should map to Key.Home.")
    }
}

/*
 * Numeric keypad. SDL reports the keypad digits and the keypad Enter with their own identities —
 * scancodes 88..98 (`SDL_scancode.h`) and keycodes 0x40000058..0x40000062 (`SDL_keycode.h`) — and
 * neither falls in the ASCII keycode branch nor in the main-row scancode branch, so every keypad
 * digit used to arrive as `Key.RawScancode` and never reached a text field. Both identities are
 * covered because which one a platform bridge fills in is platform specific, and each digit is
 * asserted on its own: the digit order is `KP_1 = 89 … KP_9 = 97, KP_0 = 98`, so a single offset
 * would shift the whole row.
 */

private func expectKeypadDigit(key: Key, digit: UInt8, label: String): Unit {
    match (key) {
        case Key.Digit(value) => @Expect(value, digit)
        case _ => @Fail("${label} should decode to Key.Digit(${digit}).")
    }
}

@Test
func numpadDigitScancodesDecodeToDigits(): Unit {
    expectKeypadDigit(keyFromScancode(SDL_SCANCODE_KP_0), UInt8(48), "KP_0 scancode")
    expectKeypadDigit(keyFromScancode(SDL_SCANCODE_KP_1), UInt8(49), "KP_1 scancode")
    expectKeypadDigit(keyFromScancode(SDL_SCANCODE_KP_2), UInt8(50), "KP_2 scancode")
    expectKeypadDigit(keyFromScancode(SDL_SCANCODE_KP_3), UInt8(51), "KP_3 scancode")
    expectKeypadDigit(keyFromScancode(SDL_SCANCODE_KP_4), UInt8(52), "KP_4 scancode")
    expectKeypadDigit(keyFromScancode(SDL_SCANCODE_KP_5), UInt8(53), "KP_5 scancode")
    expectKeypadDigit(keyFromScancode(SDL_SCANCODE_KP_6), UInt8(54), "KP_6 scancode")
    expectKeypadDigit(keyFromScancode(SDL_SCANCODE_KP_7), UInt8(55), "KP_7 scancode")
    expectKeypadDigit(keyFromScancode(SDL_SCANCODE_KP_8), UInt8(56), "KP_8 scancode")
    expectKeypadDigit(keyFromScancode(SDL_SCANCODE_KP_9), UInt8(57), "KP_9 scancode")
}

@Test
func numpadEnterScancodeDecodesToEnter(): Unit {
    match (keyFromScancode(SDL_SCANCODE_KP_ENTER)) {
        case Key.Enter => @Expect(true)
        case _ => @Fail("KP_ENTER scancode should decode to Key.Enter.")
    }
}

@Test
func numpadDigitKeycodesDecodeToDigits(): Unit {
    expectKeypadDigit(keyFromEvent(SDL_SCANCODE_KP_0, SDLK_KP_0), UInt8(48), "KP_0 keycode")
    expectKeypadDigit(keyFromEvent(SDL_SCANCODE_KP_1, SDLK_KP_1), UInt8(49), "KP_1 keycode")
    expectKeypadDigit(keyFromEvent(SDL_SCANCODE_KP_2, SDLK_KP_2), UInt8(50), "KP_2 keycode")
    expectKeypadDigit(keyFromEvent(SDL_SCANCODE_KP_3, SDLK_KP_3), UInt8(51), "KP_3 keycode")
    expectKeypadDigit(keyFromEvent(SDL_SCANCODE_KP_4, SDLK_KP_4), UInt8(52), "KP_4 keycode")
    expectKeypadDigit(keyFromEvent(SDL_SCANCODE_KP_5, SDLK_KP_5), UInt8(53), "KP_5 keycode")
    expectKeypadDigit(keyFromEvent(SDL_SCANCODE_KP_6, SDLK_KP_6), UInt8(54), "KP_6 keycode")
    expectKeypadDigit(keyFromEvent(SDL_SCANCODE_KP_7, SDLK_KP_7), UInt8(55), "KP_7 keycode")
    expectKeypadDigit(keyFromEvent(SDL_SCANCODE_KP_8, SDLK_KP_8), UInt8(56), "KP_8 keycode")
    expectKeypadDigit(keyFromEvent(SDL_SCANCODE_KP_9, SDLK_KP_9), UInt8(57), "KP_9 keycode")
}

@Test
func numpadEnterKeycodeDecodesToEnter(): Unit {
    match (keyFromEvent(SDL_SCANCODE_KP_ENTER, SDLK_KP_ENTER)) {
        case Key.Enter => @Expect(true)
        case _ => @Fail("KP_ENTER keycode should decode to Key.Enter.")
    }
}

@Test
func numpadPressDecodesThroughTheNativeKeyboardRecord(): Unit {
    // The whole path a keypad press takes: SDL event struct -> decodeEventRecord -> KeyDown.
    match (decodeRawKeyboard(SDL_SCANCODE_KP_7, SDLK_KP_7).event) {
        case UiEvent.KeyDown(Key.Digit(value), repeating) =>
            @Expect(value, UInt8(55))
            @Expect(!repeating)
        case _ => @Fail("A keypad 7 press should arrive as KeyDown(Key.Digit('7')).")
    }
    match (decodeRawKeyboard(SDL_SCANCODE_KP_ENTER, SDLK_KP_ENTER).event) {
        case UiEvent.KeyDown(Key.Enter, _) => @Expect(true)
        case _ => @Fail("A keypad Enter press should arrive as KeyDown(Key.Enter).")
    }
}

@Test
func mainRowDigitsAndLettersKeepTheirScancodeMapping(): Unit {
    // Regression guard for the keypad work: the main number row is scancode 30..39 and the letters
    // are 4..29, and neither may be rewritten by the new branch.
    expectKeypadDigit(keyFromScancode(SDL_SCANCODE_1), UInt8(49), "main-row 1")
    expectKeypadDigit(keyFromScancode(31), UInt8(50), "main-row 2")
    expectKeypadDigit(keyFromScancode(32), UInt8(51), "main-row 3")
    expectKeypadDigit(keyFromScancode(33), UInt8(52), "main-row 4")
    expectKeypadDigit(keyFromScancode(34), UInt8(53), "main-row 5")
    expectKeypadDigit(keyFromScancode(35), UInt8(54), "main-row 6")
    expectKeypadDigit(keyFromScancode(36), UInt8(55), "main-row 7")
    expectKeypadDigit(keyFromScancode(37), UInt8(56), "main-row 8")
    expectKeypadDigit(keyFromScancode(38), UInt8(57), "main-row 9")
    expectKeypadDigit(keyFromScancode(SDL_SCANCODE_0), UInt8(48), "main-row 0")
    for (index in 0..26) {
        let scancode = SDL_SCANCODE_A + Int32(index)
        match (keyFromScancode(scancode)) {
            case Key.Letter(value) => @Expect(value, UInt8(UInt32(65) + UInt32(index)))
            case _ => @Fail("scancode ${scancode} should still decode to a letter.")
        }
    }
}

@Test
func navigationScancodesAreNotTakenOverByTheKeypad(): Unit {
    // With NumLock off the keypad's 1/2/3/4/6/7/8/9 positions navigate, and SDL surfaces that
    // through these scancodes. They must keep their navigation keys instead of becoming digits.
    match (keyFromScancode(SDL_SCANCODE_HOME)) {
        case Key.Home => @Expect(true)
        case _ => @Fail("Home scancode should stay Key.Home.")
    }
    match (keyFromScancode(SDL_SCANCODE_END)) {
        case Key.End => @Expect(true)
        case _ => @Fail("End scancode should stay Key.End.")
    }
    match (keyFromScancode(SDL_SCANCODE_PAGEUP)) {
        case Key.PageUp => @Expect(true)
        case _ => @Fail("PageUp scancode should stay Key.PageUp.")
    }
    match (keyFromScancode(SDL_SCANCODE_PAGEDOWN)) {
        case Key.PageDown => @Expect(true)
        case _ => @Fail("PageDown scancode should stay Key.PageDown.")
    }
    match (keyFromScancode(SDL_SCANCODE_LEFT)) {
        case Key.Left => @Expect(true)
        case _ => @Fail("Left scancode should stay Key.Left.")
    }
    match (keyFromScancode(SDL_SCANCODE_RIGHT)) {
        case Key.Right => @Expect(true)
        case _ => @Fail("Right scancode should stay Key.Right.")
    }
    match (keyFromScancode(SDL_SCANCODE_UP)) {
        case Key.Up => @Expect(true)
        case _ => @Fail("Up scancode should stay Key.Up.")
    }
    match (keyFromScancode(SDL_SCANCODE_DOWN)) {
        case Key.Down => @Expect(true)
        case _ => @Fail("Down scancode should stay Key.Down.")
    }
}

@Test
func buttonFromCodeMapsKnownButtons(): Unit {
    match (buttonFromCode(SDL_BUTTON_LEFT)) {
        case MouseButton.Left => @Expect(true)
        case _ => @Fail("Left button code should map to MouseButton.Left.")
    }

    match (buttonFromCode(UInt8(9))) {
        case MouseButton.RawCode(value) => @Expect(value, UInt8(9))
        case _ => @Fail("Unknown button code should map to MouseButton.RawCode.")
    }
}

@Test
func mouseEventsScaleCoordinates(): Unit {
    let event = scaleEventCoordinates(UiEvent.MouseDown(MouseButton.Left, 30.0, 45.0), 1.5)

    match (event) {
        case UiEvent.MouseDown(MouseButton.Left, x, y) =>
            @Expect(x, Float32(20.0))
            @Expect(y, Float32(30.0))
        case _ => @Fail("Scaled event should remain a left mouse down event.")
    }
}

@Test
func dropEventsDecodeFileData(): Unit {
    let event = decodeRawDrop(SDL_EVENT_DROP_FILE, "C:/tmp/note.txt", 30.0, 45.0)

    match (event) {
        case UiEvent.DropFile(path, x, y) =>
            @Expect(path, "C:/tmp/note.txt")
            @Expect(x, Float32(30.0))
            @Expect(y, Float32(45.0))
        case _ => @Fail("Drop file event should decode with path and position.")
    }
}

@Test
func dropEventsScaleCoordinates(): Unit {
    let event = scaleEventCoordinates(UiEvent.DropText("hello", 30.0, 45.0), 1.5)

    match (event) {
        case UiEvent.DropText(value, x, y) =>
            @Expect(value, "hello")
            @Expect(x, Float32(20.0))
            @Expect(y, Float32(30.0))
        case _ => @Fail("Drop text event should scale coordinates.")
    }
}

@Test
func frameEventsKeepTimeValuesWhenScaled(): Unit {
    let event = scaleEventCoordinates(UiEvent.Frame(FrameInfo(UInt64(32), UInt64(16))), 2.0)

    match (event) {
        case UiEvent.Frame(info) =>
            @Expect(info.elapsedMs, UInt64(32))
            @Expect(info.deltaMs, UInt64(16))
        case _ => @Fail("Frame event should not be converted by coordinate scaling.")
    }
}

@Test
func keyboardEventPreservesTimestampWindowLogicalKeyAndModifiers(): Unit {
    let eventPtr = unsafe { LibC.malloc<SdlEvent>() }
    try (eventResource = eventPtr.asResource()) {
        var key = SdlKeyboardEvent()
        key.eventType = SDL_EVENT_KEY_DOWN
        key.timestamp = UInt64(123456)
        key.windowID = UInt32(42)
        key.scancode = SDL_SCANCODE_A
        key.key = UInt32(113) // logical 'q' on a non-QWERTY layout
        key.mod = UInt16(0x0040)
        unsafe { CPointer<SdlKeyboardEvent>(eventResource.value).write(key) }

        let record = decodeEventRecord(unsafe { eventResource.value.read() })

        match (record.event) {
            case UiEvent.KeyDown(Key.Letter(value), _) => @Expect(value, UInt8(81))
            case _ => @Fail("Logical keycode should drive printable shortcut keys.")
        }
        @Expect(record.metadata.timestampNs, UInt64(123456))
        @Expect(record.metadata.windowId, UInt32(42))
        @Expect(record.metadata.physicalScancode, SDL_SCANCODE_A)
        @Expect(record.metadata.logicalKeycode, UInt32(113))
        @Expect(record.metadata.modifiers.ctrl)
        @Expect(record.metadata.modifiers.command)
    }
}

@Test
func textEditingEventCopiesCompositionAndSelection(): Unit {
    let eventPtr = unsafe { LibC.malloc<SdlEvent>() }
    let composition = unsafe { LibC.mallocCString("拼音") }
    try (eventResource = eventPtr.asResource()) {
        try (textResource = composition.asResource()) {
            var editing = SdlTextEditingEvent()
            editing.eventType = SDL_EVENT_TEXT_EDITING
            editing.timestamp = UInt64(99)
            editing.windowID = UInt32(7)
            editing.text = textResource.value.getChars()
            editing.start = 1
            editing.length = 2
            unsafe { CPointer<SdlTextEditingEvent>(eventResource.value).write(editing) }

            let record = decodeEventRecord(unsafe { eventResource.value.read() })

            match (record.event) {
                case UiEvent.TextEditing(text, start, length) =>
                    @Expect(text, "拼音")
                    @Expect(start, Int32(1))
                    @Expect(length, Int32(2))
                case _ => @Fail("Text editing event should preserve the IME preedit range.")
            }
            @Expect(record.metadata.timestampNs, UInt64(99))
            @Expect(record.metadata.windowId, UInt32(7))
        }
    }
}

@Test
func windowAndRenderLifecycleEventsRemainTyped(): Unit {
    match (decodeRawWindowEvent(SDL_EVENT_WINDOW_CLOSE_REQUESTED, UInt32(8)).event) {
        case UiEvent.WindowCloseRequested => @Expect(true)
        case _ => @Fail("Close requested should not be dropped as Unknown.")
    }
    match (decodeRawRenderEvent(SDL_EVENT_RENDER_DEVICE_RESET, UInt32(9)).event) {
        case UiEvent.RenderDeviceReset => @Expect(true)
        case _ => @Fail("Renderer reset should remain typed.")
    }
}

private func decodeRawDrop(eventType: UInt32, data: String, x: Float32, y: Float32): UiEvent {
    let eventPtr = unsafe { LibC.malloc<SdlEvent>() }
    let cData = unsafe { LibC.mallocCString(data) }
    var decoded = UiEvent.Unknown(UInt32(0))
    try (eventResource = eventPtr.asResource()) {
        try (dataResource = cData.asResource()) {
            var drop = SdlDropEvent()
            drop.eventType = eventType
            drop.x = x
            drop.y = y
            drop.data = dataResource.value.getChars()
            unsafe { CPointer<SdlDropEvent>(eventResource.value).write(drop) }
            decoded = decodeEvent(unsafe { eventResource.value.read() })
        }
    }
    decoded
}

private func decodeRawWindowEvent(eventType: UInt32, windowId: UInt32): UiEventRecord {
    let eventPtr = unsafe { LibC.malloc<SdlEvent>() }
    var record = UiEventRecord(UiEvent.Unknown(UInt32(0)))
    try (eventResource = eventPtr.asResource()) {
        var window = SdlWindowEvent()
        window.eventType = eventType
        window.timestamp = UInt64(17)
        window.windowID = windowId
        unsafe { CPointer<SdlWindowEvent>(eventResource.value).write(window) }
        record = decodeEventRecord(unsafe { eventResource.value.read() })
    }
    record
}

private func decodeRawRenderEvent(eventType: UInt32, windowId: UInt32): UiEventRecord {
    let eventPtr = unsafe { LibC.malloc<SdlEvent>() }
    var record = UiEventRecord(UiEvent.Unknown(UInt32(0)))
    try (eventResource = eventPtr.asResource()) {
        var renderer = SdlRenderEvent()
        renderer.eventType = eventType
        renderer.timestamp = UInt64(23)
        renderer.windowID = windowId
        unsafe { CPointer<SdlRenderEvent>(eventResource.value).write(renderer) }
        record = decodeEventRecord(unsafe { eventResource.value.read() })
    }
    record
}

private func decodeRawKeyboard(scancode: Int32, keycode: UInt32): UiEventRecord {
    let eventPtr = unsafe { LibC.malloc<SdlEvent>() }
    var record = UiEventRecord(UiEvent.Unknown(UInt32(0)))
    try (eventResource = eventPtr.asResource()) {
        var key = SdlKeyboardEvent()
        key.eventType = SDL_EVENT_KEY_DOWN
        key.timestamp = UInt64(31)
        key.windowID = UInt32(5)
        key.scancode = scancode
        key.key = keycode
        key.repeat = false
        unsafe { CPointer<SdlKeyboardEvent>(eventResource.value).write(key) }
        record = decodeEventRecord(unsafe { eventResource.value.read() })
    }
    record
}
