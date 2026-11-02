package textura.views.gtd

import std.collection.*
import std.unicode.*
import cui.*
import textura.core.data.*
import textura.ui.*
import textura.views.gtd.logic as gl

/*
 * 浮层：澄清弹窗（ClarifyDialog.tsx 1-347 + gtd.css:866-938）、场景/领域选择器、日期编辑。
 *
 * 弹窗本体用 `Ui.modal` + `Ui.field` + `Ui.textInput`（ui.css 的 .modal/.field/.input 几何），
 * 表单值放在视图状态里，提交时由 `logic.clarifyItem` 产出意图序列再落库；
 * 校验顺序与 TS 一致：`validateClarifyForm` → 有错不写库。
 */

/* ---------------------------------------------------------------- 表单状态 */

/** 场景下拉：`''`（未设置）+ 5 个预设 + `__custom__`。 */
func clarifyContextValue(index: Int64): String {
    if (index <= 0) {
        ""
    } else if (index <= gl.PRESET_CONTEXTS.size) {
        gl.PRESET_CONTEXTS[index - 1]
    } else {
        "__custom__"
    }
}

func clarifyContextIndex(context: String): Int64 {
    if (context.isEmpty()) {
        return 0
    }
    var index: Int64 = 0
    while (index < gl.PRESET_CONTEXTS.size) {
        if (gl.PRESET_CONTEXTS[index] == context) {
            return index + 1
        }
        index += 1
    }
    gl.PRESET_CONTEXTS.size + 1
}

func clarifyTypeValue(index: Int64): gl.ClarifyType {
    match (index) {
        case 1 => gl.ClarifyType.Project
        case 2 => gl.ClarifyType.Reference
        case 3 => gl.ClarifyType.Note
        case _ => gl.ClarifyType.Next
    }
}

func clarifyTypeIndex(types: gl.ClarifyType): Int64 {
    match (types) {
        case gl.ClarifyType.Next => 0
        case gl.ClarifyType.Project => 1
        case gl.ClarifyType.Reference => 2
        case gl.ClarifyType.Note => 3
    }
}

func clarifyEnergyValue(index: Int64): gl.Energy {
    match (index) {
        case 0 => gl.Energy.Low
        case 2 => gl.Energy.High
        case _ => gl.Energy.Medium
    }
}

func clarifyEnergyIndex(energy: gl.Energy): Int64 {
    match (energy) {
        case gl.Energy.Low => 0
        case gl.Energy.Medium => 1
        case gl.Energy.High => 2
    }
}

/** 从视图状态重建纯函数层的表单对象。 */
func clarifyForm(scene: GtdScene): gl.ClarifyFormState {
    let s = scene.state
    let estimateIndex = s.clarifyEstimate.value
    let areaIndex = s.clarifyArea.value
    let areas = scene.workspace.areas
    gl.ClarifyFormState(
        clarifyType: clarifyTypeValue(s.clarifyType.value),
        title: s.clarifyTitle.value,
        notes: s.clarifyNotes.value,
        tags: s.clarifyTags.value,
        areaId: if (areaIndex <= 0 || areaIndex > areas.size) {
            ""
        } else {
            areas[areaIndex - 1].id
        },
        context: clarifyContextValue(s.clarifyContext.value),
        customContext: s.clarifyCustomContext.value,
        energy: clarifyEnergyValue(s.clarifyEnergy.value),
        estimateMin: if (estimateIndex <= 0 || estimateIndex > gl.ESTIMATE_OPTIONS.size) {
            None
        } else {
            Some(gl.ESTIMATE_OPTIONS[estimateIndex - 1])
        },
        dueDate: s.clarifyDue.value,
        delegated: s.clarifyDelegated.value,
        waitingFor: s.clarifyWaitingFor.value,
        someday: s.clarifySomeday.value,
        twoMinuteCandidate: s.clarifyTwoMinute.value
    )
}

