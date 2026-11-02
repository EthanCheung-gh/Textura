package textura.core.data

import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*

/** Parity anchor: 2026-03-16T10:00:00+08:00 == 2026-03-16T02:00:00.000Z. */
let TEST_ANCHOR: Int64 = 1773626400000
let TEST_TODAY: String = "2026-03-16"
let TEST_STAMP: String = "2026-01-01T00:00:00.000Z"

func testItem(
    id: String,
    kind: ItemKind,
    title: String,
    parentId!: ?String = None,
    order!: Int64 = 0,
    status!: ItemStatus = ItemStatus.Next,
    tags!: Array<String> = [],
    areaId!: ?String = None,
    createdAt!: String = TEST_STAMP,
    updatedAt!: String = TEST_STAMP,
    completedAt!: ?String = None,
    okr!: ?OkrData = None,
    sop!: ?SopData = None,
    gtd!: ?GtdData = None,
    gantt!: ?GanttData = None
): Item {
    Item(
        id,
        kind,
        title,
        parentId: parentId,
        order: order,
        status: status,
        tags: tags,
        areaId: areaId,
        createdAt: createdAt,
        updatedAt: updatedAt,
        completedAt: completedAt,
        okr: okr,
        sop: sop,
        gtd: gtd,
        gantt: gantt
    )
}

func testWorkspace(
    items: Array<Item>,
    edges!: Array<Edge> = [],
    areas!: Array<Area> = [],
    runs!: Array<SopRunEntry> = []
): Workspace {
    Workspace(
        version: WORKSPACE_VERSION,
        items: items,
        edges: edges,
        areas: areas,
        runs: runs,
        updatedAt: TEST_STAMP
    )
}

/** Joins ids so assertions stay readable (`Array` has no equality operator). */
func ids(items: Array<Item>): String {
    let out = StringBuilder()
    for (index in 0..items.size) {
        if (index > 0) {
            out.append(",")
        }
        out.append(items[index].id)
    }
    out.toString()
}

func idList(entries: Array<ExecutionItemRef>): String {
    let out = StringBuilder()
    for (index in 0..entries.size) {
        if (index > 0) {
            out.append(",")
        }
        out.append(entries[index].item.id)
    }
    out.toString()
}

func cycleText(cycles: Array<Array<String>>): String {
    let out = StringBuilder()
    for (index in 0..cycles.size) {
        if (index > 0) {
            out.append("|")
        }
        for (position in 0..cycles[index].size) {
            if (position > 0) {
                out.append(">")
            }
            out.append(cycles[index][position])
        }
    }
    out.toString()
}

/** Locates the parity fixture regardless of the working directory. */
func parityWorkspaceText(): ?String {
    let candidates = [
        "tools/parity/workspace.json",
        "cangjie/tools/parity/workspace.json",
        "../tools/parity/workspace.json"
    ]
    for (path in candidates) {
        try {
            let text = String.fromUtf8(File.readFrom(path))
            if (!text.isEmpty()) {
                return Some(text)
            }
        } catch (_: Exception) {
            ()
        }
    }
    None
}

func seededStore(): AppStore {
    let store = AppStore(clock: FixedClock(TEST_ANCHOR))
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(FixedClock(TEST_ANCHOR))))
    store
}
