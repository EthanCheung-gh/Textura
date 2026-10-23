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

/** 打开编辑浮层：`target` 是条目 / 连线 id，`entry` 只给检查项用。 */
func openSopPrompt(state: SopViewState, kind: SopPromptKind, target: String, value: String,
    entry!: String = ""): Unit {
    state.promptKind.value = sopPromptKindId(kind)
    state.promptTarget.value = target
    state.promptEntry.value = entry
    state.promptText.value = value
    state.promptError.value = ""
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
        case SopPromptKind.SopTitle => SopPromptCopy("编辑流程名称", "名称", "例如：客户投诉处理", "名称会显示在左侧流程列表。")
        case SopPromptKind.SopNotes => SopPromptCopy("编辑描述", "描述", "这个流程解决什么问题、适用范围…",
            "支持多行；Ctrl+Enter 保存，Esc 取消。可以留空。", multiline: true)
        case SopPromptKind.SopOwner => SopPromptCopy("编辑默认负责人", "默认负责人", "未指定", "留空表示未指定。")
        case SopPromptKind.NodeTitle => SopPromptCopy("编辑步骤标题", "标题", "用一个动词开头", "标题会显示在画布节点上。")
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

/** 页面浮层入口（`sop.cj` 的 `render` 在页面之后调用）。 */
func sopPromptDialog(theme: Theme, store: AppStore, state: SopViewState): Unit {
    if (!state.promptOpen.value) {
        return
    }
    let kind = parseSopPromptKind(state.promptKind.value)
    let copy = sopPromptCopy(kind)
    Ui.prompt(theme, state.promptText, state.promptOpen, {=> closeSopPrompt(state)}, title: copy.title,
        key: SOP_PROMPT_INPUT, label: copy.label, placeholder: copy.placeholder, hint: copy.hint,
        multiline: copy.multiline, error: state.promptError.value, focus: state.promptFocus) {value =>
        commitSopPrompt(store, state, value)
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
                    case Some(minutes) =>
                        patch.durationMin = SetValue<?Int64>.Value(Some(minutes))
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
        case SopPromptKind.EdgeLabel =>
            store.updateEdge(target, label: value)
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
