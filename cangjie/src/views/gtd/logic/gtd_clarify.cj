package textura.views.gtd.logic

import std.collection.*
import std.unicode.*
import std.deriving.*
import std.unicode.*

/*
 * 澄清表单 → 条目补丁 / 新建输入的纯映射。
 *
 * 与 `gtdLogic.ts` 的 ClarifyFormState / ClarifyPatch / NewItemInput 一一对应；
 * 表单状态由 UI 持有，这里只做校验与纯映射，不落库。
 */

/** 澄清类型。 */
@Derive[Equatable]
public enum ClarifyType {
    | Next
    | Project
    | Reference
    | Note
}

/** 澄清表单状态（UI 持有；提交时交给纯函数换算）。 */
public class ClarifyFormState {
    public let clarifyType: ClarifyType
    public let title: String
    public let notes: String
    /** 逗号/空格分隔，允许带 # 前缀。 */
    public let tags: String
    /** '' 表示无领域。 */
    public let areaId: String
    /** 预设场景、''（未设置）或 `__custom__`。 */
    public let context: String
    public let customContext: String
    public let energy: Energy
    /** UI 辅助：仅用于 2 分钟规则提示，模型没有时长字段。 */
    public let estimateMin: ?Int64
    /** `YYYY-MM-DD`；'' 表示清空截止日期。 */
    public let dueDate: String
    public let delegated: Bool
    public let waitingFor: String
    public let someday: Bool
    public let twoMinuteCandidate: Bool

    public init(
        clarifyType!: ClarifyType = ClarifyType.Next,
        title!: String = "",
        notes!: String = "",
        tags!: String = "",
        areaId!: String = "",
        context!: String = "",
        customContext!: String = "",
        energy!: Energy = Energy.Medium,
        estimateMin!: ?Int64 = None,
        dueDate!: String = "",
        delegated!: Bool = false,
        waitingFor!: String = "",
        someday!: Bool = false,
        twoMinuteCandidate!: Bool = false
    ) {
        this.clarifyType = clarifyType
        this.title = title
        this.notes = notes
        this.tags = tags
        this.areaId = areaId
        this.context = context
        this.customContext = customContext
        this.energy = energy
        this.estimateMin = estimateMin
        this.dueDate = dueDate
        this.delegated = delegated
        this.waitingFor = waitingFor
        this.someday = someday
        this.twoMinuteCandidate = twoMinuteCandidate
    }

    /** 复制并替换若干字段（UI 的 `patchForm` / 测试的展开写法）。 */
    public func patched(
        clarifyType!: ?ClarifyType = None,
        title!: ?String = None,
        notes!: ?String = None,
        tags!: ?String = None,
        areaId!: ?String = None,
        context!: ?String = None,
        customContext!: ?String = None,
        energy!: ?Energy = None,
        estimateMin!: ?Int64 = None,
        dueDate!: ?String = None,
        delegated!: ?Bool = None,
        waitingFor!: ?String = None,
        someday!: ?Bool = None,
        twoMinuteCandidate!: ?Bool = None
    ): ClarifyFormState {
        ClarifyFormState(
            clarifyType: match (clarifyType) {
                case Some(value) => value
                case None => this.clarifyType
            },
            title: match (title) {
                case Some(value) => value
                case None => this.title
            },
            notes: match (notes) {
                case Some(value) => value
                case None => this.notes
            },
            tags: match (tags) {
                case Some(value) => value
                case None => this.tags
            },
            areaId: match (areaId) {
                case Some(value) => value
                case None => this.areaId
            },
            context: match (context) {
                case Some(value) => value
                case None => this.context
            },
            customContext: match (customContext) {
                case Some(value) => value
                case None => this.customContext
            },
            energy: match (energy) {
                case Some(value) => value
                case None => this.energy
            },
            estimateMin: match (estimateMin) {
                case Some(value) => Some(value)
                case None => this.estimateMin
            },
            dueDate: match (dueDate) {
                case Some(value) => value
                case None => this.dueDate
            },
            delegated: match (delegated) {
                case Some(value) => value
                case None => this.delegated
            },
            waitingFor: match (waitingFor) {
                case Some(value) => value
                case None => this.waitingFor
            },
            someday: match (someday) {
                case Some(value) => value
                case None => this.someday
            },
            twoMinuteCandidate: match (twoMinuteCandidate) {
                case Some(value) => value
                case None => this.twoMinuteCandidate
            }
        )
    }
}

/** 表单校验错误；三个字段都为空表示通过。 */
public class ClarifyErrors {
    public let title: ?String
    public let waitingFor: ?String
    public let status: ?String

