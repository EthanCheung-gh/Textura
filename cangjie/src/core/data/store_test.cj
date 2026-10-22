package textura.core.data

import std.collection.*
import std.env.*
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * Store behaviour: one fact source, immutable updates, undo, atomic save.
 * These are the guarantees the seven views build on.
 */

/**
 * Scratch path for save/load tests.
 *
 * Honours `TMPDIR` (standard convention) so runs on hosts where `/tmp` is a
 * small quota'd tmpfs can point somewhere roomier; falls back to `/tmp`.
 */
func tempStorePath(name: String): String {
    let base = match (getVariable("TMPDIR")) {
        case Some(value) => if (value.isEmpty()) {
            "/tmp"
        } else {
            value
        }
        case None => "/tmp"
    }
    let root = "${base}/textura-core-data-tests"
    try {
        Directory.create(root, recursive: true)
    } catch (_: Exception) {
        // Already present from an earlier run.
        ()
    }
    "${root}/${name}"
}

@Test
func storeCreateItemAppliesKindDefaults(): Unit {
    let store = AppStore(clock: FixedClock(TEST_ANCHOR))
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(FixedClock(TEST_ANCHOR))))

    let action = store.createItem(NewItemInput(ItemKind.Action, "打电话"))
    @Expect(itemStatusWire(action.status), "next")
    @Expect(action.gtd.isSome(), true)
    @Expect(action.gantt.isSome(), true)
    match (action.gtd) {
        case Some(gtd) => @Expect(gtd.clarified, true)
        case None => @Expect(false, true)
    }

    let note = store.createItem(NewItemInput(ItemKind.Note, "随手记"))
    @Expect(itemStatusWire(note.status), "inbox")
    @Expect(note.okr.isNone(), true)

    let objective = store.createItem(NewItemInput(ItemKind.Objective, "新目标"))
    match (objective.okr) {
        case Some(okr) =>
            @Expect(okr.period, "2026-Q1")
            @Expect(okr.confidence, 5)
        case None => @Expect(false, true)
    }

    let step = store.createItem(NewItemInput(ItemKind.Step, "步骤", parentId: Some("sop_onboarding")))
    @Expect(step.sop.isSome(), true)
    // Newest sibling of sop_onboarding: the seeded next_email_draft has order 7.
    @Expect(step.order, 8)
    @Expect(store.workspace().items.size, 34)
}

@Test
func storeUpdateItemMergesPatchAndTimestamps(): Unit {
    let store = seededStore()
    let before = store.workspace()
    store.updateItem("act_design", ItemPatch()
        .withTitle("视觉稿二审")
        .withTags(["官网", "设计"]))
    let after = store.workspace()
    let updated = itemById(after, "act_design") ?? before.items[0]
    @Expect(updated.title, "视觉稿二审")
    @Expect(updated.tags.size, 2)
    @Expect(updated.updatedAt, "2026-03-16T02:00:00.000Z")
    @Expect(after.updatedAt, "2026-03-16T02:00:00.000Z")
    // Unrelated items keep their identity (shared fact, not a copy).
    let untouched = itemById(after, "act_ia") ?? before.items[0]
    @Expect(untouched.updatedAt, itemById(before, "act_ia")?.updatedAt ?? "")
}

@Test
func storeUpdateItemStatusWritesCompletedAt(): Unit {
    let store = seededStore()
    let patch = ItemPatch().withStatus(ItemStatus.Done)
    store.updateItem("act_ia", patch)
    match (itemById(store.workspace(), "act_ia")) {
        case Some(item) =>
            @Expect(itemStatusWire(item.status), "done")
            match (item.completedAt) {
                case Some(value) => @Expect(value, "2026-03-16T02:00:00.000Z")
                case None => @Expect(false, true)
            }
        case None => @Expect(false, true)
    }
    store.setStatus("act_ia", ItemStatus.Next)
    match (itemById(store.workspace(), "act_ia")) {
        case Some(item) => @Expect(item.completedAt.isNone(), true)
        case None => @Expect(false, true)
    }
}

