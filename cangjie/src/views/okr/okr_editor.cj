package textura.views.okr

import std.collection.ArrayList
import std.unicode.*
import cui.*
import textura.core.data.{AppStore, Item, ItemKind, ItemPatch, ItemStatus, OkrPatch, SaveState, SetValue, ViewContext,
    Workspace, itemById}
import textura.ui.*
import textura.views.okr.logic.{EMPTY_METRIC, METRIC_FIELDS, MetricDraft, MetricField, OkrMetric, formatMetric,
    metricFieldText, metricToDraft, metricToText, pendingMetricPatch, quarterLabel}

/*
 * 独立的目标编辑页（P1+P2，`docs/OKR-EDIT-PLAN.md` §4）。
 *
 * 为什么是一整页原生控件树，而不是卡片画布上的行内编辑器：
 *   - CUI 只在**构建期**把控件登记进焦点图；画布（`OkrPage`）的控件在 layout 期构造，行内
 *     `TextField` 永远拿不到焦点（`docs/DEVICE-NOTES.md` §16）。
 *   - 崩溃组合是「自绘页 + `Ui.inlineEditor` + `Portal` + IME 锚点」（`docs/HANDOFF.md` §6.2）；
 *     本页**不用**这三件中的任何一件，输入框就是普通的 `TextField` / `TextArea`。
 *
 * 渐进式单编辑态（对齐 `ObjectiveEditor.tsx` / `KrRow.tsx`）：默认全是只读文本，点哪一处的小
 * 铅笔才出现输入；同一时刻只有一个编辑目标（`ui.editTarget`）：
 *   `""` | `title` | `notes` | `area` | `status` | `confidence` | `kr:<id>` | `add-kr`
 * 切换目标时上一处先提交再收起（`okrEditorSetTarget`）。
 *
 * 保存模型（`docs/OKR-EDIT-PLAN.md` §4.4）：
 *   - 标题 / KR 标题 / 领域 / 状态 / 信心 / 指标四格 / 负责人：失焦或 Enter 立即写；
 *   - notes：停止输入 600ms 后写（`FrameInfo.elapsedMs`，视图不读系统时钟），失焦 / 返回时 flush；
 *   - 外部改动（撤销 / 导入 / 其它视图）不打断草稿：只有 store 的值 ≠ 自己最后提交的值才覆盖草稿。
 */

/** 编辑页根节点的稳定标识（`OkrEditorWatch` 的语义/调试用；不参与焦点）。 */
let OKR_EDITOR_ROOT: String = "okr-ed-root";
/** notes 停止输入多久写库（`ObjectiveEditor.tsx:23` 的 `NOTES_COMMIT_DELAY_MS`）。 */
let OKR_NOTES_DEBOUNCE_MS: Int64 = 600;
/** `.okr-editor { max-width: 1080px }`。 */
let OKR_EDITOR_MAX_W: Float32 = 1080.0;

/* ------------------------------------------------------------------ 控件 id */

func okrEditorTitleId(): String {
    "okr-ed-title"
}

func okrEditorNotesId(): String {
    "okr-ed-notes"
}

func okrEditorAddId(): String {
    "okr-ed-addkr"
}

func okrEditorKrTitleId(krId: String): String {
    "okr-ed-krtitle-${krId}"
}

func okrEditorOwnerId(krId: String): String {
    "okr-ed-owner-${krId}"
}

func okrEditorMetricId(krId: String, field: MetricField): String {
    "okr-ed-metric-${krId}-${metricFieldText(field)}"
}

/** 铅笔 / 展开按钮的控件 id（测试用语义节点定位它们）。 */
func okrEditorPencilId(kind: String): String {
    "okr-ed-edit-${kind}"
}

func okrEditorKrPencilId(krId: String): String {
    "okr-ed-edit-kr-${krId}"
}

func okrEditorKrTarget(krId: String): String {
    "kr:${krId}"
}

/**
 * 编辑目标 → 该目标展开后应该拿到焦点的控件 id（`""` = 纯展示，没有输入框）。
 *
 * 用于两处：`openOkrEditor`（从列表带着某个目标进来，例如「新增关键结果」）与
 * `okrEditorSetTarget`（点铅笔展开）。焦点请求由树里的 `FocusOnceView` 落地，`FocusRequest`
 * 会重试几帧，因此「控件下一帧才出现」也能落上。
 */
func okrEditorTargetFocusId(target: String): String {
    if (target == "title") {
        return okrEditorTitleId()
    }
    if (target == "notes") {
        return okrEditorNotesId()
    }
    if (target == "add-kr") {
        return okrEditorAddId()
    }
    if (target.startsWith("kr:")) {
        return okrEditorKrTitleId(target["kr:".size..target.size])
    }
    // `area` / `status` / `confidence` 展开后是一排选择按钮，没有文本输入：焦点留在铅笔上。
    ""
}

/* --------------------------------------------------------------- 草稿键 */

func okrEditorDraftTitle(objectiveId: String): String {
    "ed-title-${objectiveId}"
}

func okrEditorDraftNotes(objectiveId: String): String {
    "ed-notes-${objectiveId}"
}

func okrEditorDraftAdd(objectiveId: String): String {
    "ed-addkr-${objectiveId}"
}

func okrEditorDraftKrTitle(krId: String): String {
    "ed-krtitle-${krId}"
}

func okrEditorDraftOwner(krId: String): String {
    "ed-owner-${krId}"
}

func okrEditorDraftMetric(krId: String, field: MetricField): String {
    "ed-metric-${krId}-${metricFieldText(field)}"
}

/* ------------------------------------------------------------------ 数据 */

/** 编辑页的数据快照：目标条目 + 它自己的季度。 */
class OkrEditorData {
    let entry: OkrObjEntry
    let period: String

    init(entry: OkrObjEntry, period: String) {
        this.entry = entry
        this.period = period
    }
}

/**
 * 编辑页要编辑的那个目标：id 必须存在且 `kind == Objective`（`resolveEditorObjective`）。
 *
 * 派生值（进度 / 落后 / 执行项）走与列表页**同一条** `buildOkrPageData`，所以两边看到的数字
 * 一定一致；这里只是按目标 id 把那一格挑出来。
 */
func buildOkrEditorData(workspace: Workspace, objectiveId: String, todayKey: String,
    fallbackPeriod: String): ?OkrEditorData {
    if (objectiveId.isEmpty()) {
        return None
    }
    let objective = match (itemById(workspace, objectiveId)) {
        case Some(value) => value
        case None => return None
    }
    if (objective.kind != ItemKind.Objective) {
        return None
    }
    let period = itemPeriod(objective, fallbackPeriod)
    let data = buildOkrPageData(workspace, period, "", todayKey)
    for (entry in data.entries) {
        if (entry.item.id == objectiveId) {
            return Some(OkrEditorData(entry, period))
        }
    }
    None
}

/* --------------------------------------------------------------- 打开 / 返回 */

/**
 * 打开编辑页（卡片铅笔 `okr-edit-<id>` 与「新增关键结果」入口都走这里）。
 *
 * `target` 是打开后立即进入的编辑目标：`""` = 纯展示，`add-kr` = 直接展开新增输入框。
 * 这里还顺手把 notes 的「已提交值」对齐到 store（防抖以它为基准判断外部改动）。
 */
func openOkrEditor(ui: OkrUiState, store: AppStore, objectiveId: String, target: String): Unit {
    if (objectiveId.isEmpty()) {
        return
    }
    let notes = okrEditorNotesOf(store.state.value(), objectiveId)
    ui.notesCommitted.value = notes
    ui.notesSeen.value = notes
    ui.notesTick.value = 0
    ui.menuOpen.value = false
    ui.editSession.value = ui.editSession.value + 1
    ui.editTarget.value = target
    ui.editId.value = objectiveId
    store.select(objectiveId)
    /*
     * 焦点：带目标进来（「新增关键结果」）→ 新控件的输入框；纯展示进入 → 第一支铅笔（标题）。
     *
     * CUI 的焦点 id 只能来自**构建期声明的控件**，而「返回目标列表」是共享 `ButtonView`
     * （id 由构建序号派生，无法预先请求），所以落点是本页自己的控件；返回列表时再请求卡片上的
     * 铅笔 `okr-edit-<id>`。
     */
    var focusTarget = okrEditorTargetFocusId(target)
    if (focusTarget.isEmpty()) {
        focusTarget = okrEditorPencilId("title")
    }
    ui.editorFocus.request(focusTarget)
}

