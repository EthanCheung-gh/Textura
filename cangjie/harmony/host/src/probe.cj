/*
 * Temporary on-device diagnostics for the HarmonyOS host. Off by default.
 *
 * Two questions on a real device that no unit test can answer:
 *
 *   1. What does a pointer press actually look like once it reaches CUI? The desktop path delivers
 *      `UiEvent.MouseDown(MouseButton.Left, …)`; a touch/pointer backend may deliver a button-less
 *      press or an unknown button code, in which case every `MouseDown(MouseButton.Left, …)` handler
 *      in the tree (sidebar navigation, buttons) stays silent while hover keeps working — exactly the
 *      symptom this probe was written for.
 *   2. What does a frame cost, and how big is the surface? A logical 1440x900 hint that turns out to
 *      be a 2880x1620 backing store (or a supersampled one) is four times the pixel budget.
 *
 * Enabling: `PROBE_COMPILED_ON` (build-time) or a flag file placed by something that can write into
 * the app sandbox. Nothing is compiled out, so a normal run behaves exactly as before — the only cost
 * is one `exists()` per frame window and, when active, one line per event / per 60 frames.
 *
 *   flag   <sandbox>/debug-input                      (in-sandbox flag; see the caveat below)
 *          /data/local/tmp/textura-debug-input        (checked too; a root/eng device can place it)
 *   output <sandbox>/diag.log                         (world-readable, so `hdc shell cat` works)
 *          plus the same lines through SDL_LogMessage
 *
 * Caveat measured on the MateBook (docs/DEVICE-NOTES.md §1.1): neither flag path is reachable on a
 * normal user build — the sandbox directory is app-owned (so `hdc shell touch` / `hdc file send` are
 * denied) and the app's SELinux domain does not read `/data/local/tmp`. A diagnostic capture is
 * therefore built with `PROBE_COMPILED_ON = true`; the shipping default is false.
 *
 * Why a file as well as hilog: hilog is a ring buffer that rotates during a long interactive
 * session, the host library cannot use Cangjie's println() (it does not reach hilog), and SDL_Log on
 * this port does not reach hilog either (verified). The file is the durable copy; a probe line and an
 * SDL `SDL/APP` hilog line still correlate, because both are stamped from the same SDL tick base.
 */
package textura_host

import std.collection.ArrayList
import std.fs.{File, exists}
import std.sort.sort
import cui.*
import sdl.input.Mouse
import sdl.system.PerformanceClock
import textura.shell.{DisplayPush, ShellHost}
import textura.ui.isPrimaryPointerButton

/*
 * SDL_LogMessage(category, priority, message) — the *non-variadic* entry point, so it is reachable
 * from Cangjie FFI without varargs support. libSDL3.so is already a NEEDED dependency of this
 * library (the sdl bindings link it), so no extra link flag is required.
 * SDL_LOG_CATEGORY_APPLICATION = 0, SDL_LOG_PRIORITY_INFO = 3.
 */
foreign {
    func SDL_LogMessage(category: Int32, priority: Int32, message: CString): Unit
}

private let PROBE_FLAG_IN_SANDBOX: String = "debug-input"
private let PROBE_FLAG_DEVICE: String = "/data/local/tmp/textura-debug-input"
private let PROBE_LOG_NAME: String = "diag.log"
/*
 * How many input events one session records verbatim.
 *
 * Raised 200 → 800 (2026-10) after a session in which the whole event budget was spent in the
 * first 65 s of a start-up run: the bug being chased ("the pointer goes dead after an edit is
 * committed") happens minutes in, and the log had already gone blind, so the report could not be
 * turned into evidence (§26). 800 covers a full seven-route acceptance walk with room to spare;
 * the per-event cost is one line appended to the log and one SDL_Log line.
 */
private let PROBE_EVENT_LIMIT: Int64 = 800
private let PROBE_FRAME_WINDOW: Int64 = 60
private let PROBE_FLAG_RECHECK_FRAMES: Int64 = 120

