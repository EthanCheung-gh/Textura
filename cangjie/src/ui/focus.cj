package textura.ui

import cui.*

/*
 * One-shot focus requests for dialogs and editors.
 *
 * CUI only adopts a focus id that some control registered **during the build phase**; asking
 * for an id that was not registered this frame makes the focus graph drop it at the next
 * commit (no caret, no IME). `layout` is the only per-frame hook that receives a `UiContext`,
 * so the request is applied from there — through `FocusOnceView` — and retried for a couple of
 * frames because a target may be declared slightly later in the same subtree.
 *
 * The request lives in a caller-owned object (`FocusRequest`) instead of a CUI `State`: a
 * `State` keyed by control id would latch for the whole session (that is why
 * `TextField.autofocus()` could not focus the second time a dialog opened), while a plain
 * object can be armed again by whoever opens the editor, including after it closed.
 *
 * The request never fights the user: the first frame applies it unconditionally (the control
 * that opened the dialog is allowed to lose focus), later frames only retry while no control
 * owns focus, and any other owner ends the request.
 */
public class FocusRequest {
    private var pending: String = ""
    /** The control that held focus when the request was armed; restored by `release()`. */
    private var previous: String = ""
    private var attemptsLeft: Int64 = 0
    private var firstAttempt: Bool = false
    private var restoring: Bool = false
    private let attempts: Int64

    public init(attempts!: Int64 = 3) {
        this.attempts = attempts
    }

    /** Arms the request: the next layout pass focuses `id`, overriding the current focus once. */
    public func request(id: String): Unit {
        if (id.isEmpty()) {
            return
        }
        pending = id
        attemptsLeft = attempts
        firstAttempt = true
        restoring = false
    }

    /**
     * Hands focus back to the control that held it when the editor opened (nothing to do when
     * none did — the caller's own fallback then decides, e.g. the shell focuses the nav row).
     */
    public func release(): Unit {
        let target = previous
        previous = ""
        if (target.isEmpty()) {
            cancel()
            return
        }
        pending = target
        attemptsLeft = 1
        firstAttempt = true
        restoring = true
    }

    /** Drops a pending request (the editor closed before it landed). */
    public func cancel(): Unit {
        pending = ""
        attemptsLeft = 0
        firstAttempt = false
        restoring = false
    }

    /** Whether a request is still waiting to be applied. */
    public func isPending(): Bool {
        !pending.isEmpty()
    }

    /**
     * The control id the pending request points at (`""` when idle).
     *
     * Exposed for probes and tests: 「返回后焦点请求指向 `okr-edit-<id>`」这样的验收需要看到
     * 请求本身，而不是等它落地之后再去读 `focusId`（画布热点的 id 不在焦点图里，落地那一帧
     * 之后就会被清掉）。
     */
    public func pendingId(): String {
        pending
    }

    /**
     * Applies at most one attempt this frame. Stops as soon as the target owns focus; retries
     * only while nothing owns focus (the control may not be registered yet); gives up after
     * `attempts` frames so a control that never appears cannot keep stealing focus.
     */
    public func consume(ctx: UiContext): Unit {
        if (pending.isEmpty()) {
            return
        }
        if (ctx.focusId == pending) {
            pending = ""
            attemptsLeft = 0
            firstAttempt = false
            restoring = false
            return
        }
        if (!firstAttempt && (!ctx.focusId.isEmpty() || attemptsLeft <= 0)) {
            // Another control owns focus now (the user tabbed or clicked elsewhere), or the
            // target never appeared: the request is finished either way.
            pending = ""
            return
        }
        if (firstAttempt && !restoring) {
            previous = ctx.focusId
        }
        firstAttempt = false
        attemptsLeft -= 1
        ctx.focus(pending)
        ctx.requestFrame()
    }
}

/**
 * Zero-sized, non-interactive carrier for a caller-owned `FocusRequest`. Declared next to the
 * editor it belongs to (or once at a view root, so a request raised while no dialog is open —
 * the focus restore after closing — still lands).
 */
public class FocusOnceView <: Widget {
    private let request: FocusRequest

    public init(request: FocusRequest) {
        this.request = request
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size.zero()
    }

    public func layout(ctx: UiContext, _: Rect): Unit {
        request.consume(ctx)
    }

    public func draw(_: UiContext): Unit {}

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
