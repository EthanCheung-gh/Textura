package textura.views.gtd

import std.collection.*
import cui.*
import textura.core.data.*
import textura.ui.*
import textura.views.gtd.logic as gl

/*
 * 侧栏两个列表：等待中（WaitingList.tsx 1-100）与某天/搁置（SomedayList.tsx 1-73）。
 * 行几何来自 gtd.css:551-573：9px 上下内边距、间距 8、底部 1px 分隔线。
 */

/* ---------------------------------------------------------------- 等待中 */

func gtdWaitingSection(scene: GtdScene): Unit {
    let tokens = scene.tokens
    gtdSectionShell(scene, "waiting") {
        gtdSectionHeader(scene, IconGlyph.Clock, "等待中", scene.waiting.size)
        if (scene.waiting.isEmpty()) {
            gtdEmptyBlock(scene, "没有等待中的事项", "委派出去的事会在这里跟踪。", IconGlyph.Clock)
        } else {
            let rows = gl.buildWaitingRows(scene.waiting, scene.today)
            let page = gl.paginateItems(rows, scene.state.waitingLimit.value)
            VStack(spacing: vp(0.0)) {
                ForEachIndexed(page.items) {index, row =>
                    waitingRow(scene, row, index == page.items.size - 1 && page.remaining == 0)}
                if (page.remaining > 0) {
                    gtdShowMore(scene, page.remaining, page.shown, page.total, note: false,
                        onClick: {=> scene.state.waitingLimit.value = scene.state.waitingLimit.value +
                            gl.LIST_PAGE_SIZE})
                }
            }.hug().fillWidth()
        }
    }
}

func waitingRow(scene: GtdScene, row: gl.WaitingRow, last: Bool): Unit {
    let tokens = scene.tokens
    let item = row.item
    let waitingFor = match (gl.nonEmpty(item.waitingFor)) {
        case Some(value) => value
        case None => "未填写等待对象"
    }
    VStack(spacing: vp(0.0)) {
        HStack(spacing: vp(SIDE_GAP)) {
            GtdCheck(tokens, "gtd-waiting-check:${item.id}", "完成「${item.title}」", {=>
                scene.ctx.store.toggleDone(item.id)
                scene.ctx.store.notify("等待事项已完成「${item.title}」", tone: NoticeTone.Success)
            })
            VStack(spacing: vp(META_MARGIN_TOP)) {
                GtdText(item.title, ROW_TITLE_SIZE, ROW_TITLE_WEIGHT, tokens.color.text,
                    boxHeight: lineBox(ROW_TITLE_SIZE, ratio: ROW_TITLE_LH))
                HStack(spacing: vp(META_GAP)) {
                    gtdBadge(tokens, "等待 ${waitingFor}", BadgeTone.Info, dot: true)
                    gtdIconText(scene, IconGlyph.Clock, "已等待 ${row.days} 天",
                        if (row.overdue) {
                            tokens.color.danger
                        } else {
                            tokens.color.textFaint
                        },
                        weight: if (row.overdue) {
                            600
                        } else {
                            400
                        })
                    if (row.overdue) {
                        gtdBadge(tokens, "超过 ${gl.WAITING_WARN_DAYS} 天", BadgeTone.Warn)
                    }
                    Spacer()
                }
                    .crossAxisAlignment(CrossAxisAlignment.Center)
                    .hug()
                    .fillWidth()
            }.hug().flex()
            Ui.button(scene.theme, "催办", {=> scene.run(gl.nudgeWaitingItem(item, scene.now()))},
                variant: if (row.overdue) {
                    ButtonVariant.Secondary
                } else {
                    ButtonVariant.Ghost
                }, size: ControlSize.Sm)
        }
            .crossAxisAlignment(CrossAxisAlignment.Center)
            .hug()
            .fillWidth()
            .padding(vp(SIDE_PAD_H), vp(SIDE_PAD_V), vp(SIDE_PAD_H), vp(SIDE_PAD_V))
        if (!last) {
            gtdRule(tokens.color.border)
        }
    }.hug().fillWidth()
}

/* ---------------------------------------------------------------- 某天 / 搁置 */

func gtdSomedaySection(scene: GtdScene): Unit {
    let tokens = scene.tokens
    gtdSectionShell(scene, "someday") {
        gtdSectionHeader(scene, IconGlyph.Flag, "某天 / 搁置", scene.someday.size)
        if (scene.someday.isEmpty()) {
            gtdEmptyBlock(scene, "没有搁置的想法", "暂时不做的事，放在这里不占注意力。", IconGlyph.Flag)
        } else {
            let page = gl.paginateItems(scene.someday, scene.state.somedayLimit.value)
            VStack(spacing: vp(0.0)) {
                ForEachIndexed(page.items) {index, item =>
                    somedayRow(scene, item, index == page.items.size - 1 && page.remaining == 0)}
                if (page.remaining > 0) {
                    gtdShowMore(scene, page.remaining, page.shown, page.total, note: false,
                        onClick: {=> scene.state.somedayLimit.value = scene.state.somedayLimit.value +
                            gl.LIST_PAGE_SIZE})
                }
            }.hug().fillWidth()
        }
    }
}

func somedayRow(scene: GtdScene, item: gl.GtdItem, last: Bool): Unit {
    let tokens = scene.tokens
    let energy = gl.energyLabel(match (item.energy) {
        case Some(value) => value
        case None => gl.Energy.Medium
    })
    VStack(spacing: vp(0.0)) {
        HStack(spacing: vp(SIDE_GAP)) {
            VStack(spacing: vp(META_MARGIN_TOP)) {
                GtdText(item.title, ROW_TITLE_SIZE, ROW_TITLE_WEIGHT, tokens.color.text,
                    boxHeight: lineBox(ROW_TITLE_SIZE, ratio: ROW_TITLE_LH))
                HStack(spacing: vp(META_GAP)) {
                    match (gl.contextOf(item)) {
                        case Some(value) => gtdBadge(tokens, "@${value}", BadgeTone.Info)
                        case None => ()
                    }
                    gtdBadge(tokens, "能量 ${energy}", BadgeTone.Neutral)
                    Spacer()
                }
                    .crossAxisAlignment(CrossAxisAlignment.Center)
                    .hug()
                    .fillWidth()
            }.hug().flex()
            Ui.button(scene.theme, "激活为下一步",
                {=> scene.run(gl.activateSomedayItem(item, scene.placeholder("act"), scene.now()))},
                variant: ButtonVariant.Ghost, size: ControlSize.Sm, iconLeft: IconGlyph.Play)
        }
            .crossAxisAlignment(CrossAxisAlignment.Center)
            .hug()
            .fillWidth()
            .padding(vp(SIDE_PAD_H), vp(SIDE_PAD_V), vp(SIDE_PAD_H), vp(SIDE_PAD_V))
        if (!last) {
            gtdRule(tokens.color.border)
        }
    }.hug().fillWidth()
}
