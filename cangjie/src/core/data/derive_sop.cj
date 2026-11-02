package textura.core.data

import std.collection.*

/**
 * SOP list/run selectors, extracted from `src/modules/sop` so the SOP view and
 * any cross-view summary (dashboard, GTD) read the same numbers.
 */
public class SopSummary {
    public let sop: Item
    public let stepCount: Int64
    public let runCount: Int64
    public let latestRun: ?SopRunEntry
    /** Share of steps that are `done`, 0..100. */
    public let completion: Int64

    public init(
        sop: Item,
        stepCount: Int64,
        runCount: Int64,
        latestRun: ?SopRunEntry,
        completion: Int64
    ) {
        this.sop = sop
        this.stepCount = stepCount
        this.runCount = runCount
        this.latestRun = latestRun
        this.completion = completion
    }
}

/** All SOPs with step/run roll-ups, ordered like `itemsOfKind` (order/createdAt). */
public func sopList(workspace: Workspace): Array<SopSummary> {
    let result = ArrayList<SopSummary>()
    for (sop in itemsOfKind(workspace, ItemKind.Sop)) {
        let graph = sopGraph(workspace, sop.id)
        var stepCount = 0
        var doneCount = 0
        for (node in graph.nodes) {
            stepCount += 1
            if (node.isDone()) {
                doneCount += 1
            }
        }
        var runCount = 0
        var latest: ?SopRunEntry = None
        for (run in sortedRuns(workspace)) {
            if (run.sopId != sop.id) {
                continue
            }
            runCount += 1
            match (latest) {
                case None => latest = Some(run)
                case Some(_) => ()
            }
        }
        let completion = if (stepCount == 0) {
            0
        } else {
            roundHalfUp(Float64(doneCount) * 100.0 / Float64(stepCount))
        }
        result.add(SopSummary(sop, stepCount, runCount, latest, completion))
    }
    result.toArray()
}

/** Steps of one SOP in flow order (order, then createdAt). */
public func sopSteps(workspace: Workspace, sopId: String): Array<Item> {
    sopGraph(workspace, sopId).nodes
}

/** Run history of one SOP, newest first, capped at `limit`. */
public func recentRunsFor(workspace: Workspace, sopId: String, limit!: Int64 = 10): Array<SopRunEntry> {
    let result = ArrayList<SopRunEntry>()
    for (run in sortedRuns(workspace)) {
        if (run.sopId != sopId) {
            continue
        }
        if (result.size >= limit) {
            break
        }
        result.add(run)
    }
    result.toArray()
}

/** Pass/fail/skip counts for one SOP (used by its header badges). */
public class SopRunTally {
    public let pass: Int64
    public let fail: Int64
    public let skip: Int64

    public init(pass: Int64, fail: Int64, skip: Int64) {
        this.pass = pass
        this.fail = fail
        this.skip = skip
    }

    public func total(): Int64 {
        pass + fail + skip
    }
}

public func sopRunTally(workspace: Workspace, sopId: String): SopRunTally {
    var pass = 0
    var fail = 0
    var skip = 0
    for (run in workspace.runs) {
        if (run.sopId != sopId) {
            continue
        }
        match (run.result) {
            case RunResult.Pass => pass += 1
            case RunResult.Fail => fail += 1
            case RunResult.Skip => skip += 1
        }
    }
    SopRunTally(pass, fail, skip)
}
