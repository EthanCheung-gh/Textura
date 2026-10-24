package textura.ui

import cui.*

/*
 * `Ui` — the public control kit used by the shell and the seven views.
 *
 * Why a namespace struct instead of free `Button` / `Badge` / `Modal` definitions:
 * CUI already exports classes with those names, and Cangjie treats `import cui.*` +
 * `import textura.ui.*` as two equally-ranked wildcard imports, so a second `Button`
 * makes every bare `Button(...)` call in a view an "ambiguous use" error (verified with
 * cjc 1.2.0). `Ui.button(...)` keeps the vocabulary and stays unambiguous.
 *
 * Every builder takes `theme` first: token lookups happen at build time (labels, borders,
 * dividers), and taking the theme explicitly keeps light and dark widgets composable in one
 * tree — which the kit gallery (`kit_demo.cj`) relies on.
 *
 * Token resolution: `theme` is a CUI `Theme`, which cannot carry a name, so `Ui` resolves the
 * matching `ThemeTokens` with `tokensOf(theme)`. That lookup is exact for `tokens.theme()`
 * round-trips and for the two shipped palettes; callers holding a recoloured theme must pass
 * the tokens themselves — either `tokensOf(theme, explicit: tk)` or the widget constructors
 * (`ButtonView(tokens, ...)` etc.), which take `ThemeTokens` as their first parameter.
 */
/** Prompt panel width: wide enough for a date, a metric label or a checklist entry. */
private let PROMPT_WIDTH: Float32 = 440.0
/** `.textarea` inside a prompt: two comfortable lines plus the 7vp padding. */
private let PROMPT_AREA_HEIGHT: Float32 = 92.0

public struct Ui {
    // ---------------------------------------------------------------- button / icon button

    /** `.btn` — primary/secondary/ghost/danger, sm/md, optional glyphs, block width. */
    public static func button(
        theme: Theme,
        label: String,
        onClick: () -> Unit,
        variant!: ButtonVariant = ButtonVariant.Secondary,
        size!: ControlSize = ControlSize.Md,
        iconLeft!: ?IconGlyph = None,
        iconRight!: ?IconGlyph = None,
        block!: Bool = false,
        enabled!: Bool = true
    ): Unit {
        ButtonView(tokensOf(theme), label, onClick, variant: variant, size: size, iconLeft: iconLeft,
            iconRight: iconRight, block: block, enabled: enabled)
    }

    /** `.icon-btn` — 26/34 square icon button with an optional tooltip. */
    public static func iconButton(
        theme: Theme,
        glyph: IconGlyph,
        onClick: () -> Unit,
        variant!: IconButtonVariant = IconButtonVariant.Ghost,
        size!: ControlSize = ControlSize.Md,
        tooltip!: ?String = None,
        enabled!: Bool = true
    ): Unit {
        IconButtonView(tokensOf(theme), glyph, onClick, variant: variant, size: size, tooltip: tooltip, enabled: enabled)
    }

    // ---------------------------------------------------------------------------- display

    /** `.badge` — tone pill with an optional status dot. */
    public static func badge(
        theme: Theme,
        text: String,
        tone!: BadgeTone = BadgeTone.Neutral,
        dot!: Bool = false
    ): Unit {
        BadgeView(tokensOf(theme), text, tone: tone, dot: dot)
    }

    /** `.progress` — pill track + optional right-aligned percentage. */
    public static func progress(
        theme: Theme,
        value: Float32,
        tone!: ProgressTone = ProgressTone.Accent,
        size!: ControlSize = ControlSize.Md,
        showLabel!: Bool = false
    ): Unit {
        ProgressView(tokensOf(theme), value, tone: tone, size: size, showLabel: showLabel)
    }

    /** `.segmented` — tray + pill segments; `selected` is the index of the active item. */
    public static func segmented(
        theme: Theme,
        items: Array<String>,
        selected: Bindable<Int64>,
        size!: ControlSize = ControlSize.Md
    ): Unit {
        SegmentedView(tokensOf(theme), toSegmentedItems(items), selected, size: size)
    }

