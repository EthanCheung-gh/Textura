package textura.views.gantt.logic

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * 逐条移植 Web 版 `scale.test.ts` 的 `buildRows` 断言。
 * 期望值与 TS 实现（含 `rollupProgress` / `treeDepth` / `descendantsOf`）逐项对齐。
 */
func rowsWorkspace(): Array<GanttRow> {
    [
        makeItem(
            "p1",
            "官网改版",
            GanttKind.Project,
            startDate: Some("2026-01-05"),
            endDate: Some("2026-01-10"),
            progress: Some(30.0),
            status: GanttStatus.Active,
            order: 1
        ),
        makeItem(
            "a2",
            "较早任务",
            GanttKind.Action,
            startDate: Some("2026-01-05"),
            endDate: Some("2026-01-06"),
            progress: Some(0.0),
            parentId: Some("p1"),
            order: 1
        ),
        makeItem(
            "a1",
            "较晚任务",
            GanttKind.Action,
            startDate: Some("2026-01-07"),
            endDate: Some("2026-01-09"),
            progress: Some(100.0),
            status: GanttStatus.Done,
            parentId: Some("p1"),
            order: 0
        ),
        makeItem("a3", "未排期任务", GanttKind.Action, parentId: Some("p1"), order: 2),
        makeItem(
            "a4",
            "最早任务",
            GanttKind.Action,
            startDate: Some("2026-01-03"),
            endDate: Some("2026-01-04"),
            progress: Some(0.0),
            parentId: Some("p1"),
            order: 3
        ),
        makeItem(
            "a2b",
            "嵌套子任务",
            GanttKind.Action,
            startDate: Some("2026-01-06"),
            endDate: Some("2026-01-06"),
            progress: Some(0.0),
            parentId: Some("a2"),
            order: 0
        ),
        makeItem("s1", "新用户 onboarding SOP", GanttKind.Sop, status: GanttStatus.Active, order: 0),
        makeItem("step1", "注册", GanttKind.Step, parentId: Some("s1"), order: 0),
        makeItem("a5", "欢迎邮件初稿", GanttKind.Action, parentId: Some("s1"), order: 1),
        makeItem("r1", "整理本周复盘", GanttKind.Action, order: 4),
        makeItem("i1", "收件箱任务", GanttKind.Action, status: GanttStatus.Inbox, order: 0),
        makeItem(
            "m1",
            "发布里程碑",
            GanttKind.Milestone,
            startDate: Some("2026-01-12"),
            endDate: Some("2026-01-12"),
            progress: Some(0.0),
            order: 5
        )
    ]
}

func rowIds(rows: Array<GanttTreeRow>): Array<String> {
    let ids = ArrayList<String>()
    for (row in rows) {
        ids.add(treeRowId(row))
    }
    ids.toArray()
}

func groupIds(rows: Array<GanttTreeRow>): Array<String> {
    let ids = ArrayList<String>()
    for (row in rows) {
        if (isGroupRow(row)) {
            ids.add(treeRowId(row))
        }
    }
    ids.toArray()
}

func itemIdsOf(rows: Array<GanttTreeRow>, groupId: String): Array<String> {
    let ids = ArrayList<String>()
    for (row in rows) {
        match (itemRowOf(row)) {
            case Some(item) =>
                if (item.groupId == groupId) {
                    ids.add(item.id)
                }
            case None => ()
        }
    }
    ids.toArray()
}

func findGroup(rows: Array<GanttTreeRow>, id: String): ?GanttGroupRow {
    for (row in rows) {
        match (groupRowOf(row)) {
            case Some(group) =>
                if (group.id == id) {
                    return Some(group)
                }
            case None => ()
        }
    }
    None
}

func findItem(rows: Array<GanttTreeRow>, id: String): ?GanttItemRow {
    for (row in rows) {
        match (itemRowOf(row)) {
            case Some(item) =>
                if (item.id == id) {
                    return Some(item)
                }
            case None => ()
        }
    }
    None
}