/** 返回列表：先 flush notes，再清 `editId`，并把焦点请求指回进入时的那支铅笔。 */
func closeOkrEditor(store: AppStore, ui: OkrUiState): Unit {
    let objectiveId = ui.editId.value
    if (!objectiveId.isEmpty()) {
        match (ui.peekField(okrEditorDraftNotes(objectiveId))) {
            case Some(draft) => okrEditorFlushNotes(store, ui, objectiveId, draft.value)
            case None => ()
        }
    }
    ui.editTarget.value = ""
    ui.editId.value = ""
    if (!objectiveId.isEmpty()) {
        ui.editorFocus.request("okr-edit-${objectiveId}")
    }
}

func okrEditorNotesOf(workspace: Workspace, objectiveId: String): String {
    match (itemById(workspace, objectiveId)) {
        case Some(item) => item.notes
        case None => ""
    }
}

/* ------------------------------------------------------------------ 页面 */

/** `render` 在 `editId != ""` 时调用它（`okr.cj`）。 */
func okrEditorPage(ctx: ViewContext, ui: OkrUiState): Unit {
    let store = ctx.store
    let tokens = if (ctx.theme == "dark") {
        ThemeTokens.dark()
    } else {
        ThemeTokens.light()
    }
    let theme = tokens.theme()
    let workspace = store.state.value()
    let objectiveId = ui.editId.value
    let fallbackPeriod = quarterOfDate(okrToday(ctx.today))
    let maybeData = buildOkrEditorData(workspace, objectiveId, ctx.today, fallbackPeriod)
    if (maybeData.isNone()) {
        // 目标不存在 / 已被删除：空态 + 返回按钮，不白屏（`ObjectiveEditor.tsx:114-126`）。
        okrEditorMissingPage(store, ui, tokens, theme)
        return
    }
    let data = maybeData.getOrThrow()
    let entry = data.entry
    okrEditorPrimeDrafts(ui, entry)
    /*
     * notes 防抖要的是 `FrameInfo.elapsedMs`（`AGENTS.md` §6：视图不读系统时钟），而帧回调只有
     * `FrameHandler` 能拿到。代价是编辑页打开期间持续出帧（每帧重建这棵小控件树）；关闭编辑页
     * 即停止。列表页的自绘画布不受影响。
     */
    FrameHandler(onFrame: {info => okrEditorTick(store, ui, entry, info)}) {
        EventHandler(onEvent: {eventCtx, event => okrEditorEscape(eventCtx, event, store, ui, entry)}) {
            okrEditorBody(store, ui, entry, data.period, tokens, theme)
        }
        okrDialogs(ctx, ui, OkrDialogScope(data.period, [entry]))
    }
}

/**
 * 构建期登记编辑页用到的全部草稿 State（`rememberState` 只能在构建阶段调用）。
 *
 * 值只在**第一次**创建时生效；之后由 `okrEditorSyncDrafts`（帧回调）在「该字段当前没有在编辑」
 * 时对齐 store —— 这样外部改动（撤销 / 导入 / 其它视图）能反映进来，而正在输入的那个字段不为所动。
 */
func okrEditorPrimeDrafts(ui: OkrUiState, entry: OkrObjEntry): Unit {
    let objectiveId = entry.item.id
    let _ = ui.field(okrEditorDraftTitle(objectiveId), entry.item.title)
    let _ = ui.field(okrEditorDraftNotes(objectiveId), entry.item.notes)
    let _ = ui.field(okrEditorDraftAdd(objectiveId), "")
    for (kr in entry.krs) {
        let krId = kr.item.id
        let _ = ui.field(okrEditorDraftKrTitle(krId), kr.item.title)
        let _ = ui.field(okrEditorDraftOwner(krId), kr.owner)
        for (field in METRIC_FIELDS) {
            let _ = ui.field(okrEditorDraftMetric(krId, field), okrEditorMetricText(kr, field))
        }
    }
}

/** 指标草稿的初值：没有指标时四格都为空（与「未设指标」一致）。 */
func okrEditorMetricText(kr: OkrKrEntry, field: MetricField): String {
    match (kr.metric) {
        case Some(metric) =>
            if (field == MetricField.UnitField) {
                metric.unit
            } else {
                metricToText(okrEditorMetricValue(metric, field))
            }
        case None => ""
    }
}

func okrEditorMetricValue(metric: OkrMetric, field: MetricField): Float64 {
    match (field) {
        case MetricField.Start => metric.start
        case MetricField.Current => metric.current
        case MetricField.Target => metric.target
        case MetricField.UnitField => 0.0
    }
}

/** 每帧（build 之前）：对齐草稿 + 推进 notes 防抖。 */
func okrEditorTick(store: AppStore, ui: OkrUiState, entry: OkrObjEntry, info: FrameInfo): Unit {
    okrEditorSyncDrafts(ui, entry)
    match (ui.peekField(okrEditorDraftNotes(entry.item.id))) {
        case Some(draft) => okrEditorNotesTick(store, ui, entry.item.id, draft, info)
        case None => ()
    }
}

/** 外部改动 → 草稿：只同步**当前没有在编辑**的字段，正在输入的那一处不被覆盖。 */
func okrEditorSyncDrafts(ui: OkrUiState, entry: OkrObjEntry): Unit {
    let target = ui.editTarget.value
    let objectiveId = entry.item.id
    if (target != "title") {
        okrSyncField(ui, okrEditorDraftTitle(objectiveId), entry.item.title)
    }
    for (kr in entry.krs) {
        let krId = kr.item.id
        if (target == okrEditorKrTarget(krId)) {
            continue
        }
        okrSyncField(ui, okrEditorDraftKrTitle(krId), kr.item.title)
        okrSyncField(ui, okrEditorDraftOwner(krId), kr.owner)
        for (field in METRIC_FIELDS) {
            okrSyncField(ui, okrEditorDraftMetric(krId, field), okrEditorMetricText(kr, field))
        }
    }
}

/* ------------------------------------------------------------ notes 防抖 */

/**
 * notes 的 600ms 防抖（`ObjectiveEditor.tsx:168-210` 的移植）。
 *
 * `elapsedMs` 是帧回调给的时间戳，视图不读系统时钟。两条判据分开：
 *   - 草稿这一帧变了 → 记下「最后一次输入时刻」，重新计时；
 *   - 草稿 ≠ 已提交值且静默 ≥ 600ms → 写库。
 * store 的值 ≠ 已提交值 = **外部改动**：覆盖草稿（与 Web 的 `notesCommittedRef` 同义）。
 */
func okrEditorNotesTick(store: AppStore, ui: OkrUiState, objectiveId: String, draft: State<String>,
    info: FrameInfo): Unit {
    let now = Int64(info.elapsedMs)
    let current = okrEditorNotesOf(store.state.value(), objectiveId)
    if (current != ui.notesCommitted.value) {
        ui.notesCommitted.value = current
        ui.notesSeen.value = current
        ui.notesTick.value = now
        if (draft.value != current) {
            draft.value = current
        }
        return
    }
    let text = draft.value
    if (text != ui.notesSeen.value) {
        ui.notesSeen.value = text
        ui.notesTick.value = now
    }
    if (text == ui.notesCommitted.value) {
        return
    }
    if (now - ui.notesTick.value >= OKR_NOTES_DEBOUNCE_MS) {
        okrEditorFlushNotes(store, ui, objectiveId, text)
    }
}

func okrEditorFlushNotes(store: AppStore, ui: OkrUiState, objectiveId: String, text: String): Unit {
    if (text == ui.notesCommitted.value) {
        return
    }
    ui.notesCommitted.value = text
    ui.notesSeen.value = text
    match (itemById(store.state.value(), objectiveId)) {
        case Some(item) => if (item.notes != text) {
            store.updateItem(objectiveId, ItemPatch().withNotes(text))
        }
        case None => ()
    }
}

/* ------------------------------------------------------------ 失焦提交 */