    public init(title!: ?String = None, waitingFor!: ?String = None, status!: ?String = None) {
        this.title = title
        this.waitingFor = waitingFor
        this.status = status
    }

    public func isEmpty(): Bool {
        title.isNone() && waitingFor.isNone() && status.isNone()
    }
}

func isTagSpace(rune: Rune): Bool {
    let codePoint = UInt32(rune)
    if (codePoint == 32u32 || codePoint == 9u32 || codePoint == 10u32 || codePoint == 13u32 || codePoint == 11u32 ||
        codePoint == 12u32) {
        return true
    }
    if (codePoint == 0x3000u32 || codePoint == 0xA0u32 || codePoint == 0x2028u32 || codePoint == 0x2029u32) {
        return true
    }
    false
}

func isTagSeparator(rune: Rune): Bool {
    UInt32(rune) == 44u32 || UInt32(rune) == 0xFF0Cu32 || isTagSpace(rune)
}

func stripLeadingHashes(token: String): String {
    let runes = token.toRuneArray()
    var start: Int64 = 0
    while (start < runes.size && runes[start] == r'#') {
        start += 1
    }
    var end = runes.size
    while (end > start && isTagSpace(runes[end - 1])) {
        end -= 1
    }
    var text = ""
    var index = start
    while (index < end) {
        text += String(runes[index])
        index += 1
    }
    text
}

/** 逗号 / 中文逗号 / 空白分隔，去掉 `#` 前缀，按首次出现去重。 */
public func parseTags(input: String): Array<String> {
    let seen = HashMap<String, Bool>()
    let result = ArrayList<String>()
    var current = ArrayList<Rune>()
    let runes = input.toRuneArray()
    var index: Int64 = 0
    while (index <= runes.size) {
        let atEnd = index == runes.size
        if (atEnd || isTagSeparator(runes[index])) {
            if (current.size > 0) {
                var token = ""
                for (rune in current) {
                    token += String(rune)
                }
                let tag = stripLeadingHashes(token)
                if (!tag.isEmpty() && seen.get(tag).isNone()) {
                    seen[tag] = true
                    result.add(tag)
                }
                current.clear()
            }
        } else {
            current.add(runes[index])
        }
        index += 1
    }
    result.toArray()
}

/** 自定义场景输入与预设场景取值合并。 */
public func resolveFormContext(form: ClarifyFormState): String {
    let raw = if (form.context == "__custom__") {
        form.customContext
    } else {
        form.context
    }
    raw.trim()
}

/** 表单类型 → 目标条目类型。 */
public func desiredKind(types: ClarifyType): GtdKind {
    match (types) {
        case ClarifyType.Project => GtdKind.Project
        case ClarifyType.Reference => GtdKind.Reference
        case ClarifyType.Note => GtdKind.Note
        case ClarifyType.Next => GtdKind.Action
    }
}

/** 参考资料 / 笔记属于归档类。 */
public func isArchiveType(types: ClarifyType): Bool {
    types == ClarifyType.Reference || types == ClarifyType.Note
}

/** 目标状态：归档类 → done；委派 → waiting；someday → someday；其余 → next。 */
public func clarifyTargetStatus(form: ClarifyFormState): GtdStatus {
    if (isArchiveType(form.clarifyType)) {
        return GtdStatus.Done
    }
    if (form.delegated) {
        return GtdStatus.Waiting
    }
    if (form.someday) {
        return GtdStatus.Someday
    }
    GtdStatus.Next
}

public func validateClarifyForm(form: ClarifyFormState): ClarifyErrors {
    var title: ?String = None
    var waitingFor: ?String = None
    var status: ?String = None
    if (form.title.trim().isEmpty()) {
        title = Some("标题不能为空")
    }
    let actsOnStatus = !isArchiveType(form.clarifyType)
    if (form.delegated && actsOnStatus && form.waitingFor.trim().isEmpty()) {
        waitingFor = Some("委派给他人时必须填写等待对象")
    }
    if (form.delegated && form.someday && actsOnStatus) {
        status = Some("「委派等待」与「某天/搁置」只能选一个")
    }
    ClarifyErrors(title: title, waitingFor: waitingFor, status: status)
}

/** 澄清表单换算出的完整补丁（不是部分补丁）。 */
public class ClarifyPatch {
    public let title: String
    public let notes: String
    public let tags: Array<String>
    public let areaId: ?String
    public let dueDate: ?String
    public let clarified: Bool
    public let context: String
    public let energy: Energy
    public let waitingFor: String
    public let twoMinuteCandidate: Bool

