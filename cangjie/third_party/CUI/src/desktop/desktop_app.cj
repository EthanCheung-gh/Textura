package cui.desktop

import std.collection.ArrayList
import std.env.getCommandLine
import std.sync.Mutex
import sdl.{FrameInfo, Key, MouseButton, Rect, RenderPass, SdlWindow, UiEvent, UiEventRecord, WindowSpec, SdlException}
import sdl.input.{Cursor, SystemCursor}
import sdl.dialogs.FileDialogOptions
import sdl.dialogs.FileDialogRequest
import sdl.dialogs.FileDialogs
import sdl.system.AppMetadata
import sdl.system.ApplicationMetadata
import sdl.system.SdlHintSetting
import sdl.system.SdlHints
import cui.core.{AccessibilityAdapter, CursorShape, FrameSchedule, FrameScheduler, RetainedFrameDamage,
    RetainedGraphDiagnostics, StateStore, Theme, UiContext, UiFailureCollector, Widget, broadcastEvent, buildRoot,
    collectRootLayoutStateReads, collectRootPaintStateReads, commitSemanticsForStore, dispatchEventRecord,
    dispatchFrameSubscribers, drawTooltip, frameSubscriberCount, retainedGraphDiagnostics, takeRetainedFrameDamage,
    enableAutomaticComposition, useFullRetainedExecution, useIncrementalRetainedExecution, withFrameScheduler}

// Long enough for the first paint to settle and for background work started at launch
// (dialog-free examples fetch data on worker threads) to land in the frame.
private let SNAPSHOT_SETTLE_FRAMES: UInt64 = 48
private let MAX_STABILIZATION_PASSES: Int64 = 3
// SDL_WaitEventTimeout is a blocking foreign call. Bounding it avoids occupying a Cangjie M:N
// carrier indefinitely and also drains posted work eventually if SDL rejects a rare wake event.
private let MAX_EVENT_WAIT_MS: Int32 = 250
/*
 * Bounded wait used when an embedding host owns the tick (`beginHostedRun`).
 *
 * CUI's blocking `run()` loop is the thread that has nothing else to do, so a 250ms wait there is
 * free. A hosted tick is not: HarmonyOS drives `step()` from the XComponent `OnFrame` callback on the
 * application's UI thread, so a 250ms block also stalls every other window-system operation queued
 * behind it. Measured on the MateBook with the 250ms wait: the app's own main thread burned ~5% CPU
 * and a system Dfx watchdog thread ~18% while the UI was completely idle.
 *
 * 16ms keeps an idle host at roughly one wake-up per display frame (measured ~2% CPU) and returns
 * control to the platform within one frame budget.
 */
private let HOSTED_MAX_EVENT_WAIT_MS: Int32 = 16
// Upper bound on input records dispatched inside one frame (see collectPendingEvents).
private let MAX_EVENTS_PER_FRAME: Int64 = 64

private enum DesktopAppLifecycle {
    | Ready
    | Running
    | Stopped
}

private class LayoutAttempt {
    let widget: Widget
    let buildNs: UInt64
    let layoutNs: UInt64
    let startGeneration: UInt64
    let endGeneration: UInt64

    init(widget: Widget, buildNs: UInt64, layoutNs: UInt64, startGeneration: UInt64, endGeneration: UInt64) {
        this.widget = widget
        this.buildNs = buildNs
        this.layoutNs = layoutNs
        this.startGeneration = startGeneration
        this.endGeneration = endGeneration
    }
}

private class StableLayout {
    let widget: Widget
    let buildNs: UInt64
    let layoutNs: UInt64
    let passes: Int64
    let generation: UInt64

    init(widget: Widget, buildNs: UInt64, layoutNs: UInt64, passes: Int64, generation: UInt64) {
        this.widget = widget
        this.buildNs = buildNs
        this.layoutNs = layoutNs
        this.passes = passes
        this.generation = generation
    }
}

/*
 * The desktop shell: owns the SDL window and runs the frame loop that incrementally rebuilds dirty
 * declarative scopes from `run`'s body, lays out, dispatches input, and draws. Idle frames are skipped — a frame is only
 * rendered on input, a `State` write, a resize, or a widget's `ctx.requestFrame()`, so time-driven
 * animation must request frames or it freezes. The loop brackets pointer dispatch with the context's
 * focus/hover/click-count protocols, routes events to open overlays before the tree, and paints the
 * tooltip and overlay passes above the tree. Resources registered with `manage` are closed in reverse
 * order, then the window — even when a widget throws out of the loop.
 */
public class DesktopApp {
    private let window: SdlWindow
    private let ctx: UiContext
    private let accessibility: DesktopAccessibilityHub
    private let frameDelay: UInt32
    private let vsync: Bool
    private let resources = ArrayList<Resource>()
    private let stateStore = StateStore()
    private let scheduler = FrameScheduler()
    private let postedActions: DesktopPostQueue
    private let closeCoordinator = CloseCoordinator()
    private let lifecycleLock = Mutex()
    private var lifecycle = DesktopAppLifecycle.Ready
    private let waitedEvents = ArrayList<UiEventRecord>()
    private let snapshotPath: ?String
    // Per-phase frame timing, enabled with `--profile`; None (and zero cost) in a normal run.
    private let profiler: ?FrameProfiler
    private let retainedDamageEnabled: Bool
    private var lastPartialDamage = false
    // Nanoseconds of the last drawn frame's begin / tree / resolve / present phases (HostedFrameCost).
    private var lastDrawSplit: (UInt64, UInt64, UInt64, UInt64) = (UInt64(0), UInt64(0), UInt64(0), UInt64(0))
    private var lastCost = HostedFrameCost.none()
    // Interaction owners as they stood when the frame started, and whether the frame's input moved
    // one of them. A frame that moved focus/pressed/drag cannot be repainted piecewise; a frame that
    // only changed hover can (see canRepaintPartially).
    private var frameFocusOwner: String = ""
    private var framePressedOwner: String = ""
    private var frameDragOwner: String = ""
    private var intrinsicPointerStateChanged = false
    private var frames: UInt64 = 0
    private var baseCursor: ?Cursor = None
    private var pointerCursor: ?Cursor = None
    private var textCursor: ?Cursor = None
    private var resizeHCursor: ?Cursor = None
    private var resizeVCursor: ?Cursor = None
    private var appliedShape: ?CursorShape = None
    // The caret rectangle last forwarded to the OS for IME anchoring (logical pixels).
    private var appliedInputAnchor: ?Rect = None
    // Cross-frame loop state. Held as fields rather than runLoop locals so the frame driver can be
    // either the blocking run() loop or an embedding host that owns the tick (see beginHostedRun).
    private var loopPreviousTick: UInt64 = 0
    private var loopLastRenderedGen: UInt64 = 0
    private var loopSchedule = FrameSchedule(immediate: true, deadlineMs: None)
    private var loopRenderedWidth: Int32 = -1
    private var loopRenderedHeight: Int32 = -1
    // Set only between beginHostedRun and endHostedRun.
    private var hostedBody: ?(() -> Unit) = None
    private var hostedFailures: ?UiFailureCollector = None

