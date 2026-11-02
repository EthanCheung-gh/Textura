package textura.views.sop

import std.collection.*
import std.deriving.*
import std.math.{floor, sqrt, cos, sin}
import cui.*
import textura.core.data.*
import textura.ui.*
import textura.views.sop.logic as lg

/*
 * Canvas column — `src/modules/sop/SopCanvas.tsx` + `.sop-canvas*` / `.sop-node*` (sop.css:227-556).
 *
 * Structure: `.sop-toolbar` (add-node buttons, run toggle, auto layout, viewport icons),
 * then the `.sop-canvas-flow` pane with the React Flow dot background, smoothstep edges
 * (React Flow's `getSmoothStepPath` geometry, transcribed below), arrow markers, edge
 * labels and the custom nodes.
 *
 * Coordinates: `view.zoom` / `view.panX` / `view.panY` reproduce the React Flow viewport;
 * node coordinates come from `logic` (saved `sop.canvas`, or the compact preview layout).
 */

/** React Flow handle sides (`Position`). */
let SOP_HANDLE_TOP: Int64 = 0
let SOP_HANDLE_BOTTOM: Int64 = 1
let SOP_HANDLE_LEFT: Int64 = 2
let SOP_HANDLE_RIGHT: Int64 = 3

/** React Flow defaults used by the app: `getSmoothStepPath` offset 20 / borderRadius 5. */
let SOP_EDGE_OFFSET: Float64 = 20.0
let SOP_EDGE_BEND: Float64 = 5.0

/** `Background variant="dots" gap={18} size={1} color="var(--border-strong)"`. */
let SOP_DOT_GAP: Float64 = 18.0
/** Safety cap for one dot grid pass: 526×646 at 0.84 zoom needs ~1.5k dots. */
let SOP_DOTS_LIMIT: Int64 = 20000
let SOP_DOT_RADIUS: Float64 = 1.0

/** CSS px at the current canvas zoom (`<csspx> * zoom`), kept in Float32 for layout maths. */
func scaled(value: Float32, zoom: Float64): Float32 {
    Float32(Float64(value) * zoom)
}

/** Route of one smoothstep edge in canvas coordinates, plus the React Flow label anchor. */
class SopEdgePath {
    let points: Array<(Float64, Float64)>
    let labelX: Float64
    let labelY: Float64

    init(points: Array<(Float64, Float64)>, labelX: Float64, labelY: Float64) {
        this.points = points
        this.labelX = labelX
        this.labelY = labelY
    }
}

/** Handle anchor in canvas coordinates. */
func handleAnchor(view: SopFrame, item: Item, side: Int64): (Float64, Float64) {
    let position = view.nodePos(item.id)
    let halfWidth = lg.SOP_NODE_WIDTH / 2.0
    let height = lg.SOP_NODE_HEIGHT
    if (side == SOP_HANDLE_TOP) {
        return (position.x + halfWidth, position.y)
    }
    if (side == SOP_HANDLE_BOTTOM) {
        return (position.x + halfWidth, position.y + height)
    }
    if (side == SOP_HANDLE_LEFT) {
        return (position.x, position.y + height / 2.0)
    }
    return (position.x + lg.SOP_NODE_WIDTH, position.y + height / 2.0)
}

/** `handlesFor` from SopCanvas.tsx:358-376 — picks the handle pair from the node geometry. */
func handlesFor(view: SopFrame, from: Item, to: Item): (Int64, Int64) {
    let a = view.nodePos(from.id)
    let b = view.nodePos(to.id)
    let dx = b.x - a.x
    let dy = b.y - a.y
    if (dy < -20.0) {
        return (SOP_HANDLE_RIGHT, SOP_HANDLE_TOP)
    }
    if (absF(dx) >= absF(dy) * 1.2 && dx > 0.0) {
        return (SOP_HANDLE_RIGHT, SOP_HANDLE_LEFT)
    }
    return (SOP_HANDLE_BOTTOM, SOP_HANDLE_TOP)
}

func absF(value: Float64): Float64 {
    if (value < 0.0) {
        return -value
    }
    return value
}

/**
 * `getSmoothStepPath` (`@xyflow/system`) restricted to the handle pairs this canvas uses;
 * every branch below mirrors the vendored implementation so the routing, the bend radius
 * and the label anchor match the Web build.
 */
