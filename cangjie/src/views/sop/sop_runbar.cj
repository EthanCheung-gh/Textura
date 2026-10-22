package textura.views.sop

import std.collection.*
import std.deriving.*
import cui.*
import textura.core.data.*
import textura.ui.*
import textura.views.sop.logic as lg

/*
 * Run bar + 通过/未通过/跳过 — `SopRunBar.tsx` + `.sop-runbar*` (sop.css:558-671).
 *
 * The bar appears while a run session exists: current step, checklist chips that can be
 * ticked, and the four result buttons. Recording a result goes through
 * `logic.recordResult` (the Web state machine) and persists a `SopRunEntry` via
 * `store.logRun`, so the run history in the right column updates for real.
 */

/** Branch option row geometry inside the branch modal. */
let SOP_BRANCH_WIDTH: Float32 = 440.0
let SOP_BRANCH_ROW_H: Float32 = 42.0

/** Laid-out run bar geometry (shared by paint and hit-testing). */
class SopRunBarRects {
    let bar: Rect
    let pass: Rect
    let fail: Rect
    let skip: Rect
    let exit: Rect
    let chips: Array<(String, Rect)>

    init(bar: Rect, pass: Rect, fail: Rect, skip: Rect, exit: Rect, chips: Array<(String, Rect)>) {
        this.bar = bar
        this.pass = pass
        this.fail = fail
        this.skip = skip
        this.exit = exit
        this.chips = chips
    }
}

/** Right-aligned action row of the run bar (`12px 16px` padding, `--space-2` gap). */
func runBarRects(ctx: UiContext, view: SopFrame): SopRunBarRects {
    let bar = view.runBarRect(ctx)
    let right = bar.right() - 1.0 - SOP_RUNBAR_PAD_X
    let labels = [("pass", "通过", IconGlyph.Check), ("fail", "未通过", IconGlyph.Cross),
        ("skip", "跳过", IconGlyph.ChevronRight), ("exit", "退出", IconGlyph.Play)]
    var widths = ArrayList<Float32>()
    for ((_, label, glyph) in labels) {
        widths.add(SOP_BTN_SM_PAD * 2.0 + 2.0 + contentWidth(ctx, label, Some(glyph), 14.0, SOP_BTN_SM_FONT))
    }
    var cursor = right
    var buttons = Array<Rect>(4) {index => Rect.zero()}
    var index = 3
    while (index >= 0) {
        let width = widths[index]
        cursor -= width
        buttons[index] = Rect(cursor, bar.y + SOP_RUNBAR_PAD_Y, width, SOP_BTN_SM_H)
        cursor -= SOP_TOOLBAR_GAP
        index -= 1
    }
    // Checklist chips of the current step (`.sop-runbar-checklist`).
    let chips = ArrayList<(String, Rect)>()
    match (view.currentStep()) {
        case Some(step) => match (step.sop) {
            case Some(data) =>
                var chipX = bar.x + 1.0 + SOP_RUNBAR_BAR + SOP_RUNBAR_PAD_X
                let chipY = bar.y + SOP_RUNBAR_PAD_Y + SOP_BADGE_H + SOP_BLOCK_GAP
                for (entry in data.checklist) {
                    let width = 14.0 + 8.0 + measureText(ctx, entry.text, SOP_RUNBAR_META_SIZE, 400) + 16.0 + 2.0
                    chips.add((entry.id, Rect(chipX, chipY, width, SOP_CHIP_H)))
                    chipX += width + 8.0
                }
            case None => ()
        }
        case None => ()
    }
    return SopRunBarRects(bar, buttons[0], buttons[1], buttons[2], buttons[3], chips.toArray())
}