    public init(
        spec: WindowSpec,
        theme!: Theme = Theme.light(),
        frameDelay!: UInt32 = UInt32(16),
        fontScale!: Float32 = 1.0,
        metadata!: ?AppMetadata = None,
        hints!: Array<SdlHintSetting> = [],
        maxPendingPosts!: Int64 = 4096
    ) {
        this.postedActions = DesktopPostQueue(maxPendingPosts)
        this.window = configuredWindow(spec, metadata, hints)
        this.ctx = UiContext(window.renderer, theme)
        this.accessibility = DesktopAccessibilityHub(window)
        this.ctx.displayScale = window.scale * window.currentPixelDensity
        this.ctx.fontScale = max(0.1, fontScale)
        this.frameDelay = frameDelay
        this.vsync = spec.vsync
        this.snapshotPath = snapshotArgument()
        scheduler.assertOwnerThread()
        enableAutomaticComposition(stateStore)
        let forceFullRetained = fullRetainedExecutionEnabled()
        if (forceFullRetained) {
            useFullRetainedExecution(stateStore)
        } else {
            useIncrementalRetainedExecution(stateStore)
        }
        this.retainedDamageEnabled = !forceFullRetained && !retainedDamageDisabled()
        this.profiler = if (profileEnabled()) {
            Some(FrameProfiler(60))
        } else {
            None
        }
        if (accessibility.hasNativeBridge()) {
            ctx.setAccessibilityAdapter(accessibility)
        }
    }

    /** Registers a resource to be closed on shutdown, in reverse registration order. */
    public func manage(resource: Resource): Unit {
        ensureUiAccess("manage resources")
        resources.add(resource)
    }

    /**
     * Prevents the user from shrinking the window below `width` x `height` logical
     * pixels. Layouts do not reflow below their design minimum, so resizable windows
     * should set one to keep content from being squeezed off screen.
     */
    public func setMinimumSize(width: Int32, height: Int32): Unit {
        ensureUiAccess("set the minimum window size")
        window.setMinimumSize(width, height)
    }

    /**
     * Sets the window's resting cursor — the shape shown wherever no control asks for a
     * different one. Applications wanting a themed base pointer (for example a crosshair
     * over a drawing canvas) call this instead of activating a cursor directly, so the
     * hover-driven shapes (a hand over buttons, an I-beam over text) still layer on top.
     */
    public func useBaseCursor(kind: SystemCursor): Unit {
        ensureUiAccess("change the base cursor")
        match (baseCursor) {
            case Some(existing) => existing.close()
            case None => ()
        }
        baseCursor = createCursor(kind)
        appliedShape = None
        applyDesiredCursor()
    }

    /** Runs several UI-state writes as one visual invalidation. Must be called on the UI thread. */
    public func batch(action: () -> Unit): Unit {
        ensureUiAccess("batch UI state")
        withFrameScheduler(scheduler, {=> scheduler.transaction(action)})
    }

    /** Captures the last committed retained execution graph for profiling and bug reports. */
    public func retainedDiagnostics(): RetainedGraphDiagnostics {
        ensureUiAccess("inspect retained diagnostics")
        retainedGraphDiagnostics(stateStore)
    }

    /** Whether the current/most recently drawn frame used automatic retained partial damage. */
    public func lastFrameUsedPartialDamage(): Bool {
        ensureUiAccess("inspect retained frame damage")
        lastPartialDamage
    }

    /**
     * Per-phase cost of the most recently drawn frame.
     *
     * The `--profile` reporter above needs a desktop command line, which an embedding host (the
     * HarmonyOS SDL port) does not have. This accessor is the hosted equivalent: it is filled on
     * every drawn frame, so a host can attribute a slow frame to build, layout, input, semantics or
     * a draw/present phase in its own diagnostics instead of guessing from wall time.
     */
    public func lastFrameCost(): HostedFrameCost {
        ensureUiAccess("inspect hosted frame cost")
        lastCost
    }

    /**
     * Runs `action` as one visual invalidation on whichever thread the caller is on.
     *
     * A store/observer callback is usually reached from the UI thread while an input event or a
     * build is running: running the action immediately keeps the caused repaint inside the *same*
     * frame, which is what a click handler needs (one frame of latency instead of two). A callback
     * reached from a worker thread must not touch the thread-confined `State`s, so it is handed to
     * `post` instead and drained at the next frame boundary.
     */
    public func deliver(action: () -> Unit): Unit {
        if (scheduler.ownsCurrentThread()) {
            withFrameScheduler(scheduler, {=> scheduler.transaction(action)})
        } else if (!post(action)) {
            // Capacity or shutdown: the action is dropped rather than run on the wrong thread.
            // The next frame still reflects the underlying store write when something else
            // invalidates the tree, and postStats() reports the refusal to the host.
            ()
        }
    }

