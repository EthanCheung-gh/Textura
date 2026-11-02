package textura.ui

import std.collection.ArrayList
import std.math.{atan2, cos, sin, sqrt}
import cui.*

/*
 * A tiny SVG `d` flattener for the Textura glyph set.
 *
 * `src/ui/icons.tsx` describes every icon as inline SVG paths on a 24x24 grid with
 * `stroke="currentColor" strokeWidth={1.75} strokeLinecap="round" strokeLinejoin="round"`.
 * CUI only offers line/rect/circle primitives, so the port flattens the same `d` strings at
 * draw time and strokes the resulting polylines with a round-capped pen — same source data,
 * same geometry, no hand-redrawn approximations.
 *
 * Supported subset (all the icon set uses): M/m, L/l, H/h, V/v, A/a, Z/z, plus implicit
 * lineto after a moveto. Unsupported commands abort the remainder of that path.
 */

private let GLYPH_GRID: Float32 = 24.0
private let GLYPH_STROKE: Float32 = 1.75
private let TWO_PI: Float64 = 6.283185307179586

/** Point on the 24-unit glyph grid. */
public struct GlyphPoint {
    public let x: Float32
    public let y: Float32

    public init(x: Float32, y: Float32) {
        this.x = x
        this.y = y
    }
}

private func isDigit(ch: Rune): Bool {
    ch >= r'0' && ch <= r'9'
}

private func isSeparator(ch: Rune): Bool {
    ch == r' ' || ch == r',' || ch == r'\t' || ch == r'\n' || ch == r'\r'
}

private func isCommand(ch: Rune): Bool {
    match (ch) {
        case r'M' | r'm' | r'L' | r'l' | r'H' | r'h' | r'V' | r'v' | r'A' | r'a' | r'Z' | r'z' => true
        case _ => false
    }
}

private func isLower(ch: Rune): Bool {
    match (ch) {
        case r'm' | r'l' | r'h' | r'v' | r'a' | r'z' => true
        case _ => false
    }
}

/** Reads one `d` attribute into flattened polylines on the 24x24 grid. */
private class SvgPathReader {
    private let runes: Array<Rune>
    private var index: Int64 = 0
    private var command: Rune = r'M'
    private var curX: Float32 = 0.0
    private var curY: Float32 = 0.0
    private var startX: Float32 = 0.0
    private var startY: Float32 = 0.0
    private var current = ArrayList<GlyphPoint>()
    private let finished = ArrayList<Array<GlyphPoint>>()

    init(d: String) {
        runes = d.toRuneArray()
    }

    func flatten(): Array<Array<GlyphPoint>> {
        var guard = 0
        while (true) {
            guard += 1
            if (guard > 4096) {
                break
            }
            skipSeparators()
            if (index >= runes.size) {
                break
            }
            let ch = runes[index]
            if (isCommand(ch)) {
                command = ch
                index += 1
            } else if (command == r'Z' || command == r'z') {
                // A number cannot follow a closepath; stop rather than loop forever.
                break
            } else if (command == r'M') {
                command = r'L'
            } else if (command == r'm') {
                command = r'l'
            }
            let relative = isLower(command)
            match (command) {
                case r'M' | r'm' => moveOrLine(relative)
                case r'L' | r'l' => lineTo(relative)
                case r'H' | r'h' => horizontalTo(relative)
                case r'V' | r'v' => verticalTo(relative)
                case r'A' | r'a' => arcTo(relative)
                case _ => closePath()
            }
        }
        flush()
        finished.toArray()
    }

    private func skipSeparators(): Unit {
        while (index < runes.size && isSeparator(runes[index])) {
            index += 1
        }
    }

    private func readNumber(): ?Float32 {
        skipSeparators()
        if (index >= runes.size) {
            return None
        }
        var sign: Float64 = 1.0
        if (runes[index] == r'-') {
            sign = -1.0
            index += 1
        } else if (runes[index] == r'+') {
            index += 1
        }
        var whole: Float64 = 0.0
        var fraction: Float64 = 0.0
        var scale: Float64 = 1.0
        var any = false
        while (index < runes.size && isDigit(runes[index])) {
            whole = whole * 10.0 + Float64(Int64(UInt32(runes[index]) - UInt32(r'0')))
            index += 1
            any = true
        }
        if (index < runes.size && runes[index] == r'.') {
            index += 1
            while (index < runes.size && isDigit(runes[index])) {
                fraction = fraction * 10.0 + Float64(Int64(UInt32(runes[index]) - UInt32(r'0')))
                scale *= 10.0
                index += 1
                any = true
            }
        }
        if (!any) {
            return None
        }
        Some(Float32(sign * (whole + fraction / scale)))
    }

