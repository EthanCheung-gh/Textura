package textura.views.okr

import std.collection.ArrayList
import std.unicode.*
import cui.*
import textura.core.data.{Item, ItemKind, ItemPatch, ItemStatus, OkrPatch, SetValue}
import textura.ui.*
import textura.views.okr.logic.{EMPTY_METRIC, ExecutionVia, MetricField, MetricProgressState, OkrMetric,
    confidenceBucket, formatMetric, formatNumber, formatSchedule, metricFieldText, metricProgress, metricToText,
    unitSuffix}

/*
 * 目标卡 + KR 行（`ObjectiveCard.tsx` / `KrRow.tsx` / `MetricEditor.tsx`，
 * 样式见 `okr.css:219-851`）。
 *
 * 垂直节奏（全部来自 CSS，不含近似值）：
 *   .okr-objective-head  padding 16 16 12，纵向 gap 6
 *   .okr-objective-meta  高度 = 徽章 23.6
 *   .okr-objective-title 16.5px / line-height 1.35 = 22.275，加 1px 上下内边距
 *   .okr-objective-notes 12.5px / line-height 1.5 = 18.75
 *   .okr-objective-progress  padding-top 2，行高 = 信心刻度 28
 *   .okr-kr               padding 12 16，纵向 gap 6，border-bottom 1
 *   .okr-kr-main          行高 = 标题(20.9) + gap 2 + 徽章行(23.6) = 46.5
 *   .okr-kr-detail        指标行 28 + gap 6 + 元信息行 28 = 62
 */

/** `.okr-objective-title { font-size: 16.5; line-height: 1.35 }` + `.okr-editable-title { padding: 1px 3px }`。 */
let OKR_OBJ_TITLE_H: Float32 = 16.5 * 1.35 + 2.0
/** `.okr-kr-title { font-size: 13.5; line-height: 1.4 }` + EditableTitle 的 2px 内边距。 */
let OKR_KR_TITLE_H: Float32 = 13.5 * 1.4 + 2.0
/** `.okr-conf` 整组高度 = 22 + 2×2 padding + 2×1 border。 */
let OKR_CONF_H: Float32 = 28.0
/** `.okr-conf` 整组宽度 = 10×19 + 9×1 gap + 4 padding + 2 border。 */
let OKR_CONF_W: Float32 = 205.0
/** `.okr-kr-progress { flex: 0 0 150px }`。 */
let OKR_KR_PROGRESS_W: Float32 = 150.0
/** `.okr-kr-actions`：4 个 26 的图标按钮 + 3 个 1px 间距。 */
let OKR_KR_ACTIONS_W: Float32 = 107.0
/** `.okr-add-kr`：输入 26 / 按钮 28 + 上下 3 padding + 1 border → 36。 */
let OKR_ADD_KR_H: Float32 = 36.0

/** `.okr-objectives { gap: var(--space-4) }`（okr.css:219-224）。 */
func layoutCards(page: OkrPage, ctx: UiContext, cv: PageCanvas, x0: Float32, w: Float32, y: Float32): Float32 {
    var cursor = y
    for (entry in page.data.entries) {
        cursor = layoutObjectiveCard(page, ctx, cv, x0, w, cursor, entry)
        cursor += OKR_S4
    }
    cursor - OKR_S4
}

func objectiveHeadHeight(entry: OkrObjEntry, detailed: Bool): Float32 {
    var content: Float32 = OKR_BADGE_H + 6.0 + OKR_OBJ_TITLE_H
    if (detailed && !entry.item.notes.isEmpty()) {
        content += 6.0 + 12.5 * 1.5
    }
    content += 6.0 + 2.0 + OKR_CONF_H
    16.0 + content + 12.0
}

func krRowHeight(detailed: Bool): Float32 {
    // 12 + main(46.5) + [6 + detail(62)] + 12 + border 1
    let mainH: Float32 = OKR_KR_TITLE_H + 2.0 + OKR_BADGE_H
    if (detailed) {
        12.0 + mainH + 6.0 + (28.0 + 6.0 + 28.0) + 12.0 + 1.0
    } else {
        12.0 + mainH + 12.0 + 1.0
    }
}