    /**
     * Installs an external semantic-tree observer without replacing the native accessibility bridge.
     * A rejected bootstrap quarantines only the observer and rethrows its exception to this caller.
     */
    public func setAccessibilityAdapter(adapter: AccessibilityAdapter): Unit {
        ensureUiAccess("install an accessibility adapter")
        accessibility.setExternalAdapter(adapter)
        ctx.setAccessibilityAdapter(accessibility)
        match (accessibility.takeExternalBootstrapFailure()) {
            case Some(error) => throw error
            case None => ()
        }
    }

    /** Installs a non-blocking UI-thread callback for isolated accessibility delivery failures. */
    public func setAccessibilityFailureHandler(handler: (AccessibilityFailure) -> Unit): Unit {
        ensureUiAccess("install an accessibility failure handler")
        accessibility.setFailureHandler(handler)
    }

    /** Returns and clears accessibility failures retained for deterministic diagnostics. */
    public func takeAccessibilityFailures(): Array<AccessibilityFailure> {
        ensureUiAccess("inspect accessibility failures")
        accessibility.takeFailures()
    }

    /**
     * Queues an action from any thread. False means it was not queued (capacity reached or stopped).
     * A wake failure does not revoke admission: bounded event waits still drain accepted work.
     */
    public func post(action: () -> Unit): Bool {
        let (accepted, needsWake) = postedActions.add(action)
        if (needsWake && !window.wake()) {
            postedActions.noteWakeFailure()
        }
        accepted
    }

    /** Thread-safe queue diagnostics, including capacity refusals and native wake failures. */
    public func postStats(): DesktopPostStats {
        postedActions.stats()
    }

    /** Installs a UI-thread asynchronous close confirmation; None restores immediate acceptance. */
    public func setCloseRequestHandler(handler: ?(CloseRequest) -> Unit): Unit {
        ensureUiAccess("set the close request handler")
        closeCoordinator.setHandler(handler)
    }

    /** Requests normal closing through the installed confirmation handler. */
    public func requestClose(): Unit {
        closeCoordinator.request({=> ensureUiAccess("resolve a close request")}, {=> ctx.requestClose()})
    }

    /** Drops all local values created by `rememberState` before the next rebuild. */
    public func clearRememberedState(): Unit {
        batch(
            {
                =>
                    stateStore.clear()
                    scheduler.invalidate()
            }
        )
    }

    /** Opens the native open-file dialog; poll the returned request each frame for the result. */
    public func openFileDialog(options!: FileDialogOptions = FileDialogOptions()): FileDialogRequest {
        ensureUiAccess("open a file dialog")
        FileDialogs.openFile(options: options, window: Some(window))
    }

    /** Opens the native save-file dialog; poll the returned request each frame for the result. */
    public func saveFileDialog(options!: FileDialogOptions = FileDialogOptions()): FileDialogRequest {
        ensureUiAccess("open a save dialog")
        FileDialogs.saveFile(options: options, window: Some(window))
    }

    /** Opens the native pick-folder dialog; poll the returned request each frame for the result. */
    public func openFolderDialog(options!: FileDialogOptions = FileDialogOptions()): FileDialogRequest {
        ensureUiAccess("open a folder dialog")
        FileDialogs.openFolder(options: options, window: Some(window))
    }

    /*
     * Runs the frame loop until close: each rendered frame reuses clean declarative scopes and rebuilds
     * dirty paths from `body`, then lays out, dispatches input, and draws. Blocks until the window closes; managed resources
     * and the window are released deterministically even when a widget throws out of the loop. One
     * DesktopApp owns one window lifecycle, so run may be called only once.
     */
    public func run(body: () -> Unit): Unit {
        beginRun()
        let failures = UiFailureCollector()
        try {
            failures.run({=> withFrameScheduler(scheduler, {=> runLoop(body)})})
        } finally {
            // Every stage runs even after another stage fails. A fatal Error still propagates;
            // recoverable Exceptions are reported together after ownership has been released.
            failures.run({=> markStoppedAndDiscardPosts()})
            failures.run({=> closeManagedResources()})
            failures.run({=> accessibility.close()})
            failures.run({=> stateStore.clear()})
            failures.run({=> window.close()})
        }
        failures.raiseIfAny()
    }

    /*
     * Starts a frame loop whose tick is owned by an embedding host instead of by CUI.
     *
     * run() blocks inside CUI's own loop, which does not fit a host that calls back once per frame:
     * the HarmonyOS SDL port, for example, drives SDL_AppIterate from the XComponent OnFrame
     * callback on the only thread permitted to touch the surface. In hosted mode the caller passes
     * the same declarative root as run(), then calls step() exactly once per host frame and
     * endHostedRun() when the host stops.
     *
     * Like run(), this may be called only once per DesktopApp. Do not mix the two on one app.
     */
    public func beginHostedRun(body: () -> Unit): Unit {
        beginRun()
        hostedBody = body
        hostedFailures = UiFailureCollector()
        resetLoopState()
    }

    /*
     * Advances exactly one hosted frame, returning whether the loop should continue: false once the
     * window asked to close, or when the app was not started with beginHostedRun. Recoverable frame
     * failures are collected and surfaced by endHostedRun instead of being thrown out of a host
     * callback, where nothing could catch them.
     */
    public func step(): Bool {
        let body = match (hostedBody) {
            case Some(hosted) => hosted
            case None => return false
        }
        let failures = match (hostedFailures) {
            case Some(collector) => collector
            case None => return false
        }
        ensureUiAccess("step")
        failures.run({=> withFrameScheduler(scheduler, {=> stepFrame(body)})})
        !ctx.shouldClose
    }

    /*
     * Releases everything a hosted run owns, mirroring the teardown run() performs when its loop
     * exits. Idempotent: once the run has ended, later calls do nothing.
     */
    public func endHostedRun(): Unit {
        let failures = match (hostedFailures) {
            case Some(collector) => collector
            case None => return
        }
        failures.run({=> markStoppedAndDiscardPosts()})
        failures.run({=> closeManagedResources()})
        failures.run({=> accessibility.close()})
        failures.run({=> stateStore.clear()})
        failures.run({=> window.close()})
        hostedBody = None
        hostedFailures = None
        failures.raiseIfAny()
    }