/**
 * 零尺寸的每帧钩子：`layout` 是唯一每帧都能拿到 `UiContext`（含 `focusId`）的地方，
 * 失焦提交靠它做「上一帧聚焦的字段 → 本帧不再聚焦」的比较（`OkrPage` 过去也是这么做的）。
 */
class OkrEditorWatch <: Widget {
    private let onLayout: (UiContext) -> Unit

    init(onLayout: (UiContext) -> Unit) {
        this.onLayout = onLayout
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size.zero()
    }

    public func layout(ctx: UiContext, _: Rect): Unit {
        onLayout(ctx)
    }

    public func draw(_: UiContext): Unit {}

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }

    public func participatesInLayout(): Bool {
        false
    }

    public func needsDetachedLayout(): Bool {
        true
    }
}

/** 编辑器自己声明的控件 id（铅笔按钮等不属于本页的焦点不触发任何提交）。 */
func okrEditorOwnsFocus(id: String): Bool {
    !id.isEmpty() && id.startsWith("okr-ed-")
}

func okrEditorBlurCommit(ctx: UiContext, store: AppStore, ui: OkrUiState, entry: OkrObjEntry): Unit {
    let current = if (okrEditorOwnsFocus(ctx.focusId)) {
        ctx.focusId
    } else {
        ""
    }
    let previous = ui.editorFocusTrack.value
    if (current == previous) {
        return
    }
    ui.editorFocusTrack.value = current
    if (previous.isEmpty()) {
        return
    }
    okrEditorCommitFocusId(store, ui, entry, previous)
}

func okrEditorCommitFocusId(store: AppStore, ui: OkrUiState, entry: OkrObjEntry, controlId: String): Unit {
    if (controlId == okrEditorTitleId()) {
        okrEditorCommitTitle(store, ui, entry.item.id, entry.item.title)
        return
    }
    if (controlId == okrEditorNotesId()) {
        match (ui.peekField(okrEditorDraftNotes(entry.item.id))) {
            case Some(draft) => okrEditorFlushNotes(store, ui, entry.item.id, draft.value)
            case None => ()
        }
        return
    }
    for (kr in entry.krs) {
        let krId = kr.item.id
        if (controlId == okrEditorKrTitleId(krId) || controlId == okrEditorOwnerId(krId)) {
            okrEditorCommitKr(store, ui, kr)
            return
        }
        for (field in METRIC_FIELDS) {
            if (controlId == okrEditorMetricId(krId, field)) {
                okrEditorCommitMetric(store, ui, kr)
                return
            }
        }
    }
}

func okrEditorCommitTitle(store: AppStore, ui: OkrUiState, objectiveId: String, original: String): Unit {
    match (ui.peekField(okrEditorDraftTitle(objectiveId))) {
        case Some(state) =>
            let draft = state.value.trim()
            if (draft.isEmpty()) {
                // 空标题不写库（`EditableTitle` 同义），把草稿还原成 store 的值。
                state.value = original
                return
            }
            if (draft != original) {
                store.updateItem(objectiveId, ItemPatch().withTitle(draft))
            }
            if (state.value != draft) {
                state.value = draft
            }
        case None => ()
    }
}

/** 标题回车：提交并收起（React `EditableTitle` 的 Enter → blur → commit → 退出编辑）。 */
func okrEditorCommitTitleAndClose(store: AppStore, ui: OkrUiState, entry: OkrObjEntry): Unit {
    okrEditorCommitTitle(store, ui, entry.item.id, entry.item.title)
    ui.editTarget.value = ""
}

/** KR 标题回车：整块提交并收起（与 `EditableTitle` 同义）。 */
func okrEditorCommitKrAndClose(store: AppStore, ui: OkrUiState, kr: OkrKrEntry): Unit {
    okrEditorCommitKr(store, ui, kr)
    ui.editTarget.value = ""
}

/** 一条 KR 的「整块提交」：标题 + 负责人 + 指标（切走 / 失焦 / Esc 都用它）。 */
func okrEditorCommitKr(store: AppStore, ui: OkrUiState, kr: OkrKrEntry): Unit {
    let krId = kr.item.id
    match (ui.peekField(okrEditorDraftKrTitle(krId))) {
        case Some(state) =>
            let draft = state.value.trim()
            if (draft.isEmpty()) {
                state.value = kr.item.title
            } else {
                if (draft != kr.item.title) {
                    store.updateItem(krId, ItemPatch().withTitle(draft))
                }
                if (state.value != draft) {
                    state.value = draft
                }
            }
        case None => ()
    }
    match (ui.peekField(okrEditorDraftOwner(krId))) {
        case Some(state) =>
            let draft = state.value.trim()
            if (draft != kr.owner) {
                let patch = ItemPatch()
                let okr = OkrPatch()
                let owner: ?String = if (draft.isEmpty()) {
                    None
                } else {
                    Some(draft)
                }
                okr.krOwner = SetValue<?String>.Value(owner)
                patch.okr = Some(okr)
                store.updateItem(krId, patch)
            }
            if (state.value != draft) {
                state.value = draft
            }
        case None => ()
    }
    okrEditorCommitMetric(store, ui, kr)
}

/**
 * 指标四格 → store。`pendingMetricPatch` 只合并**真的变了且能解析**的字段：
 * 与库里的值相同（用户没改）不会多写一条历史，非法数字则整格跳过（保留旧值）。
 */
func okrEditorCommitMetric(store: AppStore, ui: OkrUiState, kr: OkrKrEntry): Unit {
    let krId = kr.item.id
    let base = match (kr.metric) {
        case Some(value) => value
        case None => EMPTY_METRIC
    }
    let draft = MetricDraft(
        start: okrEditorDraftValue(ui, okrEditorDraftMetric(krId, MetricField.Start)),
        current: okrEditorDraftValue(ui, okrEditorDraftMetric(krId, MetricField.Current)),
        target: okrEditorDraftValue(ui, okrEditorDraftMetric(krId, MetricField.Target)),
        unit: okrEditorDraftValue(ui, okrEditorDraftMetric(krId, MetricField.UnitField))
    )
    let committed = metricToDraft(base)
    match (pendingMetricPatch(kr.metric, draft, committed)) {
        case Some(decision) =>
            store.setMetric(krId, decision.metric.start, decision.metric.target, decision.metric.current,
                decision.metric.unit)
            okrEditorSyncMetricDrafts(ui, krId, decision.metric)
        case None => okrEditorSyncMetricDrafts(ui, krId, base)
    }
}

func okrEditorSyncMetricDrafts(ui: OkrUiState, krId: String, metric: OkrMetric): Unit {
    okrSyncField(ui, okrEditorDraftMetric(krId, MetricField.Start), metricToText(metric.start))
    okrSyncField(ui, okrEditorDraftMetric(krId, MetricField.Current), metricToText(metric.current))
    okrSyncField(ui, okrEditorDraftMetric(krId, MetricField.Target), metricToText(metric.target))
    okrSyncField(ui, okrEditorDraftMetric(krId, MetricField.UnitField), metric.unit)
}

func okrEditorDraftValue(ui: OkrUiState, key: String): String {
    match (ui.peekField(key)) {
        case Some(state) => state.value
        case None => ""
    }
}

/* ------------------------------------------------------- 编辑目标切换 */

/**
 * 点铅笔：同一处再点一次 = 收起；换到别处 = 先提交当前这一处再展开新的。
 * 「同一时刻只允许一个编辑目标」就落在这个唯一入口上。
 */
func okrEditorSetTarget(store: AppStore, ui: OkrUiState, entry: OkrObjEntry, target: String): Unit {
    if (ui.editTarget.value == target) {
        okrEditorCommitTarget(store, ui, entry, target)
        ui.editTarget.value = ""
        return
    }
    okrEditorCommitTarget(store, ui, entry, ui.editTarget.value)
    // 新的编辑会话：`okrEditorInput` 靠它判断「这一次打开还没全选过」。
    ui.editSession.value = ui.editSession.value + 1
    ui.editTarget.value = target
    // 展开后把焦点送进新出现的输入框（`EditableTitle` 的 `autoFocus` 同义）：不请求焦点的话，
    // 键入的字符会落到那支铅笔按钮上，`Enter` 还会被按钮当成「激活」而立刻把编辑收起。
    let focusId = okrEditorTargetFocusId(target)
    if (!focusId.isEmpty()) {
        ui.editorFocus.request(focusId)
    }
}

