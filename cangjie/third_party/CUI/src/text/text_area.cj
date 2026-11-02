package cui.text

import sdl.{Key, MouseButton, Rect, Size, UiEvent}
import cui.core.{Bindable, CUI_SMALL_H, CursorShape, ScrollBar, maxScrollOffset, State, UiContext, Widget,
    claimHoverIfInside, clampScrollOffset, emit, localState, registerFocusable, resolveControlKey,
    registerFrameSubscriber, scrollByWheel, Semantics, SemanticsAction, SemanticsRole, drawVerticalScrollBar}

private let TEXT_AREA_COPY_SHORTCUT: UInt8 = 67

/*
 * A multi-line text editor bound to a `Bindable<String>`, with vertical scrolling and a scroll bar.
 * As in `TextField`, the caret and selection anchor are BYTE offsets into the UTF-8 text; an owner
 * that moves the cursor from outside (loading a file, a programmatic paste) must move the anchor with
 * it, or the next keystroke replaces a selection the user never made. Visual rows are cached
 * by text, font environment and wrapping width; scrolling paints only visible rows.
 * `editable: false` renders read-only and stays out of Tab traversal.
 */
public class TextArea <: Widget {
    private let id: String
    private let text: Bindable<String>
    private var scrollStateValue: State<Float32>
    private var cursorStateValue: State<Int64>
    private var anchorStateValue: State<Int64>
    private var isEditable: Bool
    private let scrollBar: ScrollBar
    private let history: UndoHistory
    private let clipboard: TextClipboard
    private let interaction: TextAreaInteraction
    private let boundaryCache: TextEditBoundaryCache
    private var inputAppearance = TextInputStyle()
    private var hint = ""
    private var wrapLines = false
    private var autofocusRequested = false
    private let autofocusDone: State<Bool>
    private var frame = Rect.zero()
    private var rowHeight: Float32 = CUI_SMALL_H
    // CUI-P10: printable presses the platform reports only as `KeyDown`, inserted one frame later
    // unless the IME commits them first. See `text_printable_key.cj`.
    private let printableKeys: PrintableKeyFallback

    public init(
        text: Bindable<String>,
        key!: ?String = None,
        scroll!: ?State<Float32> = None,
        cursor!: ?State<Int64> = None,
        anchor!: ?State<Int64> = None,
        editable!: Bool = true,
        clipboard!: TextClipboard = TextClipboard.system
    ) {
        let ident = resolveControlKey(key, "TextArea")
        this.id = ident
        this.text = text
        this.scrollStateValue = match (scroll) {
            case Some(value) => value
            case None => localState<Float32>("TextArea:${ident}:scroll") {0.0}
        }
        this.cursorStateValue = match (cursor) {
            case Some(value) => value
            case None => localState<Int64>("TextArea:${ident}:cursor") {text.value.size}
        }
        // The anchor starts collapsed on the caret so no phantom selection appears. A caller
        // that owns the cursor and moves it from outside (loading a file, a programmatic
        // paste) must own the anchor too and move both together — otherwise the stale anchor
        // spans a selection the user never made, and the next keystroke replaces it.
        let caretStart = cursorStateValue.value
        this.anchorStateValue = match (anchor) {
            case Some(value) => value
            case None => localState<Int64>("TextArea:${ident}:anchor") {caretStart}
        }
        this.isEditable = editable
        this.scrollBar = ScrollBar("TextArea:${ident}:thumb")
        this.history = localState<UndoHistory>("TextArea:${ident}:history") {UndoHistory()}.value
        this.clipboard = clipboard
        this.interaction = TextAreaInteraction(ident, history)
        this.boundaryCache = localState<TextEditBoundaryCache>("TextArea:${ident}:boundaries") {TextEditBoundaryCache()}
            .value
        this.autofocusDone = localState<Bool>("TextArea:${ident}:autofocused") {false}
        this.printableKeys = PrintableKeyFallback("TextArea:${ident}", ident)
        // A read-only text area is not an editing stop, so it stays out of Tab traversal.
        if (editable) {
            registerFocusable(ident)
        }
        // Last, once every member is assigned: `arm` captures this control's insert path and asks for
        // the frame tick that inserts a staged printable character.
        printableKeys.arm(isEditable, {
            ctx, value =>
                interaction.preferredX.value = -1.0
                interaction.upstream.value = false
                let changed = actions().insert(value, ctx.frame.elapsedMs, isolated: false)
                revealCaretLine()
                changed
        })
        emit(this)
    }