/*
 * Compile-time override, for a build that has to collect evidence before the sandbox-writable
 * flag path has been proven on the firmware under test (it is NOT on this device: the app sandbox
 * is app-owned and `/data/local/tmp` is unreadable from the app domain, see docs/DEVICE-NOTES.md §1.1).
 * Must stay false in shipping builds: the probe is a diagnostic, not a feature.
 */
private let PROBE_COMPILED_ON: Bool = false

private var probeRoot: String = "."
private var probeLogPath: String = PROBE_LOG_NAME
private var probeActive: Bool = false
private var probeText: String = ""
private var probeEventCount: Int64 = 0
private var probeContext: ?UiContext = None
private var probeFrames: Int64 = 0
private var probeActiveSamples: ArrayList<Float64> = ArrayList<Float64>()
private var probeIdleSamples: ArrayList<Float64> = ArrayList<Float64>()
private var probeTextSamples: ArrayList<Float64> = ArrayList<Float64>()
private var probeCostSamples: ArrayList<Float64> = ArrayList<Float64>()
private let PROBE_PHASE_SLOTS: Int64 = 10
private let NANOS_PER_MILLI: Float64 = 1000000.0
private var probePhaseTotals: Array<Int64> = Array<Int64>(10, repeat: 0)
private var probePhaseFrames: Int64 = 0

/* Points the probe at the app sandbox and evaluates the flag once. Called from SDL_AppInit. */
func probeConfigure(sandbox: ?String): Unit {
    match (sandbox) {
        case Some(directory) =>
            probeRoot = directory
            probeLogPath = "${directory}${PROBE_LOG_NAME}"
        case None => ()
    }
    probeRefresh()
    // One line per launch, always: it is how an operator learns whether the flag file was visible
    // to the app at all (the app sandbox is not writable from the hdc shell user, so a "flag
    // ignored" report has to be distinguishable from "probe broken").
    probeHilog(
        "config sandbox='${probeRoot}' flag_sandbox=${exists(probeRoot + PROBE_FLAG_IN_SANDBOX)}" +
            " flag_tmp=${exists(PROBE_FLAG_DEVICE)} compiled=${PROBE_COMPILED_ON} enabled=${probeActive}"
    )
    if (probeActive) {
        probeEmit("probe on sandbox=${probeRoot} compiled=${PROBE_COMPILED_ON}")
    }
}

/* Re-evaluates the flag file. Two `exists()` calls per frame window — negligible, and it lets an
 * operator switch the probe on and off between runs without reinstalling. */
private func probeRefresh(): Unit {
    probeActive = PROBE_COMPILED_ON || exists(probeRoot + PROBE_FLAG_IN_SANDBOX) ||
        exists(PROBE_FLAG_DEVICE)
}

private func probeEmit(line: String): Unit {
    let stamped = "t=${PerformanceClock.ticksMilliseconds()} ${line}"
    probeText = "${probeText}${stamped}\n"
    probeWrite()
    probeHilog(stamped)
}

/* The file is the durable copy. A write failure must never disturb the UI, and a probe that cannot
 * write is useless rather than fatal, so errors are swallowed. */
private func probeWrite(): Unit {
    try {
        File.writeTo(probeLogPath, probeText.toArray())
    } catch (_: Exception) {
        ()
    }
}

private func probeHilog(line: String): Unit {
    try {
        let message = unsafe { LibC.mallocCString("probe ${line}") }
        unsafe { SDL_LogMessage(0, 3, message) }
    } catch (_: Exception) {
        ()
    }
}

/* ------------------------------------------------------------------ per-event capture (capture phase) */

/*
 * Logs the first PROBE_EVENT_LIMIT pointer and key events exactly as CUI routes them, together with
 * the interaction state a handler would see. Runs in the capture phase at the root, so an event is
 * recorded whether or not anything below consumes it — "the tree never saw a press" and "the tree saw
 * a press nobody handled" cannot be confused.
 */