@Test
func storeToggleDoneFlipsBothWays(): Unit {
    let store = seededStore()
    store.toggleDone("act_design")
    match (itemById(store.workspace(), "act_design")) {
        case Some(item) => @Expect(itemStatusWire(item.status), "done")
        case None => @Expect(false, true)
    }
    store.toggleDone("act_design")
    match (itemById(store.workspace(), "act_design")) {
        case Some(item) => @Expect(itemStatusWire(item.status), "next")
        case None => @Expect(false, true)
    }
    // Unknown ids are a no-op, never an exception.
    store.toggleDone("missing")
    @Expect(store.workspace().items.size, 30)
}

@Test
func storeUpdateItemsAppliesBatch(): Unit {
    let store = seededStore()
    store.updateItems([
        ItemPatchTarget("act_design", ItemPatch().withProgress(80.0)),
        ItemPatchTarget("act_ia", ItemPatch().withProgress(90.0)),
        ItemPatchTarget("missing", ItemPatch().withTitle("忽略"))
    ])
    let workspace = store.workspace()
    @Expect(displayProgress(itemById(workspace, "act_design") ?? workspace.items[0]), 80)
    @Expect(displayProgress(itemById(workspace, "act_ia") ?? workspace.items[0]), 90)
}

@Test
func storeDeleteItemsCascades(): Unit {
    let store = seededStore()
    store.deleteItems(["proj_website"])
    let workspace = store.workspace()
    @Expect(itemById(workspace, "proj_website").isNone(), true)
    @Expect(itemById(workspace, "act_design").isNone(), true)
    @Expect(workspace.items.size, 30 - 7)
    var depends = 0
    for (edge in workspace.edges) {
        if (edge.edgeType == EdgeType.Depends) {
            depends += 1
        }
    }
    @Expect(depends, 0)
    @Expect(workspace.runs.size, 3)
}

@Test
func storeDeleteSopRemovesRuns(): Unit {
    let store = seededStore()
    store.deleteItems(["sop_onboarding"])
    @Expect(store.workspace().runs.size, 0)
    @Expect(itemById(store.workspace(), "step_check").isNone(), true)
}

@Test
func storeMoveItemRenumbersSiblings(): Unit {
    let store = seededStore()
    store.moveItem("act_launch", Some("proj_website"), Some(0))
    let workspace = store.workspace()
    @Expect(orderOf(workspace, "act_launch"), 0)
    @Expect(orderOf(workspace, "act_research"), 1)
    @Expect(orderOf(workspace, "act_design"), 2)

    // Moving a node under its own descendant is refused.
    store.moveItem("proj_website", Some("act_design"), None)
    @Expect(parentIdOf(store.workspace(), "proj_website"), "None")
}

@Test
func storeCreateEdgeDeduplicates(): Unit {
    let store = seededStore()
    let first = store.createEdge("act_build", "act_design", EdgeType.Depends)
    let second = store.createEdge("act_build", "act_design", EdgeType.Depends)
    @Expect(first.id, second.id)
    @Expect(store.workspace().edges.size, 12)
    let fresh = store.createEdge("act_launch", "act_content", EdgeType.Depends, label: "串行")
    @Expect(fresh.label, "串行")
    @Expect(store.workspace().edges.size, 13)
    store.deleteEdge(fresh.id)
    @Expect(store.workspace().edges.size, 12)
}

@Test
func storeDependencyHelpers(): Unit {
    let store = seededStore()
    store.addDependency("act_content", "act_ia")
    @Expect(ids(edgeTargetsOf(store.workspace(), "act_content", EdgeType.Depends)), "act_ia")
    store.removeDependency("act_content", "act_ia")
    @Expect(edgeTargetsOf(store.workspace(), "act_content", EdgeType.Depends).size, 0)
}

