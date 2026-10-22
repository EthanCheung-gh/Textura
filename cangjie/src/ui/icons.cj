package textura.ui

import cui.*

/*
 * Textura glyph set — a 1:1 port of `src/ui/icons.tsx`.
 *
 * Naming note: CUI exports its own `IconName` (sdl's 15-glyph system set) and an `Icon`
 * widget class. Exporting the same identifiers from `textura.ui` would make every bare
 * `IconName` / `Icon` reference ambiguous in any package that also writes `import cui.*`
 * (which every view must, for containers). The port therefore exports `IconGlyph` +
 * `IconView` + `Ui.icon(...)`; `iconGlyphId()` returns the original kebab-case id from
 * icons.tsx so the two sets stay diffable.
 *
 * Geometry: 24x24 grid, `stroke="currentColor" strokeWidth={1.75}`, round caps/joins.
 * Everything is stroked from the original `d` strings (see icon_path.cj); nothing is
 * redrawn by hand.
 */

/** Every icon name from `src/ui/icons.tsx` (order matches the `IconName` union). */
public enum IconGlyph {
    | Folder
    | Home
    | Target
    | Inbox
    | Timeline
    | Workflow
    | Search
    | Plus
    | ChevronLeft
    | ChevronRight
    | ChevronDown
    | Close
    | Settings
    | Sun
    | Moon
    | Check
    | Cross
    | Play
    | Grip
    | ZoomIn
    | ZoomOut
    | Link
    | Calendar
    | CalendarGrid
    | Tag
    | Flag
    | Clock
    | Trash
    | Edit
    | More

    /**
     * Identity comparison. Cangjie does not synthesise `==` for enums, and views routinely need
     * `selected == IconGlyph.CalendarGrid`; comparing the canonical ids keeps this correct even
     * if the variant order ever changes.
     */
    public operator func ==(other: IconGlyph): Bool {
        iconGlyphId(this) == iconGlyphId(other)
    }

    public operator func !=(other: IconGlyph): Bool {
        !(this == other)
    }
}

/** The icons.tsx identifier (`'chevron-left'`, `'calendar-grid'`, ...). */
public func iconGlyphId(glyph: IconGlyph): String {
    match (glyph) {
        case Folder => "folder"
        case Home => "home"
        case Target => "target"
        case Inbox => "inbox"
        case Timeline => "timeline"
        case Workflow => "workflow"
        case Search => "search"
        case Plus => "plus"
        case ChevronLeft => "chevron-left"
        case ChevronRight => "chevron-right"
        case ChevronDown => "chevron-down"
        case Close => "close"
        case Settings => "settings"
        case Sun => "sun"
        case Moon => "moon"
        case Check => "check"
        case Cross => "x"
        case Play => "play"
        case Grip => "grip"
        case ZoomIn => "zoom-in"
        case ZoomOut => "zoom-out"
        case Link => "link"
        case Calendar => "calendar"
        case CalendarGrid => "calendar-grid"
        case Tag => "tag"
        case Flag => "flag"
        case Clock => "clock"
        case Trash => "trash"
        case Edit => "edit"
        case More => "more"
    }
}

/** All glyphs in icons.tsx declaration order (parity / docs / tests). */
public let ALL_ICON_GLYPHS: Array<IconGlyph> = [
    IconGlyph.Folder, IconGlyph.Home, IconGlyph.Target, IconGlyph.Inbox, IconGlyph.Timeline, IconGlyph.Workflow,
    IconGlyph.Search, IconGlyph.Plus, IconGlyph.ChevronLeft, IconGlyph.ChevronRight, IconGlyph.ChevronDown,
    IconGlyph.Close, IconGlyph.Settings, IconGlyph.Sun, IconGlyph.Moon, IconGlyph.Check, IconGlyph.Cross,
    IconGlyph.Play, IconGlyph.Grip, IconGlyph.ZoomIn, IconGlyph.ZoomOut, IconGlyph.Link, IconGlyph.Calendar,
    IconGlyph.CalendarGrid, IconGlyph.Tag, IconGlyph.Flag, IconGlyph.Clock, IconGlyph.Trash, IconGlyph.Edit,
    IconGlyph.More
]

/** Reverse of `iconGlyphId`; `None` for a name the port does not implement. */
public func iconGlyphFromId(id: String): ?IconGlyph {
    for (glyph in ALL_ICON_GLYPHS) {
        if (iconGlyphId(glyph) == id) {
            return Some(glyph)
        }
    }
    None
}

/** Shapes making up one glyph, exactly as declared in icons.tsx. */
struct GlyphSpec {
    let paths: Array<String>
    let rings: Array<GlyphRing>
    let boxes: Array<GlyphBox>
    let dots: Array<GlyphDot>

