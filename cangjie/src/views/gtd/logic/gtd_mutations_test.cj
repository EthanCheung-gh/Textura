package textura.views.gtd.logic

/*
 * `src/modules/gtd/gtdMutations.ts` 的意图序列断言，外加映射自
 * `ClarifyDialog.submit` 的澄清四分支。
 *
 * 断言方式：把意图序列压成可读摘要（`mutationSummary`）整体比对，
 * 再对关键载荷（notes / status / 新建条目）做精确断言。
 */

let NOW_ISO: String = isoAt(0)

func inboxItem(): GtdItem {
    mkItem("i1", GtdKind.Action, "给财务回电", status: GtdStatus.Inbox, capturedAt: Some(isoAt(-1)))
}

@Test
func completeInboxItemTogglesDoneAndNotifies(): Unit {
    let change = completeInboxItem(inboxItem())
    @Expect(
        mutationSummary(change.mutations),
        "ToggleDone(i1) -> Notify(已完成「给财务回电」，2 分钟规则处理完毕)"
    )
    @Expect(change.resultId, Option<String>.None)
    @Expect(change.createdSpec().isNone(), true)
}

@Test
func deleteInboxItemDeletesWithUndoHint(): Unit {
    let change = deleteInboxItem(inboxItem())
    @Expect(
        mutationSummary(change.mutations),
        "DeleteItems(i1) -> Notify(已删除「给财务回电」，按 Ctrl/Cmd+Z 可撤销)"
    )
}

@Test
func promoteActionInPlaceFlipsClarifiedAndStatus(): Unit {
    let change = promoteItemToNext(inboxItem(), "unused", NOW_ISO)
    @Expect(
        mutationSummary(change.mutations),
        "UpdateItem(i1{clarified=true}) -> SetStatus(i1:next) -> Notify(已放入下一步「给财务回电」)"
    )
    @Expect(change.resultId, Some("i1"))
}

@Test
func promoteReferenceCreatesNextActionAndArchivesSource(): Unit {
    let source = mkItem(
        "i1",
        GtdKind.Reference,
        "竞品截图",
        notes: "记录",
        tags: ["竞品"],
        areaId: Some("area_product"),
        status: GtdStatus.Inbox,
        capturedAt: Some(isoAt(-3)),
        context: Some("电话"),
        energy: Some(Energy.High)
    )
    let change = promoteItemToNext(source, "new1", NOW_ISO)
    @Expect(
        mutationSummary(change.mutations),
        "CreateItem(new1:action:next:竞品截图) -> " +
        "UpdateItem(i1{notes=记录\n[2026-10-21 12:00] 澄清：已转为下一步行动（new1）;clarified=true}) -> " +
        "SetStatus(i1:done) -> Notify(已转为下一步「竞品截图」)"
    )
    @Expect(change.resultId, Some("new1"))

    let spec = change.createdSpec().getOrThrow()
    @Expect(kindText(spec.kind), "action")
    @Expect(spec.notes, "记录")
    @Expect(joinTags(spec.tags), "竞品")
    @Expect(spec.areaId, Some("area_product"))
    @Expect(spec.context, Some("电话"))
    @Expect(spec.energy, Some(Energy.High))
    @Expect(spec.capturedAt, Some(isoAt(-3)))
    @Expect(spec.twoMinuteCandidate, false)
    @Expect(spec.clarified, true)
}

@Test
func promoteReferenceWithoutCapturedAtUsesInjectedNow(): Unit {
    let source = mkItem("i1", GtdKind.Note, "笔记", notes: "")
    let change = promoteItemToNext(source, "new1", NOW_ISO)
    @Expect(change.createdSpec().getOrThrow().capturedAt, Some(NOW_ISO))
}

