package textura.views.gtd

import std.collection.*
import cui.*
import textura.ui.*
import textura.views.gtd.logic as gl

/*
 * 收件箱分区（InboxList.tsx 1-174 + gtd.css:226-342）。
 *
 * 行结构：2px 高亮条 + 16px 内边距 + 主列（标题 13.5/560、元信息 11.5）+ 右侧动作
 * （2 分钟处理 ghost / 转为下一步 secondary / 删除 danger 图标按钮）。
 * 行高由标题行盒 18.225 + 4 + 徽标行 23.6 + 上下 10 推导 = 65.825（与实测 66.8 含 1px 分隔线一致）。
 */

/** 收件箱分区：标题 + 键盘提示 + 列表（空态给「去推进下一步」）。 */
func gtdInboxSection(scene: GtdScene): Unit {
    let tokens = scene.tokens
    gtdSectionShell(scene, "inbox") {
        gtdSectionHeader(scene, IconGlyph.Inbox, "收件箱", scene.inbox.size, hint: {=> inboxHint(scene)})
        if (scene.inbox.isEmpty()) {
            gtdEmptyBlock(scene, "收件箱已清空，去推进下一步", "所有收集到的事项都已澄清，系统重新变得可信。",
                IconGlyph.Inbox,
                action: {=>
                    Ui.button(scene.theme, "去推进下一步", {=> scene.focusSection("next")},
                        variant: ButtonVariant.Primary, size: ControlSize.Sm, iconRight: IconGlyph.ChevronRight)
                })
        } else {
            inboxRows(scene)
        }
    }
}

/** `.gtd-section-note` + `.gtd-kbd-hint`（gtd.css:182-224）。 */
func inboxHint(scene: GtdScene): Unit {
    let tokens = scene.tokens
    GtdText("来自快速收集 · 澄清后进入下一步", NOTE_SIZE, 400, tokens.color.textFaint,
        boxHeight: NOTE_SIZE * LINE_HEIGHT, hoverId: "gtd-inbox-note")
    GtdKbdHint(tokens)
}

func inboxRows(scene: GtdScene): Unit {
    let page = gl.paginateItems(scene.inbox, scene.state.inboxLimit.value)
    // useRowKeyboard.ts:`useState(ids[0] ?? null)` —— 首行默认就是选中行。
    let activeId = resolvedActiveId(scene.state.activeInbox.value, page.items)
    VStack(spacing: vp(0.0)) {
        ForEachIndexed(page.items) {index, item =>
            inboxRow(scene, item, index == page.items.size - 1, activeId)
        }
        if (page.remaining > 0) {
            gtdShowMore(scene, page.remaining, page.shown, page.total,
                onClick: {=> scene.state.inboxLimit.value = scene.state.inboxLimit.value + gl.LIST_PAGE_SIZE})
        }
    }.hug().fillWidth()
}

func inboxRow(scene: GtdScene, item: gl.GtdItem, last: Bool, activeId: String): Unit {
    let tokens = scene.tokens
    let active = activeId == item.id
    let capturedAt = match (item.capturedAt) {
        case Some(value) => Some(value)
        case None => Some(item.createdAt)
    }
    VStack(spacing: vp(0.0)) {
        HStack(spacing: vp(0.0)) {
            gtdRowEdge(if (active) {
                tokens.color.accent
            } else {
                Color.rgba(0, 0, 0, 0)
            })
            HStack(spacing: vp(ROW_GAP)) {
                VStack(spacing: vp(META_MARGIN_TOP)) {
                    GtdText(item.title, ROW_TITLE_SIZE, ROW_TITLE_WEIGHT, tokens.color.text,
                        boxHeight: lineBox(ROW_TITLE_SIZE, ratio: ROW_TITLE_LH), hoverColor: tokens.color.accent,
                        hoverId: "gtd-inbox-title:${item.id}", onClick: {=>
                            scene.state.activeInbox.value = item.id
                            scene.state.keyTarget.value = "inbox"
                            scene.openClarify(item.id)
                        })
                    HStack(spacing: vp(META_GAP)) {
                        for (tag in item.tags) {
                            gtdBadge(tokens, "#${tag}", BadgeTone.Neutral)
                        }
                        match (gl.contextOf(item)) {
                            case Some(value) => gtdBadge(tokens, "@${value}", BadgeTone.Info)
                            case None => ()
                        }
                        if (item.twoMinuteCandidate) {
                            gtdBadge(tokens, "2 分钟可完成", BadgeTone.Warn, dot: true)
                        }
                        gtdIconText(scene, IconGlyph.Clock, gl.relativeTimeLabel(capturedAt, scene.today),
                            tokens.color.textFaint)
                    }
                        .crossAxisAlignment(CrossAxisAlignment.Center)
                        .hug()
                        .fillWidth()
                }.hug().flex()
                HStack(spacing: vp(INLINE_GAP)) {
                    Ui.button(scene.theme, "2 分钟处理", {=> scene.run(gl.completeInboxItem(item))},
                        variant: ButtonVariant.Ghost, size: ControlSize.Sm, iconLeft: IconGlyph.Check)
                    Ui.button(scene.theme, "转为下一步",
                        {=> scene.run(gl.promoteItemToNext(item, scene.placeholder("act"), scene.now()))},
                        variant: ButtonVariant.Secondary, size: ControlSize.Sm, iconLeft: IconGlyph.Play)
                    Ui.iconButton(scene.theme, IconGlyph.Trash, {=> scene.run(gl.deleteInboxItem(item))},
                        variant: IconButtonVariant.Danger, size: ControlSize.Sm, tooltip: "删除「${item.title}」")
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
    }
        .hug()
        .fillWidth()
}