/** Esc：取消当前编辑（草稿回退到 store 的值），不写库。 */
func okrEditorCancelTarget(ui: OkrUiState, entry: OkrObjEntry): Unit {
    ui.editTarget.value = ""
    okrEditorSyncDrafts(ui, entry)
    okrSyncField(ui, okrEditorDraftTitle(entry.item.id), entry.item.title)
    okrSyncField(ui, okrEditorDraftNotes(entry.item.id), entry.item.notes)
    ui.notesCommitted.value = entry.item.notes
    ui.notesSeen.value = entry.item.notes
    okrSyncField(ui, okrEditorDraftAdd(entry.item.id), "")
}

func okrEditorCommitTarget(store: AppStore, ui: OkrUiState, entry: OkrObjEntry, target: String): Unit {
    if (target.isEmpty()) {
        return
    }
    if (target == "title") {
        okrEditorCommitTitle(store, ui, entry.item.id, entry.item.title)
        return
    }
    if (target == "notes") {
        match (ui.peekField(okrEditorDraftNotes(entry.item.id))) {
            case Some(draft) => okrEditorFlushNotes(store, ui, entry.item.id, draft.value)
            case None => ()
        }
        return
    }
    if (target.startsWith("kr:")) {
        let krId = target["kr:".size..target.size]
        for (kr in entry.krs) {
            if (kr.item.id == krId) {
                okrEditorCommitKr(store, ui, kr)
                return
            }
        }
    }
}

/* ------------------------------------------------------------ Esc 返回 */

/**
 * Esc：字段内先「取消当前编辑」，再按一次才返回列表（`ObjectiveEditor.tsx:70-85`）。
 *
 * `EventHandler` 在子控件之前看到事件，所以输入框里的 Esc 也走这里；浮层（季度对话框 / 删除
 * 确认）是 overlay，按 CUI 的派发顺序先于整棵树收到事件，因此对话框里的 Esc 仍然是「关对话框」。
 */
func okrEditorEscape(ctx: UiContext, event: UiEvent, store: AppStore, ui: OkrUiState,
    entry: OkrObjEntry): Bool {
    let _ = ctx
    match (event) {
        case UiEvent.KeyDown(Key.Escape, isRepeat) where !isRepeat =>
            if (ui.editTarget.value.isEmpty()) {
                closeOkrEditor(store, ui)
            } else {
                okrEditorCancelTarget(ui, entry)
            }
            true
        case _ => false
    }
}

/**
 * 编辑页的图标按钮（26×26）：与 `IconButtonView` 同样的观感，但带**稳定 id 与语义节点**。
 *
 * 为什么自己画一个：`textura.ui.IconButtonView` 不注册 semantics（只有 `ButtonView` 会），
 * 它的焦点 id 还是构建序号派生的，测试既点不到也断言不了「铅笔 → 出现输入」。这里把 id、标签、
 * `Activate` 动作一起注册，点击路径（按下 / 抬起 / 焦点 / 悬停）与共享控件完全一致。
 */
class OkrEditorIconButton <: Widget {
    private let tokens: ThemeTokens
    private let id: String
    private let label: String
    private let glyph: IconGlyph
    private let danger: Bool
    private let isEnabled: Bool
    private let onClick: () -> Unit
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, id: String, label: String, glyph: IconGlyph, onClick: () -> Unit,
        danger!: Bool = false, enabled!: Bool = true) {
        this.tokens = tokens
        this.id = id
        this.label = label
        this.glyph = glyph
        this.danger = danger
        this.isEnabled = enabled
        this.onClick = onClick
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(min(26.0, max(available.w, 0.0)), min(26.0, max(available.h, 0.0)))
    }

    public func layout(ctx: UiContext, rect: Rect): Unit {
        frame = rect
        ctx.registerSemantics(
            SemanticsNode(id, Semantics(label: label, role: SemanticsRole.Button, enabled: isEnabled), rect,
                actions: [SemanticsAction.Activate]), perform: {action => match (action) {
                case SemanticsAction.Activate =>
                    if (isEnabled) {
                        onClick()
                        true
                    } else {
                        false
                    }
                case _ => false
            }}
        )
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        let radius = tokens.radius.md
        let hovered = isEnabled && ctx.isHovered(id)
        let pressed = isEnabled && ctx.isPressed(id)
        var ink = if (danger) {
            c.danger
        } else {
            c.textMuted
        }
        if (hovered || pressed) {
            if (danger) {
                fillRound(ctx, frame, radius, tint(c.danger, 12.0))
                ink = if (pressed) {
                    c.dangerStrongActive
                } else {
                    c.dangerStrong
                }
            } else {
                fillRound(ctx, frame, radius, c.surface2)
                ink = c.text
            }
        }
        if (!isEnabled) {
            ink = withOpacity(ink, 0.4)
        }
        let side = min(min(frame.w, frame.h), 16.0)
        paintSpec(ctx, glyph, Rect(frame.centerX() - side / 2.0, frame.centerY() - side / 2.0, side, side), ink)
        if (isEnabled && ctx.showFocusRing(id)) {
            focusRing(ctx, tokens, frame, radius)
        }
        if (hovered) {
            ctx.showTooltip(label, frame)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        if (!isEnabled) {
            return false
        }
        match (event) {
            case UiEvent.MouseMove(_, _) => claimHoverIfInside(ctx, event, frame, id, CursorShape.Interactive)
            case UiEvent.MouseDown(button, x, y) =>
                if (isPrimaryPointerButton(button) && frame.contains(x, y)) {
                    ctx.focus(id, viaKeyboard: false)
                    ctx.press(id)
                    return true
                }
            case UiEvent.MouseUp(button, x, y) =>
                if (isPrimaryPointerButton(button) && ctx.isPressed(id)) {
                    ctx.clearPress()
                    if (frame.contains(x, y)) {
                        onClick()
                        return true
                    }
                }
            case UiEvent.KeyDown(key, isRepeat) =>
                if (ctx.hasFocus(id) && !isRepeat) {
                    match (key) {
                        case Key.Enter | Key.Space =>
                            onClick()
                            return true
                        case _ => ()
                    }
                }
            case _ => ()
        }
        false
    }

    public func focusableId(): ?String {
        if (isEnabled) {
            Some(id)
        } else {
            None
        }
    }
}

/**
 * 跨帧的「全选只做一次」标记（普通对象，不进 `State` 版本号）。
 *
 * 每次展开一个编辑目标都会递增 `ui.editSession`，因此令牌 `<控件 id>#<会话号>` 在**新会话**
 * 里一定不同 —— 打开即全选（同 React `EditableTitle` 的 `select()`），而同一会话里不会再选
 * 第二次（否则每帧重选，第二个字符会把第一个字符替换掉）。
 */
class OkrEditorSelection {
    var token: String = ""
}

/* ------------------------------------------------------------ 输入控件 */

/**
 * `.input` 的盒模型（与 `textura.ui` 的 `Ui.textInput` 逐项一致：10/7 内边距、radius 8、
 * 1px 边框、聚焦换 accent 边框）。
 *
 * 这里不直接用 `Ui.textInput`，是因为它不暴露 `onSubmit`：编辑页的每个文本字段都要
 * 「Enter 立即写库」（`docs/OKR-EDIT-PLAN.md` §4.4），而 `TextField.onSubmit` 是唯一的
 * 提交钩子。样式逐项照抄，视觉与其它视图的 `.input` 相同。
 */
func okrEditorInputStyle(tokens: ThemeTokens): TextInputStyle {
    let c = tokens.color
    TextInputStyle(
        padding: LengthInsets(Length(10.0, LengthUnit.Vp), Length(7.0, LengthUnit.Vp)),
        textColor: c.text,
        placeholderColor: c.textFaint,
        cursorColor: c.accent,
        surface: SurfaceStyle(c.surface, border: c.border, radius: tokens.radius.md,
            borderWidth: tokens.metrics.borderWidth),
        focusedSurface: SurfaceStyle(c.surface, border: c.accent, radius: tokens.radius.md,
            borderWidth: tokens.metrics.borderWidth)
    )
}