    private func runLoop(body: () -> Unit): Unit { // cjcheck-ignore: long-function # one visible frame transaction; helpers own waiting and stabilization details
        match (profiler) {
            case Some(_) => println(
                "[profile] 渲染后端 ${ctx.renderer.driverName()}｜超采样 ${ctx.renderer.supersampleFactor()}x｜视口 ${window.width}x${window.height} @ ${window.scale}x")
            case None => ()
        }
        resetLoopState()
        while (!ctx.shouldClose) {
            stepFrame(body)
        }
    }

    /* Seeds the cross-frame loop state. Shared by run() and beginHostedRun(). */
    private func resetLoopState(): Unit {
        loopPreviousTick = window.ticks()
        loopLastRenderedGen = scheduler.generation
        loopSchedule = FrameSchedule(immediate: true, deadlineMs: None)
        loopRenderedWidth = -1
        loopRenderedHeight = -1
    }

    /*
     * Advances exactly one frame: polls input, rebuilds dirty paths from `body`, lays out,
     * dispatches, and draws when the frame is dirty, then hands control back to its driver.
     * The cross-frame state lives in fields, so the driver may be either the blocking run()
     * loop or an embedding host that owns the tick.
     */
    private func stepFrame(body: () -> Unit): Unit {
        let frame = nextFrame(loopPreviousTick)
        loopPreviousTick = frame.elapsedMs
        ctx.frame = frame
        let events = collectPendingEvents()
        let viewportW = window.width
        let viewportH = window.height
        ctx.viewportWidth = Float32(viewportW)
        ctx.viewportHeight = Float32(viewportH)
        scheduler.transaction(
            {
                =>
                    drainPostedActions()
                    accessibility.drainActions()
            }
        )
        let stateGen = scheduler.generation
        let forced = snapshotPath.isSome() || profiler.isSome()
        let timerTriggered = loopSchedule.isDue(frame.elapsedMs)
        let stateTriggered = stateGen != loopLastRenderedGen
        let resized = viewportW != loopRenderedWidth || viewportH != loopRenderedHeight
        let mustRender = timerTriggered || !events.isEmpty() || stateTriggered || resized || forced
        // A step that does not draw reports no cost (`lastFrameCost` would otherwise repeat the
        // previous drawn frame's numbers, which reads as "every idle step rendered" in a host log).
        lastCost = HostedFrameCost.none()

        if (mustRender) {
            let costBuildStart = hostedNow()
            // Measure and route input on the same raster grid as the upcoming render pass.
            ctx.renderer.prepareTextLayout(Float32(viewportW), Float32(viewportH))
            match (profiler) {
                case Some(_) => ctx.renderer.resetTextMeasureCount()
                case None => ()
            }
            let costLayoutStart = hostedNow()
            var stable = buildAndLayoutStable(body, viewportW, viewportH)
            let costEventStart = hostedNow()
            var eventNs = UInt64(0)
            frameFocusOwner = ctx.focusId
            framePressedOwner = ctx.pressedId
            frameDragOwner = ctx.dragId
            for (record in events) {
                eventNs += dispatchInputEvent(stable.widget, record)
                stable = reflectStateChanges(stable, body, viewportW, viewportH)
            }
            eventNs += dispatchFrameTick(frame)
            stable = reflectStateChanges(stable, body, viewportW, viewportH)
            intrinsicPointerStateChanged = ctx.focusId != frameFocusOwner || ctx.pressedId != framePressedOwner ||
                ctx.dragId != frameDragOwner
            let costSemanticsStart = hostedNow()
            let semanticsStart = frameProfileTimestamp(profiler)
            commitSemanticsForStore(ctx, stateStore)
            let semanticsNs = frameProfileTimestamp(profiler) - semanticsStart
            let costDrawStart = hostedNow()
            frames += 1
            loopLastRenderedGen = stable.generation // writes made during draw intentionally schedule the next frame
            let allowPartialDamage = canRepaintPartially(stateTriggered, events, timerTriggered, resized)
            let frameDamage = takeRetainedFrameDamage(stateStore,
                Rect(0.0, 0.0, Float32(viewportW), Float32(viewportH)), allowPartialDamage)
            let (beginNs, treeNs, resolveNs, presentNs) = draw(stable.widget, frameDamage)
            lastCost = HostedFrameCost(
                costLayoutStart - costBuildStart,
                costEventStart - costLayoutStart,
                costSemanticsStart - costEventStart,
                costDrawStart - costSemanticsStart,
                lastDrawSplit[0],
                lastDrawSplit[1],
                lastDrawSplit[2],
                lastDrawSplit[3],
                Int64(events.size),
                lastPartialDamage
            )
            loopSchedule = ctx.takeFrameSchedule()
            loopRenderedWidth = viewportW
            loopRenderedHeight = viewportH
            match (profiler) {
                case Some(p) => p.record(
                    FrameProfileSample(
                        FramePhaseTimes(stable.buildNs, stable.layoutNs, eventNs, semanticsNs, beginNs, treeNs,
                            resolveNs, presentNs),
                        FrameProfileSignals(stable.passes, !events.isEmpty(), stateTriggered, timerTriggered,
                            resized, forced, frameSubscriberCount(stateStore), lastPartialDamage),
                        FrameTextCounts(ctx.renderer.textMeasureCount(), ctx.renderer.textComputeCount(),
                            ctx.renderer.textShapeCount(), ctx.renderer.textDrawCount())
                    )
                )
                case None => ()
            }
        }
        waitForWork(loopSchedule, frame.elapsedMs, scheduler.generation != loopLastRenderedGen)
    }