@Test
func storeAreaLifecycle(): Unit {
    let store = seededStore()
    let area = store.createArea("财务")
    @Expect(area.color, "#9B6A8F")
    @Expect(area.order, 3)
    store.updateArea(area.id, name: Some("财务与法务"))
    @Expect((areaById(store.workspace(), area.id)?.name) ?? "", "财务与法务")
    store.updateItem("act_design", ItemPatch().withAreaId(Some(area.id)))
    @Expect(areaIdOf(store.workspace(), "act_design"), area.id)
    store.deleteArea(area.id)
    @Expect(areaById(store.workspace(), area.id).isNone(), true)
    @Expect(areaIdOf(store.workspace(), "act_design"), "None")
}

@Test
func storeLogRunAppends(): Unit {
    let store = seededStore()
    let run = store.logRun("sop_onboarding", "step_check", RunResult.Pass, note: "权限 OK")
    @Expect(store.workspace().runs.size, 4)
    @Expect(run.result == RunResult.Pass, true)
    @Expect(store.workspace().runs[3].id, run.id)
}

@Test
func storeUndoRedoRestoresSnapshots(): Unit {
    let store = seededStore()
    @Expect(store.canUndo(), false)
    store.updateItem("act_design", ItemPatch().withTitle("改过"))
    @Expect(store.canUndo(), true)
    @Expect(store.undo(), true)
    @Expect(titleOf(store.workspace(), "act_design"), "视觉稿评审")
    @Expect(store.canRedo(), true)
    @Expect(store.redo(), true)
    @Expect(titleOf(store.workspace(), "act_design"), "改过")
    @Expect(store.historyLimit(), 80)
}

@Test
func storeQuickCaptureCreatesInboxAction(): Unit {
    let store = seededStore()
    let item = store.quickCapture("买咖啡豆", context: Some("外出"))
    @Expect(itemStatusWire(item.status), "inbox")
    match (item.gtd) {
        case Some(gtd) =>
            @Expect(gtd.clarified, false)
            @Expect(gtd.context ?? "", "外出")
        case None => @Expect(false, true)
    }
}

@Test
func storeClarifyValidatesAndApplies(): Unit {
    let store = seededStore()
    let form = createClarifyForm(itemById(store.workspace(), "inbox_call_finance") ?? store.workspace().items[0])
    form.title = "  "
    match (store.clarify("inbox_call_finance", form)) {
        case Some(errors) => @Expect(errors.title ?? "", "标题不能为空")
        case None => @Expect(false, true)
    }
    // Nothing was written on validation failure.
    @Expect(titleOf(store.workspace(), "inbox_call_finance"), "给财务回电确认发票抬头")

    form.title = "给财务回电确认发票抬头（已澄清）"
    form.context = "电话"
    form.delegated = true
    form.waitingFor = "财务 · 王会计"
    match (store.clarify("inbox_call_finance", form)) {
        case Some(_) => @Expect(false, true)
        case None => ()
    }
    match (itemById(store.workspace(), "inbox_call_finance")) {
        case Some(item) =>
            @Expect(itemStatusWire(item.status), "waiting")
            match (item.gtd) {
                case Some(gtd) =>
                    @Expect(gtd.clarified, true)
                    @Expect(gtd.waitingFor ?? "", "财务 · 王会计")
                case None => @Expect(false, true)
            }
        case None => @Expect(false, true)
    }
}