    private func readPair(): ?GlyphPoint {
        match (readNumber()) {
            case Some(x) =>
                match (readNumber()) {
                    case Some(y) => Some(GlyphPoint(x, y))
                    case None => None
                }
            case None => None
        }
    }

    private func moveOrLine(relative: Bool): Unit {
        match (readPair()) {
            case Some(point) =>
                let x = if (relative) {
                    curX + point.x
                } else {
                    point.x
                }
                let y = if (relative) {
                    curY + point.y
                } else {
                    point.y
                }
                flush()
                curX = x
                curY = y
                startX = x
                startY = y
                current.add(GlyphPoint(x, y))
            case None => index = runes.size
        }
    }

    private func lineTo(relative: Bool): Unit {
        match (readPair()) {
            case Some(point) =>
                let x = if (relative) {
                    curX + point.x
                } else {
                    point.x
                }
                let y = if (relative) {
                    curY + point.y
                } else {
                    point.y
                }
                curX = x
                curY = y
                current.add(GlyphPoint(x, y))
            case None => index = runes.size
        }
    }

    private func horizontalTo(relative: Bool): Unit {
        match (readNumber()) {
            case Some(value) =>
                let x = if (relative) {
                    curX + value
                } else {
                    value
                }
                curX = x
                current.add(GlyphPoint(x, curY))
            case None => index = runes.size
        }
    }

    private func verticalTo(relative: Bool): Unit {
        match (readNumber()) {
            case Some(value) =>
                let y = if (relative) {
                    curY + value
                } else {
                    value
                }
                curY = y
                current.add(GlyphPoint(curX, y))
            case None => index = runes.size
        }
    }

    private func arcTo(relative: Bool): Unit {
        match (readNumber()) {
            case Some(rxValue) =>
                match (readNumber()) {
                    case Some(ryValue) =>
                        match (readNumber()) {
                            case Some(rotation) =>
                                match (readNumber()) {
                                    case Some(largeArc) =>
                                        match (readNumber()) {
                                            case Some(sweepFlag) => readArcTarget(relative, rxValue, ryValue, rotation,
                                                largeArc, sweepFlag)
                                            case None => index = runes.size
                                        }
                                    case None => index = runes.size
                                }
                            case None => index = runes.size
                        }
                    case None => index = runes.size
                }
            case None => index = runes.size
        }
    }

    private func readArcTarget(
        relative: Bool,
        rx: Float32,
        ry: Float32,
        rotation: Float32,
        largeArc: Float32,
        sweepFlag: Float32
    ): Unit {
        match (readPair()) {
            case Some(point) =>
                let x2 = if (relative) {
                    curX + point.x
                } else {
                    point.x
                }
                let y2 = if (relative) {
                    curY + point.y
                } else {
                    point.y
                }
                appendArc(curX, curY, rx, ry, rotation, largeArc > 0.5, sweepFlag > 0.5, x2, y2)
                curX = x2
                curY = y2
            case None => index = runes.size
        }
    }

    // Endpoint-to-centre arc conversion (SVG 1.1 implementation notes F.6.5), sampled into
    // line segments. A zero radius degenerates to a straight line, as the spec requires.
    private func appendArc(
        x1: Float32,
        y1: Float32,
        rxIn: Float32,
        ryIn: Float32,
        rotationDeg: Float32,
        largeArc: Bool,
        sweep: Bool,
        x2: Float32,
        y2: Float32
    ): Unit {
        if (rxIn == 0.0 || ryIn == 0.0) {
            current.add(GlyphPoint(x2, y2))
            return
        }
        var rx = Float64(if (rxIn < 0.0) {
            -rxIn
        } else {
            rxIn
        })
        var ry = Float64(if (ryIn < 0.0) {
            -ryIn
        } else {
            ryIn
        })
        let phi = Float64(rotationDeg) * 3.141592653589793 / 180.0
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx2 = (Float64(x1) - Float64(x2)) / 2.0
        let dy2 = (Float64(y1) - Float64(y2)) / 2.0
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if (lambda > 1.0) {
            let grow = sqrt(lambda)
            rx = rx * grow
            ry = ry * grow
        }
        let rxSq = rx * rx
        let rySq = ry * ry
        let numerator = rxSq * rySq - rxSq * y1p * y1p - rySq * x1p * x1p
        let denominator = rxSq * y1p * y1p + rySq * x1p * x1p
        var coefficient: Float64 = 0.0
        if (denominator > 0.0) {
            let value = if (numerator <= 0.0) {
                0.0
            } else {
                sqrt(numerator / denominator)
            }
            coefficient = if (largeArc == sweep) {
                -value
            } else {
                value
            }
        }
        let cxp = coefficient * (rx * y1p / ry)
        let cyp = coefficient * (-ry * x1p / rx)
        let cx = cosPhi * cxp - sinPhi * cyp + (Float64(x1) + Float64(x2)) / 2.0
        let cy = sinPhi * cxp + cosPhi * cyp + (Float64(y1) + Float64(y2)) / 2.0
        let startAngle = atan2((y1p - cyp) / ry, (x1p - cxp) / rx)
        let endAngle = atan2((-y1p - cyp) / ry, (-x1p - cxp) / rx)
        var sweepAngle = endAngle - startAngle
        if (sweep && sweepAngle < 0.0) {
            sweepAngle += TWO_PI
        } else if (!sweep && sweepAngle > 0.0) {
            sweepAngle -= TWO_PI
        }
        let radius = (rx + ry) / 2.0
        var steps = Int64(radius * (if (sweepAngle < 0.0) {
            -sweepAngle
        } else {
            sweepAngle
        }) / 0.8) + 3
        if (steps > 64) {
            steps = 64
        }
        var step: Int64 = 1
        while (step <= steps) {
            let t = startAngle + sweepAngle * Float64(step) / Float64(steps)
            let px = cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi
            let py = cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi
            current.add(GlyphPoint(Float32(px), Float32(py)))
            step += 1
        }
    }

