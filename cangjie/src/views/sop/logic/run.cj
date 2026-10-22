/**
 * SOP 运行状态机（`runLogic.ts` + `SopPage.tsx` 运行会话部分的等价实现）。
 *
 * 语义与 Web 版逐条一致：
 * - 起点优先 `start` 节点，否则入度为 0 的第一个节点，否则第一个节点；
 * - 单出边直行、多出边需选择、无出边结束；
 * - pass / fail / skip 都沿流程前进（「未通过」只记录失败步骤与历史，不阻断）；
 * - 运行可重复经过同一步骤（回边场景），`visited` 去重、`failed` 逐次追加；
 * - 历史条目字段 id / sopId / stepId / at / result / note；
 * - `now` 由调用方注入（epoch 毫秒或 ISO），不读系统时钟。
 */
package textura.views.sop.logic

import std.collection.*

/** 分支选项（多出边时展示）。 */
public struct BranchOption {
    public let edgeId: String
    public let to: String
    public let label: String

    public init(edgeId: String, to: String, label!: String = "") {
        this.edgeId = edgeId
        this.to = to
        this.label = label
    }
}

/** 推进结果：直行（目标步骤, 经过的边）/ 待选择分支 / 结束。 */
public enum AdvanceResult {
    | Next(String, String)
    | Branch(Array<BranchOption>)
    | End
}

/** 运行统计。 */
public struct RunStats {
    public let pass: Int64
    public let fail: Int64
    public let skip: Int64
    public let total: Int64

    public init(pass: Int64, fail: Int64, skip: Int64, total: Int64) {
        this.pass = pass
        this.fail = fail
        this.skip = skip
        this.total = total
    }
}

/**
 * 一次运行会话（对应 `RunSession`）。
 *
 * 数组按值传递引用，调用方应把 `visited` / `failed` / `results` 视为只读；
 * 本包所有函数都返回新数组，不会原地修改入参。
 */
public struct RunSession {
    public let currentId: String
    public let visited: Array<String>
    public let failed: Array<String>
    public let startedAt: String
    public let results: Array<RunResult>

    public init(
        currentId: String,
        visited: Array<String>,
        failed!: Array<String> = Array<String>(),
        startedAt!: String = "",
        results!: Array<RunResult> = Array<RunResult>()
    ) {
        this.currentId = currentId
        this.visited = visited
        this.failed = failed
        this.startedAt = startedAt
        this.results = results
    }
}

/** 当前步骤的所有出边（按 edges 原顺序，保证分支选项稳定）。 */
public func nextCandidates(stepId: String, edges: Array<SopEdge>): Array<SopEdge> {
    let candidates = ArrayList<SopEdge>()
    for (edge in edges) {
        if (edge.from == stepId) {
            candidates.add(edge)
        }
    }
    return candidates.toArray()
}

/**
 * 起点：优先 `start` 节点；否则取入度为 0 的第一个节点；都没有时退化为第一个节点。
 */
public func startStepId(steps: Array<SopNode>, edges: Array<SopEdge>): ?String {
    for (step in steps) {
        if (step.nodeType == SopNodeType.Start) {
            return Some(step.id)
        }
    }
    let withIncoming = HashMap<String, Bool>()
    for (edge in edges) {
        withIncoming[edge.to] = true
    }
    for (step in steps) {
        if (!withIncoming.contains(step.id)) {
            return Some(step.id)
        }
    }
    if (steps.size == 0) {
        return None
    }
    return Some(steps[0].id)
}

/**
 * 结果记录后的推进：
 * - 无出边 → 结束；
 * - 单出边 → 直接进入目标；
 * - 多出边 → 未指定 choice（或 choice 非法）时返回分支选项；指定合法 choice 时进入对应目标。
 */
public func advance(
    stepId: String,
    edges: Array<SopEdge>,
    choice!: ?String = None,
    visited!: Array<String> = Array<String>()
): AdvanceResult {
    let candidates = nextCandidates(stepId, edges)
    if (candidates.size == 0) {
        return AdvanceResult.End
    }
    if (candidates.size == 1) {
        return AdvanceResult.Next(candidates[0].to, edgeId(candidates[0]))
    }
    let chosen = chooseBranchCandidate(candidates, choice)
    if (chosen.isSome()) {
        let edge = chosen.getOrThrow()
        return AdvanceResult.Next(edge.to, edgeId(edge))
    }
    let visitedSet = HashMap<String, Bool>()
    for (id in visited) {
        visitedSet[id] = true
    }
    // 稳定排序：未访问的分支优先，其余保持原顺序。
    let fresh = ArrayList<BranchOption>()
    let seen = ArrayList<BranchOption>()
    for (edge in candidates) {
        let option = BranchOption(edgeId(edge), edge.to, label: edge.label)
        if (visitedSet.contains(edge.to)) {
            seen.add(option)
        } else {
            fresh.add(option)
        }
    }
    for (option in seen) {
        fresh.add(option)
    }
    return AdvanceResult.Branch(fresh.toArray())
}

func chooseBranchCandidate(candidates: Array<SopEdge>, choice: ?String): ?SopEdge {
    let wanted = match (choice) {
        case Some(value) => value
        case None => return None
    }
    if (wanted.isEmpty()) {
        return None
    }
    for (edge in candidates) {
        if (edgeId(edge) == wanted) {
            return Some(edge)
        }
    }
    return None
}

/** 统计通过 / 未通过 / 跳过。 */
public func summarizeResults(results: Array<RunResult>): RunStats {
    var pass = 0
    var fail = 0
    var skip = 0
    for (result in results) {
        match (result) {
            case RunResult.Pass => pass += 1
            case RunResult.Fail => fail += 1
            case RunResult.Skip => skip += 1
        }
    }
    return RunStats(pass, fail, skip, results.size)
}

