/*
 * Textura host shell — the Cangjie library the HarmonyOS HAP runs.
 *
 * Startup chain (see cangjie/docs/HARMONY.md §4 for the evidence behind every link):
 *
 *   XComponent(libraryname: 'SDL3')
 *     -> system loads libSDL3.so, whose openharmony backend takes over the surface
 *     -> SDL dlopen("libmain.so")                 [entry C shim: host_bootstrap.c]
 *     -> libmain.so dlsym("SDL_AppInit") here     [this package, loaded by requireCJLib]
 *     -> ArkTS EntryAbility.onCreate called requireCJLib("libtextura_host.so") first, which is
 *        what starts the Cangjie runtime on an ArkTS-bound thread. Nothing in this file (or in
 *        the C shim) may start the runtime itself — doing so raised SIGBUS inside
 *        CJ_MRT_CjRuntimeStart in the reference project.
 *
 * CUI's own DesktopApp.run() blocks in its frame loop, which cannot be used here: the XComponent
 * OnFrame callback is the only thread allowed to touch the surface, so the patched CUI host API
 * (CUI-P01-hosted-frame-step) drives exactly one frame per SDL_AppIterate.
 *
 * The shell contract is the desktop one (`cangjie/src/main.cj`): build an `AppStore` over a
 * workspace document, wrap it in `ShellRuntime` (autosave/toasts/pref persistence) and `ShellHost`,
 * then render `buildShell(host)`. Keep the two entry points in step — when the shell entry changes,
 * this file changes with it, and the cross build is what proves it.
 */
package textura_host

import std.env.*
import std.fs.{Directory, exists}
import cui.*
import sdl.Fonts
import sdl.system.{ApplicationPaths, PerformanceClock}
import textura.core.data.*
import textura.shell.*

/*
 * SDL3 callback result codes (SDL_main.h): continue, success (finish the run), failure.
 * SDL_AppIterate returning SUCCESS is how a hosted run asks SDL to tear the app down.
 */
private let APP_CONTINUE: Int32 = 0
private let APP_SUCCESS: Int32 = 1
private let APP_FAILURE: Int32 = 2

/* SDL_GetPrefPath app label. On the openharmony backend SDL ignores the organization and returns
 * `<filesDir>/<app>/` (application-level files dir), e.g. `/data/storage/el2/base/files/textura/`.
 * The font directory uses the same helper with the label "fonts". */
private let FONT_APP_NAME: String = "fonts"
private let STATE_APP_NAME: String = "textura"
private let WORKSPACE_FILE: String = "workspace.json"
/* `$HOME/.textura/` in the desktop layout, i.e. `<sandbox>/.textura/` on the device. */
private let PREFS_DIR: String = ".textura/"

/* Initial window size. The XComponent owns the real surface and the openharmony backend resizes
 * the window to it, so these numbers are only the first-frame hint (and the shell's initial
 * viewport for layout math). */
private let WINDOW_WIDTH: Int32 = 1440
private let WINDOW_HEIGHT: Int32 = 900

/* Last startup failure, exposed to the C shim as a NUL-terminated string.
 * Cangjie's println() does not reach hilog, so an exception thrown here would otherwise vanish:
 * the shim reads this buffer and reports it through SDL_Log, which does reach hilog. */
private var hostErrorText: String = ""

private func recordHostError(message: String): Unit {
    hostErrorText = message
}

/** Returns the last startup error as a C string; empty when startup has not failed. */
@C
public func textura_host_error(): CString {
    unsafe {
        LibC.mallocCString(hostErrorText)
    }
}

/* DesktopApp enforces a one-run lifecycle, so the single instance lives here for the callbacks. */
private var hostedApp: ?DesktopApp = None
/* The shell the hosted run is rendering; only used to report sandbox facts through the probe. */
private var hostedShell: ?ShellHost = None
private var prefsReported: Bool = false

/** True once a hosted run is live; the shim uses it to keep the log line honest. */
@C
public func textura_host_ready(): Int32 {
    match (hostedApp) {
        case Some(_) => 1
        case None => 0
    }
}