func smoothStepPath(view: SopFrame, from: Item, to: Item, sourceSide: Int64, targetSide: Int64): SopEdgePath {
    let source = handleAnchor(view, from, sourceSide)
    let target = handleAnchor(view, to, targetSide)
    let offset = SOP_EDGE_OFFSET
    let sourceDir = handleDirection(sourceSide)
    let targetDir = handleDirection(targetSide)
    let sourceGapped = (source[0] + sourceDir[0] * offset, source[1] + sourceDir[1] * offset)
    let targetGapped = (target[0] + targetDir[0] * offset, target[1] + targetDir[1] * offset)

    // `getDirection`: the primary axis follows the source handle side.
    let horizontal = sourceSide == SOP_HANDLE_LEFT || sourceSide == SOP_HANDLE_RIGHT
    var currDir = 1.0
    if (horizontal) {
        currDir = if (sourceGapped[0] < targetGapped[0]) {
            1.0
        } else {
            -1.0
        }
    } else {
        currDir = if (sourceGapped[1] < targetGapped[1]) {
            1.0
        } else {
            -1.0
        }
    }

    let points = ArrayList<(Float64, Float64)>()
    var labelX = 0.0
    var labelY = 0.0

    let sourceAxis = if (horizontal) {
        sourceDir[0]
    } else {
        sourceDir[1]
    }
    let targetAxis = if (horizontal) {
        targetDir[0]
    } else {
        targetDir[1]
    }

    if (sourceAxis * targetAxis == -1.0) {
        // Opposite handles (Bottom -> Top / Left -> Right): one bent step through the middle.
        if (horizontal) {
            let centerX = sourceGapped[0] + (targetGapped[0] - sourceGapped[0]) * 0.5
            let centerY = (sourceGapped[1] + targetGapped[1]) / 2.0
            if (sourceAxis == currDir) {
                points.add((centerX, sourceGapped[1]))
                points.add((centerX, targetGapped[1]))
            } else {
                points.add((sourceGapped[0], centerY))
                points.add((targetGapped[0], centerY))
            }
            labelX = centerX
            labelY = centerY
        } else {
            let centerX = (sourceGapped[0] + targetGapped[0]) / 2.0
            let centerY = sourceGapped[1] + (targetGapped[1] - sourceGapped[1]) * 0.5
            if (sourceAxis == currDir) {
                points.add((sourceGapped[0], centerY))
                points.add((targetGapped[0], centerY))
            } else {
                points.add((centerX, sourceGapped[1]))
                points.add((centerX, targetGapped[1]))
            }
            labelX = centerX
            labelY = centerY
        }
    } else {
        // Mixed handles (e.g. Right -> Top): a single elbow, flipped so the line leaves the
        // source outward and approaches the target inward (see `flipSourceTarget`).
        var flip = false
        if (sourceSide != targetSide) {
            let sameDir = if (horizontal) {
                sourceDir[0] == targetDir[1]
            } else {
                sourceDir[1] == targetDir[0]
            }
            let sourceGtTargetOppo = if (horizontal) {
                sourceGapped[1] > targetGapped[1]
            } else {
                sourceGapped[0] > targetGapped[0]
            }
            let sourceLtTargetOppo = if (horizontal) {
                sourceGapped[1] < targetGapped[1]
            } else {
                sourceGapped[0] < targetGapped[0]
            }
            let sourcePositive = currDir == 1.0
            flip = (sourcePositive && ((!sameDir && sourceGtTargetOppo) || (sameDir && sourceLtTargetOppo))) ||
                (!sourcePositive && ((!sameDir && sourceLtTargetOppo) || (sameDir && sourceGtTargetOppo)))
        }
        let sourceTarget = (sourceGapped[0], targetGapped[1])
        let targetSource = (targetGapped[0], sourceGapped[1])
        let base = if (horizontal) {
            if (sourceDir[0] == currDir) {
                targetSource
            } else {
                sourceTarget
            }
        } else {
            if (sourceDir[1] == currDir) {
                sourceTarget
            } else {
                targetSource
            }
        }
        let chosen = if (flip) {
            if (horizontal) {
                sourceTarget
            } else {
                targetSource
            }
        } else {
            base
        }
        points.add(chosen)
        // Label goes on the longest of the two elbow segments.
        let maxXDistance = maxF(absF(sourceGapped[0] - chosen[0]), absF(targetGapped[0] - chosen[0]))
        let maxYDistance = maxF(absF(sourceGapped[1] - chosen[1]), absF(targetGapped[1] - chosen[1]))
        if (maxXDistance >= maxYDistance) {
            labelX = (sourceGapped[0] + targetGapped[0]) / 2.0
            labelY = chosen[1]
        } else {
            labelX = chosen[0]
            labelY = (sourceGapped[1] + targetGapped[1]) / 2.0
        }
    }

    // `pathPoints` — insert the gapped ends when they differ from the first/last bent point.
    let pathPoints = ArrayList<(Float64, Float64)>()
    pathPoints.add(source)
    if (sourceGapped[0] != points[0][0] || sourceGapped[1] != points[0][1]) {
        pathPoints.add(sourceGapped)
    }
    for (point in points) {
        pathPoints.add(point)
    }
    let last = points[points.size - 1]
    if (targetGapped[0] != last[0] || targetGapped[1] != last[1]) {
        pathPoints.add(targetGapped)
    }
    pathPoints.add(target)
    return SopEdgePath(pathPoints.toArray(), labelX, labelY)
}

func handleDirection(side: Int64): (Float64, Float64) {
    if (side == SOP_HANDLE_TOP) {
        return (0.0, -1.0)
    }
    if (side == SOP_HANDLE_BOTTOM) {
        return (0.0, 1.0)
    }
    if (side == SOP_HANDLE_LEFT) {
        return (-1.0, 0.0)
    }
    return (1.0, 0.0)
}

func maxF(a: Float64, b: Float64): Float64 {
    if (a > b) {
        return a
    }
    return b
}

func minF(a: Float64, b: Float64): Float64 {
    if (a < b) {
        return a
    }
    return b
}

/** Edge side used for the run highlight (`is-active` when the step is the current one). */
func edgeIsActive(view: SopFrame, edge: Edge): Bool {
    match (view.state.session) {
        case Some(session) => return session.currentId == edge.from
        case None => return false
    }
}

func edgeIsSelected(view: SopFrame, edge: Edge): Bool {
    match (view.state.selectedEdgeId) {
        case Some(id) => return id == edge.id
        case None => return false
    }
}

/** `.sop-canvas` panel: toolbar strip + graph pane. */
func paintCanvas(ctx: UiContext, view: SopFrame): Unit {
    let tk = view.tk
    let panel = view.canvasRect(ctx)
    fillRound(ctx, panel, SOP_RADIUS_PANEL, tk.color.bgSubtle)
    strokeRound(ctx, panel, SOP_RADIUS_PANEL, SOP_BORDER, tk.color.border)

    paintToolbar(ctx, view)

    let flow = view.flow
    if (flow.w <= 0.0 || flow.h <= 0.0) {
        return
    }
    ctx.renderer.fill(flow, tk.color.bgSubtle)
    ctx.renderer.pushClip(flow)
    paintDots(ctx, view)
    if (view.nodes.isEmpty()) {
        paintCanvasEmptyState(ctx, view)
        ctx.renderer.popClip()
        return
    }
    // Edges (React Flow paints them below the nodes).
    for (edge in view.edges) {
        if (edge.edgeType != EdgeType.Flow) {
            continue
        }
        match (view.nodeById(edge.from)) {
            case Some(from) =>
                match (view.nodeById(edge.to)) {
                    case Some(to) =>
                        let sides = handlesFor(view, from, to)
                        let path = smoothStepPath(view, from, to, sides[0], sides[1])
                        paintEdge(ctx, view, edge, path)
                    case None => ()
                }
            case None => ()
        }
    }
    // Nodes.
    for (item in view.nodes) {
        paintNode(ctx, view, item)
    }
    ctx.renderer.popClip()
}