@Test
func buildRowsGroupsAndSortsMembers() {
    let rows = buildRows(rowsWorkspace())
    // 有日期的分组优先；SOP 只有未排期子项；未分组始终最后。
    @Assert(groupIds(rows), ["p1", "s1", UNGROUPED_ID])

    let p1 = findGroup(rows, "p1").getOrThrow()
    @Assert(p1.count, 5)
    @Assert(p1.start, Some("2026-01-03"))
    @Assert(p1.end, Some("2026-01-10"))
    @Assert(p1.collapsed, false)
    // TS `rollupProgress`：p1 的 4 个直接子项里 1 个 done → 25。
    @Assert(p1.progress, 25)
    @Assert(p1.title, "官网改版")

    @Assert(itemIdsOf(rows, "p1"), ["a4", "a2", "a2b", "a1", "a3"])
    @Assert(findItem(rows, "a2b").getOrThrow().depth, 2)
    @Assert(findItem(rows, "a4").getOrThrow().depth, 1)

    // 收件箱条目被排除，step 不进入甘特。
    @Assert(findItem(rows, "i1").isNone(), true)
    @Assert(findItem(rows, "step1").isNone(), true)

    let ungrouped = findGroup(rows, UNGROUPED_ID).getOrThrow()
    @Assert(ungrouped.count, 2)
    @Assert(ungrouped.title, "未分组")
    @Assert(ungrouped.start, Some("2026-01-12"))
    @Assert(ungrouped.end, Some("2026-01-12"))
    @Assert(ungrouped.progress, 0)
    @Assert(ungrouped.item.isNone(), true)
    @Assert(itemIdsOf(rows, UNGROUPED_ID), ["m1", "r1"])

    let s1 = findGroup(rows, "s1").getOrThrow()
    @Assert(s1.count, 1)
    @Assert(s1.start.isNone(), true)
    @Assert(s1.end.isNone(), true)
}

@Test
func buildRowsHonorsCollapsedGroups() {
    let collapsed = HashSet<String>()
    collapsed.add("p1")
    let rows = buildRows(rowsWorkspace(), collapsed)
    let p1 = findGroup(rows, "p1").getOrThrow()
    @Assert(p1.collapsed, true)
    @Assert(p1.count, 5)
    @Assert(itemIdsOf(rows, "p1").size, 0)

    let collapsedUngroupedSet = HashSet<String>()
    collapsedUngroupedSet.add(UNGROUPED_ID)
    let collapsedUngrouped = buildRows(rowsWorkspace(), collapsedUngroupedSet)
    @Assert(itemIdsOf(collapsedUngrouped, UNGROUPED_ID).size, 0)
    @Assert(treeRowId(collapsedUngrouped[collapsedUngrouped.size - 1]), UNGROUPED_ID)
    // 其它分组不受影响。
    @Assert(itemIdsOf(collapsedUngrouped, "p1").size, 5)
}

@Test
func buildRowsExcludesHiddenKindsAndStatuses() {
    let rows = buildRows(rowsWorkspace())
    let ids = rowIds(rows)
    // 「未分组」只有里程碑与普通行动；收件箱条目与 SOP step 都不出现在任何行里。
    @Assert(ids.size, 11)
    @Assert(findItem(rows, "i1").isNone(), true)
    @Assert(findItem(rows, "step1").isNone(), true)
}

@Test
func rowDepthMatchesProvidedLevel() {
    // `level` 是调用方从 core.data 的 treeDepth 预计算的绝对深度；
    // logic 内部用 parentId 重算，两者在合法输入下必须一致。
    let source = [
        makeItem("root", "根", GanttKind.Project, level: 0, order: 0),
        makeItem("child", "子", GanttKind.Action, level: 1, parentId: Some("root"), order: 0),
        makeItem("grand", "孙", GanttKind.Action, level: 2, parentId: Some("child"), order: 0)
    ]
    for (row in source) {
        @Assert(rowDepth(source, row.id), row.level)
    }
    let rows = buildRows(source)
    @Assert(findItem(rows, "grand").getOrThrow().depth, 2)
    @Assert(findItem(rows, "child").getOrThrow().depth, 1)
}

@Test
func buildRowsHandlesCyclesSafely() {
    let rows = [
        makeItem("x", "X", GanttKind.Project, parentId: Some("y"), order: 0),
        makeItem("y", "Y", GanttKind.Project, parentId: Some("x"), order: 1),
        makeItem("z", "Z", GanttKind.Action, parentId: Some("z"), order: 2)
    ]
    let built = buildRows(rows)
    // 环里没有合法根，全部落到「未分组」，且不会死循环。
    @Assert(groupIds(built), [UNGROUPED_ID])
    @Assert(findItem(built, "z").getOrThrow().depth, 1)
}