    /** Sets colors, inner padding, alignment and minimum visual row height. */
    public func style(value: TextInputStyle): TextArea {
        inputAppearance = value
        this
    }
    /** Shows a hint while the document and pre-edit are empty. */
    public func placeholder(value: String): TextArea {
        hint = normalizedEditorInput(value, multiline: true)
        this
    }
    /** Wraps visual rows without changing document bytes; disabled by default. */
    public func wrap(value!: Bool = true): TextArea {
        wrapLines = value
        this
    }

    /** Claims keyboard focus the first time an editable area appears (e.g. a compose box). */
    public func autofocus(): TextArea {
        autofocusRequested = true
        registerFrameSubscriber({ctx, _ => applyAutofocus(ctx)})
        this
    }

    /** Reverts the last edit group; also bound to Ctrl+Z. */
    public func undo(): Unit {
        interaction.upstream.value = false
        interaction.preferredX.value = -1.0
        actions().undo()
        revealCaretLine()
    }

    /** Reapplies the last undone edit; also bound to Ctrl+Y / Ctrl+Shift+Z. */
    public func redo(): Unit {
        interaction.upstream.value = false
        interaction.preferredX.value = -1.0
        actions().redo()
        revealCaretLine()
    }

    /** Selects all text; selection and copying remain available in read-only mode. */
    public func selectAll(): Unit {
        interaction.upstream.value = false
        interaction.preferredX.value = -1.0
        actions().selectAll()
    }
    /** Selects byte offsets, snapping both endpoints to extended-grapheme boundaries. */
    public func selectRange(anchor: Int64, cursor: Int64): Unit {
        interaction.upstream.value = false
        interaction.preferredX.value = -1.0
        actions().selectRange(anchor, cursor)
    }
    /** Returns selected plain text. */
    public func selectedText(): String {
        actions().selectedText()
    }
    /** Replaces selection as one undo step; an empty value deletes the selection. */
    public func replaceSelection(value: String): Bool {
        interaction.upstream.value = false
        interaction.preferredX.value = -1.0
        let changed = actions().replaceSelection(value)
        if (changed) {
            revealCaretLine()
        }
        changed
    }
    /** Copies selection; false means empty selection or a rejected/failed clipboard write. */
    public func copy(): Bool {
        actions().copy()
    }
    /** Deletes selection only after a successful copy; read-only controls return false. */
    public func cut(): Bool {
        interaction.upstream.value = false
        interaction.preferredX.value = -1.0
        let changed = actions().cut()
        if (changed) {
            revealCaretLine()
        }
        changed
    }
    /** Pastes as one undo step; empty/failed clipboard reads leave selection intact. */
    public func paste(): Bool {
        interaction.upstream.value = false
        interaction.preferredX.value = -1.0
        let changed = actions().paste()
        if (changed) {
            revealCaretLine()
        }
        changed
    }
    /** Whether this editable document has an undo step. */
    public func canUndo(): Bool {
        actions().canUndo()
    }
    /** Whether this editable document has a redo step. */
    public func canRedo(): Bool {
        actions().canRedo()
    }

    public func measure(ctx: UiContext, available: Size): Size {
        rowHeight = inputAppearance.rowHeight(ctx, multiline: true)
        Size(available.w, available.h)
    }