/** `.sop-toolbar` (sop.css:248-272) + group separators. */
func paintToolbar(ctx: UiContext, view: SopFrame): Unit {
    let tk = view.tk
    let toolbar = view.toolbar
    let panel = view.canvasRect(ctx)
    ctx.renderer.fill(Rect(panel.x + 1.0, panel.y + 1.0, panel.w - 2.0, toolbar.height), tk.color.surface)
    paintHLine(ctx, panel.x + 1.0, panel.right() - 1.0, panel.y + 1.0 + toolbar.height, tk.color.border)
    for ((x, top, bottom) in toolbar.separators) {
        paintVLine(ctx, top, bottom, x, tk.color.border)
    }
    let running = view.running()
    for (button in toolbar.buttons) {
        if (button.iconOnly) {
            let tone = if (button.id == "delete") {
                SopTone.Danger
            } else {
                SopTone.Neutral
            }
            let enabled = if (button.id == "delete") {
                view.state.selectedNodeId.isSome() || view.state.selectedEdgeId.isSome()
            } else if (button.id == "undo") {
                view.store.canUndo()
            } else if (button.id == "redo") {
                view.store.canRedo()
            } else {
                true
            }
            paintIconButton(ctx, tk, button.glyph.getOrThrow(), button.rect, tone: tone, enabled: enabled)
            continue
        }
        let enabled = if (button.id.startsWith("add:")) {
            !running
        } else if (button.id == "layout") {
            !running && !view.nodes.isEmpty()
        } else {
            true
        }
        if (button.id == "run") {
            if (running) {
                paintPrimaryButton(ctx, tk, button.label, button.rect, glyph: button.glyph, glyphSide: 13.0,
                    enabled: enabled)
            } else {
                paintSecondaryButton(ctx, tk, button.label, button.rect, glyph: button.glyph, glyphSide: 13.0,
                    enabled: enabled)
            }
            continue
        }
        if (button.id == "layout") {
            paintGhostButton(ctx, tk, button.label, button.rect, glyph: button.glyph, glyphSide: 13.0,
                enabled: enabled)
            continue
        }
        paintGhostButton(ctx, tk, button.label, button.rect, glyph: button.glyph, glyphSide: 13.0, enabled: enabled)
    }
}

/**
 * `Background variant="dots"`: scaled dot grid following the viewport translate (sop.css:280).
 *
 * The grid is clipped to the visible intersection of the flow area and the active renderer
 * clip, and capped by `SOP_DOTS_LIMIT`. Without that cap a mis-sized host rect (for example an
 * unbounded `ScrollView` measure probe) would emit millions of circle meshes per frame, which
 * overflows the SDL geometry batch and crashes later inside unrelated draw calls.
 */
func paintDots(ctx: UiContext, view: SopFrame): Unit {
    var flow = view.flow
    let cell = Float64(SOP_DOT_GAP) * view.zoom
    if (cell < 4.0) {
        return
    }
    if (ctx.renderer.clipEnabled()) {
        let clip = ctx.renderer.clipRect()
        flow = Rect(max(flow.x, clip.x), max(flow.y, clip.y), min(flow.right(), clip.right()) - max(flow.x, clip.x),
            min(flow.bottom(), clip.bottom()) - max(flow.y, clip.y))
    }
    if (flow.w <= 0.0 || flow.h <= 0.0) {
        return
    }
    let columns = Int64(Float64(flow.w) / cell) + 2
    let rows = Int64(Float64(flow.h) / cell) + 2
    if (columns * rows > SOP_DOTS_LIMIT) {
        return
    }
    let color = view.tk.color.borderStrong
    var phaseX = view.panX - floor(view.panX / cell) * cell
    if (phaseX < 0.0) {
        phaseX += cell
    }
    var phaseY = view.panY - floor(view.panY / cell) * cell
    if (phaseY < 0.0) {
        phaseY += cell
    }
    var y = Float64(flow.y) + phaseY + cell / 2.0
    while (y < Float64(flow.bottom())) {
        var x = Float64(flow.x) + phaseX + cell / 2.0
        while (x < Float64(flow.right())) {
            ctx.renderer.fillCircle(Float32(x), Float32(y), Float32(SOP_DOT_RADIUS * view.zoom), color)
            x += cell
        }
        y += cell
    }
}

/** `.sop-canvas-empty` panel shown when the graph has no nodes (SopCanvas.tsx:726-745). */
func paintCanvasEmptyState(ctx: UiContext, view: SopFrame): Unit {
    let tk = view.tk
    let flow = view.flow
    let width = min(420.0, flow.w * 0.88)
    let height: Float32 = 150.0
    let rect = Rect(flow.x + (flow.w - width) / 2.0, flow.y + 32.0, width, height)
    paintShadow1(ctx, tk, rect, SOP_RADIUS_PANEL)
    fillRound(ctx, rect, SOP_RADIUS_PANEL, tk.color.surface)
    strokeRound(ctx, rect, SOP_RADIUS_PANEL, 1.5, tk.color.borderStrong)
    paintTextMid(ctx, "先添加一个开始节点", rect.x, rect.right(), rect.y + 46.0, 14.0, 600, tk.color.text)
    paintTextMid(ctx, "SOP 就是一张可执行的流程图：节点是步骤，连线决定下一步。", rect.x, rect.right(), rect.y + 70.0,
        12.5, 400, tk.color.textMuted)
    let label = "添加开始节点"
    let width2 = SOP_BTN_SM_PAD * 2.0 + 2.0 + contentWidth(ctx, label, Some(IconGlyph.Plus), 14.0, SOP_BTN_SM_FONT)
    let buttonRect = Rect(rect.x + (rect.w - width2) / 2.0, rect.y + 92.0, width2, SOP_BTN_SM_H)
    paintPrimaryButton(ctx, tk, label, buttonRect, glyph: IconGlyph.Plus, glyphSide: 14.0)
}

/** `.react-flow__edge-path` + `markerEnd` arrow + `label`. */
func paintEdge(ctx: UiContext, view: SopFrame, edge: Edge, path: SopEdgePath): Unit {
    let tk = view.tk
    let selected = edgeIsSelected(view, edge)
    let active = edgeIsActive(view, edge)
    let color = if (selected || active) {
        tk.color.accent
    } else {
        tk.color.textFaint
    }
    let width = if (selected) {
        scaled(2.25, view.zoom)
    } else if (active) {
        scaled(2.0, view.zoom)
    } else {
        scaled(SOP_EDGE_W, view.zoom)
    }
    let screen = ArrayList<(Float32, Float32)>()
    for (point in path.points) {
        screen.add((view.screenX(point[0]), view.screenY(point[1])))
    }
    paintOrthogonalPath(ctx, screen.toArray(), Pen(width: max(1.0, width), color: color),
        Float32(SOP_EDGE_BEND * view.zoom))
    paintArrowHead(ctx, screen.toArray(), color, view.zoom)
    if (!edge.label.isEmpty()) {
        paintEdgeLabel(ctx, view, edge.label, view.screenX(path.labelX), view.screenY(path.labelY))
    }
}

/**
 * Orthogonal polyline with rounded corners: every interior corner is cut by the SVG
 * `getBend` radius and re-joined with a quarter arc sampled in four chords.
 */
