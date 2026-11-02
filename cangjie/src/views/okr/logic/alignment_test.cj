package textura.views.okr.logic

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

/*
 * 对齐 `okrMath.test.ts` 的 `executionItemsOf` / `filterObjectives` 断言，以及
 * `okrListPerf.test.ts` 的 `paginateObjectiveKrs` / 分页状态 / `buildParentPathText`
 * 断言的「值」部分（引用同一性是 React memo 细节，纯函数包不保留）。
 */

private func executionWorkspace(): OkrWorkspace {
    makeWorkspace(
        items: [
            makeItem("kr", OkrItemKind.KeyResult, "KR", okr: Some(OkrData("2026-Q1", 5.0))),
            makeItem("act_edge", OkrItemKind.Action, "边关联行动", parentId: Some("kr"), order: 0),
            makeItem("act_child", OkrItemKind.Action, "子项行动", parentId: Some("kr"), order: 1),
            makeItem("proj_edge", OkrItemKind.Project, "边关联项目", order: 0),
            makeItem("note_edge", OkrItemKind.Note, "笔记", order: 0)
        ],
        edges: [
            OkrEdge("e1", "kr", "act_edge", OkrEdgeType.Okr),
            OkrEdge("e2", "kr", "proj_edge", OkrEdgeType.Okr),
            OkrEdge("e3", "kr", "note_edge", OkrEdgeType.Okr),
            OkrEdge("e4", "kr", "proj_edge", OkrEdgeType.Related)
        ]
    )
}

@Test
func executionItemsOfMergesEdgesAndChildren() {
    let items = executionItemsOf(executionWorkspace(), "kr")
    @Assert(items.size, 3)
    @Assert(joinedExecution(items), "[[act_edge:edge:e1,proj_edge:edge:e2,act_child:child:null]]")
}

@Test
func executionItemsOfIgnoresNonExecutionKinds() {
    let items = executionItemsOf(executionWorkspace(), "note_edge")
    @Assert(items.size, 0)
    let unknown = executionItemsOf(executionWorkspace(), "missing")
    @Assert(unknown.size, 0)
}

@Test
func executionItemsOfDeduplicatesByItemId() {
    // 同一执行项同时命中 okr 边与 parentId 时以 edge 为准，只出现一次
    let workspace = makeWorkspace(
        items: [
            makeItem("kr", OkrItemKind.KeyResult, "KR"),
            makeItem("act", OkrItemKind.Action, "行动", parentId: Some("kr"))
        ],
        edges: [OkrEdge("e1", "kr", "act", OkrEdgeType.Okr)]
    )
    let items = executionItemsOf(workspace, "kr")
    @Assert(items.size, 1)
    @Assert(joinedExecution(items), "[[act:edge:e1]]")
}

private func searchWorkspace(): OkrWorkspace {
    makeWorkspace(
        items: [
            makeItem(
                "obj",
                OkrItemKind.Objective,
                "让新用户爱上织理",
                tags: ["增长"],
                areaId: Some("area_product"),
                okr: Some(OkrData("2026-Q1", 6.0))
            ),
            makeItem(
                "kr_nps",
                OkrItemKind.KeyResult,
                "NPS 从 42 提升到 60",
                parentId: Some("obj"),
                order: 0,
                okr: Some(OkrData("2026-Q1", 4.0, krOwner: Some("林一")))
            ),
            makeItem(
                "kr_wau",
                OkrItemKind.KeyResult,
                "周活跃用户 1200 → 2000",
                parentId: Some("obj"),
                order: 1,
                okr: Some(OkrData("2026-Q1", 6.0, krOwner: Some("周然")))
            )
        ],
        areas: [OkrArea("area_product", "产品", color: "#C0663A", order: 0)]
    )
}

@Test
func filterObjectivesReturnsEverythingForEmptyQuery() {
    let result = filterObjectives(searchWorkspace(), "2026-Q1", "")
    @Assert(result.size, 1)
    @Assert(result[0].keyResults.size, 2)
    @Assert(result[0].objectiveMatched, true)
}

