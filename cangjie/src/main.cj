package textura

import cui.*
import std.fs.*
import std.env.*
import textura.core.data.*
import textura.shell.*
import textura.ui.*

/**
 * Desktop entry point + the frozen parity CLI (`docs/PARITY.md`).
 *
 * Everything the shell renders is derived from argv / the workspace document. The only
 * wall-clock reads are `AppStore`'s own timestamps on a *write*; `--snapshot` runs never
 * mutate the workspace, so two runs stay pixel-identical.
 */
main(): Int64 {
    let cli = parseCli(getCommandLine())
    if (cli.help) {
        println(usageText())
        return 0
    }
    match (cli.error) {
        case Some(message) =>
            println("textura: ${message}")
            println(usageText())
            return 2
        case None => ()
    }

    var digest: ?WorkspaceDigest = None
    match (cli.workspace) {
        case Some(path) =>
            try {
                digest = Some(inspectWorkspace(path))
            } catch (error: Exception) {
                println("textura: cannot read workspace ${path}: ${error}")
                return 2
            }
        case None => ()
    }

    configureFonts(cli.font)

    // Route/theme precedence (`routeState.ts`): explicit argv > remembered choice > default.
    // Snapshot runs ignore the remembered choice so `--snapshot` output never depends on
    // `$HOME/.textura/ui-prefs.json`.
    let prefs = ShellPreferences.load()
    let themedByPrefs = cli.snapshot.isNone() && !cli.themeExplicit &&
        (prefs.theme == "light" || prefs.theme == "dark")
    let initialTheme = if (themedByPrefs) {
        prefs.theme
    } else {
        cli.theme
    }
    var initialRoute = cli.route
    if (cli.snapshot.isNone() && !cli.routeExplicit) {
        match (parseRoute(prefs.route)) {
            case Some(value) => initialRoute = value
            case None => ()
        }
    }

    let workspacePath = match (cli.workspace) {
        case Some(value) => value
        case None => "textura-workspace.json"
    }
    // The parity anchor lives in `--today` or `workspace.updatedAt`; it must be
    // resolved *before* the store exists so the store can freeze its clock on it.
    // Without an anchor (plain interactive launch) the store explicitly uses the
    // system clock, which is the only place allowed to do so.
    let anchor: ?String = match (cli.today) {
        case Some(value) => if (isIsoDateKey(value)) {
            Some(value)
        } else {
            None
        }
        case None => match (digest) {
            case Some(value) => if (isIsoDateKey(value.anchorDate)) {
                Some(value.anchorDate)
            } else {
                None
            }
            case None => None
        }
    }
    let store = match (anchor) {
        case Some(value) => AppStore.forParity(value)
        case None => if (cli.workspace.isSome() || cli.today.isSome()) {
            // Parity intent without a usable anchor: stay deterministic (epoch)
            // instead of falling back to the host clock.
            AppStore(clock: FixedClock(0))
        } else {
            AppStore(clock: SystemClock())
        }
    }
    var loadError: ?String = None
    try {
        store.load(workspacePath)
    } catch (error: Exception) {
        loadError = Some(error.message)
    }
    store.setRoute(routeId(initialRoute))
    store.setTheme(initialTheme)

    let today = match (anchor) {
        case Some(value) => value
        case None => if (cli.workspace.isSome() || cli.today.isSome()) {
            "unknown"
        } else {
            match (loadError) {
                case Some(_) => "unknown"
                case None => store.anchorToday()
            }
        }
    }
    let runtime = ShellRuntime(prefs, store)
    let host = ShellHost(store, runtime, today, cli.snapshot.isNone(), loadError, cli.width, cli.height)

    let app = DesktopApp(
        WindowSpec("织理 · Textura", Int32(cli.width), Int32(cli.height)),
        theme: themeByName(initialTheme)
    )
    // `.shell { min-width: 1024px }` + a 640px minimum height for the chrome + one card row.
    app.setMinimumSize(1024, 640)
    // Store → CUI invalidation (see `ShellHost.revision`): without it a click changes the store and
    // the retained tree keeps rendering the previous route. `deliver` keeps a store write made on a
    // worker thread off the UI thread's States.
    host.armStoreBridge({action => app.deliver(action)})
    app.run {
        if (cli.exitAfterFrame && cli.snapshot.isNone()) {
            // FrameHandler keeps the loop awake for one extra frame, then the second frame
            // requests a normal close. Snapshot mode exits through CUI's settle-and-capture.
            let sawFrame = rememberState<Bool>("auto-exit-saw-frame") {false}
            FrameHandler(onFrame: {_ =>
                if (sawFrame.value) {
                    app.requestClose()
                } else {
                    sawFrame.value = true
                }
            }) {
                buildShell(host)
            }
        } else {
            buildShell(host)
        }
    }

    match (cli.snapshot) {
        case Some(path) =>
            if (path.endsWith(".png")) {
                try {
                    convertBmpToPng(path, path)
                } catch (error: Exception) {
                    println("textura: snapshot conversion failed: ${error}")
                    return 3
                }
            }
            if (!exists(path)) {
                println("textura: snapshot was not written: ${path}")
                return 3
            }
            println("snapshot: ${path}")
        case None => ()
    }
    0
}

/** std.fs.exists is not part of the 1.2.0 surface used by the skeleton; a read probe keeps
 * the check dependency-free. */
func exists(path: String): Bool {
    try {
        File.readFrom(path)
        true
    } catch (_: Exception) {
        false
    }
}

/** A resolver-usable `YYYY-MM-DD` anchor (parity `--today` / `workspace.updatedAt`). */
func isIsoDateKey(value: String): Bool {
    match (parseIsoMillis(value)) {
        case Some(_) => true
        case None => false
    }
}