func paintRunBar(ctx: UiContext, view: SopFrame): Unit {
    let tk = view.tk
    let rects = runBarRects(ctx, view)
    let bar = rects.bar
    paintShadow1(ctx, tk, bar, SOP_RADIUS_PANEL)
    fillRound(ctx, bar, SOP_RADIUS_PANEL, tk.color.surface)
    strokeRound(ctx, bar, SOP_RADIUS_PANEL, SOP_BORDER, tk.color.border)
    // `border-left: 3px solid var(--accent)` on top of the 1px border.
    ctx.renderer.pushClip(bar)
    fillRound(ctx, Rect(bar.x, bar.y, SOP_RUNBAR_BAR + SOP_RADIUS_PANEL, bar.h), SOP_RADIUS_PANEL, tk.color.accent)
    ctx.renderer.popClip()

    let left = bar.x + 1.0 + SOP_RUNBAR_BAR + SOP_RUNBAR_PAD_X
    let top = bar.y + SOP_RUNBAR_PAD_Y
    let total = view.nodes.size
    let index = match (view.state.session) {
        case Some(session) => min(session.visited.size, max(total, 1))
        case None => 0
    }
    // Row 1: 运行中 badge, 第 n/total 步, divider, title, type badge, owner, duration.
    let rowCenter = top + SOP_BADGE_H / 2.0
    var cursor = left
    let badgeW = badgeWidth(ctx, "运行中", SOP_BADGE_FONT, SOP_BADGE_PAD_X, 550) + 10.0
    let _ = paintBadge(ctx, tk, "运行中", cursor, rowCenter, SopTone.Accent, dot: true)
    cursor += badgeW + 8.0
    let progressText = "第 ${index}/${total} 步"
    paintText(ctx, progressText, cursor, rowCenter, 12.0, 400, tk.color.textMuted)
    cursor += measureText(ctx, progressText, 12.0, 400) + 8.0
    paintVLine(ctx, rowCenter - 8.0, rowCenter + 8.0, cursor, tk.color.border)
    cursor += 9.0
    let step = view.currentStep()
    let title = match (step) {
        case Some(item) => item.title
        case None => "流程结束"
    }
    let titleWidth = measureText(ctx, title, SOP_RUNBAR_TITLE_SIZE, 650)
    paintTextClipped(ctx, title, cursor, rowCenter, min(titleWidth, rects.pass.x - 16.0 - cursor), SOP_RUNBAR_TITLE_SIZE,
        650, tk.color.text)
    cursor += min(titleWidth, rects.pass.x - 16.0 - cursor) + 8.0
    match (step) {
        case Some(item) =>
            let typeLabel = nodeTypeLabel(nodeTypeOf(item))
            let typeW = badgeWidth(ctx, typeLabel, SOP_BADGE_FONT, SOP_BADGE_PAD_X, 550)
            let _ = paintBadge(ctx, tk, typeLabel, cursor, rowCenter, SopTone.Neutral)
            cursor += typeW + 8.0
            match (item.sop) {
                case Some(data) =>
                    match (data.owner) {
                        case Some(owner) =>
                            if (!owner.isEmpty()) {
                                paintText(ctx, owner, cursor, rowCenter, SOP_RUNBAR_META_SIZE, 400,
                                    tk.color.textFaint)
                                cursor += measureText(ctx, owner, SOP_RUNBAR_META_SIZE, 400) + 8.0
                            }
                        case None => ()
                    }
                    match (data.durationMin) {
                        case Some(minutes) =>
                            if (minutes > 0) {
                                paintText(ctx, "${minutes} 分钟", cursor, rowCenter, SOP_RUNBAR_META_SIZE, 400,
                                    tk.color.textFaint)
                            }
                        case None => ()
                    }
                case None => ()
            }
        case None => ()
    }

    // Row 2: checklist chips (tick = real store write), or the hint text.
    if (!rects.chips.isEmpty()) {
        for ((chipId, chip) in rects.chips) {
            paintChip(ctx, view, chip, chipId)
        }
        let stepChecklist = match (step) {
            case Some(item) => checklistOf(item)
            case None => Array<ChecklistEntry>()
        }
        let done = countDone(stepChecklist)
        let lastEntry = rects.chips[rects.chips.size - 1]
        let lastChip = lastEntry[1]
        paintText(ctx, "${done}/${stepChecklist.size}", lastChip.right() + 8.0, lastChip.centerY(), 11.0, 400,
            tk.color.textFaint)
    } else {
        let chipLine = top + SOP_BADGE_H + SOP_BLOCK_GAP + SOP_HINT_LINE / 2.0
        paintText(ctx, "这一步没有检查项，直接记录结果即可。", left, chipLine, SOP_HINT_SIZE, 400, tk.color.textFaint)
    }

    // Actions.
    let enabled = step.isSome()
    paintPrimaryButton(ctx, tk, "通过", rects.pass, glyph: IconGlyph.Check, glyphSide: 14.0, enabled: enabled)
    paintDangerButton(ctx, tk, "未通过", rects.fail, glyph: IconGlyph.Cross, glyphSide: 14.0, enabled: enabled)
    paintSecondaryButton(ctx, tk, "跳过", rects.skip, glyph: IconGlyph.ChevronRight, glyphSide: 14.0,
        enabled: enabled)
    paintGhostButton(ctx, tk, "退出", rects.exit)
}

