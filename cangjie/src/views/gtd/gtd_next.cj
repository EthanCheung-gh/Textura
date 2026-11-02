package textura.views.gtd

import std.collection.*
import cui.*
import textura.core.data.*
import textura.ui.*
import textura.views.gtd.logic as gl

/*
 * 下一步分区（NextActions.tsx 1-525 + gtd.css:344-549）。
 *
 * 结构：标题 + 键盘提示 → 筛选栏（场景 / 仅今天超期 / 领域 / 计数）→ 按场景分组的行
 * → 分页脚注。行内左侧 20px 勾选圆，中间标题 + 面包屑、截止/场景/能量/领域，
 * 右侧 98px 场景 select + 124px 日期盒 + 编辑图标按钮（gtd.css:418-442）。
 */

func gtdNextSection(scene: GtdScene): Unit {
    let tokens = scene.tokens
    gtdSectionShell(scene, "next") {
        gtdSectionHeader(scene, IconGlyph.Play, "下一步", scene.next.size, hint: {=> GtdKbdHint(tokens)})
        gtdFilterBar(scene)
        if (scene.next.isEmpty()) {
            gtdEmptyBlock(scene, "没有符合条件的下一步", "调整筛选，或去收件箱澄清新事项。", IconGlyph.Search)
        } else {
            nextRows(scene)
        }
    }
}

/** 当前筛选条件下的排序结果（NextActions.tsx `filtered`）。 */
func nextFiltered(scene: GtdScene): Array<gl.GtdItem> {
    let ui = scene.ctx.store.ui.value()
    let filter = gl.NextFilter(
        context: ui.gtdContext,
        dueSoonOnly: scene.state.dueSoonOnly.value,
        areaId: optionalText(scene.state.areaFilter.value),
        search: ui.search,
        today: scene.today
    )
    gl.sortNextActions(gl.filterNextActions(scene.next, filter))
}

/** 分页 key：筛选 / 搜索 / 折叠任一变化都回到第一页（NextActions.tsx `pageKey`）。 */
func nextPageKeyOf(scene: GtdScene): String {
    let ui = scene.ctx.store.ui.value()
    let context = match (ui.gtdContext) {
        case Some(value) => value
        case None => ""
    }
    "${context}|${ui.search}|${scene.state.dueSoonOnly.value}|${scene.state.areaFilter.value}|" +
        "${scene.today}|${scene.state.collapsed.value}"
}

/* ---------------------------------------------------------------- 筛选栏 */

/** `.gtd-filterbar`（gtd.css:445-463）：9px 上下内边距、间距 8、次表面分隔线。 */
func gtdFilterBar(scene: GtdScene): Unit {
    let tokens = scene.tokens
    let ui = scene.ctx.store.ui.value()
    let filtered = nextFiltered(scene)
    let contextLabel = match (ui.gtdContext) {
        case Some(value) =>
            if (value == gl.NO_CONTEXT_FILTER) {
                "@${gl.NO_CONTEXT}"
            } else {
                "@${value}"
            }
        case None => "全部场景"
    }
    let areaLabel = if (scene.state.areaFilter.value.isEmpty()) {
        "全部领域"
    } else {
        scene.areaName(Some(scene.state.areaFilter.value))
    }
    VStack(spacing: vp(0.0)) {
        HStack(spacing: vp(FILTER_GAP)) {
            GtdSelectBox(tokens, contextLabel, FILTER_SELECT_MIN, "gtd-filter-context",
                {_ => scene.state.picker.value = "filter-context"}, fontSize: FILTER_SELECT_FONT,
                padRight: FILTER_SELECT_PAD_R)
            HStack(spacing: vp(TOGGLE_GAP)) {
                GtdCheckBox(tokens, scene.state.dueSoonOnly.value, "gtd-filter-due",
                    {=> scene.state.dueSoonOnly.value = !scene.state.dueSoonOnly.value})
                GtdText("仅今天/超期", TOGGLE_SIZE, 400, tokens.color.textMuted,
                    boxHeight: TOGGLE_SIZE * LINE_HEIGHT, hoverId: "gtd-filter-due-label",
                    onClick: {=> scene.state.dueSoonOnly.value = !scene.state.dueSoonOnly.value})
            }
                .crossAxisAlignment(CrossAxisAlignment.Center)
                .hug()
                .padding(vp(TOGGLE_PAD_H), vp(TOGGLE_PAD_V), vp(TOGGLE_PAD_H), vp(TOGGLE_PAD_V))
            GtdSelectBox(tokens, areaLabel, FILTER_SELECT_MIN, "gtd-filter-area",
                {_ => scene.state.picker.value = "filter-area"}, fontSize: FILTER_SELECT_FONT,
                padRight: FILTER_SELECT_PAD_R)
            Spacer()
            GtdText("${filtered.size} / ${scene.next.size}", FILTER_COUNT_SIZE, 400, tokens.color.textFaint,
                boxHeight: FILTER_COUNT_SIZE * LINE_HEIGHT)
        }
            .crossAxisAlignment(CrossAxisAlignment.Center)
            .hug()
            .fillWidth()
            .padding(vp(FILTER_PAD_H), vp(FILTER_PAD_V), vp(FILTER_PAD_H), vp(FILTER_PAD_V))
        gtdRule(tokens.color.border)
    }.hug().fillWidth()
}