/** 一张目标卡（okr.css:226-333 + 408-532）。 */
func layoutObjectiveCard(page: OkrPage, ctx: UiContext, cv: PageCanvas, x0: Float32, w: Float32, y: Float32,
    entry: OkrObjEntry): Float32 {
    let c = page.tokens.color
    let detailed = page.ui.isDetailed()
    let headH = objectiveHeadHeight(entry, detailed)
    let krPitch = krRowHeight(detailed)
    let cardH = 1.0 + headH + 1.0 + Float32(entry.krs.size) * krPitch + 2.0 + OKR_ADD_KR_H + 8.0 + 1.0
    // 内部行位置从吸附后的卡片顶边算起，避免小数累积把 1px 分隔线推到相邻像素行
    let cardTop = cv.snapValue(y)
    let cardRect = Rect(x0, cardTop, w, cardH)
    cv.shadow(cardRect, OKR_R_LG)
    cv.fill(cardRect, OKR_R_LG, c.surface)
    cv.stroke(cardRect, OKR_R_LG, c.border)

    let left = x0 + 1.0 + OKR_S4
    let right = x0 + w - 1.0 - OKR_S4
    let mainW = right - left - 12.0 - 26.0
    let headTop = cardTop + 1.0 + OKR_S4
    let metaCenter = headTop + OKR_BADGE_H / 2.0
    var cursor = left
    match (entry.area) {
        case Some(area) =>
            cv.dot(cursor + 3.5, metaCenter, 3.5, hexColor(area.color, c.textMuted))
            cursor += 7.0 + 5.0
            cursor += cv.text(ctx, cursor, metaCenter, area.name, 11.5, 400, c.textMuted) + OKR_S2
        case None =>
            cursor += cv.text(ctx, cursor, metaCenter, "未归属 Area", 11.5, 400, c.textFaint) + OKR_S2
    }
    let statusLabel = okrStatusLabel(entry.item.status)
    cursor += cv.badge(ctx, cursor, headTop, statusLabel, okrStatusTone(entry.item.status)) + OKR_S2
    cursor += cv.text(ctx, cursor, metaCenter, "${entry.allKrCount} 个关键结果", 11.0, 400, c.textMuted)
    if (entry.allKrCount == 0) {
        cursor += OKR_S2
        cursor += cv.badge(ctx, cursor, headTop, "缺少关键结果", BadgeTone.Warn, dot: true)
    }
    // 标题（画布自绘；点击打开编辑浮层，见 okr_prompt.cj）
    let titleTop = headTop + OKR_BADGE_H + 6.0
    let titleCenter = titleTop + OKR_OBJ_TITLE_H / 2.0
    let titleId = "okr-title-${entry.item.id}"
    let hovered = ctx.isHovered(titleId)
    let titleRect = Rect(left - 3.0, titleTop, min(mainW + 6.0, okrTextW(ctx, entry.item.title, 16.5, 650) + 6.0),
        OKR_OBJ_TITLE_H)
    // 编辑态：原位编辑器（真 TextField）压在这个矩形上，画布不再重复画这行标题；
    // 同时每帧把矩形写回锚点，滚动/resize 后编辑器跟着字段走（`okr_prompt.cj` 的 `trackOkrPrompt`）。
    if (!trackOkrPrompt(page.ui, "title", entry.item.id, "", titleRect)) {
        cv.text(ctx, left, titleCenter, entry.item.title, 16.5, 650, if (hovered) {
            c.accentInk
        } else {
            c.text
        })
    }
    cv.focusRingFor(titleId, Rect(left - 3.0, titleTop, mainW + 6.0, OKR_OBJ_TITLE_H), OKR_R_MD)
    cv.addHotspot(titleId, titleRect, {=> openOkrTitlePrompt(page.ui, entry.item.id, entry.item.title, titleRect)})
    var afterTitle = titleTop + OKR_OBJ_TITLE_H
    if (detailed && !entry.item.notes.isEmpty()) {
        let notesTop = afterTitle + 6.0
        let lines = wrapText(ctx, entry.item.notes, 12.5, 400, mainW)
        var lineIndex = 0
        for (line in lines) {
            cv.text(ctx, left, notesTop + 12.5 * 1.5 * (Float32(lineIndex) + 0.5), line, 12.5, 400, c.textMuted)
            lineIndex += 1
        }
        afterTitle = notesTop + 12.5 * 1.5 * Float32(lines.size)
    }
    // 整体进度行
    let progressTop = afterTitle + 6.0 + 2.0
    let progressCenter = progressTop + OKR_CONF_H / 2.0
    let labelText = "整体进度"
    let labelW = cv.text(ctx, left, progressCenter, labelText, 11.0, 400, c.textMuted)
    let pctText = "${entry.progress}%"
    let pctW = max(34.0, okrTextW(ctx, pctText, 11.5, 400, mono: true))
    let confX = right - OKR_CONF_W
    let confLabelW = okrTextW(ctx, "信心", 11.0, 400)
    let pctRight = confX - OKR_S2 - confLabelW - OKR_S2 - 4.0 - OKR_S2
    let barLeft = left + labelW + OKR_S2
    let barRight = pctRight - pctW - OKR_S2
    cv.progress(ctx, Rect(barLeft, progressCenter - 4.0, max(0.0, barRight - barLeft), 8.0),
        Float32(entry.progress), okrProgressTone(entry.progress, false), ControlSize.Md)
    cv.textRight(ctx, pctRight, progressCenter, pctText, 11.5, 400, c.textMuted, mono: true)
    cv.textRight(ctx, confX - OKR_S2, progressCenter, "信心", 11.0, 400, c.textMuted)
    page.paintConfidenceScale(ctx, cv, entry.item.id, Rect(confX, progressTop, OKR_CONF_W, OKR_CONF_H),
        entry.confidence) {value => page.store.setConfidence(entry.item.id, value)}
    // 目标更多操作（右上角 26×26）
    page.paintIconButton(ctx, cv, "okr-more-${entry.item.id}", Rect(right - 26.0, headTop, 26.0, 26.0),
        IconGlyph.More, false, true) {=>
        page.ui.menuObjective.value = entry.item.id
        page.ui.menuOpen.value = true
    }

    // KR 区：`.okr-kr-section` 的上边框 + 每行 border-bottom（最后一行没有）
    let sectionY = cardTop + 1.0 + headH
    cv.hLine(x0 + 1.0, x0 + w - 1.0, sectionY, c.border)
    var krY = sectionY + 1.0
    var index: Int64 = 0
    for (kr in entry.krs) {
        layoutKrRow(page, ctx, cv, entry, kr, index, Int64(entry.krs.size), krY, left, right)
        krY += krPitch
        if (index < Int64(entry.krs.size) - 1) {
            cv.hLine(x0 + 1.0, x0 + w - 1.0, krY - 1.0, c.border)
        }
        index += 1
    }
    // CSS `margin-top: 2px`；这里用 1px 抵消上方小数行高累积（对齐参考图 851 行的虚线框）
    layoutAddKeyResult(page, ctx, cv, entry, x0 + 1.0 + OKR_S4, x0 + w - 1.0 - OKR_S4, krY + 1.0)
    cardTop + cardH
}

