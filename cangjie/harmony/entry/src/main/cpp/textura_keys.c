/*
 * TEXTURA-CUI-P05 — ArkTS → SDL bridges that only ArkUI can feed.
 *
 * 1. Keys. The XComponent is the only surface, and SDL's HarmonyOS port receives hardware keys
 *    through OH_NativeXComponent_RegisterKeyEventCallback. That callback is only reached for keys
 *    ArkUI does not consume first. Tab is consumed by ArkUI's focus traversal before the component
 *    sees it, so the shell's focus ring could never be driven from the keyboard (no `ev# KeyDown
 *    key=Tab` line on device, ever). The page root therefore forwards exactly those keys into SDL's
 *    event queue through this module.
 * 2. Surface size + display density (docs/DEVICE-NOTES.md §24). ArkUI owns the XComponent, so the
 *    page is the only place that knows the real visible size; the openharmony video backend never
 *    adopts a size change on its own (maximising left SDL at the launch size). The page pushes the
 *    measured size and `densityPixels` here, and the host applies both to SDL from its frame thread.
 *
 * Everything else is left alone: character keys already reach CUI once text input is focus-driven
 * (TEXTURA-CUI-P05 in CUI), and Escape/Ctrl arrive natively.
 *
 * Why no SDL headers: the HAP ships libSDL3.so but no SDL headers are part of the build, and the
 * event we need is small and stable. SDL_PushEvent is resolved at run time from the already-loaded
 * SDL library, and the union below reproduces SDL3's SDL_KeyboardEvent layout (type / reserved /
 * timestamp / windowID / which / scancode / key / mod / raw / down / repeat) inside a 128-byte
 * buffer, which is larger than SDL_Event and therefore safe to pass. The size and density entry
 * points do not touch SDL at all: they call two scalars in the Cangjie host, so the thread that owns
 * SDL is the only one that calls SDL.
 */
#include <dlfcn.h>
#include <stdint.h>
#include <string.h>

#include "napi/native_api.h"

#define TX_EVENT_KEY_DOWN 0x300u
#define TX_EVENT_KEY_UP 0x301u

/* SDL_Scancode values we forward (SDL_scancode.h). */
#define TX_SCANCODE_TAB 43
#define TX_SCANCODE_LEFT 80
#define TX_SCANCODE_RIGHT 79
#define TX_SCANCODE_UP 82
#define TX_SCANCODE_DOWN 81

/* SDL_Keymod bits (SDL_keycode.h). */
#define TX_KMOD_LSHIFT 0x0001u
#define TX_KMOD_RSHIFT 0x0002u
#define TX_KMOD_LCTRL 0x0040u
#define TX_KMOD_RCTRL 0x0080u
#define TX_KMOD_LALT 0x0100u
#define TX_KMOD_RALT 0x0200u

typedef union {
    uint32_t type;
    struct {
        uint32_t type;
        uint32_t reserved;
        uint64_t timestamp;
        uint32_t window_id;
        uint32_t which;
        int32_t scancode;
        uint32_t key;
        uint16_t mod;
        uint16_t raw;
        uint8_t down;
        uint8_t repeat;
    } key;
    uint8_t padding[128];
} tx_sdl_event;

typedef int (*tx_push_event_fn)(const void *);

static tx_push_event_fn resolve_push_event(void)
{
    static tx_push_event_fn cached = NULL;
    if (cached) {
        return cached;
    }
    /* libSDL3.so is already loaded in this process: the XComponent asked for it. */
    void *sdl = dlopen("libSDL3.so", RTLD_NOW | RTLD_GLOBAL);
    if (!sdl) {
        sdl = RTLD_DEFAULT;
    }
    cached = (tx_push_event_fn)dlsym(sdl, "SDL_PushEvent");
    return cached;
}

static uint32_t shift_mask(bool active)
{
    return active ? (TX_KMOD_LSHIFT | TX_KMOD_RSHIFT) : 0u;
}