/* ---------------------------------------------------------------- 分组与行 */

func nextRows(scene: GtdScene): Unit {
    let tokens = scene.tokens
    let filtered = nextFiltered(scene)
    let groups = gl.groupByContext(filtered)
    let collapsed = scene.state.collapsed.value
    let pageKey = nextPageKeyOf(scene)
    let limit = gl.resolvePageLimit(gl.PaginationState(scene.state.nextPageKey.value,
        scene.state.nextLimit.value), pageKey)
    // 折叠的场景不参与分页（NextActions.tsx `flatVisible`）
    let visible = ArrayList<gl.GtdItem>()
    for (group in groups) {
        if (!setHas(collapsed, group.context)) {
            for (item in group.items) {
                visible.add(item)
            }
        }
    }
    let slice = gl.paginateItems(visible.toArray(), limit)
    let pageGroups = gl.groupByContext(slice.items)
    let pathIndex = gl.buildPathTitleIndex(scene.gws, slice.items)
    let activeId = resolvedActiveId(scene.state.activeNext.value, slice.items)
    VStack(spacing: vp(0.0)) {
        ForEachIndexed(pageGroups) {groupIndex, group =>
            let total = groupTotal(groups, group.context)
            nextGroup(scene, group, total, pathIndex, activeId, groupIndex == pageGroups.size - 1,
                slice.remaining > 0 && groupIndex == pageGroups.size - 1)}
        if (slice.remaining > 0) {
            gtdShowMore(scene, slice.remaining, slice.shown, slice.total, onClick: {=>
                let next = gl.nextPage(gl.PaginationState(scene.state.nextPageKey.value,
                    scene.state.nextLimit.value), pageKey)
                scene.state.nextPageKey.value = pageKey
                scene.state.nextLimit.value = next.limit
            })
        }
    }.hug().fillWidth()
}

func groupTotal(groups: Array<gl.ContextGroup>, context: String): Int64 {
    for (group in groups) {
        if (group.context == context) {
            return group.items.size
        }
    }
    0
}

