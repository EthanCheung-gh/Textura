package textura.views.gtd

import std.collection.*
import cui.*
import textura.core.data.*
import textura.ui.*
import textura.views.gtd.logic as gl

/*
 * GTD 视图的共享零件。
 *
 * 尺寸全部来自 gtd.css / ui.css（行号见 gtd_metrics.cj）。凡是 CSS 里没有对应几何的
 * 控件（计数药丸、kbd 提示、20px 勾选圆、行内 select/date 盒、复选开关、页头标题）
 * 都自绘：CUI 的同类控件是固定 22/34/38 高、固定内边距，无法表达 18/20/30 与 10.5px 字号。
 */

/* ---------------------------------------------------------------- 计数药丸 */

/** `.gtd-count`（gtd.css:158-171）：min-width 20、高 18、圆角 999、1px 描边、11px。 */
class GtdCountPill <: Widget {
    private let tokens: ThemeTokens
    private let count: Int64
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, count: Int64) {
        this.tokens = tokens
        this.count = count
        emit(this)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        let text = "${count}"
        let width = max(COUNT_MIN_W,
            advanceOf(ctx, text, COUNT_SIZE, 400) + COUNT_PAD_H * 2.0 + tokens.metrics.borderWidth * 2.0)
        Size(min(width, max(available.w, 0.0)), COUNT_H)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        fillRound(ctx, frame, COUNT_H / 2.0, c.surface)
        strokeRound(ctx, frame, COUNT_H / 2.0, tokens.metrics.borderWidth, c.border)
        drawLineCenter(ctx, "${count}", frame.centerX(), frame.centerY(), COUNT_SIZE, 400, c.textMuted)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/* ---------------------------------------------------------------- 键盘提示 */

/**
 * `.gtd-kbd-hint`（gtd.css:204-224）：`↑ ↓ 选择 x 完成 Enter 打开澄清`。
 * `kbd` 高 18（10px × 1.5 行盒 + 上 1px / 下 2px 描边）、左右 4px、圆角 4、等宽字体。
 */
class GtdKbdHint <: Widget {
    private let tokens: ThemeTokens
    private let parts: Array<KbdPart>
    private var frame = Rect.zero()

    init(tokens: ThemeTokens) {
        this.tokens = tokens
        let built = ArrayList<KbdPart>()
        built.add(KbdPart("↑", true))
        built.add(KbdPart("↓", true))
        built.add(KbdPart("选择", false))
        built.add(KbdPart("x", true))
        built.add(KbdPart("完成", false))
        built.add(KbdPart("Enter", true))
        built.add(KbdPart("打开澄清", false))
        this.parts = built.toArray()
        emit(this)
    }

    private func partWidth(ctx: UiContext, part: KbdPart): Float32 {
        let size = if (part.isKey) {
            KBD_SIZE
        } else {
            KBD_HINT_SIZE
        }
        let weight: Int64 = if (part.isKey) {
            400
        } else {
            400
        }
        let family = if (part.isKey) {
            Some(fontMono())
        } else {
            noFamily()
        }
        var width = advanceOf(ctx, part.text, size, weight, family: family)
        if (part.isKey) {
            width += KBD_PAD_H * 2.0 + tokens.metrics.borderWidth * 2.0
        }
        width
    }

    public func measure(ctx: UiContext, available: Size): Size {
        var width: Float32 = 0.0
        var index = 0
        for (part in parts) {
            if (index > 0) {
                width += KBD_GAP
            }
            width += partWidth(ctx, part)
            index += 1
        }
        Size(min(width, max(available.w, 0.0)), kbdHeight())
    }

    private func kbdHeight(): Float32 {
        KBD_SIZE * KBD_LINE + tokens.metrics.borderWidth + 2.0
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        var x = frame.x
        let centerY = frame.centerY()
        var index = 0
        for (part in parts) {
            if (index > 0) {
                x += KBD_GAP
            }
            let width = partWidth(ctx, part)
            if (part.isKey) {
                let box = Rect(x, centerY - kbdHeight() / 2.0, width, kbdHeight())
                fillRound(ctx, box, KBD_RADIUS, c.surface)
                // border: 1px solid border-strong; border-bottom-width: 2px
                strokeRound(ctx, box, KBD_RADIUS, tokens.metrics.borderWidth, c.borderStrong)
                ctx.renderer.fill(Rect(box.x + 1.0, box.bottom() - 2.0, box.w - 2.0, 1.0), c.borderStrong)
                drawLineCenter(ctx, part.text, box.centerX(), box.centerY() - 0.5, KBD_SIZE, 400, c.textMuted,
                    family: fontMono())
            } else {
                drawLine(ctx, part.text, x, centerY, KBD_HINT_SIZE, 400, c.textFaint)
            }
            x += width
            index += 1
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/** kbd 提示的一段：按键（画成 kbd 盒）或说明文字。 */
struct KbdPart {
    let text: String
    let isKey: Bool

    init(text: String, isKey: Bool) {
        this.text = text
        this.isKey = isKey
    }
}

/* ---------------------------------------------------------------- 页头标题 */

/**
 * `.page-header-titles`（shell.css:277-290）：h1 22px/650（行盒 33）+ gap 4 + p 13px（行盒 19.5）。
 * 自绘理由与 `gantt/page_header.cj` 相同：Label 的行盒由字体自然行高决定，钉不到 33/19.5。
 */
class GtdPageTitles <: Widget {
    private let tokens: ThemeTokens
    private let title: String
    private let subtitle: String
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, title: String, subtitle: String) {
        this.tokens = tokens
        this.title = title
        this.subtitle = subtitle
        emit(this)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        let titleWidth = advanceOf(ctx, title, H1_SIZE, H1_WEIGHT)
        let subtitleWidth = advanceOf(ctx, subtitle, SUB_SIZE, 400)
        Size(min(max(titleWidth, subtitleWidth), max(available.w, 0.0)), headerHeight())
    }

    private func headerHeight(): Float32 {
        H1_SIZE * LINE_HEIGHT + HEADER_TITLE_GAP + SUB_SIZE * LINE_HEIGHT
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        // `h1 { letter-spacing: -0.01em }`（base.css:43）
        drawLineSpaced(ctx, title, frame.x, frame.y + H1_SIZE * LINE_HEIGHT / 2.0, H1_SIZE, H1_WEIGHT,
            tokens.color.text, -0.01 * H1_SIZE)
        let subtitleTop = H1_SIZE * LINE_HEIGHT + HEADER_TITLE_GAP
        drawLine(ctx, subtitle, frame.x, frame.y + subtitleTop + SUB_SIZE * LINE_HEIGHT / 2.0, SUB_SIZE, 400,
            tokens.color.textMuted)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/* ---------------------------------------------------------------- 流程条卡片 */

/**
 * `.gtd-flow-card`（gtd.css:24-93）：1px 描边 + 左侧 3px 色条 + 圆角 8，
 * 内边距 12/16，三行内容 gap 1（11.5px 标题行、24px 数值行、11px 提示行）。
 */
class GtdFlowCard <: Widget {
    private let tokens: ThemeTokens
    private let glyph: IconGlyph
    private let glyphColor: Color
    private let label: String
    private let value: Int64
    private let hint: String
    private let leadColor: Color
    private let hoverId: String
    private let onClick: () -> Unit
    private var frame = Rect.zero()

    init(
        tokens: ThemeTokens,
        glyph: IconGlyph,
        glyphColor: Color,
        label: String,
        value: Int64,
        hint: String,
        leadColor: Color,
        hoverId: String,
        onClick: () -> Unit
    ) {
        this.tokens = tokens
        this.glyph = glyph
        this.glyphColor = glyphColor
        this.label = label
        this.value = value
        this.hint = hint
        this.leadColor = leadColor
        this.hoverId = hoverId
        this.onClick = onClick
        emit(this)
    }

    /** 高度：2 描边 + 24 内边距 + 17.25 + 27.6 + 16.5 + 2 gap ≈ 89.35。 */
    private func cardHeight(): Float32 {
        let topLine = FLOW_TOP_SIZE * LINE_HEIGHT
        let valueLine = FLOW_VALUE_SIZE * FLOW_VALUE_LH
        let hintLine = FLOW_HINT_SIZE * LINE_HEIGHT
        tokens.metrics.borderWidth * 2.0 + FLOW_PAD_V * 2.0 + topLine + valueLine + hintLine + FLOW_INNER_GAP * 2.0
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(max(available.w, 0.0), cardHeight())
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        let hovered = ctx.isHovered(hoverId)
        // `.gtd-flow-card:hover { background: surface-2; border-color: border-strong;
        //  transform: translateY(-1px) }`
        let lift: Float32 = if (hovered) {
            -1.0
        } else {
            0.0
        }
        let box = frame.shift(0.0, lift)
        shadow1(ctx, tokens, box, FLOW_RADIUS)
        fillRound(ctx, box, FLOW_RADIUS, if (hovered) {
            c.surface2
        } else {
            c.surface
        })
        strokeRound(ctx, box, FLOW_RADIUS, tokens.metrics.borderWidth, if (hovered) {
            c.borderStrong
        } else {
            c.border
        })
        // `border-left: 3px solid`：贴左边缘的色条（圆角处露出极少，与浏览器一致到 1px 内）。
        let lead = Rect(box.x + tokens.metrics.borderWidth, box.y + FLOW_RADIUS / 2.0, FLOW_LEAD,
            max(0.0, box.h - FLOW_RADIUS))
        fillRound(ctx, lead, 1.5, leadColor)

        let contentX = box.x + FLOW_LEAD + FLOW_PAD_H
        let contentTop = box.y + tokens.metrics.borderWidth + FLOW_PAD_V
        let topLine = FLOW_TOP_SIZE * LINE_HEIGHT
        let valueLine = FLOW_VALUE_SIZE * FLOW_VALUE_LH
        let hintLine = FLOW_HINT_SIZE * LINE_HEIGHT
        let topCenter = contentTop + topLine / 2.0
        // `.gtd-flow-card-top { display:flex; align-items:center; gap:6px }`
        paintSpec(ctx, glyph, Rect(contentX, topCenter - FLOW_TOP_ICON / 2.0, FLOW_TOP_ICON, FLOW_TOP_ICON),
            glyphColor)
        drawLine(ctx, label, contentX + FLOW_TOP_ICON + FLOW_TOP_GAP, topCenter, FLOW_TOP_SIZE, FLOW_TOP_WEIGHT,
            c.textMuted)
        let valueTop = contentTop + topLine + FLOW_INNER_GAP
        drawLine(ctx, "${value}", contentX, valueTop + valueLine / 2.0, FLOW_VALUE_SIZE, FLOW_VALUE_WEIGHT, c.text)
        let hintTop = valueTop + valueLine + FLOW_INNER_GAP
        drawLine(ctx, hint, contentX, hintTop + hintLine / 2.0, FLOW_HINT_SIZE, 400, c.textFaint)
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(_, _) =>
                claimHoverIfInside(ctx, event, frame, hoverId, CursorShape.Interactive)
            case UiEvent.MouseDown(pressButton, x, y) where isPrimaryPointerButton(pressButton) =>
                if (frame.contains(x, y)) {
                    ctx.press(hoverId)
                    return true
                }
            case UiEvent.MouseUp(_, x, y) =>
                if (ctx.isPressed(hoverId)) {
                    ctx.clearPress()
                    if (frame.contains(x, y)) {
                        onClick()
                        return true
                    }
                }
            case _ => ()
        }
        false
    }
}

/* ---------------------------------------------------------------- 勾选圆 / 复选 */

/** `.gtd-check`（gtd.css:324-342）：20×20 圆形按钮，1.5px 描边，hover 用强调色。 */
class GtdCheck <: Widget {
    private let tokens: ThemeTokens
    private let hoverId: String
    private let label: String
    private let onClick: () -> Unit
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, hoverId: String, label: String, onClick: () -> Unit) {
        this.tokens = tokens
        this.hoverId = hoverId
        this.label = label
        this.onClick = onClick
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(min(CHECK_SIZE, max(available.w, 0.0)), CHECK_SIZE)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        let hovered = ctx.isHovered(hoverId)
        fillRound(ctx, frame, CHECK_SIZE / 2.0, if (hovered) {
            c.accentSoft
        } else {
            c.surface
        })
        strokeRound(ctx, frame, CHECK_SIZE / 2.0, 1.5, if (hovered) {
            c.accent
        } else {
            c.borderStrong
        })
        if (hovered) {
            paintSpec(ctx, IconGlyph.Check, Rect(frame.centerX() - 6.0, frame.centerY() - 6.0, 12.0, 12.0),
                c.accent)
        }
        let _ = label
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(_, _) =>
                claimHoverIfInside(ctx, event, frame, hoverId, CursorShape.Interactive)
            case UiEvent.MouseDown(pressButton, x, y) where isPrimaryPointerButton(pressButton) =>
                if (frame.contains(x, y)) {
                    ctx.press(hoverId)
                    return true
                }
            case UiEvent.MouseUp(_, x, y) =>
                if (ctx.isPressed(hoverId)) {
                    ctx.clearPress()
                    if (frame.contains(x, y)) {
                        onClick()
                        return true
                    }
                }
            case _ => ()
        }
        false
    }
}

/** `.gtd-toggle` 的 15×15 复选方框（原生 checkbox 近似）。 */
class GtdCheckBox <: Widget {
    private let tokens: ThemeTokens
    private let checked: Bool
    private let hoverId: String
    private let onClick: () -> Unit
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, checked: Bool, hoverId: String, onClick: () -> Unit) {
        this.tokens = tokens
        this.checked = checked
        this.hoverId = hoverId
        this.onClick = onClick
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(min(TOGGLE_BOX, max(available.w, 0.0)), TOGGLE_BOX)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        let box = Rect(frame.x + 0.5, frame.y + 0.5, TOGGLE_BOX - 1.0, TOGGLE_BOX - 1.0)
        if (checked) {
            fillRound(ctx, box, 2.0, c.accent)
            paintSpec(ctx, IconGlyph.Check, Rect(box.x + 2.0, box.y + 2.0, box.w - 4.0, box.h - 4.0),
                c.textOnStrong)
        } else {
            fillRound(ctx, box, 2.0, c.surface)
            strokeRound(ctx, box, 2.0, 1.0, c.textFaint)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(_, _) =>
                claimHoverIfInside(ctx, event, frame, hoverId, CursorShape.Interactive)
            case UiEvent.MouseDown(pressButton, x, y) where isPrimaryPointerButton(pressButton) =>
                if (frame.contains(x, y)) {
                    ctx.press(hoverId)
                    return true
                }
            case UiEvent.MouseUp(_, x, y) =>
                if (ctx.isPressed(hoverId)) {
                    ctx.clearPress()
                    if (frame.contains(x, y)) {
                        onClick()
                        return true
                    }
                }
            case _ => ()
        }
        false
    }
}

/* ---------------------------------------------------------------- 行内控件 */

/**
 * 行内 select（gtd.css:426-438 / 455-463）：高 30、圆角 8、1px 描边、11.5/12px，
 * 右侧 10×5 的下拉三角（`background-position: calc(100% - 13px) 12px`）。
 */
class GtdSelectBox <: Widget {
    private let tokens: ThemeTokens
    private let text: String
    private let boxWidth: Float32
    private let fontSize: Float32
    private let padRight: Float32
    private let hoverId: String
    private let onClick: () -> Unit
    private var frame = Rect.zero()

    init(
        tokens: ThemeTokens,
        text: String,
        width: Float32,
        hoverId: String,
        onClick: () -> Unit,
        fontSize!: Float32 = INLINE_FONT,
        padRight!: Float32 = 24.0
    ) {
        this.tokens = tokens
        this.text = text
        this.boxWidth = width
        this.fontSize = fontSize
        this.padRight = padRight
        this.hoverId = hoverId
        this.onClick = onClick
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(min(boxWidth, max(available.w, 0.0)), INLINE_H)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        let hovered = ctx.isHovered(hoverId)
        fillRound(ctx, frame, tokens.radius.md, c.surface)
        strokeRound(ctx, frame, tokens.radius.md, tokens.metrics.borderWidth, if (hovered) {
            c.borderStrong
        } else {
            c.border
        })
        let leftPad = INLINE_PAD_H + tokens.metrics.borderWidth
        let textRoom = max(0.0, frame.w - leftPad - padRight)
        let fitted = ellipsizeGtd(ctx, text, fontSize, 400, textRoom)
        drawLine(ctx, fitted, frame.x + leftPad, frame.centerY(), fontSize, 400, c.text)
        // 下拉三角：10 宽 5 高，位于 `100% - 13px`（相对背景盒）。
        let caretCenter = frame.right() - 8.0
        let caretTop = frame.y + 12.0
        var row: Int64 = 0
        while (row < 5) {
            let half = 5.0 - Float32(row)
            ctx.renderer.fill(Rect(caretCenter - half, caretTop + Float32(row), half * 2.0, 1.0), c.textFaint)
            row += 1
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(_, _) =>
                claimHoverIfInside(ctx, event, frame, hoverId, CursorShape.Interactive)
            case UiEvent.MouseDown(pressButton, x, y) where isPrimaryPointerButton(pressButton) =>
                if (frame.contains(x, y)) {
                    ctx.press(hoverId)
                    return true
                }
            case UiEvent.MouseUp(_, x, y) =>
                if (ctx.isPressed(hoverId)) {
                    ctx.clearPress()
                    if (frame.contains(x, y)) {
                        onClick()
                        return true
                    }
                }
            case _ => ()
        }
        false
    }
}

/**
 * 行内日期盒（gtd.css:440-442）：124×30，占位文案 `mm/dd/yyyy`（Chrome 原生 date 输入），
 * 右侧 14px 日历图标。
 */
class GtdDateBox <: Widget {
    private let tokens: ThemeTokens
    private let text: String
    private let empty: Bool
    private let hoverId: String
    private let onClick: () -> Unit
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, text: String, hoverId: String, onClick: () -> Unit) {
        this.tokens = tokens
        this.text = if (text.isEmpty()) {
            "mm/dd/yyyy"
        } else {
            text
        }
        this.empty = text.isEmpty()
        this.hoverId = hoverId
        this.onClick = onClick
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(min(INLINE_DATE_W, max(available.w, 0.0)), INLINE_H)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        let hovered = ctx.isHovered(hoverId)
        fillRound(ctx, frame, tokens.radius.md, c.surface)
        strokeRound(ctx, frame, tokens.radius.md, tokens.metrics.borderWidth, if (hovered) {
            c.borderStrong
        } else {
            c.border
        })
        drawLine(ctx, text, frame.x + INLINE_PAD_H + tokens.metrics.borderWidth, frame.centerY(), INLINE_FONT, 400,
            if (empty) {
                c.textFaint
            } else {
                c.text
            })
        paintSpec(ctx, IconGlyph.Calendar, Rect(frame.right() - 22.0, frame.centerY() - 7.0, 14.0, 14.0),
            c.textFaint)
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(_, _) =>
                claimHoverIfInside(ctx, event, frame, hoverId, CursorShape.Interactive)
            case UiEvent.MouseDown(pressButton, x, y) where isPrimaryPointerButton(pressButton) =>
                if (frame.contains(x, y)) {
                    ctx.press(hoverId)
                    return true
                }
            case UiEvent.MouseUp(_, x, y) =>
                if (ctx.isPressed(hoverId)) {
                    ctx.clearPress()
                    if (frame.contains(x, y)) {
                        onClick()
                        return true
                    }
                }
            case _ => ()
        }
        false
    }
}

