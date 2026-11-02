package textura.views.gtd.logic

import std.collection.*

/*
 * `src/modules/gtd/gtdListPerf.test.ts` 的移植 + 1k/5k 规模正确性。
 *
 * TS 版用规模测试保证「长列表只算一次」的复杂度；这里沿用同一批断言，
 * 并把规模测试扩到 1k / 5k 条：验证排序判序、分组守恒、分页计数、
 * 路径索引与等待天数在规模下仍然正确（不依赖实际耗时，避免机器抖动）。
 */

/* ------------------------------------------------------------------ */
/* paginateItems                                                       */
/* ------------------------------------------------------------------ */

@Test
func paginationOnEmptyListRendersNothing(): Unit {
    let page = paginateItems(bulkActions(0), LIST_PAGE_SIZE)
    @Expect(page.shown, 0)
    @Expect(page.total, 0)
    @Expect(page.remaining, 0)
    @Expect(page.hasMore, false)
    @Expect(page.items.size, 0)
}

@Test
func paginationRendersAllOfNinetyNine(): Unit {
    let page = paginateItems(bulkActions(99), LIST_PAGE_SIZE)
    @Expect(page.items.size, 99)
    @Expect(page.remaining, 0)
    @Expect(page.hasMore, false)
}

@Test
func paginationFillsExactlyOnePage(): Unit {
    let page = paginateItems(bulkActions(100), LIST_PAGE_SIZE)
    @Expect(page.items.size, 100)
    @Expect(page.remaining, 0)
    @Expect(page.hasMore, false)
}

@Test
func paginationLeavesOneItemOver(): Unit {
    let page = paginateItems(bulkActions(101), LIST_PAGE_SIZE)
    @Expect(page.items.size, 100)
    @Expect(page.shown, 100)
    @Expect(page.remaining, 1)
    @Expect(page.hasMore, true)
}

@Test
func paginationTreatsNegativeLimitAsZero(): Unit {
    let items = bulkActions(3)
    @Expect(paginateItems(items, -1).items.size, 0)
    @Expect(paginateItems(items, 0).items.size, 0)
    @Expect(paginateItems(items, 2).items.size, 2)
}

@Test
func paginationDoesNotMutateInput(): Unit {
    let items = bulkActions(5)
    paginateItems(items, 2)
    @Expect(items.size, 5)
}

/* ------------------------------------------------------------------ */
/* 分页状态（筛选后重置）                                              */
/* ------------------------------------------------------------------ */

@Test
func paginationStateResetsWhenKeyChanges(): Unit {
    @Expect(resolvePageLimit(PaginationState("k1", 100), "k1"), 100)
    let advanced = nextPage(PaginationState("k1", 100), "k1")
    @Expect(advanced.key, "k1")
    @Expect(advanced.limit, 200)
    @Expect(resolvePageLimit(advanced, "k1"), 200)
    // 筛选 / 分组变化 → key 不同 → 重置
    @Expect(resolvePageLimit(advanced, "k2"), 100)
    @Expect(nextPage(advanced, "k2").limit, 200)
}

/* ------------------------------------------------------------------ */
/* buildPathTitleIndex（面包屑映射）                                   */
/* ------------------------------------------------------------------ */

@Test
func pathTitleIndexGivesPathsAndParentText(): Unit {
    let workspace = GtdWorkspace(
        items: [
            mkItem("o", GtdKind.Objective, "目标 O"),
            mkItem("p", GtdKind.Project, "项目 P", parentId: Some("o")),
            mkItem("a", GtdKind.Action, "行动 A", parentId: Some("p")),
            mkItem("root", GtdKind.Action, "根级行动")
        ]
    )
    let index = buildPathTitleIndex(workspace, workspace.items)
    @Expect(String.join(index.pathOf("a"), delimiter: "/"), "目标 O/项目 P/行动 A")
    @Expect(String.join(index.parents.get("a").getOrThrow(), delimiter: "/"), "目标 O/项目 P")
    @Expect(index.parentTextOf("a"), "目标 O / 项目 P")
    @Expect(index.parentTextOf("o"), "")
    @Expect(index.parentTextOf("root"), "")
}

@Test
func pathTitleIndexDeduplicatesIdsAndHandlesMissingItems(): Unit {
    let workspace = GtdWorkspace(items: [mkItem("p", GtdKind.Project, "项目")])
    let item = workspace.items[0]
    let index = buildPathTitleIndex(workspace, [item, item])
    @Expect(index.parentText.size, 1)
    @Expect(index.parentTextOf("p"), "")
    @Expect(index.pathOf("missing").size, 0)
}

