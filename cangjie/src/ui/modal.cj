package textura.ui

import cui.*
import cui.core.broadcastEvent

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
 * Height: `max-height: 80vh` in CSS means "hug the content, scroll the body past 80vh", so
 * header / body / footer are measured separately and the body gets an explicit height
 * (its scroll view only scrolls when the content really overflows).
 */

/** `.modal-overlay { background: rgba(26, 22, 18, 0.42) }` (ui.css:454): 0.42 * 255 = 107. */
private let OVERLAY_SCRIM: Color = Color.rgba(26, 22, 18, 107)
/** `.modal-overlay { padding: 10vh var(--space-5) var(--space-5) }` (ui.css:458). */
private let OVERLAY_TOP_RATIO: Float32 = 0.10
private let OVERLAY_SIDE_PADDING: Float32 = 24.0
/** `.modal { max-height: 80vh }` (ui.css:472). */
private let OVERLAY_MAX_HEIGHT_RATIO: Float32 = 0.80
/** `.modal-header { padding: var(--space-4) var(--space-5) }` (ui.css:481) = 16px 24px. */
private let MODAL_HEADER_VPAD: Float32 = 16.0
/** `.modal-body { padding: var(--space-5) }` (ui.css:503) = 24px. */
private let MODAL_BODY_PAD: Float32 = 24.0
/** `.modal-footer { padding: var(--space-3) var(--space-5) }` (ui.css:513) = 12px 24px. */
private let MODAL_FOOTER_VPAD: Float32 = 12.0
/** Measurement probe height: large enough to read a section's natural height. */
private let UNBOUNDED_PROBE: Float32 = 100000.0

/**
 * Declarative dialog. Renders nothing while `presented` is false; when open it registers a
 * full-viewport interactive overlay, dims the page, and lays the panel out at the CSS
 * geometry. Body content is built once per presentation, so ordinary `State`, focus and
 * event handling work inside the dialog.
 */
public class ModalHost <: Widget {
    private let owner: String
    private let tokens: ThemeTokens
    private let title: String
    private let description: String
    private let panelWidth: Float32
    private let onDismiss: () -> Unit
    private let footer: ?() -> Unit
    private let body: () -> Unit
    // Header / body / footer are built once and re-measured per frame, mirroring the CSS
    // three-row column; `column` is the assembled (and cached) dialog tree.
    private var headerPart: ?Widget = None
    private var bodyPart: ?Widget = None
    private var footerPart: ?Widget = None
    private var column: ?Widget = None
    private var builtWidth: Float32 = -1.0
    private var builtMaxHeight: Float32 = -1.0
    private var panelHeight: Float32 = 0.0
    private var panelRect = Rect.zero()

    public init(
        tokens: ThemeTokens,
        onDismiss: () -> Unit,
        title!: String = "",
        description!: String = "",
        width!: Float32 = 520.0,
        footer!: ?() -> Unit = None,
        body!: () -> Unit
    ) {
        this.owner = focusableControlIdentity("UiModal")
        this.tokens = tokens
        this.onDismiss = onDismiss
        this.title = title
        this.description = description
        this.panelWidth = width
        this.footer = footer
        this.body = body
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size.zero()
    }

    public func layout(ctx: UiContext, _: Rect): Unit {
        let viewportWidth = ctx.viewportWidth
        let viewportHeight = ctx.viewportHeight
        // .modal { max-width: calc(100vw - 48px); max-height: 80vh }
        let width = min(panelWidth, max(0.0, viewportWidth - OVERLAY_SIDE_PADDING * 2.0))
        let maxHeight = max(0.0, viewportHeight * OVERLAY_MAX_HEIGHT_RATIO)
        if (width != builtWidth || maxHeight != builtMaxHeight) {
            build(ctx, width, maxHeight)
            builtWidth = width
            builtMaxHeight = maxHeight
        }
        match (column) {
            case Some(tree) =>
                // `.modal-overlay { align-items: flex-start; justify-content: center;
                //  padding: 10vh 24px 24px }`
                panelRect = Rect((viewportWidth - width) / 2.0, viewportHeight * OVERLAY_TOP_RATIO, width, panelHeight)
                ctx.setOverlay(
                    Overlay(handleEvent: {c, e => handleOverlay(c, e)}, render: {c => paint(c)}, owner: owner)
                )
                tree.layout(ctx, panelRect)
            case None => ()
        }
    }

    public func draw(_: UiContext): Unit {
        // The overlay registered during layout paints the dialog above the tree.
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }

