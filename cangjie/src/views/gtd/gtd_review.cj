package textura.views.gtd

import std.collection.*
import cui.*
import textura.ui.*
import textura.views.gtd.logic as gl

/*
 * 周回顾（WeeklyReview.tsx 1-364 + gtd.css:634-864）。
 *
 * 概览卡：本周回顾 eyebrow + 「让系统重新可信」+ 区间/收件箱/停滞项目摘要 + 240px 回顾完成度
 * + 全部标记已回顾；下面 2 列卡片网格：收件箱清零 / 本周完成 / 超期承诺 / 停滞项目 /
 * 等待超 7 天 / 无日期任务（+ 长期无动作的领域）。
 */

func gtdWeeklyReview(scene: GtdScene): Unit {
    let tokens = scene.tokens
    let stats = gl.weeklyReview(scene.gws, scene.today)
    let cardIds = reviewCardIds(stats)
    let reviewedCount = reviewedCountOf(scene, cardIds)
    let reviewedPercent = if (cardIds.size == 0) {
        0
    } else {
        (reviewedCount * 100 + cardIds.size / 2) / cardIds.size
    }
    VStack(spacing: vp(PAGE_GAP)) {
        // 概览（gtd.css:641-691）
        VStack(spacing: vp(0.0)) {
            HStack(spacing: vp(REVIEW_OVERVIEW_GAP)) {
                VStack(spacing: vp(0.0)) {
                    HStack(spacing: vp(6.0)) {
                        IconView(IconGlyph.Calendar, side: 14.0, color: tokens.color.accent)
                        GtdText("本周回顾", REVIEW_EYEBROW_SIZE, REVIEW_EYEBROW_WEIGHT, tokens.color.accent,
                            boxHeight: REVIEW_EYEBROW_SIZE * LINE_HEIGHT)
                    }.crossAxisAlignment(CrossAxisAlignment.Center).hug()
                    GtdText("让系统重新可信", REVIEW_H2_SIZE, REVIEW_H2_WEIGHT, tokens.color.text,
                        boxHeight: REVIEW_H2_SIZE * LINE_HEIGHT)
                        .padding(vp(0.0), vp(REVIEW_TEXT_MT), vp(0.0), vp(0.0))
                    GtdText(
                        "${stats.windowStart} → ${stats.today} · 收件箱 ${stats.inboxCount} 条 · 停滞项目 " +
                            "${stats.stuckProjectCount} 个",
                        REVIEW_P_SIZE, 400, tokens.color.textMuted, boxHeight: REVIEW_P_SIZE * LINE_HEIGHT)
                        .padding(vp(0.0), vp(REVIEW_TEXT_MT), vp(0.0), vp(0.0))
                }.hug().flex()
                VStack(spacing: vp(0.0)) {
                    HStack(spacing: vp(0.0)) {
                        GtdText("回顾完成度", META_SIZE, 400, tokens.color.textMuted,
                            boxHeight: META_SIZE * LINE_HEIGHT)
                        Spacer()
                        GtdText("${reviewedCount} / ${cardIds.size}", META_SIZE, 400, tokens.color.textMuted,
                            boxHeight: META_SIZE * LINE_HEIGHT)
                    }.hug().fillWidth()
                    Ui.progress(scene.theme, Float32(reviewedPercent), tone: if (reviewedPercent == 100) {
                        ProgressTone.Ok
                    } else {
                        ProgressTone.Accent
                    }, showLabel: true)
                }.hug().width(REVIEW_PROGRESS_W)
                Ui.button(scene.theme, if (reviewedCount == cardIds.size) {
                    "重置回顾状态"
                } else {
                    "全部标记已回顾"
                }, {=> markAllReviewed(scene, cardIds)}, variant: ButtonVariant.Secondary, size: ControlSize.Sm)
            }
                .crossAxisAlignment(CrossAxisAlignment.Center)
                .hug()
                .fillWidth()
                .padding(vp(REVIEW_OVERVIEW_PAD_H), vp(REVIEW_OVERVIEW_PAD_V), vp(REVIEW_OVERVIEW_PAD_H), vp(REVIEW_OVERVIEW_PAD_V))
        }
            .hug()
            .fillWidth()
            .background(tokens.color.surface, SECTION_RADIUS)
            .border(tokens.color.border, width: tokens.metrics.borderWidth, radius: SECTION_RADIUS)
        // 卡片网格（两列）
        VStack(spacing: vp(REVIEW_GRID_GAP)) {
            reviewRow(scene, stats, cardIds, 0)
            reviewRow(scene, stats, cardIds, 1)
            reviewRow(scene, stats, cardIds, 2)
            reviewRow(scene, stats, cardIds, 3)
        }.hug().fillWidth()
    }.hug().fillWidth()
}

