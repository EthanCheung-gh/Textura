package textura.views.okr

import std.collection.ArrayList
import std.unicode.*
import cui.*
import textura.core.data.{ItemKind, ItemStatus}
import textura.ui.*
import textura.views.okr.logic.{formatMetric, formatSchedule, metricProgress, quarterLabel}

/*
 * 表格视图（OkrTable.tsx）、对齐大纲（OkrAlignment.tsx）与空态（OkrPage.tsx 的空态分支）。
 * 几何同样来自 okr.css：表头 8/12 内边距、行 8/12、目标行 9/12；对齐视图的缩进线
 * 10 + 18（KR）与 9 + 16（执行项）。
 */

/** 表格列宽（`.okr-table` 没有固定列宽，这里按内容权重分配；仅表格视图使用）。 */
func tableColumns(width: Float32): Array<Float32> {
    let fixed: Float32 = 140.0 + 130.0 + 170.0 + 112.0 + 96.0
    [140.0, max(160.0, width - fixed), 130.0, 170.0, 112.0, 96.0]
}

func layoutTable(page: OkrPage, ctx: UiContext, cv: PageCanvas, x0: Float32, w: Float32, y: Float32): Float32 {
    let c = page.tokens.color
    let columns = tableColumns(w)
    var totalH: Float32 = 33.5 + 1.0
    let detailed = page.ui.isDetailed()
    for (entry in page.data.entries) {
        let collapsed = page.ui.hasIn(page.ui.collapsed.value, entry.item.id)
        totalH += 40.0 + 1.0
        if (!collapsed) {
            for (kr in entry.krs) {
                totalH += 40.0 + 1.0
                if (page.ui.hasIn(page.ui.expanded.value, kr.item.id)) {
                    totalH += (10.0 + 28.0 + 8.0 + 16.0 + 6.0 + 20.0 + 12.0) + 1.0
                }
            }
        }
    }
    let wrapRect = Rect(x0, y, w, totalH)
    cv.shadow(wrapRect, OKR_R_MD)
    cv.fill(wrapRect, OKR_R_MD, c.surface)
    cv.stroke(wrapRect, OKR_R_MD, c.border)
    // 表头
    let headers = ["目标", "关键结果", "指标", "当前进度", "信心", "执行项"]
    let headerTop = y + 1.0
    cv.fill(Rect(x0 + 1.0, headerTop, w - 2.0, 33.5), 0.0, c.surface2)
    var cursor = x0 + 12.0
    var column = 0
    while (column < 6) {
        cv.text(ctx, cursor, headerTop + 8.0 + 16.5 / 2.0, headers[column], 11.0, 600, c.textMuted)
        cursor += columns[column]
        column += 1
    }
    cv.hLine(x0 + 1.0, x0 + w - 1.0, headerTop + 33.5, c.border)
    var rowY = headerTop + 34.5
    for (entry in page.data.entries) {
        let objectiveId = entry.item.id
        let collapsed = page.ui.hasIn(page.ui.collapsed.value, objectiveId)
        cv.fill(Rect(x0 + 1.0, rowY, w - 2.0, 40.0), 0.0, c.surface2)
        var cx = x0 + 12.0
        cv.icon(Rect(cx, rowY + 20.0 - 7.5, 15.0, 15.0), IconGlyph.ChevronDown, c.textMuted)
        cv.addHotspot("okr-table-obj-${objectiveId}", Rect(cx, rowY + 9.0, 22.0, 22.0)) {
            page.ui.toggleCollapsed(objectiveId)
        }
        cx += 22.0 + OKR_S2
        match (entry.area) {
            case Some(area) =>
                cv.dot(cx + 3.5, rowY + 20.0, 3.5, hexColor(area.color, c.textMuted))
                cx += 7.0 + OKR_S2
            case None => ()
        }
        let titleW = okrTextW(ctx, entry.item.title, 13.0, 650)
        cv.text(ctx, cx, rowY + 20.0, ellipsize(ctx, entry.item.title, 13.0, 650, columns[0] - 40.0), 13.0, 650,
            c.text)
        cx += titleW + OKR_S2
        cx += cv.badge(ctx, cx, rowY + 20.0 - OKR_BADGE_H / 2.0, okrStatusLabel(entry.item.status),
            okrStatusTone(entry.item.status)) + OKR_S2
        cx += cv.text(ctx, cx, rowY + 20.0, "${entry.allKrCount} KR · 信心 ${entry.confidence}", 11.0, 400,
            c.textMuted) + OKR_S2
        let progressW: Float32 = 120.0
        let progressRight = x0 + w - 12.0
        let progressLeft = progressRight - 34.0 - 6.0 - 120.0
        cv.progress(ctx, Rect(progressLeft, rowY + 20.0 - 2.5, progressW, 5.0), Float32(entry.progress),
            okrProgressTone(entry.progress, false), ControlSize.Sm)
        cv.textRight(ctx, progressRight, rowY + 20.0, "${entry.progress}%", 11.0, 400, c.textMuted, mono: true)
        rowY += 40.0
        cv.hLine(x0 + 1.0, x0 + w - 1.0, rowY, c.border)
        rowY += 1.0
        if (collapsed) {
            continue
        }
        for (kr in entry.krs) {
            let krId = kr.item.id
            let expanded = page.ui.hasIn(page.ui.expanded.value, krId)
            if (expanded) {
                cv.fill(Rect(x0 + 1.0, rowY, w - 2.0, 40.0), 0.0, c.accentSoft.lerp(c.surface, 0.55))
            }
            var tx = x0 + 12.0
            cv.text(ctx, tx, rowY + 20.0, ellipsize(ctx, entry.item.title, 11.0, 400, columns[0] - 12.0), 11.0, 400,
                c.textFaint)
            tx += columns[0]
            cv.icon(Rect(tx, rowY + 20.0 - 6.5, 13.0, 13.0), if (expanded) {
                IconGlyph.ChevronDown
            } else {
                IconGlyph.ChevronRight
            }, c.textMuted)
            tx += 17.0
            let krTitleW = okrwTextOrZero(ctx, kr.item.title, 12.5, 550, columns[1] - 30.0)
            cv.text(ctx, tx, rowY + 20.0, ellipsize(ctx, kr.item.title, 12.5, 550, columns[1] - 30.0), 12.5, 550,
                c.text)
            cv.addHotspot("okr-table-kr-${krId}", Rect(tx - 17.0, rowY + 8.0, min(columns[1], krTitleW + 24.0), 24.0)) {
                page.ui.toggleExpanded(krId)
            }
            tx += krTitleW + OKR_S2
            if (kr.behind) {
                tx += cv.badge(ctx, tx, rowY + 20.0 - OKR_BADGE_H / 2.0, "落后", BadgeTone.Danger, dot: true) + 6.0
            }
            if (kr.lacksGrip()) {
                tx += cv.badge(ctx, tx, rowY + 20.0 - OKR_BADGE_H / 2.0, "缺少抓手", BadgeTone.Warn, dot: true)
            }
            var mx = x0 + 12.0 + columns[0] + columns[1]
            cv.text(ctx, mx, rowY + 20.0, formatMetric(kr.metric), 11.5, 400, c.textMuted, mono: true)
            mx += columns[2]
            cv.progress(ctx, Rect(mx, rowY + 20.0 - 2.5, 112.0, 5.0), Float32(kr.progress),
                okrProgressTone(kr.progress, kr.behind), ControlSize.Sm)
            cv.textRight(ctx, mx + columns[3] - 12.0, rowY + 20.0, "${kr.progress}%", 11.0, 400, c.textMuted,
                mono: true)
            let confidenceX = mx + columns[3] + 12.0
            cv.badge(ctx, confidenceX, rowY + 20.0 - OKR_BADGE_H / 2.0,
                "${kr.confidence} · ${confidenceLabel(kr.confidence)}", confidenceTone(kr.confidence), dot: true)
            let countX = x0 + w - 12.0 - 22.0
            cv.textCenter(ctx, countX + 11.0, rowY + 20.0, "${kr.execs.size}", 11.0, 400, c.textMuted, mono: true)
            rowY += 40.0
            cv.hLine(x0 + 1.0, x0 + w - 1.0, rowY, c.border)
            rowY += 1.0
            if (expanded) {
                let detailH: Float32 = 10.0 + 28.0 + 8.0 + 16.0 + 6.0 + 20.0 + 12.0
                cv.fill(Rect(x0 + 1.0, rowY, w - 2.0, detailH), 0.0, c.surface2)
                cv.fill(Rect(x0 + 1.0, rowY, 2.0, detailH), 0.0, c.accent)
                layoutMetricEditor(page, ctx, cv, kr, x0 + 28.0, rowY + 10.0, w - 40.0)
                let metaY = rowY + 10.0 + 28.0 + 6.0
                var metaX = x0 + 28.0
                metaX += cv.badge(ctx, metaX, metaY, okrStatusLabel(kr.item.status),
                    okrStatusTone(kr.item.status)) + OKR_S3
                let ownerText = if (kr.owner.isEmpty()) {
                    "未指派"
                } else {
                    kr.owner
                }
                metaX += cv.text(ctx, metaX, metaY + OKR_BADGE_H / 2.0, "负责人：${ownerText}", 11.5, 400,
                    c.textMuted) + OKR_S3
                metaX += cv.text(ctx, metaX, metaY + OKR_BADGE_H / 2.0, "信心：${kr.confidence}/10", 11.5, 400,
                    c.textMuted) + OKR_S3
                let pace = if (kr.behind) {
                    "落后时间进度 ${Int64(roundPercent(page.data.summary.elapsedPercent - Float64(kr.progress)))} 个点"
                } else {
                    "进度不落后于时间进度"
                }
                cv.text(ctx, metaX, metaY + OKR_BADGE_H / 2.0, pace, 11.5, if (kr.behind) {
                    550
                } else {
                    400
                }, if (kr.behind) {
                    c.dangerInk
                } else {
                    c.textMuted
                })
                rowY += detailH
                cv.hLine(x0 + 1.0, x0 + w - 1.0, rowY, c.border)
                rowY += 1.0
            }
        }
        _ = detailed
    }
    y + totalH
}