/** `.sop-runbar-check` pill: checkbox + label, `data-done` swaps the border to `--ok`. */
func paintChip(ctx: UiContext, view: SopFrame, rect: Rect, entryId: String): Unit {
    let tk = view.tk
    var done = false
    var text = ""
    match (view.currentStep()) {
        case Some(item) =>
            for (entry in checklistOf(item)) {
                if (entry.id == entryId) {
                    done = entry.done
                    text = entry.text
                }
            }
        case None => ()
    }
    paintBox(ctx, rect, rect.h / 2.0, tk.color.surface2, if (done) {
        tk.color.ok
    } else {
        tk.color.border
    })
    let boxSize: Float32 = 14.0
    let checkbox = Rect(rect.x + 8.0, rect.centerY() - boxSize / 2.0, boxSize, boxSize)
    paintCheckbox(ctx, tk, checkbox, done)
    let color = if (done) {
        tk.color.textMuted
    } else {
        tk.color.text
    }
    paintText(ctx, text, checkbox.right() + 8.0, rect.centerY(), SOP_RUNBAR_META_SIZE, 400, color)
    if (done) {
        // `text-decoration: line-through`
        let width = measureText(ctx, text, SOP_RUNBAR_META_SIZE, 400)
        ctx.renderer.fill(Rect(checkbox.right() + 8.0, rect.centerY(), width, 1.0), color)
    }
}

/** Branch chooser (`SopRunBar.tsx:132-164`): centered modal listing the outgoing branches. */
func branchPanelRect(view: SopFrame): Rect {
    let width = SOP_BRANCH_WIDTH
    let rows = Float32(max(view.state.branchOptions.size, 1))
    let height = 76.0 + rows * (SOP_BRANCH_ROW_H + 8.0) + 56.0
    let page = view.pageRect()
    return Rect(page.x + (page.w - width) / 2.0, page.y + 96.0, width, height)
}

func paintBranchPanel(ctx: UiContext, view: SopFrame): Unit {
    let tk = view.tk
    let page = view.pageRect()
    ctx.renderer.fill(page, Color.rgba(26, 22, 18, 107))
    let panel = branchPanelRect(view)
    paintShadow1(ctx, tk, panel, SOP_RADIUS_PANEL)
    fillRound(ctx, panel, SOP_RADIUS_PANEL, tk.color.surface)
    strokeRound(ctx, panel, SOP_RADIUS_PANEL, SOP_BORDER, tk.color.border)
    paintText(ctx, "选择下一步", panel.x + 24.0, panel.y + 24.0, 15.0, 650, tk.color.text)
    let current = view.currentStep()
    let description = match (current) {
        case Some(item) => "「${item.title}」有多条出边，选择要走的分支。"
        case None => "选择要走的分支。"
    }
    paintTextClipped(ctx, description, panel.x + 24.0, panel.y + 46.0, panel.w - 48.0, 12.5, 400,
        tk.color.textMuted)
    var y = panel.y + 68.0
    for ((option, rect) in branchOptionRects(view, panel)) {
        paintSecondaryButton(ctx, tk, "", rect)
        let target = match (view.nodeById(option.to)) {
            case Some(item) => item.title
            case None => "未知步骤"
        }
        let label = if (option.label.isEmpty()) {
            "继续"
        } else {
            option.label
        }
        paintText(ctx, label, rect.x + 14.0, rect.centerY(), SOP_BTN_SM_FONT, 650, tk.color.text)
        paintTextClipped(ctx, "→ ${target}", rect.x + 14.0 + measureText(ctx, label, SOP_BTN_SM_FONT, 650) + 12.0,
            rect.centerY(), rect.w - 40.0, 12.0, 400, tk.color.textMuted)
        y += rect.h + 8.0
    }
    let _ = y
    paintGhostButton(ctx, tk, "取消", Rect(panel.right() - 24.0 - 60.0, panel.bottom() - 48.0, 60.0, SOP_BTN_SM_H))
}

func branchOptionRects(view: SopFrame, panel: Rect): Array<(lg.BranchOption, Rect)> {
    let result = ArrayList<(lg.BranchOption, Rect)>()
    var y = panel.y + 68.0
    for (option in view.state.branchOptions) {
        result.add((option, Rect(panel.x + 24.0, y, panel.w - 48.0, SOP_BRANCH_ROW_H)))
        y += SOP_BRANCH_ROW_H + 8.0
    }
    result.toArray()
}

/** Run bar interactions: checklist chips + the four result buttons. */
func handleRunBar(ctx: UiContext, view: SopFrame, event: UiEvent): Bool {
    if (!view.running()) {
        return false
    }
    match (event) {
        case UiEvent.MouseDown(MouseButton.Left, x, y) =>
            let rects = runBarRects(ctx, view)
            if (!rects.bar.contains(x, y)) {
                return false
            }
            for ((entryId, chip) in rects.chips) {
                if (chip.contains(x, y)) {
                    toggleRunChecklist(view, entryId)
                    return true
                }
            }
            if (rects.pass.contains(x, y)) {
                recordRun(view, lg.RunResult.Pass)
                return true
            }
            if (rects.fail.contains(x, y)) {
                recordRun(view, lg.RunResult.Fail)
                return true
            }
            if (rects.skip.contains(x, y)) {
                recordRun(view, lg.RunResult.Skip)
                return true
            }
            if (rects.exit.contains(x, y)) {
                exitRun(view)
                return true
            }
            return true
        case _ => return false
    }
}