func paintOrthogonalPath(ctx: UiContext, points: Array<(Float32, Float32)>, pen: Pen, bend: Float32): Unit {
    if (points.size < 2) {
        return
    }
    let shaped = ArrayList<(Float32, Float32)>()
    shaped.add(points[0])
    for (index in 1..points.size - 1) {
        let corner = points[index]
        let previous = points[index - 1]
        let next = points[index + 1]
        let inLength = lengthF(corner[0] - previous[0], corner[1] - previous[1])
        let outLength = lengthF(next[0] - corner[0], next[1] - corner[1])
        let radius = Float32(minF(Float64(bend), minF(inLength, outLength) / 2.0))
        if (radius <= 0.25) {
            shaped.add(corner)
            continue
        }
        shaped.add(stepTowards(corner, previous, radius))
        shaped.add(stepTowards(corner, next, radius))
    }
    shaped.add(points[points.size - 1])
    for (index in 1..shaped.size) {
        let a = shaped[index - 1]
        let b = shaped[index]
        ctx.renderer.strokeLine(a[0], a[1], b[0], b[1], pen)
    }
}

/** Point `distance` away from `from` towards `to`. */
func stepTowards(from: (Float32, Float32), to: (Float32, Float32), distance: Float32): (Float32, Float32) {
    let dx = to[0] - from[0]
    let dy = to[1] - from[1]
    let length = max(lengthF(dx, dy), 0.0001)
    return (Float32(Float64(from[0]) + Float64(dx) / length * Float64(distance)),
        Float32(Float64(from[1]) + Float64(dy) / length * Float64(distance)))
}

func lengthF(dx: Float32, dy: Float32): Float64 {
    Float64(sqrtF(dx * dx + dy * dy))
}

func sqrtF(value: Float32): Float32 {
    Float32(sqrt(Float64(value)))
}

/** React Flow `MarkerType.ArrowClosed` (16x16, `markerUnits="strokeWidth"`) as a filled triangle. */
func paintArrowHead(ctx: UiContext, points: Array<(Float32, Float32)>, color: Color, zoom: Float64): Unit {
    if (points.size < 2) {
        return
    }
    let tip = points[points.size - 1]
    let before = points[points.size - 2]
    var dx = Float64(tip[0] - before[0])
    var dy = Float64(tip[1] - before[1])
    let len = sqrt(dx * dx + dy * dy)
    if (len < 0.0001) {
        return
    }
    dx = dx / len
    dy = dy / len
    // markerWidth 16 * markerUnits(strokeWidth 1.5) / viewBox 20 => 1.2 px per unit,
    // polygon (-5,-4) (0,0) (-5,4) scaled by the viewport zoom as React Flow does.
    let scale = 1.2 * zoom
    let length = 5.0 * scale
    let halfWidth = 4.0 * scale
    let baseX = Float64(tip[0]) - dx * length
    let baseY = Float64(tip[1]) - dy * length
    let corners = ArrayList<Point>()
    corners.add(Point(Float32(baseX - dy * halfWidth), Float32(baseY + dx * halfWidth)))
    corners.add(Point(tip[0], tip[1]))
    corners.add(Point(Float32(baseX + dy * halfWidth), Float32(baseY - dx * halfWidth)))
    ctx.renderer.fillConvexPolygon(corners, color)
}

/** `.react-flow__edge-text` (11px/620 `text-muted`) on a `--surface` background chip. */
func paintEdgeLabel(ctx: UiContext, view: SopFrame, label: String, centerX: Float32, centerY: Float32): Unit {
    let tk = view.tk
    let size = scaled(SOP_EDGE_LABEL_SIZE, view.zoom)
    let width = measureText(ctx, label, size, 620)
    let height = max(textInkHeight(ctx, size, 620) + 4.0, size * 1.5)
    let rect = Rect(centerX - width / 2.0 - 2.0, centerY - height / 2.0, width + 4.0, height)
    fillRound(ctx, rect, 0.0, tk.color.surface)
    paintText(ctx, label, centerX - width / 2.0, centerY, size, 620, tk.color.textMuted)
}

/** Node surface + content (`SopNode.tsx` + `.sop-node*`). */
func paintNode(ctx: UiContext, view: SopFrame, item: Item): Unit {
    let tk = view.tk
    let kind = nodeTypeOf(item)
    let rect = view.nodeRect(item)
    let zoom = view.zoom
    let state = lg.nodeStateFor(item.id, view.runState())
    let selected = match (view.state.selectedNodeId) {
        case Some(id) => id == item.id
        case None => false
    }
    let opacity = match (state) {
        case lg.SopNodeState.Visited => if (isNodeType(kind, lg.SopNodeType.End)) {
            0.72
        } else {
            0.5
        }
        case _ => 1.0
    }
    let radius = if (isNodeType(kind, lg.SopNodeType.Start) || isNodeType(kind, lg.SopNodeType.End)) {
        rect.h / 2.0
    } else {
        scaled(SOP_NODE_RADIUS, zoom)
    }

    // `--shadow-1` under the node surface (skipped for the sticky note, which has none).
    if (!isNodeType(kind, lg.SopNodeType.Note)) {
        paintShadow1(ctx, tk, rect, radius)
    }

    if (isNodeType(kind, lg.SopNodeType.Decision)) {
        paintDecisionNode(ctx, view, rect, state, opacity)
    } else {
        var fill = tk.color.surface
        var borderColor = tk.color.borderStrong
        let borderWidth = scaled(SOP_BORDER, view.zoom)
        if (isNodeType(kind, lg.SopNodeType.Start)) {
            borderColor = fade(tk.color.ok, opacity)
        } else if (isNodeType(kind, lg.SopNodeType.End)) {
            fill = fade(tk.color.text, opacity)
            borderColor = fade(tk.color.text, opacity)
        } else if (isNodeType(kind, lg.SopNodeType.Check)) {
            borderColor = fade(tk.color.info, opacity)
        } else if (isNodeType(kind, lg.SopNodeType.Note)) {
            fill = fade(tk.color.surface2, opacity)
            borderColor = fade(tk.color.borderStrong, opacity)
        }
        fillRound(ctx, rect, radius, fill)
        if (isNodeType(kind, lg.SopNodeType.Note)) {
            // `.sop-node--note .sop-node-surface { border-style: dashed }`
            ctx.renderer.strokeRoundedRectDashed(rect, radius, Pen(width: borderWidth, color: borderColor),
                dash: 3.0, gap: 2.0)
        } else {
            strokeRound(ctx, rect, radius, borderWidth, borderColor)
        }
        if (isNodeType(kind, lg.SopNodeType.Start)) {
            // `box-shadow: inset 0 0 0 1px var(--ok)` — a second ring just inside the border.
            strokeRound(ctx, rect.inset(1.5), radius - 1.5, 1.0, fade(tk.color.ok, opacity))
        }
        if (isNodeType(kind, lg.SopNodeType.Check)) {
            // `box-shadow: inset 3px 0 0 var(--info)` — left semantic bar.
            let barWidth = Float32(3.0 * zoom)
            ctx.renderer.pushClip(rect)
            fillRound(ctx, Rect(rect.x, rect.y, barWidth + radius, rect.h), radius, fade(tk.color.info, opacity))
            ctx.renderer.popClip()
        }
    }

    // Run highlight rings (`.sop-node[data-state=…]`).
    match (state) {
        case lg.SopNodeState.Current =>
            strokeRound(ctx, rect.inset(scaled(SOP_BORDER, view.zoom)), radius,
                scaled(SOP_BORDER, view.zoom), fade(tk.color.accent, opacity))
            ctx.renderer.strokeRoundedRect(rect.inset(-3.0), radius + 3.0,
                Pen(width: 3.0, color: tk.color.accentSoft))
        case lg.SopNodeState.Failed =>
            strokeRound(ctx, rect.inset(-2.0), radius + 2.0, 2.0, tk.color.danger)
        case _ => ()
    }
    if (selected) {
        // `outline: 2px solid var(--accent); outline-offset: 2px`
        strokeRound(ctx, rect.inset(-3.0), radius + 3.0, 2.0, tk.color.accent)
    }

    paintNodeContent(ctx, view, item, kind, rect, state, opacity)
    paintNodeHandles(ctx, view, rect, radius, opacity)
}

