package textura.views.gtd.logic

import std.collection.*

/*
 * 测试专用工具（只在 `cjpm test` 时编译）。
 *
 * 所有用例都以固定「今天」（2026-10-21）为锚点：业务函数不读系统时钟，
 * 日期偏移全部由 `dayAt` / `isoAt` 显式构造，因此断言与跑测机器的时区无关。
 */

let TEST_TODAY: String = "2026-10-21"
let TEST_EPOCH: String = "2026-01-01T00:00:00.000Z"

/** 相对固定今天偏移若干天，返回日期键。 */
func dayAt(offset: Int64): String {
    dayOffset(offset, TEST_TODAY)
}

/** 相对固定今天偏移若干天，返回 Asia/Shanghai 中午的 ISO 时刻。 */
func isoAt(offset: Int64, hour!: Int64 = 12): String {
    dayAt(offset) + "T" + pad2(hour) + ":00:00+08:00"
}

/** 与 TS 测试的 `makeItem` 对应的构造器（默认值刻意固定，保持确定性）。 */
func mkItem(
    id: String,
    kind: GtdKind,
    title: String,
    notes!: String = "",
    parentId!: ?String = None,
    order!: Int64 = 0,
    status!: GtdStatus = GtdStatus.Next,
    tags!: Array<String> = [],
    areaId!: ?String = None,
    createdAt!: String = TEST_EPOCH,
    updatedAt!: String = TEST_EPOCH,
    completedAt!: ?String = None,
    capturedAt!: ?String = None,
    clarified!: Bool = false,
    context!: ?String = None,
    energy!: ?Energy = None,
    waitingFor!: ?String = None,
    twoMinuteCandidate!: Bool = false,
    startDate!: ?String = None,
    dueDate!: ?String = None,
    metric!: ?GtdMetric = None
): GtdItem {
    GtdItem(
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
        updatedAt: updatedAt,
        completedAt: completedAt,
        capturedAt: capturedAt,
        clarified: clarified,
        context: context,
        energy: energy,
        waitingFor: waitingFor,
        twoMinuteCandidate: twoMinuteCandidate,
        startDate: startDate,
        dueDate: dueDate,
        metric: metric
    )
}

func joinIds(items: Array<GtdItem>): String {
    let parts = ArrayList<String>()
    for (item in items) {
        parts.add(item.id)
    }
    String.join(parts.toArray(), delimiter: ",")
}

func joinContexts(groups: Array<ContextGroup>): String {
    let parts = ArrayList<String>()
    for (group in groups) {
        parts.add(group.context)
    }
    String.join(parts.toArray(), delimiter: ",")
}

/** 取某个场景分组的条目 id 串；组不存在返回空串。 */
func contextIds(groups: Array<ContextGroup>, context: String): String {
    for (group in groups) {
        if (group.context == context) {
            return joinIds(group.items)
        }
    }
    ""
}

func joinTags(tags: Array<String>): String {
    String.join(tags, delimiter: ",")
}

func kindText(kind: GtdKind): String {
    match (kind) {
        case GtdKind.Objective => "objective"
        case GtdKind.KeyResult => "keyresult"
        case GtdKind.Project => "project"
        case GtdKind.Action => "action"
        case GtdKind.Sop => "sop"
        case GtdKind.Step => "step"
        case GtdKind.Milestone => "milestone"
        case GtdKind.Note => "note"
        case GtdKind.Reference => "reference"
    }
}

func statusText(status: GtdStatus): String {
    match (status) {
        case GtdStatus.Inbox => "inbox"
        case GtdStatus.Next => "next"
        case GtdStatus.Active => "active"
        case GtdStatus.Waiting => "waiting"
        case GtdStatus.Scheduled => "scheduled"
        case GtdStatus.Someday => "someday"
        case GtdStatus.Done => "done"
        case GtdStatus.Dropped => "dropped"
    }
}

/** 意图序列的可读摘要：`SetStatus(w1:next)`，便于整体断言应用顺序。 */
func mutationSummary(mutations: Array<GtdMutation>): String {
    let parts = ArrayList<String>()
    for (mutation in mutations) {
        parts.add(
            match (mutation) {
                case ToggleDone(id) => "ToggleDone(" + id + ")"
                case DeleteItems(ids) => "DeleteItems(" + String.join(ids, delimiter: "|") + ")"
                case UpdateItem(id, patch) => "UpdateItem(" + id + patchSummary(patch) + ")"
                case SetStatus(id, status) => "SetStatus(" + id + ":" + statusText(status) + ")"
                case CreateItem(spec) =>
                    "CreateItem(" + spec.id + ":" + kindText(spec.kind) + ":" + statusText(spec.status) +
                    ":" + spec.title + ")"
                case Notify(message, tone) => "Notify(" + message + ")"
            }
        )
    }
    String.join(parts.toArray(), delimiter: " -> ")
}