/** Checklist chip toggle (`SopRunBar.toggleChecklist`). */
func toggleRunChecklist(view: SopFrame, entryId: String): Unit {
    let step = match (view.currentStep()) {
        case Some(item) => item
        case None => return
    }
    let next = ArrayList<ChecklistEntry>()
    for (entry in checklistOf(step)) {
        if (entry.id == entryId) {
            next.add(ChecklistEntry(entry.id, entry.text, !entry.done))
        } else {
            next.add(entry)
        }
    }
    commitChecklist(view, step.id, next.toArray())
}

/**
 * `runResult` (SopPage.tsx:132-159): log the entry, advance the state machine, then move
 * to the next step, open the branch chooser, or finish the run.
 */
func recordRun(view: SopFrame, result: lg.RunResult): Unit {
    let session = match (view.state.session) {
        case Some(value) => value
        case None => return
    }
    let sop = match (view.sop) {
        case Some(value) => value
        case None => return
    }
    let stepId = session.currentId
    let now = nowIso(view.store.clock)
    view.store.logRun(sop.id, stepId, coreResult(result))
    view.state.runSeq += 1
    let outcome = lg.recordResult(session, toSopEdges(view.edges), result, sop.id, now,
        entryIdSequence: view.state.runSeq)
    match (outcome) {
        case lg.RunOutcome.Advanced(updated, _, nextStepId, _) =>
            view.state.session = Some(updated)
            view.state.selectedNodeId = Some(nextStepId)
            view.state.selectedEdgeId = None
            view.store.select(nextStepId)
            view.state.branchOpen = false
            view.state.touch()
        case lg.RunOutcome.Branching(updated, _, options) =>
            view.state.session = Some(updated)
            view.state.branchOptions = options
            view.state.branchResult = result
            view.state.branchOpen = true
            view.state.touch()
        case lg.RunOutcome.Finished(updated, _, stats, elapsedMin) =>
            view.store.notify(lg.runEndMessage(stats, elapsedMin), tone: NoticeTone.Success)
            view.state.session = None
            view.state.branchOpen = false
            view.state.branchOptions = Array<lg.BranchOption>()
            view.state.touch()
    }
}

func coreResult(result: lg.RunResult): RunResult {
    match (result) {
        case lg.RunResult.Pass => return RunResult.Pass
        case lg.RunResult.Fail => return RunResult.Fail
        case lg.RunResult.Skip => return RunResult.Skip
    }
}

func exitRun(view: SopFrame): Unit {
    view.state.session = None
    view.state.branchOpen = false
    view.state.branchOptions = Array<lg.BranchOption>()
    view.store.notify("已退出运行模式", tone: NoticeTone.Info)
    view.state.touch()
}

/** Branch panel input: option rows and cancel. */
func handleBranchPanel(ctx: UiContext, view: SopFrame, event: UiEvent): Bool {
    let _ = ctx
    match (event) {
        case UiEvent.MouseDown(MouseButton.Left, x, y) =>
            let panel = branchPanelRect(view)
            for ((option, rect) in branchOptionRects(view, panel)) {
                if (rect.contains(x, y)) {
                    chooseBranch(view, option)
                    return true
                }
            }
            if (Rect(panel.right() - 24.0 - 60.0, panel.bottom() - 48.0, 60.0, SOP_BTN_SM_H).contains(x, y)) {
                view.state.branchOpen = false
                view.state.branchOptions = Array<lg.BranchOption>()
                view.state.touch()
                return true
            }
            return panel.contains(x, y)
        case _ => return false
    }
}

/** `chooseBranch` (SopPage.tsx:161-178): advance along the picked edge. */
func chooseBranch(view: SopFrame, option: lg.BranchOption): Unit {
    let session = match (view.state.session) {
        case Some(value) => value
        case None => return
    }
    let outcome = lg.advance(session.currentId, toSopEdges(view.edges), choice: Some(option.edgeId),
        visited: session.visited)
    match (outcome) {
        case lg.AdvanceResult.Next(nextStepId, _) =>
            view.state.session = Some(lg.moveTo(session, nextStepId))
            view.state.selectedNodeId = Some(nextStepId)
            view.store.select(nextStepId)
        case _ => ()
    }
    view.state.branchOpen = false
    view.state.branchOptions = Array<lg.BranchOption>()
    view.state.touch()
}
