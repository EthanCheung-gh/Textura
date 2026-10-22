package textura.views.okr.logic

import std.collection.*

/*
 * 测试辅助（仅 `cjpm test` 编译）。不包含断言，只为各 *_test.cj 复用构造器。
 */

let TEST_NOW = "2026-02-14T09:00:00.000Z"

/** 正无穷（仓颉没有 `Float64.POSITIVE_INFINITY` 常量）。 */
let TEST_INF: Float64 = 1.0 / 0.0

func approx(actual: Float64, expected: Float64, tolerance: Float64): Bool {
    var diff = actual - expected
    if (diff < 0.0) {
        diff = -diff
    }
    diff <= tolerance
}

func makeItem(
    id: String,
    kind: OkrItemKind,
    title: String,
    notes!: String = "",
    parentId!: ?String = None,
    order!: Int64 = 0,
    status!: OkrItemStatus = OkrItemStatus.Next,
    tags!: Array<String> = [],
    areaId!: ?String = None,
    createdAt!: String = TEST_NOW,
    okr!: ?OkrData = None
): OkrItem {
    OkrItem(
        id,
        kind,
        title,
        notes: notes,
        parentId: parentId,
        order: order,
        status: status,
        tags: tags,
        areaId: areaId,
        createdAt: createdAt,
        okr: okr
    )
}

func makeWorkspace(
    items!: Array<OkrItem> = [],
    edges!: Array<OkrEdge> = [],
    areas!: Array<OkrArea> = []
): OkrWorkspace {
    OkrWorkspace(items: items, edges: edges, areas: areas)
}

/** `[1,2,3]` 形式的 id 列表，便于和 TS 的 `map(...).toEqual([...])` 对照。 */
func joinedIds(items: Array<OkrItem>): String {
    let parts = ArrayList<String>()
    for (item in items) {
        parts.add(item.id)
    }
    "[[" + String.join(parts.toArray(), delimiter: ",") + "]]"
}

func joinedStrings(values: Array<String>): String {
    "[[" + String.join(values, delimiter: ",") + "]]"
}

func joinedExecution(items: Array<ExecutionItemRef>): String {
    let parts = ArrayList<String>()
    for (entry in items) {
        let edgeText = match (entry.edgeId) {
            case Some(value) => value
            case None => "null"
        }
        parts.add("${entry.item.id}:${executionViaText(entry.via)}:${edgeText}")
    }
    "[[" + String.join(parts.toArray(), delimiter: ",") + "]]"
}

func joinedFields(fields: Array<MetricField>): String {
    let parts = ArrayList<String>()
    for (field in fields) {
        parts.add(metricFieldText(field))
    }
    "[[" + String.join(parts.toArray(), delimiter: ",") + "]]"
}
