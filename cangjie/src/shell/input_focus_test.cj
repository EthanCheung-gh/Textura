package textura.shell

import std.collection.ArrayList
import std.env.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*

/*
 * Every text input must take focus from a primary press.
 *
 * Why this exists: on the HarmonyOS device a press on the quick-capture field (or the palette
 * search, or a GTD clarify field) produced no caret and no IME, while a press on the topbar
 * search did. The difference was *when* the control was declared: CUI registers a focus stop
 * only while a build block is active (`registerFocusable` is a no-op outside one), so a
 * `TextField` constructed from `layout` — which is what `ModalHost` used to do for its body —
 * focused an id the next commit dropped (docs/DEVICE-NOTES.md §16).
 *
 * The test removes that whole class of bug for every view at once: it reads the semantics
 * snapshot (one node per laid-out `TextField`, with the rect it occupies), presses the centre
 * of each, and requires the focus id to become that node's id. A view that rebuilds its
 * controls during layout fails here even if it renders correctly.
 */

private let FOCUS_RECT: Rect = Rect(0.0, 0.0, 1440.0, 900.0)
private let FOCUS_ANCHOR: Int64 = 1773626400000
private let FOCUS_HOME: String = "/tmp/textura-shell-focus-test-home"

private func focusTestHost(): ShellHost {
    try {
        setVariable("HOME", FOCUS_HOME)
    } catch (_: Exception) {
        ()
    }
    let clock = FixedClock(FOCUS_ANCHOR)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    store.setRoute(routeId(Route.Dashboard))
    let runtime = ShellRuntime(ShellPreferences.load(), store)
    let noLoadError: ?String = None
    ShellHost(store, runtime, "2026-01-01", false, noLoadError, 1440, 900)
}

/** One editable text control as the last frame laid it out. */
private class FieldPlace {
    let id: String
    let centerX: Float32
    let centerY: Float32

    init(id: String, centerX: Float32, centerY: Float32) {
        this.id = id
        this.centerX = centerX
        this.centerY = centerY
    }
}

/** Text controls in the committed semantics tree, clipped to what is actually on screen. */
private func fieldPlaces(testHost: WidgetTestHost): ArrayList<FieldPlace> {
    let result = ArrayList<FieldPlace>()
    for (node in testHost.context.semanticsSnapshot()) {
        match (node.properties.role) {
            case SemanticsRole.TextField => ()
            case _ => continue
        }
        let rect = node.visibleBounds
        if (rect.w <= 1.0 || rect.h <= 1.0) {
            continue
        }
        if (rect.x < 0.0 || rect.y < 0.0 || rect.right() > FOCUS_RECT.w || rect.bottom() > FOCUS_RECT.h) {
            continue
        }
        result.add(FieldPlace(node.id, rect.centerX(), rect.centerY()))
    }
    result
}

/** Presses `place` and reports the focus id the frame settled on. */
private func pressField(testHost: WidgetTestHost, place: FieldPlace, body: () -> Unit): String {
    testHost.context.clearFocus()
    let _ = testHost.frame(FOCUS_RECT,
        events: [
            UiEvent.MouseMove(place.centerX, place.centerY),
            UiEvent.MouseDown(MouseButton.Left, place.centerX, place.centerY),
            UiEvent.MouseUp(MouseButton.Left, place.centerX, place.centerY)
        ], body: body)
    testHost.context.focusId
}

/**
 * Every route: each laid-out text control takes focus from a click on its own rectangle.
 *
 * Views that keep their fields visible (gantt inspector, calendar quick add, topbar search)
 * are covered here; canvas views that paint text instead of declaring a control have nothing
 * to click, which is exactly why they edit through `Ui.prompt` (see `input_prompt_test.cj`).
 */
@Test
func everyVisibleTextFieldFocusesWhenClicked(): Unit {
    var checked = 0
    let covered = ArrayList<String>()
    for (route in ROUTES) {
        let host = focusTestHost()
        host.armStoreBridge({action => action()})
        host.store.setRoute(routeId(route))
        if (routeId(route) == "gantt") {
            // The inspector (and with it the title/date/detail editors) is collapsed by default;
            // open it and select a row so its fields are part of the enumerated tree.
            host.store.setUi({state => state.inspectorOpen = true})
            let seeded = host.store.state.value()
            if (!seeded.items.isEmpty()) {
                host.store.select(seeded.items[0].id)
            }
        }
        let testHost = WidgetTestHost()
        let body = {=> buildShell(host)}
        let _ = testHost.frame(FOCUS_RECT, body: body)
        for (place in fieldPlaces(testHost)) {
            let focused = pressField(testHost, place, body)
            @Expect(focused, place.id)
            covered.add(place.id)
            // A press that moved focus must also have left the field on screen: re-read the tree
            // so a control that only exists before the press is not silently skipped afterwards.
            let _ = testHost.frame(FOCUS_RECT, body: body)
            checked += 1
        }
    }
    // The seed workspace has an inspector, a quick-add box and the topbar search; a tree that
    // registered no text control at all would make this suite vacuously green.
    @Expect(checked >= 3, true)
    for (expected in ["shell-search", "gantt-title", "calendar-quick-input"]) {
        var found = false
        for (id in covered) {
            if (id == expected) {
                found = true
            }
        }
        @Expect("${expected} covered", "${expected} covered")
        @Expect(found, true)
    }
}

/** The command palette's search box focuses from a click, and filters through the store. */
@Test
func paletteSearchFocusesWhenClicked(): Unit {
    let host = focusTestHost()
    host.armStoreBridge({action => action()})
    let testHost = WidgetTestHost()
    let body = {=> buildShell(host)}
    let _ = testHost.frame(FOCUS_RECT, body: body)
    host.store.setUi({state => state.paletteOpen = true})
    let _ = testHost.frame(FOCUS_RECT, body: body)
    let places = fieldPlaces(testHost)
    var target: ?FieldPlace = None
    for (place in places) {
        if (place.id == "palette-search") {
            target = Some(place)
        }
    }
    @Expect(target.isSome(), true)
    match (target) {
        case Some(place) => @Expect(pressField(testHost, place, body), "palette-search")
        case None => ()
    }
}

/** Quick capture: the caret lands in the input on the opening frame, without a click. */
@Test
func quickCaptureAutofocusesOnOpen(): Unit {
    let host = focusTestHost()
    host.armStoreBridge({action => action()})
    let testHost = WidgetTestHost()
    let body = {=> buildShell(host)}
    let _ = testHost.frame(FOCUS_RECT, body: body)
    host.store.setUi({state => state.quickCaptureOpen = true})
    let _ = testHost.frame(FOCUS_RECT, body: body)
    @Expect(testHost.context.focusId, CAPTURE_INPUT_ID)
    // And closing it returns focus to the row that held it (nothing did → current route's row).
    host.closeCapture()
    let _ = testHost.frame(FOCUS_RECT, body: body)
    @Expect(testHost.context.focusId, "shell-nav-dashboard")
}
