package textura.ui

import std.collection.ArrayList
import cui.*

/*
 * Modal — port of `.modal-overlay` / `.modal*` (src/ui/ui.css:450-537) plus the Web
 * component's behaviour (Modal.tsx): Esc closes, a click on the backdrop closes, and the
 * page underneath is blocked while the dialog is open.
 *
 * CUI has a `Modal` class, but it centres a 460vp panel with 22vp padding and its own
 * `panelRaised` surface, so it cannot express Design's geometry:
 *   overlay padding `10vh 24px 24px`, panel width 520, radius 14 (`--radius-lg`),
 *   `--shadow-2`, header `16px 24px`, body `24px`, footer `12px 24px` on `--surface-2`.
 * The port therefore registers its own `Overlay` (the same public mechanism CUI uses) and
 * keeps the CUI-compatible dismissal semantics.
 *
 * ## Why the content is built in the build phase (and how)
 *
 * CUI attributes keyboard focus stops to the declaring element *during build*
 * (`registerFocusable` is a no-op outside one). An earlier revision built the dialog body
 * from `layout`, where there is no active build store: the `TextField`s inside it never
 * entered the focus graph, so a click focused an id the next commit discarded — no caret,
 * no IME, no typing (docs/DEVICE-NOTES.md §16).
 *
 * `textura.ui` cannot open a nested build block itself (`buildChild` is `protected` inside
 * the CUI module), so the dialog is declared as two cooperating widgets at the call site:
 *
 *   `ModalHost`  zero-sized: measures the content, registers the overlay that paints the
 *                scrim and the panel surface, and handles Esc / backdrop / Tab.
 *   `Portal`     builds its body through the public CUI builder (so every control inside
 *                registers focus like any other control), lays that body out at the panel
 *                rect and draws it above the scrim.
 *
 * Both share a `ModalFrame` created per presentation. Overlay registration order is z-order
 * (CUI paints bottom-up and dispatches top-down), so the content sees input first and the
 * scrim overlay underneath only gets what the content declined — which is exactly the
 * "page never sees the event" contract.
 */

/** `.modal-overlay { background: rgba(26, 22, 18, 0.42) }` (ui.css:454): 0.42 * 255 = 107. */
private let OVERLAY_SCRIM: Color = Color.rgba(26, 22, 18, 107)
/** `.modal-overlay { padding: 10vh var(--space-5) var(--space-5) }` (ui.css:458). */
private let OVERLAY_TOP_RATIO: Float32 = 0.10
private let OVERLAY_SIDE_PADDING: Float32 = 24.0
/** `.modal { max-height: 80vh }` (ui.css:472). */
private let OVERLAY_MAX_HEIGHT_RATIO: Float32 = 0.80
/** `.modal-header { padding: var(--space-4) var(--space-5) }` (ui.css:481) = 16px 24px. */
let MODAL_HEADER_VPAD: Float32 = 16.0
/** `.modal-body { padding: var(--space-5) }` (ui.css:503) = 24px. */
let MODAL_BODY_PAD: Float32 = 24.0
/** `.modal-footer { padding: var(--space-3) var(--space-5) }` (ui.css:513) = 12px 24px. */
let MODAL_FOOTER_VPAD: Float32 = 12.0
/** Measurement probe height: large enough to read a section's natural height. */
private let UNBOUNDED_PROBE: Float32 = 100000.0

/**
 * One presentation of a dialog: the measured panel rect, the built content subtree and the
 * dismissal/focus protocol. Created once per frame the dialog is open; the widgets that use
 * it (`ModalHost`, the body `Portal`) are its siblings.
 */
public class ModalFrame {
    let tokens: ThemeTokens
    private let title: String
    private let panelWidth: Float32
    private let onDismiss: () -> Unit
    // Parts are captured so the panel can be sized to its content (CSS `max-height: 80vh` +
    // hug) before layout: header / body / footer are measured separately, exactly like the
    // three-row column of `.modal`.
    private var headerPart: ?Widget = None
    private var bodyPart: ?Widget = None
    private var footerPart: ?Widget = None
    private var columnPart: ?Widget = None
    private var panelRect = Rect.zero()

    public init(tokens: ThemeTokens, title: String, width: Float32, onDismiss: () -> Unit) {
        this.tokens = tokens
        this.title = title
        this.panelWidth = width
        this.onDismiss = onDismiss
    }

    /** Overlay owner of the scrim/panel layer. Stable across frames, so re-registration is in place. */
    public func owner(): String {
        if (title.isEmpty()) {
            "UiModal"
        } else {
            "UiModal:${title}"
        }
    }

    /** Overlay owner of the content layer (declared above the scrim). */
    public func contentOwner(): String {
        "${owner()}-content"
    }

    func attachHeader(widget: Widget): Unit {
        headerPart = Some(widget)
    }

    func attachBody(widget: Widget): Unit {
        bodyPart = Some(widget)
    }

    func attachFooter(widget: Widget): Unit {
        footerPart = Some(widget)
    }

    func attachColumn(widget: Widget): Unit {
        columnPart = Some(widget)
    }