    /** `.segmented` with leading glyphs per item (Segmented.tsx `option.icon`). */
    public static func segmentedWithGlyphs(
        theme: Theme,
        items: Array<SegmentedItem>,
        selected: Bindable<Int64>,
        size!: ControlSize = ControlSize.Md
    ): Unit {
        SegmentedView(tokensOf(theme), items, selected, size: size)
    }

    /** `.empty-state` — centred icon tile, title, description and optional action. */
    public static func emptyState(
        theme: Theme,
        title: String,
        description!: String = "",
        glyph!: ?IconGlyph = None,
        compact!: Bool = false,
        action!: ?() -> Unit = None
    ): Unit {
        let tokens = tokensOf(theme)
        let c = tokens.color
        // .empty-state { gap: 8px; padding: 32px; color: text-muted; align-items: center }
        // .empty-state--compact { padding: 16px }
        let padding = if (compact) {
            tokens.space.s4
        } else {
            tokens.space.s6
        }
        VStack(spacing: vp(tokens.space.s2)) {
            match (glyph) {
                case Some(value) => emptyStateIcon(tokens, value)
                case None => ()
            }
            // .empty-state-title { font-size: 14px; font-weight: 600; color: text }
            Label(title)
                .fontSize(Length(TextSize.body, LengthUnit.Fp))
                .fontWeight(FontWeight(600))
                .foregroundColor(c.text)
                .textAlign(TextAlign.Center)
            if (!description.isEmpty()) {
                // .empty-state-description { 12.5px; max-width: 42ch; line-height: 1.6 }
                Label(description)
                    .fontSize(Length(TextSize.controlSmall, LengthUnit.Fp))
                    .foregroundColor(c.textMuted)
                    .textAlign(TextAlign.Center)
                    .wrap()
                    .maxWidth(420.0)
            }
            match (action) {
                case Some(actionBody) => emptyStateAction(tokens, actionBody)
                case None => ()
            }
        }
            // `.empty-state { align-items: center; text-align: center }` (ui.css:361-370)
            .crossAxisAlignment(CrossAxisAlignment.Center).hug().padding(padding).fillWidth()
    }

    /** `.empty-state-icon`: 44x44 tile, radius-lg, `surface-2`, 1px border, `text-faint`. */
    private static func emptyStateIcon(tokens: ThemeTokens, glyph: IconGlyph): Unit {
        IconView(glyph, side: 18.0, color: tokens.color.textFaint)
            .width(44.0)
            .height(44.0)
            .background(tokens.color.surface2, tokens.radius.lg)
            .border(tokens.color.border, width: tokens.metrics.borderWidth, radius: tokens.radius.lg)
            .padding(0.0, 0.0, 0.0, tokens.space.s1)
    }

    /** `.empty-state-action { margin-top: var(--space-2) }`. */
    private static func emptyStateAction(tokens: ThemeTokens, action: () -> Unit): Unit {
        HStack(spacing: vp(tokens.space.s2)) {
            action()
        }.hug().padding(0.0, tokens.space.s2, 0.0, 0.0)
    }

    /** `1px` hairline in `--border`; `Divider` in CUI is the same 1vp rule. */
    public static func divider(theme: Theme, axis!: Axis = Axis.Horizontal, color!: ?Color = None): Unit {
        let tokens = tokensOf(theme)
        Divider(axis: axis, color: match (color) {
            case Some(value) => value
            case None => tokens.color.border
        })
    }

    /** `icons.tsx` `<Icon>` — non-interactive glyph, 18vp by default. */
    public static func icon(theme: Theme, glyph: IconGlyph, side!: Float32 = 18.0, color!: ?Color = None): Unit {
        let tokens = tokensOf(theme)
        IconView(glyph, side: side, color: match (color) {
            case Some(value) => value
            case None => tokens.color.text
        })
    }

    /** `Tooltip(text:)` wrapper — nothing visible until the pointer rests on the child. */
    public static func tooltip(theme: Theme, text: String, body!: () -> Unit): Unit {
        let _ = theme
        Tooltip(text: text) {
            body()
        }
    }

    // ---------------------------------------------------------------------------- inputs

