package textura.views.gtd.logic

import std.collection.*
import std.deriving.*

/*
 * GTD 行内动作 → 「变更意图」。
 *
 * 与 `gtdMutations.ts` 一一对应，但纯函数化：这里不持有 store、不生成 id、
 * 不读时钟，只返回一串 `GtdMutation` 意图，由 UI / store 层顺序应用到
 * workspace。需要新建条目时，id 与「现在」由调用方注入（改造自 TS 的
 * `store.createItem` / `nowIso`），因此同一输入永远得到同一意图序列。
 */

/** 三态字段更新：保持 / 清空 / 设值。用来表达 `areaId`、`gantt.end` 这类可空字段。 */
public enum FieldUpdate<T> {
    | Keep
    | Clear
    | Set(T)
}

/** 条目补丁；未设置的字段表示「保持不变」。 */
public class GtdPatch {
    public let title: ?String
    public let notes: ?String
    public let tags: ?Array<String>
    public let areaId: FieldUpdate<String>
    public let dueDate: FieldUpdate<String>
    public let context: ?String
    public let energy: ?Energy
    public let waitingFor: ?String
    public let clarified: ?Bool
    public let twoMinuteCandidate: ?Bool

    public init(
        title!: ?String = None,
        notes!: ?String = None,
        tags!: ?Array<String> = None,
        areaId!: FieldUpdate<String> = FieldUpdate<String>.Keep,
        dueDate!: FieldUpdate<String> = FieldUpdate<String>.Keep,
        context!: ?String = None,
        energy!: ?Energy = None,
        waitingFor!: ?String = None,
        clarified!: ?Bool = None,
        twoMinuteCandidate!: ?Bool = None
    ) {
        this.title = title
        this.notes = notes
        this.tags = tags
        this.areaId = areaId
        this.dueDate = dueDate
        this.context = context
        this.energy = energy
        this.waitingFor = waitingFor
        this.clarified = clarified
        this.twoMinuteCandidate = twoMinuteCandidate
    }
}

/** `createItem` 的输入；`id` 由调用方分配，保证纯函数可重放。 */
public class GtdNewItem {
    public let id: String
    public let kind: GtdKind
    public let title: String
    public let notes: String
    public let tags: Array<String>
    public let areaId: ?String
    public let parentId: ?String
    public let status: GtdStatus
    public let capturedAt: ?String
    public let clarified: Bool
    public let context: ?String
    public let energy: ?Energy
    public let waitingFor: String
    public let twoMinuteCandidate: Bool
    public let startDate: ?String
    public let dueDate: ?String

    public init(
        id: String,
        kind: GtdKind,
        title: String,
        notes!: String = "",
        tags!: Array<String> = [],
        areaId!: ?String = None,
        parentId!: ?String = None,
        status!: GtdStatus = GtdStatus.Inbox,
        capturedAt!: ?String = None,
        clarified!: Bool = false,
        context!: ?String = None,
        energy!: ?Energy = None,
        waitingFor!: String = "",
        twoMinuteCandidate!: Bool = false,
        startDate!: ?String = None,
        dueDate!: ?String = None
    ) {
        this.id = id
        this.kind = kind
        this.title = title
        this.notes = notes
        this.tags = tags
        this.areaId = areaId
        this.parentId = parentId
        this.status = status
        this.capturedAt = capturedAt
        this.clarified = clarified
        this.context = context
        this.energy = energy
        this.waitingFor = waitingFor
        this.twoMinuteCandidate = twoMinuteCandidate
        this.startDate = startDate
        this.dueDate = dueDate
    }
}

/** 提示语气（对应 store.notify 的 kind）。 */
@Derive[Equatable]
public enum NoticeTone {
    | Info
    | Success
    | Error
}

/**
 * 一条可应用的变更意图。
 *
 * `ToggleDone` / `DeleteItems` / `UpdateItem` / `SetStatus` / `CreateItem`
 * 直接映射 store 的公开动作；`Notify` 是提示文案。应用顺序即数组顺序，
 * 与 TS 里连续调用 store 的顺序一致。
 */
public enum GtdMutation {
    | ToggleDone(String)
    | DeleteItems(Array<String>)
    | UpdateItem(String, GtdPatch)
    | SetStatus(String, GtdStatus)
    | CreateItem(GtdNewItem)
    | Notify(String, NoticeTone)
}

/** 一次 GTD 动作的完整结果：意图序列 + 应聚焦的条目 id。 */
public class GtdChange {
    public let mutations: Array<GtdMutation>
    /** TS 版动作的返回值（被新建或被修改的条目）；没有则 `None`。 */
    public let resultId: ?String

    public init(mutations: Array<GtdMutation>, resultId!: ?String = None) {
        this.mutations = mutations
        this.resultId = resultId
    }

    /** 本次动作是否新建了条目。 */
    public func createdSpec(): ?GtdNewItem {
        for (mutation in mutations) {
            match (mutation) {
                case CreateItem(spec) => return Some(spec)
                case _ => ()
            }
        }
        None
    }
}