    init(
        paths!: Array<String> = [],
        rings!: Array<GlyphRing> = [],
        boxes!: Array<GlyphBox> = [],
        dots!: Array<GlyphDot> = []
    ) {
        this.paths = paths
        this.rings = rings
        this.boxes = boxes
        this.dots = dots
    }
}

/** The SVG geometry for `glyph` (icons.tsx `PATHS`). */
func glyphSpec(glyph: IconGlyph): GlyphSpec {
    match (glyph) {
        case Folder => GlyphSpec(
            paths: ["M3 7.5A2.5 2.5 0 0 1 5.5 5h3.2l2 2.2h7.8A2.5 2.5 0 0 1 21 9.7v7.8A2.5 2.5 0 0 1 18.5 20h-13A2.5 2.5 0 0 1 3 17.5z"]
        )
        case Home => GlyphSpec(paths: ["M3.5 10.5 12 3.5l8.5 7", "M5.5 9.5V20h13V9.5", "M9.5 20v-5.5h5V20"])
        case Target =>
            GlyphSpec(rings: [GlyphRing(12.0, 12.0, 8.5), GlyphRing(12.0, 12.0, 4.5)], dots: [GlyphDot(12.0, 12.0, 1.0)])
        case Inbox => GlyphSpec(
            paths: [
                "M3.5 13.5 6 6.5A2 2 0 0 1 7.9 5h8.2a2 2 0 0 1 1.9 1.5l2.5 7",
                "M3.5 13.5h4l1.6 2.6h5.8l1.6-2.6h4v4A2.5 2.5 0 0 1 18 20H6a2.5 2.5 0 0 1-2.5-2.5z"
            ]
        )
        case Timeline => GlyphSpec(paths: ["M3 4v16", "M6 7h9", "M9 12h10", "M6 17h7"])
        case Workflow => GlyphSpec(
            paths: ["M9 6.5h6M6 9v6a2 2 0 0 0 2 2h7"],
            boxes: [
                GlyphBox(3.0, 4.0, 6.0, 5.0, 1.5), GlyphBox(15.0, 15.0, 6.0, 5.0, 1.5),
                GlyphBox(15.0, 4.0, 6.0, 5.0, 1.5)
            ]
        )
        case Search => GlyphSpec(paths: ["m16.5 16.5 4 4"], rings: [GlyphRing(11.0, 11.0, 7.0)])
        case Plus => GlyphSpec(paths: ["M12 5v14M5 12h14"])
        case ChevronLeft => GlyphSpec(paths: ["m14 6-6 6 6 6"])
        case ChevronRight => GlyphSpec(paths: ["m10 6 6 6-6 6"])
        case ChevronDown => GlyphSpec(paths: ["m6 10 6 6 6-6"])
        case Close => GlyphSpec(paths: ["m6 6 12 12M18 6 6 18"])
        case Settings => GlyphSpec(
            paths: ["M4 7h9M17 7h3M4 17h3M11 17h9"],
            rings: [GlyphRing(15.0, 7.0, 2.0), GlyphRing(9.0, 17.0, 2.0)]
        )
        case Sun => GlyphSpec(
            paths: ["M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4"],
            rings: [GlyphRing(12.0, 12.0, 4.0)]
        )
        case Moon => GlyphSpec(paths: ["M20.5 13.2A8.5 8.5 0 1 1 10.8 3.5a6.8 6.8 0 0 0 9.7 9.7z"])
        case Check => GlyphSpec(paths: ["m5 12.5 4.5 4.5L19 7"])
        case Cross => GlyphSpec(paths: ["m6 6 12 12M18 6 6 18"])
        case Play => GlyphSpec(paths: ["M8 5.5 19 12 8 18.5z"])
        case Grip => GlyphSpec(
            dots: [
                GlyphDot(9.0, 6.0, 1.2), GlyphDot(15.0, 6.0, 1.2), GlyphDot(9.0, 12.0, 1.2), GlyphDot(15.0, 12.0, 1.2),
                GlyphDot(9.0, 18.0, 1.2), GlyphDot(15.0, 18.0, 1.2)
            ]
        )
        case ZoomIn => GlyphSpec(paths: ["m16.5 16.5 4 4M8 11h6M11 8v6"], rings: [GlyphRing(11.0, 11.0, 7.0)])
        case ZoomOut => GlyphSpec(paths: ["m16.5 16.5 4 4M8 11h6"], rings: [GlyphRing(11.0, 11.0, 7.0)])
        case Link => GlyphSpec(
            paths: [
                "M10 13a4 4 0 0 0 5.7 0l2.6-2.6a4 4 0 0 0-5.7-5.7L11 6.3",
                "M14 11a4 4 0 0 0-5.7 0l-2.6 2.6a4 4 0 0 0 5.7 5.7l1.6-1.6"
            ]
        )
        case Calendar => GlyphSpec(
            paths: ["M3.5 10h17M8 3.5V7M16 3.5V7"],
            boxes: [GlyphBox(3.5, 5.0, 17.0, 15.5, 2.0)]
        )
        case CalendarGrid => GlyphSpec(
            paths: ["M3.5 9.5h17M8 2.5V6M16 2.5V6"],
            boxes: [GlyphBox(3.5, 4.5, 17.0, 16.0, 2.0)],
            dots: [
                GlyphDot(8.0, 13.2, 1.0), GlyphDot(12.0, 13.2, 1.0), GlyphDot(16.0, 13.2, 1.0), GlyphDot(8.0, 17.0, 1.0),
                GlyphDot(12.0, 17.0, 1.0), GlyphDot(16.0, 17.0, 1.0)
            ]
        )
        case Tag => GlyphSpec(
            paths: ["M20.3 13.3 13.3 20.3a2 2 0 0 1-2.8 0L3.5 13.3V3.5h9.8l7 7a2 2 0 0 1 0 2.8z"],
            rings: [GlyphRing(7.8, 7.8, 1.3)]
        )
        case Flag => GlyphSpec(paths: ["M6 21V4h11l-2.2 4L17 12H6"])
        case Clock => GlyphSpec(paths: ["M12 7.5V12l3 2"], rings: [GlyphRing(12.0, 12.0, 8.5)])
        case Trash => GlyphSpec(paths: ["M4 7h16M9.5 7V4.5h5V7M6.5 7l1 13h9l1-13", "M10 11v5M14 11v5"])
        case Edit => GlyphSpec(paths: ["M4 20h4L20 8l-4-4L4 16z", "m14.5 5.5 4 4"])
        case More => GlyphSpec(dots: [GlyphDot(6.0, 12.0, 1.4), GlyphDot(12.0, 12.0, 1.4), GlyphDot(18.0, 12.0, 1.4)])
    }
}