func probeEvent(ctx: UiContext, event: UiEvent): Unit {
    if (!probeActive) {
        return
    }
    if (probeContext.isNone()) {
        // First event of the session: the context is the only place the host can read the real
        // viewport/scale from (WindowSpec is just the creation hint).
        probeContext = Some(ctx)
        probeDescribeContext(ctx, "first-event")
    }
    if (!probeIsInput(event)) {
        return
    }
    if (probeEventCount >= PROBE_EVENT_LIMIT) {
        return
    }
    probeEventCount += 1
    probeEmit("ev#${probeEventCount} ${probeDescribe(event)} ${probeState(ctx)}")
}

private func probeIsInput(event: UiEvent): Bool {
    match (event) {
        case UiEvent.MouseMove(_, _) | UiEvent.MouseDown(_, _, _) | UiEvent.MouseUp(_, _, _) |
            UiEvent.MouseWheel(_, _, _, _) | UiEvent.KeyDown(_, _) | UiEvent.KeyUp(_) |
            UiEvent.TextInput(_) => true
        case _ => false
    }
}

private func probeDescribe(event: UiEvent): String {
    match (event) {
        case UiEvent.MouseMove(x, y) => "MouseMove x=${x} y=${y}"
        case UiEvent.MouseDown(button, x, y) =>
            "MouseDown button=${probeButton(button)}${probePrimaryFlag(button)} x=${x} y=${y}"
        case UiEvent.MouseUp(button, x, y) =>
            "MouseUp button=${probeButton(button)}${probePrimaryFlag(button)} x=${x} y=${y}"
        case UiEvent.MouseWheel(dx, dy, x, y) => "MouseWheel dx=${dx} dy=${dy} x=${x} y=${y}"
        case UiEvent.KeyDown(key, repeat) => "KeyDown key=${probeKey(key)} repeat=${repeat}"
        case UiEvent.KeyUp(key) => "KeyUp key=${probeKey(key)}"
        case UiEvent.TextInput(text) => "TextInput text='${text}'"
        case _ => "other"
    }
}

/* The exact decoded button, including the raw code a backend sends when it cannot name one: that
 * value is the whole point of this probe. The `primary=` flag states whether the shell treats this
 * press as the left button (`textura.ui.isPrimaryPointerButton`), so an aliased press is visible in
 * the log instead of silently behaving like a left click. */
private func probeButton(button: MouseButton): String {
    match (button) {
        case MouseButton.Left => "Left"
        case MouseButton.Middle => "Middle"
        case MouseButton.Right => "Right"
        case MouseButton.RawCode(code) => "RawCode(${code})"
    }
}

private func probePrimaryFlag(button: MouseButton): String {
    if (isPrimaryPointerButton(button)) {
        " primary=true"
    } else {
        " primary=false"
    }
}

/* `Key` has no ToString, and the scancode is the interesting part anyway. */
private func probeKey(key: Key): String {
    match (key) {
        case Key.Escape => "Escape"
        case Key.Backspace => "Backspace"
        case Key.Enter => "Enter"
        case Key.Tab => "Tab"
        case Key.Delete => "Delete"
        case Key.Space => "Space"
        case Key.Home => "Home"
        case Key.End => "End"
        case Key.PageUp => "PageUp"
        case Key.PageDown => "PageDown"
        case Key.Left => "Left"
        case Key.Right => "Right"
        case Key.Up => "Up"
        case Key.Down => "Down"
        case Key.Letter(code) => "Letter(${code})"
        case Key.Digit(code) => "Digit(${code})"
        case Key.RawScancode(code) => "Scan(${code})"
    }
}

/* ------------------------------------------------------------------ window size / resize probe */

/*
 * One `size` line per second — the authoritative answer to "did a window resize reach the app?".
 *
 * The resize path is three hops: SDL reports the new surface size (`SDL_EVENT_WINDOW_RESIZED`, or the
 * openharmony backend's own 250ms surface probe), CUI copies `window.width/height` into
 * `UiContext.viewportWidth/Height` each frame, and the shell turns that into `ViewContext.width/height`
 * for the views. A break in any hop looks identical on screen ("pages keep the launch size"), so the
 * line prints every hop's number side by side:
 *
 *   w/h      what the driver reports for the window right now (logical px)
 *   changes  how many distinct window sizes were seen this session (0 = the app never noticed a resize)
 *   viewport what the shell adopted from the window (viewpoint of the layout math)
 *   built    the height the *committed tree* was described with; equal to viewport once the rebuild
 *            has run, smaller/larger while a resize is still one frame away
 *
 * `scale` is the content scale the driver reports, i.e. the factor between window pixels and logical
 * points; a resize that changes it must not be read as a resize in logical px.
 */