func clarifiedPatch(): GtdPatch {
    GtdPatch(clarified: Some(true))
}

func notesPatch(notes: String): GtdPatch {
    GtdPatch(notes: Some(notes))
}

/** TS 里 `{ notes, gtd: { clarified: true } }` 是一次 updateItem，这里也合成一条意图。 */
func notesAndClarifiedPatch(notes: String): GtdPatch {
    GtdPatch(notes: Some(notes), clarified: Some(true))
}

func patchFromClarify(patch: ClarifyPatch): GtdPatch {
    GtdPatch(
        title: Some(patch.title),
        notes: Some(patch.notes),
        tags: Some(patch.tags),
        areaId: match (patch.areaId) {
            case Some(value) => FieldUpdate<String>.Set(value)
            case None => FieldUpdate<String>.Clear
        },
        dueDate: match (patch.dueDate) {
            case Some(value) => FieldUpdate<String>.Set(value)
            case None => FieldUpdate<String>.Clear
        },
        context: Some(patch.context),
        energy: Some(patch.energy),
        waitingFor: Some(patch.waitingFor),
        clarified: Some(patch.clarified),
        twoMinuteCandidate: Some(patch.twoMinuteCandidate)
    )
}

func single(mutation: GtdMutation): Array<GtdMutation> {
    let buffer = ArrayList<GtdMutation>()
    buffer.add(mutation)
    buffer.toArray()
}

/** 2 分钟规则：直接完成并给出提示。 */
public func completeInboxItem(item: GtdItem): GtdChange {
    let mutations = ArrayList<GtdMutation>()
    mutations.add(GtdMutation.ToggleDone(item.id))
    mutations.add(GtdMutation.Notify("已完成「" + item.title + "」，2 分钟规则处理完毕", NoticeTone.Success))
    GtdChange(mutations.toArray())
}

/** 收件箱删除：即时删除，提示可撤销（Ctrl/Cmd+Z）。 */
public func deleteInboxItem(item: GtdItem): GtdChange {
    let mutations = ArrayList<GtdMutation>()
    mutations.add(GtdMutation.DeleteItems([item.id]))
    mutations.add(GtdMutation.Notify("已删除「" + item.title + "」，按 Ctrl/Cmd+Z 可撤销", NoticeTone.Info))
    GtdChange(mutations.toArray())
}

/**
 * 把条目放入下一步。
 *
 * action/project 直接改状态；note/reference 无法就地改 kind，
 * 因此新建 action 并把原条目归档（notes 记录来源）。
 *
 * 返回 `resultId`：就地改状态时是原条目 id，新建时是新条目 id
 * （对应 TS 返回 `item` / `created`）。
 */
public func promoteItemToNext(item: GtdItem, newId: String, nowIso: String): GtdChange {
    let mutations = ArrayList<GtdMutation>()
    if (item.kind == GtdKind.Action || item.kind == GtdKind.Project) {
        mutations.add(GtdMutation.UpdateItem(item.id, clarifiedPatch()))
        mutations.add(GtdMutation.SetStatus(item.id, GtdStatus.Next))
        mutations.add(GtdMutation.Notify("已放入下一步「" + item.title + "」", NoticeTone.Success))
        return GtdChange(mutations.toArray(), resultId: Some(item.id))
    }
    let capturedAt = match (item.capturedAt) {
        case Some(value) => value
        case None => nowIso
    }
    let spec = GtdNewItem(
        newId,
        GtdKind.Action,
        item.title,
        notes: item.notes,
        tags: item.tags,
        areaId: item.areaId,
        parentId: None,
        status: GtdStatus.Next,
        capturedAt: Some(capturedAt),
        clarified: true,
        context: item.context,
        energy: item.energy,
        waitingFor: "",
        twoMinuteCandidate: false,
        startDate: None,
        dueDate: None
    )
    mutations.add(GtdMutation.CreateItem(spec))
    mutations.add(
        GtdMutation.UpdateItem(
            item.id,
            notesAndClarifiedPatch(appendTimestampedNote(item.notes, "澄清：已转为下一步行动（" + newId + "）", nowIso))
        )
    )
    mutations.add(GtdMutation.SetStatus(item.id, GtdStatus.Done))
    mutations.add(GtdMutation.Notify("已转为下一步「" + item.title + "」", NoticeTone.Success))
    GtdChange(mutations.toArray(), resultId: Some(newId))
}

/** 等待中的「催办」：在 notes 追加时间戳并提示。 */
public func nudgeWaitingItem(item: GtdItem, at: String): GtdChange {
    let target = match (nonEmpty(item.waitingFor)) {
        case Some(value) => value
        case None => "对方"
    }
    let mutations = ArrayList<GtdMutation>()
    mutations.add(
        GtdMutation.UpdateItem(
            item.id,
            notesPatch(appendTimestampedNote(item.notes, "催办：已提醒 " + target + "，等待回复。", at))
        )
    )
    mutations.add(GtdMutation.Notify("已记录催办：" + item.title, NoticeTone.Success))
    GtdChange(mutations.toArray())
}