/** 打开澄清弹窗：表单从条目重新初始化（ClarifyDialog.tsx `createClarifyForm`）。 */
func openClarifyState(scene: GtdScene, id: String): Unit {
    let s = scene.state
    match (scene.item(id)) {
        case Some(item) =>
            let form = gl.createClarifyForm(toGtdItem(item))
            s.clarifyId.value = id
            s.clarifyType.value = clarifyTypeIndex(form.clarifyType)
            s.clarifyEnergy.value = clarifyEnergyIndex(form.energy)
            s.clarifyContext.value = clarifyContextIndex(form.context)
            s.clarifyTitle.value = form.title
            s.clarifyNotes.value = form.notes
            s.clarifyTags.value = form.tags
            s.clarifyCustomContext.value = form.customContext
            s.clarifyDue.value = form.dueDate
            s.clarifyWaitingFor.value = form.waitingFor
            s.clarifyDelegated.value = form.delegated
            s.clarifySomeday.value = form.someday
            s.clarifyTwoMinute.value = form.twoMinuteCandidate
            s.clarifyEstimate.value = match (form.estimateMin) {
                case Some(value) =>
                    var index: Int64 = 1
                    var found: Int64 = 0
                    for (option in gl.ESTIMATE_OPTIONS) {
                        if (option == value) {
                            found = index
                        }
                        index += 1
                    }
                    found
                case None => 0
            }
            s.clarifyArea.value = if (form.areaId.isEmpty()) {
                0
            } else {
                var index: Int64 = 1
                var found: Int64 = 0
                for (area in scene.workspace.areas) {
                    if (area.id == form.areaId) {
                        found = index
                    }
                    index += 1
                }
                found
            }
            s.clarifySubmitted.value = false
        case None => ()
    }
}

/** 提交（ClarifyDialog.tsx `submit`）：校验 → 意图 → 落库 → 关闭。 */
func submitClarify(scene: GtdScene): Unit {
    let id = scene.state.clarifyId.value
    if (id.isEmpty()) {
        return
    }
    match (scene.item(id)) {
        case Some(item) =>
            let form = clarifyForm(scene)
            scene.state.clarifySubmitted.value = true
            let errors = gl.validateClarifyForm(form)
            if (!errors.isEmpty()) {
                return
            }
            scene.run(gl.clarifyItem(toGtdItem(item), form, scene.placeholder("act"), scene.now()))
            scene.state.clarifyId.value = ""
            scene.state.clarifySubmitted.value = false
        case None => scene.state.clarifyId.value = ""
    }
}

/* ---------------------------------------------------------------- 浮层声明 */

func gtdOverlays(scene: GtdScene): Unit {
    gtdClarifyDialog(scene)
    gtdPickerDialog(scene)
    gtdDateDialog(scene)
    gtdSceneDialog(scene)
}

/** 行内日期 / 场景编辑器里那个输入框的焦点 id（一次只有一个编辑器）。 */
let GTD_DATE_INPUT: String = "gtd-date-input";
let GTD_SCENE_INPUT: String = "gtd-scene-input";

func modalFlag(): State<Bool> {
    State<Bool>(true)
}

