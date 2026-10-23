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
    openSopPrompt(state, SopPromptKind.NodeTitle, step.id, step.title)
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
    openSopPrompt(state, SopPromptKind.NodeTitle, step.id, "")
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
    openSopPrompt(state, SopPromptKind.NodeDuration, step.id, "")
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
