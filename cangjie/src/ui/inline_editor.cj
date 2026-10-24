package textura.ui

import cui.*

/*
 * `Ui.inlineEditor` — edit a field **where it is**, with a real text control, and no dialog.
 *
 * Why this exists (docs/DEVICE-NOTES.md §16 and §20): the canvas-painted views (SOP inspector,
 * OKR cards, GTD rows) draw their "inputs" themselves, so they cannot host a CUI `TextField`
 * where the pixels are: CUI registers a focus stop only for controls declared **during build**,
 * and a canvas only knows its field rectangles after `layout`. The first fix was to open a modal
 * editor (`Ui.prompt`), which works but is a second window for every field — the user's
 * complaint. This is the third possibility: the editor is declared during build (so focus, caret
 * and the IME anchor all work), and it is *positioned* like the field, through a `Portal` at the
 * rectangle the view recorded while it laid the canvas out.
 *
 * Contract with a view (docs/DEVICE-NOTES.md §25):
 *   1. own an [InlineAnchor] across frames (`inlineAnchor("…")`);
 *   2. while laying the canvas out, `update(rect)` the anchor whenever that field is the one
 *      being edited — this is what keeps the editor on the field through scroll and resize;
 *   3. when the field is clicked, `request(rect)` + open the editor;
 *   4. call `Ui.inlineEditor(...)` from `build` with the anchor.
 *
 * `anchor.request/update` take **window-absolute** coordinates, the same space as `Ui.modal`'s
 * panel rect (sidebar + topbar + content padding + scroll offset are already in them). An anchor
 * that was never written (or was written with a zero extent) does **not** open an editor: the
 * editor waits for the field's layout and opens on the frame that stores a usable rect. Painting
 * a control from a zero rectangle is what put the editor in the window's top-left corner on
 * device (docs/DEVICE-NOTES.md §25.1).
 *
 * Editing semantics match the Web build: Enter commits (Ctrl/Cmd+Enter for a multi-line field),
 * Esc cancels, a press outside commits, focus leaving the editor commits, and a commit that the
 * caller refuses (validation) keeps the editor open with its error line under the field.
 * The dismissal layer is a **transparent full-window backdrop** registered below the editor: it
 * consumes primary presses (commit / keep focus) and Tab (focus stays in the editor), and it lets
 * wheel and pointer-move through so the page still scrolls under the editor. Esc and a backdrop
 * press close the editor even when the recorded rectangle is unusable — "cannot be dismissed" is
 * not an acceptable failure mode.
 * Geometry: same width and height as the field, accent border (CUI's focused `TextInputStyle`),
 * no panel, no scrim, no shadow.
 */

/**
 * Shortest usable single-line editor: one row of text with the input padding (`.input` is 34px,
 * ui.css:196-206, so a 34px field is exactly one row and a shorter box is floored here).
 */
private let INLINE_LINE_FLOOR: Float32 = 28.0
/**
 * A multi-line field is only allowed to grow on its own content above this anchor height. Below
 * it the field is a one-row box (a checklist row, a 30px label) and keeping the multi-line
 * minimum would make the editor taller than the box the canvas painted — the overlap the user
 * saw as "a second box below the field".
 */
private let INLINE_AREA_MIN_ANCHOR: Float32 = 40.0
/** Multi-line ceiling as a share of the window (`40vh`). */
private let INLINE_AREA_MAX_RATIO: Float32 = 0.40
/** Below this width an editor is unusable; the field rect is widened instead of collapsed. */
private let INLINE_MIN_WIDTH: Float32 = 72.0
/**
 * How many consecutive frames a **lost focus with no new owner** must persist before the edit is
 * committed.
 *
 * Leaving the editor really is "the user moved on" (Web parity), but *one* frame without focus is
 * not leaving: CUI re-describes the tree whenever a `State` read during build changes, and the
 * focused id is only re-adopted for ids registered during *that* build. A frame in which the
 * editor is being rebuilt (or its portal is placed for the first time) therefore reports
 * `focusId == ""` even though the user never touched anything. Committing there ends the edit
 * silently, and when the caller refuses the value it leaves the editor open but **unfocused** —
 * every later character goes nowhere while the dismissal backdrop keeps eating the presses, which
 * is exactly the "typing does nothing, then nothing responds at all" report
 * (docs/DEVICE-NOTES.md §26). A blur that persists for this many frames is a real one; a focus
 * that moved straight to another control commits immediately (that owner is not empty).
 */
