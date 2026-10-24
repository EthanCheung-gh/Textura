package textura.views.okr

import std.collection.ArrayList
import std.unicode.*
import cui.*
import textura.core.data.{Area, EdgeType, Item, ItemKind, ItemStatus, Metric, NewItemInput, NoticeTone, ViewContext,
    Workspace, areaById, itemById}
import textura.ui.*
import textura.views.okr.logic.{OkrSchedule, executionItemsOf, formatSchedule, matchesQuery, quarterLabel}

/*
 * OKR 页的浮层：新建目标 / 新建季度 / 关联执行项 / 目标更多操作 / KR 状态 / 删除确认。
 *
 * 全部用 `textura.ui` 的 `Ui.modal`（`ui.css:450-537`）：Esc 关闭、点遮罩关闭、
 * 打开期间阻断下层交互；页脚按钮与主体控件都是共享控件，因此键盘可达。
 */

/** 页面浮层的总入口（`render` 在页面之后调用，`Ui.modal` 自己注册 Overlay）。 */
func okrDialogs(ctx: ViewContext, ui: OkrUiState, page: OkrPage): Unit {
    let tokens = page.tokens
    let c = tokens.color
    let theme = page.theme
    let workspace = ctx.store.state.value()
    newObjectiveDialog(ctx, ui, page, theme, tokens, c)
    quarterDialog(ctx, ui, page, theme, tokens, c)
    linkDialog(ctx, ui, page, theme, tokens, c, workspace)
    menuDialog(ctx, ui, page, theme, tokens, c)
    statusDialog(ctx, ui, page, theme, tokens, c)
    confirmDialogs(ctx, ui, page, theme, tokens, c)
    // 卡片画布上的行内编辑（标题 / 指标 / 负责人 / 新增 KR）。
    okrPromptDialog(ctx, ui, page)
}

/** 新建季度目标（`OkrPage.tsx` 的 objective modal，宽 560）。 */
func newObjectiveDialog(ctx: ViewContext, ui: OkrUiState, page: OkrPage, theme: Theme, tokens: ThemeTokens,
    c: TokenColors): Unit {
    if (!ui.objectiveOpen.value) {
        return
    }
    let workspace = ctx.store.state.value()
    Ui.modal(
        theme,
        ui.objectiveOpen,
        {=> ui.objectiveOpen.value = false},
        title: "新建季度目标",
        description: "周期 ${quarterLabel(page.data.period)} · 先写定性目标，随后补充可量化的 KR",
        width: 560.0,
        footer: {=>
            Ui.button(theme, "取消", {=> ui.objectiveOpen.value = false}, variant: ButtonVariant.Ghost)
            Ui.button(theme, "创建目标", {=> submitObjective(ctx, ui, page)}, variant: ButtonVariant.Primary)
        }
    ) { =>
        Ui.field(theme, label: "目标（定性描述）", required: true, error: ui.objectiveError.value) {
            Ui.textInput(theme, ui.objectiveTitle, key: "okr-dlg-objective-title",
                placeholder: "例如：让新用户在第一周就爱上织理")
        }
        Ui.field(theme, label: "归属 Area", hint: "决定目标在侧栏 Area 下的归属。") {
            HStack(spacing: vp(6.0)) {
                areaChoice(theme, tokens, ui, "", "未归属 Area")
                for (area in workspace.areas) {
                    areaChoice(theme, tokens, ui, area.id, area.name)
                }
            }.hug()
        }
        Ui.field(theme, label: "备注（可选）") {
            Ui.textArea(theme, ui.objectiveNotes, key: "okr-dlg-objective-notes", height: 60.0,
                placeholder: "为什么这是本季度最重要的事？")
        }
        let _ = c
    }
}

func areaChoice(theme: Theme, tokens: ThemeTokens, ui: OkrUiState, id: String, label: String): Unit {
    let selected = ui.objectiveArea.value == id
    Ui.button(
        theme,
        label,
        {=> ui.objectiveArea.value = id},
        variant: if (selected) {
            ButtonVariant.Primary
        } else {
            ButtonVariant.Secondary
        },
        size: ControlSize.Sm
    )
}

