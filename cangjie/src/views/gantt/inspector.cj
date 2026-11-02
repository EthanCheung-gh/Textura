package textura.views.gantt

import std.collection.*
import std.convert.*
import cui.*
import textura.core.data as data
import textura.ui.*
import textura.views.gantt.logic.*

/*
 * 右侧检查器（GanttInspector.tsx / gantt.css:806-1014）。
 *
 * 这一层用 `textura.ui` 的真实输入控件（`Ui.textInput` / `Ui.progress`），因为需要光标、
 * 选区、IME 与键盘焦点；几何按 CSS 逐项钉住：面板 320 宽、头部 52 高、
 * 内容区 `padding: 16px 16px 24px`、区块间距 16、`gap: 6px`。
 *
 * 写回策略：标题与日期用草稿 `State` + `Enter` 提交（也提供「保存」按钮），
 * 避免逐键写库产生大量撤销快照；进度用 ±5% 步进直接写库（与 `setProgress` 一致）。
 */

/** 面板块的竖直内边距/间距（gantt.css:840-848 / 856-860）。 */
let INSPECTOR_HEAD_HEIGHT: Float32 = 52.0
let INSPECTOR_PADDING: Float32 = 16.0
let INSPECTOR_SECTION_GAP: Float32 = 16.0

func buildInspector(
    ctx: data.ViewContext,
    theme: Theme,
    tokens: ThemeTokens,
    workspace: data.Workspace,
    selectedId: String,
    onSelect: (String) -> Unit,
    onClose: () -> Unit
): Unit {
    let _ = onSelect
    VStack(spacing: vp(0.0)) {
        inspectorHead(theme, tokens, workspace, selectedId, onClose)
        match (selectedItem(workspace, selectedId)) {
            case Some(item) => Keyed("gantt-inspector:${item.id}") {
                inspectorBody(ctx, theme, tokens, workspace, item)
            }
            case None =>
                VStack(spacing: vp(tokens.space.s2)) {
                    Ui.emptyState(theme, "未选中条目", description: "点击左侧任务或时间轴上的任务条，查看并编辑细节。",
                        glyph: IconGlyph.Timeline, compact: true)
                }.hug().padding(INSPECTOR_PADDING)
        }
    }
        .crossAxisAlignment(CrossAxisAlignment.Start)
        // `.gantt-inspector { background: surface; border-left: 1px }`——左边框由画布绘制
        .background(tokens.color.surface)
}

func inspectorHead(theme: Theme, tokens: ThemeTokens, workspace: data.Workspace, selectedId: String,
    onClose: () -> Unit): Unit {
    HStack(spacing: vp(tokens.space.s2)) {
        Label("详情").fontSize(fp(13.5)).fontWeight(FontWeight(650)).foregroundColor(tokens.color.text)
        match (selectedItem(workspace, selectedId)) {
            case Some(item) => Ui.badge(theme, data.itemKindLabel(item.kind))
            case None => ()
        }
        Spacer()
        Ui.iconButton(theme, IconGlyph.Close, onClose, size: ControlSize.Sm, tooltip: "收起详情")
    }
        .crossAxisAlignment(CrossAxisAlignment.Center)
        .hug()
        .fillWidth()
        .padding(vp(tokens.space.s4), vp(0.0), vp(tokens.space.s2), vp(0.0))
        .height(INSPECTOR_HEAD_HEIGHT - 1.0)
    // `.gantt-inspector-head { border-bottom: 1px }`
    Box(tokens.color.border).height(tokens.metrics.borderWidth).fillWidth()
}

