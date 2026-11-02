package sdl

internal let SDL_INIT_VIDEO: UInt32 = UInt32(0x00000020)
internal let SDL_WINDOW_FULLSCREEN: UInt64 = UInt64(0x0000000000000001)
internal let SDL_WINDOW_OPENGL: UInt64 = UInt64(0x0000000000000002)
internal let SDL_WINDOW_OCCLUDED: UInt64 = UInt64(0x0000000000000004)
internal let SDL_WINDOW_HIDDEN: UInt64 = UInt64(0x0000000000000008)
internal let SDL_WINDOW_BORDERLESS: UInt64 = UInt64(0x0000000000000010)
internal let SDL_WINDOW_RESIZABLE: UInt64 = UInt64(0x0000000000000020)
internal let SDL_WINDOW_MINIMIZED: UInt64 = UInt64(0x0000000000000040)
internal let SDL_WINDOW_MAXIMIZED: UInt64 = UInt64(0x0000000000000080)
internal let SDL_WINDOW_MOUSE_GRABBED: UInt64 = UInt64(0x0000000000000100)
internal let SDL_WINDOW_INPUT_FOCUS: UInt64 = UInt64(0x0000000000000200)
internal let SDL_WINDOW_MOUSE_FOCUS: UInt64 = UInt64(0x0000000000000400)
internal let SDL_WINDOW_EXTERNAL: UInt64 = UInt64(0x0000000000000800)
internal let SDL_WINDOW_MODAL: UInt64 = UInt64(0x0000000000001000)
internal let SDL_WINDOW_HIGH_PIXEL_DENSITY: UInt64 = UInt64(0x0000000000002000)
internal let SDL_WINDOW_MOUSE_CAPTURE: UInt64 = UInt64(0x0000000000004000)
internal let SDL_WINDOW_MOUSE_RELATIVE_MODE: UInt64 = UInt64(0x0000000000008000)
internal let SDL_WINDOW_ALWAYS_ON_TOP: UInt64 = UInt64(0x0000000000010000)
internal let SDL_WINDOW_UTILITY: UInt64 = UInt64(0x0000000000020000)
internal let SDL_WINDOW_TOOLTIP: UInt64 = UInt64(0x0000000000040000)
internal let SDL_WINDOW_POPUP_MENU: UInt64 = UInt64(0x0000000000080000)
internal let SDL_WINDOW_KEYBOARD_GRABBED: UInt64 = UInt64(0x0000000000100000)
internal let SDL_WINDOW_FILL_DOCUMENT: UInt64 = UInt64(0x0000000000200000)
internal let SDL_WINDOW_VULKAN: UInt64 = UInt64(0x0000000010000000)
internal let SDL_WINDOW_METAL: UInt64 = UInt64(0x0000000020000000)
internal let SDL_WINDOW_TRANSPARENT: UInt64 = UInt64(0x0000000040000000)
internal let SDL_WINDOW_NOT_FOCUSABLE: UInt64 = UInt64(0x0000000080000000)
internal let SDL_EVENT_QUIT: UInt32 = UInt32(0x100)
internal let SDL_EVENT_WINDOW_EXPOSED: UInt32 = UInt32(0x204)
internal let SDL_EVENT_WINDOW_RESIZED: UInt32 = UInt32(0x206)
internal let SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED: UInt32 = UInt32(0x207)
internal let SDL_EVENT_WINDOW_MINIMIZED: UInt32 = UInt32(0x209)
internal let SDL_EVENT_WINDOW_RESTORED: UInt32 = UInt32(0x20B)
internal let SDL_EVENT_WINDOW_FOCUS_GAINED: UInt32 = UInt32(0x20E)
internal let SDL_EVENT_WINDOW_FOCUS_LOST: UInt32 = UInt32(0x20F)
internal let SDL_EVENT_WINDOW_CLOSE_REQUESTED: UInt32 = UInt32(0x210)
internal let SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED: UInt32 = UInt32(0x214)
internal let SDL_EVENT_WINDOW_OCCLUDED: UInt32 = UInt32(0x216)
internal let SDL_EVENT_KEY_DOWN: UInt32 = UInt32(0x300)
internal let SDL_EVENT_KEY_UP: UInt32 = UInt32(0x301)
internal let SDL_EVENT_TEXT_EDITING: UInt32 = UInt32(0x302)
internal let SDL_EVENT_TEXT_INPUT: UInt32 = UInt32(0x303)
internal let SDL_EVENT_TEXT_EDITING_CANDIDATES: UInt32 = UInt32(0x307)
internal let SDL_EVENT_MOUSE_MOTION: UInt32 = UInt32(0x400)
internal let SDL_EVENT_MOUSE_BUTTON_DOWN: UInt32 = UInt32(0x401)
internal let SDL_EVENT_MOUSE_BUTTON_UP: UInt32 = UInt32(0x402)
internal let SDL_EVENT_MOUSE_WHEEL: UInt32 = UInt32(0x403)
internal let SDL_EVENT_DROP_FILE: UInt32 = UInt32(0x1000)
internal let SDL_EVENT_DROP_TEXT: UInt32 = UInt32(0x1001)
internal let SDL_EVENT_DROP_BEGIN: UInt32 = UInt32(0x1002)
internal let SDL_EVENT_DROP_COMPLETE: UInt32 = UInt32(0x1003)
internal let SDL_EVENT_DROP_POSITION: UInt32 = UInt32(0x1004)
internal let SDL_EVENT_RENDER_TARGETS_RESET: UInt32 = UInt32(0x2000)
internal let SDL_EVENT_RENDER_DEVICE_RESET: UInt32 = UInt32(0x2001)
internal let SDL_EVENT_RENDER_DEVICE_LOST: UInt32 = UInt32(0x2002)
internal let SDL_SCANCODE_A: Int32 = 4
internal let SDL_SCANCODE_Z: Int32 = 29
internal let SDL_SCANCODE_1: Int32 = 30
internal let SDL_SCANCODE_0: Int32 = 39
internal let SDL_SCANCODE_RETURN: Int32 = 40
internal let SDL_SCANCODE_ESCAPE: Int32 = 41
internal let SDL_SCANCODE_BACKSPACE: Int32 = 42
internal let SDL_SCANCODE_TAB: Int32 = 43
internal let SDL_SCANCODE_SPACE: Int32 = 44
internal let SDL_SCANCODE_HOME: Int32 = 74
internal let SDL_SCANCODE_PAGEUP: Int32 = 75
internal let SDL_SCANCODE_DELETE: Int32 = 76
internal let SDL_SCANCODE_END: Int32 = 77
internal let SDL_SCANCODE_PAGEDOWN: Int32 = 78
internal let SDL_SCANCODE_RIGHT: Int32 = 79
internal let SDL_SCANCODE_LEFT: Int32 = 80
internal let SDL_SCANCODE_DOWN: Int32 = 81
internal let SDL_SCANCODE_UP: Int32 = 82
// Numeric keypad, values from SDL3 `include/SDL3/SDL_scancode.h` (USB usage page 0x07, cluster
// 83..99). The digit order is the trap: `KP_1` is 89 through `KP_9` is 97 and *then* `KP_0` is 98,
// so an offset from `KP_0` would shift every key. The remaining cluster keys (`KP_DIVIDE` 84,
// `KP_MULTIPLY` 85, `KP_MINUS` 86, `KP_PLUS` 87, `KP_PERIOD` 99) have no `Key` variant and stay
// `RawScancode`.
internal let SDL_SCANCODE_KP_ENTER: Int32 = 88
internal let SDL_SCANCODE_KP_1: Int32 = 89
internal let SDL_SCANCODE_KP_2: Int32 = 90
internal let SDL_SCANCODE_KP_3: Int32 = 91
internal let SDL_SCANCODE_KP_4: Int32 = 92
internal let SDL_SCANCODE_KP_5: Int32 = 93
internal let SDL_SCANCODE_KP_6: Int32 = 94
internal let SDL_SCANCODE_KP_7: Int32 = 95
internal let SDL_SCANCODE_KP_8: Int32 = 96
internal let SDL_SCANCODE_KP_9: Int32 = 97
internal let SDL_SCANCODE_KP_0: Int32 = 98
// SDL3 `include/SDL3/SDL_keycode.h`: a keycode for a scancode-backed key is
// `SDLK_SCANCODE_MASK (1 << 30) | scancode`, so the keypad digits are `SDLK_KP_1 = 0x40000059`
// through `SDLK_KP_9 = 0x40000061`, `SDLK_KP_0 = 0x40000062`, and `SDLK_KP_ENTER = 0x40000058`.
// Both identities have to decode: which one SDL fills in depends on the platform bridge.
internal let SDLK_KP_ENTER: UInt32 = UInt32(0x40000058)
internal let SDLK_KP_1: UInt32 = UInt32(0x40000059)
internal let SDLK_KP_2: UInt32 = UInt32(0x4000005A)
internal let SDLK_KP_3: UInt32 = UInt32(0x4000005B)
internal let SDLK_KP_4: UInt32 = UInt32(0x4000005C)
internal let SDLK_KP_5: UInt32 = UInt32(0x4000005D)
internal let SDLK_KP_6: UInt32 = UInt32(0x4000005E)
internal let SDLK_KP_7: UInt32 = UInt32(0x4000005F)
internal let SDLK_KP_8: UInt32 = UInt32(0x40000060)
internal let SDLK_KP_9: UInt32 = UInt32(0x40000061)
internal let SDLK_KP_0: UInt32 = UInt32(0x40000062)
internal let SDL_BUTTON_LEFT: UInt8 = UInt8(1)
internal let SDL_BUTTON_MIDDLE: UInt8 = UInt8(2)
internal let SDL_BUTTON_RIGHT: UInt8 = UInt8(3)
internal let SDL_BLENDMODE_NONE: UInt32 = UInt32(0)
internal let SDL_BLENDMODE_BLEND: UInt32 = UInt32(1)
internal let SDL_TEXTUREACCESS_TARGET: Int32 = 2
internal let SDL_SCALEMODE_LINEAR: Int32 = 1
internal let SDL_PIXELFORMAT_RGBA8888: UInt32 = 0x16462004
internal let SDL_PROGRESS_STATE_INVALID: Int32 = -1
internal let SDL_PROGRESS_STATE_NONE: Int32 = 0
internal let SDL_PROGRESS_STATE_INDETERMINATE: Int32 = 1
internal let SDL_PROGRESS_STATE_NORMAL: Int32 = 2
internal let SDL_PROGRESS_STATE_PAUSED: Int32 = 3
internal let SDL_PROGRESS_STATE_ERROR: Int32 = 4