/** 澄清弹窗（ClarifyDialog.tsx）。 */
func gtdClarifyDialog(scene: GtdScene): Unit {
    let id = scene.state.clarifyId.value
    if (id.isEmpty()) {
        return
    }
    let theme = scene.theme
    let tokens = scene.tokens
    match (scene.item(id)) {
        case Some(item) =>
            let form = clarifyForm(scene)
            let errors = gl.validateClarifyForm(form)
            let showErrors = scene.state.clarifySubmitted.value
            let archive = gl.isArchiveType(form.clarifyType)
            let source = toGtdItem(item)
            let capturedAt = match (source.capturedAt) {
                case Some(value) => Some(value)
                case None => Some(source.createdAt)
            }
            let description = "${itemKindLabel(item.kind)} · 收集于 ${gl.relativeTimeLabel(capturedAt, scene.today)}"
            Ui.modal(
                theme,
                modalFlag(),
                {=> closeClarify(scene)},
                title: "澄清这一条",
                description: description,
                width: CLARIFY_WIDTH,
                footer: {=>
                    Ui.button(theme, "取消", {=> closeClarify(scene)}, variant: ButtonVariant.Ghost,
                        size: ControlSize.Sm)
                    Ui.button(theme, "完成澄清", {=> submitClarify(scene)}, variant: ButtonVariant.Primary,
                        size: ControlSize.Sm)
                },
                body: {=> clarifyFormBody(scene, item, form, errors, showErrors, archive)}
            )
        case None => ()
    }
    let _ = tokens
}

func closeClarify(scene: GtdScene): Unit {
    scene.state.clarifyId.value = ""
    scene.state.clarifySubmitted.value = false
}