func inspectorBody(ctx: data.ViewContext, theme: Theme, tokens: ThemeTokens, workspace: data.Workspace,
    item: data.Item): Unit {
    let titleDraft = rememberState<String>("title") {item.title}
    let startDraft = rememberState<String>("start") {ganttStart(item)}
    let endDraft = rememberState<String>("end") {ganttEnd(item)}
    // 进度也可以直接填数字：% 步进按钮留在下面，输入框给「精确到某一步」的场景（Enter 写回）。
    let progressDraft = rememberState<String>("progress") {"${displayProgress(toGanttRow(workspace, item, 0))}"}
    let range = itemRange(toGanttRow(workspace, item, 0))

    ScrollView(key: "gantt-inspector-scroll") {
        VStack(spacing: vp(INSPECTOR_SECTION_GAP)) {
            // 标题（`.field` + `.input`）
            Ui.field(theme, label: "标题", hint: "Enter 或「保存标题」写回。") {
                EventHandler(onEvent: {event =>
                    match (event) {
                        case UiEvent.KeyDown(Key.Enter, _) =>
                            commitTitle(ctx, item, titleDraft.value)
                            true
                        case _ => false
                    }
                }) {
                    Ui.textInput(theme, titleDraft, key: "gantt-title")
                }
                HStack(spacing: vp(tokens.space.s2)) {
                    Ui.button(theme, "保存标题", {=> commitTitle(ctx, item, titleDraft.value)}, variant:
                        ButtonVariant.Secondary, size: ControlSize.Sm)
                    Ui.button(theme, if (item.status == data.ItemStatus.Done) {
                        "标记未完成"
                    } else {
                        "标记完成"
                    }, {=> ctx.store.toggleDone(item.id)}, variant: ButtonVariant.Ghost, size: ControlSize.Sm)
                }.hug()
            }

            // 日期区块（`.gantt-section`）
            VStack(spacing: vp(6.0)) {
                HStack(spacing: vp(tokens.space.s2)) {
                    Label("日期").fontSize(fp(11.0)).fontWeight(FontWeight(600)).foregroundColor(
                        tokens.color.textFaint)
                    Spacer()
                    Ui.button(theme, "清除日期", {=> ctx.store.updateItem(item.id,
                        data.ItemPatch().withGanttRange(noKey(), noKey()))}, variant: ButtonVariant.Ghost,
                        size: ControlSize.Sm, enabled: !ganttStart(item).isEmpty() || !ganttEnd(item).isEmpty())
                }.hug().fillWidth()

                dateRow(theme, tokens, "开始", startDraft, "gantt-start") {value =>
                    ctx.store.updateItem(item.id, data.ItemPatch().withGanttRange(cleared(value), ganttEndOrNone(item)))
                }
                dateRow(theme, tokens, "结束", endDraft, "gantt-end") {value =>
                    ctx.store.updateItem(item.id, data.ItemPatch().withGanttRange(ganttStartOrNone(item), cleared(value)))
                }
                // 工期（含首尾天数）：`diffDays + 1`
                Label(durationText(range)).fontSize(fp(11.0)).foregroundColor(tokens.color.textFaint)
            }.hug().fillWidth()

            // 进度区块
            VStack(spacing: vp(6.0)) {
                HStack(spacing: vp(tokens.space.s2)) {
                    Label("进度").fontSize(fp(11.0)).fontWeight(FontWeight(600)).foregroundColor(
                        tokens.color.textFaint)
                    Spacer()
                    Label("${displayProgress(toGanttRow(workspace, item, 0))}%").fontSize(fp(11.5))
                        .foregroundColor(tokens.color.textMuted)
                }.hug().fillWidth()
                Ui.progress(theme, Float32(progressOf(item)), tone: ProgressTone.Accent, showLabel: false)
                // 数值输入（原位，不再弹窗）：Enter 写回，非法输入回退到当前值。
                HStack(spacing: vp(tokens.space.s2)) {
                    Label("数值").fontSize(fp(12.0)).foregroundColor(tokens.color.textMuted).width(30.0)
                    EventHandler(onEvent: {event =>
                        match (event) {
                            case UiEvent.KeyDown(Key.Enter, _) =>
                                commitProgress(ctx, item, progressDraft)
                                true
                            case _ => false
                        }
                    }) {
                        Ui.textInput(theme, progressDraft, key: "gantt-progress", placeholder: "0-100")
                    }
                    Label("%").fontSize(fp(12.0)).foregroundColor(tokens.color.textMuted)
                }.crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
                HStack(spacing: vp(tokens.space.s2)) {
                    Ui.button(theme, "−5%", {=> stepProgress(ctx, item, -5.0)}, variant: ButtonVariant.Secondary,
                        size: ControlSize.Sm, enabled: item.status != data.ItemStatus.Done)
                    Ui.button(theme, "+5%", {=> stepProgress(ctx, item, 5.0)}, variant: ButtonVariant.Secondary,
                        size: ControlSize.Sm, enabled: item.status != data.ItemStatus.Done)
                    Ui.badge(theme, data.itemStatusLabel(item.status), tone: statusTone(item.status))
                }.hug()
            }.hug().fillWidth()

            // 子任务计数（`.gantt-section` 的「子任务」区块）
            let children = data.childrenOf(workspace, item.id)
            VStack(spacing: vp(6.0)) {
                HStack(spacing: vp(tokens.space.s2)) {
                    Label("子任务").fontSize(fp(11.0)).fontWeight(FontWeight(600)).foregroundColor(
                        tokens.color.textFaint)
                    Spacer()
                    Label("${children.size}").fontSize(fp(11.0)).foregroundColor(tokens.color.textFaint)
                }.hug().fillWidth()
                if (children.size == 0) {
                    Label("暂无子任务。").fontSize(fp(12.0)).foregroundColor(tokens.color.textFaint)
                }
            }.hug().fillWidth()
        }
            .hug()
            .fillWidth()
            .padding(vp(INSPECTOR_PADDING), vp(INSPECTOR_PADDING), vp(INSPECTOR_PADDING), vp(tokens.space.s5))
    }
}