@C
internal struct SdlRect {
    var x: Int32 = 0
    var y: Int32 = 0
    var w: Int32 = 0
    var h: Int32 = 0
}

@C
internal struct SdlFRect {
    var x: Float32 = 0.0
    var y: Float32 = 0.0
    var w: Float32 = 0.0
    var h: Float32 = 0.0
}

@C
internal struct SdlFPoint {
    var x: Float32 = 0.0
    var y: Float32 = 0.0
}

@C
internal struct SdlPoint {
    var x: Int32 = 0
    var y: Int32 = 0
}

@C
internal struct SdlDisplayMode {
    var displayId: UInt32 = 0
    var pixelFormat: UInt32 = 0
    var w: Int32 = 0
    var h: Int32 = 0
    var pixelDensity: Float32 = 0.0
    var refreshRate: Float32 = 0.0
    var refreshRateNumerator: Int32 = 0
    var refreshRateDenominator: Int32 = 0
    var internalData = CPointer<Unit>()
}

@C
internal struct SdlEvent {
    var padding = VArray<UInt8, $128>(repeat: 0)
}

@C
internal struct SdlCommonEvent {
    var eventType: UInt32 = 0
    var reserved: UInt32 = 0
    var timestamp: UInt64 = 0
}

@C
internal struct SdlWindowEvent {
    var eventType: UInt32 = 0
    var reserved: UInt32 = 0
    var timestamp: UInt64 = 0
    var windowID: UInt32 = 0
    var data1: Int32 = 0
    var data2: Int32 = 0
}

