package textura.views.okr

import std.unicode.*
import cui.*
import textura.core.data.{ItemPatch, OkrPatch, SetValue, ViewContext}
import textura.ui.*
import textura.views.okr.logic.{EMPTY_METRIC, METRIC_FIELDS, MetricDraft, MetricField, metricFieldText, metricToDraft,
    parseMetricNumber, pendingMetricPatch}

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

/** 目标 / KR 标题。`rect` 是画布记录的标题矩形。 */
func openOkrTitlePrompt(ui: OkrUiState, id: String, title: String, rect: Rect): Unit {
    armPrompt(ui, "title", id, "", title, rect)
}

/** 指标数值（起点 / 当前 / 目标 / 单位）。`rect` 是画布记录的输入框矩形。 */
func openOkrMetricPrompt(ui: OkrUiState, krId: String, field: MetricField, value: String, rect: Rect): Unit {
    armPrompt(ui, "metric", krId, metricFieldText(field), value, rect)
}

/** 负责人。 */
func openOkrOwnerPrompt(ui: OkrUiState, krId: String, owner: String, rect: Rect): Unit {
    armPrompt(ui, "owner", krId, "", owner, rect)
}

/** 新增关键结果。`rect` 是「添加」框里那行输入的区域。 */
func openOkrAddKrPrompt(ui: OkrUiState, objectiveId: String, rect: Rect): Unit {
    armPrompt(ui, "addkr", objectiveId, "", "", rect)
}

/**
 * 这一帧这个字段是否正被原位编辑器接管。
 *
 * 卡片上的标题 / 指标 / 负责人都是画上去的，编辑器是压在同一个矩形上的真控件；两边同时画
 * 就会看到「两层文字 + 双边框」，而控件一旦比盒子高就变成「下面又冒出一个一样的框」。
 * 编辑态下画布只留背景，文字与边框交给控件自己画。
 */
func okrFieldEditing(ui: OkrUiState, kind: String, target: String, field!: String = ""): Bool {
    ui.promptOpen.value && ui.promptKind.value == kind && ui.promptTarget.value == target &&
        ui.promptField.value == field
}

/**
 * 画布上的画法：这个字段是否正被原位编辑器接管；是的话顺手把**本帧**的矩形写回锚点。
 *
 * 两个作用必须同时生效，否则真机上又会出现「编辑器留在原地、字段滚走了」或反过来：
 *   - 返回 true → 画布不再画这个字段的文字与边框（避免两层文字 + 双边框）；
 *   - `anchor.update(rect)` → 滚动偏移、窗口 resize、同页其它编辑改变行高时，编辑器跟着字段走
 *     （`Ui.inlineEditor` 的锚点合同，见 `ui/inline_anchor.cj`）。
 */
func trackOkrPrompt(ui: OkrUiState, kind: String, target: String, field: String, rect: Rect): Bool {
    let editing = okrFieldEditing(ui, kind, target, field: field)
    if (editing) {
        ui.promptAnchor.update(rect)
    }
    editing
}

private func armPrompt(ui: OkrUiState, kind: String, target: String, field: String, value: String,
    rect: Rect): Unit {
    ui.promptKind.value = kind
    ui.promptTarget.value = target
    ui.promptField.value = field
    ui.promptText.value = value
    ui.promptError.value = ""
    ui.promptAnchor.request(rect)
    ui.promptOpen.value = true
    ui.promptFocus.request(OKR_PROMPT_INPUT)
}

func closeOkrPrompt(ui: OkrUiState): Unit {
    // 焦点归还：把打开编辑器的那个画布字段重新交还回去。`FocusRequest.release()` 依赖「打开前
    // 谁持有焦点」，而画布热点是在 layout 里登记的，那一帧的拥有者未必还被焦点图认；字段 id 由
    // 编辑目标直接算得出来（`okr-field-<kr>-<field>` / `okr-owner-<id>` / `okr-addkr-<id>` /
    // `okr-title-<id>`），所以直接请求它，比自己猜前一个拥有者可靠。
    let opener = okrPromptFocusTarget(ui)
    ui.promptOpen.value = false
    ui.promptError.value = ""
    if (opener.isEmpty()) {
        ui.promptFocus.release()
    } else {
        ui.promptFocus.request(opener)
    }
}