private let PROBE_SIZE_INTERVAL_MS: UInt64 = 1000
private var probeSizeLastEmitMs: UInt64 = 0
private var probeSizeEmitted: Bool = false
private var probeSizeLastW: Float32 = -1.0
private var probeSizeLastH: Float32 = -1.0
private var probeSizeChanges: Int64 = 0

func probeSize(host: ShellHost): Unit {
    if (!probeActive) {
        return
    }
    let ctx = match (probeContext) {
        case Some(value) => value
        case None => return
    }
    let w = ctx.viewportWidth
    let h = ctx.viewportHeight
    if (w != probeSizeLastW || h != probeSizeLastH) {
        if (probeSizeLastW >= 0.0) {
            probeSizeChanges += 1
        }
        probeSizeLastW = w
        probeSizeLastH = h
    }
    let now = PerformanceClock.ticksMilliseconds()
    if (probeSizeEmitted && now - probeSizeLastEmitMs < PROBE_SIZE_INTERVAL_MS) {
        return
    }
    probeSizeEmitted = true
    probeSizeLastEmitMs = now
    let scale = ctx.displayScale
    probeEmit("size w=${w} h=${h} scale=${scale} changes=${probeSizeChanges}" +
        " viewport=${host.viewportWidth}x${host.viewportHeight}" +
        " built=${host.builtViewportWidth}x${host.builtViewportHeight}" +
        " epoch=${host.viewportEpochValue()} builds=${host.buildCount}")
}

/* ------------------------------------------------------------------ per-build resize trace */

/*
 * One line per *build* that changes either the size the tree was described with or the viewport
 * epoch — the two facts that must move together when the window is resized.
 *
 * The `size` line above samples once a second and cannot say *why* a number moved; this line is
 * event-shaped and answers the two questions the resize investigation actually asks:
 *
 *   build#N   how many times `buildShell` has described the tree this session. A resize must add at
 *             least one; a stale, cached tree shows a number that never moves.
 *   size=WxH  the `ViewContext.width/height` the newest tree was built with (`built=`, not the live
 *             window). After a resize this must equal `viewport=`.
 *   viewport= the size the shell adopted from the driver; `size` != `viewport` means the rebuild is
 *             still one frame away (or that the rebuild never happened at all — the device bug this
 *             line exists for).
 */
private var probeBuildLastW: Int64 = -1
private var probeBuildLastH: Int64 = -1
private var probeBuildLastEpoch: Int64 = -1
private var probeBuildLastViewportW: Int64 = -1
private var probeBuildLastViewportH: Int64 = -1

func probeBuild(host: ShellHost): Unit {
    if (!probeActive) {
        return
    }
    let epoch = host.viewportEpochValue()
    let unchanged = host.builtViewportWidth == probeBuildLastW &&
        host.builtViewportHeight == probeBuildLastH && epoch == probeBuildLastEpoch &&
        host.viewportWidth == probeBuildLastViewportW && host.viewportHeight == probeBuildLastViewportH
    if (unchanged) {
        return
    }
    probeBuildLastW = host.builtViewportWidth
    probeBuildLastH = host.builtViewportHeight
    probeBuildLastEpoch = epoch
    probeBuildLastViewportW = host.viewportWidth
    probeBuildLastViewportH = host.viewportHeight
    probeEmit("build#${host.buildCount} size=${host.builtViewportWidth}x${host.builtViewportHeight}" +
        " epoch=${epoch} viewport=${host.viewportWidth}x${host.viewportHeight}")
}

/* ------------------------------------------------------------------ hosted frame failures */

/*
 * A hosted step swallows a recoverable frame failure into CUI's failure collector: the process stays
 * alive, the window keeps the last frame, and input (dispatched after build/layout) stops arriving —
 * a "frozen" app with no log line. `DesktopApp.takeHostedFailure()` (CUI-P07) exposes those
 * exceptions; this reports the first few with the route that produced them.
 */