    public func layout(ctx: UiContext, rect: Rect): Unit {
        rowHeight = inputAppearance.rowHeight(ctx, multiline: true)
        frame = rect
        let supported = if (isEditable) {
            [SemanticsAction.Focus, SemanticsAction.SetValue("")]
        } else {
            [SemanticsAction.Focus]
        }
        ctx.registerSemanticProvider(id, rect, supported,
            {=> Semantics(role: SemanticsRole.TextField, value: text.value)}, {
                action => match (action) {
                    case SemanticsAction.Focus =>
                        ctx.focus(id, viaKeyboard: true);
                        true
                    case SemanticsAction.SetValue(next) where isEditable && !next.contains("\u{0000}") =>
                        interaction.preferredX.value = -1.0
                        if (this.actions().replaceValue(next)) {
                            ctx.requestFrame()
                        }
                        revealCaretLine()
                        true
                    case _ => false
                }
            })
    }

    public func draw(ctx: UiContext): Unit {
        let view = editorView(ctx)
        let clampedScroll = if (interaction.revealPending.value) {
            view.followVertical()
        } else {
            clampScrollOffset(scrollStateValue.value, view.contentHeight(), view.viewport.h)
        }
        interaction.revealPending.value = false
        if (clampedScroll != scrollStateValue.value) {
            scrollStateValue.value = clampedScroll
        }
        view.scroll = clampedScroll
        let offset = if (wrapLines) {
            Float32(0.0)
        } else {
            view.followHorizontal()
        }
        if (offset != interaction.xOffset.value) {
            interaction.xOffset.value = offset
        }
        view.xShift = offset
        view.draw(frame, id, isEditable, hint, interaction.blinkEpoch.value)
        drawVerticalScrollBar(ctx, frame, clampedScroll, view.contentHeight(), view.viewport.h,
            active: scrollBar.dragging(ctx))
    }

    private func editorView(ctx: UiContext): TextEditorView {
        let edit = editState()
        if (interaction.lastCaret.value != edit.cursor.value) {
            if (interaction.lastCaret.value >= 0) {
                interaction.revealPending.value = true
            }
            interaction.blinkEpoch.value = ctx.frame.elapsedMs
            interaction.lastCaret.value = edit.cursor.value
        }
        if (!isEditable && ctx.hasFocus(id)) {
            ctx.clearTextInputAnchor();
            ctx.clearImeComposition()
        }
        let view = TextEditorView(ctx, frame, TextEditorDisplay(ctx, id, edit, isEditable), interaction.layoutCache,
            TextEditorViewState(inputAppearance, multiline: true, wrap: wrapLines, scroll: scrollStateValue.value,
                xShift: interaction.xOffset.value, upstream: interaction.upstream.value))
        rowHeight = view.rowHeight
        view
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        let consumed = handleEvent(ctx, event)
        if (interaction.revealPending.value) {
            let next = editorView(ctx).followVertical()
            if (scrollStateValue.value != next) {
                scrollStateValue.value = next
            }
            interaction.revealPending.value = false
        }
        consumed
    }

    private func handleEvent(ctx: UiContext, event: UiEvent): Bool {
        let view = editorView(ctx)
        claimHoverIfInside(ctx, event, frame, id, CursorShape.Text)
        let edit = editState()
        match (event) {
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (scrollBar.press(ctx, frame, scrollStateValue, view.contentHeight(), view.viewport.h, x, y)) {
                    return true
                }
                return pressAt(ctx, edit, x, y)
            case UiEvent.MouseMove(x, y) =>
                if (scrollBar.drag(ctx, frame, scrollStateValue, view.contentHeight(), view.viewport.h, y)) {
                    return true
                }
                if (ctx.isDragging(id) && ctx.leftMouseDown) {
                    edit.extendTo(pointOffset(ctx, x, y))
                    revealCaretLine()
                    return true
                }
            case UiEvent.MouseWheel(_, wheelY, pointerX, pointerY) => return scrollWheel(view, wheelY, pointerX,
                pointerY)
            case UiEvent.TextEditing(value, start, length) =>
                if (ctx.hasFocus(id) && isEditable) {
                    printableKeys.cancel() // the IME owns this press; its commit is the text
                    ctx.setImeComposition(id, value, start, length)
                    interaction.revealPending.value = true
                    return true
                }
            case UiEvent.TextEditingCandidates(values, selected, horizontal) =>
                if (ctx.hasFocus(id) && isEditable) {
                    ctx.setImeCandidates(id, values, selected, horizontal)
                    return true
                }
            case UiEvent.TextInput(value) => return inputText(ctx, value)
            case UiEvent.KeyDown(key, _) => return handleKey(ctx, edit, key)
            case UiEvent.Frame(_) =>
                // One-time initial focus for an editable area, applied after the frame's pointer
                // events so a stray startup click cannot cancel it; mirrors TextField.
                applyAutofocus(ctx)
                // Second, idempotent trigger for hosts that broadcast a frame event down the tree;
                // `DesktopApp` reaches the staged character through the one-frame subscription that
                // `PrintableKeyFallback.arm` registers (see `text_printable_key.cj`).
                printableKeys.flush(ctx)
            case _ => ()
        }
        false
    }