    /**
     * `.field` — 6px stack of label / control / hint-or-error (ui.css:161-240).
     * Pass the control as the trailing closure, e.g. `Ui.field(theme, label: "标题") { ... }`.
     */
    public static func field(
        theme: Theme,
        label!: String = "",
        hint!: String = "",
        error!: String = "",
        required!: Bool = false,
        body!: () -> Unit
    ): Unit {
        let tokens = tokensOf(theme)
        let c = tokens.color
        VStack(spacing: vp(6.0)) {
            if (!label.isEmpty()) {
                // .field-label { 12px; 600; text-muted; gap: 2px } + .field-required { accent-ink }
                HStack(spacing: vp(2.0)) {
                    Label(label)
                        .fontSize(Length(TextSize.label, LengthUnit.Fp))
                        .fontWeight(FontWeight(600))
                        .foregroundColor(c.textMuted)
                    if (required) {
                        Label("*").fontSize(Length(TextSize.label, LengthUnit.Fp)).foregroundColor(c.accentInk)
                    }
                }.hug()
            }
            body()
            if (!error.isEmpty()) {
                // .field-error { 11.5px; color: danger }
                Label(error).fontSize(Length(TextSize.caption, LengthUnit.Fp)).foregroundColor(c.danger)
            } else if (!hint.isEmpty()) {
                // .field-hint { 11.5px; color: text-faint }
                Label(hint).fontSize(Length(TextSize.caption, LengthUnit.Fp)).foregroundColor(c.textFaint)
            }
        }.hug().fillWidth()
    }

    /**
     * `.input` — single-line editor: `min-height: 34px; padding: 7px 10px; radius 8;
     * 1px border; background: surface; font-size: 13.5px`, focus swaps the border to
     * `--accent` and adds the 3px `--accent-soft` halo (`ui.css:181-210`).
     */
    public static func textInput(
        theme: Theme,
        text: Bindable<String>,
        key!: String = "",
        placeholder!: String = "",
        enabled!: Bool = true,
        invalid!: Bool = false
    ): Unit {
        let tokens = tokensOf(theme)
        let field = TextField(text, key: Ui.optionalKey(key), editable: enabled)
        field.style(Ui.inputStyle(tokens, invalid))
        field.placeholder(placeholder)
        field.height(34.0)
    }

    /**
     * `.textarea` — same surface as `.input`, `min-height: 76px`, `line-height: 1.55`
     * (ui.css:212-216).
     */
    public static func textArea(
        theme: Theme,
        text: Bindable<String>,
        key!: String = "",
        placeholder!: String = "",
        height!: Float32 = 76.0,
        enabled!: Bool = true
    ): Unit {
        let tokens = tokensOf(theme)
        let area = TextArea(text, key: optionalKey(key), editable: enabled)
        area.style(Ui.inputStyle(tokens, false))
        area.height(height)
        if (!placeholder.isEmpty()) {
            area.placeholder(placeholder)
        }
    }

    // --------------------------------------------------------------------------- overlay