@C
internal struct SdlKeyboardEvent {
    var eventType: UInt32 = 0
    var reserved: UInt32 = 0
    var timestamp: UInt64 = 0
    var windowID: UInt32 = 0
    var which: UInt32 = 0
    var scancode: Int32 = 0
    var key: UInt32 = 0
    var mod: UInt16 = 0
    var raw: UInt16 = 0
    var down: Bool = false
    var repeat: Bool = false
}

@C
internal struct SdlTextInputEvent {
    var eventType: UInt32 = 0
    var reserved: UInt32 = 0
    var timestamp: UInt64 = 0
    var windowID: UInt32 = 0
    var text = CPointer<UInt8>()
}

@C
internal struct SdlTextEditingEvent {
    var eventType: UInt32 = 0
    var reserved: UInt32 = 0
    var timestamp: UInt64 = 0
    var windowID: UInt32 = 0
    var text = CPointer<UInt8>()
    var start: Int32 = 0
    var length: Int32 = 0
}

@C
internal struct SdlTextEditingCandidatesEvent {
    var eventType: UInt32 = 0
    var reserved: UInt32 = 0
    var timestamp: UInt64 = 0
    var windowID: UInt32 = 0
    var candidates = CPointer<CPointer<UInt8>>()
    var count: Int32 = 0
    var selected: Int32 = -1
    var horizontal: Bool = false
    var padding1: UInt8 = 0
    var padding2: UInt8 = 0
    var padding3: UInt8 = 0
}