func reviewCardIds(stats: gl.WeeklyReviewStats): Array<String> {
    let ids = ArrayList<String>()
    ids.add("inbox")
    ids.add("completed")
    ids.add("overdue")
    ids.add("stuck")
    ids.add("waiting")
    ids.add("undated")
    if (stats.staleAreas.size > 0) {
        ids.add("stale")
    }
    ids.toArray()
}

func reviewedCountOf(scene: GtdScene, cardIds: Array<String>): Int64 {
    var count: Int64 = 0
    for (id in cardIds) {
        if (setHas(scene.state.reviewed.value, id)) {
            count += 1
        }
    }
    count
}

func markAllReviewed(scene: GtdScene, cardIds: Array<String>): Unit {
    if (reviewedCountOf(scene, cardIds) == cardIds.size) {
        scene.state.reviewed.value = ""
        return
    }
    var encoded = ""
    var index = 0
    for (id in cardIds) {
        if (index > 0) {
            encoded += "\n"
        }
        encoded += id
        index += 1
    }
    scene.state.reviewed.value = encoded
}

/** 一行两张卡片；最后一行的第二张可能是停滞领域卡或空。 */
func reviewRow(scene: GtdScene, stats: gl.WeeklyReviewStats, cardIds: Array<String>, row: Int64): Unit {
    HStack(spacing: vp(REVIEW_GRID_GAP)) {
        if (row * 2 < cardIds.size) {
            VStack(spacing: vp(0.0)) {
                reviewCard(scene, stats, cardIds[row * 2])
            }.hug().flex()
        }
        if (row * 2 + 1 < cardIds.size) {
            VStack(spacing: vp(0.0)) {
                reviewCard(scene, stats, cardIds[row * 2 + 1])
            }.hug().flex()
        } else {
            VStack(spacing: vp(0.0)) {
                Spacer()
            }.flex()
        }
    }.crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
}

func reviewCard(scene: GtdScene, stats: gl.WeeklyReviewStats, id: String): Unit {
    let tokens = scene.tokens
    let reviewed = setHas(scene.state.reviewed.value, id)
    let head = reviewCardHead(stats, id)
    VStack(spacing: vp(REVIEW_CARD_GAP)) {
        // head：标题 + kicker + 标记已回顾
        HStack(spacing: vp(12.0)) {
            VStack(spacing: vp(0.0)) {
                GtdText(head.title, REVIEW_CARD_TITLE_SIZE, REVIEW_CARD_TITLE_WEIGHT, tokens.color.text,
                    boxHeight: REVIEW_CARD_TITLE_SIZE * LINE_HEIGHT)
                GtdText(head.kicker, REVIEW_CARD_KICKER_SIZE, 400, tokens.color.textFaint,
                    boxHeight: REVIEW_CARD_KICKER_SIZE * LINE_HEIGHT)
                    .padding(vp(0.0), vp(REVIEW_TEXT_MT), vp(0.0), vp(0.0))
            }.hug().flex()
            Ui.button(scene.theme, if (reviewed) {
                "已回顾"
            } else {
                "标记已回顾"
            }, {=> scene.state.reviewed.value = setToggle(scene.state.reviewed.value, id)},
                variant: if (reviewed) {
                    ButtonVariant.Secondary
                } else {
                    ButtonVariant.Ghost
                }, size: ControlSize.Sm, iconLeft: IconGlyph.Check)
        }
            .crossAxisAlignment(CrossAxisAlignment.Start)
            .hug()
            .fillWidth()
        // metric（28px 数值 + 单位）
        HStack(spacing: vp(REVIEW_METRIC_GAP)) {
            GtdText("${head.value}", REVIEW_METRIC_SIZE, REVIEW_METRIC_WEIGHT, metricInk(tokens, head.tone),
                boxHeight: REVIEW_METRIC_SIZE)
            GtdText(head.unit, REVIEW_METRIC_UNIT_SIZE, 400, tokens.color.textMuted,
                boxHeight: REVIEW_METRIC_UNIT_SIZE * LINE_HEIGHT)
        }.crossAxisAlignment(CrossAxisAlignment.End).hug()
        // body
        VStack(spacing: vp(8.0)) {
            if (id == "inbox") {
                Ui.progress(scene.theme, Float32(stats.inboxProgress), tone: if (stats.inboxProgress == 100) {
                    ProgressTone.Ok
                } else {
                    ProgressTone.Accent
                }, size: ControlSize.Sm, showLabel: true)
                reviewItems(scene, stats.inbox, "收件箱已清空。", {item =>
                    let capturedAt = match (item.capturedAt) {
                        case Some(value) => Some(value)
                        case None => Some(item.createdAt)
                    }
                    gl.relativeTimeLabel(capturedAt, scene.today)
                })
            } else if (id == "completed") {
                reviewItems(scene, stats.completedThisWeek, "本周还没有完成记录，先挑一件小事做完。",
                    {item => gl.relativeTimeLabel(item.completedAt, scene.today)})
            } else if (id == "overdue") {
                reviewItems(scene, stats.overdue, "没有超期事项。",
                    {item => gl.deadlineInfo(item, stats.today).label})
            } else if (id == "stuck") {
                reviewItems(scene, stats.stuckProjects, "所有项目都有正在推进的下一步。", {item =>
                    let tags = item.tags
                    if (tags.isEmpty()) {
                        "项目 · 无标签"
                    } else {
                        "项目 · " + joinWith(tags, " / ")
                    }
                })
            } else if (id == "waiting") {
                reviewItems(scene, stats.waitingOverdue, "没有超过 7 天的等待。",
                    {item => "已等待 ${gl.waitingDays(item, stats.today)} 天"})
            } else if (id == "undated") {
                reviewItems(scene, stats.undatedTasks, "所有可执行事项都有日期。", {item =>
                    match (gl.contextOf(item)) {
                        case Some(value) => value
                        case None => gl.NO_CONTEXT
                    }
                })
            } else {
                staleAreaList(scene, stats)
            }
        }.hug().fillWidth()
        // footer：动作按钮
        HStack(spacing: vp(4.0)) {
            reviewAction(scene, id)
            Spacer()
        }.crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
    }
        .hug()
        .fillWidth()
        .padding(vp(REVIEW_CARD_PAD))
        .background(tokens.color.surface, SECTION_RADIUS)
        .border(if (reviewed) {
            tokens.color.ok
        } else {
            tokens.color.border
        }, width: tokens.metrics.borderWidth, radius: SECTION_RADIUS)
}