/* ---------------------------------------------------------------- font + theme (before frame 1) */

private func looksLikeFontFile(name: String): Bool {
    let lower = name.toAsciiLower()
    lower.endsWith(".ttf") || lower.endsWith(".ttc") || lower.endsWith(".otf")
}

/* Fonts shipped in the HarmonyOS image, world-readable and present on this device's firmware.
 * Absolute paths never pass through SDL's rawfile layer. */
private let PLATFORM_FONT_PATHS: Array<String> = [
    "/system/fonts/HarmonyOS_Sans_SC.ttf",
    "/system/fonts/NotoSansCJK-Regular.ttc",
    "/system/fonts/HarmonyOS_Sans.ttf"
]

/*
 * Registers a CJK-capable font before the first frame.
 *
 * CUI/SDL_ttf opens fonts through a real filesystem path, so a font inside the HAP's rawfile is
 * unreachable: SDL resolves a relative path against the rawfile root and an absolute one against
 * the filesystem. Two sources are therefore tried in order — a font the operator side-loaded into
 * the app sandbox (`<filesDir>/fonts`, i.e. SDL_GetPrefPath, which is also what `hdc file send`
 * targets), then a font from the device image itself (`PLATFORM_FONT_PATHS`). Whichever opens is
 * registered as "textura-ui" and made the default.
 *
 * Falling back to a bare family *name* is not enough: the bootstrap chain cannot turn a name into a
 * file without a loaded system catalog, so SDL_ttf reports "No usable font" and SDL_AppInit fails
 * before frame 1 (see cangjie/docs/HARMONY.md §7.1c).
 */
private func configureHostFont(): Unit {
    let fallbackFamily = "HarmonyOS Sans SC"
    let fontDir = try {
        ApplicationPaths.preferencePath("textura", FONT_APP_NAME)
    } catch (_: Exception) {
        ""
    }
    if (!fontDir.isEmpty() && registerSideLoadedFont(fontDir)) {
        return
    }
    // Device image fonts, opened by real path. SDL_ttf resolves a registered path through the
    // ordinary filesystem, so nothing here needs the HAP to carry a rawfile. Ordered by CJK
    // coverage: the SC face is the one the shell's Chinese labels are shaped with.
    for (path in PLATFORM_FONT_PATHS) {
        if (registerFontPath(path)) {
            return
        }
    }
    // Last resort: a family name only. The bootstrap chain cannot resolve a bare name to a file, so
    // this path stays dead on a HarmonyOS image that exposes fonts no other way — screen shots of
    // such a launch show SDL_AppInit aborting with "No usable font".
    Fonts.setDefault(Some(fallbackFamily))
}

/* Registers `path` as the UI family when the file is present; returns whether it took effect. */
private func registerFontPath(path: String): Bool {
    if (!looksLikeFontFile(path) || !exists(path)) {
        return false
    }
    try {
        Fonts.register("textura-ui", path)
        Fonts.setDefault(Some("textura-ui"))
        return true
    } catch (_: Exception) {
        return false
    }
}

/* Operator side-loaded directory (`hdc file send` into <filesDir>/fonts): the only way to run a
 * font the device image does not ship. Returns whether a font was registered from it. */
private func registerSideLoadedFont(fontDir: String): Bool {
    let entries = try {
        Directory.readFrom(fontDir)
    } catch (_: Exception) {
        return false
    }
    for (info in entries) {
        if (registerFontPath(fontDir + info.name)) {
            return true
        }
    }
    false
}

/* ------------------------------------------------------------ sandbox paths (HarmonyOS app dir) */

