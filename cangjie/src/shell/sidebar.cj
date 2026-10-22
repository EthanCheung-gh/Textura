package textura.shell

import std.collection.*
import cui.*
import textura.ui.*

/*
 * `src/app/Sidebar.tsx` + `shell.css` `.sidebar*` — drawn as one widget so the 240px
 * column keeps the Web build's exact metrics:
 *
 *   brand 56px (30x30 mark, 15px/680 name, 11px/.18em sub)
 *   scroll padding 16/12, nav rows 34.25px (7px padding + 13.5px × 1.5 line box) with 2px gap
 *   section title 11px/600 with .08em tracking, area rows 31.5px (6px + 13px × 1.5)
 *   footer border-top + 12/16 padding, 11.5px status rows with an 8px gap
 *
 * All colours come from `textura.ui` tokens; the only external colour is `Area.color`,
 * which is domain data (`core.data` palette) and is parsed here.
 */

public class SidebarNavItem {
    public let id: String
    public let label: String
    public let glyph: IconGlyph
    /** `countByStatus(workspace).inbox` for GTD; 0 hides the badge (Sidebar.tsx:49). */
    public let count: Int64
    public let active: Bool

    public init(id: String, label: String, glyph: IconGlyph, count: Int64, active: Bool) {
        this.id = id
        this.label = label
        this.glyph = glyph
        this.count = count
        this.active = active
    }
}

public class SidebarAreaItem {
    public let name: String
    public let color: Color
    /** Open items (`status != done && status != dropped`) for this area. */
    public let count: Int64

    public init(name: String, color: Color, count: Int64) {
        this.name = name
        this.color = color
        this.count = count
    }
}

public class SidebarData {
    public let nav: Array<SidebarNavItem>
    public let areas: Array<SidebarAreaItem>
    public let saveState: String
    public let footerText: String

    public init(nav: Array<SidebarNavItem>, areas: Array<SidebarAreaItem>, saveState: String, footerText: String) {
        this.nav = nav
        this.areas = areas
        this.saveState = saveState
        this.footerText = footerText
    }
}

/** `.sidebar-link { padding: 7px 8px; font-size: 13.5px }` row box. */
func sidebarNavRowHeight(): Float32 {
    NAV_ROW_PAD_Y * 2.0 + lineBox(NAV_ROW_FONT)
}

/** `.sidebar-area { padding: 6px 8px; font-size: 13px }` row box. */
func sidebarAreaRowHeight(): Float32 {
    AREA_ROW_PAD_Y * 2.0 + lineBox(AREA_ROW_FONT)
}

/** `.sidebar-footer { border-top 1px; padding: 12px 16px; gap: 8px }` with two 11.5px rows. */
func sidebarFooterHeight(): Float32 {
    CHROME_BORDER + FOOTER_PAD_Y * 2.0 + lineBox(STATUS_FONT) * 2.0 + FOOTER_GAP
}

/** `.sidebar-scroll` starts at y = 56 with 16px top padding. */
func sidebarNavTop(): Float32 {
    TOPBAR_HEIGHT + SIDEBAR_SCROLL_PAD_Y
}

func sidebarNavRowsHeight(count: Int64): Float32 {
    if (count <= 0) {
        return 0.0
    }
    Float32(count) * sidebarNavRowHeight() + Float32(count - 1) * NAV_ROW_GAP
}

/** Nav block + `gap: 24px` + section title (line box + 8px padding). */
func sidebarAreasTop(navCount: Int64): Float32 {
    sidebarNavTop() + sidebarNavRowsHeight(navCount) + SIDEBAR_SCROLL_GAP +
        lineBox(SECTION_TITLE_FONT) + SECTION_TITLE_PAD_BOTTOM
}

/** `Sidebar.tsx` — brand, nav, areas and the storage footer. */
public class SidebarView <: Widget {
    private let tokens: ThemeTokens
    private let data: SidebarData
    private let onNavigate: (String) -> Unit
    private var frame = Rect.zero()
    private var navRects: Array<Rect> = []
    private var hoveredRow: Int64 = -1

    public init(tokens: ThemeTokens, data: SidebarData, onNavigate: (String) -> Unit) {
        this.tokens = tokens
        this.data = data
        this.onNavigate = onNavigate
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(SIDEBAR_WIDTH, max(available.h, 0.0))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
        let rects = ArrayList<Rect>()
        var index = 0
        while (index < data.nav.size) {
            let top = frame.y + sidebarNavTop() + Float32(index) * (sidebarNavRowHeight() + NAV_ROW_GAP)
            rects.add(
                Rect(frame.x + SIDEBAR_SCROLL_PAD_X, top, SIDEBAR_WIDTH - SIDEBAR_SCROLL_PAD_X * 2.0,
                    sidebarNavRowHeight())
            )
            index += 1
        }
        navRects = rects.toArray()
    }