private let PROBE_FAILURE_LIMIT: Int64 = 40
private var probeFailureCount: Int64 = 0

func probeFailure(route: String, failure: ?Exception): Unit {
    if (!probeActive) {
        return
    }
    match (failure) {
        case Some(error) =>
            probeFailureCount += 1
            if (probeFailureCount <= PROBE_FAILURE_LIMIT) {
                probeEmit("fail n=${probeFailureCount} route='${route}' error='${error}'")
            }
        case None => ()
    }
}

/* ------------------------------------------------------------------ ArkUI surface push (one line) */

/*
 * Reports one applied ArkUI push: the pixel size the XComponent was laid out at and the display
 * density it was measured with (docs/DEVICE-NOTES.md §24).
 *
 * This is the first half of the resize evidence and it exists to separate two failures that look
 * identical on screen: `changes=0` in the `size` line with no `push` line at all means the page never
 * reached the host (ArkTS/NAPI side), while a `push` line without a following `build#N` means the host
 * got the number and SDL refused to adopt it. Density is printed as a milli value so a fractional
 * density (1.125 on the external panel) is readable without float formatting.
 *
 * `pixel` is what the window manager laid out; the logical viewport is `pixel / density`, which is
 * printed too because that is the number the layout actually used.
 */
func probeDisplayPush(
    pixelWidth: Int64, pixelHeight: Int64, densityMilli: Int64, adoptedWidth: Int64, adoptedHeight: Int64
): Unit {
    if (!probeActive) {
        return
    }
    let push = DisplayPush(pixelWidth, pixelHeight, Float32(densityMilli) / Float32(1000.0))
    probeEmit("push size=${pixelWidth}x${pixelHeight} density=${densityMilli}per1000" +
        " logical=${push.logicalWidth()}x${push.logicalHeight()}" +
        " adopted=${adoptedWidth}x${adoptedHeight}")
}

private func probeState(ctx: UiContext): String {
    let modifiers = ctx.eventModifiers()
    // `raw` is the SDL cursor position with no logical scaling applied. CUI divides incoming
    // coordinates by the window scale, so raw/event is exactly the factor it used: if they disagree
    // the pointer is hitting a different widget than the one the operator sees under the cursor.
    let physical = Mouse.state(scale: 1.0)
    "down=${ctx.leftMouseDown} mouse=${ctx.mouseX},${ctx.mouseY} raw=${physical.x},${physical.y}" +
        " buttons=0x${physical.buttons} focus='${ctx.focusId}' hover='${ctx.hoverId}'" +
        " pressed='${ctx.pressedId}' mods=${modifiers.raw}"
}

/* ------------------------------------------------------------------ sandbox preferences (one line) */

/*
 * Reports where the shell resolved `ui-prefs.json` and whether its last write reached the disk.
 *
 * Preferences are written during a build, so by the second host frame the first attempt has already
 * happened. Before this line existed a failed write was invisible: the file kept an old `route`, the
 * next launch opened the default view, and nothing anywhere said why (docs/DEVICE-NOTES.md §6).
 */
func probePrefs(path: String, ok: Bool, error: String, route: String): Unit {
    if (!probeActive) {
        return
    }
    probeEmit("prefs path='${path}' wrote=${ok} route='${route}' error='${error}'")
}

/* ------------------------------------------------------------------------- surface + frame timing */
/*
 * One report per phase: this is what tells apart "the device renders 2880x1620 logical" from "the
 * port renders 1930x1020" and "a frame costs 3ms" from "a frame costs 25ms".
 *
 * A hosted `step()` does not only render: when nothing is dirty it ends by *waiting* for the next
 * event (CUI caps that wait at 250ms). Raw step time therefore says nothing about frame cost — an
 * idle app "takes" 250ms per step and renders nothing. The monotonic renderer text counters are used
 * as the discriminator: an unchanged counter pair means the step only waited, a changed pair means it
 * built, laid out and drew. The active bucket's *minimum* is the tightest frame this window saw.
 */