func clarifyFormBody(
    scene: GtdScene,
    item: Item,
    form: gl.ClarifyFormState,
    errors: gl.ClarifyErrors,
    showErrors: Bool,
    archive: Bool
): Unit {
    let theme = scene.theme
    let tokens = scene.tokens
    let s = scene.state
    let typeItems = ["下一步行动", "项目（升级）", "参考资料", "笔记"]
    let energyItems = ["低能量", "中能量", "高能量"]
    VStack(spacing: vp(FORM_GAP)) {
        // 第一行：类型 / 能量
        HStack(spacing: vp(FORM_GRID_GAP_H)) {
            VStack(spacing: vp(0.0)) {
                Ui.field(theme, label: "类型") {
                    Ui.segmented(theme, typeItems, s.clarifyType, size: ControlSize.Sm)
                }
            }.hug().flex()
            VStack(spacing: vp(0.0)) {
                Ui.field(theme, label: "能量") {
                    Ui.segmented(theme, energyItems, s.clarifyEnergy, size: ControlSize.Sm)
                }
            }.hug().flex()
        }.hug().fillWidth()
        // 标题（必填，跨列）
        Ui.field(theme, label: "标题", required: true, error: if (showErrors) {
            match (errors.title) {
                case Some(value) => value
                case None => ""
            }
        } else {
            ""
        }) {
            Ui.textInput(theme, s.clarifyTitle, key: "gtd-clarify-title",
                placeholder: "用一个动词开头的具体行动", invalid: showErrors && errors.title.isSome())
        }
        // 备注
        Ui.field(theme, label: "备注") {
            Ui.textArea(theme, s.clarifyNotes, key: "gtd-clarify-notes",
                placeholder: "成功的标准、链接、下一步线索…", height: FORM_TEXTAREA_H)
        }
        // 场景 / 预计时长
        HStack(spacing: vp(FORM_GRID_GAP_H)) {
            VStack(spacing: vp(0.0)) {
                Ui.field(theme, label: "场景 context") {
                    clarifyContextPicker(scene)
                }
            }.hug().flex()
            VStack(spacing: vp(0.0)) {
                Ui.field(theme, label: "预计时长（仅判断 2 分钟）") {
                    clarifyEstimatePicker(scene)
                }
            }.hug().flex()
        }.hug().fillWidth()
        if (form.context == "__custom__") {
            Ui.field(theme, label: "自定义场景") {
                Ui.textInput(theme, s.clarifyCustomContext, key: "gtd-clarify-custom",
                    placeholder: "例如：通勤、飞机上")
            }
        }
        // 截止日期 / 领域
        HStack(spacing: vp(FORM_GRID_GAP_H)) {
            VStack(spacing: vp(0.0)) {
                Ui.field(theme, label: "截止日期") {
                    Ui.textInput(theme, s.clarifyDue, key: "gtd-clarify-due", placeholder: "YYYY-MM-DD")
                }
            }.hug().flex()
            VStack(spacing: vp(0.0)) {
                Ui.field(theme, label: "领域") {
                    clarifyAreaPicker(scene)
                }
            }.hug().flex()
        }.hug().fillWidth()
        // 标签
        Ui.field(theme, label: "标签") {
            Ui.textInput(theme, s.clarifyTags, key: "gtd-clarify-tags",
                placeholder: "空格或逗号分隔，例如：官网 品牌")
        }
        // 三个复选行（gtd.css:891-909）
        VStack(spacing: vp(0.0)) {
            HStack(spacing: vp(FORM_GRID_GAP_H)) {
                checkLine(scene, "委派给他人，进入等待", s.clarifyDelegated, !archive, {=>
                    s.clarifyDelegated.value = !s.clarifyDelegated.value
                    if (s.clarifyDelegated.value) {
                        s.clarifySomeday.value = false
                    }
                })
                checkLine(scene, "某天 / 搁置", s.clarifySomeday, !archive, {=>
                    s.clarifySomeday.value = !s.clarifySomeday.value
                    if (s.clarifySomeday.value) {
                        s.clarifyDelegated.value = false
                    }
                })
                checkLine(scene, "属于 2 分钟规则（提示先做）", s.clarifyTwoMinute, !archive,
                    {=> s.clarifyTwoMinute.value = !s.clarifyTwoMinute.value})
                Spacer()
            }
                .crossAxisAlignment(CrossAxisAlignment.Center)
                .hug()
                .fillWidth()
        }
            .hug()
            .fillWidth()
            .padding(vp(FORM_CHECKS_PAD_H), vp(FORM_CHECKS_PAD_V), vp(FORM_CHECKS_PAD_H), vp(FORM_CHECKS_PAD_V))
            .background(tokens.color.bgSubtle, tokens.radius.md)
            .border(tokens.color.border, width: tokens.metrics.borderWidth, radius: tokens.radius.md)
        if (form.delegated) {
            Ui.field(theme, label: "等待对象", required: true, error: if (showErrors) {
                match (errors.waitingFor) {
                    case Some(value) => value
                    case None => ""
                }
            } else {
                ""
            }) {
                Ui.textInput(theme, s.clarifyWaitingFor, key: "gtd-clarify-waiting",
                    placeholder: "例如：法务 · 张律师", invalid: showErrors && errors.waitingFor.isSome())
            }
        }
        match (errors.status) {
            case Some(value) =>
                if (showErrors) {
                    Label(value).fontSize(11.5).foregroundColor(tokens.color.danger)
                }
            case None => ()
        }
        match (clarifyHint(item, form, archive)) {
            case Some(text) => callout(scene, text, IconGlyph.Link, false)
            case None => ()
        }
        if (form.twoMinuteCandidate && !archive) {
            callout(scene, "2 分钟内能完成的事，建议直接做完，不必留在系统里。", IconGlyph.Clock, true)
        }
    }.hug().fillWidth()
}

func checkLine(scene: GtdScene, label: String, flag: State<Bool>, enabled: Bool, onClick: () -> Unit): Unit {
    let tokens = scene.tokens
    HStack(spacing: vp(CHECKLINE_GAP)) {
        GtdCheckBox(tokens, flag.value, "gtd-checkline:${label}", {=>
            if (enabled) {
                onClick()
            }
        })
        GtdText(label, CHECKLINE_SIZE, 400, tokens.color.textMuted, boxHeight: CHECKLINE_SIZE * LINE_HEIGHT)
    }
        .crossAxisAlignment(CrossAxisAlignment.Center)
        .hug()
}

/** `ClarifyType` 判别（`@Derive[Equatable]` 的 `==` 不跨包可见，改用 match）。 */
func isClarifyProject(types: gl.ClarifyType): Bool {
    match (types) {
        case gl.ClarifyType.Project => true
        case _ => false
    }
}