func submitObjective(ctx: ViewContext, ui: OkrUiState, page: OkrPage): Unit {
    let title = ui.objectiveTitle.value.trim()
    if (title.isEmpty()) {
        ui.objectiveError.value = "先写下一句定性的季度目标"
        return
    }
    let area = ui.objectiveArea.value
    let created = ctx.store.createItem(
        NewItemInput(
            ItemKind.Objective,
            title,
            notes: ui.objectiveNotes.value.trim(),
            status: Some(ItemStatus.Active),
            areaId: if (area.isEmpty()) {
                None
            } else {
                Some(area)
            },
            okr: page.okrBlock(page.data.period, 5)
        )
    )
    ctx.store.select(created.id)
    ui.objectiveOpen.value = false
    ctx.store.notify("季度目标已创建", tone: NoticeTone.Success)
}

/** 年份 + 季度选择（`QuarterDialog.tsx`，宽 460）。 */
func quarterDialog(ctx: ViewContext, ui: OkrUiState, page: OkrPage, theme: Theme, tokens: ThemeTokens,
    c: TokenColors): Unit {
    if (!ui.quarterOpen.value) {
        return
    }
    let mode = ui.quarterMode.value
    let title = if (mode == "copy") {
        "复制为新季度目标"
    } else if (mode == "move") {
        "移动目标到其他季度"
    } else {
        "新建季度"
    }
    let description = if (mode == "copy") {
        "复制目标与全部 KR；KR 的当前值会重置为起点，执行项关联不会复制。"
    } else if (mode == "move") {
        "目标与它的 KR 会一起移动到新季度。"
    } else {
        "选择要切换到的季度周期。新建季度后可以立即创建目标。"
    }
    let confirmLabel = if (mode == "copy") {
        "复制"
    } else if (mode == "move") {
        "移动"
    } else {
        "切换到该季度"
    }
    let current = periodFromParts(ui.quarterYear.value, ui.quarterIndex.value)
    let quarterIndex = State<Int64>(ui.quarterIndex.value - 1)
    Ui.modal(
        theme,
        ui.quarterOpen,
        {=> ui.quarterOpen.value = false},
        title: title,
        description: description,
        width: 460.0,
        footer: {=>
            Ui.button(theme, "取消", {=> ui.quarterOpen.value = false}, variant: ButtonVariant.Ghost)
            Ui.button(
                theme,
                confirmLabel,
                {=>
                    ui.quarterOpen.value = false
                    confirmQuarter(ctx, ui, page, periodFromParts(ui.quarterYear.value, ui.quarterIndex.value))
                },
                variant: ButtonVariant.Primary
            )
        }
    ) { =>
        HStack(spacing: vp(OKR_S4)) {
            VStack(spacing: vp(6.0)) {
                ModalCaption(tokens, "年份")
                HStack(spacing: vp(6.0)) {
                    Ui.iconButton(theme, IconGlyph.ChevronLeft, {=> ui.quarterYear.value = ui.quarterYear.value - 1},
                        size: ControlSize.Sm, tooltip: "上一年")
                    Label("${ui.quarterYear.value}").fontSize(fp(13.0)).foregroundColor(c.text)
                    Ui.iconButton(theme, IconGlyph.ChevronRight, {=> ui.quarterYear.value = ui.quarterYear.value + 1},
                        size: ControlSize.Sm, tooltip: "下一年")
                }.hug()
            }.hug()
            VStack(spacing: vp(6.0)) {
                ModalCaption(tokens, "季度")
                Ui.segmented(theme, ["Q1", "Q2", "Q3", "Q4"], quarterIndex, size: ControlSize.Sm)
            }.hug()
            Spacer()
        }.hug().fillWidth()
        Label("目标周期将设为 ${quarterLabel(current)}。")
            .fontSize(fp(11.5)).foregroundColor(c.textMuted)
        let _ = c
    }
}

func ModalCaption(tokens: ThemeTokens, text: String): Unit {
    Label(text).fontSize(fp(11.0)).foregroundColor(tokens.color.textFaint)
}

func confirmQuarter(ctx: ViewContext, ui: OkrUiState, page: OkrPage, period: String): Unit {
    let mode = ui.quarterMode.value
    let target = ui.quarterTarget.value
    if (mode.isEmpty()) {
        ctx.store.setOkrPeriod(period)
        ctx.store.notify("已切换到 ${quarterLabel(period)}", tone: NoticeTone.Info)
        return
    }
    for (entry in page.data.entries) {
        if (entry.item.id == target) {
            if (mode == "copy") {
                page.copyObjective(entry, period)
            } else {
                page.moveObjective(entry, period)
            }
            return
        }
    }
}