    public func isFlexible(): Bool {
        false
    }

    public func draw(ctx: UiContext): Unit {
        let c = tokens.color
        // .sidebar { background: bg-subtle; border-right: 1px solid border }
        fillRect(ctx, frame, c.bgSubtle)
        ctx.renderer.fill(Rect(frame.right() - CHROME_BORDER, frame.y, CHROME_BORDER, frame.h), c.border)
        drawBrand(ctx)
        drawNav(ctx)
        drawAreas(ctx)
        drawFooter(ctx)
    }

    private func drawBrand(ctx: UiContext): Unit {
        let c = tokens.color
        // .sidebar-brand { height: 56px; padding: 0 16px; gap: 12px; border-bottom: 1px }
        paintRule(ctx, frame.x, frame.y + TOPBAR_HEIGHT - CHROME_BORDER, SIDEBAR_WIDTH, c.border)
        let mark = Rect(frame.x + FOOTER_PAD_X, frame.y + (TOPBAR_HEIGHT - CHROME_BORDER - 30.0) / 2.0, 30.0, 30.0)
        fillRound(ctx, mark, tokens.radius.md, c.text)
        let icon: Float32 = 17.0
        paintSpec(ctx, IconGlyph.Workflow,
            Rect(mark.centerX() - icon / 2.0f32,
                mark.centerY() - icon / 2.0f32, icon, icon), c.bgSubtle)
        let textX = mark.right() + 12.0
        // .sidebar-brand-text { line-height: 1.15 } — two stacked line boxes, centred in 55px
        let nameBox: Float32 = 15.0 * 1.15
        let subBox: Float32 = 11.0 * 1.15
        let blockTop = frame.y + (TOPBAR_HEIGHT - CHROME_BORDER - nameBox - subBox) / 2.0f32
        textTracked(ctx, "Textura", textX, blockTop + nameBox / 2.0f32 + 0.5f32, c.text, fpSize(ctx, 15.0), 680,
            fpSize(ctx, 15.0) * 0.01f32)
        textTracked(ctx, "织理", textX, blockTop + nameBox + subBox / 2.0f32 - 0.5f32, c.textFaint, fpSize(ctx, 11.0), 400,
            fpSize(ctx, 11.0) * 0.18f32)
    }

    private func drawNav(ctx: UiContext): Unit {
        let c = tokens.color
        var index = 0
        while (index < data.nav.size && index < navRects.size) {
            let item = data.nav[index]
            let row = navRects[index]
            let hovered = hoveredRow == index
            if (item.active) {
                // [aria-current='page'] { background: surface; box-shadow: shadow-1 }
                shadow1(ctx, tokens, row, tokens.radius.md)
                fillRound(ctx, row, tokens.radius.md, c.surface)
            } else if (hovered) {
                fillRound(ctx, row, tokens.radius.md, c.surface2)
            }
            let centerY = row.centerY()
            let iconColor = if (item.active) {
                c.accent
            } else {
                c.textFaint
            }
            paintSpec(ctx, item.glyph, Rect(row.x + NAV_ROW_PAD_X, centerY - 8.0, 16.0, 16.0), iconColor)
            let labelColor = if (item.active || hovered) {
                c.text
            } else {
                c.textMuted
            }
            let labelX = row.x + NAV_ROW_PAD_X + 16.0 + 12.0
            let weight = if (item.active) {
                600
            } else {
                400
            }
            textLeading(ctx, item.label, labelX, centerY, labelColor, fpSize(ctx, NAV_ROW_FONT), weight)
            if (item.count > 0) {
                textTrailing(ctx, item.count.toString(), row.right() - NAV_ROW_PAD_X, centerY, c.textFaint,
                    fpSize(ctx, 11.0), 400)
            }
            if (ctx.showFocusRing(navFocusId(index))) {
                focusRing(ctx, tokens, row, tokens.radius.md)
            }
            index += 1
        }
    }