func isClarifyNext(types: gl.ClarifyType): Bool {
    match (types) {
        case gl.ClarifyType.Next => true
        case _ => false
    }
}

/** 升级/归档提示（ClarifyDialog.tsx `upgradeHint`）。 */
func clarifyHint(item: Item, form: gl.ClarifyFormState, archive: Bool): ?String {
    if (isClarifyProject(form.clarifyType) && item.kind != ItemKind.Project) {
        return Some("提交后会新建项目，并把当前条目归档为来源记录。")
    }
    if (isClarifyNext(form.clarifyType) && item.kind != ItemKind.Action && item.kind != ItemKind.Project) {
        return Some("当前条目不是行动类型；提交后会新建下一步行动，并把原条目归档。")
    }
    if (archive) {
        return Some("参考资料 / 笔记会归档，不再出现在收件箱。")
    }
    None
}

func callout(scene: GtdScene, text: String, glyph: IconGlyph, warn: Bool): Unit {
    let tokens = scene.tokens
    HStack(spacing: vp(CALLOUT_GAP)) {
        IconView(glyph, side: 14.0, color: tokens.color.accent)
        GtdText(text, CALLOUT_SIZE, 400, if (warn) {
            tokens.color.text
        } else {
            tokens.color.textMuted
        }, boxHeight: CALLOUT_SIZE * LINE_HEIGHT)
    }
        .crossAxisAlignment(CrossAxisAlignment.Start)
        .hug()
        .fillWidth()
        .padding(vp(CALLOUT_PAD_H), vp(CALLOUT_PAD_V), vp(CALLOUT_PAD_H), vp(CALLOUT_PAD_V))
        .background(if (warn) {
            tokens.color.surface2
        } else {
            tokens.color.accentSoft
        }, tokens.radius.md)
}

/* ---------------------------------------------------------------- 表单内的选择器 */

func clarifyContextPicker(scene: GtdScene): Unit {
    let labels = ArrayList<String>()
    labels.add("未设置场景")
    for (context in gl.PRESET_CONTEXTS) {
        labels.add("@${context}")
    }
    labels.add("自定义场景…")
    Dropdown(labels.toArray(), scene.state.clarifyContext, key: "gtd-dropdown-context")
}

func clarifyEstimatePicker(scene: GtdScene): Unit {
    let labels = ArrayList<String>()
    labels.add("未估时")
    for (minutes in gl.ESTIMATE_OPTIONS) {
        labels.add("${minutes} 分钟")
    }
    Dropdown(labels.toArray(), scene.state.clarifyEstimate, key: "gtd-dropdown-estimate")
}

func clarifyAreaPicker(scene: GtdScene): Unit {
    let labels = ArrayList<String>()
    labels.add("无领域")
    for (area in scene.workspace.areas) {
        labels.add(area.name)
    }
    Dropdown(labels.toArray(), scene.state.clarifyArea, key: "gtd-dropdown-area")
}

/* ---------------------------------------------------------------- 场景 / 领域选择器 */

/** 简单选择弹窗：点击行内 select 打开，选项直接落库（替代 Web 的 `<select>` 浮层）。 */
func gtdPickerDialog(scene: GtdScene): Unit {
    let target = scene.state.picker.value
    if (target.isEmpty()) {
        return
    }
    let theme = scene.theme
    let tokens = scene.tokens
    let options = pickerOptions(scene, target)
    let title = pickerTitle(target)
    Ui.modal(
        theme,
        modalFlag(),
        {=> scene.state.picker.value = ""},
        title: title,
        description: "选择一个值，立即写入工作区。",
        width: 420.0,
        footer: {=> Ui.button(theme, "关闭", {=> scene.state.picker.value = ""},
            variant: ButtonVariant.Ghost, size: ControlSize.Sm)},
        body: {=>
            VStack(spacing: vp(4.0)) {
                for (option in options) {
                    Ui.button(theme, option.label, {=>
                        applyPicker(scene, target, option.value)
                        scene.state.picker.value = ""
                    }, variant: if (option.selected) {
                        ButtonVariant.Secondary
                    } else {
                        ButtonVariant.Ghost
                    }, size: ControlSize.Sm, block: true)
                }
            }.hug().fillWidth()
            let _ = tokens
        }
    )
}