/*
 * The shell persists two things: the workspace document and the UI preferences (last route/theme,
 * palette recents). Both must live inside the application sandbox — the HAP's own directories are
 * read-only and the process working directory is not a place to write.
 *
 * `ApplicationPaths.preferencePath` is SDL_GetPrefPath, which on HarmonyOS returns the
 * application-level files directory with the app label appended:
 *   in-app view   /data/storage/el2/base/files/textura/
 *   shell view    /data/app/el2/100/base/com.ethancheung.textura/files/textura/
 * (The module-level `filesDir` from UIAbility.context is a *different* directory — do not confuse
 * the two; SDL's `OH_AbilityRuntime_ApplicationContextGetFilesDir` is the application one.)
 *
 * `ShellPreferences.load()` resolves `$HOME/.textura/ui-prefs.json`, so HOME is pointed at the same
 * sandbox directory before the shell is built: without it the preferences would fall back to a
 * relative path in a read-only working directory and silently never persist. Writing them is
 * best-effort by design (ShellPreferences.persist swallows I/O errors), so a failure here can
 * never take the UI down.
 */
private func sandboxDir(): ?String {
    try {
        Some(ApplicationPaths.preferencePath("textura", STATE_APP_NAME))
    } catch (_: Exception) {
        None
    }
}

private func prepareSandbox(): ?String {
    let dir = match (sandboxDir()) {
        case Some(value) => value
        case None => return None
    }
    try {
        if (!exists(dir)) {
            Directory.create(dir, recursive: true)
        }
    } catch (_: Exception) {
        return None
    }
    // The preference directory is created here, once and idempotently, instead of being left to
    // `File.writeTo`'s best-effort path: the shell treats a write failure as "retry next build", and a
    // directory that each attempt has to create is one more thing that can fail per frame. Both are
    // cheap (the existence check makes `Directory.create` a no-op) and the whole sandbox layout is
    // then decided in one place.
    try {
        let prefsDir = "${dir}${PREFS_DIR}"
        if (!exists(prefsDir)) {
            Directory.create(prefsDir, recursive: true)
        }
    } catch (_: Exception) {
        // A failure here shows up as `prefs wrote=false` in the probe, not as a broken shell.
    }
    // `ShellPreferences.load(path)` is called with this same directory by `buildShellHost`, so HOME is
    // only a convenience for anything else in the process; it is not what the preferences rely on.
    try {
        setVariable("HOME", dir)
    } catch (_: Exception) {
        ()
    }
    dir
}

/* Preferences live next to the workspace, in the sandbox: `<sandbox>/.textura/ui-prefs.json`. */
private func preferencesFile(dir: ?String): String {
    match (dir) {
        case Some(value) => "${value}${PREFS_DIR}ui-prefs.json"
        case None => "ui-prefs.json"
    }
}

/* -------------------------------------------------------------- workspace + shell construction */

/*
 * AppStore over the sandbox workspace.
 *
 * `store.load` is also the seeding path: a missing or blank document counts as a fresh install and
 * core.data writes the demo workspace back to that path, so the first launch on a device ends up
 * with the same content the desktop app shows (and the second launch loads it instead of reseeding).
 *
 * The clock is injected explicitly — `AppStore` refuses to fall back to the wall clock on its own —
 * and an interactive run is exactly the case where `SystemClock()` is correct (the parity CLI is
 * what freezes time).
 */
private func buildShellHost(dir: ?String, viewportWidth: Int64, viewportHeight: Int64): ShellHost {
    let workspacePath = match (dir) {
        case Some(value) => "${value}${WORKSPACE_FILE}"
        case None => WORKSPACE_FILE
    }
    let prefs = ShellPreferences.load(preferencesFile(dir))
    let store = AppStore(clock: SystemClock())
    var loadError: ?String = None
    try {
        store.load(workspacePath)
    } catch (error: Exception) {
        loadError = Some(error.message)
    }
    // Remembered choice wins over the default, exactly like the desktop entry (`main.cj:45-62`):
    // explicit argv > remembered preference > default, and an interactive launch has no argv.
    let rememberedTheme = prefs.theme == THEME_LIGHT || prefs.theme == THEME_DARK
    store.setTheme(if (rememberedTheme) {
        prefs.theme
    } else {
        THEME_LIGHT
    })
    let initialRoute = match (parseRoute(prefs.route)) {
        case Some(value) => value
        case None => Route.Dashboard
    }
    store.setRoute(routeId(initialRoute))

    let today = match (loadError) {
        case Some(_) => "unknown"
        case None => store.anchorToday()
    }
    let runtime = ShellRuntime(prefs, store)
    // interactive = true: this is a live window, so autosave, toasts and preference persistence all
    // run. A snapshot-style run would pass false (it must not write anything).
    ShellHost(store, runtime, today, true, loadError, viewportWidth, viewportHeight)
}

