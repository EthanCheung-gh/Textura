package textura.views.gtd

import std.collection.*
import std.unicode.*
import textura.core.data.*
import textura.views.gtd.logic as gl

/*
 * 适配层与「变更意图」执行器。
 *
 * - `core.data.Item` → `logic.GtdItem`：字段对照见 docs/GTD-LOGIC.md §3，不做任何业务判断。
 * - `logic.GtdMutation` → `AppStore` 动作：顺序即应用顺序（GTD-LOGIC.md §6）。
 *
 * `logic.GtdNewItem.id` 在纯函数层由调用方注入，而 `AppStore.createItem` 自己生成 id
 * （`uid(prefix, random)`），因此应用 `CreateItem` 时把「意图 id → 落库 id」记进映射表，
 * 后续意图里的 id 与备注文案里的占位 id 一并改写，保证数据自洽。
 */

/* ---------------------------------------------------------------- Item → GtdItem */

func gtdKindOf(kind: ItemKind): gl.GtdKind {
    match (kind) {
        case ItemKind.Objective => gl.GtdKind.Objective
        case ItemKind.KeyResult => gl.GtdKind.KeyResult
        case ItemKind.Project => gl.GtdKind.Project
        case ItemKind.Action => gl.GtdKind.Action
        case ItemKind.Sop => gl.GtdKind.Sop
        case ItemKind.Step => gl.GtdKind.Step
        case ItemKind.Milestone => gl.GtdKind.Milestone
        case ItemKind.Note => gl.GtdKind.Note
        case ItemKind.Reference => gl.GtdKind.Reference
    }
}

func coreKindOf(kind: gl.GtdKind): ItemKind {
    match (kind) {
        case gl.GtdKind.Objective => ItemKind.Objective
        case gl.GtdKind.KeyResult => ItemKind.KeyResult
        case gl.GtdKind.Project => ItemKind.Project
        case gl.GtdKind.Action => ItemKind.Action
        case gl.GtdKind.Sop => ItemKind.Sop
        case gl.GtdKind.Step => ItemKind.Step
        case gl.GtdKind.Milestone => ItemKind.Milestone
        case gl.GtdKind.Note => ItemKind.Note
        case gl.GtdKind.Reference => ItemKind.Reference
    }
}

func gtdStatusOf(status: ItemStatus): gl.GtdStatus {
    match (status) {
        case ItemStatus.Inbox => gl.GtdStatus.Inbox
        case ItemStatus.Next => gl.GtdStatus.Next
        case ItemStatus.Active => gl.GtdStatus.Active
        case ItemStatus.Waiting => gl.GtdStatus.Waiting
        case ItemStatus.Scheduled => gl.GtdStatus.Scheduled
        case ItemStatus.Someday => gl.GtdStatus.Someday
        case ItemStatus.Done => gl.GtdStatus.Done
        case ItemStatus.Dropped => gl.GtdStatus.Dropped
    }
}

func coreStatusOf(status: gl.GtdStatus): ItemStatus {
    match (status) {
        case gl.GtdStatus.Inbox => ItemStatus.Inbox
        case gl.GtdStatus.Next => ItemStatus.Next
        case gl.GtdStatus.Active => ItemStatus.Active
        case gl.GtdStatus.Waiting => ItemStatus.Waiting
        case gl.GtdStatus.Scheduled => ItemStatus.Scheduled
        case gl.GtdStatus.Someday => ItemStatus.Someday
        case gl.GtdStatus.Done => ItemStatus.Done
        case gl.GtdStatus.Dropped => ItemStatus.Dropped
    }
}

func gtdEnergyOf(energy: ?Energy): ?gl.Energy {
    match (energy) {
        case Some(Energy.Low) => Some(gl.Energy.Low)
        case Some(Energy.Medium) => Some(gl.Energy.Medium)
        case Some(Energy.High) => Some(gl.Energy.High)
        case None => None
    }
}

func coreEnergyOf(energy: ?gl.Energy): ?Energy {
    match (energy) {
        case Some(gl.Energy.Low) => Some(Energy.Low)
        case Some(gl.Energy.Medium) => Some(Energy.Medium)
        case Some(gl.Energy.High) => Some(Energy.High)
        case None => None
    }
}