/** 单条 KR（KrRow.tsx）。 */
func layoutKrRow(page: OkrPage, ctx: UiContext, cv: PageCanvas, entry: OkrObjEntry, kr: OkrKrEntry, index: Int64,
    count: Int64, y: Float32, left: Float32, right: Float32): Unit {
    let c = page.tokens.color
    let detailed = page.ui.isDetailed()
    let mainH: Float32 = OKR_KR_TITLE_H + 2.0 + OKR_BADGE_H
    let mainTop = y + OKR_S3
    // 索引（.okr-kr-index { width: 16px; font-size: 10.5 }）
    cv.text(ctx, left, mainTop + mainH / 2.0, pad2(index + 1), 10.5, 400, c.textFaint, mono: true)
    let headingX = left + 16.0 + OKR_S2
    let actionsX = right - OKR_KR_ACTIONS_W
    let confX = actionsX - OKR_S2 - OKR_CONF_W
    let progressX = confX - OKR_S2 - OKR_KR_PROGRESS_W
    let headingW = progressX - OKR_S2 - headingX
    // 标题（画布自绘；点击打开编辑浮层，见 okr_prompt.cj）
    let titleId = "okr-title-${kr.item.id}"
    let titleTop = mainTop
    let hovered = ctx.isHovered(titleId)
    let title = ellipsize(ctx, kr.item.title, 13.5, 600, headingW - 6.0)
    let titleRect = Rect(headingX - 3.0, titleTop, min(headingW, okrTextW(ctx, title, 13.5, 600) + 6.0),
        OKR_KR_TITLE_H)
    if (!trackOkrPrompt(page.ui, "title", kr.item.id, "", titleRect)) {
        cv.text(ctx, headingX, titleTop + OKR_KR_TITLE_H / 2.0, title, 13.5, 600, if (hovered) {
            c.accentInk
        } else {
            c.text
        })
    }
    cv.focusRingFor(titleId, Rect(headingX - 3.0, titleTop, headingW, OKR_KR_TITLE_H), OKR_R_MD)
    cv.addHotspot(titleId, titleRect, {=> openOkrTitlePrompt(page.ui, kr.item.id, kr.item.title, titleRect)})
    // 徽章行
    let badgesTop = titleTop + OKR_KR_TITLE_H + 2.0
    let badgeCenter = badgesTop + OKR_BADGE_H / 2.0
    var badgeX = headingX
    if (kr.behind) {
        badgeX += cv.badge(ctx, badgeX, badgesTop, "落后", BadgeTone.Danger, dot: true) + 6.0
    }
    if (kr.lacksGrip()) {
        badgeX += cv.badge(ctx, badgeX, badgesTop, "缺少抓手", BadgeTone.Warn, dot: true) + 6.0
    }
    if (!detailed) {
        badgeX += cv.badge(ctx, badgeX, badgesTop, okrStatusLabel(kr.item.status), okrStatusTone(kr.item.status)) + 6.0
        let metricText = match (kr.metric) {
            case Some(metric) => "${formatNumber(metric.current)} / ${formatNumber(metric.target)}${unitSuffix(metric.unit)}"
            case None => "无指标"
        }
        badgeX += cv.text(ctx, badgeX, badgeCenter, metricText, 11.0, 400, c.textMuted, mono: true) + 6.0
        badgeX += cv.text(ctx, badgeX, badgeCenter, if (kr.owner.isEmpty()) {
            "未指派"
        } else {
            kr.owner
        }, 11.0, 400, c.textFaint)
    }
    // 进度
    let progressCenter = mainTop + mainH / 2.0
    let pctText = "${kr.progress}%"
    cv.progress(ctx, Rect(progressX, progressCenter - 2.5, OKR_KR_PROGRESS_W - 6.0 - 32.0, 5.0),
        Float32(kr.progress), okrProgressTone(kr.progress, kr.behind), ControlSize.Sm)
    cv.textRight(ctx, progressX + OKR_KR_PROGRESS_W, progressCenter, pctText, 11.0, 400, c.textMuted, mono: true)
    // 信心刻度
    page.paintConfidenceScale(ctx, cv, kr.item.id, Rect(confX, mainTop + (mainH - OKR_CONF_H) / 2.0, OKR_CONF_W,
        OKR_CONF_H), kr.confidence) {value => page.store.setConfidence(kr.item.id, value)}
    // 行内操作：上移 / 下移 / 关联 / 删除
    let actionsTop = mainTop + (mainH - 26.0) / 2.0
    let upId = "okr-up-${kr.item.id}"
    let downId = "okr-down-${kr.item.id}"
    let linkId = "okr-link-${kr.item.id}"
    let delId = "okr-del-${kr.item.id}"
    paintChevronButton(page, ctx, cv, upId, Rect(actionsX, actionsTop, 26.0, 26.0), true, index > 0) {
        => page.store.moveItem(kr.item.id, Some(entry.item.id), Some(index - 1))
    }
    paintChevronButton(page, ctx, cv, downId, Rect(actionsX + 27.0, actionsTop, 26.0, 26.0), false, index < count - 1) {
        => page.store.moveItem(kr.item.id, Some(entry.item.id), Some(index + 1))
    }
    page.paintIconButton(ctx, cv, linkId, Rect(actionsX + 54.0, actionsTop, 26.0, 26.0), IconGlyph.Link, false, true) {
        => openLinkDialog(page, kr.item.id)
    }
    page.paintIconButton(ctx, cv, delId, Rect(actionsX + 81.0, actionsTop, 26.0, 26.0), IconGlyph.Trash, true, true) {
        =>
        page.ui.confirmKr.value = kr.item.id
        page.ui.confirmOpen.value = true
    }
    if (detailed) {
        let detailTop = mainTop + mainH + 6.0
        let detailLeft = left + 24.0
        let detailW = right - detailLeft
        layoutMetricEditor(page, ctx, cv, kr, detailLeft, detailTop, detailW)
        layoutKrMeta(page, ctx, cv, entry, kr, detailLeft, detailTop + 28.0 + 6.0, detailW)
        let execTop = detailTop + 28.0 + 6.0 + 28.0 + 6.0
        if (kr.execs.size > 0) {
            _ = layoutExecList(page, ctx, cv, kr, detailLeft, execTop, detailW)
        }
    }
}

