/**
 * 画布渲染的纯函数层（`perf.ts` 的可移植部分）。
 *
 * Web 版 `buildCanvasNodes` 的一半价值在于 **对象引用复用**（React.memo 依赖引用相等），
 * 这在仓颉的值语义世界里没有对应物：视图层只关心「哪些节点的 data 变了」。
 * 因此本文件提供：
 * - `nodeStateFor`：运行高亮状态（current > failed > visited > idle）；
 * - `sopNodeData`：只含原始值的节点数据（便于缓存比较）；
 * - `sameNodeData`：结构等价判断（对应 `sameNodeData`）；
 * - `nodeStateDiffs`：两次构建之间状态发生变化的节点 id（视图只需重绘这些节点）。
 */
package textura.views.sop.logic

import std.collection.*
import std.deriving.*

@Derive[Equatable]
public enum SopNodeState {
    | Idle
    | Current
    | Visited
    | Failed
}

public func nodeStateId(state: SopNodeState): String {
    match (state) {
        case SopNodeState.Idle => "idle"
        case SopNodeState.Current => "current"
        case SopNodeState.Visited => "visited"
        case SopNodeState.Failed => "failed"
    }
}

/** 构建节点所需的运行高亮信息（只读、原始值）。 */
public struct CanvasRunState {
    public let currentId: ?String
    public let visited: Array<String>
    public let failed: Array<String>

    public init(
        currentId!: ?String = None,
        visited!: Array<String> = Array<String>(),
        failed!: Array<String> = Array<String>()
    ) {
        this.currentId = currentId
        this.visited = visited
        this.failed = failed
    }
}

/** 传给自定义节点的数据：只含原始值，便于 memo 比较。 */
public struct SopNodeData {
    public let title: String
    public let nodeType: SopNodeType
    public let owner: String
    public let durationMin: ?Int64
    public let checklistDone: Int64
    public let checklistTotal: Int64
    public let areaColor: ?String
    public let state: SopNodeState

    public init(
        title: String,
        nodeType: SopNodeType,
        owner: String,
        durationMin: ?Int64,
        checklistDone: Int64,
        checklistTotal: Int64,
        areaColor: ?String,
        state: SopNodeState
    ) {
        this.title = title
        this.nodeType = nodeType
        this.owner = owner
        this.durationMin = durationMin
        this.checklistDone = checklistDone
        this.checklistTotal = checklistTotal
        this.areaColor = areaColor
        this.state = state
    }
}

/** 优先级与 Web 版一致：current > failed > visited > idle。 */
public func nodeStateFor(id: String, run: ?CanvasRunState): SopNodeState {
    let state = match (run) {
        case Some(value) => value
        case None => return SopNodeState.Idle
    }
    if (state.currentId.isSome() && state.currentId.getOrThrow() == id) {
        return SopNodeState.Current
    }
    if (containsString(state.failed, id)) {
        return SopNodeState.Failed
    }
    if (containsString(state.visited, id)) {
        return SopNodeState.Visited
    }
    return SopNodeState.Idle
}

func containsString(values: Array<String>, target: String): Bool {
    for (value in values) {
        if (value == target) {
            return true
        }
    }
    return false
}

/** 由节点与运行态生成视图数据（`areaColor` 由调用方按 areaId 查表后传入）。 */
public func sopNodeData(node: SopNode, areaColor: ?String, run: ?CanvasRunState): SopNodeData {
    return SopNodeData(
        node.title,
        node.nodeType,
        node.owner,
        node.durationMin,
        checklistDoneCount(node),
        node.checklist.size,
        areaColor,
        nodeStateFor(node.id, run)
    )
}

public func sameNodeData(left: SopNodeData, right: SopNodeData): Bool {
    return left.title == right.title && left.nodeType == right.nodeType && left.owner == right.owner &&
        left.durationMin == right.durationMin && left.checklistDone == right.checklistDone && left.checklistTotal == right
        .checklistTotal && left.areaColor == right.areaColor && left.state == right.state
}

/**
 * 两次构建之间「运行高亮状态」变化的节点 id（保持 `nodes` 顺序）。
 * 视图层据此只重绘变化的节点，等价 Web 版的引用复用收益。
 */
public func nodeStateDiffs(nodes: Array<SopNode>, before: ?CanvasRunState, after: ?CanvasRunState): Array<String> {
    let changed = ArrayList<String>()
    for (node in nodes) {
        if (nodeStateFor(node.id, before) != nodeStateFor(node.id, after)) {
            changed.add(node.id)
        }
    }
    return changed.toArray()
}
