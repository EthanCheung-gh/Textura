package textura.shell

import textura.views.calendar as calendar
import textura.views.dashboard as dashboard
import textura.views.gantt as gantt
import textura.views.gtd as gtd
import textura.views.okr as okr
import textura.views.settings as settings
import textura.views.sop as sop
import textura.ui.*

/** The seven top-level routes. URL/CLI ids are lowercase to match the Web build. */
public enum Route {
    | Dashboard
    | Calendar
    | Okr
    | Gtd
    | Gantt
    | Sop
    | Settings

    public operator func ==(right: Route): Bool {
        routeId(this) == routeId(right)
    }

    public operator func !=(right: Route): Bool {
        !(this == right)
    }
}

public let ROUTES: Array<Route> = [
    Route.Dashboard,
    Route.Calendar,
    Route.Okr,
    Route.Gtd,
    Route.Gantt,
    Route.Sop,
    Route.Settings
]

public func parseRoute(value: String): ?Route {
    match (value) {
        case "dashboard" => Some(Route.Dashboard)
        case "calendar" => Some(Route.Calendar)
        case "okr" => Some(Route.Okr)
        case "gtd" => Some(Route.Gtd)
        case "gantt" => Some(Route.Gantt)
        case "sop" => Some(Route.Sop)
        case "settings" => Some(Route.Settings)
        case _ => None
    }
}

public func routeId(route: Route): String {
    match (route) {
        case Route.Dashboard => "dashboard"
        case Route.Calendar => "calendar"
        case Route.Okr => "okr"
        case Route.Gtd => "gtd"
        case Route.Gantt => "gantt"
        case Route.Sop => "sop"
        case Route.Settings => "settings"
    }
}

public func routeTitle(route: Route): String {
    match (route) {
        case Route.Dashboard => dashboard.bootstrapTitle()
        case Route.Calendar => calendar.bootstrapTitle()
        case Route.Okr => okr.bootstrapTitle()
        case Route.Gtd => gtd.bootstrapTitle()
        case Route.Gantt => gantt.bootstrapTitle()
        case Route.Sop => sop.bootstrapTitle()
        case Route.Settings => settings.bootstrapTitle()
    }
}

public func routeNote(route: Route): String {
    match (route) {
        case Route.Dashboard => dashboard.bootstrapNote()
        case Route.Calendar => calendar.bootstrapNote()
        case Route.Okr => okr.bootstrapNote()
        case Route.Gtd => gtd.bootstrapNote()
        case Route.Gantt => gantt.bootstrapNote()
        case Route.Sop => sop.bootstrapNote()
        case Route.Settings => settings.bootstrapNote()
    }
}

/*
 * `src/app/routes.ts` metadata — sidebar order is the product flow:
 * 今日 → 日历 → OKR → GTD → 甘特 → SOP → 设置.
 *
 * `routeTitle()` / `routeNote()` above stay wired to each view's bootstrap strings
 * (docs/STRUCTURE.md §3.6); the strings below are the Web build's own labels, which the
 * shell chrome (sidebar labels, topbar title/subtitle, command palette) must show
 * verbatim regardless of whether the route's view has landed yet.
 */
public func routeLabel(route: Route): String {
    match (route) {
        case Route.Dashboard => "今日"
        case Route.Calendar => "日历"
        case Route.Okr => "OKR"
        case Route.Gtd => "GTD"
        case Route.Gantt => "甘特"
        case Route.Sop => "SOP"
        case Route.Settings => "设置"
    }
}

public func routeMetaTitle(route: Route): String {
    routeLabel(route)
}

public func routeSubtitle(route: Route): String {
    match (route) {
        case Route.Dashboard => "今天要推进的事，一屏看完"
        case Route.Calendar => "公历、农历与节气的日程视图"
        case Route.Okr => "目标与关键结果的季度视图"
        case Route.Gtd => "收集、澄清、推进下一步"
        case Route.Gantt => "时间轴上的承诺与依赖"
        case Route.Sop => "把流程画成可执行图"
        case Route.Settings => "存储、备份与工作区"
    }
}

/** `routes.ts` `icon`: home / calendar-grid / target / inbox / timeline / workflow / settings. */
public func routeGlyph(route: Route): IconGlyph {
    match (route) {
        case Route.Dashboard => IconGlyph.Home
        case Route.Calendar => IconGlyph.CalendarGrid
        case Route.Okr => IconGlyph.Target
        case Route.Gtd => IconGlyph.Inbox
        case Route.Gantt => IconGlyph.Timeline
        case Route.Sop => IconGlyph.Workflow
        case Route.Settings => IconGlyph.Settings
    }
}
