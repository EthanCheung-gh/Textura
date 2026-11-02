/**
 * 初始适配策略（`fit.ts` 的等价实现，纯函数）。
 *
 * 目标：打开 SOP 时优先保证文字可读，而不是一味把整张图塞进视口。
 * - padding 0.16（可用空间 = 容器 / 1.16）；
 * - zoom 有可读下限 0.7；
 * - 手动缩放仍可到 0.25，「适应画布」也允许低于下限以看全；
 * - 内容宽/高于视口时不再强行居中，而是从左上角 margin 开始，保证流程起点可见。
 */
package textura.views.sop.logic

import std.collection.*

public let INITIAL_FIT_PADDING: Float64 = 0.16
public let READABLE_MIN_ZOOM: Float64 = 0.7
public let MAX_FIT_ZOOM: Float64 = 1.0
public let MIN_ZOOM: Float64 = 0.25
public let FIT_MARGIN: Float64 = 16.0
/** 节点实际高度略高于 56（含检查项进度条），包围盒估算时留一点余量。 */
public let FIT_NODE_HEIGHT: Float64 = SOP_NODE_HEIGHT + 4.0

/** 演示/编辑用的紧凑纵向预览间距：在 7 步规模下可让内容竖向铺满画布。 */
public let PREVIEW_LAYOUT: LayoutOptions = LayoutOptions(
    rankdir: RankDir.TopDown,
    nodesep: 44.0,
    ranksep: 60.0,
    margin: 0.0
)

public struct FitBounds {
    public let x: Float64
    public let y: Float64
    public let width: Float64
    public let height: Float64

    public init(x: Float64, y: Float64, width: Float64, height: Float64) {
        this.x = x
        this.y = y
        this.width = width
        this.height = height
    }
}

public struct ViewportTransform {
    public let x: Float64
    public let y: Float64
    public let zoom: Float64

    public init(x: Float64, y: Float64, zoom: Float64) {
        this.x = x
        this.y = y
        this.zoom = zoom
    }
}

public struct ReadableViewport {
    public let viewport: ViewportTransform
    public let zoom: Float64
    /** 是否因为可读下限而放弃「一屏看全」 */
    public let clamped: Bool
    public let fitsWidth: Bool
    public let fitsHeight: Bool

    public init(viewport: ViewportTransform, zoom: Float64, clamped: Bool, fitsWidth: Bool, fitsHeight: Bool) {
        this.viewport = viewport
        this.zoom = zoom
        this.clamped = clamped
        this.fitsWidth = fitsWidth
        this.fitsHeight = fitsHeight
    }
}

public struct ReadableFitOptions {
    public let containerWidth: Float64
    public let containerHeight: Float64
    public let bounds: FitBounds
    /** 0.16 对应上下左右各留约 8% 的余量 */
    public let padding: Float64
    /** 初始 fit 的可读下限 */
    public let minZoom: Float64
    public let maxZoom: Float64
    /** 内容放不下时左上角保留的像素边距 */
    public let margin: Float64

    public init(
        containerWidth: Float64,
        containerHeight: Float64,
        bounds: FitBounds,
        padding!: Float64 = INITIAL_FIT_PADDING,
        minZoom!: Float64 = READABLE_MIN_ZOOM,
        maxZoom!: Float64 = MAX_FIT_ZOOM,
        margin!: Float64 = FIT_MARGIN
    ) {
        this.containerWidth = containerWidth
        this.containerHeight = containerHeight
        this.bounds = bounds
        this.padding = padding
        this.minZoom = minZoom
        this.maxZoom = maxZoom
        this.margin = margin
    }
}

/** 由节点尺寸计算内容包围盒；空输入或全部坐标非法返回 None。 */
public func boundsOfNodes(
    nodes: Array<SopNode>,
    nodeWidth!: Float64 = SOP_NODE_WIDTH,
    nodeHeight!: Float64 = SOP_NODE_HEIGHT
): ?FitBounds {
    let positions = HashMap<String, SopPosition>()
    for (node in nodes) {
        positions[node.id] = SopPosition(node.canvasX, node.canvasY)
    }
    return boundsOfPositions(positions, nodeWidth: nodeWidth, nodeHeight: nodeHeight)
}

