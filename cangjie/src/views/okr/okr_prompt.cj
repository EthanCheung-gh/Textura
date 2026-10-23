package textura.views.okr

import std.unicode.*
import cui.*
import textura.core.data.{ItemPatch, OkrPatch, SetValue, ViewContext}
import textura.ui.*
import textura.views.okr.logic.{EMPTY_METRIC, METRIC_FIELDS, MetricDraft, MetricField, metricFieldText, metricToDraft,
    pendingMetricPatch}

/*
 * 卡片画布上的文本编辑：统一走 `textura.ui.Ui.prompt`。
 *
 * 为什么不是行内输入框：`OkrPage` 是一块自绘画布，它的布局（以及一切子控件）在 `layout` 阶段
 * 才发生，而 CUI 只在 **build 阶段**把控件登记进焦点图。行内 `TextField` 因此永远拿不到焦点，
 * 点击后下一帧焦点被清空 —— 既没有光标也打不进字（`docs/DEVICE-NOTES.md` §16）。
 * 把编辑动作换成构建期声明的模态浮层，画布保持逐像素不变，输入框则是一个正常的、可聚焦的控件。
 */

/** Prompt 里那个输入框的焦点 id（一次只有一个浮层，所以是常量）。 */
let OKR_PROMPT_INPUT: String = "okr-prompt-input";

/** 目标 / KR 标题。 */
func openOkrTitlePrompt(ui: OkrUiState, id: String, title: String): Unit {
    armPrompt(ui, "title", id, "", title)
}

/** 指标数值（起点 / 当前 / 目标 / 单位）。 */
func openOkrMetricPrompt(ui: OkrUiState, krId: String, field: MetricField, value: String): Unit {
    armPrompt(ui, "metric", krId, metricFieldText(field), value)
}

/** 负责人。 */
func openOkrOwnerPrompt(ui: OkrUiState, krId: String, owner: String): Unit {
    armPrompt(ui, "owner", krId, "", owner)
}

/** 新增关键结果。 */
func openOkrAddKrPrompt(ui: OkrUiState, objectiveId: String): Unit {
    armPrompt(ui, "addkr", objectiveId, "", "")
}

private func armPrompt(ui: OkrUiState, kind: String, target: String, field: String, value: String): Unit {
    ui.promptKind.value = kind
    ui.promptTarget.value = target
    ui.promptField.value = field
    ui.promptText.value = value
    ui.promptError.value = ""
    ui.promptOpen.value = true
    ui.promptFocus.request(OKR_PROMPT_INPUT)
}

func closeOkrPrompt(ui: OkrUiState): Unit {
    ui.promptOpen.value = false
    ui.promptError.value = ""
    ui.promptFocus.release()
}

/** Prompt 文案：标题 / 字段名 / 占位提示 / 说明。 */
class OkrPromptCopy {
    let title: String
    let label: String
    let placeholder: String
    let hint: String

    init(title: String, label: String, placeholder: String, hint: String) {
        this.title = title
        this.label = label
        this.placeholder = placeholder
        this.hint = hint
    }
}

private func promptCopy(ui: OkrUiState, objectiveTitle: String): OkrPromptCopy {
    let kind = ui.promptKind.value
    if (kind == "metric") {
        return match (okrFieldLabel(ui.promptField.value)) {
            case Some(label) => OkrPromptCopy("编辑指标", label, "例如 42", "数字会换算成 KR 进度；单位可以留空。")
            case None => OkrPromptCopy("编辑指标", "数值", "例如 42", "")
        }
    }
    if (kind == "owner") {
        return OkrPromptCopy("指派负责人", "负责人", "未指派", "留空表示未指派。")
    }
    if (kind == "addkr") {
        return OkrPromptCopy("新增关键结果", "关键结果", "例如：把首周留存提升到 45%",
            "为「${objectiveTitle}」补充一个可量化的结果。")
    }
    OkrPromptCopy("编辑标题", "标题", "一句话说明这条要达成什么", "标题会立即写回工作区。")
}

private func okrFieldLabel(field: String): ?String {
    for (candidate in METRIC_FIELDS) {
        if (metricFieldText(candidate) == field) {
            return Some(okrMetricLabel(candidate))
        }
    }
    None
}