/** `.gtd-linkbtn`（gtd.css:837-848）：accent 11.5px，hover 下划线。 */
class GtdLinkButton <: Widget {
    private let tokens: ThemeTokens
    private let text: String
    private let hoverId: String
    private let onClick: () -> Unit
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, text: String, hoverId: String, onClick: () -> Unit) {
        this.tokens = tokens
        this.text = text
        this.hoverId = hoverId
        this.onClick = onClick
        emit(this)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        Size(min(advanceOf(ctx, text, LINKBTN_SIZE, 400), max(available.w, 0.0)), lineBox(LINKBTN_SIZE))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        drawLine(ctx, text, frame.x, frame.centerY(), LINKBTN_SIZE, 400, tokens.color.accent)
        if (ctx.isHovered(hoverId)) {
            let width = advanceOf(ctx, text, LINKBTN_SIZE, 400)
            ctx.renderer.fill(Rect(frame.x, frame.centerY() + LINKBTN_SIZE * 0.55, width, 1.0),
                tokens.color.accent)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(_, _) =>
                claimHoverIfInside(ctx, event, frame, hoverId, CursorShape.Interactive)
            case UiEvent.MouseDown(pressButton, x, y) where isPrimaryPointerButton(pressButton) =>
                if (frame.contains(x, y)) {
                    ctx.press(hoverId)
                    return true
                }
            case UiEvent.MouseUp(_, x, y) =>
                if (ctx.isPressed(hoverId)) {
                    ctx.clearPress()
                    if (frame.contains(x, y)) {
                        onClick()
                        return true
                    }
                }
            case _ => ()
        }
        false
    }
}