    private func closePath(): Unit {
        if (!current.isEmpty()) {
            current.add(GlyphPoint(startX, startY))
        }
        flush()
        curX = startX
        curY = startY
    }

    private func flush(): Unit {
        if (current.size >= 2) {
            finished.add(current.toArray())
        }
        current = ArrayList<GlyphPoint>()
    }
}

/** Flattens one SVG `d` string into polylines on the 24-unit grid. */
public func flattenSvgPath(d: String): Array<Array<GlyphPoint>> {
    let reader = SvgPathReader(d)
    reader.flatten()
}

/** Filled circle on the glyph grid (SVG `<circle fill="currentColor">`). */
public struct GlyphDot {
    public let cx: Float32
    public let cy: Float32
    public let r: Float32

    public init(cx: Float32, cy: Float32, r: Float32) {
        this.cx = cx
        this.cy = cy
        this.r = r
    }
}

/** Stroked circle on the glyph grid (SVG `<circle>`). */
public struct GlyphRing {
    public let cx: Float32
    public let cy: Float32
    public let r: Float32

    public init(cx: Float32, cy: Float32, r: Float32) {
        this.cx = cx
        this.cy = cy
        this.r = r
    }
}

/** Stroked rounded rectangle on the glyph grid (SVG `<rect rx>`). */
public struct GlyphBox {
    public let x: Float32
    public let y: Float32
    public let w: Float32
    public let h: Float32
    public let rx: Float32

    public init(x: Float32, y: Float32, w: Float32, h: Float32, rx: Float32) {
        this.x = x
        this.y = y
        this.w = w
        this.h = h
        this.rx = rx
    }
}

/**
 * Paints a glyph into `frame` with the exact SVG stroke geometry: 24-unit grid, 1.75 stroke
 * scaled by the frame, round caps/joins (`strokeLine` is round-capped in SDL3).
 */
public func paintGlyph(
    renderer: Renderer,
    paths: Array<String>,
    rings: Array<GlyphRing>,
    boxes: Array<GlyphBox>,
    dots: Array<GlyphDot>,
    frame: Rect,
    color: Color
): Unit {
    let side = min(frame.w, frame.h)
    if (side <= 0.0) {
        return
    }
    let scale = side / GLYPH_GRID
    let originX = frame.x + (frame.w - side) / 2.0
    let originY = frame.y + (frame.h - side) / 2.0
    let pen = Pen(width: max(1.0, GLYPH_STROKE * scale), color: color)
    for (d in paths) {
        for (polyline in flattenSvgPath(d)) {
            var index = 1
            while (index < polyline.size) {
                let from = polyline[index - 1]
                let to = polyline[index]
                renderer.strokeLine(
                    originX + from.x * scale,
                    originY + from.y * scale,
                    originX + to.x * scale,
                    originY + to.y * scale,
                    pen
                )
                index += 1
            }
        }
    }
    for (ring in rings) {
        renderer.strokeCircle(
            originX + ring.cx * scale,
            originY + ring.cy * scale,
            ring.r * scale,
            pen,
            segments: 32
        )
    }
    for (box in boxes) {
        renderer.strokeRoundedRect(
            Rect(originX + box.x * scale, originY + box.y * scale, box.w * scale, box.h * scale),
            box.rx * scale,
            pen
        )
    }
    for (dot in dots) {
        renderer.fillCircle(originX + dot.cx * scale, originY + dot.cy * scale, dot.r * scale, color)
    }
}