    /** Builds header/body/footer, then the assembled column, once per (width) change. */
    private func build(ctx: UiContext, width: Float32, maxHeight: Float32): Unit {
        let c = tokens.color
        let innerWidth = max(0.0, width - MODAL_BODY_PAD * 2.0)
        // .modal-header: padding 16px 24px, space-between, align-items flex-start
        let header = HStack(spacing: vp(tokens.space.s4)) {
            VStack(spacing: vp(2.0)) {
                if (!title.isEmpty()) {
                    // .modal-title { font-size: 15px; font-weight: 650 } (ui.css:492-495)
                    Label(title)
                        .fontSize(Length(TextSize.subheading, LengthUnit.Fp))
                        .fontWeight(FontWeight(650))
                        .foregroundColor(c.text)
                }
                if (!description.isEmpty()) {
                    Label(description)
                        .fontSize(Length(TextSize.controlSmall, LengthUnit.Fp))
                        .foregroundColor(c.textMuted)
                }
            }.hug().flex()
            // Modal.tsx renders a small ghost close button in the header.
            IconButtonView(tokens, IconGlyph.Close, onDismiss, variant: IconButtonVariant.Ghost,
                size: ControlSize.Sm, tooltip: "关闭")
        }
            .crossAxisAlignment(CrossAxisAlignment.Start)
            .hug()
            .padding(tokens.space.s5, MODAL_HEADER_VPAD, tokens.space.s5, MODAL_HEADER_VPAD)
        // .modal-body { padding: 24px }
        let bodyContent = VStack(spacing: vp(tokens.space.s3)) {
            body()
        }.hug().fillWidth().padding(MODAL_BODY_PAD)
        headerPart = Some(header)
        bodyPart = Some(bodyContent)
        let footerRow: ?Widget = match (footer) {
            case Some(footerBody) =>
                Some(
                    HStack(spacing: vp(tokens.space.s2)) {
                        Spacer()
                        footerBody()
                    }
                        // `.modal-footer { align-items: center; justify-content: flex-end }`
                        .crossAxisAlignment(CrossAxisAlignment.Center)
                        .hug()
                        .padding(tokens.space.s5, MODAL_FOOTER_VPAD, tokens.space.s5, MODAL_FOOTER_VPAD)
                        .background(c.surface2, corners: Corners.bottom(tokens.radius.lg))
                )
            case None => None
        }
        footerPart = footerRow
        let footerHeight: Float32 = match (footerRow) {
            case Some(row) => row.measure(ctx, Size(width, UNBOUNDED_PROBE)).h + tokens.metrics.borderWidth
            case None => 0.0
        }
        let headerHeight = header.measure(ctx, Size(width, UNBOUNDED_PROBE)).h
        let bodyHeight = bodyContent.measure(ctx, Size(innerWidth, UNBOUNDED_PROBE)).h
        // One 1vp divider under the header, plus the body budget.
        let chrome = headerHeight + tokens.metrics.borderWidth + footerHeight
        let budget = max(0.0, maxHeight - chrome)
        let finalBodyHeight = min(bodyHeight, budget)
        let tree = VStack(spacing: vp(0.0)) {
            emit(header)
            Divider().foregroundColor(c.border)
            ScrollView(key: "${owner}-body") {
                emit(bodyContent)
            }.height(finalBodyHeight)
            match (footerRow) {
                case Some(row) =>
                    Divider().foregroundColor(c.border)
                    emit(row)
                case None => ()
            }
        }
        panelHeight = chrome + finalBodyHeight
        column = Some(tree.width(width).height(panelHeight))
    }

    private func paint(ctx: UiContext): Unit {
        if (panelRect.w <= 0.0 || panelRect.h <= 0.0) {
            return
        }
        // .modal-overlay background
        ctx.renderer.fill(Rect(0.0, 0.0, ctx.viewportWidth, ctx.viewportHeight), OVERLAY_SCRIM)
        // .modal { background: surface; border: 1px solid border; radius: --radius-lg;
        //          box-shadow: --shadow-2 }
        softShadow(ctx, panelRect, tokens.radius.lg, tokens.shadow2)
        fillRound(ctx, panelRect, tokens.radius.lg, tokens.color.surface)
        strokeRound(ctx, panelRect, tokens.radius.lg, tokens.metrics.borderWidth, tokens.color.border)
        match (column) {
            case Some(tree) => tree.draw(ctx)
            case None => ()
        }
    }

    private func handleOverlay(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.KeyDown(Key.Escape, isRepeat) =>
                if (!isRepeat) {
                    onDismiss()
                }
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (!panelRect.contains(x, y)) {
                    // Modal.tsx: only a backdrop mousedown dismisses.
                    onDismiss()
                } else {
                    route(ctx, event)
                }
            case _ => route(ctx, event)
        }
        true // modal: the page underneath never sees the event
    }

    private func route(ctx: UiContext, event: UiEvent): Unit {
        match (column) {
            case Some(tree) => broadcastEvent(tree, ctx, event)
            case None => ()
        }
    }
}