func probeCounters(): UInt64 {
    match (probeContext) {
        case Some(ctx) => ctx.renderer.textMeasureCount() + ctx.renderer.textDrawCount()
        case None => UInt64(0)
    }
}

/* Text measure/shape work, the part of a frame that scales with the amount of text on screen. */
func probeTextWork(): UInt64 {
    match (probeContext) {
        case Some(ctx) => ctx.renderer.textMeasureCount()
        case None => UInt64(0)
    }
}

func probeFrame(started: UInt64, ended: UInt64, countersBefore: UInt64, textBefore: UInt64,
    partialDamage: Bool, cost: HostedFrameCost): Unit {
    probeFrames += 1
    if (probeFrames % PROBE_FLAG_RECHECK_FRAMES == 0) {
        probeRefresh()
    }
    if (!probeActive) {
        return
    }
    let frequency = PerformanceClock.frequency()
    if (frequency == 0) {
        return
    }
    let elapsedMs = Float64(ended - started) * 1000.0 / Float64(frequency)
    // "drawn" is decided by the frame's own cost, not by the renderer text counters: a frame that
    // repaints a retained scene issues no new text work, and a frame that only waited issues no work
    // at all. `elapsed` deliberately stays the *step* wall time (it is what the pre-CUI-P03 probe
    // reported, so old and new logs are comparable) — a step that waited for input is not frame cost,
    // and `costavg` beside it is.
    let active = cost.totalNs() > UInt64(0) || probeCounters() != countersBefore
    if (active) {
        probeActiveSamples.add(elapsedMs)
        probeCostSamples.add(Float64(cost.totalNs()) / NANOS_PER_MILLI)
        probeTextSamples.add(Float64(probeTextWork() - textBefore))
        probePhaseAdd(cost)
    } else {
        probeIdleSamples.add(elapsedMs)
    }
    if (probeActiveSamples.size + probeIdleSamples.size < PROBE_FRAME_WINDOW) {
        return
    }
    let activeTimes = probeActiveSamples.toArray()
    let idleTimes = probeIdleSamples.toArray()
    let costTimes = probeCostSamples.toArray()
    let textCounts = probeTextSamples.toArray()
    let phaseLine = probePhaseLine()
    probeActiveSamples = ArrayList<Float64>()
    probeIdleSamples = ArrayList<Float64>()
    probeCostSamples = ArrayList<Float64>()
    probeTextSamples = ArrayList<Float64>()
    probeEmit("step#${probeFrames} drawn=${activeTimes.size} ${probeTiming("drawn", activeTimes)}" +
        " cost=${probeTiming("cost", costTimes)}" +
        " idle=${idleTimes.size} ${probeTiming("idle", idleTimes)}" +
        " textPerFrame=${probeMean(textCounts)} partial=${partialDamage} ${probeSurfaceReport()}")
    probeEmit("phases ${phaseLine}")
}

/* Accumulates one drawn frame's phase split (CUI-P03 `app.lastFrameCost()`). */
private func probePhaseAdd(cost: HostedFrameCost): Unit {
    probePhaseTotals[0] += Int64(cost.buildNs)
    probePhaseTotals[1] += Int64(cost.layoutNs)
    probePhaseTotals[2] += Int64(cost.eventNs)
    probePhaseTotals[3] += Int64(cost.semanticsNs)
    probePhaseTotals[4] += Int64(cost.beginNs)
    probePhaseTotals[5] += Int64(cost.treeNs)
    probePhaseTotals[6] += Int64(cost.resolveNs)
    probePhaseTotals[7] += Int64(cost.presentNs)
    probePhaseTotals[8] += cost.events
    probePhaseTotals[9] += if (cost.partialDamage) {
        1
    } else {
        0
    }
    probePhaseFrames += 1
}

/*
 * Averages the accumulated phases over the drawn frames into one line.
 *
 * This is the number `docs/DEVICE-NOTES.md` §3 lacked: a 250ms frame can be a build storm, a layout
 * storm, a thousand text draws, or a slow GL ES2 submit, and only the split says which. Reset on
 * read, like the timing samples beside it.
 */