/** 两个 ISO 时间之间的分钟数（不小于 0，四舍五入到整数；非法时间返回 0）。 */
public func elapsedMinutes(startIso: String, endIso: String): Int64 {
    let startOpt = parseIsoMillis(startIso)
    let endOpt = parseIsoMillis(endIso)
    if (startOpt.isNone() || endOpt.isNone()) {
        return 0
    }
    return elapsedMinutesBetween(startOpt.getOrThrow(), endOpt.getOrThrow())
}

func isoMillisOr(iso: String, fallback: Int64): Int64 {
    let parsed = parseIsoMillis(iso)
    return match (parsed) {
        case Some(value) => value
        case None => fallback
    }
}

/** epoch 毫秒版本：四舍五入到分钟，负数截为 0。 */
public func elapsedMinutesBetween(startMillis: Int64, endMillis: Int64): Int64 {
    let delta = endMillis - startMillis
    let minutes = Float64(delta) / 60000.0
    let rounded = jsRound(minutes)
    if (rounded < 0) {
        return 0
    }
    return rounded
}

/**
 * 起始会话：`currentId` = 起点、`visited` = [起点]、`startedAt` = 注入的 now。
 * 画布还没有步骤时返回 None（Web 版提示「先添加一个开始节点」）。
 */
public func startSession(steps: Array<SopNode>, edges: Array<SopEdge>, nowIso: String): ?RunSession {
    let startOpt = startStepId(steps, edges)
    if (startOpt.isNone()) {
        return None
    }
    let start = startOpt.getOrThrow()
    return Some(RunSession(start, [start], startedAt: nowIso))
}

/** 进入下一步：更新 currentId，`visited` 去重追加。 */
public func moveTo(session: RunSession, stepId: String): RunSession {
    let visited = ArrayList<String>()
    var present = false
    for (id in session.visited) {
        visited.add(id)
        if (id == stepId) {
            present = true
        }
    }
    if (!present) {
        visited.add(stepId)
    }
    return RunSession(
        stepId,
        visited.toArray(),
        failed: session.failed,
        startedAt: session.startedAt,
        results: session.results
    )
}

/** 记录一条运行历史（等价 `store.logRun`）。`idSequence` 由调用方递增，避免随机 id。 */
public func makeRunEntry(
    sopId: String,
    stepId: String,
    atIso: String,
    result: RunResult,
    note!: String = "",
    idSequence!: Int64 = 0
): SopRunEntry {
    return SopRunEntry("run_${idSequence}", sopId, stepId, atIso, result, note: note)
}

/**
 * 记录结果后的三种走向（`entry` 是本次写入的历史条目）：
 * - `Advanced(session, entry, nextStepId, viaEdgeId)`
 * - `Branching(session, entry, options)`
 * - `Finished(session, entry, stats, elapsedMin)`
 */
public enum RunOutcome {
    | Advanced(RunSession, SopRunEntry, String, String)
    | Branching(RunSession, SopRunEntry, Array<BranchOption>)
    | Finished(RunSession, SopRunEntry, RunStats, Int64)
}

/**
 * 记录一次结果并推进流程（对应 `SopPage.runResult`）：
 * 1. 先落历史条目与 results / failed；
 * 2. 用「记录前」的 visited 计算分支排序；
 * 3. 直行 → 进入下一步；分支 → 返回选项；结束 → 给出统计与耗时。
 */
public func recordResult(
    session: RunSession,
    edges: Array<SopEdge>,
    result: RunResult,
    sopId: String,
    nowIso: String,
    note!: String = "",
    entryIdSequence!: Int64 = 0
): RunOutcome {
    let stepId = session.currentId
    let entry = makeRunEntry(sopId, stepId, nowIso, result, note: note, idSequence: entryIdSequence)
    let results = ArrayList<RunResult>(session.results)
    results.add(result)
    let failed = ArrayList<String>(session.failed)
    if (result == RunResult.Fail) {
        failed.add(stepId)
    }
    let updated = RunSession(
        session.currentId,
        session.visited,
        failed: failed.toArray(),
        startedAt: session.startedAt,
        results: results.toArray()
    )

    let outcome = advance(stepId, edges, visited: session.visited)
    match (outcome) {
        case AdvanceResult.Next(nextStepId, viaEdgeId) => return RunOutcome.Advanced(
            moveTo(updated, nextStepId),
            entry,
            nextStepId,
            viaEdgeId
        )
        case AdvanceResult.Branch(options) => return RunOutcome.Branching(updated, entry, options)
        case AdvanceResult.End => return RunOutcome.Finished(
            updated,
            entry,
            summarizeResults(updated.results),
            elapsedMinutesBetween(isoMillisOr(updated.startedAt, isoMillisOr(nowIso, 0)), isoMillisOr(nowIso, 0))
        )
    }
}

/** 选择分支：返回选中的边；非法选择返回 None（Web 版会保留分支面板）。 */
public func chooseBranch(options: Array<BranchOption>, choice: String): ?BranchOption {
    if (choice.isEmpty()) {
        return None
    }
    for (option in options) {
        if (option.edgeId == choice) {
            return Some(option)
        }
    }
    return None
}

/** 运行中当前步骤被删除时的安全退出判定。 */
public func isStaleSession(session: RunSession, steps: Array<SopNode>): Bool {
    for (step in steps) {
        if (step.id == session.currentId) {
            return false
        }
    }
    return true
}

/** 结束时写入提示栏的文案（与 Web 版 `finishRun` 完全一致）。 */
public func runEndMessage(stats: RunStats, elapsedMin: Int64): String {
    return "流程结束：通过 ${stats.pass} / 未通过 ${stats.fail} / 跳过 ${stats.skip}，耗时 ${elapsedMin} 分钟"
}