/** Content of a rectangular node: title line, meta line, optional checklist progress. */
func paintNodeContent(
    ctx: UiContext,
    view: SopFrame,
    item: Item,
    kind: lg.SopNodeType,
    rect: Rect,
    state: lg.SopNodeState,
    opacity: Float64
): Unit {
    let tk = view.tk
    let zoom = Float32(view.zoom)
    let pill = isNodeType(kind, lg.SopNodeType.Start) || isNodeType(kind, lg.SopNodeType.End)
    let padX = if (pill) {
        scaled(18.0, view.zoom)
    } else if (isNodeType(kind, lg.SopNodeType.Decision)) {
        scaled(16.0, view.zoom)
    } else {
        scaled(SOP_NODE_PAD_X, view.zoom)
    }
    let padY = scaled(SOP_NODE_PAD_Y, view.zoom)
    let titleLine = scaled(SOP_NODE_TITLE_LINE, view.zoom)
    let metaLine = scaled(SOP_NODE_META_LINE, view.zoom)
    let gap = scaled(SOP_NODE_INNER_GAP, view.zoom)
    let titleSize = scaled(SOP_NODE_TITLE_SIZE, view.zoom)
    let metaSize = scaled(SOP_NODE_META_SIZE, view.zoom)

    let titleColor = fade(if (isNodeType(kind, lg.SopNodeType.End)) {
        tk.color.bg
    } else {
        tk.color.text
    }, opacity)
    let kindColor = fade(nodeKindColor(tk, kind), opacity)

    let contentLeft = rect.x + padX
    let contentRight = rect.right() - padX
    let titleCenter = rect.y + padY + titleLine / 2.0
    paintNodeTitle(ctx, view, item, kind, contentLeft, contentRight, titleCenter, titleSize, titleColor, pill,
        opacity)

    let metaCenter = rect.y + padY + titleLine + gap + metaLine / 2.0
    paintNodeMeta(ctx, view, item, kind, contentLeft, contentRight, metaCenter, metaSize, kindColor, titleColor, pill,
        opacity)

    // `.sop-node-progress`: 3px info track (only when the step has checklist entries).
    match (item.sop) {
        case Some(data) =>
            if (!data.checklist.isEmpty()) {
                let done = lg.checklistDoneCount(toSopNode(item))
                let total = data.checklist.size
                let percent: Float32 = if (total > 0) {
                    Float32(done) / Float32(total)
                } else {
                    0.0
                }
                let top = rect.y + padY + titleLine + gap + metaLine + gap
                let height = scaled(3.0, view.zoom)
                let outer = Rect(contentLeft, top, contentRight - contentLeft, height)
                fillRound(ctx, outer, height / 2.0, fade(tk.color.surface2, opacity))
                if (percent > 0.0) {
                    ctx.renderer.pushClip(outer)
                    fillRound(ctx, Rect(outer.x, outer.y, outer.w * percent, height), height / 2.0,
                        fade(tk.color.info, opacity))
                    ctx.renderer.popClip()
                }
            }
        case None => ()
    }
    let _ = state
}

func paintNodeTitle(
    ctx: UiContext,
    view: SopFrame,
    item: Item,
    kind: lg.SopNodeType,
    left: Float32,
    right: Float32,
    centerY: Float32,
    size: Float32,
    color: Color,
    centered: Bool,
    opacity: Float64
): Unit {
    let _ = view
    let _ = kind
    let _ = opacity
    let title = item.title
    if (centered) {
        paintTextMid(ctx, ellipsize(ctx, title, right - left, size, 620), left, right, centerY, size, 620, color)
    } else {
        paintText(ctx, ellipsize(ctx, title, right - left, size, 620), left, centerY, size, 620, color)
    }
}

func paintNodeMeta(
    ctx: UiContext,
    view: SopFrame,
    item: Item,
    kind: lg.SopNodeType,
    left: Float32,
    right: Float32,
    centerY: Float32,
    size: Float32,
    kindColor: Color,
    baseColor: Color,
    centered: Bool,
    opacity: Float64
): Unit {
    let tk = view.tk
    let zoom = Float32(view.zoom)
    let label = nodeTypeLabel(kind)
    var parts = ArrayList<String>()
    var owner = ""
    var duration: ?Int64 = None
    var checkDone = 0
    var checkTotal = 0
    match (item.sop) {
        case Some(data) =>
            match (data.owner) {
                case Some(value) => owner = value
                case None => ()
            }
            duration = data.durationMin
            checkTotal = data.checklist.size
            for (entry in data.checklist) {
                if (entry.done) {
                    checkDone += 1
                }
            }
        case None => ()
    }
    if (!owner.isEmpty()) {
        parts.add(owner)
    }
    match (duration) {
        case Some(minutes) =>
            if (minutes > 0) {
                parts.add("${minutes} 分钟")
            }
        case None => ()
    }
    let metaColor = fade(tk.color.textFaint, opacity)
    var cursor = left
    var usedWidth = measureText(ctx, label, size, 600) + measureText(ctx, " · ", size, 400) * Float32(parts.size)
    if (centered) {
        var total = measureText(ctx, label, size, 600)
        for (part in parts) {
            total += measureText(ctx, part, size, 400) + measureText(ctx, " · ", size, 400)
        }
        cursor = left + max(0.0, (right - left - total) / 2.0)
    }
    paintText(ctx, label, cursor, centerY, size, 600, kindColor)
    cursor += measureText(ctx, label, size, 600)
    for (part in parts) {
        paintText(ctx, " · ", cursor, centerY, size, 400, metaColor)
        cursor += measureText(ctx, " · ", size, 400)
        paintText(ctx, part, cursor, centerY, size, 400, metaColor)
        cursor += measureText(ctx, part, size, 400)
    }
    if (checkTotal > 0 && !centered) {
        let countText = "${checkDone}/${checkTotal}"
        let width = measureText(ctx, countText, size, 400)
        paintText(ctx, countText, right - width, centerY, size, 400, fade(tk.color.textMuted, opacity))
    }
    let _ = usedWidth
    let _ = zoom
}