private let INLINE_BLUR_FRAMES: Int64 = 2

/**
 * One inline edit session: the anchor, the dismissal protocol and the state the widgets below
 * share. **Remembered across frames** (`Ui.inlineEditor` keeps one per editor key) so the
 * blur-commit latch and the "field left the window" latch are real edges rather than per-frame
 * flags; `bind` refreshes the tokens/draft/callbacks from the newest declaration.
 */
public class InlineEditFrame {
    private var tokens: ThemeTokens
    private let ownerId: String
    private let key: String
    private let anchor: InlineAnchor
    private var multiline: Bool
    /** The draft the control is bound to; a commit submits exactly what the field shows. */
    private var draft: State<String>
    private var onCommit: (String) -> Unit
    private var onCancel: () -> Unit
    /** Where the control ended up this frame (`resolve`); used by the backdrop hit test. */
    private var fieldRect: Rect = Rect.zero()
    /** True once the editor itself owned focus — the precondition for "blur commits". */
    private var sawFocus: Bool = false
    /** Consecutive frames the editor has been without focus *and* without another owner. */
    private var blurFrames: Int64 = 0
    /**
     * The session should select its whole text once, on the frame the control is (re)built.
     *
     * A short numeric field is a *slot*, not a document: the box already shows `47`, the user
     * clicks it and types `42`. With the caret parked at the end (CUI's default) the result is
     * `4742` — visibly wrong, and the user reads it as "my input did not take". Selecting the
     * value on open makes the first character replace it, which is what the field's own
     * placeholder ("例如 42") promises.
     */
    private var selectAllPending: Bool = false
    /** True once the field scrolled out of the window: the edit is cancelled exactly once. */
    private var cancelledOffWindow: Bool = false

    init(
        tokens: ThemeTokens,
        ownerId: String,
        key: String,
        anchor: InlineAnchor,
        multiline: Bool,
        draft: State<String>,
        onCommit: (String) -> Unit,
        onCancel: () -> Unit
    ) {
        this.tokens = tokens
        this.ownerId = ownerId
        this.key = key
        this.anchor = anchor
        this.multiline = multiline
        this.draft = draft
        this.onCommit = onCommit
        this.onCancel = onCancel
    }

    /**
     * Rebinds the session to this frame's declaration. The control identity (`key`) and the anchor
     * stay; everything the caller owns (tokens, draft, callbacks) is taken from the newest build,
     * so a remembered frame can never call into a stale closure.
     *
     * A fresh `anchor.request(...)` is the "the user just opened a field" edge: it clears the
     * blur-commit latch so the previous session's focus cannot commit an untouched draft.
     */
    func bind(
        tokens: ThemeTokens,
        multiline: Bool,
        selectAllOnOpen: Bool,
        draft: State<String>,
        onCommit: (String) -> Unit,
        onCancel: () -> Unit
    ): Unit {
        this.tokens = tokens
        this.multiline = multiline
        this.draft = draft
        this.onCommit = onCommit
        this.onCancel = onCancel
        if (anchor.takeFresh()) {
            sawFocus = false
            cancelledOffWindow = false
            blurFrames = 0
            selectAllPending = selectAllOnOpen
        }
    }

    /**
     * True exactly once per edit session: the frame that builds the control should select its
     * text (`selectAllOnOpen`). Consuming the flag rather than keeping it keeps the selection
     * from being re-applied every frame — which would wipe the user's caret moves and their
     * drag-selection right after they made them.
     */
    func takeSelectAll(): Bool {
        let pending = selectAllPending
        selectAllPending = false
        pending
    }

    /** Overlay owner of the dismissal layer (registered below the content). */
    public func owner(): String {
        "UiInlineEditor:${ownerId}"
    }

    /** Overlay owner of the editor control itself. */
    public func contentOwner(): String {
        "${owner()}-content"
    }

