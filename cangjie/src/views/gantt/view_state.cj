package textura.views.gantt

import std.collection.*
import textura.views.gantt.logic.*

/*
 * 跨帧手势/视图状态。
 *
 * 时间轴滚动位置与折叠集合必须是 `State`（CUI 每帧重建，普通字段会丢），但拖拽手势、
 * 悬停行、按下行属于“一次手势内的临时事实”，放进 `remember` 保留的 `GanttViewState` 实例里。
 *
 * 这些临时事实**不再**递增 `rev`：输入帧本身一定会重建绘制（`MouseMove/Down/Up` 让宿主
 * `mustRender`），而 `draw` 直接读 `hoverRow` / `gesture` / `pressedRow`，所以只重绘就够。
 * 递增 `rev` 会重建整个 shell（`rev` 在 `gantt.render` 的作用域里被读），一次跨行 hover
 * 就付一次 30–55ms 级的重建成本 —— 真机上表现为「颜色动效慢半拍」。只有真正改变行集合的
 * 操作（折叠分组）才需要 `rev`。
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

    /**
     * 本帧按下的行 id（空串表示无）。点击后立刻用「选中」同色绘制，反馈在下一帧可见，
     * 不必等 `store.select` 触发的那次重建。
     */
    var pressedRow: String = ""

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