private func probePhaseLine(): String {
    let frames = max(Int64(1), probePhaseFrames)
    let names = ["build", "layout", "event", "semantics", "begin", "tree", "resolve", "present", "events", "partial"]
    let text = StringBuilder()
    text.append("frames=${probePhaseFrames}")
    var index = 0
    while (index < PROBE_PHASE_SLOTS) {
        let average = Float64(probePhaseTotals[index]) / Float64(frames)
        if (index < 8) {
            text.append(" ${names[index]}=${round2(average / NANOS_PER_MILLI)}ms")
        } else {
            text.append(" ${names[index]}=${round2(average)}")
        }
        index += 1
    }
    probePhaseTotals = zeroPhaseTotals()
    probePhaseFrames = 0
    text.toString()
}

private func zeroPhaseTotals(): Array<Int64> {
    Array<Int64>(PROBE_PHASE_SLOTS, repeat: 0)
}

private func probeMean(values: Array<Float64>): String {
    if (values.isEmpty()) {
        return "-"
    }
    var total = 0.0
    for (value in values) {
        total += value
    }
    "${round2(total / Float64(values.size))}"
}

private func probeTiming(label: String, values: Array<Float64>): String {
    if (values.isEmpty()) {
        return "${label}avg=- min=- p95=-"
    }
    var total = 0.0
    for (value in values) {
        total += value
    }
    sort(values, by: {left, right => compareFloats(left, right)})
    "${label}avg=${round2(total / Float64(values.size))}ms min=${round2(values[0])}ms" +
        " p95=${round2(values[percentileIndex(values.size, 0.95)])}ms"
}

/* Reported once at the first event and repeated in every frame line, so a resize mid-session is
 * visible without extra plumbing (window events never reach the widget tree). */
private func probeSurfaceReport(): String {
    match (probeContext) {
        case Some(ctx) =>
            let renderer = ctx.renderer
            "vp=${ctx.viewportWidth}x${ctx.viewportHeight} scale=${ctx.displayScale}" +
                " font=${ctx.fontScale} driver=${renderer.driverName()} super=${renderer.supersampleFactor()}" +
                " text=measure${renderer.textMeasureCount()}/shape${renderer.textShapeCount()}" +
                "/draw${renderer.textDrawCount()}"
        case None => "vp=unknown"
    }
}

private func probeDescribeContext(ctx: UiContext, tag: String): Unit {
    if (!probeActive) {
        return
    }
    probeEmit("ctx ${tag} ${probeSurfaceReport()}")
}

/*
 * Zero-sized widget that hands the probe the session's `UiContext` on the very first frame.
 *
 * `probeEvent` used to be the only capture point, which made every size/timing line depend on the
 * operator moving the pointer first — exactly the wrong dependency for a resize investigation, where
 * the interesting moment is "launch, then maximise, without touching the app".
 */
class ProbeContextView <: Widget {
    public init() {
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size.zero()
    }

    public func layout(ctx: UiContext, _: Rect): Unit {
        probeCaptureContext(ctx)
    }

    public func draw(_: UiContext): Unit {}

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }

    public func participatesInLayout(): Bool {
        false
    }

    public func needsDetachedLayout(): Bool {
        true
    }
}

/* Records the session context once; inert (one Bool test) while the probe is off. */
func probeCaptureContext(ctx: UiContext): Unit {
    if (!probeActive) {
        return
    }
    if (probeContext.isNone()) {
        probeContext = Some(ctx)
        probeDescribeContext(ctx, "first-frame")
    }
}

private func percentileIndex(size: Int64, fraction: Float64): Int64 {
    let index = Int64(Float64(size) * fraction)
    if (index >= size) {
        size - 1
    } else if (index < 0) {
        0
    } else {
        index
    }
}

private func compareFloats(left: Float64, right: Float64): Ordering {
    if (left < right) {
        Ordering.LT
    } else if (left > right) {
        Ordering.GT
    } else {
        Ordering.EQ
    }
}

private func round2(value: Float64): Float64 {
    let scaled = Int64(value * 100.0 + 0.5)
    Float64(scaled) / 100.0
}
