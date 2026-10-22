package textura.shell

import std.convert.*

/** Parsed parity CLI. The CUI runtime also inspects the raw argv for the
 * `--snapshot` bitmap switch, so do not remove that flag before `app.run`. */
public class CliOptions {
    public var workspace: ?String = None
    public var route: Route = Route.Dashboard
    public var theme: String = "light"
    /** True when argv contained `--route`; the remembered route must not override it. */
    public var routeExplicit: Bool = false
    /** True when argv contained `--theme`; the remembered theme must not override it. */
    public var themeExplicit: Bool = false
    public var width: Int64 = 1440
    public var height: Int64 = 900
    public var snapshot: ?String = None
    public var exitAfterFrame: Bool = false
    public var today: ?String = None
    public var font: String = "Noto Sans CJK SC"
    public var help: Bool = false
    public var error: ?String = None

    public init() {}
}

public func usageText(): String {
    """
usage: textura --workspace <workspace.json> --route <dashboard|calendar|okr|gtd|gantt|sop|settings> --theme <light|dark> --width 1440 --height 900 --snapshot <out.png> [--exit] [--today YYYY-MM-DD] [--font <family>]

  --workspace  parity workspace exported by tools/parity/capture_ref.mjs
  --route      which top-level view to render (dashboard|calendar|okr|gtd|gantt|sop|settings)
  --theme      light (warm paper) or dark
  --width      logical window width, default 1440
  --height     logical window height, default 900
  --snapshot   write a deterministic PNG and exit after the frame settles
  --exit       close after the first stable frame (snapshot implies this)
  --today      frozen "today" anchor; defaults to workspace.updatedAt date
  --font       UI font family, default Noto Sans CJK SC
  --help       print this message
"""
}

public func parseCli(args: Array<String>): CliOptions {
    let options = CliOptions()
    var index: Int64 = 1
    while (index < args.size) {
        let arg = args[index]
        if (arg == "--workspace") {
            if (index + 1 < args.size) {
                options.workspace = Some(args[index + 1])
                index += 1
            } else {
                options.error = Some("--workspace requires a path")
            }
        } else if (arg == "--route") {
            if (index + 1 < args.size) {
                match (parseRoute(args[index + 1])) {
                    case Some(route) =>
                        options.route = route
                        options.routeExplicit = true
                    case None => options.error = Some("unknown route: ${args[index + 1]}")
                }
                index += 1
            } else {
                options.error = Some("--route requires a value")
            }
        } else if (arg == "--theme") {
            if (index + 1 < args.size) {
                let value = args[index + 1]
                if (value == "light" || value == "dark") {
                    options.theme = value
                    options.themeExplicit = true
                } else {
                    options.error = Some("--theme must be light or dark")
                }
                index += 1
            } else {
                options.error = Some("--theme requires a value")
            }
        } else if (arg == "--width" || arg == "--height") {
            if (index + 1 < args.size) {
                match (Int64.tryParse(args[index + 1])) {
                    case Some(value) =>
                        if (value < 320 || value > 4096) {
                            options.error = Some("${arg} must be between 320 and 4096")
                        } else if (arg == "--width") {
                            options.width = value
                        } else {
                            options.height = value
                        }
                    case None => options.error = Some("${arg} requires an integer")
                }
                index += 1
            } else {
                options.error = Some("${arg} requires a value")
            }
        } else if (arg == "--snapshot") {
            if (index + 1 < args.size) {
                options.snapshot = Some(args[index + 1])
                index += 1
            } else {
                options.error = Some("--snapshot requires an output path")
            }
        } else if (arg == "--exit") {
            options.exitAfterFrame = true
        } else if (arg == "--today") {
            if (index + 1 < args.size) {
                options.today = Some(args[index + 1])
                index += 1
            } else {
                options.error = Some("--today requires YYYY-MM-DD")
            }
        } else if (arg == "--font") {
            if (index + 1 < args.size) {
                options.font = args[index + 1]
                index += 1
            } else {
                options.error = Some("--font requires a family name")
            }
        } else if (arg == "--help" || arg == "-h") {
            options.help = true
        }
        index += 1
    }
    options
}