/** 关联执行项（`LinkItemsDialog.tsx`，宽 640）。 */
func linkDialog(ctx: ViewContext, ui: OkrUiState, page: OkrPage, theme: Theme, tokens: ThemeTokens, c: TokenColors,
    workspace: Workspace): Unit {
    if (!ui.linkOpen.value) {
        return
    }
    let krId = ui.linkKr.value
    let kr = itemById(workspace, krId)
    let krTitle = match (kr) {
        case Some(value) => value.title
        case None => ""
    }
    let okrWorkspace = buildOkrWorkspace(workspace)
    let linked = ArrayList<String>()
    for (ref in executionItemsOf(okrWorkspace, krId)) {
        linked.add(ref.item.id)
    }
    let selected = ui.linkSelected.value
    let removed = ui.linkRemoved.value
    let rows = ArrayList<OkrLinkRowData>()
    for (item in okrLinkCandidates(workspace)) {
        let okrItem = toOkrItem(item)
        if (!matchesQuery(okrWorkspace, okrItem, ui.linkQuery.value)) {
            continue
        }
        let isLinked = hasIn(linked, item.id)
        // Linked rows start checked; unchecking one marks it for `deleteEdge` on confirm.
        let checked = if (isLinked) {
            !ui.hasIn(removed, item.id)
        } else {
            ui.hasIn(selected, item.id)
        }
        let area: ?Area = match (item.areaId) {
            case Some(areaId) => areaById(workspace, areaId)
            case None => None
        }
        let progress: Int64 = if (item.status == ItemStatus.Done) {
            100
        } else {
            match (item.gantt) {
                case Some(gantt) => Int64(roundPercent(gantt.progress))
                case None => 0
            }
        }
        rows.add(OkrLinkRowData(item, area, isLinked, checked, Float32(progress)))
    }
    let rowArray = rows.toArray()
    // The list/selection states are read here on purpose: a row click writes them, and this
    // read is what makes CUI rebuild the dialog (rows' checkmarks) before the next layout.
    let _ = ui.linkQuery.value
    let _ = ui.linkSelected.value
    let _ = ui.linkRemoved.value
    let _ = ui.linkScroll.value
    Ui.modal(
        theme,
        ui.linkOpen,
        {=> closeLinkDialog(ui)},
        title: "关联执行项",
        description: "为「${krTitle}」挑选支撑它的项目或行动。",
        width: 640.0,
        focus: ui.linkFocus,
        initialFocus: "okr-link-search",
        footer: {=>
            // `.okr-link-count { margin-right: auto; font-size: 12px }`
            Label("已选 ${selected.size}").fontSize(fp(12.0)).foregroundColor(c.textMuted)
            Spacer()
            Ui.button(theme, "取消", {=> closeLinkDialog(ui)}, variant: ButtonVariant.Ghost)
            Ui.button(
                theme,
                "关联所选",
                {=> confirmLink(ctx, ui, krId)},
                variant: ButtonVariant.Primary,
                enabled: selected.size > 0 || removed.size > 0
            )
        }
    ) { =>
        VStack(spacing: vp(8.0)) {
            // `.okr-link-search { display:flex; gap:8px }` + `.input { flex:1 }`
            HStack(spacing: vp(8.0)) {
                Ui.icon(theme, IconGlyph.Search, side: 15.0, color: c.textFaint)
                linkSearchField(tokens, ui)
            }.crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
            // `.okr-dialog-hint { margin-top: 8px; font-size: 11.5px; line-height: 1.5 }`
            Label("来自甘特 / GTD 的项目与行动。已通过层级挂在 KR 下的子项也会显示为「已关联」。")
                .fontSize(fp(11.5)).foregroundColor(c.textMuted)
        }.hug().fillWidth()
        // `.okr-link-list`: 46vh scroll window, 2px row gap (see okr_link_list.cj).
        OkrLinkList(tokens, theme, rowArray, ui.linkScroll) {id => toggleLinkRow(ui, linked, id)}
        if (rowArray.isEmpty()) {
            Ui.emptyState(theme, "没有匹配的执行项", description: "换个关键词，或先在甘特 / GTD 中创建行动。",
                glyph: IconGlyph.Search, compact: true)
        }
    }
}

