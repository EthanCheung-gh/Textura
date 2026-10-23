package textura.shell

import std.collection.*
import cui.*
import textura.core.data.*
import textura.ui.*

/*
 * `src/modules/appshell/QuickCapture.tsx` + `.capture*` (appshell.css:156-317).
 *
 * Modal 560px wide, title "收集到 GTD 收件箱". The body is a 12px stack: label, 15px input,
 * a live parse-preview chip row, the syntax hint paragraph, and the session list of what
 * this dialog already captured (with undo). Enter keeps the dialog open, ⌘/Ctrl+Enter
 * collects and closes; Esc closes (ModalHost).
 */

/** `.capture-chip`: padding 2/8, radius 999, 11.5px, tone colouring by data-tone. */
class CaptureChipView <: Widget {
    private let tokens: ThemeTokens
    private let label: String
    private let glyph: ?IconGlyph
    private let tone: String
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, label: String, glyph!: ?IconGlyph = None, tone!: String = "") {
        this.tokens = tokens
        this.label = label
        this.glyph = glyph
        this.tone = tone
        emit(this)
    }

    private func colors(): (Color, Color, Color) {
        let c = tokens.color
        match (tone) {
            case "accent" => (c.accentSoft, tint(c.accent, 30.0), c.accent)
            case "info" => (tint(c.info, 10.0), tint(c.info, 30.0), c.info)
            case "warn" => (tint(c.warn, 12.0), tint(c.warn, 32.0), c.warn)
            case "ok" => (tint(c.ok, 10.0), tint(c.ok, 30.0), c.ok)
            case _ => (c.surface2, c.border, c.textMuted)
        }
    }

    public func measure(ctx: UiContext, _: Size): Size {
        let fontSize = fpSize(ctx, 11.5)
        let iconPart: Float32 = match (glyph) {
            case Some(_) => 11.0 + 4.0
            case None => 0.0
        }
        Size(iconPart + textWidth(ctx, label, fontSize, 400) + 16.0 + CHROME_BORDER * 2.0,
            11.5f32 * 1.6f32 + 4.0f32 + CHROME_BORDER * 2.0f32)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func isFlexible(): Bool {
        false
    }

    public func draw(ctx: UiContext): Unit {
        let (bg, border, fg) = colors()
        fillRound(ctx, frame, 999.0, bg)
        strokeRound(ctx, frame, 999.0, CHROME_BORDER, border)
        let fontSize = fpSize(ctx, 11.5)
        var x = frame.x + 8.0
        match (glyph) {
            case Some(value) =>
                paintSpec(ctx, value, Rect(x, frame.centerY() - 5.5, 11.0, 11.0), fg)
                x += 11.0 + 4.0
            case None => ()
        }
        textLeading(ctx, label, x, frame.centerY() + 0.4, fg, fontSize, 400)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

public func captureEnergyLabel(energy: Energy): String {
    match (energy) {
        case Energy.High => "高能"
        case Energy.Medium => "中能"
        case Energy.Low => "低能"
    }
}

func monoTextWidth(ctx: UiContext, text: String, sizePx: Float32): Float32 {
    ctx.textWidth(text, pointSize: sizePx, style: FontStyle(weight: cssWeight(400)), font: fontMono())
}

/** One `本次会话已收集` row: title flex + right-aligned meta chips. */
class CaptureSessionRowView <: Widget {
    private let tokens: ThemeTokens
    private let entry: CaptureEntry
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, entry: CaptureEntry) {
        this.tokens = tokens
        this.entry = entry
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(max(available.w, 0.0), 5.0 * 2.0 + lineBox(12.5))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        fillRound(ctx, frame, tokens.radius.sm, c.surface2)
        let centerY = frame.centerY()
        var right = frame.right() - 8.0
        let metaSize = fpSize(ctx, 10.5)
        if (entry.date.isSome()) {
            let text = formatDateKey(entry.date, pattern: "MM/dd")
            textTrailing(ctx, text, right, centerY, c.textFaint, metaSize, 400)
            right -= textWidth(ctx, text, metaSize, 400) + 8.0
        }
        if (entry.energy.isSome()) {
            let text = captureEnergyLabel(entry.energy.getOrThrow())
            textTrailing(ctx, text, right, centerY, c.textFaint, metaSize, 400)
            right -= textWidth(ctx, text, metaSize, 400) + 8.0
        }
        match (entry.context) {
            case Some(value) =>
                let text = "@${value}"
                textTrailing(ctx, text, right, centerY, c.textFaint, metaSize, 400)
                right -= textWidth(ctx, text, metaSize, 400) + 8.0
            case None => ()
        }
        if (!entry.tags.isEmpty()) {
            let parts = ArrayList<String>()
            for (tag in entry.tags) {
                parts.add("#${tag}")
            }
            let text = String.join(parts.toArray(), delimiter: " ")
            textTrailing(ctx, text, right, centerY, c.textFaint, metaSize, 400)
            right -= textWidth(ctx, text, metaSize, 400) + 8.0
        }
        textLeading(ctx, entry.title, frame.x + 8.0, centerY, c.text, fpSize(ctx, 12.5), 400)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/**
 * `.capture-hints` — an inline paragraph mixing `<code>` chips and 11.5px faint text.
 * Runs are laid out greedily at 21.85px (11.5 × 1.9) line boxes.
 */
class CaptureHintsView <: Widget {
    private let tokens: ThemeTokens
    private let runs: Array<(String, Bool)>
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, runs: Array<(String, Bool)>) {
        this.tokens = tokens
        this.runs = runs
        emit(this)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        Size(max(available.w, 0.0), Float32(pieces(ctx, max(available.w, 0.0f32)).lines) * lineBox(11.5f32) * 1.9f32 / 1.5f32)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        let fontSize = fpSize(ctx, 11.5)
        let line = lineBox(11.5f32) * 1.9f32 / 1.5f32
        let laid = pieces(ctx, frame.w)
        for (piece in laid.placed) {
            let centerY = frame.y + line * Float32(piece.line) + line / 2.0
            if (piece.code) {
                let monoSize = fpSize(ctx, 11.0)
                let width = monoTextWidth(ctx, piece.text, monoSize) + 8.0 + CHROME_BORDER * 2.0
                let height = lineBox(11.0) + 2.0 + CHROME_BORDER * 2.0
                let rect = Rect(piece.x, centerY - height / 2.0, width, height)
                fillRound(ctx, rect, tokens.radius.sm, c.surface2)
                strokeRound(ctx, rect, tokens.radius.sm, CHROME_BORDER, c.border)
                textCentered(ctx, piece.text, rect, c.textMuted, monoSize, 400, family: fontMono())
            } else {
                textLeading(ctx, piece.text, piece.x, centerY, c.textFaint, fontSize, 400)
            }
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }

    private func pieces(ctx: UiContext, width: Float32): HintLayout {
        let fontSize = fpSize(ctx, 11.5)
        let monoSize = fpSize(ctx, 11.0)
        let placed = ArrayList<HintPiece>()
        var x: Float32 = 0.0
        var line: Int64 = 0
        for ((text, code) in runs) {
            let pieceWidth = if (code) {
                monoTextWidth(ctx, text, monoSize) + 8.0 + CHROME_BORDER * 2.0
            } else {
                textWidth(ctx, text, fontSize, 400)
            }
            if (code && x + pieceWidth > width && x > 0.0) {
                x = 0.0
                line += 1
            }
            placed.add(HintPiece(text, code, x, line))
            x += pieceWidth + (if (code) {
                2.0
            } else {
                0.0
            })
        }
        HintLayout(placed.toArray(), line + 1)
    }
}

class HintPiece {
    let text: String
    let code: Bool
    let x: Float32
    let line: Int64

    init(text: String, code: Bool, x: Float32, line: Int64) {
        this.text = text
        this.code = code
        this.x = x
        this.line = line
    }
}

class HintLayout {
    let placed: Array<HintPiece>
    let lines: Int64

    init(placed: Array<HintPiece>, lines: Int64) {
        this.placed = placed
        this.lines = lines
    }
}

func captureHintRuns(): Array<(String, Bool)> {
    let runs: Array<(String, Bool)> = [
        ("#标签", true),
        (" 打标签 · ", false),
        ("@场景", true),
        (" 采上下文 · ", false),
        ("!高能", true),
        (" / ", false),
        ("!低能", true),
        (" 标能量 · ", false),
        ("/今天", true),
        (" ", false),
        ("/明天", true),
        (" ", false),
        ("/本周", true),
        (" 设截止日期。多个标签用空格分隔。", false)
    ]
    runs
}

/** `.capture-input` 的控件 id：`ShellHost.openCapture/closeCapture` 也用它请求焦点。 */
let CAPTURE_INPUT_ID: String = "capture-input";

/** `.capture-input { font-size: 15px; padding: 10px 12px }`. */
func captureInputStyle(tokens: ThemeTokens): TextInputStyle {
    let c = tokens.color
    TextInputStyle(
        lineHeight: vp(22.5),
        padding: LengthInsets(Length(12.0, LengthUnit.Vp), Length(10.0, LengthUnit.Vp)),
        textColor: c.text,
        placeholderColor: c.textFaint,
        cursorColor: c.accent,
        surface: SurfaceStyle(c.surface, border: c.border, radius: tokens.radius.md,
            borderWidth: tokens.metrics.borderWidth),
        focusedSurface: SurfaceStyle(c.surface, border: c.accent, radius: tokens.radius.md,
            borderWidth: tokens.metrics.borderWidth)
    )
}

/**
 * QuickCapture dialog. `onCollect(raw, closeAfter)` owns the store writes; `onUndo`
 * removes the last captured item from both the workspace and the session list.
 */
public func buildQuickCapture(
    theme: Theme,
    open: Bool,
    text: State<String>,
    session: ArrayList<CaptureEntry>,
    today: String,
    onClose: () -> Unit,
    onCollect: (String, Bool) -> Unit,
    onUndo: () -> Unit
): Unit {
    let tokens = tokensOf(theme)
    let c = tokens.color
    let presented = State<Bool>(open)
    let parsed = parseCapture(text.value, today)
    let hasPreview = !parsed.tags.isEmpty() || parsed.context.isSome() || parsed.energy.isSome() || parsed.date.isSome()
    let sessionSnapshot = session.toArray()
    let sessionSuffix = if (sessionSnapshot.isEmpty()) {
        ""
    } else {
        "（保存在收件箱）"
    }
    /*
     * Build the input here, in the build phase, and only `emit` it inside the modal body.
     *
     * `ModalHost` invokes its `body` closure from `layout` (it needs the panel width to measure the
     * three rows). CUI has no active state store during layout, so a `TextField` constructed there
     * never registers its focus id in the focus graph: the next commit clears `ctx.focus(id)` and
     * the caret never appears. That is also why `TextField.autofocus()` — whose subscriber focuses
     * during the frame tick — could not keep the field focused. Constructing the field while the
     * shell body is building registers it like any other control, so the shell's one-shot focus
     * request (see `ShellHost.noteQuickCaptureVisibility`) sticks.
     */
    let inputField: ?Widget = if (open) {
        Some(
            TextField(text, key: CAPTURE_INPUT_ID)
                .style(captureInputStyle(tokens))
                .placeholder("例如：给财务回电确认发票抬头 #财务 @电话 !低能 /明天")
                .textStyle(TextStyle(fontSize: fp(15.0)))
                .height(44.5)
        )
    } else {
        None
    }
    Ui.modal(theme, presented, onClose, title: "收集到 GTD 收件箱",
        description: "先记录，稍后再澄清。Enter 连续收集，⌘/Ctrl + Enter 收集并关闭。", width: 560.0,
        footer: {=>
            KeyChipView(tokens, "Enter", style: KeyChipStyle.Capture)
            Label("继续收集").fontSize(Length(11.0, LengthUnit.Fp)).foregroundColor(c.textFaint)
            Ui.button(theme, "关闭", onClose, variant: ButtonVariant.Ghost, size: ControlSize.Sm)
            Ui.button(theme, "收集并关闭", {=> onCollect(text.value, true)}, variant: ButtonVariant.Secondary,
                size: ControlSize.Sm, enabled: parsed.hasContent)
            Ui.button(theme, "收集", {=> onCollect(text.value, false)}, variant: ButtonVariant.Primary,
                size: ControlSize.Sm, iconLeft: IconGlyph.Plus, enabled: parsed.hasContent)
        }, body: {=>
            VStack(spacing: vp(tokens.space.s3)) {
                // .capture-label { 12px; 600; text-muted }
                Label("收集什么？").fontSize(Length(12.0, LengthUnit.Fp)).fontWeight(FontWeight(600))
                    .foregroundColor(c.textMuted)
                match (inputField) {
                    case Some(field) =>
                        EventHandler(onEvent: {ctx, event =>
                            match (event) {
                                case UiEvent.KeyDown(Key.Enter, isRepeat) =>
                                    if (isRepeat || !parsed.hasContent) {
                                        false
                                    } else {
                                        onCollect(text.value, ctx.eventModifiers().command)
                                        true
                                    }
                                case _ => false
                            }
                        }) {
                            emit(field)
                        }.fillWidth()
                    case None => ()
                }
                // .capture-chips { display:flex; gap:8; min-height:22 }
                HStack(spacing: vp(tokens.space.s2)) {
                    if (hasPreview) {
                        Label("解析预览").fontSize(Length(11.0, LengthUnit.Fp)).foregroundColor(c.textFaint)
                    }
                    for (tag in parsed.tags) {
                        CaptureChipView(tokens, "#${tag}", glyph: Some(IconGlyph.Tag), tone: "accent")
                    }
                    match (parsed.context) {
                        case Some(value) => CaptureChipView(tokens, "@${value}", tone: "info")
                        case None => ()
                    }
                    match (parsed.energy) {
                        case Some(value) => CaptureChipView(tokens, captureEnergyLabel(value), tone: "warn")
                        case None => ()
                    }
                    match (parsed.date) {
                        case Some(value) =>
                            CaptureChipView(tokens, "${formatDateKey(value, pattern: "MM/dd")} 到期",
                                glyph: Some(IconGlyph.Calendar), tone: "ok")
                        case None => ()
                    }
                }.hug().minHeight(22.0).fillWidth()
                CaptureHintsView(tokens, captureHintRuns()).fillWidth()
                // .capture-session { border-top 1px; padding-top 12; gap 8 }
                Divider().foregroundColor(c.border)
                VStack(spacing: vp(tokens.space.s2)) {
                    HStack(spacing: vp(tokens.space.s2)) {
                        Label("本次会话已收集 ${sessionSnapshot.size} 条${sessionSuffix}")
                            .fontSize(Length(12.0, LengthUnit.Fp))
                            .fontWeight(FontWeight(600))
                            .foregroundColor(c.textMuted)
                            .flex()
                        if (!sessionSnapshot.isEmpty()) {
                            IconButtonView(tokens, IconGlyph.Trash, onUndo, variant: IconButtonVariant.Ghost,
                                size: ControlSize.Sm, tooltip: "撤销最后一条收集")
                        }
                    }.hug().fillWidth()
                    if (sessionSnapshot.isEmpty()) {
                        Label("还没有收集内容。每按一次 Enter，就会在下方留下一条记录。")
                            .fontSize(Length(12.0, LengthUnit.Fp)).foregroundColor(c.textFaint)
                    } else {
                        VStack(spacing: vp(2.0)) {
                            for (entry in sessionSnapshot) {
                                CaptureSessionRowView(tokens, entry).fillWidth()
                            }
                        }.hug().fillWidth()
                    }
                }.hug().fillWidth()
            }.hug().fillWidth()
        })
}