    /** The field rectangle this frame, window-absolute and unclamped (the anchor's value). */
    func target(): Rect {
        anchor.current()
    }

    /**
     * Height the control is built with. The editor covers the field box and nothing more:
     *   - a single-line field (or any field shorter than 40px) keeps its own height, floored at
     *     one row (`INLINE_LINE_FLOOR`) so the caret has somewhere to sit;
     *   - a multi-line field at least 40px tall uses its own height too — `resolve` is what caps
     *     it at 40vh — so a description box is not silently inflated past the painted rectangle.
     */
    func fieldHeight(): Float32 {
        let anchorRect = target()
        if (multiline && anchorRect.h >= INLINE_AREA_MIN_ANCHOR) {
            anchorRect.h
        } else if (anchorRect.h >= INLINE_LINE_FLOOR) {
            anchorRect.h
        } else {
            INLINE_LINE_FLOOR
        }
    }

    /**
     * Absolute rectangle of the editor: the field's own box, widened to a usable minimum, moved
     * inside the window, and — for a multi-line field — capped at 40vh so a tall description field
     * cannot cover the page.
     *
     * For every field that fits the window and is at least [INLINE_MIN_WIDTH] wide this returns
     * the anchor unchanged, which is the invariant the host tests pin: the real control must land
     * exactly on the rectangle the view painted. The rect is clamped to the window **without an
     * artificial margin**, so a field at the content edge keeps its own coordinates; only a field
     * that the window edge cuts off is pulled back inside.
     */
    public func resolve(ctx: UiContext): Rect {
        let viewportWidth = max(0.0, ctx.viewportWidth)
        let viewportHeight = max(0.0, ctx.viewportHeight)
        let anchorRect = target()
        let width = min(max(anchorRect.w, INLINE_MIN_WIDTH), max(0.0, viewportWidth))
        var height = fieldHeight()
        if (multiline && anchorRect.h >= INLINE_AREA_MIN_ANCHOR) {
            height = min(height, max(INLINE_LINE_FLOOR, viewportHeight * INLINE_AREA_MAX_RATIO))
        }
        height = min(height, max(INLINE_LINE_FLOOR, viewportHeight))
        let x = clampF32(anchorRect.x, 0.0, max(0.0, viewportWidth - width))
        let y = clampF32(anchorRect.y, 0.0, max(0.0, viewportHeight - height))
        fieldRect = Rect(x, y, width, height)
        fieldRect
    }

    /**
     * Cancels the edit when the field is no longer on screen at all (the page scrolled it away or
     * the window shrank). Choice: **cancel**, not commit — a scroll is not a confirmation, and
     * cancelling leaves the stored value untouched, so nothing is silently written by scrolling.
     * The editor cannot be left floating over unrelated content, and Esc/backdrop keep working
     * while the cancellation is in flight.
     */
    func observeViewport(ctx: UiContext): Unit {
        if (cancelledOffWindow || !anchor.ready()) {
            return
        }
        let window = Rect(0.0, 0.0, max(0.0, ctx.viewportWidth), max(0.0, ctx.viewportHeight))
        let visible = window.intersection(target())
        if (visible.w <= 0.0 || visible.h <= 0.0) {
            cancelledOffWindow = true
            onCancel()
        }
    }

    /**
     * Commits when focus leaves the editor. Focus is the only "the user moved on" signal that also
     * covers a click on a non-editable spot, which CUI routes around the overlay; the latch is
     * cleared on open, because the editor has not received focus during its first frames yet (the
     * one-shot `FocusRequest` still retries).
     *
     * A frame with **no owner at all** is not a blur yet — it is the rebuild window in which the
     * editor's own focus id has not been re-adopted. The caret is re-asserted and the commit waits
     * for [INLINE_BLUR_FRAMES] frames, so a re-description cannot end an edit under the user's
     * fingers; a focus that moved *to another control* still commits on the very same frame
     * (`focusId` is not empty), which is the Web behaviour.
     */
    func observeFocus(ctx: UiContext): Unit {
        if (ctx.focusId == key) {
            sawFocus = true
            blurFrames = 0
            return
        }
        if (!sawFocus) {
            return
        }
        if (ctx.focusId.isEmpty() && blurFrames + 1 < INLINE_BLUR_FRAMES) {
            blurFrames += 1
            ctx.focus(key)
            ctx.requestFrame()
            return
        }
        sawFocus = false
        blurFrames = 0
        onCommit(draft.value)
    }