    public func isFlexible(): Bool {
        true
    }

    private func scrollWheel(view: TextEditorView, wheelY: Float32, pointerX: Float32, pointerY: Float32): Bool {
        let contentH = view.contentHeight()
        let viewportH = view.viewport.h
        if (!frame.contains(pointerX, pointerY) || maxScrollOffset(contentH, viewportH) <= 0.0) {
            return false
        }
        return scrollByWheel(scrollStateValue, wheelY, contentH, viewportH)
    }

    private func handleKey(ctx: UiContext, edit: TextEditState, key: Key): Bool {
        match (key) {
            case Key.Enter => return recordedEdit(ctx, {=> edit.insert("\n")})
            case Key.Backspace => return recordedEdit(ctx, {
                => if (textWordModifier(ctx)) {
                    edit.deleteWordBackward()
                } else {
                    edit.backspace()
                }
            })
            case Key.Delete => return recordedEdit(ctx, {
                => if (textWordModifier(ctx)) {
                    edit.deleteWordForward()
                } else {
                    edit.deleteForward()
                }
            })
            case Key.Left =>
                if (textWordModifier(ctx)) {
                    return navigate(ctx, {=> edit.moveWordLeft()}, {=> edit.extendWordLeft()})
                }
                return navigate(ctx, {=> edit.moveLeft()}, {=> edit.extendLeft()})
            case Key.Right =>
                if (textWordModifier(ctx)) {
                    return navigate(ctx, {=> edit.moveWordRight()}, {=> edit.extendWordRight()})
                }
                return navigate(ctx, {=> edit.moveRight()}, {=> edit.extendRight()})
            case Key.Up => return interaction.moveVertical(ctx, edit, editorView(ctx), -1)
            case Key.Down => return interaction.moveVertical(ctx, edit, editorView(ctx), 1)
            case Key.PageUp => return interaction.moveVertical(ctx, edit, editorView(ctx),
                -max(1, Int64(inputAppearance.viewport(ctx, frame).h / rowHeight)))
            case Key.PageDown => return interaction.moveVertical(ctx, edit, editorView(ctx),
                max(1, Int64(inputAppearance.viewport(ctx, frame).h / rowHeight)))
            case Key.Home =>
                if (ctx.eventModifiers().command) {
                    return navigate(ctx, {=> edit.moveToStart()}, {=> edit.extendToStart()})
                }
                return interaction.moveEdge(ctx, edit, editorView(ctx), toEnd: false)
            case Key.End =>
                if (ctx.eventModifiers().command) {
                    return navigate(ctx, {=> edit.moveToEnd()}, {=> edit.extendToEnd()})
                }
                return interaction.moveEdge(ctx, edit, editorView(ctx), toEnd: true)
            // A plain letter press may be the platform's last word on the character (no `TextInput`
            // behind it); a modifier makes it a command instead, which `stage` declines.
            case Key.Letter(code) =>
                if (printableKeys.stage(ctx, isEditable, key)) {
                    return true
                }
                return shortcut(ctx, edit, code)
            case Key.Digit(_) => return printableKeys.stage(ctx, isEditable, key)
            case Key.Space => return printableKeys.stage(ctx, isEditable, key)
            case _ => false
        }
    }

