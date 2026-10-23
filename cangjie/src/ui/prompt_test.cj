package textura.ui

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*

/*
 * `Ui.prompt` — the shared "edit one field" overlay used by the canvas views (SOP, OKR).
 *
 * Three things have to hold, because the canvas views cannot host an inline `TextField`:
 *   1. the body is declared during build, so the editor is a real focus stop;
 *   2. opening the prompt focuses the editor once (and a later Save/Cancel press must not be
 *      undone by a per-frame focus grab);
 *   3. Enter saves, Esc cancels, and neither writes when the caller validates the value away.
 */

private let PROMPT_RECT: Rect = Rect(0.0, 0.0, 1440.0, 900.0)

private class PromptHarness {
    let open = State<Bool>(false)
    let text = State<String>("")
    let focus = FocusRequest()
    let saved = ArrayList<String>()
    var dismissed = 0
    let key: String = "prompt-test-input"

    func arm(value: String): Unit {
        text.value = value
        open.value = true
        focus.request(key)
    }

    func build(theme: Theme): Unit {
        Ui.prompt(theme, text, open, {=> dismiss()}, title: "编辑标题", key: key, label: "标题",
            placeholder: "例如：给财务回电", focus: focus, onSave: {value => saved.add(value)})
        FocusOnceView(focus)
    }

    func dismiss(): Unit {
        dismissed += 1
        open.value = false
        focus.cancel()
    }
}

@Test
func promptOpensWithItsEditorFocused(): Unit {
    let harness = PromptHarness()
    let testHost = WidgetTestHost()
    harness.arm("旧标题")
    let _ = testHost.frame(PROMPT_RECT, body: {=> harness.build(texturaLight())})
    @Expect(testHost.context.focusId, harness.key)
    // The editor is laid out inside the measured panel — a zero-height panel or a body that never
    // got the flex leftover would still focus, so pin the geometry the dialog depends on.
    var editor: ?SemanticsNode = None
    for (node in testHost.context.semanticsSnapshot()) {
        if (node.id == harness.key) {
            editor = Some(node)
        }
    }
    @Expect(editor.isSome(), true)
    match (editor) {
        case Some(node) =>
            @Expect(node.bounds.w > 200.0, true)
            @Expect(node.bounds.h >= 30.0, true)
            @Expect(node.bounds.y > 0.0 && node.bounds.bottom() < PROMPT_RECT.h, true)
        case None => ()
    }
}

@Test
func promptEnterSavesTheEditedText(): Unit {
    let harness = PromptHarness()
    let testHost = WidgetTestHost()
    harness.arm("旧标题")
    let _ = testHost.frame(PROMPT_RECT, body: {=> harness.build(texturaLight())})
    // The editor is focused, so typed text lands in the draft.
    let _ = testHost.frame(PROMPT_RECT, events: [UiEvent.TextInput("新标题")],
        body: {=> harness.build(texturaLight())})
    @Expect(harness.text.value, "旧标题新标题")
    let _ = testHost.frame(PROMPT_RECT, events: [UiEvent.KeyDown(Key.Enter, false)],
        body: {=> harness.build(texturaLight())})
    @Expect(harness.saved.size, 1)
    @Expect(harness.saved[0], "旧标题新标题")
}

@Test
func promptEscapeCancelsWithoutSaving(): Unit {
    let harness = PromptHarness()
    let testHost = WidgetTestHost()
    harness.arm("旧标题")
    let _ = testHost.frame(PROMPT_RECT, body: {=> harness.build(texturaLight())})
    let _ = testHost.frame(PROMPT_RECT, events: [UiEvent.KeyDown(Key.Escape, false)],
        body: {=> harness.build(texturaLight())})
    @Expect(harness.dismissed, 1)
    @Expect(harness.saved.size, 0)
    @Expect(harness.open.value, false)
}

/**
 * The focus request is one-shot: after the user Tabs away from the editor (the dialog traps
 * Tab inside its own body), the next frame must not pull focus back.
 */
@Test
func promptTabDoesNotSnapBackToTheEditor(): Unit {
    let harness = PromptHarness()
    let testHost = WidgetTestHost()
    harness.arm("旧标题")
    let _ = testHost.frame(PROMPT_RECT, body: {=> harness.build(texturaLight())})
    @Expect(testHost.context.focusId, harness.key)
    let _ = testHost.frame(PROMPT_RECT, events: [UiEvent.KeyDown(Key.Tab, false)],
        body: {=> harness.build(texturaLight())})
    let afterTab = testHost.context.focusId
    @Expect(afterTab.isEmpty(), false)
    @Expect(afterTab == harness.key, false)
    let _ = testHost.frame(PROMPT_RECT, body: {=> harness.build(texturaLight())})
    @Expect(testHost.context.focusId, afterTab)
}