@Test
func storeMetricAndProgressShortcuts(): Unit {
    let store = seededStore()
    store.setMetric("kr_nps", 42.0, 70.0, 50.0, "分")
    match (okrOf(store.workspace(), "kr_nps")) {
        case Some(okr) => match (okr.metric) {
            case Some(metric) =>
                @Expect(metric.target, 70.0)
                @Expect(metric.unit, "分")
            case None => @Expect(false, true)
        }
        case None => @Expect(false, true)
    }
    store.setMetricCurrent("kr_wau", 1600.0)
    match (okrOf(store.workspace(), "kr_wau")) {
        case Some(okr) => match (okr.metric) {
            case Some(metric) =>
                @Expect(metric.start, 1200.0)
                @Expect(metric.current, 1600.0)
            case None => @Expect(false, true)
        }
        case None => @Expect(false, true)
    }
    store.setConfidence("kr_nps", 42)
    match (okrOf(store.workspace(), "kr_nps")) {
        case Some(okr) => @Expect(okr.confidence, 10)
        case None => @Expect(false, true)
    }
    store.setProgress("act_design", 140.0)
    @Expect(displayProgress(itemById(store.workspace(), "act_design") ?? store.workspace().items[0]), 100)
    store.setDueDate("act_design", Some("2026-04-01"))
    @Expect(dueKeyOf(store.workspace(), "act_design"), "2026-04-01")
    store.reschedule("act_design", Some("2026-03-30"), None)
    @Expect(startKeyOf(store.workspace(), "act_design"), "2026-03-30")
    @Expect(dueKeyOf(store.workspace(), "act_design"), "None")
}

@Test
func storeLinkOkrCreatesEdge(): Unit {
    let store = seededStore()
    let edge = store.linkOkr("kr_nps", "proj_website")
    @Expect(edge.from, "kr_nps")
    @Expect(edge.edgeType == EdgeType.Okr, true)
    let refs = executionItemsOf(store.workspace(), "kr_nps")
    @Expect(idList(refs), "proj_website")
}

@Test
func storeSaveAndLoadRoundTrip(): Unit {
    let path = tempStorePath("roundtrip.json")
    try {
        remove(path)
    } catch (_: Exception) {
        ()
    }
    let store = AppStore(clock: FixedClock(TEST_ANCHOR))
    store.load(path)
    // Fresh install seeds the demo workspace and writes it out; like the Web
    // store, `load` leaves the save indicator idle afterwards.
    @Expect(store.workspace().items.size, 30)
    @Expect(store.saveStatus() == SaveState.Idle, true)
    let firstBytes = File.readFrom(path)
    let firstDigest = inspectWorkspace(path)
    @Expect(firstDigest.anchorDate, "2026-03-16")

    store.updateItem("act_design", ItemPatch().withTitle("落盘测试"))
    @Expect(store.save(), true)
    let secondDigest = inspectWorkspace(path)
    @Expect(secondDigest.byteCount != firstDigest.byteCount, true)

    let reloaded = AppStore(clock: FixedClock(TEST_ANCHOR))
    reloaded.load(path)
    @Expect(titleOf(reloaded.workspace(), "act_design"), "落盘测试")
    @Expect(reloaded.error().isNone(), true)
    @Expect(reloaded.storeStatus() == StoreStatus.Ready, true)

    // Saving the reloaded document must be byte-identical (stable key order).
    let before = String.fromUtf8(File.readFrom(path))
    @Expect(reloaded.save(), true)
    let after = String.fromUtf8(File.readFrom(path))
    @Expect(after == before, true)
    @Expect(firstBytes.size > 0, true)
}

@Test
func storeSaveFailureNotifies(): Unit {
    let store = seededStore()
    let ok = store.saveTo("/proc/definitely-not-writable/workspace.json")
    @Expect(ok, false)
    @Expect(store.saveStatus() == SaveState.Error, true)
    let notices = store.notices.value()
    @Expect(notices.size > 0, true)
    var hasError = false
    for (notice in notices) {
        if (notice.tone == NoticeTone.Error) {
            hasError = true
        }
    }
    @Expect(hasError, true)
}

@Test
func storeNoticesAreCapped(): Unit {
    let store = AppStore(clock: FixedClock(TEST_ANCHOR))
    for (index in 0..6) {
        store.notify("消息 ${index}")
    }
    @Expect(store.notices.value().size, 4)
    let first = store.notices.value()[0]
    store.dismissNotice(first.id)
    @Expect(store.notices.value().size, 3)
    store.clearNotices()
    @Expect(store.notices.value().size, 0)
}