/** `开始/结束` 一行：标签 30px、输入框、清除按钮（gantt.css:885-902）。 */
func dateRow(theme: Theme, tokens: ThemeTokens, label: String, draft: State<String>, key: String,
    commit: (String) -> Unit): Unit {
    HStack(spacing: vp(tokens.space.s1)) {
        Label(label).fontSize(fp(12.0)).foregroundColor(tokens.color.textMuted).width(30.0)
        EventHandler(onEvent: {event =>
            match (event) {
                case UiEvent.KeyDown(Key.Enter, _) =>
                    commit(draft.value)
                    true
                case _ => false
            }
        }) {
            Ui.textInput(theme, draft, key: key, placeholder: "YYYY-MM-DD")
        }
        Ui.iconButton(theme, IconGlyph.Close, {=> commit("")}, size: ControlSize.Sm, tooltip: "清除")
    }.crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
}

func commitTitle(ctx: data.ViewContext, item: data.Item, value: String): Unit {
    let next = value.trimAscii()
    if (!next.isEmpty() && next != item.title) {
        ctx.store.updateItem(item.id, data.ItemPatch().withTitle(next))
    }
}

/**
 * 进度数值输入：只接受 0–100，取整到 1%；`35%` / ` 35 ` 也可以。
 * 非法输入把草稿还原成当前值（不写库、不报错），与标题/日期草稿的提交方式一致。
 */
func commitProgress(ctx: data.ViewContext, item: data.Item, draft: State<String>): Unit {
    var digits = ""
    for (byte in draft.value) {
        if (byte >= UInt8(48) && byte <= UInt8(57)) {
            digits += String.fromUtf8([byte])
        } else if (byte == UInt8(37) || byte == UInt8(32)) {
            continue
        } else {
            digits = ""
            break
        }
    }
    var parsed: ?Float64 = None
    if (!digits.isEmpty()) {
        try {
            parsed = Some(Float64.parse(digits))
        } catch (_: Exception) {
            parsed = None
        }
    }
    let next = match (parsed) {
        case Some(value) => max(0.0, min(100.0, value))
        case None => progressOf(item)
    }
    draft.value = "${Int64(next)}"
    if (next != progressOf(item)) {
        ctx.store.setProgress(item.id, next)
    }
}

func stepProgress(ctx: data.ViewContext, item: data.Item, delta: Float64): Unit {
    let current = progressOf(item)
    let next = max(0.0, min(100.0, current + delta))
    ctx.store.setProgress(item.id, next)
}

func selectedItem(workspace: data.Workspace, selectedId: String): ?data.Item {
    if (selectedId.isEmpty()) {
        return noItem()
    }
    data.itemById(workspace, selectedId)
}

func progressOf(item: data.Item): Float64 {
    match (item.gantt) {
        case Some(gantt) => gantt.progress
        case None => 0.0
    }
}

func ganttStart(item: data.Item): String {
    match (item.gantt) {
        case Some(gantt) => data.dateKey(gantt.start).getOrDefault({=> ""})
        case None => ""
    }
}

func ganttEnd(item: data.Item): String {
    match (item.gantt) {
        case Some(gantt) => data.dateKey(gantt.end).getOrDefault({=> ""})
        case None => ""
    }
}

func ganttStartOrNone(item: data.Item): ?String {
    cleared(ganttStart(item))
}

func ganttEndOrNone(item: data.Item): ?String {
    cleared(ganttEnd(item))
}

func cleared(value: String): ?String {
    if (value.isEmpty()) {
        None
    } else {
        Some(value)
    }
}

/** 工期文案：`2026/03/06 → 2026/03/29 · 24 天`。 */
func durationText(range: ?BarRange): String {
    match (range) {
        case Some(bar) =>
            let days = diffDays(bar.start, bar.end) + 1
            let start = data.formatDateKey(bar.start, pattern: "yyyy/MM/dd")
            let end = data.formatDateKey(bar.end, pattern: "yyyy/MM/dd")
            "${start} → ${end} · ${days} 天"
        case None => "未排期：设置开始日期后即可在时间轴上看到任务条。"
    }
}

func statusTone(status: data.ItemStatus): BadgeTone {
    match (status) {
        case data.ItemStatus.Done => BadgeTone.Ok
        case data.ItemStatus.Active => BadgeTone.Accent
        case data.ItemStatus.Waiting => BadgeTone.Warn
        case data.ItemStatus.Scheduled => BadgeTone.Info
        case _ => BadgeTone.Neutral
    }
}