@Test
func filterObjectivesKeepsOnlyMatchingKrs() {
    let result = filterObjectives(searchWorkspace(), "2026-Q1", "nps")
    @Assert(result.size, 1)
    @Assert(result[0].objectiveMatched, false)
    @Assert(joinedIds(result[0].keyResults), "[[kr_nps]]")
}

@Test
func filterObjectivesMatchesTitleTagAreaAndOwner() {
    @Assert(filterObjectives(searchWorkspace(), "2026-Q1", "织理")[0].keyResults.size, 2)
    @Assert(filterObjectives(searchWorkspace(), "2026-Q1", "增长")[0].keyResults.size, 2)
    @Assert(filterObjectives(searchWorkspace(), "2026-Q1", "产品")[0].objectiveMatched, true)
    let byOwner = filterObjectives(searchWorkspace(), "2026-Q1", "周然")
    @Assert(joinedIds(byOwner[0].keyResults), "[[kr_wau]]")
    // 大小写不敏感（KR 标题含大写 NPS）
    let upper = filterObjectives(searchWorkspace(), "2026-Q1", "NPS")
    @Assert(joinedIds(upper[0].keyResults), "[[kr_nps]]")
}

@Test
func filterObjectivesReturnsNothingWithoutMatch() {
    @Assert(filterObjectives(searchWorkspace(), "2026-Q1", "不存在").size, 0)
    @Assert(filterObjectives(searchWorkspace(), "2026-Q2", "").size, 0)
    // 前后空白不影响命中
    @Assert(filterObjectives(searchWorkspace(), "2026-Q1", "  nps  ").size, 1)
}

@Test
func matchesQueryChecksNotesAndTags() {
    let workspace = makeWorkspace(
        items: [
            makeItem("a", OkrItemKind.KeyResult, "KR", notes: "季度复盘", tags: ["增长"]),
            makeItem("b", OkrItemKind.KeyResult, "KR")
        ]
    )
    let first = workspace.items[0]
    @Assert(matchesQuery(workspace, first, "复盘"), true)
    @Assert(matchesQuery(workspace, first, "增长"), true)
    @Assert(matchesQuery(workspace, first, "不存在"), false)
    @Assert(matchesQuery(workspace, first, "   "), true)
}

private func objectiveView(id: String, krCount: Int64): ObjectiveView {
    let objective = makeItem(id, OkrItemKind.Objective, "目标 ${id}")
    let keyResults = ArrayList<OkrItem>()
    for (index in 0..krCount) {
        keyResults.add(
            makeItem(
                "${id}_kr${index}",
                OkrItemKind.KeyResult,
                "KR ${index}",
                parentId: Some(id),
                order: index
            )
        )
    }
    ObjectiveView(objective, keyResults.toArray(), true)
}

@Test
func paginateObjectiveKrsHandlesEmptyInput() {
    @Assert(OKR_KR_PAGE_SIZE, 200)
    let empty = paginateObjectiveKrs(Array<ObjectiveView>(), OKR_KR_PAGE_SIZE)
    @Assert(empty.entries.size, 0)
    @Assert(empty.shownKeyResults, 0)
    @Assert(empty.totalKeyResults, 0)
    @Assert(empty.remaining, 0)
    @Assert(empty.hasMore, false)

    let noKrs = paginateObjectiveKrs([objectiveView("o", 0)], OKR_KR_PAGE_SIZE)
    @Assert(noKrs.entries.size, 1)
    @Assert(noKrs.entries[0].keyResults.size, 0)
    @Assert(noKrs.hasMore, false)
}

@Test
func paginateObjectiveKrsRespectsPageSize() {
    let under = paginateObjectiveKrs([objectiveView("o", 199)], OKR_KR_PAGE_SIZE)
    @Assert(under.shownKeyResults, 199)
    @Assert(under.entries[0].keyResults.size, 199)
    @Assert(under.hasMore, false)

    let exact = paginateObjectiveKrs([objectiveView("o", 200)], OKR_KR_PAGE_SIZE)
    @Assert(exact.shownKeyResults, 200)
    @Assert(exact.remaining, 0)
    @Assert(exact.hasMore, false)

    let over = paginateObjectiveKrs([objectiveView("o", 201)], OKR_KR_PAGE_SIZE)
    @Assert(over.entries.size, 1)
    @Assert(over.entries[0].keyResults.size, 200)
    @Assert(over.entries[0].keyResults[199].id, "o_kr199")
    @Assert(over.remaining, 1)
    @Assert(over.hasMore, true)
}

