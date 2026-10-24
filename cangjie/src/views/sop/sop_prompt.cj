package textura.views.sop

import std.collection.ArrayList
import std.convert.*
import std.unicode.*
import cui.*
import textura.core.data.*
import textura.ui.*

/*
 * 检查器里的文本编辑：统一走 `textura.ui.Ui.prompt`。
 *
 * 检查器是画布自绘的（`sop_inspector.cj` 用 `paintInputBox` 画出「输入框」的样子），
 * 里面的控件在 `layout`/`draw` 阶段才出现，而 CUI 只在 build 阶段登记焦点。
 * 行内 `TextField` 因此点得进去却拿不到焦点（光标与输入法都不出现）；
 * 改成构建期声明的编辑浮层，既保留逐像素外观，又让输入框是真正的控件
 * （`docs/DEVICE-NOTES.md` §16）。
 */

/** 浮层输入框的焦点 id。 */
let SOP_PROMPT_INPUT: String = "sop-prompt-input";

/** 字段种类：画布上的哪一个「输入框」被点了。 */
enum SopPromptKind {
    | SopTitle
    | SopNotes
    | SopOwner
    | NodeTitle
    | NodeNotes
    | NodeOwner
    | NodeDuration
    | CheckText
    | EdgeLabel
}

func sopPromptKindId(kind: SopPromptKind): String {
    match (kind) {
        case SopPromptKind.SopTitle => "sop-title"
        case SopPromptKind.SopNotes => "sop-notes"
        case SopPromptKind.SopOwner => "sop-owner"
        case SopPromptKind.NodeTitle => "node-title"
        case SopPromptKind.NodeNotes => "node-notes"
        case SopPromptKind.NodeOwner => "node-owner"
        case SopPromptKind.NodeDuration => "node-duration"
        case SopPromptKind.CheckText => "check-text"
        case SopPromptKind.EdgeLabel => "edge-label"
    }
}

func parseSopPromptKind(id: String): SopPromptKind {
    match (id) {
        case "sop-title" => SopPromptKind.SopTitle
        case "sop-notes" => SopPromptKind.SopNotes
        case "sop-owner" => SopPromptKind.SopOwner
        case "node-notes" => SopPromptKind.NodeNotes
        case "node-owner" => SopPromptKind.NodeOwner
        case "node-duration" => SopPromptKind.NodeDuration
        case "check-text" => SopPromptKind.CheckText
        case "edge-label" => SopPromptKind.EdgeLabel
        case _ => SopPromptKind.NodeTitle
    }
}

/**
 * 这一帧这个字段是否正被原位编辑器接管。
 *
 * 画布上那些「输入框」是画出来的，编辑器是压在上面的真控件；两边同时画同一个字段就会看到
 * 「两层文字 + 双边框」，叠加的控件还会比盒子高出一截——用户说的「下方又弹出一个一样的框」。
 * 所以编辑态下画布不再画该字段的文本与边框（背景留着，位置不变），由控件自己画。
 */
func sopFieldEditing(state: SopViewState, kind: SopPromptKind): Bool {
    state.promptOpen.value && state.promptKind.value == sopPromptKindId(kind)
}

/**
 * 打开原位编辑器：`target` 是条目 / 连线 id，`rect` 是被点字段的绝对矩形（检查器 layout 记录，
 * 见 `inspectorRects`），`entry` 只给检查项用。
 */
func openSopPrompt(state: SopViewState, kind: SopPromptKind, target: String, value: String, rect: Rect,
    entry!: String = ""): Unit {
    state.promptKind.value = sopPromptKindId(kind)
    state.promptTarget.value = target
    state.promptEntry.value = entry
    state.promptText.value = value
    state.promptError.value = ""
    state.promptAnchor.request(rect)
    state.promptOpen.value = true
    state.promptFocus.request(SOP_PROMPT_INPUT)
}

func closeSopPrompt(state: SopViewState): Unit {
    state.promptOpen.value = false
    state.promptError.value = ""
    state.promptFocus.release()
}

private class SopPromptCopy {
    let title: String
    let label: String
    let placeholder: String
    let hint: String
    let multiline: Bool

    init(title: String, label: String, placeholder: String, hint: String, multiline!: Bool = false) {
        this.title = title
        this.label = label
        this.placeholder = placeholder
        this.hint = hint
        this.multiline = multiline
    }
}