func metricInk(tokens: ThemeTokens, tone: String): Color {
    if (tone == "accent") {
        tokens.color.accent
    } else if (tone == "ok") {
        tokens.color.ok
    } else if (tone == "warn") {
        tokens.color.warn
    } else if (tone == "danger") {
        tokens.color.danger
    } else {
        tokens.color.text
    }
}

class ReviewHead {
    let title: String
    let kicker: String
    let value: Int64
    let unit: String
    let tone: String

    init(title: String, kicker: String, value: Int64, unit: String, tone: String) {
        this.title = title
        this.kicker = kicker
        this.value = value
        this.unit = unit
        this.tone = tone
    }
}

func reviewCardHead(stats: gl.WeeklyReviewStats, id: String): ReviewHead {
    if (id == "inbox") {
        return ReviewHead("收件箱清零", "收集之后没有澄清，系统就会失真", stats.inboxCount,
            "条待澄清", if (stats.inboxCount > 0) {
                "danger"
            } else {
                "ok"
            })
    }
    if (id == "completed") {
        return ReviewHead("本周完成", "最近 7 天已完成的事项", stats.completedCount, "条完成",
            if (stats.completedCount > 0) {
                "ok"
            } else {
                "neutral"
            })
    }
    if (id == "overdue") {
        return ReviewHead("超期承诺", "截止日期已过且未完成", stats.overdueCount, "条超期",
            if (stats.overdueCount > 0) {
                "danger"
            } else {
                "ok"
            })
    }
    if (id == "stuck") {
        return ReviewHead("停滞项目", "没有「下一步」子动作的项目", stats.stuckProjectCount, "个项目",
            if (stats.stuckProjectCount > 0) {
                "warn"
            } else {
                "ok"
            })
    }
    if (id == "waiting") {
        return ReviewHead("等待超 7 天", "委派出去、需要催办的事项", stats.waitingOverdueCount, "条等待",
            if (stats.waitingOverdueCount > 0) {
                "warn"
            } else {
                "ok"
            })
    }
    if (id == "undated") {
        return ReviewHead("无日期任务", "没有截止日期的下一步 / 进行中动作", stats.undatedCount, "条未排期",
            if (stats.undatedCount > 0) {
                "warn"
            } else {
                "ok"
            })
    }
    ReviewHead("长期无动作的领域", "14 天内没有更新的开放动作", stats.staleAreas.size, "个领域", "warn")
}

func reviewAction(scene: GtdScene, id: String): Unit {
    let theme = scene.theme
    if (id == "inbox") {
        Ui.button(theme, "去逐条澄清", {=> scene.focusSection("inbox")}, size: ControlSize.Sm)
    } else if (id == "completed") {
        Ui.button(theme, "在今日回看", {=> scene.ctx.navigate("dashboard")}, size: ControlSize.Sm)
    } else if (id == "overdue") {
        Ui.button(theme, "处理超期", {=> scene.focusSection("next")}, size: ControlSize.Sm)
    } else if (id == "stuck") {
        Ui.button(theme, "查看项目", {=> scene.focusSection("projects")}, size: ControlSize.Sm)
    } else if (id == "waiting") {
        Ui.button(theme, "去催办", {=> scene.focusSection("waiting")}, size: ControlSize.Sm)
    } else if (id == "undated") {
        Ui.button(theme, "安排日期", {=> scene.focusSection("next")}, size: ControlSize.Sm)
    } else {
        Ui.button(theme, "查看下一步", {=> scene.focusSection("next")}, size: ControlSize.Sm)
    }
}

