package textura.ui

import cui.*

/*
 * `InlineAnchor` — the window-absolute rectangle of the field an inline editor sits on.
 *
 * ## Why a separate object instead of a `Rect` field on the view state
 *
 * The rect has to survive **until the editor's frame runs**, and that is a different frame than
 * the click. Two of the three views that edit in place rebuild a *throwaway* state shell every
 * frame (`OkrUiState()` / `GtdState()` in `okr_page.cj` / `gtd_state.cj`); only their CUI `State`s
 * are remembered. A plain `var promptRect: Rect` therefore came back as `Rect.zero()` on the very
 * next build, which placed the editor in the window's top-left corner — the on-device report
 * ("输入框出现在应用左上角，原字段位置消失，而且无法关闭"): the field was painted in its
 * editing state (text suppressed) while the real control sat at (0, 0) over the sidebar, and a
 * backdrop press there committed an empty draft that the caller rejected, so it never went away.
 *
 * ## Coordinate contract
 *
 * `request`/`update` take **window-absolute** coordinates — the same space as `Ui.modal`'s panel
 * rect: sidebar (240) + topbar (56) + content padding (24) and the content scroll offset are
 * already included, because the views derive their field rects from the layout rectangle CUI
 * hands them (which is absolute; `ScrollView` subtracts its offset before laying the child out).
 * Canvas views therefore pass their own canvas coordinates unchanged, and a field inside a
 * scrolled page simply reports the scrolled position.
 *
 * ## `revision`
 *
 * A CUI `State<Int64>` bumped whenever the rect really changes (open, scroll, resize). The build
 * scope that declares the editor reads it (`Ui.inlineEditor`), so:
 *   - a rect written *after* the click (deferred case) re-describes the tree and the editor
 *     appears as soon as the field is laid out — never at (0, 0);
 *   - scrolling or resizing while editing re-places the editor on the field instead of leaving
 *     it behind.
 */
public class InlineAnchor {
    private var rect: Rect = Rect.zero()
    private let revision: State<Int64>
    /**
     * Set by [request] (a user opened the editor on a field) and consumed by the editor frame:
     * it marks the "just opened" edge, which resets the blur-commit latch. `update` never sets it,
     * so a scroll cannot look like a fresh open.
     */
    private var fresh: Bool = false

    public init(revision: State<Int64>) {
        this.revision = revision
    }

    /**
     * Records the field the user just clicked, in window-absolute coordinates. Zero or negative
     * extents are stored as given — [ready] reports them as unusable, and `Ui.inlineEditor` then
     * waits for the field's own layout instead of drawing a control at the origin.
     */
    public func request(rect: Rect): Unit {
        fresh = true
        store(rect)
    }

    /**
     * Per-frame refresh from the view's own layout/paint pass (scroll offset, resize, the field
     * moving because of an edit elsewhere). Same coordinate space as [request].
     */
    public func update(rect: Rect): Unit {
        store(rect)
    }

    /** Forgets the field (the editor closed). */
    public func clear(): Unit {
        fresh = false
        store(Rect.zero())
    }

    /** The rectangle recorded last, window-absolute. */
    public func current(): Rect {
        rect
    }

    /**
     * Whether the rect can position a control: both extents positive. Everything else (the zero
     * default, a degenerate 0×N box) is "not laid out yet" — the editor must not be drawn from it.
     */
    public func ready(): Bool {
        rect.w > 0.0 && rect.h > 0.0
    }

    /** Reads the revision: the build dependency that makes a rect change re-place the editor. */
    public func token(): Int64 {
        revision.value
    }

    /** Consumes the "the user opened this field" edge (see [fresh]). */
    func takeFresh(): Bool {
        let value = fresh
        fresh = false
        value
    }

    private func store(value: Rect): Unit {
        if (value.x == rect.x && value.y == rect.y && value.w == rect.w && value.h == rect.h) {
            return
        }
        rect = value
        revision.value = revision.value + 1
    }
}

/**
 * Returns this view's cross-frame anchor for one editor, creating it on first use.
 *
 * For views whose state shell is rebuilt every frame (OKR's `OkrUiState`, GTD's `GtdState`): the
 * anchor object itself is what has to be remembered. A view that already keeps one long-lived
 * state object (SOP's `SopViewState`, held by `remember<SopViewState>`) can construct the anchor
 * directly with `InlineAnchor(State<Int64>(0))` and save the lookup.
 *
 * Must be called during **build** (`remember` is a declarative-scope API). The key identifies the
 * editor (one per view, except GTD's date and scene boxes which get their own).
 */
public func inlineAnchor(key: String): InlineAnchor {
    remember<InlineAnchor>(key) {InlineAnchor(State<Int64>(0))}
}