/** `.gtd-area`（gtd.css:403-416）：7×7 领域色圆点 + 名称，11.5px、text-faint。 */
class GtdAreaChip <: Widget {
    private let tokens: ThemeTokens
    private let color: Color
    private let name: String
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, color: Color, name: String) {
        this.tokens = tokens
        this.color = color
        this.name = name
        emit(this)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        let width = AREA_DOT + CHIP_GAP + advanceOf(ctx, name, META_SIZE, 400)
        Size(min(width, max(available.w, 0.0)), lineBox(META_SIZE))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        ctx.renderer.fillCircle(frame.x + AREA_DOT / 2.0, frame.centerY(), AREA_DOT / 2.0, color)
        drawLine(ctx, name, frame.x + AREA_DOT + CHIP_GAP, frame.centerY(), META_SIZE, 400, tokens.color.textFaint)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/* ---------------------------------------------------------------- 分区外壳 */

/** `.gtd-section-header`：图标 + 标题 + 计数 + 提示，10px 上下内边距、次表面底色。 */
func gtdSectionHeader(
    scene: GtdScene,
    glyph: IconGlyph,
    title: String,
    count: Int64,
    hint!: ?() -> Unit = noAction()
): Unit {
    let tokens = scene.tokens
    VStack(spacing: vp(0.0)) {
        HStack(spacing: vp(SECTION_HEADING_GAP)) {
            IconView(glyph, side: SECTION_ICON, color: tokens.color.textFaint)
            GtdText(title, SECTION_TITLE_SIZE, SECTION_TITLE_WEIGHT, tokens.color.text,
                boxHeight: SECTION_TITLE_SIZE * LINE_HEIGHT)
            GtdCountPill(tokens, count)
            match (hint) {
                case Some(body) =>
                    HStack(spacing: vp(HINT_GAP)) {
                        body()
                    }
                        .crossAxisAlignment(CrossAxisAlignment.Center)
                        .hug()
                        .padding(vp(HINT_MARGIN), vp(0.0), vp(0.0), vp(0.0))
                case None => ()
            }
            Spacer()
        }
            .crossAxisAlignment(CrossAxisAlignment.Center)
            .hug()
            .fillWidth()
            .padding(vp(SECTION_HEADER_PAD_H), vp(SECTION_HEADER_PAD_V), vp(SECTION_HEADER_PAD_H), vp(SECTION_HEADER_PAD_V))
            .background(tokens.color.bgSubtle, corners: Corners.top(SECTION_RADIUS))
        gtdRule(tokens.color.border)
    }.hug().fillWidth()
}

/**
 * 卡片底（`.gtd-section` / `.gtd-review-card` / `.gtd-review-overview`）：
 * 圆角 14、1px 描边、`--surface` 底、`--shadow-1`。
 *
 * 自绘并把外框吸附到整数像素：CUI 的 `.border()` / `.background()` 按小数坐标绘制，
 * 1px 描边会摊成两行 50% 混合色，而浏览器会把边框吸附到设备像素。这里用 ZStack 叠在
 * 内容后面（ZStack 给每个子节点同一矩形），内容自己按 1px 描边内缩。
 */
class GtdCard <: Widget {
    private let tokens: ThemeTokens
    private let radius: Float32
    private let borderColor: Color
    private let borderWidth: Float32
    private var frame = Rect.zero()

    init(tokens: ThemeTokens, radius: Float32, borderColor: Color, borderWidth!: Float32 = 1.0) {
        this.tokens = tokens
        this.radius = radius
        this.borderColor = borderColor
        this.borderWidth = borderWidth
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size.zero()
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let x = Float32(Int64(frame.x + 0.5))
        let y = Float32(Int64(frame.y + 0.5))
        let box = Rect(x, y, max(0.0, Float32(Int64(frame.right() + 0.5)) - x),
            max(0.0, Float32(Int64(frame.bottom() + 0.5)) - y))
        shadow1(ctx, tokens, box, radius)
        fillRound(ctx, box, radius, tokens.color.surface)
        strokeRound(ctx, box, radius, borderWidth, borderColor)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

func gtdSectionShell(scene: GtdScene, key: String, body!: () -> Unit): Unit {
    let tokens = scene.tokens
    let highlighted = scene.state.highlight.value == key
    let inset = tokens.metrics.borderWidth
    ZStack {
        GtdCard(tokens, SECTION_RADIUS, if (highlighted) {
            tokens.color.accent
        } else {
            tokens.color.border
        }, borderWidth: if (highlighted) {
            2.0
        } else {
            1.0
        })
        VStack(spacing: vp(0.0)) {
            body()
        }.hug().fillWidth().padding(vp(inset))
    }.fillWidth()
}

/** 空态：`.gtd-empty-body { padding: 12 }` + `Ui.emptyState(compact)`。 */
func gtdEmptyBlock(scene: GtdScene, title: String, description: String, glyph: IconGlyph,
    action!: ?() -> Unit = noAction()): Unit {
    VStack(spacing: vp(0.0)) {
        Ui.emptyState(scene.theme, title, description: description, glyph: glyph, compact: true, action: action)
    }.hug().fillWidth().padding(vp(EMPTY_BODY_PAD))
}

/** 分页脚注：`显示更多（剩余 N 条）` + `已显示 X / Y 条`。 */
func gtdShowMore(
    scene: GtdScene,
    remaining: Int64,
    shown: Int64,
    total: Int64,
    onClick!: () -> Unit,
    note!: Bool = true
): Unit {
    let tokens = scene.tokens
    VStack(spacing: vp(0.0)) {
        VStack(spacing: vp(0.0)) {
            GtdDashedRule(tokens.color.border)
        }.hug().fillWidth()
        HStack(spacing: vp(SHOW_MORE_GAP)) {
            GtdLinkButton(tokens, "显示更多（剩余 ${remaining} 条）", "gtd-show-more:${total}", onClick)
            if (note) {
                GtdText("已显示 ${shown} / ${total} 条", SHOW_MORE_NOTE_SIZE, 400, tokens.color.textFaint,
                    boxHeight: SHOW_MORE_NOTE_SIZE * LINE_HEIGHT)
            }
            Spacer()
        }
            .crossAxisAlignment(CrossAxisAlignment.Center)
            .hug()
            .fillWidth()
            .padding(vp(SHOW_MORE_PAD_H), vp(SHOW_MORE_PAD_V), vp(SHOW_MORE_PAD_H), vp(SHOW_MORE_PAD_V))
    }.hug().fillWidth()
}

/**
 * `.badge` 的定高版本。
 *
 * `BadgeView.measure` 按 `11 × 1.6 + 2×2` 算 21.6（漏掉 1px 描边），而 CSS 的边框盒是
 * `11 × 1.6 + 4 + 2 = 23.6`（ui.css:247-251）。差 2px 会让每个徽标行与整行高度短 1~2px，
 * 6 行收件箱累计漂移 8px。这里用定高容器把徽标钉到 23.6，BadgeView 按 frame 高度绘制圆角。
 */
func gtdBadge(tokens: ThemeTokens, text: String, tone: BadgeTone, dot!: Bool = false): Unit {
    HStack(spacing: vp(0.0)) {
        BadgeView(tokens, text, tone: tone, dot: dot)
    }.hug().height(BADGE_HEIGHT)
}

/** 元信息里的图标 + 文本（`.gtd-row-time` / `.gtd-deadline`）。 */
func gtdIconText(
    scene: GtdScene,
    glyph: IconGlyph,
    text: String,
    color: Color,
    size!: Float32 = META_SIZE,
    weight!: Int64 = 400
): Unit {
    let tokens = scene.tokens
    let _ = tokens
    HStack(spacing: vp(CHIP_GAP)) {
        IconView(glyph, side: META_ICON, color: color)
        GtdText(text, size, weight, color, boxHeight: size * LINE_HEIGHT)
    }.crossAxisAlignment(CrossAxisAlignment.Center).hug()
}

/**
 * 行左侧 2px 高亮条（`.gtd-row { border-left: 2px solid transparent }`）。
 *
 * 自绘而不是 `.fillHeight()`：视图被 shell 放进 ScrollView 后按「无界高度」测量，
 * `fillHeight` 会把行撑到整屏（实测首行吃掉 1000px，后续行全部跑到折线以下）。
 * 这里 measure 只报 0 高、宽度 2，交叉轴 Stretch 会把 frame 撑成行高。
 */
class GtdRowEdge <: Widget {
    private let color: Color
    private var frame = Rect.zero()

    init(color: Color) {
        this.color = color
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(min(ROW_EDGE, max(available.w, 0.0)), 0.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        if (color.a == 0 || frame.w <= 0.0 || frame.h <= 0.0) {
            return
        }
        ctx.renderer.fill(frame, color)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

func gtdRowEdge(color: Color): Unit {
    GtdRowEdge(color)
}