@Test
func nudgeWaitingItemAppendsTimestampedNote(): Unit {
    let waiting = mkItem(
        "w1",
        GtdKind.Action,
        "等回复",
        notes: "旧记录",
        status: GtdStatus.Waiting,
        waitingFor: Some("  张律师  ")
    )
    let change = nudgeWaitingItem(waiting, NOW_ISO)
    @Expect(
        mutationSummary(change.mutations),
        "UpdateItem(w1{notes=旧记录\n[2026-10-21 12:00] 催办：已提醒 张律师，等待回复。}) -> " +
        "Notify(已记录催办：等回复)"
    )
}

@Test
func nudgeWaitingItemFallsBackToGenericTarget(): Unit {
    let waiting = mkItem("w1", GtdKind.Action, "等回复", status: GtdStatus.Waiting, waitingFor: Some("   "))
    let change = nudgeWaitingItem(waiting, NOW_ISO)
    match (change.mutations[0]) {
        case UpdateItem(id, patch) =>
            @Expect(id, "w1")
            @Expect(patch.notes.getOrThrow(), "[2026-10-21 12:00] 催办：已提醒 对方，等待回复。")
        case _ => @Fail("第一条意图应为 UpdateItem")
    }
}

@Test
func createNextActionForProjectAddsChildAction(): Unit {
    let project = mkItem(
        "p1",
        GtdKind.Project,
        "官网改版",
        status: GtdStatus.Active,
        areaId: Some("area_a"),
        tags: ["市场"]
    )
    let change = createNextActionForProject(project, "new2", NOW_ISO)
    @Expect(
        mutationSummary(change.mutations),
        "CreateItem(new2:action:next:推进：官网改版) -> Notify(已为「官网改版」补一个下一步动作)"
    )
    @Expect(change.resultId, Some("new2"))
    let spec = change.createdSpec().getOrThrow()
    @Expect(spec.parentId, Some("p1"))
    @Expect(spec.areaId, Some("area_a"))
    @Expect(joinTags(spec.tags), "市场")
    @Expect(spec.capturedAt, Some(NOW_ISO))
    @Expect(spec.clarified, true)
}

@Test
func activateSomedayItemReusesPromoteBehaviour(): Unit {
    let someday = mkItem("s1", GtdKind.Action, "某天再说", status: GtdStatus.Someday)
    let promised = promoteItemToNext(someday, "new1", NOW_ISO)
    let activated = activateSomedayItem(someday, "new1", NOW_ISO)
    @Expect(mutationSummary(activated.mutations), mutationSummary(promised.mutations))
    @Expect(activated.resultId, Some("s1"))
}

@Test
func clarifyArchivePatchesInPlaceAndMarksDone(): Unit {
    let item = mkItem("i1", GtdKind.Action, "竞品截图", status: GtdStatus.Inbox, notes: "原记录")
    let form = baseForm().patched(clarifyType: Some(ClarifyType.Reference))
    let change = clarifyItem(item, form, "new3", NOW_ISO)
    @Expect(
        mutationSummary(change.mutations),
        "UpdateItem(i1{title=给财务回电;" +
        "notes=确认发票抬头\n[2026-10-21 12:00] 澄清：归档为参考资料。;" +
        "tags=杂事,财务;areaId=area_product;due=2026-01-02;context=飞机上;clarified=true;twoMinute=true}) -> " +
        "SetStatus(i1:done) -> Notify(已归档为参考资料「给财务回电」)"
    )
    @Expect(change.resultId, Some("i1"))
    @Expect(change.createdSpec().isNone(), true)
}

@Test
func clarifyNoteArchiveUsesNoteLabel(): Unit {
    let item = mkItem("i1", GtdKind.Action, "随手记", status: GtdStatus.Inbox)
    let form = baseForm().patched(clarifyType: Some(ClarifyType.Note))
    let change = clarifyItem(item, form, "new3", NOW_ISO)
    @Expect(
        mutationSummary(change.mutations),
        "UpdateItem(i1{title=给财务回电;" +
        "notes=确认发票抬头\n[2026-10-21 12:00] 澄清：归档为笔记。;" +
        "tags=杂事,财务;areaId=area_product;due=2026-01-02;context=飞机上;clarified=true;twoMinute=true}) -> " +
        "SetStatus(i1:done) -> Notify(已归档为笔记「给财务回电」)"
    )
}