/** 停滞项目的一键补位：新建一个 next 子动作。 */
public func createNextActionForProject(project: GtdItem, newId: String, nowIso: String): GtdChange {
    let spec = GtdNewItem(
        newId,
        GtdKind.Action,
        "推进：" + project.title,
        notes: "",
        tags: project.tags,
        areaId: project.areaId,
        parentId: Some(project.id),
        status: GtdStatus.Next,
        capturedAt: Some(nowIso),
        clarified: true,
        context: None,
        energy: None,
        waitingFor: "",
        twoMinuteCandidate: false,
        startDate: None,
        dueDate: None
    )
    let mutations = ArrayList<GtdMutation>()
    mutations.add(GtdMutation.CreateItem(spec))
    mutations.add(GtdMutation.Notify("已为「" + project.title + "」补一个下一步动作", NoticeTone.Success))
    GtdChange(mutations.toArray(), resultId: Some(newId))
}

/** 某天 → 下一步：action/project 直接激活；note/reference 走「新建 + 归档」。 */
public func activateSomedayItem(item: GtdItem, newId: String, nowIso: String): GtdChange {
    promoteItemToNext(item, newId, nowIso)
}

/**
 * 澄清提交（`ClarifyDialog.submit` 的纯函数化），四个分支与 TS 一致：
 * 1. 归档类（参考资料/笔记）：就地打补丁 + done
 * 2. 目标 action 且原条目不是 action/project：新建 action，原条目归档
 * 3. 目标 project 且原条目不是 project：新建 project，原条目归档
 * 4. 其余：就地打补丁 + 目标状态
 *
 * 调用前必须先跑 `validateClarifyForm`（TS 在组件里提前 return）。
 */
public func clarifyItem(item: GtdItem, form: ClarifyFormState, newId: String, nowIso: String): GtdChange {
    let targetStatus = clarifyTargetStatus(form)
    let patch = buildClarifyPatch(form)
    let desired = desiredKind(form.clarifyType)
    let mutations = ArrayList<GtdMutation>()
    if (isArchiveType(form.clarifyType)) {
        let label = if (form.clarifyType == ClarifyType.Reference) {
            "参考资料"
        } else {
            "笔记"
        }
        let archivePatch = GtdPatch(
            title: Some(patch.title),
            notes: Some(appendTimestampedNote(patch.notes, "澄清：归档为" + label + "。", nowIso)),
            tags: Some(patch.tags),
            areaId: match (patch.areaId) {
                case Some(value) => FieldUpdate<String>.Set(value)
                case None => FieldUpdate<String>.Clear
            },
            dueDate: match (patch.dueDate) {
                case Some(value) => FieldUpdate<String>.Set(value)
                case None => FieldUpdate<String>.Clear
            },
            context: Some(patch.context),
            energy: Some(patch.energy),
            waitingFor: Some(patch.waitingFor),
            clarified: Some(true),
            twoMinuteCandidate: Some(patch.twoMinuteCandidate)
        )
        mutations.add(GtdMutation.UpdateItem(item.id, archivePatch))
        mutations.add(GtdMutation.SetStatus(item.id, targetStatus))
        mutations.add(GtdMutation.Notify("已归档为" + label + "「" + patch.title + "」", NoticeTone.Success))
        return GtdChange(mutations.toArray(), resultId: Some(item.id))
    }
    let needsNewAction = desired == GtdKind.Action && item.kind != GtdKind.Action && item.kind != GtdKind.Project
    let needsNewProject = desired == GtdKind.Project && item.kind != GtdKind.Project
    if (needsNewAction || needsNewProject) {
        let spec = buildClarifyNewItem(form, item, targetStatus, newId, nowIso)
        let message = if (needsNewProject) {
            "澄清：已升级为项目（" + newId + "）"
        } else {
            "澄清：已转为下一步行动（" + newId + "）"
        }
        let notifyText = if (needsNewProject) {
            "已升级为项目「" + spec.title + "」"
        } else {
            "已转为下一步「" + spec.title + "」"
        }
        mutations.add(GtdMutation.CreateItem(spec))
        mutations.add(
            GtdMutation.UpdateItem(
                item.id,
                notesAndClarifiedPatch(appendTimestampedNote(item.notes, message, nowIso))
            )
        )
        mutations.add(GtdMutation.SetStatus(item.id, GtdStatus.Done))
        mutations.add(GtdMutation.Notify(notifyText, NoticeTone.Success))
        return GtdChange(mutations.toArray(), resultId: Some(newId))
    }
    mutations.add(GtdMutation.UpdateItem(item.id, patchFromClarify(patch)))
    mutations.add(GtdMutation.SetStatus(item.id, targetStatus))
    mutations.add(GtdMutation.Notify("已澄清「" + patch.title + "」", NoticeTone.Success))
    GtdChange(mutations.toArray(), resultId: Some(item.id))
}

/** 记录一条纯提示（例如表单校验失败后回传错误文案）。 */
public func notifyOnly(message: String, tone: NoticeTone): GtdChange {
    GtdChange(single(GtdMutation.Notify(message, tone)))
}