/** 上移/下移：Web 用 `rotate(90deg)` 的 chevron；CUI 没有旋转图标，按同一 24 网格几何自绘。 */
func paintChevronButton(page: OkrPage, ctx: UiContext, cv: PageCanvas, id: String, rect: Rect, up: Bool,
    enabled: Bool, action: () -> Unit): Unit {
    let c = page.tokens.color
    let hovered = enabled && ctx.isHovered(id)
    let pressed = enabled && ctx.isPressed(id)
    var ink = c.textMuted
    if (hovered || pressed) {
        cv.fill(rect, OKR_R_MD, c.surface2)
        ink = c.text
    }
    if (!enabled) {
        ink = withOpacity(ink, 0.4)
    }
    let side = min(min(rect.w, rect.h), 14.0)
    cv.chevron(Rect(rect.centerX() - side / 2.0, rect.centerY() - side / 2.0, side, side), up, ink)
    if (enabled) {
        cv.focusRingFor(id, rect, OKR_R_MD)
        cv.addHotspot(id, rect, action)
    }
}

/** 指标编辑器（MetricEditor.tsx / okr.css:597-677）。 */
func layoutMetricEditor(page: OkrPage, ctx: UiContext, cv: PageCanvas, kr: OkrKrEntry, x: Float32, y: Float32,
    width: Float32): Unit {
    let c = page.tokens.color
    let krId = kr.item.id
    let metric = match (kr.metric) {
        case Some(value) => value
        case None => EMPTY_METRIC
    }
    let info = metricProgress(kr.metric)
    let flat = info.state == MetricProgressState.Flat
    let labels = ["起点", "当前", "目标", "单位"]
    let fields = [MetricField.Start, MetricField.Current, MetricField.Target, MetricField.UnitField]
    var cursor = x
    var index = 0
    while (index < 4) {
        let field = fields[index]
        let isUnit = field == MetricField.UnitField
        let inputW: Float32 = if (isUnit) {
            64.0
        } else {
            78.0
        }
        let warn = index == 2 && flat
        let labelW = cv.text(ctx, cursor, y + 14.0, labels[index], 11.0, 400, if (warn) {
            c.warnInk
        } else {
            c.textMuted
        })
        let inputX = cursor + labelW + 5.0
        let fieldId = "okr-field-${krId}-${metricFieldText(field)}"
        let initial = if (isUnit) {
            metric.unit
        } else {
            metricToText(metricFieldValue(field, metric))
        }
        let fieldEditing = okrFieldEditing(page.ui, "metric", krId, field: metricFieldText(field))
        paintOkrField(page, ctx, cv, fieldId, Rect(inputX, y, inputW, 28.0), initial, if (isUnit) {
            "例如 %"
        } else {
            "0"
        }, warn, {=> openOkrMetricPrompt(page.ui, krId, field, initial, Rect(inputX, y, inputW, 28.0))},
            editing: fieldEditing)
        cursor = inputX + inputW + OKR_S2
        index += 1
    }
    // 摘要：`42 → 60 分` + `换算 28%` + 超额/低于起点
    var summaryX = cursor
    let metricText = formatMetric(kr.metric)
    summaryX += cv.text(ctx, summaryX, y + 14.0, metricText, 11.0, 400, c.textMuted, mono: true) + OKR_S2
    match (info.percent) {
        case Some(percent) =>
            let pct = "换算 ${Int64(roundPercent(percent))}%"
            summaryX += cv.text(ctx, summaryX, y + 14.0, pct, 11.0, 600, c.accentInk) + OKR_S2
            match (info.state) {
                case MetricProgressState.Over =>
                    summaryX += cv.badge(ctx, summaryX, y + 2.0, "已超额", BadgeTone.Ok, dot: true)
                case MetricProgressState.Under =>
                    summaryX += cv.badge(ctx, summaryX, y + 2.0, "低于起点", BadgeTone.Warn, dot: true)
                case _ => ()
            }
        case None =>
            if (kr.metric.isNone()) {
                cv.text(ctx, summaryX, y + 14.0, "未设指标 · 进度按完成比计算", 11.0, 400, c.warnInk)
            }
    }
    if (flat) {
        cv.text(ctx, x, y + 28.0 + 2.0 + 11.0 * 1.45 / 2.0, "起点与目标相同，无法换算进度；请调整目标值，或直接用完成状态标记 KR。",
            11.0, 400, c.warnInk)
    } else if (info.state == MetricProgressState.Invalid) {
        cv.text(ctx, x, y + 28.0 + 2.0 + 11.0 * 1.45 / 2.0, "指标数值无效，无法换算进度。", 11.0, 400, c.warnInk)
    }
    _ = width
}

