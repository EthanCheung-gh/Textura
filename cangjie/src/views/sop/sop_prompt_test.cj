package textura.views.sop

import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*
import textura.ui.*

/*
 * The SOP inspector edits through `Ui.prompt`: the inspector is painted on a canvas, so an
 * inline `TextField` there would be declared during layout and never enter the focus graph
 * (docs/DEVICE-NOTES.md §16). These tests pin the path end to end — open → focus → type →
 * Enter writes the store — for the fields the device report could not type into.
 */

private let SOP_PROMPT_RECT: Rect = Rect(0.0, 0.0, 1440.0, 900.0)
/*
 * The rectangle the inspector recorded for the field under test (`rects.titleInput` and friends in
 * production). Everything below edits at this position: the inline editor is placed here, exactly
 * like a real field, which is the point of the change.
 */
private let SOP_FIELD_RECT: Rect = Rect(320.0, 200.0, 260.0, 34.0)

private func sopPromptStore(): AppStore {
    let clock = FixedClock(1773626400000)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    store
}

/** First step node of the seeded workspace (the inspector's node variant edits it). */
private func firstStep(workspace: Workspace): ?Item {
    for (item in workspace.items) {
        if (item.kind == ItemKind.Step) {
            return Some(item)
        }
    }
    None
}

@Test
func sopPromptFocusesItsEditorAndSavesTheTitle(): Unit {
    let store = sopPromptStore()
    let step = match (firstStep(store.state.value())) {
        case Some(item) => item
        case None =>
            @Expect("seeded step", "missing")
            return
    }
    let state = SopViewState(State<Int64>(0))
    openSopPrompt(state, SopPromptKind.NodeTitle, step.id, step.title, SOP_FIELD_RECT)
    let testHost = WidgetTestHost()
    let body = {=> sopPromptDialog(texturaLight(), store, state)}
    let _ = testHost.frame(SOP_PROMPT_RECT, body: body)
    // Opening the prompt puts the caret in its editor — the whole point of the shared overlay.
    @Expect(testHost.context.focusId, SOP_PROMPT_INPUT)
    let _ = testHost.frame(SOP_PROMPT_RECT, events: [UiEvent.TextInput("（改）")], body: body)
    let _ = testHost.frame(SOP_PROMPT_RECT, events: [UiEvent.KeyDown(Key.Enter, false)], body: body)
    @Expect(state.promptOpen.value, false)
    let updated = match (itemById(store.state.value(), step.id)) {
        case Some(item) => item.title
        case None => ""
    }
    @Expect(updated, step.title + "（改）")
}

@Test
func sopPromptRejectsAnEmptyTitleAndStaysOpen(): Unit {
    let store = sopPromptStore()
    let step = match (firstStep(store.state.value())) {
        case Some(item) => item
        case None =>
            @Expect("seeded step", "missing")
            return
    }
    let state = SopViewState(State<Int64>(0))
    openSopPrompt(state, SopPromptKind.NodeTitle, step.id, "", SOP_FIELD_RECT)
    let testHost = WidgetTestHost()
    let body = {=> sopPromptDialog(texturaLight(), store, state)}
    let _ = testHost.frame(SOP_PROMPT_RECT, body: body)
    let _ = testHost.frame(SOP_PROMPT_RECT, events: [UiEvent.KeyDown(Key.Enter, false)], body: body)
    // Validation keeps the dialog open and leaves the workspace untouched.
    @Expect(state.promptOpen.value, true)
    @Expect(state.promptError.value.isEmpty(), false)
    let current = match (itemById(store.state.value(), step.id)) {
        case Some(item) => item.title
        case None => ""
    }
    @Expect(current, step.title)
}

@Test
func sopDurationPromptWritesWholeMinutes(): Unit {
    let store = sopPromptStore()
    let step = match (firstStep(store.state.value())) {
        case Some(item) => item
        case None =>
            @Expect("seeded step", "missing")
            return
    }
    let state = SopViewState(State<Int64>(0))
    openSopPrompt(state, SopPromptKind.NodeDuration, step.id, "", SOP_FIELD_RECT)
    let testHost = WidgetTestHost()
    let body = {=> sopPromptDialog(texturaLight(), store, state)}
    let _ = testHost.frame(SOP_PROMPT_RECT, body: body)
    let _ = testHost.frame(SOP_PROMPT_RECT, events: [UiEvent.TextInput("25 分钟")], body: body)
    let _ = testHost.frame(SOP_PROMPT_RECT, events: [UiEvent.KeyDown(Key.Enter, false)], body: body)
    let minutes = match (itemById(store.state.value(), step.id)) {
        case Some(item) => match (item.sop) {
            case Some(data) => data.durationMin.getOrDefault({=> Int64(-1)})
            case None => Int64(-1)
        }
        case None => Int64(-1)
    }
    @Expect(minutes, 25)
}

/* ------------------------------------------------------------------ 描述（多行） */

/** Ctrl+Enter: the multiline editor keeps plain Enter for a newline, so saving uses the chord. */
private let CTRL_ENTER: UiEventRecord = UiEventRecord(UiEvent.KeyDown(Key.Enter, false),
    UiEventMetadata(modifiers: EventKeyModifiers(raw: UInt16(0x0040))))

private func currentNotes(store: AppStore, id: String): String {
    match (itemById(store.state.value(), id)) {
        case Some(item) => item.notes
        case None => ""
    }
}

/**
 * 步骤「描述」: clicking the painted textarea opens the multiline prompt, Enter inserts a line
 * break, Ctrl+Enter writes `Item.notes` back and closes, and the new text is immediately visible
 * to the canvas/list (it reads the same store).
 */