/**
 * 浮层文案。SOP 级与步骤级的备注字段统一叫「描述」（产品术语统一；Web 原版两级
 * 用了两个不同的词，本次按用户要求合并）。
 */
private func sopPromptCopy(kind: SopPromptKind): SopPromptCopy {
    match (kind) {
        case SopPromptKind.SopTitle => SopPromptCopy("编辑流程名称", "名称", "例如：客户投诉处理",
            "名称会显示在左侧流程列表。")
        case SopPromptKind.SopNotes => SopPromptCopy("编辑描述", "描述", "这个流程解决什么问题、适用范围…",
            "支持多行；Ctrl+Enter 保存，Esc 取消。可以留空。", multiline: true)
        case SopPromptKind.SopOwner => SopPromptCopy("编辑默认负责人", "默认负责人", "未指定", "留空表示未指定。")
        case SopPromptKind.NodeTitle => SopPromptCopy("编辑步骤标题", "标题", "用一个动词开头",
            "标题会显示在画布节点上。")
        case SopPromptKind.NodeNotes => SopPromptCopy("编辑描述", "描述", "这一步要做什么、注意什么…",
            "支持多行；Ctrl+Enter 保存，Esc 取消。可以留空。", multiline: true)
        case SopPromptKind.NodeOwner => SopPromptCopy("编辑负责人", "负责人", "谁来做", "留空表示未指派。")
        case SopPromptKind.NodeDuration => SopPromptCopy("编辑预计耗时", "预计耗时（分钟）", "5",
            "只接受整数分钟；留空表示未估算。")
        case SopPromptKind.CheckText => SopPromptCopy("编辑检查项", "检查项", "这条检查要确认什么",
            "检查项会出现在节点进度与运行条里。")
        case SopPromptKind.EdgeLabel => SopPromptCopy("编辑分支文案", "标签", "例如：是 / 否 / 补充",
            "分支文案显示在连线上。")
    }
}

/**
 * 原位编辑器（`sop.cj` 的 `render` 在页面之后调用，仍在 build 阶段）。
 *
 * 检查器画上去的那些「输入框」现在就在原地编辑：编辑器按点击时的字段矩形定位，宽高等于字段本身，
 * Enter 提交、Esc 取消、点外部提交（与 Web 一致），不再出现第二个窗口。
 * 校验失败时 `commitSopPrompt` 只写 `promptError` 而不关闭，错误行显示在字段下方。
 */
func sopPromptDialog(theme: Theme, store: AppStore, state: SopViewState): Unit {
    if (!state.promptOpen.value) {
        return
    }
    let kind = parseSopPromptKind(state.promptKind.value)
    let copy = sopPromptCopy(kind)
    Ui.inlineEditor(theme, state.promptText, state.promptAnchor, true, key: SOP_PROMPT_INPUT,
        multiline: copy.multiline, placeholder: copy.placeholder, error: state.promptError.value,
        focus: state.promptFocus, onCommit: {value => commitSopPrompt(store, state, value)},
        onCancel: {=> closeSopPrompt(state)})
}

/**
 * 编辑中的字段每帧把矩形写回锚点（滚动检查器、换选中项、窗口 resize 时编辑器跟着字段走）。
 *
 * 在页面 `layout` 里调用：页面布局先于编辑器所在的 `Portal`，所以同一帧里编辑器就用上新矩形。
 * 幂等：矩形没变时 `InlineAnchor` 不递增修订号，不会造成重建风暴。
 */
func trackSopPrompt(ctx: UiContext, view: SopFrame): Unit {
    let state = view.state
    if (!state.promptOpen.value) {
        return
    }
    let kind = parseSopPromptKind(state.promptKind.value)
    let rects = inspectorRects(ctx, view, scroll: clampInspectorScroll(ctx, view))
    match (sopPromptFieldRect(rects, kind, state.promptEntry.value)) {
        case Some(rect) => state.promptAnchor.update(rect)
        case None => ()
    }
}

