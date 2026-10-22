/**
 * 画布坐标写回的纯函数层（`positions.ts` 的等价实现）。
 *
 * 拖动结束 / 自动布局结束后，先把节点位置整理成「只包含变化项」的补丁，
 * 再交给 store 一次性写回 `item.sop.canvas`。视图层因此不需要散落取整/去重逻辑。
 */
package textura.views.sop.logic

import std.collection.*

/** 画布节点坐标（对应 React Flow 的 `{ id, position: { x, y } }` 摊平后的形状）。 */
public struct CanvasPosition {
    public let id: String
    public let x: Float64
    public let y: Float64

    public init(id: String, x: Float64, y: Float64) {
        this.id = id
        this.x = x
        this.y = y
    }
}

/** `item.sop.canvas` 补丁值（只有一层 `canvas`）。 */
public struct SopCanvasPatch {
    public let canvas: SopPosition

    public init(canvas: SopPosition) {
        this.canvas = canvas
    }
}

/** `ItemPatch` 的最小切片：`{ sop: { canvas } }`。 */
public struct ItemCanvasPatch {
    public let sop: SopCanvasPatch

    public init(sop: SopCanvasPatch) {
        this.sop = sop
    }
}

/** `store.updateItems` 的单条载荷。 */
public struct CanvasPatchUpdate {
    public let id: String
    public let patch: ItemCanvasPatch

    public init(id: String, patch: ItemCanvasPatch) {
        this.id = id
        this.patch = patch
    }
}

/**
 * @param nodes 任意带 id + position 的节点
 * @param current 现有 `sop.canvas` 映射；提供时只返回位置真正变化的节点
 */
public func positionsToPatch(
    nodes: Array<CanvasPosition>,
    current!: ?HashMap<String, SopPosition> = None
): Array<CanvasPosition> {
    return canvasPositionsToPatch(nodes, current: current)
}

/** 把整批画布补丁整理成 `updateItems` 载荷（调用方只触发一次批量写入）。 */
public func canvasPatchesToUpdateItems(patches: Array<CanvasPosition>): Array<CanvasPatchUpdate> {
    let updates = ArrayList<CanvasPatchUpdate>()
    for (patch in patches) {
        let canvas = CanvasPosition(patch.id, patch.x, patch.y)
        updates.add(
            CanvasPatchUpdate(
                canvas.id,
                ItemCanvasPatch(SopCanvasPatch(SopPosition(canvas.x, canvas.y)))
            )
        )
    }
    return updates.toArray()
}