    /*
     * Whether this frame may repaint through retained partial damage.
     *
     * CUI's original rule demanded `events.isEmpty()`, i.e. "any input at all repaints the whole
     * window". On a 1930x1020 software-rasterised HarmonyOS surface that is 250ms per pointer move:
     * a hover turns into a queue of full repaints and the UI feels frozen.
     *
     * The rule is now stated as what actually has to hold. A repaint may be limited to the damaged
     * retained region when *every* reason to paint but one is absent and the input that arrived can
     * only have changed hover: no mouse press/release, no wheel, no key, no text, and the focus,
     * pressed and drag owners are unchanged across the frame. Anything else — a press that can move
     * focus, a scroll that can clip, a resize, a timer — keeps the conservative full frame, and a
     * frame with no retained damage hint at all still falls back to full damage inside
     * `takeRetainedFrameDamage`.
     */
    private func canRepaintPartially(
        stateTriggered: Bool,
        events: ArrayList<UiEventRecord>,
        timerTriggered: Bool,
        resized: Bool
    ): Bool {
        if (!retainedDamageEnabled || timerTriggered || resized || snapshotPath.isSome() ||
            frameSubscriberCount(stateStore) != 0 || ctx.hasOverlay() || !ctx.dragId.isEmpty()) {
            return false
        }
        if (stateTriggered) {
            // A state write owns the frame only when no input arrived, as before (CUI-P01 behaviour).
            return events.isEmpty() && ctx.hoverId.isEmpty() && ctx.focusId.isEmpty() && ctx.pressedId.isEmpty()
        }
        if (events.isEmpty()) {
            return false
        }
        // Input-only frame: it may be repainted piecewise iff the input cannot have changed anything
        // but hover. Pointer moves are the whole set; presses settle focus and presses.
        if (intrinsicPointerStateChanged) {
            return false
        }
        for (record in events) {
            match (record.event) {
                case UiEvent.MouseMove(_, _) => ()
                case _ => return false
            }
        }
        true
    }

    private func dispatchInputEvent(widget: Widget, record: UiEventRecord): UInt64 {
        let eventStart = frameProfileTimestamp(profiler)
        scheduler.transaction({
            => dispatchEventRecord(record, ctx, {event => preparePointer(event)}, {
                event => routeEvent(widget, event)
            }, {event => completePointer(event)})
        })
        frameProfileTimestamp(profiler) - eventStart
    }

    private func dispatchFrameTick(frame: FrameInfo): UInt64 {
        let eventStart = frameProfileTimestamp(profiler)
        scheduler.transaction({=> dispatchFrameSubscribers(stateStore, ctx, frame)})
        frameProfileTimestamp(profiler) - eventStart
    }

    private func reflectStateChanges(
        stable: StableLayout,
        body: () -> Unit,
        viewportW: Int32,
        viewportH: Int32
    ): StableLayout {
        if (scheduler.generation == stable.generation) {
            return stable
        }
        let reflected = buildAndLayoutStable(body, viewportW, viewportH)
        StableLayout(reflected.widget, stable.buildNs + reflected.buildNs, stable.layoutNs + reflected.layoutNs,
            stable.passes + reflected.passes, reflected.generation)
    }

    private func buildAndLayoutStable(body: () -> Unit, viewportW: Int32, viewportH: Int32): StableLayout {
        var attempt = buildAndLayoutOnce(body, viewportW, viewportH)
        var buildNs = attempt.buildNs
        var layoutNs = attempt.layoutNs
        var passes: Int64 = 1
        while (attempt.startGeneration != attempt.endGeneration && passes < MAX_STABILIZATION_PASSES) {
            attempt = buildAndLayoutOnce(body, viewportW, viewportH)
            buildNs += attempt.buildNs
            layoutNs += attempt.layoutNs
            passes += 1
        }
        if (attempt.startGeneration != attempt.endGeneration) {
            // A build/layout side effect that never stabilizes must not spin forever. Keep the
            // newest complete tree and ask for another frame; profiling exposes the extra passes.
            ctx.requestFrame()
        }
        StableLayout(attempt.widget, buildNs, layoutNs, passes, attempt.endGeneration)
    }

    private func buildAndLayoutOnce(body: () -> Unit, viewportW: Int32, viewportH: Int32): LayoutAttempt {
        let startGeneration = scheduler.generation
        ctx.clearActiveOverlay()
        ctx.clearSemantics()
        let buildStart = frameProfileTimestamp(profiler)
        let widget = buildRoot(body, stateStore)
        let layoutStart = frameProfileTimestamp(profiler)
        stateStore.adoptFocus(ctx)
        collectRootLayoutStateReads(stateStore, {
            => widget.layout(ctx, Rect(0.0, 0.0, Float32(viewportW), Float32(viewportH)))
        })
        ctx.settleModalFocus()
        let layoutEnd = frameProfileTimestamp(profiler)
        LayoutAttempt(widget, layoutStart - buildStart, layoutEnd - layoutStart, startGeneration, scheduler.generation)
    }

    private func drainPostedActions(): Unit {
        // Reentrant producers cannot keep one frame inside this loop indefinitely.
        if (postedActions.drain(256)) {
            ctx.requestFrame()
        }
    }

    private func waitForWork(schedule: FrameSchedule, frameStartedMs: UInt64, dirtyState: Bool): Unit {
        if (ctx.shouldClose) {
            return
        }
        let forced = snapshotPath.isSome() || profiler.isSome()
        if (schedule.immediate || dirtyState || forced) {
            // Present already blocks on vertical blank when vsync is enabled. Adding the legacy
            // 16ms delay there roughly halves the refresh rate, so only pace an un-synchronised loop.
            if (!vsync && frameDelay > UInt32(0)) {
                let elapsed = tickDelta(frameStartedMs, window.ticks())
                if (elapsed < UInt64(frameDelay)) {
                    window.delay(UInt32(UInt64(frameDelay) - elapsed))
                }
            }
            return
        }

        let now = window.ticks()
        // Hosted ticks block briefly (see HOSTED_MAX_EVENT_WAIT_MS); CUI's own loop uses MAX_EVENT_WAIT_MS.
        let timeout = eventWaitTimeout(schedule, now, if (hostedBody.isSome()) {
            HOSTED_MAX_EVENT_WAIT_MS
        } else {
            MAX_EVENT_WAIT_MS
        })
        match (window.waitEventRecordTimeout(timeout)) {
            case Some(record) => match (record.event) {
                case UiEvent.Wake => ()
                case _ =>
                    waitedEvents.add(record)
                    // Merge the rest of the burst this wake-up belongs to into the same frame. A
                    // pointer drag delivers dozens of motion records back to back; dispatching them
                    // one per frame turns a 250ms repaint into a 250ms queue, while all of them
                    // describe one pointer position anyway. Order is preserved: the blocking record
                    // is queued first, then whatever SDL already has.
                    mergeQueuedEvents()
            }
            case None => () // timer deadline elapsed
        }
    }