/** `.input` 的搜索框：尺寸/边框/焦点色与 `Ui.textInput` 相同，但需要 `.flex()` 占满剩余宽度。 */
func linkSearchField(tokens: ThemeTokens, ui: OkrUiState): Unit {
    let field = TextField(ui.linkQuery, key: "okr-link-search")
    field.style(TextInputStyle(
        padding: LengthInsets(Length(10.0, LengthUnit.Vp), Length(7.0, LengthUnit.Vp)),
        textColor: tokens.color.text,
        placeholderColor: tokens.color.textFaint,
        cursorColor: tokens.color.accent,
        surface: SurfaceStyle(tokens.color.surface, border: tokens.color.border, radius: tokens.radius.md,
            borderWidth: tokens.metrics.borderWidth),
        focusedSurface: SurfaceStyle(tokens.color.surface, border: tokens.color.accent, radius: tokens.radius.md,
            borderWidth: tokens.metrics.borderWidth)
    ))
    field.placeholder("搜索项目或行动（标题、标签、负责人）…")
    // `textStyle`/`height`/`flex` 是 widget 修饰器：每次调用都会用一个包装节点替换父列表里的原节点。
    // 分成多条语句写在同一个 `field` 上时，第一条替换、后面每条都变成「再追加一个同样的输入框」，
    // 界面上就是搜索框下面又冒出一个一样的框。必须链在上一次调用的返回值上。
    let _ = field.textStyle(TextStyle(fontSize: fp(13.5))).height(34.0).flex()
}

func closeLinkDialog(ui: OkrUiState): Unit {
    ui.linkOpen.value = false
    ui.linkSelected.value = []
    ui.linkRemoved.value = []
    ui.linkScroll.value = 0.0
    ui.linkFocus.cancel()
}

/** 勾选/取消：已关联项写入 `linkRemoved`（确认时删边），其余写入 `linkSelected`。 */
func toggleLinkRow(ui: OkrUiState, linked: ArrayList<String>, rowId: String): Unit {
    // The list hands back its row's semantic id; the item id follows the prefix.
    let id = if (rowId.startsWith("okr-link-row-")) {
        rowId[OKR_LINK_ROW_ID_PREFIX.size..rowId.size]
    } else {
        rowId
    }
    if (hasIn(linked, id)) {
        let next = ArrayList<String>()
        var removed = false
        for (value in ui.linkRemoved.value) {
            if (value == id) {
                removed = true
            } else {
                next.add(value)
            }
        }
        if (!removed) {
            next.add(id)
        }
        ui.linkRemoved.value = next.toArray()
        return
    }
    let next = ArrayList<String>()
    var dropped = false
    for (value in ui.linkSelected.value) {
        if (value == id) {
            dropped = true
        } else {
            next.add(value)
        }
    }
    if (!dropped) {
        next.add(id)
    }
    ui.linkSelected.value = next.toArray()
}

/** 确认：先建 `okr` 边，再删除被取消勾选条目对应的边。 */
func confirmLink(ctx: ViewContext, ui: OkrUiState, krId: String): Unit {
    var linked = 0
    for (id in ui.linkSelected.value) {
        ctx.store.linkOkr(krId, id)
        linked += 1
    }
    var unlinked = 0
    let workspace = ctx.store.state.value()
    for (id in ui.linkRemoved.value) {
        for (edge in workspace.edges) {
            if (edge.edgeType == EdgeType.Okr && edge.from == krId && edge.to == id) {
                ctx.store.deleteEdge(edge.id)
                unlinked += 1
            }
        }
    }
    closeLinkDialog(ui)
    if (linked > 0 && unlinked > 0) {
        ctx.store.notify("已关联 ${linked} 个执行项，解除 ${unlinked} 个", tone: NoticeTone.Success)
    } else if (linked > 0) {
        ctx.store.notify("已关联 ${linked} 个执行项", tone: NoticeTone.Success)
    } else if (unlinked > 0) {
        ctx.store.notify("已解除 ${unlinked} 个执行项", tone: NoticeTone.Info)
    }
}

func hasIn(values: ArrayList<String>, id: String): Bool {
    for (value in values) {
        if (value == id) {
            return true
        }
    }
    false
}

/** 目标「更多操作」菜单（`ObjectiveCard.tsx` 的 okr-menu）。 */
func menuDialog(ctx: ViewContext, ui: OkrUiState, page: OkrPage, theme: Theme, tokens: ThemeTokens, c: TokenColors): Unit {
    if (!ui.menuOpen.value) {
        return
    }
    let objectiveId = ui.menuObjective.value
    let open = ui.menuOpen
    Ui.modal(
        theme,
        open,
        {=>
            ui.menuOpen.value = false
            ui.menuObjective.value = ""
        },
        title: "目标操作",
        width: 360.0
    ) { =>
        VStack(spacing: vp(2.0)) {
            Ui.button(
                theme,
                "移动到其他季度",
                {=>
                    open.value = false
                    ui.menuObjective.value = ""
                    page.openQuarterDialog("move", objectiveId)
                },
                variant: ButtonVariant.Ghost,
                iconLeft: IconGlyph.Calendar,
                block: true
            )
            Ui.button(
                theme,
                "复制为新季度目标",
                {=>
                    open.value = false
                    ui.menuObjective.value = ""
                    page.openQuarterDialog("copy", objectiveId)
                },
                variant: ButtonVariant.Ghost,
                iconLeft: IconGlyph.Plus,
                block: true
            )
            Divider().foregroundColor(c.border)
            Ui.button(
                theme,
                "删除目标",
                {=>
                    open.value = false
                    ui.menuObjective.value = ""
                    ui.confirmObjective.value = objectiveId
                },
                variant: ButtonVariant.Ghost,
                iconLeft: IconGlyph.Trash
            )
        }.hug().fillWidth()
        let _ = tokens
    }
}