func okrwTextOrZero(ctx: UiContext, text: String, size: Float32, weight: Int64, limit: Float32): Float32 {
    min(okrTextW(ctx, text, size, weight), limit)
}

/** 对齐大纲（OkrAlignment.tsx / okr.css:1105-1274）。 */
func layoutAlignment(page: OkrPage, ctx: UiContext, cv: PageCanvas, x0: Float32, w: Float32, y: Float32): Float32 {
    let c = page.tokens.color
    // 先算高度：Objective 行 24 + 6 + border，KR 行 20 + 4/exec 行
    var bodyH: Float32 = 0.0
    for (entry in page.data.entries) {
        bodyH += 24.0 + 6.0 + 1.0 + 6.0
        if (entry.krs.size == 0) {
            bodyH += 17.0
        } else {
            for (kr in entry.krs) {
                bodyH += 20.0 + 4.0
                if (kr.execs.size > 0) {
                    bodyH += Float32(kr.execs.size) * 26.0
                } else {
                    bodyH += 20.0
                }
            }
            bodyH += Float32(entry.krs.size) * 8.0
        }
        bodyH += OKR_S4
    }
    let cardH = OKR_S4 + bodyH + OKR_S4
    let cardRect = Rect(x0, y, w, cardH)
    cv.shadow(cardRect, OKR_R_MD)
    cv.fill(cardRect, OKR_R_MD, c.surface)
    cv.stroke(cardRect, OKR_R_MD, c.border)
    var cursor = y + 1.0 + OKR_S4
    let left = x0 + 1.0 + OKR_S4
    let right = x0 + w - 1.0 - OKR_S4
    for (entry in page.data.entries) {
        let objectiveId = entry.item.id
        cv.icon(Rect(left, cursor + 3.0, 15.0, 15.0), IconGlyph.Target, c.text)
        let titleW = okrTextW(ctx, entry.item.title, 15.0, 650)
        cv.text(ctx, left + 15.0 + 7.0, cursor + 10.5, entry.item.title, 15.0, 650, c.text)
        cv.addHotspot("okr-align-obj-${objectiveId}", Rect(left, cursor, min(titleW + 22.0, right - left), 21.0)) {
            page.store.select(objectiveId)
            page.ui.view.value = OKR_VIEW_CARDS
        }
        var metaRight = right
        let confBadge = "信心 ${entry.confidence}"
        let confW = page.badgeWidth(ctx, confBadge, false)
        metaRight -= confW
        cv.badge(ctx, metaRight, cursor + 3.0, confBadge, confidenceTone(entry.confidence))
        metaRight -= OKR_S2
        let progressBadge = "O · ${entry.progress}%"
        let progressW = page.badgeWidth(ctx, progressBadge, false)
        metaRight -= progressW
        cv.badge(ctx, metaRight, cursor + 3.0, progressBadge, BadgeTone.Neutral)
        metaRight -= OKR_S2
        let statusLabel = okrStatusLabel(entry.item.status)
        let statusW = page.badgeWidth(ctx, statusLabel, false)
        metaRight -= statusW
        cv.badge(ctx, metaRight, cursor + 3.0, statusLabel, okrStatusTone(entry.item.status))
        match (entry.area) {
            case Some(area) =>
                metaRight -= OKR_S2
                let nameW = okrTextW(ctx, area.name, 11.5, 400)
                cv.dot(metaRight - nameW - 5.0 - 7.0 + 3.5, cursor + 10.5, 3.5, hexColor(area.color, c.textMuted))
                cv.textRight(ctx, metaRight, cursor + 10.5, area.name, 11.5, 400, c.textMuted)
            case None => ()
        }
        cursor += 24.0 + 6.0
        cv.hLine(left, right, cursor, c.border)
        cursor += 1.0 + 6.0
        let krLeft = left + 10.0 + 18.0
        cv.vLine(left + 10.0, cursor - 6.0, cursor + bodyH - 6.0, c.textFaint)
        if (entry.krs.size == 0) {
            cv.text(ctx, krLeft, cursor + 8.0, "没有关键结果 · 这个目标缺少可量化的支撑。", 11.5, 400, c.textFaint)
            cursor += 17.0 + OKR_S4
            continue
        }
        for (kr in entry.krs) {
            let krId = kr.item.id
            cv.icon(Rect(krLeft, cursor + 3.5, 14.0, 14.0), IconGlyph.Flag, c.textMuted)
            let krTitleW = okrTextW(ctx, kr.item.title, 13.5, 600)
            cv.text(ctx, krLeft + 14.0 + 7.0, cursor + 10.5, kr.item.title, 13.5, 600, c.text)
            cv.addHotspot("okr-align-kr-${krId}", Rect(krLeft, cursor, min(krTitleW + 21.0, right - krLeft), 21.0)) {
                page.store.select(krId)
                page.ui.view.value = OKR_VIEW_CARDS
            }
            var metaRight = right
            if (kr.lacksGrip()) {
                let gripW = page.badgeWidth(ctx, "缺少抓手", true)
                metaRight -= gripW
                cv.badge(ctx, metaRight, cursor + 3.0, "缺少抓手", BadgeTone.Warn, dot: true)
                metaRight -= OKR_S2
            }
            if (kr.behind) {
                let behindW = page.badgeWidth(ctx, "落后", true)
                metaRight -= behindW
                cv.badge(ctx, metaRight, cursor + 3.0, "落后", BadgeTone.Danger, dot: true)
                metaRight -= OKR_S2
            }
            let confW = page.badgeWidth(ctx, "${kr.confidence}", true)
            metaRight -= confW
            cv.badge(ctx, metaRight, cursor + 3.0, "${kr.confidence}", confidenceTone(kr.confidence), dot: true)
            metaRight -= OKR_S2
            let pctW = okrTextW(ctx, "${kr.progress}%", 11.0, 400, mono: true)
            metaRight -= pctW
            cv.text(ctx, metaRight, cursor + 10.5, "${kr.progress}%", 11.0, 400, c.textMuted, mono: true)
            metaRight -= 5.0
            metaRight -= 70.0
            cv.progress(ctx, Rect(metaRight, cursor + 8.0, 70.0, 5.0), Float32(kr.progress),
                okrProgressTone(kr.progress, kr.behind), ControlSize.Sm)
            metaRight -= OKR_S2
            let metricText = formatMetric(kr.metric)
            let metricW = okrTextW(ctx, metricText, 11.0, 400, mono: true)
            metaRight -= metricW
            cv.text(ctx, metaRight, cursor + 10.5, metricText, 11.0, 400, c.textMuted, mono: true)
            cursor += 20.0 + 4.0
            if (kr.execs.size == 0) {
                cv.text(ctx, krLeft + 9.0 + 16.0, cursor + 10.0, "没有关联执行项。", 11.5, 400, c.textFaint)
                cursor += 20.0
            } else {
                let execX = krLeft + 9.0
                cv.vLine(execX, cursor, cursor + Float32(kr.execs.size) * 26.0, c.textFaint, dashed: true)
                for (exec in kr.execs) {
                    let rowLeft = execX + 16.0
                    cv.icon(Rect(rowLeft, cursor + 6.0, 13.0, 13.0), if (exec.item.kind == ItemKind.Project) {
                        IconGlyph.Folder
                    } else {
                        IconGlyph.Check
                    }, c.textMuted)
                    let done = exec.item.status == ItemStatus.Done
                    let itemProgress: Int64 = if (done) {
                        100
                    } else {
                        match (exec.item.gantt) {
                            case Some(gantt) => Int64(roundPercent(gantt.progress))
                            case None => 0
                        }
                    }
                    cv.text(ctx, rowLeft + 13.0 + OKR_S2, cursor + 12.0, ellipsize(ctx, exec.item.title, 12.0, 400, 420.0),
                        12.0, 400, c.text)
                    cv.addHotspot("okr-align-exec-${exec.item.id}", Rect(rowLeft, cursor, min(600.0, right - rowLeft),
                        24.0)) {
                        page.store.select(exec.item.id)
                    }
                    var emRight = right
                    emRight -= cv.textRight(ctx, emRight, cursor + 12.0, "${itemProgress}%", 10.5, 400, c.textMuted, mono: true)
                    emRight -= OKR_S2
                    emRight -= cv.textRight(ctx, emRight, cursor + 12.0, formatSchedule(exec.schedule()), 10.5, 400,
                        c.textFaint, mono: true)
                    emRight -= OKR_S2
                    emRight -= page.badgeWidth(ctx, okrStatusLabel(exec.item.status), false)
                    cv.badge(ctx, emRight, cursor + 1.0, okrStatusLabel(exec.item.status),
                        okrStatusTone(exec.item.status))
                    cursor += 26.0
                }
            }
            cursor += OKR_S2
        }
        cursor += OKR_S4
    }
    y + cardH
}