    /* Queues every already-pending record for the upcoming frame, up to the per-frame bound. */
    private func mergeQueuedEvents(): Unit {
        var current = window.pollEventRecord()
        while (let Some(record) <- current) {
            match (record.event) {
                case UiEvent.Wake => ()
                case _ =>
                    if (Int64(waitedEvents.size) >= MAX_EVENTS_PER_FRAME) {
                        return // the remainder stays in SDL; the next frame drains it
                    }
                    waitedEvents.add(record)
            }
            current = window.pollEventRecord()
        }
    }

    // Polls every event SDL has queued into a buffer, so the render decision can tell whether any input
    // arrived before deciding whether to build a frame at all. Dispatch is deferred (see below).
    // At most MAX_EVENTS_PER_FRAME records go into one frame: the rest stay queued (SDL + waitedEvents)
    // and the frame asks for its successor immediately, so a flood is drained over several frames
    // instead of stalling one.
    private func collectPendingEvents(): ArrayList<UiEventRecord> {
        let events = ArrayList<UiEventRecord>()
        while (!waitedEvents.isEmpty() && Int64(events.size) < MAX_EVENTS_PER_FRAME) {
            events.add(waitedEvents.remove(at: 0))
        }
        var deferred = !waitedEvents.isEmpty()
        var current = window.pollEventRecord()
        while (let Some(record) <- current) {
            match (record.event) {
                case UiEvent.Wake => ()
                case _ =>
                    if (Int64(events.size) >= MAX_EVENTS_PER_FRAME) {
                        waitedEvents.add(record)
                        deferred = true
                        break
                    }
                    events.add(record)
            }
            current = window.pollEventRecord()
        }
        if (deferred) {
            ctx.requestFrame()
        }
        events
    }

    /*
     * Routes one input event. Window-level events belong to the shell and are handled
     * before the overlays, so a modal dialog can neither swallow a quit request nor keep
     * the logical size stale through a resize. The open overlays (dropdowns, menus,
     * dialogs) then see the event before the tree, top-most first — a click inside a
     * popup is not stolen by the dialog or control drawn underneath it, and a dialog
     * consumes whatever its popups decline, protecting the backdrop tree. Pointer
     * bookkeeping brackets BOTH paths: click counting and hover resolution run for
     * overlay-hosted controls (a Modal's fields) exactly as for tree controls, keeping
     * double-clicks and cursor shapes alive there.
     */
    private func routeEvent(widget: Widget, event: UiEvent): Unit {
        if (handleWindowEvent(event)) {
            return
        }
        match (event) {
            case UiEvent.MouseMove(_, _) =>
                // Resolve which control the pointer is over, then reflect its requested
                // shape in the system cursor. Bracketing keeps hover single-winner.
                ctx.beginHoverTest()
                if (!ctx.dispatchOverlay(event)) {
                    dispatchEvent(widget, event)
                }
                ctx.settleHover()
                applyDesiredCursor()
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                // Click counting runs before any dispatch so controls can read it while
                // handling the press, wherever the press lands.
                ctx.recordPress(x, y)
                if (ctx.dispatchOverlay(event)) {
                    return // popups and dialogs manage focus themselves
                }
                // A primary press in the tree either moves focus to the claiming control
                // or blurs the current one, matching desktop conventions.
                ctx.beginPointerPress()
                dispatchEvent(widget, event)
                ctx.settleFocusAfterPress()
            case UiEvent.KeyDown(Key.Tab, _) =>
                if (ctx.dispatchOverlay(event)) {
                    return
                }
                // Tab traversal is a shell responsibility: it walks the build-order
                // focus ring and is not forwarded to the focused control, so a text
                // field cannot swallow it. Shift reverses direction.
                if (ctx.eventModifiers().shift) {
                    ctx.focusPrevious()
                } else {
                    ctx.focusNext()
                }
            case _ =>
                if (!ctx.dispatchOverlay(event)) {
                    dispatchEvent(widget, event)
                }
        }
    }

    private func handleWindowEvent(event: UiEvent): Bool {
        match (event) {
            case UiEvent.Quit => requestClose()
            case UiEvent.WindowCloseRequested => requestClose()
            case UiEvent.WindowResized(_, _) =>
                // The SDL wrapper already refreshed while decoding; query once more so custom
                // injected events preserve the same authoritative-size contract.
                let _ = window.refreshSize() // cjcheck-ignore: ignore-result # width/height are consumed at the next loop boundary
                scheduler.invalidate()
            case UiEvent.WindowDisplayScaleChanged => refreshGuiDisplayScale()
            case UiEvent.WindowPixelSizeChanged(_, _) => refreshGuiDisplayScale()
            case UiEvent.WindowExposed => scheduler.invalidate()
            case UiEvent.WindowRestored => scheduler.invalidate()
            case UiEvent.RenderTargetsReset => scheduler.invalidate()
            case UiEvent.RenderDeviceReset => scheduler.invalidate()
            case UiEvent.RenderDeviceLost => scheduler.invalidate()
            case UiEvent.WindowFocusLost => ctx.cancelTransientInput()
            case _ => return false
        }
        true
    }

    private func refreshGuiDisplayScale(): Unit {
        ctx.displayScale = window.scale * window.currentPixelDensity
        scheduler.invalidate()
    }