/** `.gtd-review-list`（gtd.css:789-830）：最多 5 条 + 「查看全部」。 */
func reviewItems(scene: GtdScene, items: Array<gl.GtdItem>, empty: String, meta: (gl.GtdItem) -> String): Unit {
    let tokens = scene.tokens
    if (items.isEmpty()) {
        gtdBadge(tokens, empty, BadgeTone.Ok, dot: true)
        return
    }
    VStack(spacing: vp(0.0)) {
        ForEachIndexed(items) {index, item =>
            if (index < 5) {
                reviewItemRow(scene, item, index, items.size, meta)
            }}
        if (items.size > 5) {
            GtdLinkButton(tokens, "查看全部 ${items.size} 条", "gtd-review-all:${empty}", {=> ()})
        }
    }.hug().fillWidth()
}

/** 单条回顾清单行（`.gtd-review-item`：6px 间距、3px 上下内边距、虚线分隔）。 */
func reviewItemRow(scene: GtdScene, item: gl.GtdItem, index: Int64, total: Int64,
    meta: (gl.GtdItem) -> String): Unit {
    let tokens = scene.tokens
    VStack(spacing: vp(0.0)) {
        HStack(spacing: vp(REVIEW_ITEM_GAP)) {
            HStack(spacing: vp(0.0)) {
                Spacer()
            }.width(REVIEW_DOT).height(REVIEW_DOT).background(tokens.color.borderStrong, REVIEW_DOT / 2.0)
            GtdText(item.title, REVIEW_ITEM_SIZE, 400, tokens.color.text,
                boxHeight: REVIEW_ITEM_SIZE * LINE_HEIGHT).flex()
            GtdText(meta(item), REVIEW_ITEM_META_SIZE, 400, tokens.color.textFaint,
                boxHeight: REVIEW_ITEM_META_SIZE * LINE_HEIGHT)
        }
            .crossAxisAlignment(CrossAxisAlignment.Center)
            .hug()
            .fillWidth()
            .padding(vp(0.0), vp(REVIEW_ITEM_PAD_V), vp(0.0), vp(REVIEW_ITEM_PAD_V))
        if (index < total - 1 && index < 4) {
            GtdDashedRule(tokens.color.border)
        }
    }.hug().fillWidth()
}

/** 停滞领域清单（gtd.css:789-830 + WeeklyReview.tsx `staleAreas.slice(0, 5)`）。 */
func staleAreaList(scene: GtdScene, stats: gl.WeeklyReviewStats): Unit {
    let tokens = scene.tokens
    VStack(spacing: vp(0.0)) {
        ForEachIndexed(stats.staleAreas) {index, entry =>
            if (index < 5) {
                staleAreaRow(scene, entry, stats)
            }}
    }.hug().fillWidth()
}

func staleAreaRow(scene: GtdScene, entry: gl.StaleArea, stats: gl.WeeklyReviewStats): Unit {
    let tokens = scene.tokens
    let dotColor = match (scene.areaColor(Some(entry.area.id))) {
        case Some(value) => value
        case None => tokens.color.borderStrong
    }
    HStack(spacing: vp(REVIEW_ITEM_GAP)) {
        HStack(spacing: vp(0.0)) {
            Spacer()
        }.width(AREA_DOT).height(AREA_DOT).background(dotColor, AREA_DOT / 2.0)
        GtdText(entry.area.name, REVIEW_ITEM_SIZE, 400, tokens.color.text,
            boxHeight: REVIEW_ITEM_SIZE * LINE_HEIGHT).flex()
        GtdText("${entry.openCount} 条 · 最近 ${gl.relativeTimeLabel(entry.lastTouched, stats.today)}",
            REVIEW_ITEM_META_SIZE, 400, tokens.color.textFaint,
            boxHeight: REVIEW_ITEM_META_SIZE * LINE_HEIGHT)
    }
        .crossAxisAlignment(CrossAxisAlignment.Center)
        .hug()
        .fillWidth()
        .padding(vp(0.0), vp(REVIEW_ITEM_PAD_V), vp(0.0), vp(REVIEW_ITEM_PAD_V))
}

func joinWith(values: Array<String>, separator: String): String {
    var result = ""
    var index = 0
    for (value in values) {
        if (index > 0) {
            result += separator
        }
        result += value
        index += 1
    }
    result
}
