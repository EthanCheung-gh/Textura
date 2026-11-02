package textura.shell

import std.collection.ArrayList
import std.env.*
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import textura.ui.isPrimaryPointerButton

/*
 * Source gate: a control may not decode the pointer button by itself.
 *
 * Why it exists: on the HarmonyOS device a primary press can arrive as
 * `MouseDown(RawCode(0))` or `MouseDown(RawCode(1))` instead of `MouseButton.Left` (the touch
 * backend maps SDL's "unknown"/"left" codes that way, see docs/DEVICE-NOTES.md §1 and §4.4),
 * so a handler written as `case UiEvent.MouseDown(MouseButton.Left, …)` silently does nothing
 * while hover and scrolling keep working. `textura.ui.isPrimaryPointerButton` accepts
 * `Left | RawCode(0) | RawCode(1)` and is the only decoder the tree may use for presses.
 *
 * Release events are matched with a wildcard (`MouseUp(_, x, y)`): the button code of a
 * release is not worth trusting when the press that armed the gesture already passed the
 * primary check, and a release that never reaches its owner leaves a control stuck pressed.
 *
 * The scan is over the production sources only (every .cj file under src, excluding
 * `*_test.cj`), so it also catches a new view that hand-rolls its own press handling.
 * Comment lines are skipped: the decoder's own documentation names the pattern it replaces.
 */
private func collectSources(directory: String, into: ArrayList<String>): Unit {
    let entries = try {
        Directory.readFrom(directory)
    } catch (_: Exception) {
        return
    }
    for (entry in entries) {
        let path = "${directory}/${entry.name}"
        if (entry.isDirectory()) {
            collectSources(path, into)
        } else if (entry.name.endsWith(".cj")) {
            into.add(path)
        }
    }
}

/** Whether a source line only mentions the pattern in a comment. */
private func isCommentLine(line: String): Bool {
    let trimmed = line.trimAscii()
    trimmed.startsWith("//") || trimmed.startsWith("*") || trimmed.startsWith("/*") ||
        trimmed.startsWith("///")
}

@Test
func pointerPressesGoThroughTheSharedButtonDecoder(): Unit {
    let root = match (getVariable("TEXTURA_CANGJIE_ROOT")) {
        case Some(value) => value
        case None => "."
    }
    let files = ArrayList<String>()
    collectSources("${root}/src", files)
    // A vacuously green scan (wrong root, unreadable tree) must fail loudly.
    @Expect(files.size > 100, true)
    let offenders = ArrayList<String>()
    for (path in files) {
        if (path.endsWith("_test.cj")) {
            continue
        }
        let text = try {
            String.fromUtf8(File.readFrom(path))
        } catch (_: Exception) {
            ""
        }
        var lineNumber = 0
        for (line in text.split("\n")) {
            lineNumber += 1
            if (isCommentLine(line)) {
                continue
            }
            let directDown = line.contains("MouseDown(MouseButton.")
            let directUp = line.contains("MouseUp(MouseButton.")
            if (directDown || directUp) {
                offenders.add("${path}:${lineNumber}: ${line.trimAscii()}")
            }
        }
    }
    if (!offenders.isEmpty()) {
        // One readable message listing every offender: the fix is mechanical
        // (`MouseDown(pressButton, x, y) where isPrimaryPointerButton(pressButton)`).
        @Expect(offenders.size, 0)
        for (offender in offenders) {
            @Expect(offender, "")
        }
    }
}

/** The decoder itself: desktop `Left`, device `RawCode(0|1)`, and nothing else. */
@Test
func primaryPointerDecoderAcceptsEveryBackendSpelling(): Unit {
    @Expect(isPrimaryPointerButton(MouseButton.Left), true)
    @Expect(isPrimaryPointerButton(MouseButton.RawCode(0)), true)
    @Expect(isPrimaryPointerButton(MouseButton.RawCode(1)), true)
    @Expect(isPrimaryPointerButton(MouseButton.RawCode(2)), false)
}