/*
 * sendKey(scancode: number, down: boolean, mods: number): boolean
 *
 * `mods` uses SDL_Keymod bits; the caller passes what the ArkUI KeyEvent reported (shift/ctrl/alt).
 * Returns whether SDL accepted the event, so the device log can tell "not delivered" from "filtered".
 */
static napi_value SendKey(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value argv[3] = { NULL, NULL, NULL };
    napi_status status = napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    napi_value result = NULL;
    bool accepted = false;
    if (status == napi_ok && argc >= 2) {
        int32_t scancode = 0;
        bool down = false;
        uint32_t mods = 0;
        uint32_t as_double = 0;
        napi_get_value_int32(env, argv[0], &scancode);
        napi_get_value_bool(env, argv[1], &down);
        if (argc >= 3) {
            /* KeyEvent modifier masks arrive as numbers; accept both int and double encodings. */
            napi_status modStatus = napi_get_value_uint32(env, argv[2], &as_double);
            if (modStatus != napi_ok) {
                double raw = 0.0;
                if (napi_get_value_double(env, argv[2], &raw) == napi_ok) {
                    mods = (uint32_t)raw;
                }
            } else {
                mods = as_double;
            }
        }
        tx_push_event_fn push = resolve_push_event();
        if (push) {
            tx_sdl_event event;
            memset(&event, 0, sizeof(event));
            event.key.type = down ? TX_EVENT_KEY_DOWN : TX_EVENT_KEY_UP;
            event.key.reserved = 0;
            event.key.timestamp = 0;
            event.key.window_id = 0;
            event.key.which = 1;
            event.key.scancode = scancode;
            event.key.key = 0;
            event.key.mod = (uint16_t)mods;
            event.key.raw = (uint16_t)((uint32_t)scancode | (shift_mask((mods & TX_KMOD_LSHIFT) != 0) << 8));
            event.key.down = down ? 1 : 0;
            event.key.repeat = 0;
            accepted = push(&event) == 1;
        }
    }
    napi_get_boolean(env, accepted, &result);
    return result;
}

/*
 * getImeAnchor(): [x, y, w, h] | null
 *
 * The caret rectangle the focused CUI text control reported this frame, in logical pixels. SDL's
 * HarmonyOS backend has no SetTextInputArea implementation (the openharmony video driver never reads
 * the rect), so the system IME cannot learn where the caret is from SDL; the ArkTS page reads it
 * here and passes it as `TextConfig.cursorInfo` when it (re)attaches the input method, which is what
 * makes the candidate window follow the field instead of sitting in a screen corner.
 *
 * The value comes from the Cangjie host's `textura_ime_anchor(index)`; the symbol is resolved with
 * dlsym so this module keeps no link-time dependency on the host library (which is loaded by
 * requireCJLib before the page exists).
 */
typedef int32_t (*tx_ime_anchor_fn)(int32_t);

static napi_value GetImeAnchor(napi_env env, napi_callback_info info)
{
    napi_value result = NULL;
    tx_ime_anchor_fn anchor = NULL;
    void *host = dlopen("libtextura_host.so", RTLD_NOW | RTLD_GLOBAL);
    anchor = (tx_ime_anchor_fn)dlsym(host ? host : RTLD_DEFAULT, "textura_ime_anchor");
    if (!anchor) {
        napi_get_null(env, &result);
        return result;
    }
    int32_t x = anchor(0);
    int32_t y = anchor(1);
    int32_t w = anchor(2);
    int32_t h = anchor(3);
    if (x < 0 || y < 0 || w <= 0 || h <= 0) {
        napi_get_null(env, &result);
        return result;
    }
    napi_create_array_with_length(env, 4, &result);
    napi_value values[4];
    napi_create_int32(env, x, &values[0]);
    napi_create_int32(env, y, &values[1]);
    napi_create_int32(env, w, &values[2]);
    napi_create_int32(env, h, &values[3]);
    for (uint32_t index = 0; index < 4; index++) {
        napi_set_element(env, result, index, values[index]);
    }
    return result;
}