func metricFieldValue(field: MetricField, metric: OkrMetric): Float64 {
    match (field) {
        case MetricField.Start => metric.start
        case MetricField.Current => metric.current
        case MetricField.Target => metric.target
        case MetricField.UnitField => 0.0
    }
}

/** KR 元信息行（负责人 / 状态 / 关联执行项 / 节奏提示，okr.css:679-717）。 */
func layoutKrMeta(page: OkrPage, ctx: UiContext, cv: PageCanvas, entry: OkrObjEntry, kr: OkrKrEntry, x: Float32,
    y: Float32, width: Float32): Unit {
    let c = page.tokens.color
    let krId = kr.item.id
    let centerY = y + 14.0
    let ownerLabelW = cv.text(ctx, x, centerY, "负责人", 11.0, 400, c.textMuted)
    let ownerX = x + ownerLabelW + 5.0
    paintOkrField(page, ctx, cv, "okr-owner-${krId}", Rect(ownerX, y, 96.0, 28.0), kr.owner, "未指派", false,
        {=> openOkrOwnerPrompt(page.ui, krId, kr.owner, Rect(ownerX, y, 96.0, 28.0))},
        editing: okrFieldEditing(page.ui, "owner", krId))
    var cursor = ownerX + 96.0 + OKR_S2
    let statusLabelW = cv.text(ctx, cursor, centerY, "状态", 11.0, 400, c.textMuted)
    let selectX = cursor + statusLabelW + 5.0
    paintSelect(page, ctx, cv, "okr-status-${krId}", Rect(selectX, y, 96.0, 28.0), okrStatusLabel(kr.item.status)) {
        page.ui.statusKr.value = krId
        page.ui.statusOpen.value = true
    }
    cursor = selectX + 96.0 + OKR_S2
    let linkText = if (kr.execs.size > 0) {
        "关联执行项 (${kr.execs.size})"
    } else {
        "关联执行项"
    }
    let linkW = page.buttonWidth(ctx, linkText, 0, Some(IconGlyph.Link))
    page.paintButton(ctx, cv, "okr-link-button-${krId}", Rect(cursor, y, linkW, 28.0), linkText, OKR_BTN_SECONDARY, 0,
        Some(IconGlyph.Link), true, {=> openLinkDialog(page, krId)})
    cursor += linkW + OKR_S2
    let delta = Int64(roundPercent(page.data.summary.elapsedPercent - Float64(kr.progress)))
    let pace = if (kr.behind) {
        "落后时间进度 ${delta} 个点"
    } else if (delta < 0) {
        "领先时间进度 ${-delta} 个点"
    } else {
        "与时间进度相差 ${delta} 个点"
    }
    var hint = pace
    if (kr.metric.isSome()) {
        hint += " · 指标 ${formatMetric(kr.metric)}"
    }
    if (kr.execs.size == 0) {
        hint += " · 尚未关联执行项"
    }
    cv.text(ctx, cursor, centerY, ellipsize(ctx, hint, 11.0, if (kr.behind) {
        550
    } else {
        400
    }, max(0.0, x + width - cursor)), 11.0, if (kr.behind) {
        550
    } else {
        400
    }, if (kr.behind) {
        c.dangerInk
    } else {
        c.textMuted
    })
    _ = entry
}