    /** `.text-danger`, one small line under the field: the caller refused the value. */
    func paintError(ctx: UiContext, message: String): Unit {
        if (message.isEmpty() || fieldRect.w <= 0.0) {
            return
        }
        let size: Float32 = 11.5
        let y = min(fieldRect.bottom() + 3.0, max(0.0, ctx.viewportHeight - size - 2.0))
        textLeading(ctx, message, fieldRect.x + 2.0, y + size / 2.0, tokens.color.danger, size, 500)
    }

    /**
     * The transparent backdrop's input protocol:
     *   - Esc cancels — **unconditionally**, even when the field rect is unusable;
     *   - Tab / Shift+Tab are consumed and focus stays on the editor (no traversal into the page
     *     underneath; Esc, Enter or a press outside are the ways out);
     *   - a primary press inside the field keeps the caret, anywhere else commits (the Web
     *     build's "click outside = done") — and it is always consumed, so the page's painted
     *     hotspots can never fire behind an open editor;
     *   - everything else (wheel, pointer moves, typing) is left to the control and the page.
     */
    func handleOverlay(ctx: UiContext, event: UiEvent): Bool {
        // 失焦提交挂在这里而不是只挂在 `layout` 上：CUI 的保留图会跳过「本帧没变化」的子树，
        // 编辑器那段布局并不是每帧都跑，而事件一定会送到 overlay。
        observeFocus(ctx)
        match (event) {
            case UiEvent.KeyDown(Key.Escape, isRepeat) =>
                if (!isRepeat) {
                    onCancel()
                }
                true
            case UiEvent.KeyDown(Key.Tab, isRepeat) =>
                if (!isRepeat) {
                    ctx.focus(key)
                }
                true
            case UiEvent.MouseDown(button, x, y) =>
                if (isPrimaryPointerButton(button)) {
                    if (fieldRect.contains(x, y)) {
                        ctx.focus(key)
                    } else {
                        onCommit(draft.value)
                    }
                }
                true
            case UiEvent.MouseUp(_, _, _) => true
            case _ => false
        }
    }
}

/**
 * Dismissal layer for [InlineEditFrame]: a full-window, fully transparent backdrop registered
 * below the editor. It turns "a press outside the field" and "focus went elsewhere" into a
 * commit, "Esc" into a cancel, and paints the caller's validation line. The editor itself is a
 * sibling `Portal` (see `Ui.inlineEditor`), so its controls are declared during build.
 */
public class InlineEditorHost <: Widget {
    private let frame: InlineEditFrame
    private let error: String

    public init(frame: InlineEditFrame, error: String) {
        this.frame = frame
        this.error = error
        // Per-frame hook for the focus latch. Neither hook below runs every frame on its own:
        // the retained graph skips the layout of an unchanged subtree, and events only arrive when
        // the user does something — so a focus lost during a *rebuild* would not be noticed until
        // the next keystroke, and that keystroke is exactly when it costs a character. Frame ticks
        // always run, which turns "the editor lost focus for one frame" into "the caret is back
        // before the next key arrives" (docs/DEVICE-NOTES.md §26).
        subscribeFrame({ctx, _ => frame.observeFocus(ctx)})
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size.zero()
    }

    public func layout(ctx: UiContext, _: Rect): Unit {
        let _ = frame.resolve(ctx)
        frame.observeViewport(ctx)
        ctx.setOverlay(
            Overlay(handleEvent: {c, e => frame.handleOverlay(c, e)}, render: {c => frame.paintError(c, error)},
                owner: frame.owner()))
        frame.observeFocus(ctx)
    }

    public func draw(_: UiContext): Unit {
        // The overlay registered during layout paints the validation line.
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }

    public func participatesInLayout(): Bool {
        false
    }

    public func needsDetachedLayout(): Bool {
        true
    }
}