@Test
func clarifyReferenceIntoNextActionCreatesAndArchives(): Unit {
    let item = mkItem("i1", GtdKind.Reference, "竞品截图", notes: "原记录", status: GtdStatus.Inbox)
    let change = clarifyItem(item, baseForm(), "new3", NOW_ISO)
    @Expect(
        mutationSummary(change.mutations),
        "CreateItem(new3:action:next:给财务回电) -> " +
        "UpdateItem(i1{notes=原记录\n[2026-10-21 12:00] 澄清：已转为下一步行动（new3）;clarified=true}) -> " +
        "SetStatus(i1:done) -> Notify(已转为下一步「给财务回电」)"
    )
    @Expect(change.resultId, Some("new3"))
}

@Test
func clarifyIntoProjectCreatesProjectAndArchives(): Unit {
    let item = mkItem("i1", GtdKind.Action, "官网改版", notes: "原记录", status: GtdStatus.Inbox)
    let form = baseForm().patched(clarifyType: Some(ClarifyType.Project))
    let change = clarifyItem(item, form, "new4", NOW_ISO)
    @Expect(
        mutationSummary(change.mutations),
        "CreateItem(new4:project:next:给财务回电) -> " +
        "UpdateItem(i1{notes=原记录\n[2026-10-21 12:00] 澄清：已升级为项目（new4）;clarified=true}) -> " +
        "SetStatus(i1:done) -> Notify(已升级为项目「给财务回电」)"
    )
    @Expect(change.resultId, Some("new4"))
    @Expect(change.createdSpec().getOrThrow().kind, GtdKind.Project)
}

@Test
func clarifyActionInPlacePatchesAllFieldsAndKeepsEnergy(): Unit {
    let item = mkItem("i1", GtdKind.Action, "旧标题", status: GtdStatus.Inbox)
    let change = clarifyItem(item, baseForm(), "unused", NOW_ISO)
    @Expect(
        mutationSummary(change.mutations),
        "UpdateItem(i1{title=给财务回电;notes=确认发票抬头;tags=杂事,财务;areaId=area_product;" +
        "due=2026-01-02;context=飞机上;clarified=true;twoMinute=true}) -> " +
        "SetStatus(i1:next) -> Notify(已澄清「给财务回电」)"
    )
    match (change.mutations[0]) {
        case UpdateItem(id, patch) =>
            @Expect(id, "i1")
            @Expect(patch.energy, Some(Energy.High))
        case _ => @Fail("第一条意图应为 UpdateItem")
    }
}

@Test
func clarifyDelegatedActionTargetsWaitingStatus(): Unit {
    let item = mkItem("i1", GtdKind.Action, "旧标题", status: GtdStatus.Inbox)
    let form = baseForm().patched(delegated: Some(true), waitingFor: Some("张律师"))
    let change = clarifyItem(item, form, "unused", NOW_ISO)
    @Expect(
        mutationSummary(change.mutations),
        "UpdateItem(i1{title=给财务回电;notes=确认发票抬头;tags=杂事,财务;areaId=area_product;" +
        "due=2026-01-02;context=飞机上;clarified=true;twoMinute=true}) -> " +
        "SetStatus(i1:waiting) -> Notify(已澄清「给财务回电」)"
    )
    match (change.mutations[0]) {
        case UpdateItem(id, patch) =>
            @Expect(patch.waitingFor, Some("张律师"))
        case _ => @Fail("第一条意图应为 UpdateItem")
    }
}

@Test
func notifyOnlyWrapsASingleNotice(): Unit {
    let change = notifyOnly("标题不能为空", NoticeTone.Error)
    @Expect(mutationSummary(change.mutations), "Notify(标题不能为空)")
    @Expect(change.resultId, Option<String>.None)
}