func pickerTitle(target: String): String {
    if (target == "filter-area") {
        "按领域筛选"
    } else if (target == "filter-context") {
        "按场景筛选"
    } else {
        "修改场景"
    }
}

struct PickerOption {
    let value: String
    let label: String
    let selected: Bool

    init(value: String, label: String, selected: Bool) {
        this.value = value
        this.label = label
        this.selected = selected
    }
}

func pickerOptions(scene: GtdScene, target: String): Array<PickerOption> {
    let options = ArrayList<PickerOption>()
    if (target == "filter-area") {
        let current = scene.state.areaFilter.value
        options.add(PickerOption("", "全部领域", current.isEmpty()))
        for (area in scene.workspace.areas) {
            options.add(PickerOption(area.id, area.name, current == area.id))
        }
        return options.toArray()
    }
    let ui = scene.ctx.store.ui.value()
    if (target == "filter-context") {
        let current = match (ui.gtdContext) {
            case Some(value) => value
            case None => ""
        }
        options.add(PickerOption("", "全部场景", current.isEmpty()))
        for (context in gl.PRESET_CONTEXTS) {
            options.add(PickerOption(context, "@${context}", current == context))
        }
        options.add(PickerOption(gl.NO_CONTEXT_FILTER, "@${gl.NO_CONTEXT}", current == gl.NO_CONTEXT_FILTER))
        return options.toArray()
    }
    // row-context:<id>
    let id = target.replace("row-context:", "")
    let current = match (scene.item(id)) {
        case Some(item) => match (toGtdItem(item).context) {
            case Some(value) => value.trim()
            case None => ""
        }
        case None => ""
    }
    options.add(PickerOption("", "@${gl.NO_CONTEXT}", current.isEmpty()))
    for (context in gl.PRESET_CONTEXTS) {
        options.add(PickerOption(context, "@${context}", current == context))
    }
    match (scene.item(id)) {
        case Some(item) =>
            let extra = match (toGtdItem(item).context) {
                case Some(value) => value.trim()
                case None => ""
            }
            if (!extra.isEmpty() && clarifyContextIndex(extra) > gl.PRESET_CONTEXTS.size) {
                options.add(PickerOption(extra, "@${extra}", true))
            }
        case None => ()
    }
    options.toArray()
}

func applyPicker(scene: GtdScene, target: String, value: String): Unit {
    if (target == "filter-area") {
        scene.state.areaFilter.value = value
        return
    }
    if (target == "filter-context") {
        scene.ctx.store.setGtdContext(if (value.isEmpty()) {
            None
        } else {
            Some(value)
        })
        return
    }
    let id = target.replace("row-context:", "")
    let patch = GtdPatch()
    patch.context = SetValue<?String>.Value(optionalText(value))
    scene.ctx.store.updateItem(id, ItemPatch().withGtd(patch))
    scene.ctx.store.notify("场景已更新", tone: NoticeTone.Success)
}

/* ---------------------------------------------------------------- 日期 / 场景原位编辑 */

/**
 * 行内日期盒被点击：记下条目、当前值与那个盒子的矩形，然后**就地**打开编辑器
 * （`Ui.inlineEditor`，见 `gtdDateDialog`）。
 */
func openDateEditor(scene: GtdScene, item: gl.GtdItem, rect: Rect): Unit {
    scene.state.dateTarget.value = item.id
    scene.state.dateDraft.value = match (dateKey(item.dueDate)) {
        case Some(value) => value
        case None => ""
    }
    scene.state.dateError.value = ""
    scene.state.dateAnchor.request(rect)
    scene.state.dateFocus.request(GTD_DATE_INPUT)
}