/* ------------------------------------------------------------------------- IME caret anchor */

/*
 * The caret rectangle the focused text control reported while drawing, in logical pixels.
 *
 * Why this exists: SDL's HarmonyOS port has no `SetTextInputArea` implementation (the openharmony
 * video backend never reads `window->text_input_rect`), so `SDL_SetTextInputArea` is a no-op there —
 * measured in the vendored source. The IME candidate window is positioned by ArkUI's
 * `inputMethodController.attach(showKeyboard, textConfig, …)`, whose `TextConfig.cursorInfo` is the
 * only caret input the system accepts ("absolute coordinate of the physical screen, unit is px").
 * CUI already computes the right rectangle every frame (`UiContext.textInputAnchorRect()`, the same
 * one it hands to `SDL_SetTextInputArea` on desktop); the host therefore republishes it for the
 * ArkTS page, which converts it to screen px and re-attaches the IME with it
 * (docs/DEVICE-NOTES.md §21).
 *
 * Layout vs draw: the anchor is cleared at the start of every frame's draw and set by the focused
 * control while it paints, so the only correct read point is *after* the tree drew — which is what
 * `ImeAnchorView.draw` gives (it is declared last in the root stack, so it paints last).
 */
private var imeAnchor: ?Rect = None

/* Zero-sized publisher for the caret anchor; declared after the shell so it draws after it. */
class ImeAnchorView <: Widget {
    public init() {
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size.zero()
    }

    public func layout(_: UiContext, _: Rect): Unit {}

    public func draw(ctx: UiContext): Unit {
        imeAnchor = ctx.textInputAnchorRect()
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }

    public func participatesInLayout(): Bool {
        false
    }

    public func needsDetachedLayout(): Bool {
        true
    }
}

/*
 * Caret anchor component accessor for the ArkTS side (`textura_keys.c` → `getImeAnchor()`).
 * `index` 0..3 = x / y / w / h in logical pixels; -1 means "no text control has a caret".
 * Four scalars instead of a struct keep the FFI to plain `Int32` in and `Int32` out.
 */
@C
public func textura_ime_anchor(index: Int32): Int32 {
    let rect = match (imeAnchor) {
        case Some(value) => value
        case None => return -1
    }
    match (index) {
        case 0 => Int32(rect.x)
        case 1 => Int32(rect.y)
        case 2 => Int32(rect.w)
        case 3 => Int32(rect.h)
        case _ => -1
    }
}

/* --------------------------------------------------------------------------- SDL entry points */

/*
 * SDL_AppInit: prepares the sandbox, builds the shell host and the declarative root, then hands the
 * frame tick to SDL. Returns SDL_APP_CONTINUE on success and SDL_APP_FAILURE when startup throws.
 */
