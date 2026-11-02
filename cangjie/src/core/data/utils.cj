package textura.core.data

import std.collection.*
import std.overflow.*
import std.random.*

/** FNV-1a 64-bit digest; the parity tooling depends on this exact value. */
public func fnv1a64(bytes: Array<Byte>): UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for (index in 0..bytes.size) {
        hash = (hash ^ UInt64(bytes[index])).wrappingMul(0x100000001b3)
    }
    hash
}

public func fnv1a64(text: String): UInt64 {
    fnv1a64(text.toArray())
}

/** `1 item` / `2 items`; Chinese copy usually uses the count + measure word form. */
public func plural(count: Int64, singular: String, plural: String): String {
    if (count == 1) {
        "${count} ${singular}"
    } else {
        "${count} ${plural}"
    }
}

public func clampInt(value: Int64, lower: Int64, upper: Int64): Int64 {
    if (value < lower) {
        lower
    } else if (value > upper) {
        upper
    } else {
        value
    }
}

public func clampFloat(value: Float64, lower: Float64, upper: Float64): Float64 {
    if (value < lower) {
        lower
    } else if (value > upper) {
        upper
    } else {
        value
    }
}

/** `Math.round` semantics: half values go up, including negatives. */
public func roundHalfUp(value: Float64): Int64 {
    if (value != value) {
        return 0
    }
    if (value < 0.0) {
        -Int64(-value + 0.5)
    } else {
        Int64(value + 0.5)
    }
}

/** `Math.round(value)` rendered as `12%`. */
public func percent(value: Float64): String {
    "${roundHalfUp(value)}%"
}

/**
 * Area color palette copied from `src/core/utils.ts`.
 *
 * This is persisted domain data (`Area.color`), not a design token, so it lives
 * in core instead of `textura.ui`.
 */
public let AREA_PALETTE: Array<String> = [
    "#C0663A", "#5B7C99", "#7C8A5D", "#9B6A8F", "#B08A3E", "#5E8A82", "#8A6B52", "#6C6FA0"
]

public func areaPalette(index: Int64): String {
    let size = AREA_PALETTE.size
    let normalized = if (index < 0) {
        ((index % size) + size) % size
    } else {
        index % size
    }
    AREA_PALETTE[normalized]
}

/** Short random id: `prefix_xxxxxxxxxx`, 10 alphanumeric characters. */
public func uid(prefix: String, random: Random): String {
    let alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
    let out = StringBuilder()
    var index = 0
    while (index < 10) {
        let value = Int64(random.nextUInt64() % 36)
        out.append(alphabet[value..value + 1])
        index += 1
    }
    "${prefix}_${out.toString()}"
}

/**
 * Package-level random source used only by the convenience overload below.
 * NOT reproducible: parity code must pass its own seeded `Random`
 * (`AppStore` does), otherwise ids differ between runs.
 */
private let defaultRandom = Random()

/**
 * Convenience id generator for tools/tests. **Not reproducible** (shared PRNG);
 * use `uid(prefix, random)` when determinism matters.
 */
public func uid(prefix!: String = "i"): String {
    uid(prefix, defaultRandom)
}

/** `done / total` as an integer percentage; 0 when there are no children. */
public func childCompletion(children: Array<Item>): Int64 {
    if (children.isEmpty()) {
        return 0
    }
    var done = 0
    for (item in children) {
        if (item.isDone()) {
            done += 1
        }
    }
    roundHalfUp(Float64(done) * 100.0 / Float64(children.size))
}

/**
 * Workspaces are immutable, so a "clone" is the same value. Kept for parity with
 * `cloneWorkspace` call sites (undo/redo snapshots need nothing else).
 */
public func cloneWorkspace(workspace: Workspace): Workspace {
    workspace
}

/**
 * String ordering is UTF-8 byte order, not ICU collation. The Web build calls
 * `localeCompare()`, whose default locale only differs for accented/non-CJK
 * text; every ordering the domain needs (ISO timestamps, ids, `YYYY-Qn`) is
 * ASCII, where both agree.
 */
public func compareText(left: String, right: String): Int64 {
    if (left == right) {
        return 0
    }
    if (left < right) {
        -1
    } else {
        1
    }
}

/** `String.prototype.trim()` equivalent for the ASCII whitespace we accept. */
public func trimmed(text: String): String {
    text.trimAscii()
}

public func isEmptyText(text: ?String): Bool {
    match (text) {
        case Some(value) => value.trimAscii().isEmpty()
        case None => true
    }
}

/**
 * Splits a tag input on commas (ASCII + full width) and whitespace, drops
 * leading `#`, de-duplicates while preserving first-seen order.
 */
public func parseTags(input: String): Array<String> {
    let seen = HashMap<String, Bool>()
    let result = ArrayList<String>()
    let cleaned = input.replace("，", " ").replace(",", " ")
    for (raw in cleaned.split(" ")) {
        var tag = raw.trimAscii()
        while (tag.size > 0 && tag[0] == UInt8(35)) {
            tag = tag[1..tag.size].trimAscii()
        }
        if (tag.isEmpty()) {
            continue
        }
        match (seen.get(tag)) {
            case Some(_) => ()
            case None =>
                seen[tag] = true
                result.add(tag)
        }
    }
    result.toArray()
}

/** Joins tags back into the space-separated edit-string used by forms. */
public func joinTags(tags: Array<String>): String {
    let out = StringBuilder()
    for (index in 0..tags.size) {
        if (index > 0) {
            out.append(" ")
        }
        out.append(tags[index])
    }
    out.toString()
}