func closeDateEditor(scene: GtdScene): Unit {
    scene.state.dateTarget.value = ""
    scene.state.dateError.value = ""
    scene.state.dateFocus.release()
}

/**
 * 日期原位编辑器。
 *
 * 草稿在本地（`state.dateDraft`，CUI `State`），**编辑期间不写 store**：每按一个键就写一次
 * store 会经 `armStoreBridge` 把整壳重建一次，编辑器随之重建、焦点与输入法一起丢
 * （docs/DEVICE-NOTES.md §26）。只有 Enter / 失焦 / 点外部才走 [commitDate]。
 *
 * 占位文案与盒子一致（`INLINE_DATE_PLACEHOLDER`），并且打开即全选：日期是槽位，
 * 输入 `2026-11-05` 是替换整个值，不是在旧值后面接。
 */
func gtdDateDialog(scene: GtdScene): Unit {
    let target = scene.state.dateTarget.value
    if (target.isEmpty()) {
        return
    }
    let state = scene.state
    Ui.inlineEditor(scene.theme, state.dateDraft, state.dateAnchor, true, key: GTD_DATE_INPUT,
        placeholder: INLINE_DATE_PLACEHOLDER, error: state.dateError.value, selectAllOnOpen: true,
        focus: state.dateFocus,
        onCommit: {value => commitDate(scene, target, value)}, onCancel: {=> closeDateEditor(scene)})
}

/**
 * 日期的提交校验：`YYYY-MM-DD` 且月/日在范围内才写回 `gantt.end`；空串表示清除日期。
 *
 * 非法值**不写、不关**：错误行显示在盒子下面，用户改对再按 Enter，或者按 Esc 放弃——
 * 「打错了就被吞掉、还关不掉」是上一轮用户现场里最不能接受的两种失败。
 */
func commitDate(scene: GtdScene, id: String, raw: String): Unit {
    let value = raw.trim()
    if (value.isEmpty()) {
        setDue(scene, id, "")
        closeDateEditor(scene)
        return
    }
    if (!gl.isValidDayKey(value)) {
        scene.state.dateError.value = "日期格式应为 YYYY-MM-DD，例如 2026-11-05。"
        return
    }
    setDue(scene, id, value)
    closeDateEditor(scene)
}

/** 行内场景（`@context`）盒被点击：同样原位编辑；留空表示未设置场景。 */
func openSceneEditor(scene: GtdScene, item: gl.GtdItem, rect: Rect): Unit {
    scene.state.sceneTarget.value = item.id
    scene.state.sceneDraft.value = match (item.context) {
        case Some(value) => value
        case None => ""
    }
    scene.state.sceneAnchor.request(rect)
    scene.state.sceneFocus.request(GTD_SCENE_INPUT)
}

func closeSceneEditor(scene: GtdScene): Unit {
    scene.state.sceneTarget.value = ""
    scene.state.sceneFocus.release()
}

func gtdSceneDialog(scene: GtdScene): Unit {
    let target = scene.state.sceneTarget.value
    if (target.isEmpty()) {
        return
    }
    let state = scene.state
    Ui.inlineEditor(scene.theme, state.sceneDraft, state.sceneAnchor, true, key: GTD_SCENE_INPUT,
        placeholder: "@场景（留空表示未设置）", focus: state.sceneFocus,
        onCommit: {value =>
            applyPicker(scene, "row-context:${target}", value.trim())
            closeSceneEditor(scene)
        }, onCancel: {=> closeSceneEditor(scene)})
}

func setDue(scene: GtdScene, id: String, value: String): Unit {
    scene.ctx.store.setDueDate(id, optionalText(value.trim()))
    scene.ctx.store.notify("截止日期已更新", tone: NoticeTone.Success)
}