    /**
     * Measures the content and computes the panel rect (CSS: centred horizontally, 10vh from
     * the top, `max-width: 100vw - 48`, `max-height: 80vh` with the body scrolling past it).
     * Idempotent: the scrim layer and the content portal both ask for it each frame.
     */
    public func resolve(ctx: UiContext): Rect {
        let viewportWidth = ctx.viewportWidth
        let viewportHeight = ctx.viewportHeight
        let width = min(panelWidth, max(0.0, viewportWidth - OVERLAY_SIDE_PADDING * 2.0))
        let maxHeight = max(0.0, viewportHeight * OVERLAY_MAX_HEIGHT_RATIO)
        let border = tokens.metrics.borderWidth
        let headerHeight = measurePart(ctx, headerPart, width)
        let footerHeight = measurePart(ctx, footerPart, width)
        let bodyNatural = measurePart(ctx, bodyPart, width)
        // One 1vp divider under the header; a second one above the footer when there is one.
        let chrome = headerHeight + border + (if (footerPart.isSome()) {
            border + footerHeight
        } else {
            0.0
        })
        let bodyHeight = min(bodyNatural, max(0.0, maxHeight - chrome))
        panelRect = Rect((viewportWidth - width) / 2.0, viewportHeight * OVERLAY_TOP_RATIO, width,
            chrome + bodyHeight)
        panelRect
    }

    /** `.modal-overlay` scrim + `.modal` surface, border and shadow. Content draws on top. */
    func paint(ctx: UiContext): Unit {
        if (panelRect.w <= 0.0 || panelRect.h <= 0.0) {
            return
        }
        ctx.renderer.fill(Rect(0.0, 0.0, ctx.viewportWidth, ctx.viewportHeight), OVERLAY_SCRIM)
        softShadow(ctx, panelRect, tokens.radius.lg, tokens.shadow2)
        fillRound(ctx, panelRect, tokens.radius.lg, tokens.color.surface)
        strokeRound(ctx, panelRect, tokens.radius.lg, tokens.metrics.borderWidth, tokens.color.border)
    }

    /**
     * Esc / backdrop / Tab. Only reached for events the content subtree declined (its overlay
     * is registered above this one), and always consumes: while a dialog is open the page
     * underneath must not react to anything.
     */
    func handleOverlay(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.KeyDown(Key.Escape, isRepeat) =>
                if (!isRepeat) {
                    onDismiss()
                }
            case UiEvent.KeyDown(Key.Tab, isRepeat) =>
                // Focus stays inside the dialog: Tab cycles the stops its body declared, in
                // declaration order, exactly like CUI's own `Modal` focus trap.
                if (!isRepeat) {
                    cycleContentFocus(ctx)
                }
            case UiEvent.MouseDown(button, x, y) =>
                // Modal.tsx: only a backdrop mousedown dismisses.
                if (isPrimaryPointerButton(button) && !panelRect.contains(x, y)) {
                    onDismiss()
                }
            case _ => ()
        }
        true
    }

    /** The control that should take focus when the dialog opens, for `FocusOnceView`. */
    public func contentFocusables(): Array<String> {
        match (columnPart) {
            case Some(tree) => tree.focusableIds()
            case None => Array<String>()
        }
    }

    private func cycleContentFocus(ctx: UiContext): Unit {
        let ids = plainFocusIds()
        if (ids.isEmpty()) {
            return
        }
        var current: Int64 = -1
        for (index in 0..ids.size) {
            if (ids[index] == ctx.focusId) {
                current = index
                break
            }
        }
        let step: Int64 = if (ctx.eventModifiers().shift) {
            -1
        } else {
            1
        }
        let count = ids.size
        let next = if (current < 0) {
            if (step > 0) {
                0
            } else {
                count - 1
            }
        } else {
            (((current + step) % count) + count) % count
        }
        ctx.focus(ids[next], viaKeyboard: true)
    }

    /**
     * The dialog's focus stops as plain control ids, in declaration order.
     *
     * `focusableIds()` reports two shapes for the same control: the id a control passes to
     * `ctx.focus`, and the owner-qualified key the committed graph stores (`"8:@Root[1];…;12:UiButton"`).
     * Comparing `ctx.focusId` against the qualified form never matches, so the owner prefix is
     * dropped and duplicates are collapsed before cycling.
     */
    private func plainFocusIds(): Array<String> {
        let result = ArrayList<String>()
        for (raw in contentFocusables()) {
            let key = plainFocusKey(raw)
            if (key.isEmpty()) {
                continue
            }
            var duplicate = false
            for (existing in result) {
                if (existing == key) {
                    duplicate = true
                }
            }
            if (!duplicate) {
                result.add(key)
            }
        }
        result.toArray()
    }

    private func plainFocusKey(raw: String): String {
        var cut: Int64 = -1
        var index: Int64 = 0
        for (byte in raw) {
            if (byte == UInt8(59)) {
                cut = index
            }
            index += 1
        }
        if (cut < 0 || cut + 1 >= raw.size) {
            return raw
        }
        raw[(cut + 1)..raw.size]
    }

    private func measurePart(ctx: UiContext, part: ?Widget, width: Float32): Float32 {
        match (part) {
            case Some(widget) => widget.measure(ctx, Size(width, UNBOUNDED_PROBE)).h
            case None => 0.0
        }
    }
}

/**
 * Declarative dialog chrome: dims and blocks the page and paints the panel. The content is a
 * sibling `Portal` (see `Ui.modal`) so its controls are declared during build.
 */
public class ModalHost <: Widget {
    private let frame: ModalFrame

    public init(frame: ModalFrame) {
        this.frame = frame
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size.zero()
    }

    public func layout(ctx: UiContext, _: Rect): Unit {
        let _ = frame.resolve(ctx)
        ctx.setOverlay(
            Overlay(handleEvent: {c, e => frame.handleOverlay(c, e)}, render: {c => frame.paint(c)},
                owner: frame.owner())
        )
    }

    public func draw(_: UiContext): Unit {
        // The overlay registered during layout paints the scrim and the panel.
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