public func toGtdItem(item: Item): gl.GtdItem {
    var capturedAt: ?String = None
    var clarified = false
    var context: ?String = None
    var energy: ?gl.Energy = None
    var waitingFor: ?String = None
    var twoMinute = false
    match (item.gtd) {
        case Some(gtd) =>
            capturedAt = Some(gtd.capturedAt)
            clarified = gtd.clarified
            context = gtd.context
            energy = gtdEnergyOf(gtd.energy)
            waitingFor = gtd.waitingFor
            match (gtd.twoMinuteCandidate) {
                case Some(value) => twoMinute = value
                case None => ()
            }
        case None => ()
    }
    var startDate: ?String = None
    var dueDate: ?String = None
    match (item.gantt) {
        case Some(gantt) =>
            startDate = gantt.start
            dueDate = gantt.end
        case None => ()
    }
    var metric: ?gl.GtdMetric = None
    match (item.okr) {
        case Some(okr) => match (okr.metric) {
            case Some(value) => metric = Some(gl.GtdMetric(value.start, value.target, current: value.current))
            case None => ()
        }
        case None => ()
    }
    gl.GtdItem(
        item.id,
        gtdKindOf(item.kind),
        item.title,
        notes: item.notes,
        parentId: item.parentId,
        order: item.order,
        status: gtdStatusOf(item.status),
        tags: item.tags,
        areaId: item.areaId,
        createdAt: item.createdAt,
        updatedAt: item.updatedAt,
        completedAt: item.completedAt,
        capturedAt: capturedAt,
        clarified: clarified,
        context: context,
        energy: energy,
        waitingFor: waitingFor,
        twoMinuteCandidate: twoMinute,
        startDate: startDate,
        dueDate: dueDate,
        metric: metric
    )
}

public func toGtdWorkspace(workspace: Workspace): gl.GtdWorkspace {
    let items = ArrayList<gl.GtdItem>()
    for (item in workspace.items) {
        items.add(toGtdItem(item))
    }
    let areas = ArrayList<gl.GtdArea>()
    for (area in workspace.areas) {
        areas.add(gl.GtdArea(area.id, area.name))
    }
    gl.GtdWorkspace(items: items.toArray(), areas: areas.toArray())
}

/* ---------------------------------------------------------------- GtdPatch → ItemPatch */

/** `''` → `None`，否则 `Some`；用来给 `SetValue<?String>` 提供明确类型。 */
func optionalText(value: String): ?String {
    if (value.isEmpty()) {
        None
    } else {
        Some(value)
    }
}

func toItemPatch(patch: gl.GtdPatch): ItemPatch {
    let out = ItemPatch()
    match (patch.title) {
        case Some(value) => out.title = SetValue<String>.Value(value)
        case None => ()
    }
    match (patch.notes) {
        case Some(value) => out.notes = SetValue<String>.Value(value)
        case None => ()
    }
    match (patch.tags) {
        case Some(value) => out.tags = SetValue<Array<String>>.Value(value)
        case None => ()
    }
    match (patch.areaId) {
        case gl.FieldUpdate<String>.Keep => ()
        case gl.FieldUpdate<String>.Clear => out.areaId = SetValue<?String>.Value(optionalText(""))
        case gl.FieldUpdate<String>.Set(value) => out.areaId = SetValue<?String>.Value(Some(value))
    }
    var gtdNeeded = false
    let gtd = GtdPatch()
    match (patch.context) {
        case Some(value) =>
            gtdNeeded = true
            gtd.context = SetValue<?String>.Value(optionalText(value.trim()))
        case None => ()
    }
    match (patch.energy) {
        case Some(value) =>
            gtdNeeded = true
            gtd.energy = SetValue<?Energy>.Value(coreEnergyOf(Some(value)))
        case None => ()
    }
    match (patch.waitingFor) {
        case Some(value) =>
            gtdNeeded = true
            gtd.waitingFor = SetValue<?String>.Value(optionalText(value.trim()))
        case None => ()
    }
    match (patch.clarified) {
        case Some(value) =>
            gtdNeeded = true
            gtd.clarified = SetValue<Bool>.Value(value)
        case None => ()
    }
    match (patch.twoMinuteCandidate) {
        case Some(value) =>
            gtdNeeded = true
            gtd.twoMinuteCandidate = SetValue<?Bool>.Value(Some(value))
        case None => ()
    }
    if (gtdNeeded) {
        out.gtd = Some(gtd)
    }
    match (patch.dueDate) {
        case gl.FieldUpdate<String>.Keep => ()
        case gl.FieldUpdate<String>.Clear =>
            let gantt = GanttPatch()
            gantt.end = SetValue<?String>.Value(optionalText(""))
            out.gantt = Some(gantt)
        case gl.FieldUpdate<String>.Set(value) =>
            let gantt = GanttPatch()
            gantt.end = SetValue<?String>.Value(Some(value))
            out.gantt = Some(gantt)
    }
    out
}