/**
 * 单行输入框：Enter → `onSubmit`（IME 组词期间 Enter 由输入法确认，不触发提交）。
 *
 * `selectAll` 用于标题类字段（React `EditableTitle` 打开即全选）：第一次出现时全选一次，
 * 之后同一会话不再重复（否则每帧重选，连续输入只会剩最后一个字符）。
 */
func okrEditorInput(ui: OkrUiState, tokens: ThemeTokens, text: State<String>, id: String, placeholder: String,
    onSubmit: () -> Unit, selectAll!: Bool = false): Unit {
    let field = TextField(text, key: Some(id))
    field.style(okrEditorInputStyle(tokens))
    field.placeholder(placeholder)
    field.onSubmit {_ => onSubmit()}
    if (selectAll) {
        let token = "${id}#${ui.editSession.value}"
        if (ui.selection.token != token) {
            ui.selection.token = token
            field.selectAll()
        }
    }
    // `textStyle`/`height` 是 widget 修饰器：必须链在上一次调用的返回值上，
    // 否则同一帧会发出两个包装节点（界面上「下面又冒出一个一样的框」，DEVICE-NOTES §20）。
    let _ = field.textStyle(TextStyle(fontSize: fp(13.5))).height(34.0)
}

/* ------------------------------------------------------------------ 页面块 */


func okrEditorBody(store: AppStore, ui: OkrUiState, entry: OkrObjEntry, period: String, tokens: ThemeTokens,
    theme: Theme): Unit {
    VStack(spacing: vp(tokens.space.s4)) {
        OkrEditorWatch({ctx => okrEditorBlurCommit(ctx, store, ui, entry)})
        // 落地 `openOkrEditor` / `okrEditorSetTarget` 武装的焦点请求（零尺寸，每帧消费一次）。
        FocusOnceView(ui.editorFocus)
        okrEditorBar(store, ui, entry, period, tokens, theme)
        okrEditorHero(store, ui, entry, tokens, theme)
        okrEditorKrSection(store, ui, entry, period, tokens, theme)
        okrEditorExecSummary(entry, tokens)
        okrEditorActions(store, ui, entry, period, tokens, theme)
    }
        .hug()
        .fillWidth()
        .maxWidth(OKR_EDITOR_MAX_W)
}

/** 顶栏：返回 / 面包屑 / 保存状态（`.okr-editor-bar`）。 */
func okrEditorBar(store: AppStore, ui: OkrUiState, entry: OkrObjEntry, period: String, tokens: ThemeTokens,
    theme: Theme): Unit {
    let c = tokens.color
    let label = okrEditorSaveLabel(store, ui, entry)
    VStack(spacing: vp(tokens.space.s2)) {
        HStack(spacing: vp(tokens.space.s3)) {
            Ui.button(
                theme,
                "返回目标列表",
                {=> closeOkrEditor(store, ui)},
                variant: ButtonVariant.Ghost,
                size: ControlSize.Sm,
                iconLeft: IconGlyph.ChevronLeft
            )
            Label("${quarterLabel(period)} · 目标编辑")
                .fontSize(fp(12.0))
                .fontWeight(FontWeight(550))
                .foregroundColor(c.textMuted)
            Spacer()
            Label(label)
                .fontSize(fp(11.5))
                .foregroundColor(if (label == "保存失败") {
                    c.dangerInk
                } else {
                    c.textMuted
                })
        }
            .crossAxisAlignment(CrossAxisAlignment.Center)
            .hug()
            .fillWidth()
        Divider().foregroundColor(c.border)
    }.hug().fillWidth()
}

/** 保存状态：notes 还有未写的草稿时算「保存中…」，其余看 store 的落盘阶段。 */
func okrEditorSaveLabel(store: AppStore, ui: OkrUiState, entry: OkrObjEntry): String {
    let draft = okrEditorDraftValue(ui, okrEditorDraftNotes(entry.item.id))
    if (draft != ui.notesCommitted.value) {
        return "保存中…"
    }
    match (store.saveStatus()) {
        case SaveState.Error => "保存失败"
        case SaveState.Saving => "保存中…"
        case _ => "已保存"
    }
}

/* ------------------------------------------------------------------ 目标卡 */

func okrEditorCard(tokens: ThemeTokens, body!: () -> Unit): Unit {
    VStack(spacing: vp(tokens.space.s3)) {
        body()
    }
        .hug()
        .fillWidth()
        .padding(vp(tokens.space.s4))
        .background(tokens.color.surface, tokens.radius.lg)
        .border(tokens.color.border, width: tokens.metrics.borderWidth, radius: tokens.radius.lg)
        .shadow(okrEditorCardShadow(tokens), radius: tokens.radius.lg)
}

func okrEditorCardShadow(tokens: ThemeTokens): Array<Shadow> {
    [
        Shadow(color: tokens.shadow1.color, offsetY: tokens.shadow1.offsetY, offsetX: tokens.shadow1.offsetX,
            blur: tokens.shadow1.blur, spread: tokens.shadow1.spread),
        Shadow(color: tokens.shadow1Contact.color, offsetY: tokens.shadow1Contact.offsetY,
            offsetX: tokens.shadow1Contact.offsetX, blur: tokens.shadow1Contact.blur,
            spread: tokens.shadow1Contact.spread)
    ]
}

/** Hero：标题 / 领域 / 状态 / 信心 / 整体进度 / 备注 / 时间（`ObjectiveEditor.tsx:280-347`）。 */
func okrEditorHero(store: AppStore, ui: OkrUiState, entry: OkrObjEntry, tokens: ThemeTokens, theme: Theme): Unit {
    let c = tokens.color
    let objective = entry.item
    let target = ui.editTarget.value
    okrEditorCard(tokens) {
        =>
            if (target == "title") {
                HStack(spacing: vp(tokens.space.s2)) {
                    // 标题是「文档」字段但打开即全选 + 回车即收起（React `EditableTitle`）。
                    okrEditorInput(ui, tokens, ui.field(okrEditorDraftTitle(objective.id), objective.title),
                        okrEditorTitleId(), "一句话说明这条要达成什么",
                        {=> okrEditorCommitTitleAndClose(store, ui, entry)}, selectAll: true)
                }.hug().fillWidth()
            } else {
                HStack(spacing: vp(tokens.space.s2)) {
                    Label(objective.title)
                        .fontSize(fp(21.0))
                        .fontWeight(FontWeight(650))
                        .foregroundColor(c.text)
                        .wrap()
                        .flex()
                    okrEditorPencil(tokens, "title", "编辑目标标题") {
                        => okrEditorSetTarget(store, ui, entry, "title")
                    }
                }
                    .crossAxisAlignment(CrossAxisAlignment.Start)
                    .hug()
                    .fillWidth()
            }
            FlowRow {
                okrEditorField(
                    tokens,
                    "领域",
                    "area",
                    target == "area",
                    okrEditorAreaText(entry),
                    picker: {=>
                        FlowRow {
                            okrEditorChoice(theme, "未归属 Area", entry.item.areaId.isNone(),
                                {=> okrEditorSetArea(store, ui, entry, Option<String>.None)})
                            for (area in store.state.value().areas) {
                                okrEditorChoice(theme, area.name, entry.item.areaId == Some(area.id),
                                    {=> okrEditorSetArea(store, ui, entry, Some(area.id))})
                            }
                        }.spacing(vp(6.0))
                    },
                    onEdit: {=> okrEditorSetTarget(store, ui, entry, "area")}
                )
                okrEditorField(
                    tokens,
                    "状态",
                    "status",
                    target == "status",
                    okrStatusLabel(objective.status),
                    picker: {=>
                        FlowRow {
                            for (status in OKR_KR_STATUSES) {
                                okrEditorChoice(theme, okrStatusLabel(status), status == objective.status,
                                    {=> okrEditorSetStatus(store, ui, entry, status)})
                            }
                        }.spacing(vp(6.0))
                    },
                    onEdit: {=> okrEditorSetTarget(store, ui, entry, "status")}
                )
                okrEditorField(
                    tokens,
                    "信心",
                    "confidence",
                    target == "confidence",
                    "${entry.confidence} / 10",
                    picker: {=>
                        FlowRow {
                            var score: Int64 = 1
                            while (score <= 10) {
                                let picked = score
                                okrEditorChoice(theme, "${picked}", picked == entry.confidence,
                                    {=> okrEditorSetConfidence(store, ui, entry, picked)})
                                score += 1
                            }
                        }.spacing(vp(4.0))
                    },
                    onEdit: {=> okrEditorSetTarget(store, ui, entry, "confidence")}
                )
            }.spacing(vp(tokens.space.s4), vp(tokens.space.s3))
            VStack(spacing: vp(4.0)) {
                Label("整体进度").fontSize(fp(11.0)).foregroundColor(c.textMuted)
                Ui.progress(theme, Float32(entry.progress), tone: okrProgressTone(entry.progress, false),
                    size: ControlSize.Md, showLabel: true)
            }.hug().fillWidth()
            okrEditorNotesBlock(store, ui, entry, tokens, theme)
            HStack(spacing: vp(tokens.space.s4)) {
                Label("创建 ${okrEditorDateOnly(objective.createdAt)}")
                    .fontSize(fp(11.5))
                    .foregroundColor(c.textMuted)
                Label("更新 ${okrEditorDateOnly(objective.updatedAt)}")
                    .fontSize(fp(11.5))
                    .foregroundColor(c.textMuted)
            }.hug()
    }
}