@Test
func paginateObjectiveKrsKeepsCrossObjectiveOrder() {
    let page = paginateObjectiveKrs([objectiveView("o1", 120), objectiveView("o2", 120)], OKR_KR_PAGE_SIZE)
    @Assert(page.entries.size, 2)
    @Assert(page.entries[0].objective.id, "o1")
    @Assert(page.entries[0].keyResults.size, 120)
    @Assert(page.entries[1].objective.id, "o2")
    @Assert(page.entries[1].keyResults.size, 80)
    @Assert(page.entries[1].keyResults[0].id, "o2_kr0")
    @Assert(page.remaining, 40)
}

@Test
func paginateObjectiveKrsShowsEmptyObjectivesWhileBudgetRemains() {
    let page = paginateObjectiveKrs([objectiveView("empty", 0), objectiveView("o", 201)], OKR_KR_PAGE_SIZE)
    @Assert(page.entries.size, 2)
    @Assert(page.entries[0].objective.id, "empty")
    @Assert(page.entries[1].objective.id, "o")
    @Assert(page.remaining, 1)
}

@Test
func paginateObjectiveKrsTreatsNegativeLimitAsZero() {
    let page = paginateObjectiveKrs([objectiveView("o", 3)], -5)
    @Assert(page.entries.size, 0)
    @Assert(page.shownKeyResults, 0)
    @Assert(page.remaining, 3)
    @Assert(page.hasMore, true)
}

@Test
func paginateObjectiveKrsDoesNotMutateInput() {
    let entry = objectiveView("o", 5)
    let page = paginateObjectiveKrs([entry], 2)
    @Assert(entry.keyResults.size, 5)
    @Assert(page.entries[0].keyResults.size, 2)
}

@Test
func okrPageStateResetsOnKeyChange() {
    let first = OkrPaginationState("2026-Q1|", 200)
    @Assert(resolveOkrPageLimit(first, "2026-Q1|"), 200)
    let advanced = nextOkrPage(first, "2026-Q1|")
    @Assert(advanced, OkrPaginationState("2026-Q1|", 400))
    @Assert(resolveOkrPageLimit(advanced, "2026-Q1|nps"), 200)
    @Assert(resolveOkrPageLimit(advanced, "2026-Q1|"), 400)
    @Assert(resolveOkrPageLimit(advanced, "2026-Q1|", pageSize: 100), 400)
    @Assert(resolveOkrPageLimit(first, "other", pageSize: 50), 50)
}

@Test
func buildParentPathTextJoinsAncestors() {
    let workspace = makeWorkspace(
        items: [
            makeItem("o", OkrItemKind.Objective, "目标 O"),
            makeItem("p", OkrItemKind.Project, "项目 P", parentId: Some("o")),
            makeItem("a", OkrItemKind.Action, "行动 A", parentId: Some("p"))
        ]
    )
    let map = buildParentPathText(workspace, workspace.items)
    @Assert(map.get("a").getOrThrow(), "目标 O / 项目 P")
    @Assert(map.get("p").getOrThrow(), "目标 O")
    @Assert(map.get("o").getOrThrow(), "")
    @Assert(map.size, 3)
}

@Test
func buildParentPathTextComputesDuplicatesOnce() {
    let workspace = makeWorkspace(items: [makeItem("a", OkrItemKind.Action, "行动")])
    let single = workspace.items[0]
    let map = buildParentPathText(workspace, [single, single])
    @Assert(map.size, 1)
    @Assert(map.get("a").getOrThrow(), "")
}

@Test
func buildParentPathTextToleratesMissingItems() {
    let workspace = makeWorkspace(items: [makeItem("a", OkrItemKind.Action, "行动")])
    let map = buildParentPathText(workspace, [makeItem("ghost", OkrItemKind.Action, "幽灵")])
    @Assert(map.get("ghost").getOrThrow(), "")
}
