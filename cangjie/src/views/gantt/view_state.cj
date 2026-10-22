package textura.views.gantt

import std.collection.*
import textura.views.gantt.logic.*

/*
 * 跨帧手势/视图状态。
 *
 * 时间轴滚动位置与折叠集合必须是 `State`（CUI 每帧重建，普通字段会丢），但拖拽手势、
 * 悬停行、待恢复的滚动端点属于“一次手势内的临时事实”，放进 `remember` 保留的
 * `GanttViewState` 实例里，改动后递增 `rev` 让重建发生。
 */

/** 拖拽方向（GanttBar.tsx `DragMode`）。 */
enum DragMode {
    | Move
    | Start
    | End
}

/** 一次任务条拖拽：起点像素、原始区间、吸附后的天数增量（GanttTimeline.tsx DragState）。 */
class DragGesture {
    let id: String
    let mode: DragMode
    let startX: Float32
    let origin: BarRange
    let rowIndex: Int64
    var deltaDays: Float64

    init(id: String, mode: DragMode, startX: Float32, origin: BarRange, rowIndex: Int64) {
        this.id = id
        this.mode = mode
        this.startX = startX
        this.origin = origin
        this.rowIndex = rowIndex
        this.deltaDays = 0.0
    }

    /** 预览区间：严格走 logic 包的 `moveBar` / `resizeBar` 吸附实现。 */
    func preview(): BarRange {
        match (mode) {
            case DragMode.Move => moveBar(origin, deltaDays)
            case DragMode.Start => resizeBar(origin, BarEdge.Start, deltaDays)
            case DragMode.End => resizeBar(origin, BarEdge.End, deltaDays)
        }
    }
}

/** 视图级临时状态（`remember` 保留，不参与 State 观察）。 */
class GanttViewState {
    /** 折叠中的分组 id（含 `UNGROUPED_ID`）。 */
    var collapsed = HashSet<String>()

    /** 进行中的拖拽；`None` 表示空闲。 */
    var gesture: ?DragGesture = None

    /** 悬停行 id（空串表示无）。 */
    var hoverRow: String = ""

    /** 左侧树/时间轴视口尺寸（上一帧布局结果，事件换算用）。 */
     var viewportW: Float32 = 0.0
     var viewportH: Float32 = 0.0

    func toggleGroup(id: String): Unit {
        if (collapsed.contains(id)) {
            collapsed.remove(id)
        } else {
            collapsed.add(id)
        }
    }

    /** 展开某条目到根的整条祖先链（GanttPage.tsx `expandAncestors`）。 */
    func expandAncestors(workspaceRows: Array<GanttRow>, rootId: ?String): Unit {
        collapsed.remove(UNGROUPED_ID)
        var cursor: ?String = rootId
        var guard = 0
        while (guard < 20) {
            guard += 1
            match (cursor) {
                case Some(id) =>
                    collapsed.remove(id)
                    var next: ?String = None
                    for (row in workspaceRows) {
                        if (row.id == id) {
                            next = row.parentId
                            break
                        }
                    }
                    cursor = next
                case None => break
            }
        }
    }
}