/** Paints `glyph` into `frame` (no background, no clipping) with the icons.tsx geometry. */
public func paintSpec(ctx: UiContext, glyph: IconGlyph, frame: Rect, color: Color): Unit {
    let spec = glyphSpec(glyph)
    paintGlyph(ctx.renderer, spec.paths, spec.rings, spec.boxes, spec.dots, frame, color)
}

/**
 * Non-interactive glyph, the port of `<Icon name={...} size={...} />`. Square, defaults to
 * 18vp and the theme text colour (icons.tsx `size = 18`, `currentColor`).
 */
public class IconView <: Widget {
    private let glyph: IconGlyph
    private let side: Float32
    private let colorOverride: ?Color
    private var frame = Rect.zero()

    public init(glyph: IconGlyph, side!: Float32 = 18.0, color!: ?Color = None) {
        this.glyph = glyph
        this.side = max(1.0, side)
        this.colorOverride = color
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        let extent = min(this.side, min(available.w, available.h))
        Size(max(0.0, extent), max(0.0, extent))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let color = colorOverride.getOrDefault({=> ctx.theme.text})
        let spec = glyphSpec(glyph)
        paintGlyph(ctx.renderer, spec.paths, spec.rings, spec.boxes, spec.dots, frame, color)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/**
 * Sidebar glyphs for the seven top-level routes, transcribed from `src/app/routes.ts`.
 *
 * These are `IconGlyph` values (not strings) on purpose: the bootstrap-era `ICON_*` strings
 * carried an id the port does not implement (`"layout-dashboard"`), so a sidebar copy would
 * have silently rendered nothing. Typed constants make the mismatch a compile error.
 */
public let ROUTE_GLYPH_DASHBOARD: IconGlyph = IconGlyph.Home
public let ROUTE_GLYPH_CALENDAR: IconGlyph = IconGlyph.CalendarGrid
public let ROUTE_GLYPH_OKR: IconGlyph = IconGlyph.Target
public let ROUTE_GLYPH_GTD: IconGlyph = IconGlyph.Inbox
public let ROUTE_GLYPH_GANTT: IconGlyph = IconGlyph.Timeline
public let ROUTE_GLYPH_SOP: IconGlyph = IconGlyph.Workflow
public let ROUTE_GLYPH_SETTINGS: IconGlyph = IconGlyph.Settings

// ---------------------------------------------------------------------------
// Legacy string ids kept for the bootstrap call sites. Every value is a real icons.tsx id
// (`ICON_DASHBOARD` used to be "layout-dashboard", which no longer exists in the source).
// New code should use `ROUTE_GLYPH_*` or `IconGlyph` directly.
// ---------------------------------------------------------------------------

public let ICON_DASHBOARD: String = "home"
public let ICON_CALENDAR: String = "calendar-grid"
public let ICON_OKR: String = "target"
public let ICON_GTD: String = "inbox"
public let ICON_GANTT: String = "timeline"
public let ICON_SOP: String = "workflow"
public let ICON_SETTINGS: String = "settings"