@C
internal struct SdlRenderEvent {
    var eventType: UInt32 = 0
    var reserved: UInt32 = 0
    var timestamp: UInt64 = 0
    var windowID: UInt32 = 0
}

@C
internal struct SdlUserEvent {
    var eventType: UInt32 = 0
    var reserved: UInt32 = 0
    var timestamp: UInt64 = 0
    var windowID: UInt32 = 0
    var code: Int32 = 0
    var data1 = CPointer<Unit>()
    var data2 = CPointer<Unit>()
}

@C
internal struct SdlMouseMotionEvent {
    var eventType: UInt32 = 0
    var reserved: UInt32 = 0
    var timestamp: UInt64 = 0
    var windowID: UInt32 = 0
    var which: UInt32 = 0
    var state: UInt32 = 0
    var x: Float32 = 0.0
    var y: Float32 = 0.0
    var xrel: Float32 = 0.0
    var yrel: Float32 = 0.0
}

@C
internal struct SdlMouseButtonEvent {
    var eventType: UInt32 = 0
    var reserved: UInt32 = 0
    var timestamp: UInt64 = 0
    var windowID: UInt32 = 0
    var which: UInt32 = 0
    var button: UInt8 = 0
    var down: Bool = false
    var clicks: UInt8 = 0
    var padding: UInt8 = 0
    var x: Float32 = 0.0
    var y: Float32 = 0.0
}

@C
internal struct SdlMouseWheelEvent {
    var eventType: UInt32 = 0
    var reserved: UInt32 = 0
    var timestamp: UInt64 = 0
    var windowID: UInt32 = 0
    var which: UInt32 = 0
    var x: Float32 = 0.0
    var y: Float32 = 0.0
    var direction: UInt32 = 0
    var mouseX: Float32 = 0.0
    var mouseY: Float32 = 0.0
    var integerX: Int32 = 0
    var integerY: Int32 = 0
}

@C
internal struct SdlDropEvent {
    var eventType: UInt32 = 0
    var reserved: UInt32 = 0
    var timestamp: UInt64 = 0
    var windowID: UInt32 = 0
    var x: Float32 = 0.0
    var y: Float32 = 0.0
    var source = CPointer<UInt8>()
    var data = CPointer<UInt8>()
}
