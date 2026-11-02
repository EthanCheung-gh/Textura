package sdl

import std.math.{ceil, floor}

// SDL accepts integer logical clip rectangles. Round the EDGES outwards, rather than
// truncating origin and extent independently (which can erase almost two logical pixels).
// Preserve empty intersections explicitly: rounding must never make them drawable again.
internal func enclosingSdlClipRect(rect: Rect): SdlRect {
    if (rect.x.isNaN() || rect.x.isInf() || rect.y.isNaN() || rect.y.isInf() || rect.w.isNaN() || rect.w.isInf() ||
        rect.h.isNaN() || rect.h.isInf()) {
        throw IllegalArgumentException("Renderer clip coordinates must be finite")
    }
    let left = floor(Float64(rect.x))
    let top = floor(Float64(rect.y))
    let width = if (rect.w <= 0.0) {
        0.0
    } else {
        ceil(Float64(rect.x) + Float64(rect.w)) - left
    }
    let height = if (rect.h <= 0.0) {
        0.0
    } else {
        ceil(Float64(rect.y) + Float64(rect.h)) - top
    }
    if (left < -2147483648.0 || left > 2147483647.0 || top < -2147483648.0 || top > 2147483647.0 || width > 2147483647.0 ||
        height > 2147483647.0 || left + width > 2147483647.0 || top + height > 2147483647.0) {
        throw IllegalArgumentException("Renderer clip exceeds SDL integer coordinates")
    }
    var raw = SdlRect()
    raw.x = Int32(left)
    raw.y = Int32(top)
    raw.w = Int32(width)
    raw.h = Int32(height)
    raw
}