/* ------------------------------------------------------------------ */
/* 分组 / 排序与分页组合                                               */
/* ------------------------------------------------------------------ */

@Test
func groupingAfterPaginationKeepsOrderAndCounts(): Unit {
    let items = sortNextActions(
        [
            mkItem("pc0", GtdKind.Action, "电脑 0", order: 0, capturedAt: Some(TEST_EPOCH), clarified: true,
                context: Some("电脑")),
            mkItem("pc1", GtdKind.Action, "电脑 1", order: 1, capturedAt: Some(TEST_EPOCH), clarified: true,
                context: Some("电脑")),
            mkItem("phone0", GtdKind.Action, "电话 0", order: 2, capturedAt: Some(TEST_EPOCH), clarified: true,
                context: Some("电话")),
            mkItem("phone1", GtdKind.Action, "电话 1", order: 3, capturedAt: Some(TEST_EPOCH), clarified: true,
                context: Some("电话")),
            mkItem("none", GtdKind.Action, "无场景", order: 4, capturedAt: Some(TEST_EPOCH), clarified: true)
        ]
    )
    let page = paginateItems(items, 3)
    let groups = groupByContext(page.items)
    @Expect(joinContexts(groups), "电脑,电话")
    @Expect(joinIds(groups[0].items), "pc0,pc1")
    @Expect(joinIds(groups[1].items), "phone0")
    @Expect(page.remaining, 2)

    let rest = groupByContext(tailFrom(items, page.shown))
    @Expect(joinContexts(rest), "电话,无场景")
    @Expect(joinIds(rest[0].items), "phone1")
    @Expect(joinIds(rest[1].items), "none")
}

@Test
func groupedFirstScreenShowsAtMostOnePage(): Unit {
    let items = sortNextActions(bulkActions(101))
    let page = paginateItems(items, LIST_PAGE_SIZE)
    let groups = groupByContext(page.items)
    var rendered: Int64 = 0
    for (group in groups) {
        rendered += group.items.size
    }
    @Expect(rendered, 100)
    @Expect(page.remaining, 1)
}

/* ------------------------------------------------------------------ */
/* buildWaitingRows                                                    */
/* ------------------------------------------------------------------ */

@Test
func waitingRowsComputeDaysOnceAndMarkOverdue(): Unit {
    let today = "2026-01-20"
    let items = [
        mkItem("w1", GtdKind.Action, "等 2 天", status: GtdStatus.Waiting, capturedAt: Some("2026-01-18")),
        mkItem("w2", GtdKind.Action, "等 10 天", status: GtdStatus.Waiting, capturedAt: Some("2026-01-10"))
    ]
    let rows = buildWaitingRows(items, today)
    @Expect(joinIds([rows[0].item, rows[1].item]), "w2,w1")
    @Expect(rows[0].days, 10)
    @Expect(rows[0].overdue, true)
    @Expect(rows[1].days, 2)
    @Expect(rows[1].overdue, false)
}

@Test
func waitingRowsCrossMonthAndYearBoundaries(): Unit {
    let items = [
        mkItem("w-year", GtdKind.Action, "跨年", status: GtdStatus.Waiting, capturedAt: Some("2026-12-28")),
        mkItem("w-month", GtdKind.Action, "跨月", status: GtdStatus.Waiting, capturedAt: Some("2027-01-02"))
    ]
    let rows = buildWaitingRows(items, "2027-01-05")
    @Expect(joinIds([rows[0].item, rows[1].item]), "w-year,w-month")
    @Expect(rows[0].days, 8)
    @Expect(rows[0].overdue, true)
    @Expect(rows[1].days, 3)
    @Expect(rows[1].overdue, false)
}

/* ------------------------------------------------------------------ */
/* 规模：1k / 5k                                                       */
/* ------------------------------------------------------------------ */

@Test
func scaleOneThousandActionsSortAndGroupCorrectly(): Unit {
    let items = bulkMixed(1000)
    let sorted = sortNextActions(items)
    @Expect(sorted.size, 1000)
    @Expect(isNextActionsSorted(sorted), true)

    let groups = groupByContext(sorted)
    @Expect(joinContexts(groups), "电脑,电话,无场景")
    var total: Int64 = 0
    for (group in groups) {
        total += group.items.size
    }
    @Expect(total, 1000)
    @Expect(groups[0].items.size, 334)
    @Expect(groups[1].items.size, 333)
    @Expect(groups[2].items.size, 333)

    let page = paginateItems(sorted, LIST_PAGE_SIZE)
    @Expect(page.shown, 100)
    @Expect(page.remaining, 900)
    @Expect(page.hasMore, true)
}