@Test
func storeImportRejectsCyclesAndKeepsUnknownFields(): Unit {
    let store = seededStore()
    let cyclic = "{\"version\":1,\"items\":[" +
        "{\"id\":\"a\",\"kind\":\"action\",\"title\":\"A\",\"parentId\":\"b\"}," +
        "{\"id\":\"b\",\"kind\":\"action\",\"title\":\"B\",\"parentId\":\"a\"}]," +
        "\"edges\":[],\"areas\":[],\"runs\":[],\"updatedAt\":\"2026-01-01T00:00:00.000Z\"}"
    match (store.importDocument(cyclic)) {
        case Some(message) => @Expect(message.contains("父子环"), true)
        case None => @Expect(false, true)
    }
    @Expect(store.workspace().items.size, 30)

    let withExtra = "{\"version\":1,\"items\":[" +
        "{\"id\":\"a\",\"kind\":\"action\",\"title\":\"A\",\"future\":1}]," +
        "\"edges\":[],\"areas\":[],\"runs\":[],\"updatedAt\":\"2026-01-01T00:00:00.000Z\"}"
    match (store.importDocument(withExtra)) {
        case Some(message) => @Expect(message, "")
        case None => ()
    }
    @Expect(store.workspace().items.size, 1)
    @Expect(store.exportDocument().contains("\"future\""), true)
}

@Test
func storeUiStateAndNavigationHelpers(): Unit {
    let store = AppStore(clock: FixedClock(TEST_ANCHOR))
    @Expect(store.ui.value().route, "dashboard")
    @Expect(store.ui.value().theme, "light")
    @Expect(store.ui.value().okrPeriod, "2026-Q1")
    store.setRoute("gtd")
    store.setTheme("dark")
    store.setSearch("复盘")
    store.setGanttZoom("month")
    store.setGtdContext(Some("电脑"))
    @Expect(store.ui.value().route, "gtd")
    @Expect(store.ui.value().theme, "dark")
    @Expect(store.ui.value().search, "复盘")
    @Expect(store.ui.value().ganttZoom, "month")
    store.setRoute("nope")
    @Expect(store.ui.value().route, "gtd")
    store.toggleTheme()
    @Expect(store.ui.value().theme, "light")
}

@Test
func storeViewContextIsConstructible(): Unit {
    let store = seededStore()
    let log = NavigationLog()
    let context = ViewContext(
        store,
        "light",
        store.anchorToday(),
        1440,
        900,
        {route => log.record(route)}
    )
    @Expect(context.today, "2026-03-16")
    @Expect(context.width, 1440)
    context.navigate("gtd")
    @Expect(log.last, "gtd")
    @Expect(context.store.workspace().items.size, 30)
}

@Test
func storeRouteHelpersMatchWebBehaviour(): Unit {
    @Expect(isRouteId("okr"), true)
    @Expect(isRouteId("nope"), false)
    match (routeFromSearch("?route=gtd&item=act_design")) {
        case Some(route) => @Expect(route, "gtd")
        case None => @Expect(false, true)
    }
    @Expect(routeFromSearch("?route=nope").isNone(), true)
    match (itemIdFromSearch("?route=gtd&item=act_design")) {
        case Some(id) => @Expect(id, "act_design")
        case None => @Expect(false, true)
    }
    @Expect(resolveInitialRoute("?route=okr", Some("gtd")), "okr")
    @Expect(resolveInitialRoute("", Some("gtd")), "gtd")
    @Expect(resolveInitialRoute("", None), "dashboard")
}

@Test
func storeStateCellNotifiesAndBumpsRevision(): Unit {
    let cell = StateCell<Int64>(1)
    let seen = SeenValues()
    let listener = cell.subscribe({value => seen.push(value)})
    cell.set(7)
    @Expect(cell.value(), 7)
    @Expect(cell.revision(), 1)
    @Expect(seen.last, 7)
    @Expect(seen.count, 1)
    cell.unsubscribe(listener)
    cell.set(9)
    @Expect(seen.last, 7)
    @Expect(cell.revision(), 2)
}