/** `.sop-node-kind` colours per node type (start=ok, decision=warn, check=info, end=bg). */
func nodeKindColor(tk: ThemeTokens, kind: lg.SopNodeType): Color {
    match (kind) {
        case lg.SopNodeType.Start => return tk.color.ok
        case lg.SopNodeType.Decision => return tk.color.warn
        case lg.SopNodeType.Check => return tk.color.info
        case lg.SopNodeType.End => return tk.color.bg
        case _ => return tk.color.textMuted
    }
}

/** `.sop-node-handle`: 9px surface circle with a 1.5px `border-strong` ring. */
func paintNodeHandles(ctx: UiContext, view: SopFrame, rect: Rect, radius: Float32, opacity: Float64): Unit {
    let tk = view.tk
    let _ = radius
    let radiusPx = scaled(SOP_NODE_HANDLE / 2.0, view.zoom)
    let points = [
        (rect.centerX(), rect.y),
        (rect.centerX(), rect.bottom()),
        (rect.x, rect.centerY()),
        (rect.right(), rect.centerY())
    ]
    for ((x, y) in points) {
        ctx.renderer.fillCircle(x, y, radiusPx, fade(tk.color.surface, opacity))
        ctx.renderer.strokeCircle(x, y, radiusPx, Pen(width: scaled(1.5, view.zoom),
            color: fade(tk.color.borderStrong, opacity)))
    }
}

/** `.sop-node--decision`: `skewX(-10deg)` parallelogram with a 1.5px warn border. */
func paintDecisionNode(ctx: UiContext, view: SopFrame, rect: Rect, state: lg.SopNodeState, opacity: Float64): Unit {
    let tk = view.tk
    let skew = Float64(rect.h) / 2.0 * 0.17632698070846498 // tan(10deg)
    let corners = ArrayList<Point>()
    corners.add(Point(Float32(Float64(rect.x) + skew), rect.y))
    corners.add(Point(rect.right(), rect.y))
    corners.add(Point(Float32(Float64(rect.right()) - skew), rect.bottom()))
    corners.add(Point(rect.x, rect.bottom()))
    ctx.renderer.fillConvexPolygon(corners, fade(tk.color.surface, opacity))
    let pen = Pen(width: scaled(1.5, view.zoom), color: fade(tk.color.warn, opacity))
    for (index in 0..corners.size) {
        let a = corners[index]
        let b = corners[(index + 1) % corners.size]
        ctx.renderer.strokeLine(a.x, a.y, b.x, b.y, pen)
    }
    let _ = state
}

/** Applies the `visited` opacity to a token colour. */
func fade(color: Color, opacity: Float64): Color {
    if (opacity >= 1.0) {
        return color
    }
    withOpacity(color, Float32(opacity))
}

/** Canvas interaction: node drag, pane pan, zoom, toolbar buttons, selection. */
func handleCanvas(ctx: UiContext, view: SopFrame, event: UiEvent): Bool {
    match (event) {
        case UiEvent.MouseDown(pressButton, x, y) where isPrimaryPointerButton(pressButton) =>
            if (handleToolbarClick(ctx, view, x, y)) {
                return true
            }
            if (!view.flow.contains(x, y)) {
                return false
            }
            // Node under the cursor wins over the pane.
            for (item in reversedItems(view)) {
                let rect = view.nodeRect(item)
                if (rect.contains(x, y)) {
                    stateSelectNode(view, item)
                    if (!view.running()) {
                        beginNodeDrag(view, item, x, y)
                    }
                    return true
                }
            }
            // Edge hit-test: within 6px of the routed path.
            for (edge in view.edges) {
                if (edge.edgeType != EdgeType.Flow) {
                    continue
                }
                match (view.nodeById(edge.from)) {
                    case Some(from) => match (view.nodeById(edge.to)) {
                        case Some(to) =>
                            let sides = handlesFor(view, from, to)
                            let path = smoothStepPath(view, from, to, sides[0], sides[1])
                            if (pathHit(view, path, x, y)) {
                                view.state.selectedNodeId = None
                                view.state.selectedEdgeId = Some(edge.id)
                                view.store.select(Option<String>.None)
                                view.state.touch()
                                return true
                            }
                        case None => ()
                    }
                    case None => ()
                }
            }
            // Pane: clear the selection and start a pan gesture.
            view.state.selectedNodeId = None
            view.state.selectedEdgeId = None
            view.store.select(Option<String>.None)
            view.state.panning = true
            view.state.panFromX = Float64(x)
            view.state.panFromY = Float64(y)
            view.state.panStartX = view.state.panX
            view.state.panStartY = view.state.panY
            view.state.touch()
            return true
        case UiEvent.MouseMove(x, y) =>
            match (view.state.dragNodeId) {
                case Some(_) =>
                    let grabX = view.state.dragGrabX
                    let grabY = view.state.dragGrabY
                    let targetX = view.flowXAt(x) - grabX
                    let targetY = view.flowYAt(y) - grabY
                    view.state.dragPosX = targetX
                    view.state.dragPosY = targetY
                    view.state.dragMoved = true
                    view.state.touch()
                    return true
                case None => ()
            }
            if (view.state.panning) {
                view.state.panX = view.state.panStartX + (Float64(x) - view.state.panFromX)
                view.state.panY = view.state.panStartY + (Float64(y) - view.state.panFromY)
                view.state.touch()
                return true
            }
            return false
        case UiEvent.MouseUp(_, _, _) =>
            var handled = false
            match (view.state.dragNodeId) {
                case Some(id) =>
                    commitNodeDrag(view, id)
                    handled = true
                case None => ()
            }
            if (view.state.panning) {
                view.state.panning = false
                handled = true
            }
            if (handled) {
                view.state.touch()
            }
            return handled
        case UiEvent.MouseWheel(_, wheelY, x, y) =>
            // (wheelX, wheelY, mouseX, mouseY): zoom needs the pointer, not the scroll delta.
            if (!view.flow.contains(x, y) || wheelY == 0.0) {
                return false
            }
            zoomAt(view, x, y, if (wheelY > 0.0) {
                0.9
            } else {
                1.1
            })
            return true
        case _ => return false
    }
}