/* ---------------------------------------------------------------- 意图执行 */

func coreToneOf(tone: gl.NoticeTone): NoticeTone {
    match (tone) {
        case gl.NoticeTone.Info => NoticeTone.Info
        case gl.NoticeTone.Success => NoticeTone.Success
        case gl.NoticeTone.Error => NoticeTone.Error
    }
}

func specToInput(spec: gl.GtdNewItem): NewItemInput {
    let gtd = GtdPatch()
    gtd.capturedAt = SetValue<String>.Value(match (spec.capturedAt) {
        case Some(value) => value
        case None => ""
    })
    gtd.clarified = SetValue<Bool>.Value(spec.clarified)
    gtd.context = SetValue<?String>.Value(spec.context)
    gtd.energy = SetValue<?Energy>.Value(coreEnergyOf(spec.energy))
    gtd.waitingFor = SetValue<?String>.Value(optionalText(spec.waitingFor))
    gtd.twoMinuteCandidate = SetValue<?Bool>.Value(Some(spec.twoMinuteCandidate))
    let gantt = GanttPatch()
    gantt.start = SetValue<?String>.Value(spec.startDate)
    gantt.end = SetValue<?String>.Value(spec.dueDate)
    NewItemInput(
        coreKindOf(spec.kind),
        spec.title,
        notes: spec.notes,
        parentId: spec.parentId,
        status: Some(coreStatusOf(spec.status)),
        tags: spec.tags,
        areaId: spec.areaId,
        gtd: gtd,
        gantt: gantt
    )
}

/** 把意图备注里出现的占位 id 改写成真正落库的 id。 */
func rewriteId(text: String, from: String, to: String): String {
    if (from.isEmpty() || from == to) {
        return text
    }
    text.replace(from, to)
}

/**
 * 按顺序把 `GtdChange` 落到 store。
 * 返回所有被新建条目的 id（按创建顺序），供 UI 记住结果。
 */
public func applyGtdChange(store: AppStore, change: gl.GtdChange): Array<String> {
    let renames = HashMap<String, String>()
    let created = ArrayList<String>()
    for (mutation in change.mutations) {
        match (mutation) {
            case gl.GtdMutation.ToggleDone(id) => store.toggleDone(resolveId(renames, id))
            case gl.GtdMutation.DeleteItems(ids) =>
                let mapped = ArrayList<String>()
                for (id in ids) {
                    mapped.add(resolveId(renames, id))
                }
                store.deleteItems(mapped.toArray())
            case gl.GtdMutation.UpdateItem(id, patch) =>
                let target = resolveId(renames, id)
                let item = toItemPatch(patch)
                match (patch.notes) {
                    case Some(notes) =>
                        item.notes = SetValue<String>.Value(rewriteRenames(notes, renames))
                    case None => ()
                }
                store.updateItem(target, item)
            case gl.GtdMutation.SetStatus(id, status) =>
                store.setStatus(resolveId(renames, id), coreStatusOf(status))
            case gl.GtdMutation.CreateItem(spec) =>
                let input = specToInput(spec)
                let item = store.createItem(input)
                renames[spec.id] = item.id
                created.add(item.id)
            case gl.GtdMutation.Notify(message, tone) =>
                store.notify(rewriteRenames(message, renames), tone: coreToneOf(tone))
        }
    }
    created.toArray()
}

func resolveId(renames: HashMap<String, String>, id: String): String {
    match (renames.get(id)) {
        case Some(value) => value
        case None => id
    }
}

func rewriteRenames(text: String, renames: HashMap<String, String>): String {
    var result = text
    for ((from, to) in renames) {
        result = rewriteId(result, from, to)
    }
    result
}

/**
 * 纯函数层需要「新条目 id」，但 store 自己生成 id，因此这里只提供一个占位 id：
 * 它在 `applyGtdChange` 里被替换为真实 id（见 `rewriteRenames`）。
 * 占位值必须与本工作区现有 id 不同，`seed` 用当前条目数量递增保证唯一。
 */
public func placeholderId(workspace: Workspace, prefix: String): String {
    var index = workspace.items.size
    var candidate = "${prefix}_pending${index}"
    while (itemById(workspace, candidate).isSome()) {
        index += 1
        candidate = "${prefix}_pending${index}"
    }
    candidate
}