/*
 * setSurfaceSize(width, height): boolean
 *
 * The XComponent's visible size in **pixels**, measured by the page (ArkUI lays out in vp, the page
 * converts with vp2px). ArkUI owns the surface, so it knows this before SDL does — and the openharmony
 * video backend never adopts a later size on its own: maximising the window left `SDL_GetWindowSize`
 * answering the launch size 1930x1020 while the surface was 2880x1620, so the whole shell stayed laid
 * out in the top-left (docs/DEVICE-NOTES.md §19, §24).
 *
 * This module only stores the value in the host library (`textura_push_surface_size`); the host
 * applies it to SDL from its frame thread. Calling SDL_SetWindowSize here would touch the video
 * subsystem from the ArkUI thread, which races SDL's event pump.
 *
 * Returns whether the host accepted the request. `false` means the host library is not loaded yet or
 * the size was rejected; the page keeps its own debounce either way.
 */
typedef void (*tx_push_size_fn)(int32_t, int32_t);
typedef void (*tx_push_density_fn)(float);

/* libtextura_host.so is loaded by requireCJLib in the ability's onCreate, i.e. before this page
 * exists, so the handle is always present unless startup failed. Symbols are resolved on demand and
 * cached, exactly like getImeAnchor does. */
static void *host_handle(void)
{
    static void *host = NULL;
    static bool resolved = false;
    if (!resolved) {
        resolved = true;
        host = dlopen("libtextura_host.so", RTLD_NOW | RTLD_GLOBAL);
    }
    return host;
}

static napi_value SetSurfaceSize(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2] = { NULL, NULL };
    napi_value result = NULL;
    bool accepted = false;
    if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) == napi_ok && argc >= 2) {
        double width = 0.0;
        double height = 0.0;
        if (napi_get_value_double(env, argv[0], &width) == napi_ok &&
            napi_get_value_double(env, argv[1], &height) == napi_ok &&
            width > 0.0 && height > 0.0) {
            tx_push_size_fn push = (tx_push_size_fn)dlsym(host_handle() ? host_handle() : RTLD_DEFAULT,
                "textura_push_surface_size");
            if (push) {
                push((int32_t)(width + 0.5), (int32_t)(height + 0.5));
                accepted = true;
            }
        }
    }
    napi_get_boolean(env, accepted, &result);
    return result;
}

/*
 * setDisplayDensity(density): boolean
 *
 * `display.getDefaultDisplaySync().densityPixels` — 1.0 on a 1x panel, 1.125 / 1.5 / 2.0 on a scaled
 * one. The openharmony backend reports pixel density 1.0 regardless, so without this the layout ran in
 * physical pixels and every control looked small on a high-density monitor. The host installs it as
 * the window's content scale (SDL-P01), which keeps the dp layout and rasterizes it at `density`.
 */
static napi_value SetDisplayDensity(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = { NULL };
    napi_value result = NULL;
    bool accepted = false;
    if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) == napi_ok && argc >= 1) {
        double density = 0.0;
        if (napi_get_value_double(env, argv[0], &density) == napi_ok && density > 0.0) {
            tx_push_density_fn push = (tx_push_density_fn)dlsym(host_handle() ? host_handle() : RTLD_DEFAULT,
                "textura_push_display_density");
            if (push) {
                push((float)density);
                accepted = true;
            }
        }
    }
    napi_get_boolean(env, accepted, &result);
    return result;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "sendKey", NULL, SendKey, NULL, NULL, NULL, napi_default, NULL },
        { "getImeAnchor", NULL, GetImeAnchor, NULL, NULL, NULL, napi_default, NULL },
        { "setSurfaceSize", NULL, SetSurfaceSize, NULL, NULL, NULL, napi_default, NULL },
        { "setDisplayDensity", NULL, SetDisplayDensity, NULL, NULL, NULL, napi_default, NULL },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module g_keys_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = NULL,
    .nm_register_func = Init,
    .nm_modname = "textura_keys",
    .nm_priv = ((void *)0),
    .reserved = { 0 },
};

__attribute__((constructor)) static void RegisterKeysModule(void)
{
    napi_module_register(&g_keys_module);
}