private func okrMetricLabel(field: MetricField): String {
    match (field) {
        case MetricField.Start => "起点"
        case MetricField.Current => "当前"
        case MetricField.Target => "目标"
        case MetricField.UnitField => "单位"
    }
}

/** 页面浮层入口：把 `ui.prompt*` 映射成 `Ui.prompt`。 */
func okrPromptDialog(ctx: ViewContext, ui: OkrUiState, page: OkrPage): Unit {
    if (!ui.promptOpen.value) {
        return
    }
    let target = ui.promptTarget.value
    var objectiveTitle = ""
    var found = false
    for (candidate in page.data.entries) {
        if (candidate.item.id == target) {
            objectiveTitle = candidate.item.title
            found = true
        }
        for (kr in candidate.krs) {
            if (kr.item.id == target) {
                objectiveTitle = candidate.item.title
                found = true
            }
        }
    }
    let _ = found
    let copy = promptCopy(ui, objectiveTitle)
    let kind = ui.promptKind.value
    Ui.prompt(page.theme, ui.promptText, ui.promptOpen, {=> closeOkrPrompt(ui)}, title: copy.title,
        key: OKR_PROMPT_INPUT, label: copy.label, placeholder: copy.placeholder, hint: copy.hint,
        error: ui.promptError.value, multiline: false, confirmLabel: if (kind == "addkr") {
            "创建"
        } else {
            "保存"
        }, focus: ui.promptFocus) {value => commitOkrPrompt(ctx, ui, page, value)}
}

/** 提交：写回 `ctx.store`，随后关闭浮层（Esc 取消不改数据）。 */
func commitOkrPrompt(ctx: ViewContext, ui: OkrUiState, page: OkrPage, raw: String): Unit {
    let kind = ui.promptKind.value
    let target = ui.promptTarget.value
    let value = raw.trim()
    let isUnit = ui.promptField.value == metricFieldText(MetricField.UnitField)
    if (value.isEmpty() && !isUnit) {
        ui.promptError.value = "不能为空。"
        return
    }
    if (kind == "title") {
        if (value.isEmpty()) {
            ui.promptError.value = "标题不能为空。"
            return
        }
        ctx.store.updateItem(target, ItemPatch().withTitle(value))
        closeOkrPrompt(ui)
        return
    }
    if (kind == "owner") {
        let patch = ItemPatch()
        let okr = OkrPatch()
        let ownerValue: ?String = if (value.isEmpty()) {
            None
        } else {
            Some(value)
        }
        okr.krOwner = SetValue<?String>.Value(ownerValue)
        patch.okr = Some(okr)
        ctx.store.updateItem(target, patch)
        closeOkrPrompt(ui)
        return
    }
    if (kind == "addkr") {
        page.addKeyResult(target, value)
        closeOkrPrompt(ui)
        return
    }
    // metric
    var base = EMPTY_METRIC
    for (candidate in page.data.entries) {
        for (kr in candidate.krs) {
            if (kr.item.id == target) {
                base = match (kr.metric) {
                    case Some(metric) => metric
                    case None => EMPTY_METRIC
                }
            }
        }
    }
    var draft = metricToDraft(base)
    let field = ui.promptField.value
    if (field == metricFieldText(MetricField.Start)) {
        draft = MetricDraft(start: value, current: draft.current, target: draft.target, unit: draft.unit)
    } else if (field == metricFieldText(MetricField.Current)) {
        draft = MetricDraft(start: draft.start, current: value, target: draft.target, unit: draft.unit)
    } else if (field == metricFieldText(MetricField.Target)) {
        draft = MetricDraft(start: draft.start, current: draft.current, target: value, unit: draft.unit)
    } else {
        draft = MetricDraft(start: draft.start, current: draft.current, target: draft.target, unit: value)
    }
    match (pendingMetricPatch(Some(base), draft, metricToDraft(base))) {
        case Some(decision) =>
            ctx.store.setMetric(target, decision.metric.start, decision.metric.target, decision.metric.current,
                decision.metric.unit)
            closeOkrPrompt(ui)
        case None =>
            ui.promptError.value = "这个值无法解析成数字。"
    }
}