    /**
     * `.modal` — Esc or a backdrop press dismisses; the page underneath is blocked while open.
     * `footer` receives the footer row (right-aligned, `--surface-2` strip).
     *
     * `body` runs during **build** (inside a `Portal`), not during layout: only then do the
     * `TextField`s it declares register their focus ids, which is what makes a click put a caret
     * in them (see `modal.cj` and docs/DEVICE-NOTES.md §16). Pass `focus` — a caller-owned
     * `FocusRequest` — plus `initialFocus` to put the caret into one control when the dialog opens.
     */
    public static func modal(
        theme: Theme,
        presented: Bindable<Bool>,
        onDismiss: () -> Unit,
        title!: String = "",
        description!: String = "",
        width!: Float32 = 520.0,
        footer!: ?() -> Unit = None,
        focus!: ?FocusRequest = None,
        initialFocus!: String = "",
        body!: () -> Unit
    ): Unit {
        if (!presented.value) {
            return
        }
        let tokens = tokensOf(theme)
        let c = tokens.color
        let frame = ModalFrame(tokens, title, width, onDismiss)
        // Chrome layer: scrim + panel surface + Esc/backdrop/Tab, registered *below* the content.
        ModalHost(frame)
        // Content layer: built here, in the build phase, then laid out at the panel rect.
        Portal(frame.contentOwner(), true, {ctx => frame.resolve(ctx)}, blocksInput: false) {
            let column = VStack(spacing: vp(0.0)) {
                // .modal-header: padding 16px 24px, space-between, align-items flex-start
                frame.attachHeader(
                    HStack(spacing: vp(tokens.space.s4)) {
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
                        .padding(tokens.space.s5, MODAL_HEADER_VPAD, tokens.space.s5, MODAL_HEADER_VPAD))
                Divider().foregroundColor(c.border)
                // The body absorbs the leftover height the frame assigned (flex), and scrolls
                // once its content is taller than the 80vh budget.
                ScrollView(key: "${frame.owner()}-body") {
                    frame.attachBody(VStack(spacing: vp(tokens.space.s3)) {
                        body()
                        match (focus) {
                            case Some(request) => FocusOnceView(request)
                            case None => ()
                        }
                    }.hug().fillWidth().padding(MODAL_BODY_PAD))
                }.flex()
                match (footer) {
                    case Some(footerBody) =>
                        Divider().foregroundColor(c.border)
                        frame.attachFooter(
                            HStack(spacing: vp(tokens.space.s2)) {
                                Spacer()
                                footerBody()
                            }
                                // `.modal-footer { align-items: center; justify-content: flex-end }`
                                .crossAxisAlignment(CrossAxisAlignment.Center)
                                .hug()
                                .padding(tokens.space.s5, MODAL_FOOTER_VPAD, tokens.space.s5, MODAL_FOOTER_VPAD)
                                .background(c.surface2, corners: Corners.bottom(tokens.radius.lg)))
                    case None => ()
                }
            }
            frame.attachColumn(column)
        }
    }

    /**
     * The shared "edit one field" overlay: a small modal with a single-line or multi-line
     * editor, Enter to save (single line), Esc to cancel, an optional validation error and a
     * caller-owned draft `State`.
     *
     * Canvas-painted views (SOP, OKR, GTD rows) cannot host an inline `TextField`: they lay
     * their content out during `layout`, where CUI registers no focus stop. Editing through
     * this prompt keeps the canvas untouched and gives the field a real, focusable build-time
     * control (docs/DEVICE-NOTES.md §16).
     */
    public static func prompt(
        theme: Theme,
        text: State<String>,
        presented: Bindable<Bool>,
        onDismiss: () -> Unit,
        title!: String,
        key!: String,
        label!: String = "",
        placeholder!: String = "",
        hint!: String = "",
        error!: String = "",
        multiline!: Bool = false,
        confirmLabel!: String = "保存",
        cancelLabel!: String = "取消",
        focus!: ?FocusRequest = None,
        onSave!: (String) -> Unit
    ): Unit {
        if (!presented.value) {
            return
        }
        let tokens = tokensOf(theme)
        let submit: () -> Unit = {=> onSave(text.value)}
        modal(
            theme,
            presented,
            onDismiss,
            title: title,
            width: PROMPT_WIDTH,
            focus: focus,
            initialFocus: key,
            footer: {
                =>
                    button(theme, cancelLabel, onDismiss, variant: ButtonVariant.Ghost, size: ControlSize.Sm)
                    button(theme, confirmLabel, submit, variant: ButtonVariant.Primary, size: ControlSize.Sm)
            },
            body: {
                => VStack(spacing: vp(tokens.space.s3)) {
                    field(theme, label: label, hint: hint, error: error) {
                        if (multiline) {
                            // `TextArea` owns Enter (it inserts a newline, like the Web
                            // `<textarea>` it ports), so the save chord is Ctrl/Cmd+Enter.
                            // `EventHandler` runs before its child, which is what lets the
                            // chord be claimed without patching CUI's TextArea.
                            EventHandler(onEvent: {
                                ctx, event => match (event) {
                                    case UiEvent.KeyDown(Key.Enter, isRepeat) where !isRepeat && ctx
                                        .eventModifiers()
                                        .command =>
                                        submit()
                                        true
                                    case _ => false
                                }
                            }) {
                                let area = TextArea(text, key: optionalKey(key))
                                area.style(inputStyle(tokens, false))
                                area.height(PROMPT_AREA_HEIGHT)
                                if (!placeholder.isEmpty()) {
                                    area.placeholder(placeholder)
                                }
                            }
                        } else {
                            let editor = TextField(text, key: optionalKey(key))
                            editor.style(inputStyle(tokens, false))
                            editor.placeholder(placeholder)
                            // Enter saves; the field consumes the key after IME composition commits.
                            editor.onSubmit {_ => submit()}
                            // `textStyle`/`height` are *widget modifiers*: each one emits a wrapper
                            // around the widget it is called on and replaces that widget in the
                            // parent's child list. Two separate statements on the same `editor`
                            // therefore build two wrappers around the same field, the second one
                            // lands as a **second child** (a visible duplicate under the first), so
                            // they must be chained on the value the previous call returned.
                            editor.textStyle(TextStyle(fontSize: fp(13.5))).height(34.0)
                        }
                    }
                }.hug().fillWidth()
            }
        )
    }

    // Prompt geometry lives at file scope (Cangjie has no private struct statics).

    /**
     * Edits one field **in place**: a real `TextField`/`TextArea` built during build, positioned at
     * `rect` by a `Portal`, so focus, caret and the IME anchor behave like any other control while
     * the page keeps its exact painted layout underneath (docs/DEVICE-NOTES.md §20).
     *
     * `rect` is the field rectangle the view recorded while laying its canvas out; `draft` is the
     * caller's `State<String>` (the editor writes into it, and a commit submits `draft.value`).
     * Enter commits, Ctrl/Cmd+Enter commits a multi-line field, Esc cancels, a press outside
     * commits, and focus leaving the editor commits. A commit the caller refuses (validation: it
     * keeps the editor open and passes `error`) is shown as one small danger-coloured line under
     * the field — no panel, no scrim, no shadow, same size as the field itself.
     *
     * This is the replacement for `prompt` on text fields; `prompt` stays for confirmations and
     * dangerous actions, where a modal really is the right shape.
     */
    public static func inlineEditor(
        theme: Theme,
        draft: State<String>,
        rect: Rect,
        open: Bool,
        key!: String,
        multiline!: Bool = false,
        placeholder!: String = "",
        error!: String = "",
        focus!: ?FocusRequest = None,
        onCommit!: (String) -> Unit,
        onCancel!: () -> Unit
    ): Unit {
        if (!open) {
            return
        }
        let tokens = tokensOf(theme)
        let frame = InlineEditFrame(tokens, key, key, rect, multiline, draft, onCommit, onCancel)
        let submit: () -> Unit = {=> onCommit(draft.value)}
        // Dismissal layer first: it is registered below the content, so the field sees its own
        // keys and presses and only what it declines (Esc, an outside press) reaches this layer.
        InlineEditorHost(frame, error)
        // Content layer: declared during build through `Portal`, which is what registers the
        // field's focus stop (a control built from layout cannot take focus at all).
        //
        // The portal body is the control itself. Two things must not come back here:
        //   - a `VStack` wrapper — it reported a content height ~76 larger than the field and
        //     centred the field inside it, so the editor was painted 38px below the rectangle;
        //   - two modifier statements on the same `editor` — `textStyle`/`height` are widget
        //     modifiers that each emit a wrapper *replacing* the widget in the parent's child list,
        //     so `editor.textStyle(...); editor.height(...)` emitted the field twice and the second
        //     copy was laid out right under the first: the "second identical box below the field"
        //     the user reported. Chained on the returned value they stay one child.
        // `inline_editor_test.cj` pins the geometry of every field (`bounds == rect`).
        Portal(frame.contentOwner(), true, {ctx => frame.resolve(ctx)}, blocksInput: false) {
            let height = frame.fieldHeight()
            if (multiline) {
                // `TextArea` owns Enter (it inserts a newline, like the Web `<textarea>`), so the
                // commit chord is Ctrl/Cmd+Enter; `EventHandler` runs before its child, which is
                // what lets the chord be claimed without patching CUI's TextArea.
                EventHandler(onEvent: {
                    ctx, event => match (event) {
                        case UiEvent.KeyDown(Key.Enter, isRepeat) where !isRepeat && ctx.eventModifiers().command =>
                            submit()
                            true
                        case _ => false
                    }
                }) {
                    // `style`/`placeholder` are `TextArea` setters (they return the same widget and
                    // emit nothing), `height` is the only modifier here — one wrapper, one child.
                    let area = TextArea(draft, key: optionalKey(key))
                    area.style(inputStyle(tokens, !error.isEmpty()))
                    area.height(height)
                    if (!placeholder.isEmpty()) {
                        area.placeholder(placeholder)
                    }
                }
            } else {
                let editor = TextField(draft, key: optionalKey(key))
                editor.style(inputStyle(tokens, !error.isEmpty()))
                editor.placeholder(placeholder)
                // Enter commits; the field consumes the key after IME composition commits.
                editor.onSubmit {_ => submit()}
                editor.textStyle(TextStyle(fontSize: fp(13.5))).height(height)
            }
        }
        // The focus carrier is a *sibling* of the `Portal`, not a child of it: a carrier declared
        // inside the portal body is only laid out when the portal places its subtree, and `Portal`
        // swallows the space, so keeping it out here is what makes "the editor takes focus on the
        // frame it opens" independent of the portal's detached layout. Same placement as
        // `prompt_test.cj` and `src/views/sop/sop.cj` (view root).
        //
        // The request itself is the caller's: whoever opens the editor arms it with the field key
        // (`state.promptFocus.request(SOP_PROMPT_INPUT)`), exactly like `Ui.prompt`. Nothing here
        // re-arms it, because a request that re-armed every frame would pull the caret back after
        // the user Tabs away (`promptTabDoesNotSnapBackToTheEditor`).
        match (focus) {
            case Some(request) => FocusOnceView(request)
            case None => ()
        }
    }

    // --------------------------------------------------------------------------- internal

    private static func toSegmentedItems(items: Array<String>): Array<SegmentedItem> {
        var result = Array<SegmentedItem>(items.size) {index => SegmentedItem(items[index])}
        result
    }

    private static func optionalKey(key: String): ?String {
        if (key.isEmpty()) {
            None
        } else {
            Some(key)
        }
    }

    private static func inputStyle(tokens: ThemeTokens, invalid: Bool): TextInputStyle {
        let c = tokens.color
        let restBorder = if (invalid) {
            c.danger
        } else {
            c.border
        }
        TextInputStyle(
            padding: LengthInsets(Length(10.0, LengthUnit.Vp), Length(7.0, LengthUnit.Vp)),
            textColor: c.text,
            placeholderColor: c.textFaint,
            cursorColor: c.accent,
            surface: SurfaceStyle(c.surface, border: restBorder, radius: tokens.radius.md,
                borderWidth: tokens.metrics.borderWidth),
            focusedSurface: SurfaceStyle(c.surface, border: c.accent, radius: tokens.radius.md,
                borderWidth: tokens.metrics.borderWidth)
        )
    }
}

/** Bootstrap-era probe kept for the parity gate (`src/shell/gate.cj`). */
public func tokenProbe(label: String): Unit {
    Panel {
        HStack(spacing: 8.vp) {
            Label(label).bold()
            Spacer()
            Label("ui tokens").muted()
        }
    }.fillWidth()
}

/*
 * `true` when a pointer button should be treated as the primary (left) button.
 *
 * Every pointer handler in this tree is written as `MouseDown(MouseButton.Left, …)`, which is what
 * the desktop SDL backend sends. A pointer backend that cannot name the button — touch-driven
 * pointer emulation, the HarmonyOS port under a finger — delivers `MouseButton.RawCode(code)` with
 * code 0 (the SDL "unknown" value) or 1 (the real left-button code) instead, so the pattern never
 * matches and presses land nowhere while hover and scrolling keep working.
 *
 * `RawCode(0)` is accepted deliberately: it is SDL's "no button information" value, and on a
 * touch-first device a press that reached the widget tree at all is a primary press. `RawCode(1)`
 * is the real button number. Anything else (2 = middle, 3 = right, 4/5 = wheel axes) stays
 * unhandled, exactly as before. The probe records each aliased press (`docs/DEVICE-NOTES.md` §1).
 */
public func isPrimaryPointerButton(button: MouseButton): Bool {
    match (button) {
        case MouseButton.Left => true
        case MouseButton.RawCode(code) => code == 0 || code == 1
        case _ => false
    }
}