@C
public func SDL_AppInit(appstate: CPointer<Unit>, argc: Int32, argv: CPointer<Unit>): Int32 {
    try {
        // Fonts first: CUI resolves its default family on the first text node of the first frame.
        configureHostFont()
        let sandbox = prepareSandbox()
        // Diagnostics (probe.cj) write into the same sandbox; off unless an operator created the
        // flag file, so this cannot change a normal run.
        probeConfigure(sandbox)
        let host = buildShellHost(sandbox, Int64(WINDOW_WIDTH), Int64(WINDOW_HEIGHT))
        // The theme for the window chrome comes from the store, so a persisted dark preference also
        // paints the very first frame dark instead of flashing light.
        let theme = themeByName(host.themeName())
        // On HarmonyOS the XComponent owns the surface and the openharmony video backend resizes this
        // window to the surface, so the spec size is only a starting hint. supersample: 1 pins the
        // backing store to 1x — the port reports pixelDensity 1.0 and Auto would rasterize every frame
        // at four times the pixel budget on a software renderer.
        let app = DesktopApp(
            WindowSpec("织理 Textura", WINDOW_WIDTH, WINDOW_HEIGHT, supersample: 1),
            theme: theme
        )
        // Store → CUI invalidation bridge (see `ShellHost.revision`). This is what makes a tap that
        // `store.setRoute` accepts actually repaint: before it, the sidebar navigated the store while
        // CUI's retained tree kept the old route, because no CUI `State` read had changed.
        host.armStoreBridge({action => app.deliver(action)})
        app.beginHostedRun {
            // Capture-phase root listener: records the pointer/key events CUI routes, before any
            // widget can consume them (probe.cj — inert unless the diagnostic build/flag enables it).
            EventListener(phase: EventPhase.Capture, scope: EventScope.Global,
                onEvent: {ctx, event =>
                    probeEvent(ctx, event)
                    EventOutcome.Continue
                }) {
                ZStack {
                    buildShell(host)
                    // Hands the probe the UiContext on frame 1 instead of on the first input event.
                    ProbeContextView()
                    // Republishes the focused caret rect for the IME (see ImeAnchorView).
                    ImeAnchorView()
                }
            }
        }
        hostedApp = app
        hostedShell = Some(host)
        return APP_CONTINUE
    } catch (e: Exception) {
        recordHostError("${e}")
        return APP_FAILURE
    }
}

/*
 * SDL_AppIterate: advances exactly one CUI frame. step() returning false means the UI asked to
 * close, which maps to SDL_APP_SUCCESS.
 */
@C
public func SDL_AppIterate(appstate: CPointer<Unit>): Int32 {
    match (hostedApp) {
        case Some(app) =>
            // Wall time of one hosted frame, measured outermost so it includes input dispatch,
            // build, layout and present. The probe only stores samples when it is enabled.
            let countersBefore = probeCounters()
            let textBefore = probeTextWork()
            let started = PerformanceClock.counter()
            let cont = app.step()
            probeFrame(started, PerformanceClock.counter(), countersBefore, textBefore,
                app.lastFrameUsedPartialDamage(), app.lastFrameCost())
            // Surface a frame failure while the session is still running: after one, input is never
            // dispatched again and the window simply stops changing (CUI-P07).
            probeFailure(match (hostedShell) {
                case Some(host) => host.store.ui.value().route
                case None => "unknown"
            }, app.takeHostedFailure())
            // One line per second: window size, resize count, adopted viewport and the height the
            // visible tree was built with (probe.cj — the resize evidence for docs/DEVICE-NOTES.md §19).
            match (hostedShell) {
                case Some(host) =>
                    probeSize(host.viewportWidth, host.viewportHeight, host.builtViewportHeight)
                case None => ()
            }
            // Preferences are written during a build, so by the second frame the first attempt has
            // happened and its outcome can be reported once.
            if (!prefsReported) {
                match (hostedShell) {
                    case Some(host) =>
                        prefsReported = true
                        probePrefs(host.runtime.prefs.path, host.runtime.prefs.lastWriteOk,
                            host.runtime.prefs.lastWriteError, host.store.ui.value().route)
                    case None => ()
                }
            }
            if (cont) {
                APP_CONTINUE
            } else {
                APP_SUCCESS
            }
        case None => APP_FAILURE
    }
}

/*
 * SDL_AppEvent: CUI polls the SDL event queue itself each frame, so events are not consumed here.
 * Consuming them would double-handle input and desynchronise CUI's hover/press bookkeeping.
 */
@C
public func SDL_AppEvent(appstate: CPointer<Unit>, event: CPointer<Unit>): Int32 {
    APP_CONTINUE
}

/* SDL_AppQuit: releases everything the hosted run owns. */
@C
public func SDL_AppQuit(appstate: CPointer<Unit>, result: Int32): Unit {
    match (hostedApp) {
        case Some(app) => app.endHostedRun()
        case None => ()
    }
    hostedApp = None
    hostedShell = None
}