func reversedItems(view: SopFrame): Array<Item> {
    let result = ArrayList<Item>()
    var index = view.nodes.size - 1
    while (index >= 0) {
        result.add(view.nodes[index])
        index -= 1
    }
    result.toArray()
}

func pathHit(view: SopFrame, path: SopEdgePath, x: Float32, y: Float32): Bool {
    let threshold = scaled(7.0 + 4.0, view.zoom)
    for (index in 1..path.points.size) {
        let a = path.points[index - 1]
        let b = path.points[index]
        let ax = view.screenX(a[0])
        let ay = view.screenY(a[1])
        let bx = view.screenX(b[0])
        let by = view.screenY(b[1])
        if (distanceToSegment(x, y, ax, ay, bx, by) <= threshold) {
            return true
        }
    }
    return false
}

func distanceToSegment(px: Float32, py: Float32, ax: Float32, ay: Float32, bx: Float32, by: Float32): Float32 {
    let dx = bx - ax
    let dy = by - ay
    let lengthSquared = dx * dx + dy * dy
    if (lengthSquared < 0.0001) {
        return sqrtF((px - ax) * (px - ax) + (py - ay) * (py - ay))
    }
    var t = ((px - ax) * dx + (py - ay) * dy) / lengthSquared
    t = max(0.0, min(1.0, t))
    let cx = ax + dx * t
    let cy = ay + dy * t
    return sqrtF((px - cx) * (px - cx) + (py - cy) * (py - cy))
}

/** Node selection writes back to the store (`store.select`) and clears the edge selection. */
func stateSelectNode(view: SopFrame, item: Item): Unit {
    view.state.selectedNodeId = Some(item.id)
    view.state.selectedEdgeId = None
    view.store.select(item.id)
    view.state.touch()
}

func beginNodeDrag(view: SopFrame, item: Item, x: Float32, y: Float32): Unit {
    // Materialise the preview layout first so a drag never leaves half of the graph at
    // preview coordinates (SopCanvas.tsx:439-445).
    if (view.previewActive) {
        materializePreview(view)
    }
    let position = view.nodePos(item.id)
    view.state.dragNodeId = Some(item.id)
    view.state.dragGrabX = view.flowXAt(x) - position.x
    view.state.dragGrabY = view.flowYAt(y) - position.y
    view.state.dragPosX = position.x
    view.state.dragPosY = position.y
    view.state.dragMoved = false
}

/** Writes the dragged node's canvas coordinates back through the store. */
func commitNodeDrag(view: SopFrame, id: String): Unit {
    let x = view.state.dragPosX
    let y = view.state.dragPosY
    view.state.dragNodeId = None
    if (!view.state.dragMoved) {
        return
    }
    let patch = SopPatch()
    patch.canvasX = SetValue<Float64>.Value(Float64(jsRound(x)))
    patch.canvasY = SetValue<Float64>.Value(Float64(jsRound(y)))
    let itemPatch = ItemPatch().withSop(patch)
    view.store.updateItems([ItemPatchTarget(id, itemPatch)])
    view.state.previewDisabled = true
}

/** `Math.round` semantics (half up), matching the Web drag handler. */
func jsRound(value: Float64): Int64 {
    Int64(floor(value + 0.5))
}

/** Writes the whole preview layout to the store (SopCanvas.tsx:439-445). */
func materializePreview(view: SopFrame): Unit {
    if (!view.previewActive) {
        return
    }
    let updates = ArrayList<ItemPatchTarget>()
    for (item in view.nodes) {
        let position = view.nodePos(item.id)
        let savedPosition = if (view.saved.contains(item.id)) {
            view.saved[item.id]
        } else {
            lg.SopPosition(-1.0, -1.0)
        }
        if (position.x == savedPosition.x && position.y == savedPosition.y) {
            continue
        }
        let patch = SopPatch()
        patch.canvasX = SetValue<Float64>.Value(Float64(jsRound(position.x)))
        patch.canvasY = SetValue<Float64>.Value(Float64(jsRound(position.y)))
        updates.add(ItemPatchTarget(item.id, ItemPatch().withSop(patch)))
    }
    if (!updates.isEmpty()) {
        view.store.updateItems(updates.toArray())
    }
    view.state.previewDisabled = true
}

/** Viewport zoom around the cursor (`zoomIn/zoomOut` + wheel zoom). */
func zoomAt(view: SopFrame, x: Float32, y: Float32, factor: Float64): Unit {
    let previous = view.state.zoom
    var next = previous * factor
    next = clampF64(next, lg.MIN_ZOOM, 1.8)
    if (next == previous) {
        return
    }
    let flowX = view.flowXAt(x)
    let flowY = view.flowYAt(y)
    view.state.zoom = next
    view.state.panX = Float64(x) - Float64(view.flow.x) - flowX * next
    view.state.panY = Float64(y) - Float64(view.flow.y) - flowY * next
    view.state.touch()
}

func clampF64(value: Float64, low: Float64, high: Float64): Float64 {
    if (value < low) {
        return low
    }
    if (value > high) {
        return high
    }
    return value
}

/** `fitView({ padding, maxZoom })` — re-centres on the whole graph (`fit.cj` policy). */
func fitToContent(view: SopFrame): Unit {
    let bounds = lg.boundsOfPositions(view.display, nodeWidth: lg.SOP_NODE_WIDTH, nodeHeight: lg.FIT_NODE_HEIGHT)
    match (bounds) {
        case Some(value) =>
            let fitted = lg.computeReadableViewport(
                lg.ReadableFitOptions(Float64(view.flow.w), Float64(view.flow.h), value, padding: lg.INITIAL_FIT_PADDING,
                    minZoom: lg.MIN_ZOOM, maxZoom: lg.MAX_FIT_ZOOM)
            )
            view.state.zoom = fitted.zoom
            view.state.panX = fitted.viewport.x
            view.state.panY = fitted.viewport.y
            view.state.touch()
        case None => ()
    }
}

