/**
 * textura.views.sop.logic · 领域记录（纯函数层，不依赖 cui / core.data）。
 *
 * 与 Web 版 `src/modules/sop` 各文件的映射关系见 `docs/SOP-LOGIC.md`：
 * - `SopNode`   <- `Item`（label 的 `sop.nodeType` / `sop.canvas` / `sop.checklist` /
 *                  `sop.owner` / `sop.durationMin`）
 * - `SopEdge`   <- `Edge`（`type === 'flow'`，`label`）
 * - `SopRunEntry` <- `SopRunEntry`（id / sopId / stepId / at / result / note）
 */
package textura.views.sop.logic

import std.deriving.*
import std.math.*

/** 与 Web 版 `SopNodeType` 一一对应的节点类型。 */
@Derive[Equatable]
public enum SopNodeType {
    | Start
    | Action
    | Decision
    | Check
    | End
    | Note
}

/** 节点类型的持久化字符串，取值与 Web 版完全一致。 */
public func nodeTypeId(kind: SopNodeType): String {
    match (kind) {
        case SopNodeType.Start => "start"
        case SopNodeType.Action => "action"
        case SopNodeType.Decision => "decision"
        case SopNodeType.Check => "check"
        case SopNodeType.End => "end"
        case SopNodeType.Note => "note"
    }
}

/** 未知字符串返回 None（Web 版读取脏数据时的兜底由调用方决定）。 */
public func parseNodeType(id: String): ?SopNodeType {
    if (id == "start") {
        return Some(SopNodeType.Start)
    }
    if (id == "action") {
        return Some(SopNodeType.Action)
    }
    if (id == "decision") {
        return Some(SopNodeType.Decision)
    }
    if (id == "check") {
        return Some(SopNodeType.Check)
    }
    if (id == "end") {
        return Some(SopNodeType.End)
    }
    if (id == "note") {
        return Some(SopNodeType.Note)
    }
    return None
}

/** 检查项，对应 `ChecklistEntry`。 */
public struct ChecklistEntry {
    public let id: String
    public let text: String
    public let done: Bool

    public init(id: String, text!: String = "", done!: Bool = false) {
        this.id = id
        this.text = text
        this.done = done
    }
}

/**
 * 画布节点。`canvasX` / `canvasY` 是节点左上角坐标（与 React Flow 的 `position` 同义）。
 */
public struct SopNode {
    public let id: String
    public let title: String
    public let nodeType: SopNodeType
    public let canvasX: Float64
    public let canvasY: Float64
    public let checklist: Array<ChecklistEntry>
    public let owner: String
    public let durationMin: ?Int64

    public init(
        id: String,
        title!: String = "",
        nodeType!: SopNodeType = SopNodeType.Action,
        canvasX!: Float64 = 0.0,
        canvasY!: Float64 = 0.0,
        checklist!: Array<ChecklistEntry> = Array<ChecklistEntry>(),
        owner!: String = "",
        durationMin!: ?Int64 = None
    ) {
        this.id = id
        this.title = title
        this.nodeType = nodeType
        this.canvasX = canvasX
        this.canvasY = canvasY
        this.checklist = checklist
        this.owner = owner
        this.durationMin = durationMin
    }
}

/** 已完成的检查项数量（对应 `checklist.filter(entry => entry.done).length`）。 */
public func checklistDoneCount(node: SopNode): Int64 {
    var done = 0
    for (entry in node.checklist) {
        if (entry.done) {
            done += 1
        }
    }
    return done
}

/**
 * 画布连线，对应 `Edge`（只含 `type === 'flow'` 的边）。
 *
 * `id` 可留空；留空时由 `edgeId()` 退化为 `from->to`，因此 `from`/`to`/`label`
 * 仍是必需的最小形状，而需要与 Web 版 `edge.id` 对齐时可显式传入。
 */
public struct SopEdge {
    public let id: String
    public let from: String
    public let to: String
    public let label: String

    public init(from: String, to: String, label!: String = "", id!: String = "") {
        this.id = id
        this.from = from
        this.to = to
        this.label = label
    }
}

/** 连线 id：显式 id 优先，否则 `from->to`（稳定且无歧义，重复边在布局里已被去重）。 */
public func edgeId(edge: SopEdge): String {
    if (!edge.id.isEmpty()) {
        return edge.id
    }
    return "${edge.from}->${edge.to}"
}

/** 画布坐标（左上角锚点）。 */
public struct SopPosition {
    public let x: Float64
    public let y: Float64

    public init(x: Float64, y: Float64) {
        this.x = x
        this.y = y
    }
}

public func samePosition(a: SopPosition, b: SopPosition): Bool {
    a.x == b.x && a.y == b.y
}

/** 一次运行结果的持久化取值：pass / fail / skip。 */
@Derive[Equatable]
public enum RunResult {
    | Pass
    | Fail
    | Skip
}

public func runResultId(result: RunResult): String {
    match (result) {
        case RunResult.Pass => "pass"
        case RunResult.Fail => "fail"
        case RunResult.Skip => "skip"
    }
}

public func parseRunResult(id: String): ?RunResult {
    if (id == "pass") {
        return Some(RunResult.Pass)
    }
    if (id == "fail") {
        return Some(RunResult.Fail)
    }
    if (id == "skip") {
        return Some(RunResult.Skip)
    }
    return None
}

/** 运行历史条目，字段与 Web 版 `SopRunEntry` 完全一致。 */
public struct SopRunEntry {
    public let id: String
    public let sopId: String
    public let stepId: String
    public let at: String
    public let result: RunResult
    public let note: String

    public init(id: String, sopId: String, stepId: String, at: String, result: RunResult, note!: String = "") {
        this.id = id
        this.sopId = sopId
        this.stepId = stepId
        this.at = at
        this.result = result
        this.note = note
    }
}

/**
 * 等价于 JS `Math.round`：.5 向 +∞ 取整。
 *
 * 仓颉 `std.math.round` 是「远离零取整」，负数半边（如 -1.5）结果不同，
 * 因此这里统一用 `floor(v + 0.5)`，保证与 Web 版逐值一致。
 */
func jsRound(value: Float64): Int64 {
    Int64(floor(value + 0.5))
}

func isFiniteNumber(value: Float64): Bool {
    !value.isNaN() && !value.isInf()
}