    public func focusableId(): ?String {
        textEditorFocusableId(id, isEditable)
    }

    private func editState(): TextEditState {
        TextEditState(text, cursorStateValue, anchorStateValue, boundaryCache)
    }

    private func actions(): TextEditorActions {
        TextEditorActions(editState(), history, clipboard, isEditable, multiline: true)
    }

    private func applyAutofocus(ctx: UiContext): Unit {
        focusTextEditorOnce(ctx, id, autofocusRequested, isEditable, autofocusDone)
    }

    // Runs a mutating action while focused and editable, recording it for undo. The
    // before/after text comparison means a no-op edit adds no undo step.
    private func inputText(ctx: UiContext, value: String): Bool {
        if (!ctx.hasFocus(id) || !isEditable) {
            return false
        }
        interaction.preferredX.value = -1.0
        interaction.upstream.value = false
        // The IME delivered the character for a press this control had staged: it supersedes it.
        printableKeys.cancel()
        let composing = ctx.imeComposition(id).isSome()
        ctx.clearImeComposition()
        if (actions().insert(value, ctx.frame.elapsedMs, isolated: composing)) {
            ctx.requestFrame()
        }
        revealCaretLine()
        true
    }

    private func recordedEdit(ctx: UiContext, action: () -> Unit): Bool {
        if (!ctx.hasFocus(id) || !isEditable) {
            return false
        }
        if (ctx.imeComposition(id).isSome()) {
            return true
        }
        interaction.preferredX.value = -1.0
        interaction.upstream.value = false
        if (actions().record(ctx.frame.elapsedMs, action)) {
            ctx.requestFrame()
        }
        revealCaretLine()
        true
    }

    private func revealCaretLine(): Unit {
        interaction.revealPending.value = true
    }



    private func pointOffset(ctx: UiContext, x: Float32, y: Float32): Int64 {
        let (offset, affinity) = editorView(ctx).hit(x, y)
        interaction.upstream.value = affinity
        offset
    }

    private func pressAt(ctx: UiContext, edit: TextEditState, x: Float32, y: Float32): Bool {
        if (frame.contains(x, y)) {
            interaction.preferredX.value = -1.0
            ctx.focus(id)
            let offset = pointOffset(ctx, x, y)
            ctx.clearImeComposition()
            interaction.blinkEpoch.value = ctx.frame.elapsedMs
            if (ctx.clickCount == 2) {
                edit.selectWordAt(offset)
            } else if (ctx.clickCount >= 3) {
                edit.selectLineAt(offset)
            } else {
                if (ctx.eventModifiers().shift) {
                    edit.extendTo(offset)
                } else {
                    edit.moveTo(offset)
                }
                ctx.beginDrag(id) // a press-drag extends the selection (see MouseMove)
            }
            history.breakGroup() // edits before and after a caret jump undo separately
            return true
        }
        false
    }

    // Held Shift extends the selection; plain navigation collapses it. Navigation stays
    // available in read-only mode so text can be selected for copying.
    private func navigate(ctx: UiContext, moveCaret: () -> Unit, growSelection: () -> Unit): Bool {
        if (!ctx.hasFocus(id)) {
            return false
        }
        if (ctx.imeComposition(id).isSome()) {
            return true
        }
        interaction.preferredX.value = -1.0
        interaction.upstream.value = false
        if (ctx.eventModifiers().shift) {
            growSelection()
        } else {
            moveCaret()
        }
        history.breakGroup() // edits before and after a caret jump undo separately
        revealCaretLine()
        true
    }



    private func shortcut(ctx: UiContext, _: TextEditState, code: UInt8): Bool {
        let consumed = handleEditorShortcut(ctx, id, code, actions())
        if (consumed && code != TEXT_AREA_COPY_SHORTCUT) {
            interaction.preferredX.value = -1.0
            interaction.upstream.value = false
            revealCaretLine()
        }
        consumed
    }
}