func nextGroup(scene: GtdScene, group: gl.ContextGroup, total: Int64, pathIndex: gl.PathTitleIndex,
    activeId: String, last: Bool, endsWithMore: Bool): Unit {
    let tokens = scene.tokens
    let collapsed = setHas(scene.state.collapsed.value, group.context)
    VStack(spacing: vp(0.0)) {
        // `.gtd-group-header`（gtd.css:505-517）：6px 上下内边距、surface-2 底、11.5/600
        HStack(spacing: vp(GROUP_GAP)) {
            IconView(if (collapsed) {
                IconGlyph.ChevronRight
            } else {
                IconGlyph.ChevronDown
            }, side: GROUP_CHEVRON, color: tokens.color.textMuted)
            GtdText("@${group.context}", GROUP_SIZE, GROUP_WEIGHT, tokens.color.textMuted,
                boxHeight: GROUP_SIZE * LINE_HEIGHT, hoverColor: tokens.color.text,
                hoverId: "gtd-group:${group.context}", tracking: 0.05 * GROUP_SIZE,
                onClick: {=> scene.state.collapsed.value = setToggle(scene.state.collapsed.value, group.context)})
            Spacer()
            GtdText("${total}", GROUP_SIZE, 400, tokens.color.textFaint,
                boxHeight: GROUP_SIZE * LINE_HEIGHT)
        }
            .crossAxisAlignment(CrossAxisAlignment.Center)
            .hug()
            .fillWidth()
            .padding(vp(GROUP_PAD_H), vp(GROUP_PAD_V), vp(GROUP_PAD_H), vp(GROUP_PAD_V))
            .background(tokens.color.surface2)
        gtdRule(tokens.color.border)
        if (!collapsed) {
            ForEachIndexed(group.items) {index, item =>
                nextRow(scene, item, pathIndex, activeId, index == group.items.size - 1 && last && !endsWithMore)}
        }
    }.hug().fillWidth()
}

func nextRow(scene: GtdScene, item: gl.GtdItem, pathIndex: gl.PathTitleIndex, activeId: String,
    last: Bool): Unit {
    let tokens = scene.tokens
    let active = activeId == item.id
    let due = gl.deadlineInfo(item, scene.today)
    let context = match (gl.contextOf(item)) {
        case Some(value) => value
        case None => gl.NO_CONTEXT
    }
    let energy = gl.energyLabel(match (item.energy) {
        case Some(value) => value
        case None => gl.Energy.Medium
    })
    let breadcrumb = match (pathIndex.parentText.get(item.id)) {
        case Some(value) => value
        case None => ""
    }
    let areaId = item.areaId
    VStack(spacing: vp(0.0)) {
        HStack(spacing: vp(0.0)) {
            gtdRowEdge(if (active) {
                tokens.color.accent
            } else {
                Color.rgba(0, 0, 0, 0)
            })
            HStack(spacing: vp(ROW_GAP)) {
                GtdCheck(tokens, "gtd-next-check:${item.id}", "完成「${item.title}」", {=>
                    scene.state.activeNext.value = item.id
                    scene.state.keyTarget.value = "next"
                    scene.ctx.store.toggleDone(item.id)
                    scene.ctx.store.notify("已完成「${item.title}」", tone: NoticeTone.Success)
                })
                VStack(spacing: vp(META_MARGIN_TOP)) {
                    HStack(spacing: vp(SECTION_HEADING_GAP)) {
                        GtdText(item.title, ROW_TITLE_SIZE, ROW_TITLE_WEIGHT, tokens.color.text,
                            boxHeight: lineBox(ROW_TITLE_SIZE, ratio: ROW_TITLE_LH),
                            hoverColor: tokens.color.accent, hoverId: "gtd-next-title:${item.id}",
                            onClick: {=>
                                scene.state.activeNext.value = item.id
                                scene.state.keyTarget.value = "next"
                                scene.openClarify(item.id)
                            })
                        if (!breadcrumb.isEmpty()) {
                            gtdBreadcrumb(scene, breadcrumb)
                        }
                    }
                        .crossAxisAlignment(CrossAxisAlignment.Center)
                        .hug()
                        .fillWidth()
                    HStack(spacing: vp(META_GAP)) {
                        gtdIconText(scene, IconGlyph.Calendar, due.label, deadlineInk(tokens, due.tone),
                            weight: if (isDeadlineMuted(due.tone)) {
                                400
                            } else {
                                600
                            })
                        gtdBadge(tokens, "@${context}", BadgeTone.Info)
                        gtdBadge(tokens, "能量 ${energy}", BadgeTone.Neutral)
                        match (scene.areaColor(areaId)) {
                            case Some(value) => GtdAreaChip(tokens, value, scene.areaName(areaId))
                            case None => ()
                        }
                        Spacer()
                    }
                        .crossAxisAlignment(CrossAxisAlignment.Center)
                        .hug()
                        .fillWidth()
                }.hug().flex()
                HStack(spacing: vp(INLINE_GAP)) {
                    // 场景与日期都在原位编辑：点哪个盒子，编辑器就出现在那个盒子上
                    // （`gtd_clarify.cj` 的 `openSceneEditor` / `openDateEditor`）。
                    // 编辑中的那个盒子只留背景（`editing`），文字与边框归真控件，避免叠字/双框。
                    GtdSelectBox(tokens, "@${context}", INLINE_SELECT_W, "gtd-row-context:${item.id}",
                        {rect => openSceneEditor(scene, item, rect)},
                        editing: scene.state.sceneTarget.value == item.id, anchor: scene.state.sceneAnchor)
                    GtdDateBox(tokens, dateBoxText(item), "gtd-row-date:${item.id}",
                        {rect => openDateEditor(scene, item, rect)},
                        editing: scene.state.dateTarget.value == item.id, anchor: scene.state.dateAnchor)
                    Ui.iconButton(scene.theme, IconGlyph.Edit, {=>
                        scene.state.activeNext.value = item.id
                        scene.openClarify(item.id)
                    }, size: ControlSize.Sm, tooltip: "打开「${item.title}」的澄清面板")
                }
                    .crossAxisAlignment(CrossAxisAlignment.Center)
                    .hug()
            }
                .crossAxisAlignment(CrossAxisAlignment.Center)
                .hug()
                .flex()
                .padding(vp(ROW_PAD_H), vp(ROW_PAD_V), vp(ROW_PAD_H), vp(ROW_PAD_V))
        }
            .hug()
            .fillWidth()
            .background(if (active) {
                tokens.color.surface2
            } else {
                Color.rgba(0, 0, 0, 0)
            })
        if (!last) {
            gtdRule(tokens.color.border)
        }
    }.hug().fillWidth()
}