func okrEditorNotesBlock(store: AppStore, ui: OkrUiState, entry: OkrObjEntry, tokens: ThemeTokens,
    theme: Theme): Unit {
    let c = tokens.color
    let objective = entry.item
    let editing = ui.editTarget.value == "notes"
    VStack(spacing: vp(6.0)) {
        HStack(spacing: vp(tokens.space.s2)) {
            Label("备注").fontSize(fp(11.0)).foregroundColor(c.textMuted)
            Spacer()
            okrEditorPencil(tokens, "notes", if (editing) {
                "收起备注"
            } else {
                "编辑备注"
            }) {
                => okrEditorSetTarget(store, ui, entry, "notes")
            }
        }.crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
        if (editing) {
            Ui.textArea(theme, ui.field(okrEditorDraftNotes(objective.id), objective.notes),
                key: okrEditorNotesId(), placeholder: "为什么这是本季度最重要的事？", height: 92.0)
            Label("停止输入 600ms 后保存；失焦立即提交。").fontSize(fp(11.0)).foregroundColor(c.textFaint)
        } else if (objective.notes.isEmpty()) {
            Label("（还没有备注）").fontSize(fp(13.0)).foregroundColor(c.textFaint)
        } else {
            Label(objective.notes).fontSize(fp(13.0)).foregroundColor(c.textMuted).wrap()
        }
    }.hug().fillWidth()
}

/** 一个「标签 + 值（或选择器）+ 铅笔」的小字段（`.okr-editor-field`）。 */
func okrEditorField(tokens: ThemeTokens, label: String, kind: String, editing: Bool, value: String,
    picker!: () -> Unit, onEdit!: () -> Unit): Unit {
    let c = tokens.color
    VStack(spacing: vp(4.0)) {
        Label(label).fontSize(fp(11.0)).foregroundColor(c.textMuted)
        if (editing) {
            HStack(spacing: vp(6.0)) {
                picker()
                okrEditorPencil(tokens, kind, "收起${label}", onEdit)
            }
                .crossAxisAlignment(CrossAxisAlignment.Center)
                .hug()
        } else {
            HStack(spacing: vp(6.0)) {
                Label(value).fontSize(fp(13.0)).foregroundColor(c.text)
                okrEditorPencil(tokens, kind, "编辑${label}", onEdit)
            }.crossAxisAlignment(CrossAxisAlignment.Center).hug()
        }
    }.hug().minWidth(168.0)
}

func okrEditorPencil(tokens: ThemeTokens, kind: String, tooltip: String, action: () -> Unit): Unit {
    OkrEditorIconButton(tokens, okrEditorPencilId(kind), tooltip, IconGlyph.Edit, action)
}

func okrEditorAreaText(entry: OkrObjEntry): String {
    match (entry.area) {
        case Some(area) => area.name
        case None => "未归属 Area"
    }
}

/** 选择项按钮（CUI 无原生 select；与 `QuarterDialog` 的选法同语义）：选中用 Primary。 */
func okrEditorChoice(theme: Theme, label: String, selected: Bool, action: () -> Unit): Unit {
    Ui.button(
        theme,
        label,
        action,
        variant: if (selected) {
            ButtonVariant.Primary
        } else {
            ButtonVariant.Secondary
        },
        size: ControlSize.Sm
    )
}

func okrEditorSetArea(store: AppStore, ui: OkrUiState, entry: OkrObjEntry, areaId: ?String): Unit {
    store.updateItem(entry.item.id, ItemPatch().withAreaId(areaId))
    ui.editTarget.value = ""
}

func okrEditorSetStatus(store: AppStore, ui: OkrUiState, entry: OkrObjEntry, status: ItemStatus): Unit {
    store.setStatus(entry.item.id, status)
    ui.editTarget.value = ""
}

func okrEditorSetConfidence(store: AppStore, ui: OkrUiState, entry: OkrObjEntry, confidence: Int64): Unit {
    store.setConfidence(entry.item.id, clampConfidence(confidence))
    ui.editTarget.value = ""
}

/** 日期显示：`2026-03-16T10:00:00…` → `2026-03-16`。 */
func okrEditorDateOnly(text: String): String {
    if (text.isEmpty()) {
        return "—"
    }
    let parts = text.split("T")
    if (parts.size > 0 && !parts[0].isEmpty()) {
        parts[0]
    } else {
        text
    }
}

/* ------------------------------------------------------------------ KR 区 */

func okrEditorKrSection(store: AppStore, ui: OkrUiState, entry: OkrObjEntry, period: String,
    tokens: ThemeTokens, theme: Theme): Unit {
    let c = tokens.color
    VStack(spacing: vp(0.0)) {
        HStack(spacing: vp(tokens.space.s2)) {
            Label("关键结果 · ${entry.krs.size}")
                .fontSize(fp(13.5))
                .fontWeight(FontWeight(650))
                .foregroundColor(c.text)
            Spacer()
            Label("点铅笔展开该行的全部字段")
                .fontSize(fp(11.0))
                .foregroundColor(c.textMuted)
        }
            .crossAxisAlignment(CrossAxisAlignment.Center)
            .hug()
            .fillWidth()
            .padding(vp(tokens.space.s4), vp(tokens.space.s3), vp(tokens.space.s4), vp(tokens.space.s3))
        Divider().foregroundColor(c.border)
        VStack(spacing: vp(0.0)) {
            if (entry.krs.size == 0) {
                Label("还没有关键结果。用一个可量化的结果来支撑这个目标，例如「NPS 从 42 提升到 60」。")
                    .fontSize(fp(12.5))
                    .foregroundColor(c.textMuted)
                    .wrap()
                    .padding(vp(tokens.space.s4), vp(tokens.space.s3), vp(tokens.space.s4), vp(tokens.space.s3))
            }
            var index: Int64 = 0
            for (kr in entry.krs) {
                okrEditorKrRow(store, ui, entry, kr, index, Int64(entry.krs.size), tokens, theme)
                index += 1
            }
        }.hug().fillWidth()
        Divider().foregroundColor(c.border)
        okrEditorAddKr(store, ui, entry, period, tokens, theme)
    }
        .hug()
        .fillWidth()
        .background(c.surface, tokens.radius.lg)
        .border(c.border, width: tokens.metrics.borderWidth, radius: tokens.radius.lg)
        .shadow(okrEditorCardShadow(tokens), radius: tokens.radius.lg)
}