@Test
func stepDescriptionEditsMultilineNotes(): Unit {
    let store = sopPromptStore()
    let step = match (firstStep(store.state.value())) {
        case Some(item) => item
        case None =>
            @Expect("seeded step", "missing")
            return
    }
    let state = SopViewState(State<Int64>(0))
    openSopPrompt(state, SopPromptKind.NodeNotes, step.id, step.notes, SOP_FIELD_RECT)
    let testHost = WidgetTestHost()
    let body = {=> sopPromptDialog(texturaLight(), store, state)}
    let _ = testHost.frame(SOP_PROMPT_RECT, body: body)
    @Expect(testHost.context.focusId, SOP_PROMPT_INPUT)
    let _ = testHost.frame(SOP_PROMPT_RECT, events: [UiEvent.TextInput("补充一行")], body: body)
    // Plain Enter is a newline in a description, not a save.
    let _ = testHost.frame(SOP_PROMPT_RECT, events: [UiEvent.KeyDown(Key.Enter, false)], body: body)
    @Expect(state.promptOpen.value, true)
    let _ = testHost.frame(SOP_PROMPT_RECT, events: [UiEvent.TextInput("第二行")], body: body)
    let _ = testHost.frameRecords(SOP_PROMPT_RECT, events: [CTRL_ENTER], body: body)
    @Expect(state.promptOpen.value, false)
    @Expect(currentNotes(store, step.id), step.notes + "补充一行\n第二行")
}

/** SOP 级「描述」也走同一个浮层；空白允许保存。 */
@Test
func sopDescriptionAcceptsAnEmptyValue(): Unit {
    let store = sopPromptStore()
    var sop: ?Item = None
    for (summary in sopList(store.state.value())) {
        if (sop.isNone()) {
            sop = Some(summary.sop)
        }
    }
    let target = match (sop) {
        case Some(item) => item
        case None =>
            @Expect("seeded sop", "missing")
            return
    }
    store.updateItem(target.id, ItemPatch().withNotes("原有描述"))
    let state = SopViewState(State<Int64>(0))
    openSopPrompt(state, SopPromptKind.SopNotes, target.id, "原有描述", SOP_FIELD_RECT)
    let testHost = WidgetTestHost()
    let body = {=> sopPromptDialog(texturaLight(), store, state)}
    let _ = testHost.frame(SOP_PROMPT_RECT, body: body)
    // Clearing the draft is allowed: a description may be empty.
    state.promptText.value = ""
    let _ = testHost.frameRecords(SOP_PROMPT_RECT, events: [CTRL_ENTER], body: body)
    @Expect(state.promptOpen.value, false)
    @Expect(currentNotes(store, target.id), "")
    @Expect(state.promptError.value.isEmpty(), true)
}

/**
 * The inspector wires both description boxes: clicking the painted 描述 field of the SOP and of a
 * step opens the prompt for that target, with the current notes as the initial value.
 */
@Test
func inspectorDescriptionFieldsOpenThePrompt(): Unit {
    let store = sopPromptStore()
    let workspace = store.state.value()
    var sop: ?Item = None
    for (summary in sopList(workspace)) {
        if (sop.isNone()) {
            sop = Some(summary.sop)
        }
    }
    let sopItem = match (sop) {
        case Some(item) => item
        case None =>
            @Expect("seeded sop", "missing")
            return
    }
    let step = match (firstStep(workspace)) {
        case Some(item) => item
        case None =>
            @Expect("seeded step", "missing")
            return
    }
    store.updateItem(sopItem.id, ItemPatch().withNotes("流程描述"))
    store.updateItem(step.id, ItemPatch().withNotes("步骤描述"))
    let state = SopViewState(State<Int64>(0))
    state.inspectorOpen = true
    let testHost = WidgetTestHost()
    let _ = testHost.frame(SOP_PROMPT_RECT) {=> }
    let view = buildFrame(testHost.context, store.state.value(), store, texturaLight(), tokensOf(texturaLight()),
        state, Rect(24.0, 56.0, 1152.0, 787.0), "2026-03-16")
    // SOP variant: the 描述 textarea opens the SOP notes prompt.
    let sopRects = inspectorRects(testHost.context, view)
    let sopHandled = handleSopSettings(view, sopRects, sopRects.notesArea.centerX(), sopRects.notesArea.centerY())
    @Expect(sopHandled, true)
    @Expect(sopPromptKindId(parseSopPromptKind(state.promptKind.value)), "sop-notes")
    @Expect(state.promptText.value, "流程描述")
    closeSopPrompt(state)
    // Node variant: same field, different target and copy. Re-read the step: `updateItem` replaced
    // the item, so the local snapshot taken before the write still holds the old notes.
    let refreshed = match (itemById(store.state.value(), step.id)) {
        case Some(item) => item
        case None =>
            @Expect("updated step", "missing")
            return
    }
    state.selectedNodeId = Some(refreshed.id)
    let nodeView = buildFrame(testHost.context, store.state.value(), store, texturaLight(),
        tokensOf(texturaLight()), state, Rect(24.0, 56.0, 1152.0, 787.0), "2026-03-16")
    let nodeRects = inspectorRects(testHost.context, nodeView)
    let nodeHandled = handleNodeFields(nodeView, nodeRects, refreshed, nodeRects.nodeNotesArea.centerX(),
        nodeRects.nodeNotesArea.centerY())
    @Expect(nodeHandled, true)
    @Expect(sopPromptKindId(parseSopPromptKind(state.promptKind.value)), "node-notes")
    @Expect(state.promptText.value, "步骤描述")
}