/** 空态（OkrPage.tsx 的 `okr-empty` 分支 / ui.css `.empty-state`）。 */
func layoutEmptyState(page: OkrPage, ctx: UiContext, cv: PageCanvas, x0: Float32, w: Float32, y: Float32): Float32 {
    let c = page.tokens.color
    let hasQuery = page.data.hasQuery()
    let title = if (hasQuery) {
        "没有匹配的目标或 KR"
    } else {
        "本季度还没有目标"
    }
    let description = if (hasQuery) {
        "「${page.data.search.trim()}」没有命中 ${quarterLabel2(page.data.period)} 的目标、关键结果、负责人或 Area。"
    } else {
        "先写一个定性的目标（O），再用 2–4 个可量化的关键结果（KR）定义「做到了」。例如：目标「让新用户第一周就爱上织理」，KR「NPS 从 42 提升到 60」。"
    }
    let descLines = wrapText(ctx, description, 12.5, 400, 420.0)
    let actionW = page.buttonWidth(ctx, if (hasQuery) {
        "清除筛选"
    } else {
        "新建本季度目标"
    }, if (hasQuery) {
        0
    } else {
        1
    }, if (hasQuery) {
        None
    } else {
        Some(IconGlyph.Plus)
    })
    if (hasQuery) {
        let innerH: Float32 = 44.0 + 8.0 + 21.0 + 8.0 + Float32(descLines.size) * 20.0 + 8.0 + 28.0
        let boxH = OKR_S4 + OKR_S3 + innerH + OKR_S3 + OKR_S4
        let boxRect = Rect(x0, y, w, boxH)
        cv.fill(boxRect, OKR_R_LG, c.surface)
        cv.dashed(boxRect, OKR_R_LG, c.borderStrong)
        emptyStateBody(page, ctx, cv, x0 + 1.0, w - 2.0, y + 1.0 + OKR_S4, 44.0, title, descLines, actionW,
            IconGlyph.Search, {=> page.store.setSearch("")}, if (hasQuery) {
                0
            } else {
                1
            })
        return y + boxH
    }
    let innerH: Float32 = 44.0 + 8.0 + 21.0 + 8.0 + Float32(descLines.size) * 20.0 + 8.0 + 34.0
    let tipsH: Float32 = 12.0 + 1.0 + 12.0 + 33.0
    let boxH = OKR_S4 + OKR_S3 + innerH + OKR_S3 + OKR_S3 + tipsH + OKR_S4
    let boxRect = Rect(x0, y, w, boxH)
    cv.fill(boxRect, OKR_R_LG, c.surface)
    cv.dashed(boxRect, OKR_R_LG, c.borderStrong)
    emptyStateBody(page, ctx, cv, x0 + 1.0, w - 2.0, y + 1.0 + OKR_S4, 44.0, title, descLines, actionW,
        IconGlyph.Target, {=> page.openObjectiveDialog()}, 1)
    // 三段提示（`.okr-empty-tips`：3 列、上边框）
    let tipsTop = y + 1.0 + OKR_S4 + OKR_S3 + innerH + OKR_S3 + OKR_S3
    cv.hLine(x0 + 1.0 + OKR_S4, x0 + w - 1.0 - OKR_S4, tipsTop, c.border)
    let columns = ["目标（O）|一句定性描述，方向明确、鼓舞人心，不堆数字。",
        "关键结果（KR）|可量化、可验证，带起点与目标值，2–4 个即可。",
        "执行项|把甘特 / GTD 里的项目与行动关联到 KR，形成抓手。"]
    let columnW = (w - 2.0 - OKR_S4 * 2.0 - OKR_S3 * 2.0) / 3.0
    var index = 0
    for (columnText in columns) {
        let parts = columnText.split("|")
        let columnX = x0 + 1.0 + OKR_S4 + Float32(index) * (columnW + OKR_S3)
        cv.text(ctx, columnX, tipsTop + 12.0 + 12.5 * 1.5 / 2.0, parts[0], 12.5, 600, c.text)
        let lines = wrapText(ctx, parts[1], 12.0, 400, columnW)
        var lineIndex = 0
        for (line in lines) {
            cv.text(ctx, columnX, tipsTop + 12.0 + 12.5 * 1.5 + 2.0 + 12.0 * 1.5 * (Float32(lineIndex) + 0.5), line,
                12.0, 400, c.textMuted)
            lineIndex += 1
        }
        index += 1
    }
    y + boxH
}