/** `.gtd-breadcrumb`（gtd.css:370-380）：12px 文件夹图标 + 11px 文本，最宽 260。 */
func gtdBreadcrumb(scene: GtdScene, text: String): Unit {
    let tokens = scene.tokens
    HStack(spacing: vp(CHIP_GAP)) {
        IconView(IconGlyph.Folder, side: META_ICON, color: tokens.color.textFaint)
        GtdText(text, BREADCRUMB_SIZE, 400, tokens.color.textFaint, boxHeight: BREADCRUMB_SIZE * LINE_HEIGHT,
            maxWidth: BREADCRUMB_MAX)
    }
        .crossAxisAlignment(CrossAxisAlignment.Center)
        .hug()
        .maxWidth(BREADCRUMB_MAX)
}

/** `.gtd-deadline--muted` 判别（`==` 不跨包可见）。 */
func isDeadlineMuted(tone: gl.DeadlineTone): Bool {
    match (tone) {
        case gl.DeadlineTone.Muted => true
        case _ => false
    }
}

/** `.gtd-deadline--danger|accent|muted`（gtd.css:382-401）。 */
func deadlineInk(tokens: ThemeTokens, tone: gl.DeadlineTone): Color {
    match (tone) {
        case gl.DeadlineTone.Danger => tokens.color.danger
        case gl.DeadlineTone.Accent => tokens.color.accent
        case gl.DeadlineTone.Muted => tokens.color.textFaint
    }
}

/** 日期盒文案：`YYYY-MM-DD`（`dateKey` 截断，与 Web 的 `<input type=date>` 取值一致）。 */
func dateBoxText(item: gl.GtdItem): String {
    match (dateKey(item.dueDate)) {
        case Some(value) => value
        case None => ""
    }
}