/** 正在编辑的字段在画布上的焦点 id（关闭编辑器后把焦点还给它）。 */
func okrPromptFocusTarget(ui: OkrUiState): String {
    let target = ui.promptTarget.value
    if (target.isEmpty()) {
        return ""
    }
    let kind = ui.promptKind.value
    if (kind == "metric") {
        return "okr-field-${target}-${ui.promptField.value}"
    }
    if (kind == "owner") {
        return "okr-owner-${target}"
    }
    if (kind == "addkr") {
        return "okr-addkr-${target}"
    }
    "okr-title-${target}"
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

/**
 * 卡片画布上的原位编辑器（`okr.cj` 的 render 在卡片之后调用，仍在 build 阶段）。
 *
 * 字段矩形由画布在 layout 时记录（标题 / 指标输入框 / 负责人 / 新增 KR），点哪个就在哪个上编辑：
 * Enter 提交、Esc 取消、点外部提交，校验失败时编辑器不关、错误行显示在字段下方。
 *
 * 两个与「打字打不进去」直接相关的细节：
 *   - **编辑期间不写 store**：草稿是 `ui.promptText`（CUI `State`，`rememberState` 跨帧），
 *     只有 `commitOkrPrompt` 在 Enter / 失焦 / 点外部时才碰 `ctx.store`。store 每写一次
 *     `armStoreBridge` 就把整壳重建一次，若每按一键都写，编辑器会被反复重建、焦点与输入法
 *     一起丢——这正是用户现场（docs/DEVICE-NOTES.md §26）。
 *   - **指标是「槽位」而不是文档**：打开时全选当前值，输入 `42` 才是替换成 42，
 *     而不是在 `47` 后面接成 `4742`。
 */
func okrPromptDialog(ctx: ViewContext, ui: OkrUiState, page: OkrPage): Unit {
    if (!ui.promptOpen.value) {
        return
    }
    let target = ui.promptTarget.value
    var objectiveTitle = ""
    for (candidate in page.data.entries) {
        if (candidate.item.id == target) {
            objectiveTitle = candidate.item.title
        }
        for (kr in candidate.krs) {
            if (kr.item.id == target) {
                objectiveTitle = candidate.item.title
            }
        }
    }
    let copy = promptCopy(ui, objectiveTitle)
    // 指标（起点 / 当前 / 目标 / 单位）都是短值槽位：打开即全选，第一次输入就是替换。
    let slot = ui.promptKind.value == "metric"
    Ui.inlineEditor(page.theme, ui.promptText, ui.promptAnchor, true, key: OKR_PROMPT_INPUT,
        placeholder: copy.placeholder, error: ui.promptError.value, selectAllOnOpen: slot, focus: ui.promptFocus,
        onCommit: {value => commitOkrPrompt(ctx, ui, page, value)}, onCancel: {=> closeOkrPrompt(ui)})
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
    /*
     * 数字槽位在这里**先自己解析一次**，原因不是重复校验，而是 `pendingMetricPatch` 的 `None`
     * 有两个完全不同的含义：
     *   - 这个字段的值解析不了（跳过该字段）；
     *   - 解析得了，但和库里的值一致，没有字段需要写。
     * 两者混在一起报「这个值无法解析成数字」，于是「点开数字框直接回车」和「把原值重打一遍」
     * ——两个完全合法的操作——都会显示一句关于解析的错误、编辑器还不关。真机上用户先删后打、
     * 打进去没生效时草稿仍是原值，回车就撞上这一条：**报告里的「有一定概率出现这个值无法解析
     * 成数字」其实就是「没有任何字段发生变化」**，与解析无关。
     * 现在只有真正解析不了的值才走错误分支；「没有变化」按成功提交处理（关闭、不写库）。
     */
    if (field != metricFieldText(MetricField.UnitField)) {
        match (parseMetricNumber(value)) {
            case None =>
                ui.promptError.value = "这个值无法解析成数字。"
                return
            case Some(_) => ()
        }
    }
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
            // 值与库里一致（用户没改，或输入了同一个数）：没有字段要写，回车就是确认。
            // 不写库（写一个相同的值只会多一条历史），也不算错误。
            closeOkrPrompt(ui)
    }
}