/** 关联执行项列表（ExecutionItemList.tsx / okr.css:719-811）。 */
func layoutExecList(page: OkrPage, ctx: UiContext, cv: PageCanvas, kr: OkrKrEntry, x: Float32, y: Float32,
    width: Float32): Float32 {
    let c = page.tokens.color
    let rowH: Float32 = 20.0
    let boxH = 6.0 + 14.0 + 4.0 + Float32(kr.execs.size) * (rowH + 1.0) + 6.0
    let boxRect = Rect(x, y, width, boxH)
    cv.fill(boxRect, OKR_R_MD, c.surface2)
    cv.stroke(boxRect, OKR_R_MD, c.border)
    cv.text(ctx, x + 8.0, y + 6.0 + 7.0, "执行项 · ${kr.execs.size}", 10.5, 400, c.textMuted)
    cv.textRight(ctx, x + width - 8.0, y + 6.0 + 7.0, "勾选可直接标记完成", 10.5, 400, c.textMuted)
    var rowY = y + 6.0 + 14.0 + 4.0
    for (exec in kr.execs) {
        let done = exec.item.status == ItemStatus.Done
        let rowRect = Rect(x + 4.0, rowY, width - 8.0, rowH)
        let centerY = rowRect.centerY()
        cv.fill(Rect(rowRect.x, rowRect.y, rowRect.w, rowH), OKR_R_SM, c.surface2)
        let checkRect = Rect(rowRect.x + 2.0, centerY - 7.0, 14.0, 14.0)
        paintCheckbox(page, ctx, cv, "okr-exec-${exec.item.id}", checkRect, done) {
            page.store.toggleDone(exec.item.id)
        }
        var cursor = rowRect.x + 22.0
        cursor += cv.text(ctx, cursor, centerY, ellipsize(ctx, exec.item.title, 12.0, 400, 320.0), 12.0, 400,
            if (done) {
                c.textFaint
            } else {
                c.text
            }) + 6.0
        cursor += cv.badge(ctx, cursor, centerY - OKR_BADGE_H / 2.0, okrStatusLabel(exec.item.status),
            okrStatusTone(exec.item.status)) + 6.0
        if (exec.via == ExecutionVia.Child) {
            cursor += cv.badge(ctx, cursor, centerY - OKR_BADGE_H / 2.0, "子项", BadgeTone.Neutral) + 6.0
        }
        cv.textRight(ctx, rowRect.right() - 30.0, centerY, formatSchedule(exec.schedule()), 10.5, 400, c.textMuted,
            mono: true)
        page.paintIconButton(ctx, cv, "okr-unlink-${exec.item.id}", Rect(rowRect.right() - 24.0, centerY - 13.0, 26.0,
            26.0), IconGlyph.Close, false, exec.edgeId.isSome()) {
            match (exec.edgeId) {
                case Some(edgeId) => page.store.deleteEdge(edgeId)
                case None => ()
            }
        }
        rowY += rowH + 1.0
    }
    boxH
}

