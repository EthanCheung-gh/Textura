package textura.shell

import std.collection.*
import cui.*
import textura.core.data.*
import textura.ui.*

/*
 * `.notices` toast stack (shell.css:312-349): anchored bottom-right 24px, 8px gap,
 * 220–360px wide cards, 12/16 padding, 1px border, radius 8, `--shadow-2`, 13px text and
 * a 3px tone bar on the left (ok / danger / info). The Web build auto-dismisses them; the
 * lifetime lives in `ShellRuntime`.
 */

public class NoticeRow {
    public let id: String
    public let message: String
    public let tone: NoticeTone

    public init(id: String, message: String, tone: NoticeTone) {
        this.id = id
        this.message = message
        this.tone = tone
    }
}

public func noticeToneColor(tokens: ThemeTokens, tone: NoticeTone): Color {
    match (tone) {
        case NoticeTone.Success => tokens.color.ok
        case NoticeTone.Error => tokens.color.danger
        case NoticeTone.Info => tokens.color.info
    }
}

/** Right-bottom toast layer; draws above the shell and never consumes pointer input. */
public class NoticeLayerView <: Widget {
    private let tokens: ThemeTokens
    private let rows: Array<NoticeRow>
    private var frame = Rect.zero()

    public init(tokens: ThemeTokens, rows: Array<NoticeRow>) {
        this.tokens = tokens
        this.rows = rows
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(max(available.w, 0.0), max(available.h, 0.0))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func isFlexible(): Bool {
        true
    }

    public func draw(ctx: UiContext): Unit {
        if (rows.isEmpty()) {
            return
        }
        let fontSize = fpSize(ctx, NOTICE_FONT)
        let line = lineBox(NOTICE_FONT)
        var total: Float32 = 0.0
        var index = 0
        while (index < rows.size) {
            total += noticeHeight(ctx, rows[index].message, fontSize, line)
            if (index + 1 < rows.size) {
                total += NOTICE_GAP
            }
            index += 1
        }
        var y = frame.bottom() - NOTICE_INSET - total
        for (row in rows) {
            let height = noticeHeight(ctx, row.message, fontSize, line)
            drawNotice(ctx, row, y, height, fontSize, line)
            y += height + NOTICE_GAP
        }
    }

    private func noticeWidth(ctx: UiContext, message: String, fontSize: Float32): Float32 {
        let textW = textWidth(ctx, message, fontSize, 400)
        min(NOTICE_MAX_WIDTH, max(NOTICE_MIN_WIDTH, textW + NOTICE_PAD_X * 2.0 + CHROME_BORDER + NOTICE_TONE_WIDTH))
    }

    private func noticeHeight(ctx: UiContext, message: String, fontSize: Float32, line: Float32): Float32 {
        let width = noticeWidth(ctx, message, fontSize)
        let inner = width - NOTICE_PAD_X * 2.0 - CHROME_BORDER - NOTICE_TONE_WIDTH
        Float32(noticeLines(ctx, message, inner, fontSize)) * line + NOTICE_PAD_Y * 2.0 + CHROME_BORDER * 2.0
    }

    private func drawNotice(ctx: UiContext, row: NoticeRow, y: Float32, height: Float32, fontSize: Float32,
        line: Float32): Unit {
        let c = tokens.color
        let width = noticeWidth(ctx, row.message, fontSize)
        let rect = Rect(frame.right() - NOTICE_INSET - width, y, width, height)
        softShadow(ctx, rect, tokens.radius.md, tokens.shadow2)
        fillRound(ctx, rect, tokens.radius.md, c.surface)
        strokeRound(ctx, rect, tokens.radius.md, CHROME_BORDER, c.border)
        // border-left: 3px solid tone
        let tone = noticeToneColor(tokens, row.tone)
        fillRound(ctx, Rect(rect.x, rect.y, tokens.radius.md, rect.h), tokens.radius.md, tone)
        fillRound(ctx, Rect(rect.x + NOTICE_TONE_WIDTH, rect.y, rect.w - NOTICE_TONE_WIDTH, rect.h),
            tokens.radius.md, c.surface)
        strokeRound(ctx, rect, tokens.radius.md, CHROME_BORDER, c.border)
        let innerX = rect.x + NOTICE_TONE_WIDTH + NOTICE_PAD_X
        let innerW = rect.w - NOTICE_TONE_WIDTH - NOTICE_PAD_X * 2.0 - CHROME_BORDER
        let lines = wrapNotice(ctx, row.message, innerW, fontSize)
        var index = 0
        while (index < lines.size) {
            textLeading(ctx, lines[index], innerX, rect.y + NOTICE_PAD_Y + line * Float32(index) + line / 2.0, c.text,
                fontSize, 400)
            index += 1
        }
    }

    private func noticeLines(ctx: UiContext, message: String, width: Float32, fontSize: Float32): Int64 {
        Int64(wrapNotice(ctx, message, width, fontSize).size)
    }

    /** Greedy single-line wrapping; the Web layer lets CSS break anywhere. */
    private func wrapNotice(ctx: UiContext, message: String, width: Float32, fontSize: Float32): Array<String> {
        if (textWidth(ctx, message, fontSize, 400) <= width) {
            return [message]
        }
        let lines = ArrayList<String>()
        let current = StringBuilder()
        var currentWidth: Float32 = 0.0
        for (rune in message.toRuneArray()) {
            let piece = String([rune])
            let pieceWidth = textWidth(ctx, piece, fontSize, 400)
            if (currentWidth + pieceWidth > width && current.size > 0) {
                lines.add(current.toString())
                current.reset()
                currentWidth = 0.0
            }
            current.append(piece)
            currentWidth += pieceWidth
        }
        if (current.size > 0) {
            lines.add(current.toString())
        }
        lines.toArray()
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}
