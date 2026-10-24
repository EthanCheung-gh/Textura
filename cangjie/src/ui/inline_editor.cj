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
 * Contract with a view:
 *   1. while laying the canvas out, remember the field rect (`inspectorRects`, `okrCardRects`, …);
 *   2. when the field is clicked, store that rect + the current text in the view state and open
 *      the editor;
 *   3. call `Ui.inlineEditor(...)` from `build` with the stored rect — the editor appears on top
 *      of the page, at the field, and takes focus on the first frame.
 *
 * Editing semantics match the Web build: Enter commits (Ctrl/Cmd+Enter for a multi-line field),
 * Esc cancels, a click outside commits, and a commit that the caller refuses (validation) keeps
 * the editor open with its error line under the field. Geometry: same width and height as the
 * field, accent border (CUI's focused `TextInputStyle`), no panel, no scrim, no shadow.
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
/** Keep the editor inside the window even when the field sits against an edge. */
private let INLINE_MARGIN: Float32 = 6.0
/** Below this width an editor is unusable; the field rect is widened instead of collapsed. */
private let INLINE_MIN_WIDTH: Float32 = 72.0

/**
 * One open inline edit: the field rectangle, the dismissal protocol and the state the widgets
 * below share. Created per frame (the declaration site rebuilds whenever the view state changes),
 * so nothing here can go stale across frames.
 */
public class InlineEditFrame {
    let tokens: ThemeTokens
    private let ownerId: String
    private let key: String
    private let anchor: Rect
    private let multiline: Bool
    /** The draft the control is bound to; a commit submits exactly what the field shows. */
    private let draft: State<String>
    private let onCommit: (String) -> Unit
    private let onCancel: () -> Unit
    private var fieldRect: Rect = Rect.zero()
    /** True once the editor itself owned focus — the precondition for "blur commits". */
    private var sawFocus: Bool = false

    init(
        tokens: ThemeTokens,
        ownerId: String,
        key: String,
        anchor: Rect,
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

    /** Overlay owner of the dismissal layer (registered below the content). */
    public func owner(): String {
        "UiInlineEditor:${ownerId}"
    }

    /** Overlay owner of the editor control itself. */
    public func contentOwner(): String {
        "${owner()}-content"
    }

    /**
     * Height the control is built with. The editor covers the field box and nothing more:
     *   - a single-line field (or any field shorter than 40px) keeps its own height, floored at
     *     one row (`INLINE_LINE_FLOOR`) so the caret has somewhere to sit;
     *   - a multi-line field at least 40px tall uses its own height too — `resolve` is what caps
     *     it at 40vh — so a description box is not silently inflated past the painted rectangle.
     */
    func fieldHeight(): Float32 {
        if (multiline && anchor.h >= INLINE_AREA_MIN_ANCHOR) {
            anchor.h
        } else if (anchor.h >= INLINE_LINE_FLOOR) {
            anchor.h
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
     * `anchor` unchanged, which is the invariant the host tests pin: the real control must land
     * exactly on the rectangle the view painted.
     */
    public func resolve(ctx: UiContext): Rect {
        let viewportWidth = max(0.0, ctx.viewportWidth)
        let viewportHeight = max(0.0, ctx.viewportHeight)
        let width = min(max(anchor.w, INLINE_MIN_WIDTH), max(INLINE_MIN_WIDTH, viewportWidth - INLINE_MARGIN * 2.0))
        var height = fieldHeight()
        if (multiline && anchor.h >= INLINE_AREA_MIN_ANCHOR) {
            height = min(height, max(INLINE_LINE_FLOOR, viewportHeight * INLINE_AREA_MAX_RATIO))
        }
        let maxX = max(INLINE_MARGIN, viewportWidth - width - INLINE_MARGIN)
        let maxY = max(INLINE_MARGIN, viewportHeight - height - INLINE_MARGIN)
        fieldRect = Rect(clampF32(anchor.x, INLINE_MARGIN, maxX), clampF32(anchor.y, INLINE_MARGIN, maxY), width, height)
        fieldRect
    }

    /**
     * Commits when focus leaves the editor. Focus is the only "the user moved on" signal that also
     * covers Tab traversal, which CUI routes around the overlay; the first frames are ignored
     * because the editor has not received focus yet (the one-shot `FocusRequest` still retries).
     */
    func observeFocus(ctx: UiContext): Unit {
        if (ctx.focusId == key) {
            sawFocus = true
            return
        }
        if (sawFocus) {
            onCommit(draft.value)
        }
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
     * Esc cancels, a press outside the field commits (the Web build's behaviour), everything else
     * is left to the control and to CUI: returning false for Tab/typing is what keeps traversal and
     * text entry working while the editor is open.
     */
    func handleOverlay(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.KeyDown(Key.Escape, isRepeat) =>
                if (!isRepeat) {
                    onCancel()
                }
                true
            case UiEvent.MouseDown(button, x, y) =>
                if (isPrimaryPointerButton(button) && !fieldRect.contains(x, y)) {
                    onCommit(draft.value)
                    true
                } else {
                    false
                }
            case _ => false
        }
    }
}

/**
 * Dismissal layer for [InlineEditFrame]: registers the overlay that turns "outside press" and
 * "focus went elsewhere" into a commit, and paints the caller's validation line. The editor
 * itself is a sibling `Portal` (see `Ui.inlineEditor`), so its controls are declared during build.
 */
public class InlineEditorHost <: Widget {
    private let frame: InlineEditFrame
    private let error: String

    public init(frame: InlineEditFrame, error: String) {
        this.frame = frame
        this.error = error
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size.zero()
    }

    public func layout(ctx: UiContext, _: Rect): Unit {
        let _ = frame.resolve(ctx)
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