@Test
func storeApplyItemPatchMergesDataBlocks(): Unit {
    let item = testItem(
        "kr",
        ItemKind.KeyResult,
        "KR",
        okr: OkrData("2026-Q1", 5, metric: Metric(0.0, 100.0, 10.0, "%"), krOwner: "林一")
    )
    let patch = ItemPatch()
    let okr = OkrPatch()
    okr.confidence = SetValue<Int64>.Value(8)
    let metric = MetricPatch()
    metric.current = SetValue<Float64>.Value(60.0)
    okr.metric = Some(metric)
    patch.okr = Some(okr)
    let updated = applyItemPatch(item, patch, TEST_STAMP, FixedClock(TEST_ANCHOR))
    match (updated.okr) {
        case Some(value) =>
            @Expect(value.confidence, 8)
            @Expect(value.period, "2026-Q1")
            @Expect(value.krOwner ?? "", "林一")
            match (value.metric) {
                case Some(metricValue) =>
                    @Expect(metricValue.start, 0.0)
                    @Expect(metricValue.target, 100.0)
                    @Expect(metricValue.current, 60.0)
                    @Expect(metricValue.unit, "%")
                case None => @Expect(false, true)
            }
        case None => @Expect(false, true)
    }
    @Expect(updated.updatedAt, TEST_STAMP)
}


class NavigationLog {
    var last: String = ""

    func record(route: String): Unit {
        last = route
    }
}

class SeenValues {
    var last: Int64 = 0
    var count: Int64 = 0

    func push(value: Int64): Unit {
        last = value
        count += 1
    }
}

func okrOf(workspace: Workspace, id: String): ?OkrData {
    match (itemById(workspace, id)) {
        case Some(item) => item.okr
        case None => None
    }
}


func titleOf(workspace: Workspace, id: String): String {
    match (itemById(workspace, id)) {
        case Some(item) => item.title
        case None => ""
    }
}

func orderOf(workspace: Workspace, id: String): Int64 {
    match (itemById(workspace, id)) {
        case Some(item) => item.order
        case None => -1
    }
}

func areaIdOf(workspace: Workspace, id: String): String {
    match (itemById(workspace, id)) {
        case Some(item) => match (item.areaId) {
            case Some(value) => value
            case None => "None"
        }
        case None => "missing"
    }
}

func parentIdOf(workspace: Workspace, id: String): String {
    match (itemById(workspace, id)) {
        case Some(item) => match (item.parentId) {
            case Some(value) => value
            case None => "None"
        }
        case None => "missing"
    }
}

func dueKeyOf(workspace: Workspace, id: String): String {
    match (itemById(workspace, id)) {
        case Some(item) => match (item.dueKey()) {
            case Some(value) => value
            case None => "None"
        }
        case None => "missing"
    }
}

func startKeyOf(workspace: Workspace, id: String): String {
    match (itemById(workspace, id)) {
        case Some(item) => match (item.startKey()) {
            case Some(value) => value
            case None => "None"
        }
        case None => "missing"
    }
}


/* ------------------------------------------------------------------ */
/* Parity clock / anchor                                               */
/* ------------------------------------------------------------------ */

/** 2026-11-05 is in 2026-Q4: deliberately a different quarter than the anchor. */
let OTHER_QUARTER_MILLIS: Int64 = 1793335200000