@Test
func scaleFiveThousandActionsSortAndPageCorrectly(): Unit {
    let items = bulkMixed(5000)
    let sorted = sortNextActions(items)
    @Expect(sorted.size, 5000)
    @Expect(isNextActionsSorted(sorted), true)

    let groups = groupByContext(sorted)
    var total: Int64 = 0
    for (group in groups) {
        total += group.items.size
    }
    @Expect(total, 5000)
    @Expect(joinContexts(groups), "电脑,电话,无场景")

    let page = paginateItems(sorted, LIST_PAGE_SIZE)
    @Expect(page.shown, 100)
    @Expect(page.total, 5000)
    @Expect(page.remaining, 4900)
    @Expect(page.hasMore, true)

    let second = paginateItems(sorted, nextPage(PaginationState("all", LIST_PAGE_SIZE), "all").limit)
    @Expect(second.shown, 200)
    @Expect(second.remaining, 4800)
}

@Test
func scaleSortingIsStableForTiedKeys(): Unit {
    let tied = ArrayList<GtdItem>()
    var index: Int64 = 0
    while (index < 500) {
        tied.add(
            mkItem(
                "t" + index.toString(),
                GtdKind.Action,
                "并列",
                order: 0,
                createdAt: TEST_EPOCH,
                capturedAt: Some(TEST_EPOCH),
                clarified: true,
                context: Some("电脑")
            )
        )
        index += 1
    }
    let input = tied.toArray()
    @Expect(joinIds(sortNextActions(input)) == joinIds(input), true)
    @Expect(joinIds(sortInboxItems(input)) == joinIds(input), true)
}

@Test
func scaleWaitingRowsStayDescending(): Unit {
    let waiting = ArrayList<GtdItem>()
    var index: Int64 = 0
    while (index < 1000) {
        waiting.add(
            mkItem(
                "w" + index.toString(),
                GtdKind.Action,
                "等待 " + index.toString(),
                order: 1000 - index,
                status: GtdStatus.Waiting,
                capturedAt: Some(dayAt(0 - index % 30))
            )
        )
        index += 1
    }
    let rows = buildWaitingRows(waiting.toArray(), TEST_TODAY)
    @Expect(rows.size, 1000)
    var position: Int64 = 1
    var descending = true
    while (position < rows.size) {
        if (rows[position - 1].days < rows[position].days) {
            descending = false
            break
        }
        if (rows[position - 1].days == rows[position].days && rows[position - 1].item.order > rows[position].item.order) {
            descending = false
            break
        }
        position += 1
    }
    @Expect(descending, true)
    @Expect(rows[0].days, 29)
}

@Test
func scalePathTitleIndexHandlesDeepChains(): Unit {
    let chain = ArrayList<GtdItem>()
    var index: Int64 = 0
    while (index < 1000) {
        let parent: ?String = if (index == 0) {
            None
        } else {
            Some("n" + (index - 1).toString())
        }
        chain.add(mkItem("n" + index.toString(), GtdKind.Action, "层级 " + index.toString(), parentId: parent))
        index += 1
    }
    let workspace = GtdWorkspace(items: chain.toArray())
    let built = buildPathTitleIndex(workspace, workspace.items)
    @Expect(built.pathOf("n0").size, 1)
    @Expect(built.pathOf("n999").size, 1000)
    @Expect(built.parentTextOf("n0"), "")
    @Expect(built.pathOf("n999")[0], "层级 0")
    @Expect(built.parentTextOf("n1"), "层级 0")
}

@Test
func scaleWeeklyReviewReusesSingleIndex(): Unit {
    let items = ArrayList<GtdItem>()
    var index: Int64 = 0
    while (index < 1000) {
        items.add(
            mkItem(
                "p" + index.toString(),
                GtdKind.Project,
                "项目 " + index.toString(),
                order: index,
                status: GtdStatus.Active,
                updatedAt: dayAt(-20)
            )
        )
        index += 1
    }
    var inbox: Int64 = 0
    while (inbox < 3000) {
        items.add(
            mkItem(
                "i" + inbox.toString(),
                GtdKind.Action,
                "收件箱 " + inbox.toString(),
                order: 2000 + inbox,
                status: GtdStatus.Inbox,
                capturedAt: Some(isoAt(-1))
            )
        )
        inbox += 1
    }
    let areas = [GtdArea("area_a", "产品")]
    let stats = weeklyReview(GtdWorkspace(items: items.toArray(), areas: areas), TEST_TODAY)
    @Expect(stats.inboxCount, 3000)
    @Expect(stats.inboxProgress, 0)
    @Expect(stats.stuckProjectCount, 1000)
    @Expect(stats.staleAreas.size, 0)
}