/** KR 状态下拉（Web 用原生 `<select>`；CUI 无 select，改为同语义的选项浮层）。 */
func statusDialog(ctx: ViewContext, ui: OkrUiState, page: OkrPage, theme: Theme, tokens: ThemeTokens,
    c: TokenColors): Unit {
    if (!ui.statusOpen.value) {
        return
    }
    let krId = ui.statusKr.value
    let open = ui.statusOpen
    Ui.modal(
        theme,
        open,
        {=>
            open.value = false
            ui.statusKr.value = ""
        },
        title: "KR 状态",
        width: 360.0
    ) { =>
        VStack(spacing: vp(2.0)) {
            for (status in OKR_KR_STATUSES) {
                Ui.button(
                    theme,
                    okrStatusLabel(status),
                    {=>
                        ctx.store.setStatus(krId, status)
                        open.value = false
                        ui.statusKr.value = ""
                    },
                    variant: ButtonVariant.Ghost,
                    block: true
                )
            }
        }.hug().fillWidth()
        let _ = tokens
        let _ = c
    }
}

/** 删除确认（`ConfirmDialog.tsx`，宽 440）。 */
func confirmDialogs(ctx: ViewContext, ui: OkrUiState, page: OkrPage, theme: Theme, tokens: ThemeTokens,
    c: TokenColors): Unit {
    let workspace = ctx.store.state.value()
    if (!ui.confirmObjective.value.isEmpty()) {
        let objectiveId = ui.confirmObjective.value
        let title = match (itemById(workspace, objectiveId)) {
            case Some(item) => item.title
            case None => ""
        }
        let open = ui.confirmOpen
        Ui.modal(
            theme,
            open,
            {=>
                open.value = false
                ui.confirmObjective.value = ""
            },
            title: "删除目标？",
            description: "「${title}」及其关键结果、子孙执行项都会被删除。此操作可以用撤销恢复。",
            width: 440.0,
            footer: {=>
                Ui.button(theme, "取消", {=>
                    open.value = false
                    ui.confirmObjective.value = ""
                }, variant: ButtonVariant.Ghost)
                Ui.button(theme, "删除目标", {=>
                    open.value = false
                    ui.confirmObjective.value = ""
                    ctx.store.deleteItems([objectiveId])
                    ctx.store.notify("目标已删除", tone: NoticeTone.Info)
                }, variant: ButtonVariant.Danger)
            }
        ) { =>
            Label("删除后可以通过撤销恢复。").fontSize(fp(13.0)).foregroundColor(c.textMuted)
            let _ = tokens
        }
    }
    if (!ui.confirmKr.value.isEmpty()) {
        let krId = ui.confirmKr.value
        let title = match (itemById(workspace, krId)) {
            case Some(item) => item.title
            case None => ""
        }
        let open = ui.confirmOpen
        Ui.modal(
            theme,
            open,
            {=>
                open.value = false
                ui.confirmKr.value = ""
            },
            title: "删除关键结果？",
            description: "「${title}」及其下挂的子项会被删除；通过边关联的执行项只会解除关联。",
            width: 440.0,
            footer: {=>
                Ui.button(theme, "取消", {=>
                    open.value = false
                    ui.confirmKr.value = ""
                }, variant: ButtonVariant.Ghost)
                Ui.button(theme, "删除 KR", {=>
                    open.value = false
                    ui.confirmKr.value = ""
                    ctx.store.deleteItems([krId])
                    ctx.store.notify("关键结果已删除", tone: NoticeTone.Info)
                }, variant: ButtonVariant.Danger)
            }
        ) { =>
            Label("删除后可以通过撤销恢复。").fontSize(fp(13.0)).foregroundColor(c.textMuted)
            let _ = tokens
        }
    }
}
