package textura.shell

import cui.*
import textura.core.data.*
import textura.ui.*
import textura.views.calendar as calendar
import textura.views.dashboard as dashboard
import textura.views.gantt as gantt
import textura.views.gtd as gtd
import textura.views.okr as okr
import textura.views.settings as settings
import textura.views.sop as sop

/*
 * View dispatch contract (docs/STRUCTURE.md §3.2b, docs/SHELL.md §4).
 *
 * Every view package exposes `public func render(ctx: ViewContext): Unit` and must not
 * import `textura.shell`. The shell keeps that shape in one place: `viewRendererFor`
 * returns the function that owns the content slot for a route. Until a view lands, its
 * slot holds `placeholderView(...)` — the same bootstrap note the gate used to print —
 * so the shared dispatch code never has to change shape again: swapping one `case` arm
 * from `placeholderView` to `<view>.render` is the entire integration step.
 */
public type ViewRenderer = (ViewContext) -> Unit

/** The renderer that owns `route`'s content slot. */
public func viewRendererFor(route: Route): ViewRenderer {
    match (route) {
        case Route.Dashboard => {viewCtx => dashboard.render(viewCtx)}
        case Route.Calendar => {viewCtx => calendar.render(viewCtx)}
        case Route.Okr => {viewCtx => okr.render(viewCtx)}
        case Route.Gtd => {viewCtx => gtd.render(viewCtx)}
        case Route.Gantt => {viewCtx => gantt.render(viewCtx)}
        case Route.Sop => {viewCtx => sop.render(viewCtx)}
        case Route.Settings => {viewCtx => settings.render(viewCtx)}
    }
}

/**
 * Dispatch + the Web build's `RouteErrorBoundary`: a view that throws is replaced by the
 * recovery card while the sidebar/topbar stay usable (the shell never goes blank).
 */
public func renderRoute(route: Route, viewCtx: ViewContext): Unit {
    try {
        viewRendererFor(route)(viewCtx)
    } catch (error: Exception) {
        buildRouteError(themeByName(viewCtx.theme), error.message, viewCtx.store)
    }
}

/**
 * Bootstrap placeholder for a view that has not landed yet. It mirrors the Web shell's
 * `.page` / `.placeholder-card` surface so the chrome can be verified independently of
 * the business views (docs/UI-KIT.md §5 does the same for the kit gallery).
 */
public func placeholderView(route: Route, viewCtx: ViewContext): Unit {
    let theme = themeByName(viewCtx.theme)
    let tokens = tokensOf(theme)
    let c = tokens.color
    let note = match (route) {
        case Route.Dashboard => dashboard.bootstrapNote()
        case Route.Calendar => calendar.bootstrapNote()
        case Route.Okr => okr.bootstrapNote()
        case Route.Gtd => gtd.bootstrapNote()
        case Route.Gantt => gantt.bootstrapNote()
        case Route.Sop => sop.bootstrapNote()
        case Route.Settings => settings.bootstrapNote()
    }
    let title = match (route) {
        case Route.Dashboard => dashboard.bootstrapTitle()
        case Route.Calendar => calendar.bootstrapTitle()
        case Route.Okr => okr.bootstrapTitle()
        case Route.Gtd => gtd.bootstrapTitle()
        case Route.Gantt => gantt.bootstrapTitle()
        case Route.Sop => sop.bootstrapTitle()
        case Route.Settings => settings.bootstrapTitle()
    }
    // `.page { max-width: 1280px; margin: 0 auto; gap: var(--space-5) }`
    VStack(spacing: vp(tokens.space.s5)) {
        VStack(spacing: vp(tokens.space.s1)) {
            Label(title).fontSize(Length(22.0, LengthUnit.Fp)).fontWeight(FontWeight(650))
                .foregroundColor(c.text)
            Label("${routeLabel(route)} · 由 ${routeId(route)} 视图 worker 填充")
                .fontSize(Length(13.0, LengthUnit.Fp)).foregroundColor(c.textMuted)
        }.hug().fillWidth()
        // `.placeholder-card { border: 1px dashed border-strong; radius 14; surface; padding 32 }`
        VStack(spacing: vp(tokens.space.s3)) {
            Label("视图占位").fontSize(Length(14.0, LengthUnit.Fp)).fontWeight(FontWeight(600))
                .foregroundColor(c.text)
            Label(note).fontSize(Length(12.5, LengthUnit.Fp)).foregroundColor(c.textMuted).wrap()
        }
            .hug()
            .fillWidth()
            .padding(vp(tokens.space.s6))
            .background(c.surface, tokens.radius.lg)
            .border(c.borderStrong, width: CHROME_BORDER, radius: tokens.radius.lg)
    }
        .maxWidth(PAGE_MAX_WIDTH)
        .fillWidth()
}
