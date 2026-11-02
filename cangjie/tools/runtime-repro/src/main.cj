/*
 * Minimal reproduction for the Cangjie runtime abort that kills Textura on device.
 *
 * Device signature (docs/HANDOFF.md §6, docs/STABILITY.md §3):
 *   F CANGJIE-RUNTIME: Check failed: toRegion2Idx != INVALID_VALUE
 *   GC thread: RegionInfo::VisitLiveObjectsUntilFalse -> RegionManager::ForwardRegion
 *              -> CopyCollector::ForwardFromSpace
 *
 * Host signature (same defect, different face): SIGSEGV with the stack top in
 * SlotRoot::VisitGCRoots -> CheckAndPush, i.e. GC scans a deep Cangjie stack and reads a stack slot
 * that is not a valid pointer.
 *
 * The shape below is what the application does: a deep recursive layout pass that allocates short
 * lived collections on every frame, repeated in one process so the GC keeps hitting those frames.
 * It deliberately keeps the allocations reachable from the deep frames until the recursion unwinds
 * (a compiler cannot elide them into an outer scope).
 *
 * Build/run: see README.md. One run surviving is not a pass; run in a loop until the process dies.
 */
package runtime_repro

import std.collection.{ArrayList, HashMap}

// A C frame in the middle of the deep Cangjie stack: the device stacks contain CUI/SDL C++ frames
// too, and the GC has no stack map for them.
foreign func malloc(size: UInt64): CPointer<Unit>
foreign func free(ptr: CPointer<Unit>): Unit

class Cell {
    let items: ArrayList<Int64>
    let names: HashMap<Int64, String>

    init(seed: Int64) {
        this.items = ArrayList<Int64>()
        this.names = HashMap<Int64, String>()
        for (i in 0..48) {
            this.items.add(seed + i)
            this.names.add(seed + i, "cell-${seed}-${i}")
        }
    }
}

func walk(depth: Int64, sink: ArrayList<Cell>): Int64 {
    let cell = Cell(depth)
    sink.add(cell)
    // Cross the FFI boundary on every frame; free immediately so the C heap churns as well.
    unsafe {
        let block = malloc(256)
        free(block)
    }
    var total = cell.items[0]
    if (depth > 0) {
        total += walk(depth - 1, sink)
    } else {
        // The heaviest allocation sits at the bottom of the stack, like the dagre layout pass in
        // `textura.views.sop.logic`.
        let local = ArrayList<String>()
        for (i in 0..4096) {
            local.add("leaf-${i}-${total}")
        }
        total += local.size
    }
    total + cell.names.size
}

main(): Int64 {
    var rounds = 0
    while (rounds < 300) {
        // A fresh sink per round makes every Cell unreachable once the round ends, so the next
        // rounds allocate into a heap that the collector must scan repeatedly.
        let sink = ArrayList<Cell>()
        let value = walk(96, sink)
        if (value == -1) {
            println("unreachable")
        }
        rounds += 1
    }
    println("survived ${rounds} rounds")
    return 0
}