@Test
func storeParityAnchorBeatsTheInjectedClock(): Unit {
    let q4Millis = match (parseIsoMillis("2026-11-05T10:00:00+08:00")) {
        case Some(value) => value
        case None => OTHER_QUARTER_MILLIS
    }
    // Clock in Q4, frozen anchor in Q1: the anchor must win, otherwise a snapshot
    // taken in another quarter would open a different OKR period than the reference.
    let store = AppStore(clock: FixedClock(q4Millis), todayOverride: Some("2026-03-16"))
    @Expect(store.anchorToday(), "2026-03-16")
    @Expect(store.ui.value().okrPeriod, "2026-Q1")

    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(FixedClock(TEST_ANCHOR))))
    @Expect(store.ui.value().okrPeriod, "2026-Q1")

    // Any write during parity must use the frozen clock, not the host clock.
    store.updateItem("act_design", ItemPatch().withTitle("锚点写入"))
    @Expect(store.workspace().updatedAt, "2026-11-05T02:00:00.000Z")
    @Expect(titleOf(store.workspace(), "act_design"), "锚点写入")
}

@Test
func storeForParityFreezesClockAndToday(): Unit {
    let store = AppStore.forParity("2026-03-16")
    @Expect(store.anchorToday(), "2026-03-16")
    @Expect(store.ui.value().okrPeriod, "2026-Q1")

    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(FixedClock(TEST_ANCHOR))))
    @Expect(store.ui.value().okrPeriod, "2026-Q1")
    @Expect(store.anchorToday(), "2026-03-16")

    // The frozen clock sits at local midnight of the anchor, so written timestamps
    // are reproducible (16:00Z of the previous day) and never the wall clock.
    store.updateItem("act_design", ItemPatch().withTitle("parity 写入"))
    @Expect(store.workspace().updatedAt, "2026-03-15T16:00:00.000Z")
    @Expect(titleOf(store.workspace(), "act_design"), "parity 写入")
}

@Test
func storeForParityRejectsUnparsableAnchor(): Unit {
    var raised = false
    try {
        AppStore.forParity("unknown")
    } catch (_: IllegalArgumentException) {
        raised = true
    }
    @Expect(raised, true)
}

@Test
func storeInitialOkrPeriodFollowsAnchorAndWebFallback(): Unit {
    let q1 = testWorkspace([testItem("o1", ItemKind.Objective, "Q1 目标", okr: OkrData("2026-Q1", 5))])
    @Expect(initialOkrPeriod(q1, "2026-03-16"), "2026-Q1")

    let multi = testWorkspace([
        testItem("o1", ItemKind.Objective, "Q1 目标", okr: OkrData("2026-Q1", 5)),
        testItem("o2", ItemKind.Objective, "Q2 目标", order: 1, okr: OkrData("2026-Q2", 5))
    ])
    // Anchor quarter wins even though it is not the newest period.
    @Expect(initialOkrPeriod(multi, "2026-03-16"), "2026-Q1")
    @Expect(initialOkrPeriod(multi, "2026-05-16"), "2026-Q2")

    // Anchor quarter absent -> newest period (TS `periods[0] ?? quarter`).
    let q4Only = testWorkspace([testItem("o3", ItemKind.Objective, "旧目标", okr: OkrData("2025-Q4", 5))])
    @Expect(initialOkrPeriod(q4Only, "2026-03-16"), "2025-Q4")

    // No objectives at all -> the anchor quarter.
    @Expect(initialOkrPeriod(emptyWorkspace(FixedClock(TEST_ANCHOR)), "2026-03-16"), "2026-Q1")
    @Expect(initialOkrPeriod(q1, "bad-date"), "2026-Q1")

    // The clock overload is the non-parity path; it must agree when the clock
    // itself sits in Q1.
    @Expect(initialOkrPeriod(multi, FixedClock(TEST_ANCHOR)), "2026-Q1")
}

@Test
func storeTodayOverrideCanBeRepointed(): Unit {
    let store = AppStore(clock: FixedClock(TEST_ANCHOR))
    @Expect(store.anchorToday(), "2026-03-16")
    store.setTodayOverride(Some("2026-05-16"))
    @Expect(store.anchorToday(), "2026-05-16")
    @Expect(store.ui.value().okrPeriod, "2026-Q2")
    store.setTodayOverride(None)
    @Expect(store.anchorToday(), "2026-03-16")
}