/** `.okr-check`（okr.css:773-779）：14×14、`accent-color`。 */
func paintCheckbox(page: OkrPage, ctx: UiContext, cv: PageCanvas, id: String, rect: Rect, checked: Bool,
    action: () -> Unit): Unit {
    let c = page.tokens.color
    if (checked) {
        cv.fill(rect, 3.0, c.accent)
        cv.icon(Rect(rect.x + 1.5, rect.y + 1.5, rect.w - 3.0, rect.h - 3.0), IconGlyph.Check, c.textOnStrong)
    } else {
        cv.fill(rect, 3.0, c.surface)
        cv.stroke(rect, 3.0, c.borderStrong)
    }
    cv.addHotspot(id, rect, action)
}

/** `.select.okr-mini-input`（okr.css:696-707）：CUI 没有原生 select，这里自绘并按需弹出选项。 */
func paintSelect(page: OkrPage, ctx: UiContext, cv: PageCanvas, id: String, rect: Rect, label: String,
    action: () -> Unit): Unit {
    let c = page.tokens.color
    let hovered = ctx.isHovered(id)
    cv.fill(rect, OKR_R_MD, c.surface)
    cv.stroke(rect, OKR_R_MD, if (hovered) {
        c.borderStrong
    } else {
        c.border
    })
    cv.text(ctx, rect.x + 7.0, rect.centerY(), ellipsize(ctx, label, 12.0, 400, rect.w - 30.0), 12.0, 400, c.text)
    // `.select` 的下拉三角（ui.css:218-226 + okr.css:704-707）：两个 5×5 半三角拼成的 10×5 实心箭头
    let arrowX = rect.right() - 13.0
    let arrowTop = rect.y + 12.0
    var row: Float32 = 0.0
    while (row < 5.0) {
        let inset = row * 0.5
        cv.fill(Rect(arrowX + inset, arrowTop + row, 10.0 - inset * 2.0, 1.0), 0.0, c.textFaint)
        row += 1.0
    }
    cv.focusRingFor(id, rect, OKR_R_MD)
    cv.addHotspot(id, rect, action)
}