/** Toolbar buttons: add node / run / auto layout / fit / zoom / undo / redo / delete. */
func handleToolbarClick(ctx: UiContext, view: SopFrame, x: Float32, y: Float32): Bool {
    let toolbar = view.toolbar
    for (button in toolbar.buttons) {
        if (!button.rect.contains(x, y)) {
            continue
        }
        let id = button.id
        if (id.startsWith("add:")) {
            match (lg.parseNodeType(id.split("add:")[1])) {
                case Some(kind) => return addNode(view, kind)
                case None => return false
            }
        }
        match (id) {
            case "run" => return toggleRun(ctx, view)
            case "layout" => return autoLayout(view)
            case "fit" =>
                fitToContent(view)
                return true
            case "zoom-in" =>
                zoomAtCenter(view, 1.2)
                return true
            case "zoom-out" =>
                zoomAtCenter(view, 1.0 / 1.2)
                return true
            case "undo" =>
                view.store.undo()
                fitToContent(view)
                return true
            case "redo" =>
                view.store.redo()
                fitToContent(view)
                return true
            case "delete" => return deleteSelection(view)
            case _ => return false
        }
    }
    return false
}

func zoomAtCenter(view: SopFrame, factor: Float64): Unit {
    zoomAt(view, view.flow.centerX(), view.flow.centerY(), factor)
}

/** New node at the viewport centre, linked from the selected node (SopCanvas.tsx:518-556). */
func addNode(view: SopFrame, kind: lg.SopNodeType): Bool {
    if (view.running()) {
        return true
    }
    materializePreview(view)
    let centerX = view.flowXAt(view.flow.centerX())
    let centerY = view.flowYAt(view.flow.centerY())
    let title = match (kind) {
        case lg.SopNodeType.Start => "开始"
        case lg.SopNodeType.Decision => "条件判断？"
        case lg.SopNodeType.Check => "新检查项"
        case lg.SopNodeType.End => "结束"
        case lg.SopNodeType.Note => "便签"
        case _ => "新行动"
    }
    let sopPatch = SopPatch()
    sopPatch.nodeType = SetValue<SopNodeType>.Value(coreNodeType(kind))
    sopPatch.canvasX = SetValue<Float64>.Value(Float64(jsRound(centerX - lg.SOP_NODE_WIDTH / 2.0)))
    sopPatch.canvasY = SetValue<Float64>.Value(Float64(jsRound(centerY - 30.0)))
    if (isNodeType(kind, lg.SopNodeType.Check)) {
        sopPatch.checklist = SetValue<Array<ChecklistEntry>>.Value([ChecklistEntry("chk_1", "检查项", false)])
    }
    let parentId = match (view.sop) {
        case Some(sop) => sop.id
        case None => ""
    }
    let areaId: ?String = match (view.sop) {
        case Some(sop) => sop.areaId
        case None => Option<String>.None
    }
    let input = NewItemInput(ItemKind.Step, title, parentId: parentId, status: Some(ItemStatus.Next),
        areaId: areaId, sop: sopPatch)
    let created = view.store.createItem(input)
    match (view.state.selectedNodeId) {
        case Some(from) => view.store.createEdge(from, created.id, EdgeType.Flow, label: "")
        case None => ()
    }
    view.state.selectedNodeId = Some(created.id)
    view.state.selectedEdgeId = None
    view.store.select(created.id)
    view.state.previewDisabled = true
    view.state.touch()
    return true
}

/** Logic node type -> core `SopNodeType` (store patch), via the shared wire id. */
func coreNodeType(kind: lg.SopNodeType): SopNodeType {
    match (parseSopNodeType(lg.nodeTypeId(kind))) {
        case Some(value) => return value
        case None => return SopNodeType.Action
    }
}

/** `handleAutoLayout` — dagre-equivalent TB layout through the logic package. */
func autoLayout(view: SopFrame): Bool {
    if (view.nodes.isEmpty() || view.running()) {
        return true
    }
    let ids = ArrayList<String>()
    for (item in view.nodes) {
        ids.add(item.id)
    }
    // `{ rankdir: 'TB', nodesep: 60, ranksep: 90, margin: 40 }` (SopCanvas.tsx:561-565).
    let options = lg.LayoutOptions(rankdir: lg.RankDir.TopDown, nodesep: 60.0, ranksep: 90.0, margin: 40.0)
    let positions = lg.layoutIds(ids.toArray(), toSopEdges(view.edges), options: options)
    let updates = ArrayList<ItemPatchTarget>()
    for (item in view.nodes) {
        if (!positions.contains(item.id)) {
            continue
        }
        let target = positions[item.id]
        let savedPosition = if (view.saved.contains(item.id)) {
            view.saved[item.id]
        } else {
            lg.SopPosition(-1.0, -1.0)
        }
        if (target.x == savedPosition.x && target.y == savedPosition.y) {
            continue
        }
        let patch = SopPatch()
        patch.canvasX = SetValue<Float64>.Value(target.x)
        patch.canvasY = SetValue<Float64>.Value(target.y)
        updates.add(ItemPatchTarget(item.id, ItemPatch().withSop(patch)))
    }
    if (!updates.isEmpty()) {
        view.store.updateItems(updates.toArray())
    }
    view.state.previewDisabled = true
    view.state.touch()
    return true
}

/** `deleteSelection` (SopPage.tsx:70-80): node or edge, with a notice. */
func deleteSelection(view: SopFrame): Bool {
    match (view.state.selectedEdgeId) {
        case Some(id) =>
            view.store.deleteEdge(id)
            view.store.notify("已删除连线", tone: NoticeTone.Info)
            view.state.selectedEdgeId = None
            view.state.touch()
            return true
        case None => ()
    }
    match (view.state.selectedNodeId) {
        case Some(id) =>
            view.store.deleteItems([id])
            view.store.notify("已删除节点及其连线", tone: NoticeTone.Info)
            view.state.selectedNodeId = None
            if (view.state.session.isSome()) {
                view.state.session = None
                view.state.branchOpen = false
            }
            view.state.touch()
            return true
        case None => ()
    }
    view.store.notify("先选中一个节点或连线", tone: NoticeTone.Info)
    return true
}

/** `toggleRun` (SopPage.tsx:106-130): starts a session at the start step or exits run mode. */
func toggleRun(ctx: UiContext, view: SopFrame): Bool {
    let _ = ctx
    if (view.state.session.isSome()) {
        view.state.session = None
        view.state.branchOpen = false
        view.store.notify("已退出运行模式", tone: NoticeTone.Info)
        view.state.touch()
        return true
    }
    let now = nowIso(view.store.clock)
    let session = lg.startSession(toSopNodes(view.nodes), toSopEdges(view.edges), now)
    match (session) {
        case Some(value) =>
            view.state.session = Some(value)
            view.state.selectedNodeId = Some(value.currentId)
            view.state.selectedEdgeId = None
            view.store.select(value.currentId)
            view.state.branchOpen = false
            view.state.touch()
        case None =>
            view.store.notify("画布还没有步骤，先添加一个开始节点", tone: NoticeTone.Error)
            view.state.touch()
    }
    return true
}