/** 由坐标表计算内容包围盒；空输入返回 None。 */
public func boundsOfPositions(
    positions: HashMap<String, SopPosition>,
    nodeWidth!: Float64 = SOP_NODE_WIDTH,
    nodeHeight!: Float64 = SOP_NODE_HEIGHT
): ?FitBounds {
    var minX = 0.0
    var minY = 0.0
    var maxX = 0.0
    var maxY = 0.0
    var seen = false
    for ((_, position) in positions) {
        if (!isFiniteNumber(position.x) || !isFiniteNumber(position.y)) {
            continue
        }
        if (!seen) {
            minX = position.x
            minY = position.y
            maxX = position.x + nodeWidth
            maxY = position.y + nodeHeight
            seen = true
            continue
        }
        if (position.x < minX) {
            minX = position.x
        }
        if (position.y < minY) {
            minY = position.y
        }
        if (position.x + nodeWidth > maxX) {
            maxX = position.x + nodeWidth
        }
        if (position.y + nodeHeight > maxY) {
            maxY = position.y + nodeHeight
        }
    }
    if (!seen) {
        return None
    }
    let width = if (maxX - minX > 1.0) {
        maxX - minX
    } else {
        1.0
    }
    let height = if (maxY - minY > 1.0) {
        maxY - minY
    } else {
        1.0
    }
    return Some(FitBounds(minX, minY, width, height))
}

/**
 * 计算初始 viewport。
 *
 * - 先按 React Flow 的 padding 语义（可用空间 = 容器 / (1 + padding)）求原始 zoom；
 * - 原始 zoom 低于可读下限时取 minZoom（宁可可滚动，也不缩小到不可读）；
 * - 某一方向放得下就居中，放不下则从 margin 锚定，避免把流程起点藏到视口外。
 */
public func computeReadableViewport(options: ReadableFitOptions): ReadableViewport {
    let width = maxFloat(options.containerWidth, 1.0)
    let height = maxFloat(options.containerHeight, 1.0)
    let contentWidth = maxFloat(options.bounds.width, 1.0)
    let contentHeight = maxFloat(options.bounds.height, 1.0)
    let padding = maxFloat(options.padding, 0.0)

    var rawZoom = width / (contentWidth * (1.0 + padding))
    let heightZoom = height / (contentHeight * (1.0 + padding))
    if (heightZoom < rawZoom) {
        rawZoom = heightZoom
    }
    if (options.maxZoom < rawZoom) {
        rawZoom = options.maxZoom
    }
    let floorZoom = minFloat(options.minZoom, options.maxZoom)
    let clamped = rawZoom < floorZoom
    var zoom = rawZoom
    if (options.maxZoom < zoom) {
        zoom = options.maxZoom
    }
    if (zoom < floorZoom) {
        zoom = floorZoom
    }

    let scaledWidth = contentWidth * zoom
    let scaledHeight = contentHeight * zoom
    let fitsWidth = scaledWidth <= width
    let fitsHeight = scaledHeight <= height

    let x: Float64 = if (fitsWidth) {
        (width - scaledWidth) / 2.0 - options.bounds.x * zoom
    } else {
        options.margin - options.bounds.x * zoom
    }
    let y: Float64 = if (fitsHeight) {
        (height - scaledHeight) / 2.0 - options.bounds.y * zoom
    } else {
        options.margin - options.bounds.y * zoom
    }

    return ReadableViewport(ViewportTransform(x, y, zoom), zoom, clamped, fitsWidth, fitsHeight)
}

func maxFloat(a: Float64, b: Float64): Float64 {
    if (a > b) {
        return a
    }
    return b
}

func minFloat(a: Float64, b: Float64): Float64 {
    if (a < b) {
        return a
    }
    return b
}

/** 保存的布局是否「过于横向」：宽高比 >= 2 时改用纵向预览布局。 */
public func isWideLayout(bounds: ?FitBounds): Bool {
    let value = match (bounds) {
        case Some(fit) => fit
        case None => return false
    }
    return value.width >= value.height * 2.0
}