    // Draws one frame, returning the nanosecond durations of its sub-phases (scene begin, tree draw,
    // supersample resolve, present) for the profiler. The timestamps are a handful of clock reads —
    // negligible against a frame — so they run unconditionally and only the profiler, when enabled,
    // records them.
    private func draw(widget: Widget, damage: RetainedFrameDamage): (UInt64, UInt64, UInt64, UInt64) {
        let t0 = frameProfileTimestamp(profiler)
        let hostBeginStart = hostedNow()
        let (pass, activeDamage) = beginFramePass(damage)
        // Report the backend decision, not merely the framework's damage plan. A renderer
        // may safely fall back to a full frame when its persistent target is unavailable.
        lastPartialDamage = activeDamage.isSome()
        ctx.setRetainedDamage(activeDamage)
        let t1 = frameProfileTimestamp(profiler)
        let hostTreeStart = hostedNow()
        var t2 = t1
        try {
            drawFrameContents(widget)
            t2 = frameProfileTimestamp(profiler)
        } finally {
            ctx.setRetainedDamage(None)
            pass.close()
        }
        let hostResolveStart = hostedNow()
        let t3 = frameProfileTimestamp(profiler)
        maybeSnapshot()
        let hostPresentStart = hostedNow()
        ctx.renderer.present()
        if (frames == UInt64(1) && !ctx.shouldClose) {
            // Window creation, font initialization and first layout happen off screen.
            // Present before showing so the compositor never sees an unfinished backbuffer.
            window.show()
            ctx.requestFrame() // redraw after native show/DPI/expose changes, even on an otherwise idle UI
        }
        let hostEnd = hostedNow()
        let t4 = frameProfileTimestamp(profiler)
        // Unconditional split for the host-facing HostedFrameCost; `resolve` is the target resolve
        // plus the supersample downsample, `present` the backend submit and swap.
        lastDrawSplit = (hostTreeStart - hostBeginStart, hostResolveStart - hostTreeStart,
            hostPresentStart - hostResolveStart, hostEnd - hostPresentStart)
        (t1 - t0, t2 - t1, t3 - t2, t4 - t3)
    }

    private func beginFramePass(damage: RetainedFrameDamage): (RenderPass, ?Rect) {
        match (damage) {
            case RetainedFrameDamage.Region(rect) =>
                let pass = ctx
                    .renderer
                    .beginRenderPassDamage(Float32(window.width), Float32(window.height), ctx.theme.bg, rect)
                (pass, if (pass.damagePreserved) {
                        Some(rect)
                    } else {
                        None
                    })
            case RetainedFrameDamage.FullFrame => (ctx
                    .renderer
                    .beginRenderPass(Float32(window.width), Float32(window.height), ctx.theme.bg), None)
        }
    }

    private func drawFrameContents(widget: Widget): Unit {
        ctx.clearTooltip()
        ctx.clearTextInputAnchor()
        collectRootPaintStateReads(stateStore, {=> widget.draw(ctx)})
        if (!ctx.hasOverlay()) {
            drawTooltip(ctx, Float32(window.width), Float32(window.height))
        }
        ctx.drawActiveOverlay()
        applyTextInputAnchor()
    }

    /*
     * Forwards the focused caret rectangle to the OS whenever it moves, so the IME
     * composition UI (candidate window) follows typing instead of sitting in a screen
     * corner. Unchanged rectangles are skipped to avoid a per-frame system call, and a
     * platform refusal is ignored — IME anchoring is polish, not frame-critical.
     */
    private func applyTextInputAnchor(): Unit {
        match (ctx.textInputAnchorRect()) {
            case Some(anchor) =>
                if (!sameAnchorRect(appliedInputAnchor, anchor)) {
                    appliedInputAnchor = Some(anchor)
                    try {
                        window.setTextInputArea(anchor)
                    } catch (_: SdlException) {
                        // A refused anchor must not stay cached as applied, or a transient
                        // platform failure would silence IME anchoring for the whole session.
                        appliedInputAnchor = None
                    }
                }
            case None => ()
        }
    }

    // Snapshot mode: `main.exe --snapshot <path.bmp>` renders a few frames so the UI
    // settles, writes the frame to a BMP, then quits. Handy for visual tests and docs.
    private func maybeSnapshot(): Unit {
        match (snapshotPath) {
            case Some(path) where frames >= SNAPSHOT_SETTLE_FRAMES =>
                ctx.renderer.captureBmp(path)
                ctx.requestClose()
            case _ => ()
        }
    }

    // Root dispatch: there is no widget behind the tree root, so the consumed flag has no
    // further recipient and the broadcast form documents that intentionally dropped result.
    private func dispatchEvent(widget: Widget, event: UiEvent): Unit {
        broadcastEvent(widget, ctx, event)
    }

    // Applies the hovered control's requested shape, skipping the SDL call when it is
    // already active. Cursor feedback is non-critical polish: a platform that refuses a
    // shape simply keeps the current cursor rather than failing the frame.
    private func applyDesiredCursor(): Unit {
        let shape = ctx.desiredCursor()
        match (appliedShape) {
            case Some(current) where current == shape => return
            case _ => ()
        }
        appliedShape = Some(shape)
        match (cursorForShape(shape)) {
            case Some(cursor) => try {
                cursor.setActive()
            } catch (_: SdlException) {
                // A refused shape must not stay cached as applied, or the same shape could
                // never be retried; the platform simply keeps the current cursor this frame.
                appliedShape = None
            }
            case None => ()
        }
    }

    private func cursorForShape(shape: CursorShape): ?Cursor {
        match (shape) {
            case CursorShape.Default => ensureCursor(SystemCursor.Default)
            case CursorShape.Interactive => ensurePointerCursor()
            case CursorShape.Text => ensureTextCursor()
            case CursorShape.ResizeH => ensureResizeHCursor()
            case CursorShape.ResizeV => ensureResizeVCursor()
        }
    }

    private func ensureCursor(kind: SystemCursor): ?Cursor {
        match (baseCursor) {
            case Some(cursor) => Some(cursor)
            case None =>
                baseCursor = createCursor(kind)
                baseCursor
        }
    }

    private func ensurePointerCursor(): ?Cursor {
        match (pointerCursor) {
            case Some(cursor) => Some(cursor)
            case None =>
                pointerCursor = createCursor(SystemCursor.Pointer)
                pointerCursor
        }
    }

    private func ensureTextCursor(): ?Cursor {
        match (textCursor) {
            case Some(cursor) => Some(cursor)
            case None =>
                textCursor = createCursor(SystemCursor.Text)
                textCursor
        }
    }

