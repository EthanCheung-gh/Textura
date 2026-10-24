/*
 * Display push: what the ArkUI page tells the host about the real window (docs/DEVICE-NOTES.md §24).
 *
 * WHY a page has to say anything: on HarmonyOS the XComponent owns the surface, and the SDL
 * openharmony video backend keeps the size it adopted when the window was created. Maximising the
 * window therefore changed the ArkUI layout while `SDL_GetWindowSize` kept answering the launch size,
 * so the whole shell stayed laid out for 1930x1020 in a 2880x1620 window (docs/DEVICE-NOTES.md §19.6).
 * The page now measures the surface it was given (context-independent vp -> px) and pushes that size
 * plus the display density through the `textura_keys` NAPI bridge.
 *
 * WHY the host stores it and applies it later: NAPI calls arrive on the ArkUI thread, and SDL calls
 * made from anywhere but the frame thread race the event pump. The C bridge therefore only writes two
 * scalars; `SDL_AppIterate` drains them and calls into SDL itself.
 *
 * WHY the tracker exists: `onAreaChange` fires for every layout pass, and re-applying an identical
 * size would ask SDL to resize to what it already is — a no-op that still emits a resize event and,
 * through the resulting re-layout, another `onAreaChange`. `DisplayPushLog` is the "only when it
 * really changed" gate, and it is the part that host tests can pin down without a device.
 */

package textura.shell

/** One accepted push: the size in window pixels and the display density it was measured at. */
public struct DisplayPush {
    /** Surface width in pixels, as the window manager laid it out. */
    public let pixelWidth: Int64
    /** Surface height in pixels. */
    public let pixelHeight: Int64
    /**
     * Display density (`densityPixels`): 1.0 on a 1x screen, 1.125 / 1.5 / 2.0 on a scaled one. The
     * layout stays in density-independent units, so this converts pixels to logical units.
     */
    public let density: Float32

    public init(pixelWidth: Int64, pixelHeight: Int64, density: Float32) {
        this.pixelWidth = pixelWidth
        this.pixelHeight = pixelHeight
        this.density = density
    }

    /** Surface width in logical units, i.e. what the layout may use. */
    public func logicalWidth(): Int64 {
        logical(pixelWidth, density)
    }

    /** Surface height in logical units. */
    public func logicalHeight(): Int64 {
        logical(pixelHeight, density)
    }

    /**
     * Pixels to logical units, rounded to the nearest unit so a 2880 px surface at 1.125 becomes
     * exactly 2560 instead of 2559 (truncation) or 2561 (ceiling).
     */
    public static func logical(pixels: Int64, density: Float32): Int64 {
        let divisor = Float32(density)
        if (divisor.isNaN() || divisor <= 0.0) {
            return pixels
        }
        let scaled = Int64(Float32(pixels) / divisor + 0.5)
        if (scaled <= 0) {
            1
        } else {
            scaled
        }
    }
}

/**
 * The "did it really change" gate between the ArkUI thread and the frame loop.
 *
 * Densities are compared in thousandths because two float encodings of the same system value must not
 * count as a change; sizes are compared in whole pixels because the manager reports whole pixels.
 * Nothing here touches SDL or CUI, which is what makes the rule testable in `cjpm test`.
 */
public class DisplayPushLog {
    private var appliedWidth: Int64 = -1
    private var appliedHeight: Int64 = -1
    private var appliedDensityMilli: Int64 = -1
    /** Last accepted push; `None` until the page has reported once. */
    private var applied: ?DisplayPush = None

    public init() {}

    /**
     * Returns the push to apply, or `None` when it repeats the accepted one (or is unusable).
     *
     * Unusable means a non-positive / non-finite size or density: a teardown-time `onAreaChange` can
     * report 0x0, and resizing the window to nothing would collapse the layout. Such a push leaves the
     * accepted values untouched, so the next good one is still compared against the real state.
     */
    public func accept(pixelWidth: Int64, pixelHeight: Int64, density: Float32): ?DisplayPush {
        if (pixelWidth <= 0 || pixelHeight <= 0) {
            return None
        }
        if (density.isNaN() || density.isInf() || density <= 0.0) {
            return None
        }
        let densityMilli = Int64(density * Float32(1000.0) + Float32(0.5))
        if (densityMilli == appliedDensityMilli && pixelWidth == appliedWidth && pixelHeight == appliedHeight) {
            return None
        }
        let next = DisplayPush(pixelWidth, pixelHeight, Float32(densityMilli) / Float32(1000.0))
        appliedWidth = pixelWidth
        appliedHeight = pixelHeight
        appliedDensityMilli = densityMilli
        applied = next
        Some(next)
    }

    /** The push currently in force, for diagnostics; `None` before the page reported anything. */
    public func current(): ?DisplayPush {
        applied
    }
}