func patchSummary(patch: GtdPatch): String {
    let parts = ArrayList<String>()
    match (patch.title) {
        case Some(value) => parts.add("title=" + value)
        case None => ()
    }
    match (patch.notes) {
        case Some(value) => parts.add("notes=" + value)
        case None => ()
    }
    match (patch.tags) {
        case Some(value) => parts.add("tags=" + joinTags(value))
        case None => ()
    }
    match (patch.areaId) {
        case FieldUpdate<String>.Keep => ()
        case FieldUpdate<String>.Clear => parts.add("areaId=<clear>")
        case FieldUpdate<String>.Set(value) => parts.add("areaId=" + value)
    }
    match (patch.dueDate) {
        case FieldUpdate<String>.Keep => ()
        case FieldUpdate<String>.Clear => parts.add("due=<clear>")
        case FieldUpdate<String>.Set(value) => parts.add("due=" + value)
    }
    match (patch.context) {
        case Some(value) => parts.add("context=" + value)
        case None => ()
    }
    match (patch.clarified) {
        case Some(value) => parts.add("clarified=" + value.toString())
        case None => ()
    }
    match (patch.twoMinuteCandidate) {
        case Some(value) => parts.add("twoMinute=" + value.toString())
        case None => ()
    }
    if (parts.size == 0) {
        return ""
    }
    "{" + String.join(parts.toArray(), delimiter: ";") + "}"
}

/** 取第 index 条意图；越界返回 Notify 占位以便断言失败可读。 */
func mutationAt(mutations: Array<GtdMutation>, index: Int64): GtdMutation {
    mutations[index]
}

/** 批量构造 1k / 5k 规模的行动条目，用于排序/分组规模测试。 */
func bulkActions(count: Int64, context!: String = "电脑"): Array<GtdItem> {
    let items = ArrayList<GtdItem>()
    var index: Int64 = 0
    while (index < count) {
        items.add(
            mkItem(
                "a" + index.toString(),
                GtdKind.Action,
                "行动 " + index.toString(),
                order: index,
                capturedAt: Some(TEST_EPOCH),
                clarified: true,
                context: Some(context)
            )
        )
        index += 1
    }
    items.toArray()
}

/** 取数组从 from 开始的尾部（TS 的 `items.slice(shown)`）。 */
func tailFrom<T>(items: Array<T>, from: Int64): Array<T> {
    let result = ArrayList<T>()
    var index = from
    while (index < items.size) {
        result.add(items[index])
        index += 1
    }
    result.toArray()
}

/** 与 `sortNextActions` 同构的独立判序器，用作规模测试的预期基准。 */
func compareNextActionKeys(left: GtdItem, right: GtdItem): Int64 {
    let leftDue = dateKey(left.dueDate)
    let rightDue = dateKey(right.dueDate)
    if (leftDue.isSome() && rightDue.isSome()) {
        let result = compareStrings(leftDue.getOrThrow(), rightDue.getOrThrow())
        if (result != 0) {
            return result
        }
    } else if (leftDue.isSome()) {
        return -1
    } else if (rightDue.isSome()) {
        return 1
    }
    let leftEnergy = energyRank(left)
    let rightEnergy = energyRank(right)
    if (leftEnergy != rightEnergy) {
        return if (leftEnergy > rightEnergy) {
            -1
        } else {
            1
        }
    }
    let byCreated = compareStrings(left.createdAt, right.createdAt)
    if (byCreated != 0) {
        return byCreated
    }
    if (left.order == right.order) {
        return 0
    }
    if (left.order < right.order) {
        -1
    } else {
        1
    }
}

func isNextActionsSorted(items: Array<GtdItem>): Bool {
    var index: Int64 = 1
    while (index < items.size) {
        if (compareNextActionKeys(items[index - 1], items[index]) > 0) {
            return false
        }
        index += 1
    }
    true
}

/** 交错场景（电脑 / 电话 / 无场景）与日期的规模数据。 */
func bulkMixed(count: Int64): Array<GtdItem> {
    let items = ArrayList<GtdItem>()
    var index: Int64 = 0
    while (index < count) {
        let remainder = index % 3
        let context: ?String = if (remainder == 0) {
            Some("电脑")
        } else if (remainder == 1) {
            Some("电话")
        } else {
            None
        }
        let energy: ?Energy = match (index % 4) {
            case 1 => Some(Energy.High)
            case 2 => Some(Energy.Medium)
            case 3 => Some(Energy.Low)
            case _ => None
        }
        let due: ?String = if (index % 5 == 0) {
            None
        } else {
            Some(dayAt(index % 11 - 5))
        }
        items.add(
            mkItem(
                "m" + index.toString(),
                GtdKind.Action,
                "混合行动 " + index.toString(),
                order: index,
                createdAt: isoAt(0 - index % 9),
                capturedAt: Some(TEST_EPOCH),
                clarified: true,
                context: context,
                energy: energy,
                dueDate: due
            )
        )
        index += 1
    }
    items.toArray()
}