/** 一条 KR：默认只读摘要 + 铅笔 / 上移 / 下移 / 删除；展开后是该行的完整编辑。 */
func okrEditorKrRow(store: AppStore, ui: OkrUiState, entry: OkrObjEntry, kr: OkrKrEntry, index: Int64,
    count: Int64, tokens: ThemeTokens, theme: Theme): Unit {
    let c = tokens.color
    let krId = kr.item.id
    let editing = ui.editTarget.value == okrEditorKrTarget(krId)
    VStack(spacing: vp(tokens.space.s2)) {
        HStack(spacing: vp(tokens.space.s2)) {
            Label(pad2(index + 1))
                .fontSize(fp(10.5))
                .fontFamily(fontMono())
                .foregroundColor(c.textFaint)
            if (editing) {
                Label("关键结果标题").fontSize(fp(12.5)).fontWeight(FontWeight(600)).foregroundColor(c.text).flex()
            } else {
                Label(kr.item.title)
                    .fontSize(fp(13.5))
                    .fontWeight(FontWeight(600))
                    .foregroundColor(c.text)
                    .wrap()
                    .flex()
            }
            if (!editing) {
                okrEditorKrBadges(theme, kr)
                Label("${kr.progress}%")
                    .fontSize(fp(11.0))
                    .fontFamily(fontMono())
                    .foregroundColor(c.textMuted)
                Label("信心 ${kr.confidence}/10").fontSize(fp(11.0)).foregroundColor(c.textMuted)
            }
            OkrEditorIconButton(tokens, okrEditorKrPencilId(krId), if (editing) {
                "收起这条关键结果"
            } else {
                "编辑这条关键结果"
            }, if (editing) {
                IconGlyph.Close
            } else {
                IconGlyph.Edit
            }, {=> okrEditorSetTarget(store, ui, entry, okrEditorKrTarget(krId))})
            OkrEditorIconButton(tokens, "okr-ed-up-${krId}", "上移", IconGlyph.ChevronLeft,
                {=> store.moveItem(krId, Some(entry.item.id), Some(index - 1))}, enabled: index > 0)
            OkrEditorIconButton(tokens, "okr-ed-down-${krId}", "下移", IconGlyph.ChevronRight,
                {=> store.moveItem(krId, Some(entry.item.id), Some(index + 1))}, enabled: index < count - 1)
            OkrEditorIconButton(tokens, "okr-ed-del-${krId}", "删除这条关键结果", IconGlyph.Trash, {=>
                ui.confirmKr.value = krId
                ui.confirmOpen.value = true
            }, danger: true)
        }
            .crossAxisAlignment(CrossAxisAlignment.Center)
            .hug()
            .fillWidth()
        if (editing) {
            // 标题输入整行：`TextField` 会占满可用宽度，和按钮挤在同一行会把按钮挤成 0 宽。
            okrEditorInput(ui, tokens, ui.field(okrEditorDraftKrTitle(krId), kr.item.title),
                okrEditorKrTitleId(krId), "可量化的结果，例如「把首周留存提升到 45%」",
                {=> okrEditorCommitKrAndClose(store, ui, kr)}, selectAll: true)
            okrEditorKrDetail(store, ui, entry, kr, tokens, theme)
        } else {
            HStack(spacing: vp(tokens.space.s2)) {
                Label(okrEditorMetricSummary(kr))
                    .fontSize(fp(11.5))
                    .fontFamily(fontMono())
                    .foregroundColor(c.textMuted)
                Label(if (kr.owner.isEmpty()) {
                    "未指派"
                } else {
                    kr.owner
                }).fontSize(fp(11.5)).foregroundColor(c.textFaint)
                Label(okrEditorExecSummaryText(kr)).fontSize(fp(11.5)).foregroundColor(c.textMuted)
            }.hug()
        }
    }
        .hug()
        .fillWidth()
        .padding(vp(tokens.space.s4), vp(tokens.space.s3), vp(tokens.space.s4), vp(tokens.space.s3))
}

func okrEditorKrBadges(theme: Theme, kr: OkrKrEntry): Unit {
    if (kr.behind) {
        Ui.badge(theme, "落后", tone: BadgeTone.Danger, dot: true)
    }
    if (kr.lacksGrip()) {
        Ui.badge(theme, "缺少抓手", tone: BadgeTone.Warn, dot: true)
    }
    Ui.badge(theme, okrStatusLabel(kr.item.status), tone: okrStatusTone(kr.item.status))
}

func okrEditorMetricSummary(kr: OkrKrEntry): String {
    formatMetric(kr.metric)
}

func okrEditorExecSummaryText(kr: OkrKrEntry): String {
    if (kr.execs.size == 0) {
        "尚未关联执行项"
    } else {
        "执行项 ${kr.execs.size}"
    }
}

/** 展开态：标题已在上方，这里是指标四格 / 负责人 / 状态 / 信心 / 关联 / 执行项 / 完成。 */
func okrEditorKrDetail(store: AppStore, ui: OkrUiState, entry: OkrObjEntry, kr: OkrKrEntry, tokens: ThemeTokens,
    theme: Theme): Unit {
    let c = tokens.color
    let krId = kr.item.id
    let _ = entry
    VStack(spacing: vp(tokens.space.s3)) {
        FlowRow {
            for (field in METRIC_FIELDS) {
                VStack(spacing: vp(4.0)) {
                    Label(okrEditorMetricLabel(field)).fontSize(fp(11.0)).foregroundColor(c.textMuted)
                    okrEditorInput(ui, tokens, ui.field(okrEditorDraftMetric(krId, field),
                        okrEditorMetricText(kr, field)), okrEditorMetricId(krId, field),
                        if (field == MetricField.UnitField) {
                            "例如 %"
                        } else {
                            "0"
                        }, {=> okrEditorCommitMetric(store, ui, kr)})
                }.hug().width(if (field == MetricField.UnitField) {
                    96.0
                } else {
                    110.0
                })
            }
        }.spacing(vp(tokens.space.s2), vp(tokens.space.s2))
        HStack(spacing: vp(tokens.space.s3)) {
            VStack(spacing: vp(4.0)) {
                Label("负责人").fontSize(fp(11.0)).foregroundColor(c.textMuted)
                // 负责人是「文档」字段：打开时把旧值全选，输入即替换（React `TextInput` 的 caret 行为）；
                // 提交后行仍保持展开（与指标格一致）。
                okrEditorInput(ui, tokens, ui.field(okrEditorDraftOwner(krId), kr.owner), okrEditorOwnerId(krId),
                    "未指派", {=> okrEditorCommitKr(store, ui, kr)}, selectAll: true)
            }.hug().width(180.0)
            VStack(spacing: vp(4.0)) {
                Label("状态").fontSize(fp(11.0)).foregroundColor(c.textMuted)
                FlowRow {
                    for (status in OKR_KR_STATUSES) {
                        okrEditorChoice(theme, okrStatusLabel(status), status == kr.item.status) {
                            => store.setStatus(krId, status)
                        }
                    }
                }.spacing(vp(4.0))
            }.hug().flex()
        }
            .crossAxisAlignment(CrossAxisAlignment.Start)
            .hug()
            .fillWidth()
        HStack(spacing: vp(tokens.space.s2)) {
            Label("信心").fontSize(fp(11.0)).foregroundColor(c.textMuted)
            FlowRow {
                var score: Int64 = 1
                while (score <= 10) {
                    let picked = score
                    okrEditorChoice(theme, "${picked}", picked == kr.confidence) {
                        => store.setConfidence(krId, picked)
                    }
                    score += 1
                }
            }.spacing(vp(4.0))
            Spacer()
        }
            .crossAxisAlignment(CrossAxisAlignment.Center)
            .hug()
            .fillWidth()
        HStack(spacing: vp(tokens.space.s2)) {
            Ui.button(theme, "关联执行项", {=> openLinkDialog(ui, store, krId)},
                variant: ButtonVariant.Secondary, size: ControlSize.Sm, iconLeft: IconGlyph.Link)
            Ui.button(
                theme,
                if (kr.item.status == ItemStatus.Done) {
                    "标记未完成"
                } else {
                    "标记完成"
                },
                {=> store.toggleDone(krId)},
                variant: ButtonVariant.Secondary,
                size: ControlSize.Sm,
                iconLeft: IconGlyph.Check
            )
            Spacer()
        }.crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
        if (kr.execs.size > 0) {
            VStack(spacing: vp(4.0)) {
                for (exec in kr.execs) {
                    okrEditorExecRow(store, exec, tokens, theme)
                }
            }.hug().fillWidth()
        }
    }.hug().fillWidth()
}