func emptyStateBody(page: OkrPage, ctx: UiContext, cv: PageCanvas, x0: Float32, w: Float32, y: Float32,
    iconSide: Float32, title: String, descLines: Array<String>, actionW: Float32, glyph: IconGlyph,
    action: () -> Unit, actionVariant: Int64): Unit {
    let c = page.tokens.color
    let innerW = min(420.0, w - OKR_S4 * 2.0)
    let left = x0 + (w - innerW) / 2.0
    cv.fill(Rect(x0 + w / 2.0 - 22.0, y, 44.0, 44.0), OKR_R_LG, c.surface2)
    cv.stroke(Rect(x0 + w / 2.0 - 22.0, y, 44.0, 44.0), OKR_R_LG, c.border)
    cv.icon(Rect(x0 + w / 2.0 - 11.0, y + 11.0, 22.0, 22.0), glyph, c.textFaint)
    var cursor = y + 44.0 + OKR_S2
    cv.textCenter(ctx, x0 + w / 2.0, cursor + 14.0 * 1.5 / 2.0, title, 14.0, 600, c.text)
    cursor += 14.0 * 1.5 + OKR_S2
    for (line in descLines) {
        cv.textCenter(ctx, x0 + w / 2.0, cursor + 20.0 / 2.0, line, 12.5, 400, c.textMuted)
        cursor += 20.0
    }
    cursor += OKR_S2
    let buttonRect = Rect(x0 + w / 2.0 - actionW / 2.0, cursor, actionW, if (actionVariant == 1) {
        34.0
    } else {
        28.0
    })
    page.paintButton(ctx, cv, "okr-empty-new", buttonRect, if (actionVariant == 1) {
        "新建本季度目标"
    } else {
        "清除筛选"
    }, if (actionVariant == 1) {
        OKR_BTN_PRIMARY
    } else {
        OKR_BTN_SECONDARY
    }, if (actionVariant == 1) {
        1
    } else {
        0
    }, if (actionVariant == 1) {
        Some(IconGlyph.Plus)
    } else {
        None
    }, true, action)
    _ = left
    _ = iconSide
}

func quarterLabel2(period: String): String {
    quarterLabel(period)
}