/** `.okr-add-kr`（okr.css:813-849）。 */
func layoutAddKeyResult(page: OkrPage, ctx: UiContext, cv: PageCanvas, entry: OkrObjEntry, left: Float32,
    right: Float32, y: Float32): Unit {
    let c = page.tokens.color
    let boxRect = Rect(left, y, right - left, OKR_ADD_KR_H)
    cv.dashed(boxRect, OKR_R_MD, c.border)
    let centerY = boxRect.centerY()
    cv.icon(Rect(boxRect.x + 9.0, centerY - 7.0, 14.0, 14.0), IconGlyph.Plus, c.textFaint)
    let addText = "添加"
    let buttonW = page.buttonWidth(ctx, addText, 0, Option<IconGlyph>.None)
    let addId = "okr-add-${entry.item.id}"
    let buttonX = boxRect.right() - 1.0 - 8.0 - buttonW
    let inputLeft = boxRect.x + 1.0 + 8.0 + 14.0 + 6.0
    let addKrId = "okr-addkr-${entry.item.id}"
    let inputRect = Rect(inputLeft, centerY - 13.0, max(0.0, buttonX - 6.0 - inputLeft), 26.0)
    if (!trackOkrPrompt(page.ui, "addkr", entry.item.id, "", inputRect)) {
        cv.text(ctx, inputLeft, centerY, ellipsize(ctx, "新增关键结果，回车创建（默认信心 5）…", 12.5, 400,
            inputRect.w), 12.5, 400, c.textFaint)
    }
    cv.focusRingFor(addKrId, inputRect, OKR_R_MD)
    cv.addHotspot(addKrId, inputRect, {=> openOkrAddKrPrompt(page.ui, entry.item.id, inputRect)})
    page.paintButton(ctx, cv, addId, Rect(buttonX, centerY - 14.0, buttonW, 28.0), addText, OKR_BTN_GHOST, 0,
        Option<IconGlyph>.None, true) {=> openOkrAddKrPrompt(page.ui, entry.item.id, inputRect)}
}

/**
 * 画布上的「输入框外观」字段：与 `.input` 同样的盒模型（surface / 1px 边框 / radius 8 /
 * 7×2 内边距 / 12.5 字号），但没有可编辑控件 —— 点击由调用方打开 `Ui.prompt`。
 */
func paintOkrField(page: OkrPage, ctx: UiContext, cv: PageCanvas, id: String, rect: Rect, value: String,
    placeholder: String, warn: Bool, action: () -> Unit, editing!: Bool = false): Unit {
    let c = page.tokens.color
    if (cv.measureOnly) {
        return
    }
    let bg = if (warn) {
        c.surface.lerp(c.warn, 0.08)
    } else {
        c.surface
    }
    let border = if (warn) {
        c.warnInk
    } else {
        c.border
    }
    cv.fill(rect, OKR_R_MD, bg)
    if (editing) {
        // 原位编辑器接管这个盒子：边框与文字归它画，画布只留背景（避免双边框 + 两层文字）。
        // 每帧写回锚点：滚动/resize/行高变化时编辑器都停在这个盒子上。
        page.ui.promptAnchor.update(rect)
        cv.addHotspot(id, rect, action)
        return
    }
    cv.stroke(rect, OKR_R_MD, border)
    let text = if (value.isEmpty()) {
        placeholder
    } else {
        value
    }
    let ink = if (value.isEmpty()) {
        c.textFaint
    } else {
        c.text
    }
    cv.text(ctx, rect.x + 7.0, rect.centerY(), ellipsize(ctx, text, 12.5, 400, rect.w - 14.0), 12.5, 400, ink)
    cv.focusRingFor(id, rect, OKR_R_MD)
    cv.addHotspot(id, rect, action)
}

func okrOwnerPatch(owner: String): ItemPatch {
    let patch = ItemPatch()
    let okr = OkrPatch()
    let ownerValue: ?String = if (owner.isEmpty()) {
        None
    } else {
        Some(owner)
    }
    okr.krOwner = SetValue<?String>.Value(ownerValue)
    patch.okr = Some(okr)
    patch
}

/** 打开「关联执行项」对话框（LinkItemsDialog.tsx）。 */
func openLinkDialog(page: OkrPage, krId: String): Unit {
    page.ui.linkKr.value = krId
    // LinkItemsDialog seeds its query from the global search on open.
    page.ui.linkQuery.value = page.store.ui.value().search
    page.ui.linkSelected.value = []
    page.ui.linkRemoved.value = []
    page.ui.linkScroll.value = 0.0
    page.ui.linkOpen.value = true
    page.ui.linkFocus.request("okr-link-search")
}