/** 「字段种类 → 本帧矩形」的唯一映射：检查器画哪个盒子，编辑器就停在哪个盒子上。 */
func sopPromptFieldRect(rects: SopInspRects, kind: SopPromptKind, entryId: String): ?Rect {
    match (kind) {
        case SopPromptKind.SopTitle => Some(rects.nameInput)
        case SopPromptKind.SopNotes => Some(rects.notesArea)
        case SopPromptKind.SopOwner => Some(rects.ownerInput)
        case SopPromptKind.NodeTitle => Some(rects.titleInput)
        case SopPromptKind.NodeNotes => Some(rects.nodeNotesArea)
        case SopPromptKind.NodeOwner => Some(rects.ownerInput)
        case SopPromptKind.NodeDuration => Some(rects.durationInput)
        case SopPromptKind.CheckText =>
            for (row in rects.checkRows) {
                if (row.entryId == entryId) {
                    return Some(row.label)
                }
            }
            None
        case SopPromptKind.EdgeLabel => Some(rects.labelInput)
    }
}

/** 写回 store（Esc 不会走到这里，因此取消不改数据）。 */
func commitSopPrompt(store: AppStore, state: SopViewState, raw: String): Unit {
    let kind = parseSopPromptKind(state.promptKind.value)
    let target = state.promptTarget.value
    let value = raw.trim()
    match (kind) {
        case SopPromptKind.SopTitle =>
            if (value.isEmpty()) {
                state.promptError.value = "名称不能为空。"
                return
            }
            store.updateItem(target, ItemPatch().withTitle(value))
        case SopPromptKind.SopOwner =>
            let patch = SopPatch()
            patch.owner = SetValue<?String>.Value(if (value.isEmpty()) {
                None
            } else {
                Some(value)
            })
            store.updateItem(target, ItemPatch().withSop(patch))
        case SopPromptKind.NodeTitle =>
            if (value.isEmpty()) {
                state.promptError.value = "标题不能为空。"
                return
            }
            store.updateItem(target, ItemPatch().withTitle(value))
        case SopPromptKind.NodeNotes | SopPromptKind.SopNotes =>
            // 描述允许为空；多行文本按原样保存（不 trim，保留用户的分行与缩进）。
            store.updateItem(target, ItemPatch().withNotes(raw))
        case SopPromptKind.NodeOwner =>
            let patch = SopPatch()
            patch.owner = SetValue<?String>.Value(if (value.isEmpty()) {
                None
            } else {
                Some(value)
            })
            store.updateItem(target, ItemPatch().withSop(patch))
        case SopPromptKind.NodeDuration =>
            let patch = SopPatch()
            if (value.isEmpty()) {
                patch.durationMin = SetValue<?Int64>.Value(Option<Int64>.None)
            } else {
                match (parseMinutes(value)) {
                    case Some(minutes) => patch.durationMin = SetValue<?Int64>.Value(Some(minutes))
                    case None =>
                        state.promptError.value = "请填写整数分钟，例如 15。"
                        return
                }
            }
            store.updateItem(target, ItemPatch().withSop(patch))
        case SopPromptKind.CheckText =>
            if (value.isEmpty()) {
                state.promptError.value = "检查项不能为空。"
                return
            }
            commitChecklistText(store, target, state.promptEntry.value, value)
        case SopPromptKind.EdgeLabel => store.updateEdge(target, label: value)
    }
    state.touch()
    closeSopPrompt(state)
}

/** `25` / `25分钟` / ` 25 ` → 25；其余返回 None。 */
private func parseMinutes(text: String): ?Int64 {
    var digits = ""
    for (byte in text) {
        if (byte >= UInt8(48) && byte <= UInt8(57)) {
            digits += String.fromUtf8([byte])
        } else if (byte >= UInt8(65) && byte <= UInt8(122)) {
            break
        }
    }
    if (digits.isEmpty()) {
        return None
    }
    try {
        Some(Int64.parse(digits))
    } catch (_: Exception) {
        None
    }
}

private func commitChecklistText(store: AppStore, itemId: String, entryId: String, text: String): Unit {
    let workspace = store.state.value()
    let item = match (itemById(workspace, itemId)) {
        case Some(value) => value
        case None => return
    }
    let next = ArrayList<ChecklistEntry>()
    for (entry in checklistOf(item)) {
        if (entry.id == entryId) {
            next.add(ChecklistEntry(entry.id, text, entry.done))
        } else {
            next.add(entry)
        }
    }
    let patch = SopPatch()
    patch.checklist = SetValue<Array<ChecklistEntry>>.Value(next.toArray())
    store.updateItem(itemId, ItemPatch().withSop(patch))
}
