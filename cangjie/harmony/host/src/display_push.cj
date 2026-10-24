/*
 * ArkUI -> host window push (docs/DEVICE-NOTES.md §24).
 *
 * On HarmonyOS the ArkUI `XComponent` owns the surface, and the SDL openharmony video backend keeps
 * the size it adopted at window creation. Maximising the window therefore moved the ArkUI layout while
 * `SDL_GetWindowSize` kept answering 1930x1020, so every page stayed laid out for the launch size in
 * the top-left of a 2880x1620 window (the "window grew, page did not" symptom of §19).
 *
 * The page now measures the surface it was given and the display density, and pushes both through the
 * `textura_keys` NAPI bridge (`textura_keys.c` -> `setSurfaceSize` / `setDisplayDensity`).
 *
 * Two rules make this safe:
 *
 *   1. NAPI calls arrive on the ArkUI thread and only write two scalars. SDL is touched from
 *      `SDL_AppIterate` — the frame thread — which drains them (see applyDisplayPush). Calling
 *      SDL_SetWindowSize straight from a NAPI callback would race the event pump.
 *   2. `DisplayPushLog` (textura.shell) drops repeats. `onAreaChange` fires for every layout pass, and
 *      re-applying an identical size emits another resize event, which re-lays out the page, which
 *      fires `onAreaChange` again — the loop this gate exists to break.
 */
package textura_host

import cui.DesktopApp
import textura.shell.{DisplayPush, DisplayPushLog}

/*
 * Last values pushed by the page. Written from the ArkUI thread, read from the frame thread; they are
 * plain aligned scalars on purpose — a Cangjie heap object shared across threads would need the
 * runtime's write barrier, and the page sends at most a few values per resize.
 *
 * Defaults describe "nothing pushed yet": a 0x0 size is dropped by DisplayPushLog, and density 1 is
 * the desktop answer, so a page that never calls the bridge behaves exactly like today.
 */
private var pushedSurfaceWidth: Int32 = 0
private var pushedSurfaceHeight: Int32 = 0
private var pushedDensityMilli: Int32 = 1000

/* Survives across frames on the frame thread only. */
private let displayPushLog = DisplayPushLog()

/*
 * `setSurfaceSize(width, height)` from the page: the XComponent's visible size in **pixels**.
 *
 * Called by the C bridge as `textura_push_surface_size`. Rejects non-positive sizes: a teardown-time
 * `onAreaChange` can report 0x0, and shrinking the window to nothing would collapse the layout.
 */
@C
public func textura_push_surface_size(width: Int32, height: Int32): Unit {
    if (width <= 0 || height <= 0) {
        return
    }
    pushedSurfaceWidth = width
    pushedSurfaceHeight = height
}

/*
 * `setDisplayDensity(density)` from the page: `display.getDefaultDisplaySync().densityPixels`.
 *
 * Called by the C bridge as `textura_push_display_density`. Stored in thousandths so the frame thread
 * compares it without float noise, and so a repeated value from a second `onAreaChange` is free.
 */
@C
public func textura_push_display_density(density: Float32): Unit {
    if (density.isNaN() || density.isInf() || density <= 0.0) {
        return
    }
    pushedDensityMilli = Int32(density * Float32(1000.0) + Float32(0.5))
}

/*
 * Hands the pending push to the app, once, on the frame thread. Returns true when something was
 * applied — the caller only uses that for the diagnostic log line.
 *
 * Both halves move together because the density decides how the pixel size becomes logical units:
 * applying the size with the old density would lay out for 2880 columns and then re-lay out for 2560.
 */
public func applyDisplayPush(app: DesktopApp): Bool {
    let density = Float32(pushedDensityMilli) / Float32(1000.0)
    match (displayPushLog.accept(Int64(pushedSurfaceWidth), Int64(pushedSurfaceHeight), density)) {
        case Some(push: DisplayPush) =>
            let adopted = app.applyHostWindow(Int32(push.pixelWidth), Int32(push.pixelHeight), push.density)
            probeDisplayPush(push.pixelWidth, push.pixelHeight, Int64(pushedDensityMilli),
                Int64(adopted.w), Int64(adopted.h))
            true
        case None => false
    }
}