    private func ensureResizeHCursor(): ?Cursor {
        match (resizeHCursor) {
            case Some(cursor) => Some(cursor)
            case None =>
                resizeHCursor = createCursor(SystemCursor.EwResize)
                resizeHCursor
        }
    }

    private func ensureResizeVCursor(): ?Cursor {
        match (resizeVCursor) {
            case Some(cursor) => Some(cursor)
            case None =>
                resizeVCursor = createCursor(SystemCursor.NsResize)
                resizeVCursor
        }
    }

    private func createCursor(kind: SystemCursor): ?Cursor {
        try {
            let cursor = Cursor.system(kind)
            resources.add(cursor)
            Some(cursor)
        } catch (_: Exception) {
            None
        }
    }

    private func nextFrame(previousTick: UInt64): FrameInfo {
        let currentTick = window.ticks()
        FrameInfo(currentTick, tickDelta(previousTick, currentTick))
    }

    private func preparePointer(event: UiEvent): Unit {
        match (event) {
            case UiEvent.MouseMove(x, y) => rememberMouse(x, y)
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                rememberMouse(x, y)
                ctx.leftMouseDown = true
            case UiEvent.MouseUp(MouseButton.Left, x, y) => rememberMouse(x, y)
            case UiEvent.DropFile(_, x, y) => rememberMouse(x, y)
            case UiEvent.DropText(_, x, y) => rememberMouse(x, y)
            case UiEvent.DropPosition(x, y) => rememberMouse(x, y)
            case _ => ()
        }
    }

    private func completePointer(event: UiEvent): Unit {
        match (event) {
            case UiEvent.MouseUp(MouseButton.Left, _, _) =>
                ctx.leftMouseDown = false
                ctx.clearDrag()
                ctx.clearPress()
            case _ => ()
        }
    }

    private func rememberMouse(x: Float32, y: Float32): Unit {
        ctx.mouseX = x
        ctx.mouseY = y
    }

    private func closeManagedResources(): Unit {
        closeResourcesInReverse(resources)
    }

    /* Throws `IllegalStateException` when the public one-run lifecycle contract is violated. */
    private func beginRun(): Unit {
        ensureUiAccess("run")
        var accepted = false
        synchronized(lifecycleLock) {
            match (lifecycle) {
                case DesktopAppLifecycle.Ready =>
                    lifecycle = DesktopAppLifecycle.Running
                    accepted = true
                case _ => ()
            }
        }
        if (!accepted) {
            throw IllegalStateException("DesktopApp.run may only be called once")
        }
    }

    /*
     * Guards every UI-affine public operation. Throws `IllegalStateException` after shutdown or
     * when the caller is not the scheduler's owner thread.
     */
    private func ensureUiAccess(operation: String): Unit {
        var stopped = false
        synchronized(lifecycleLock) {
            match (lifecycle) {
                case DesktopAppLifecycle.Stopped => stopped = true
                case _ => ()
            }
        }
        if (stopped) {
            throw IllegalStateException("DesktopApp cannot ${operation} after run has stopped")
        }
        scheduler.assertOwnerThread()
    }

    private func markStoppedAndDiscardPosts(): Unit {
        synchronized(lifecycleLock) {
            postedActions.stop()
            lifecycle = DesktopAppLifecycle.Stopped
        }
        closeCoordinator.stop()
        ctx.resetModalFocus()
    }
}

internal func closeResourcesInReverse(resources: ArrayList<Resource>): Unit {
    let failures = UiFailureCollector()
    var index = resources.size - 1
    while (index >= 0) {
        let resource = resources[index]
        failures.run({
            => if (!resource.isClosed()) {
            resource.close()
        }
        })
        index -= 1
    }
    resources.clear()
    failures.raiseIfAny()
}

internal func eventWaitTimeout(schedule: FrameSchedule, now: UInt64, cap: Int32): Int32 {
    match (schedule.deadlineMs) {
        case Some(deadline) =>
            if (deadline <= now) {
                Int32(0)
            } else {
                Int32(min(deadline - now, UInt64(cap)))
            }
        case None => cap
    }
}

internal func frameProfileTimestamp(profiler: ?FrameProfiler): UInt64 {
    match (profiler) {
        case Some(_) => FrameProfiler.now()
        case None => UInt64(0)
    }
}

private func sameAnchorRect(applied: ?Rect, next: Rect): Bool {
    match (applied) {
        case Some(rect) => rect.x == next.x && rect.y == next.y && rect.w == next.w && rect.h == next.h
        case None => false
    }
}

internal func tickDelta(previousTick: UInt64, currentTick: UInt64): UInt64 {
    if (currentTick >= previousTick) {
        currentTick - previousTick
    } else {
        UInt64(0)
    }
}

private func snapshotArgument(): ?String {
    let args = getCommandLine()
    var i = 0
    while (i < args.size - 1) {
        if (args[i] == "--snapshot") {
            return Some(args[i + 1])
        }
        i += 1
    }
    None
}

// True when `--profile` is on the command line, turning on per-phase frame timing.
private func profileEnabled(): Bool {
    for (arg in getCommandLine()) {
        if (arg == "--profile") {
            return true
        }
    }
    false
}

// Debug/E2E switch: execute retained bodies and phases every frame for differential comparison.
private func fullRetainedExecutionEnabled(): Bool {
    for (arg in getCommandLine()) {
        if (arg == "--cui-force-full-retained") {
            return true
        }
    }
    false
}

// Diagnostic escape hatch for full-frame A/B checks without disabling other retained phases.
private func retainedDamageDisabled(): Bool {
    for (arg in getCommandLine()) {
        if (arg == "--cui-disable-retained-damage") {
            return true
        }
    }
    false
}

private func configuredWindow(spec: WindowSpec, metadata: ?AppMetadata, hints: Array<SdlHintSetting>): SdlWindow {
    match (metadata) {
        case Some(value) => ApplicationMetadata.apply(value)
        case None => ()
    }
    SdlHints.apply(hints)
    SdlWindow(spec, hidden: true)
}