    private func drawAreas(ctx: UiContext): Unit {
        let c = tokens.color
        let titleTop = frame.y + sidebarNavTop() + sidebarNavRowsHeight(Int64(data.nav.size)) + SIDEBAR_SCROLL_GAP
        textTracked(ctx, "领域", frame.x + SIDEBAR_SCROLL_PAD_X + NAV_ROW_PAD_X,
            titleTop + lineBox(SECTION_TITLE_FONT) / 2.0, c.textFaint, fpSize(ctx, SECTION_TITLE_FONT), 600,
            fpSize(ctx, SECTION_TITLE_FONT) * 0.08f32)
        let areaTop = frame.y + sidebarAreasTop(Int64(data.nav.size))
        let rowHeight = sidebarAreaRowHeight()
        if (data.areas.isEmpty()) {
            textLeading(ctx, "暂无领域", frame.x + SIDEBAR_SCROLL_PAD_X + NAV_ROW_PAD_X, areaTop + rowHeight / 2.0,
                c.textFaint, fpSize(ctx, AREA_ROW_FONT), 400)
            return
        }
        var index = 0
        while (index < data.areas.size) {
            let area = data.areas[index]
            let centerY = areaTop + Float32(index) * (rowHeight + AREA_ROW_GAP) + rowHeight / 2.0
            let dot = Rect(frame.x + SIDEBAR_SCROLL_PAD_X + NAV_ROW_PAD_X, centerY - 4.0, 8.0, 8.0)
            fillRound(ctx, dot, 4.0, area.color)
            textLeading(ctx, area.name, dot.right() + 12.0, centerY - 1.0, c.textMuted,
                fpSize(ctx, AREA_ROW_FONT), 400)
            textTrailing(ctx, area.count.toString(),
                frame.x + SIDEBAR_WIDTH - SIDEBAR_SCROLL_PAD_X - NAV_ROW_PAD_X, centerY - 1.0, c.textFaint,
                fpSize(ctx, 11.0), 400)
            index += 1
        }
    }

    private func drawFooter(ctx: UiContext): Unit {
        let c = tokens.color
        let top = frame.bottom() - sidebarFooterHeight()
        paintRule(ctx, frame.x, top, SIDEBAR_WIDTH, c.border)
        let contentTop = top + CHROME_BORDER + FOOTER_PAD_Y
        let row = lineBox(STATUS_FONT)
        let dotColor = match (data.saveState) {
            case "saving" => c.warn
            case "error" => c.danger
            case _ => c.ok
        }
        let dotCenterY = contentTop + row / 2.0 - 1.0
        fillRound(ctx, Rect(frame.x + FOOTER_PAD_X, dotCenterY - 3.0, 6.0, 6.0), 3.0, dotColor)
        textLeading(ctx, saveStateLabel(data.saveState), frame.x + FOOTER_PAD_X + 6.0 + 8.0, dotCenterY, c.textFaint,
            fpSize(ctx, STATUS_FONT), 400)
        // .storage-status.faint has no dot: text starts at the padding edge.
        textLeading(ctx, data.footerText, frame.x + FOOTER_PAD_X, contentTop + row + FOOTER_GAP + row / 2.0 - 1.0,
            c.textFaint, fpSize(ctx, STATUS_FONT), 400)
    }

    private func navFocusId(index: Int64): String {
        if (index >= 0 && index < data.nav.size) {
            "shell-nav-${data.nav[index].id}"
        } else {
            ""
        }
    }

    public func focusableIds(): Array<String> {
        let ids = ArrayList<String>()
        for (item in data.nav) {
            ids.add("shell-nav-${item.id}")
        }
        ids.toArray()
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                var next: Int64 = -1
                var index = 0
                while (index < navRects.size) {
                    if (navRects[index].contains(x, y)) {
                        next = index
                        ctx.claimHover(navFocusId(index), CursorShape.Interactive)
                    }
                    index += 1
                }
                hoveredRow = next
                return next >= 0
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                var index = 0
                while (index < navRects.size) {
                    if (navRects[index].contains(x, y)) {
                        ctx.focus(navFocusId(index), viaKeyboard: false)
                        onNavigate(data.nav[index].id)
                        return true
                    }
                    index += 1
                }
                return false
            case UiEvent.KeyDown(key, isRepeat) =>
                if (isRepeat) {
                    return false
                }
                var index = 0
                while (index < navRects.size) {
                    if (ctx.hasFocus(navFocusId(index))) {
                        match (key) {
                            case Key.Enter | Key.Space =>
                                onNavigate(data.nav[index].id)
                                return true
                            case _ => ()
                        }
                    }
                    index += 1
                }
                return false
            case _ => return false
        }
    }
}