/** 执行项一行：勾选即完成，右侧解绑（与列表页的勾选框同义）。 */
func okrEditorExecRow(store: AppStore, exec: OkrExecEntry, tokens: ThemeTokens, theme: Theme): Unit {
    let c = tokens.color
    let done = exec.item.status == ItemStatus.Done
    HStack(spacing: vp(tokens.space.s2)) {
        Ui.button(
            theme,
            exec.item.title,
            {=> store.toggleDone(exec.item.id)},
            variant: if (done) {
                ButtonVariant.Ghost
            } else {
                ButtonVariant.Secondary
            },
            size: ControlSize.Sm,
            iconLeft: if (done) {
                Some(IconGlyph.Check)
            } else {
                Option<IconGlyph>.None
            }
        )
        Label(okrStatusLabel(exec.item.status)).fontSize(fp(11.0)).foregroundColor(c.textMuted)
        Label(okrEditorDateOnly(exec.item.updatedAt)).fontSize(fp(11.0)).foregroundColor(c.textFaint)
        Spacer()
        OkrEditorIconButton(tokens, "okr-ed-unlink-${exec.item.id}", "解除关联", IconGlyph.Close, {=>
            match (exec.edgeId) {
                case Some(edgeId) => store.deleteEdge(edgeId)
                case None => ()
            }
        })
    }.crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
    _ = c
}

func okrEditorMetricLabel(field: MetricField): String {
    match (field) {
        case MetricField.Start => "起点"
        case MetricField.Current => "当前"
        case MetricField.Target => "目标"
        case MetricField.UnitField => "单位"
    }
}

/** 新增关键结果：默认一个按钮，点开才出现输入；Enter 创建（信心 5），创建后收起。 */
func okrEditorAddKr(store: AppStore, ui: OkrUiState, entry: OkrObjEntry, period: String, tokens: ThemeTokens,
    theme: Theme): Unit {
    let c = tokens.color
    let editing = ui.editTarget.value == "add-kr"
    VStack(spacing: vp(6.0)) {
        if (editing) {
            // 输入框整行（`TextField` 占满可用宽度），按钮另起一行。
            okrEditorInput(ui, tokens, ui.field(okrEditorDraftAdd(entry.item.id), ""), okrEditorAddId(),
                "新增关键结果，回车创建（默认信心 5）…",
                {=> okrEditorCreateKeyResult(store, ui, entry, period)})
            HStack(spacing: vp(tokens.space.s2)) {
                Ui.button(theme, "添加", {=> okrEditorCreateKeyResult(store, ui, entry, period)},
                    variant: ButtonVariant.Primary, size: ControlSize.Sm,
                    enabled: !okrEditorDraftValue(ui, okrEditorDraftAdd(entry.item.id)).trim().isEmpty())
                Ui.button(theme, "取消", {=> ui.editTarget.value = ""}, variant: ButtonVariant.Ghost,
                    size: ControlSize.Sm)
                Spacer()
            }.crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
        } else {
            HStack(spacing: vp(tokens.space.s2)) {
                Ui.button(theme, "新增关键结果", {=> okrEditorSetTarget(store, ui, entry, "add-kr")},
                    variant: ButtonVariant.Ghost, size: ControlSize.Sm, iconLeft: IconGlyph.Plus)
                Spacer()
                Label("Enter 创建 · 默认信心 5").fontSize(fp(11.0)).foregroundColor(c.textFaint)
            }.crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
        }
    }.hug().fillWidth().padding(vp(tokens.space.s4), vp(tokens.space.s2), vp(tokens.space.s4), vp(tokens.space.s3))
    _ = c
}

/** Enter / 「添加」：创建 KR（信心 5），清空输入并收起（`ObjectiveEditor.tsx:212-225`）。 */
func okrEditorCreateKeyResult(store: AppStore, ui: OkrUiState, entry: OkrObjEntry, period: String): Unit {
    let title = okrEditorDraftValue(ui, okrEditorDraftAdd(entry.item.id))
    if (title.trim().isEmpty()) {
        return
    }
    let _ = createOkrKeyResult(store, ui, entry, title, period)
    okrSyncField(ui, okrEditorDraftAdd(entry.item.id), "")
    ui.editTarget.value = ""
}

/* ------------------------------------------------------------------ 汇总 / 操作 */

/** 执行项概览：关联 N · 已完成 M（跨 KR 按 item id 去重，与 `summarizeEditor` 同义）。 */
func okrEditorExecSummary(entry: OkrObjEntry, tokens: ThemeTokens): Unit {
    let c = tokens.color
    let seen = ArrayList<String>()
    var done: Int64 = 0
    for (kr in entry.krs) {
        for (exec in kr.execs) {
            var known = false
            for (id in seen) {
                if (id == exec.item.id) {
                    known = true
                }
            }
            if (known) {
                continue
            }
            seen.add(exec.item.id)
            if (exec.item.status == ItemStatus.Done) {
                done += 1
            }
        }
    }
    // 先落成不可变值再进构建闭包：`CUI` 的 body 是闭包，捕获 `var` 会编译不过。
    let linked = seen.size
    let doneCount = done
    let line = "关联执行项 ${linked} · 已完成 ${doneCount}"
    let hint = if (linked == 0) {
        "还没有关联执行项。在上面每条关键结果里点「关联执行项」，把甘特 / GTD 里的项目与行动挂上来。"
    } else {
        "明细在每条关键结果下；勾选可直接标记完成。"
    }
    VStack(spacing: vp(4.0)) {
        HStack(spacing: vp(6.0)) {
            IconView(IconGlyph.Link, side: 14.0, color: c.textMuted)
            Label(line).fontSize(fp(12.5)).fontWeight(FontWeight(550)).foregroundColor(c.text)
        }.hug()
        Label(hint).fontSize(fp(11.5)).foregroundColor(c.textMuted).wrap()
    }
        .hug()
        .fillWidth()
        .padding(vp(tokens.space.s4), vp(tokens.space.s3), vp(tokens.space.s4), vp(tokens.space.s3))
        .background(c.surface, tokens.radius.lg)
        .border(c.border, width: tokens.metrics.borderWidth, radius: tokens.radius.lg)
        .shadow(okrEditorCardShadow(tokens), radius: tokens.radius.lg)
}

/** 目标操作：移动季度 / 复制 / 删除（对话框复用 `okr_dialogs.cj`）。 */
func okrEditorActions(store: AppStore, ui: OkrUiState, entry: OkrObjEntry, period: String, tokens: ThemeTokens,
    theme: Theme): Unit {
    let _ = store
    let _ = tokens
    HStack(spacing: vp(8.0)) {
        Ui.button(theme, "移动到其他季度", {=> openOkrQuarterDialog(ui, period, "move", entry.item.id)},
            variant: ButtonVariant.Secondary, size: ControlSize.Sm, iconLeft: IconGlyph.Calendar)
        Ui.button(theme, "复制为新季度目标", {=> openOkrQuarterDialog(ui, period, "copy", entry.item.id)},
            variant: ButtonVariant.Secondary, size: ControlSize.Sm, iconLeft: IconGlyph.Plus)
        Ui.button(theme, "删除目标", {=>
            ui.confirmObjective.value = entry.item.id
            ui.confirmOpen.value = true
        }, variant: ButtonVariant.Danger, size: ControlSize.Sm, iconLeft: IconGlyph.Trash)
        Spacer()
    }.crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
}

/* ------------------------------------------------------------------ 空态 */

/** 目标不存在 / 已被删除：空态 + 返回按钮，不白屏。 */
func okrEditorMissingPage(store: AppStore, ui: OkrUiState, tokens: ThemeTokens, theme: Theme): Unit {
    let _ = tokens
    VStack(spacing: vp(16.0)) {
        Ui.emptyState(theme, "目标不存在或已被删除",
            description: "这个目标可能已经被删除，或链接里的 id 并不是一个目标。", glyph: IconGlyph.Edit)
        Ui.button(theme, "返回目标列表", {=> closeOkrEditor(store, ui)}, variant: ButtonVariant.Secondary,
            size: ControlSize.Sm)
    }.hug().fillWidth().maxWidth(OKR_EDITOR_MAX_W)
}