    public init(
        title: String,
        notes: String,
        tags: Array<String>,
        areaId: ?String,
        dueDate: ?String,
        clarified: Bool,
        context: String,
        energy: Energy,
        waitingFor: String,
        twoMinuteCandidate: Bool
    ) {
        this.title = title
        this.notes = notes
        this.tags = tags
        this.areaId = areaId
        this.dueDate = dueDate
        this.clarified = clarified
        this.context = context
        this.energy = energy
        this.waitingFor = waitingFor
        this.twoMinuteCandidate = twoMinuteCandidate
    }
}

/** 澄清表单 → 条目补丁（status 由 `clarifyTargetStatus` 单独决定）。 */
public func buildClarifyPatch(form: ClarifyFormState): ClarifyPatch {
    let context = resolveFormContext(form)
    let areaId: ?String = if (form.areaId.isEmpty()) {
        None
    } else {
        Some(form.areaId)
    }
    let dueDate: ?String = if (form.dueDate.isEmpty()) {
        None
    } else {
        Some(form.dueDate)
    }
    let twoMinute = form.twoMinuteCandidate || form.estimateMin == Some(2)
    ClarifyPatch(
        form.title.trim(),
        form.notes,
        parseTags(form.tags),
        areaId,
        dueDate,
        true,
        context,
        form.energy,
        if (form.delegated) {
            form.waitingFor.trim()
        } else {
            ""
        },
        twoMinute
    )
}

/**
 * 需要「新建条目 + 归档原条目」时使用的 createItem 输入。
 *
 * `newId` 由调用方分配（纯函数不生成 id），`nowIso` 是来源缺少 `capturedAt`
 * 时使用的收集时刻。
 */
public func buildClarifyNewItem(
    form: ClarifyFormState,
    source: GtdItem,
    status: GtdStatus,
    newId: String,
    nowIso: String
): GtdNewItem {
    let patch = buildClarifyPatch(form)
    let capturedAt = match (source.capturedAt) {
        case Some(value) => value
        case None => nowIso
    }
    GtdNewItem(
        newId,
        desiredKind(form.clarifyType),
        patch.title,
        notes: patch.notes,
        tags: patch.tags,
        areaId: patch.areaId,
        parentId: None,
        status: status,
        capturedAt: Some(capturedAt),
        clarified: true,
        context: Some(patch.context),
        energy: Some(patch.energy),
        waitingFor: patch.waitingFor,
        twoMinuteCandidate: patch.twoMinuteCandidate,
        startDate: source.startDate,
        dueDate: patch.dueDate
    )
}

/** 新建条目时 status 取表单目标状态。 */
public func buildClarifyNewItem(
    form: ClarifyFormState,
    source: GtdItem,
    newId: String,
    nowIso: String
): GtdNewItem {
    buildClarifyNewItem(form, source, clarifyTargetStatus(form), newId, nowIso)
}

/** 从现有条目初始化表单。 */
public func createClarifyForm(item: GtdItem): ClarifyFormState {
    let rawContext = match (item.context) {
        case Some(value) => value.trim()
        case None => ""
    }
    let isPreset = PRESET_CONTEXTS.contains(rawContext)
    let types = match (item.kind) {
        case GtdKind.Project => ClarifyType.Project
        case GtdKind.Reference => ClarifyType.Reference
        case GtdKind.Note => ClarifyType.Note
        case _ => ClarifyType.Next
    }
    let twoMinuteCandidate = item.twoMinuteCandidate
    ClarifyFormState(
        clarifyType: types,
        title: item.title,
        notes: item.notes,
        tags: String.join(item.tags, delimiter: " "),
        areaId: match (item.areaId) {
            case Some(value) => value
            case None => ""
        },
        context: if (rawContext.isEmpty()) {
            ""
        } else if (isPreset) {
            rawContext
        } else {
            "__custom__"
        },
        customContext: if (!rawContext.isEmpty() && !isPreset) {
            rawContext
        } else {
            ""
        },
        energy: match (item.energy) {
            case Some(value) => value
            case None => Energy.Medium
        },
        estimateMin: if (twoMinuteCandidate) {
            Some(2)
        } else {
            None
        },
        dueDate: match (dateKey(item.dueDate)) {
            case Some(value) => value
            case None => ""
        },
        delegated: item.status == GtdStatus.Waiting,
        waitingFor: match (item.waitingFor) {
            case Some(value) => value
            case None => ""
        },
        someday: item.status == GtdStatus.Someday,
        twoMinuteCandidate: twoMinuteCandidate
    )
}
