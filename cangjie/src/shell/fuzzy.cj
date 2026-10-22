package textura.shell

import std.collection.*
import std.sort.*
import textura.core.data.*

/*
 * `src/modules/appshell/fuzzy.ts` — scoring, ranking and recent-use ordering for the
 * command palette. The score table is copied value-for-value so a query ranks the same
 * way it does in the Web build:
 *
 *   title exact 1000 > prefix 900-… > contains 700-… > tag 500/450 > ancestor path 300
 *   command: label exact 900 > prefix 800-… > contains 600 > keyword 450/400
 *   area:    name exact 800 > prefix 700 > contains 500
 */

public let RECENT_LIMIT: Int64 = 6
public let PALETTE_ITEM_LIMIT: Int64 = 8

public class PaletteItemCandidate {
    public let id: String
    public let title: String
    public let kind: ItemKind
    public let tags: Array<String>
    public let pathTitles: Array<String>

    public init(id: String, title: String, kind: ItemKind, tags: Array<String>, pathTitles: Array<String>) {
        this.id = id
        this.title = title
        this.kind = kind
        this.tags = tags
        this.pathTitles = pathTitles
    }
}

public class PaletteCommandCandidate {
    public let id: String
    public let label: String
    public let hint: String
    public let keywords: Array<String>

    public init(id: String, label: String, hint: String, keywords: Array<String>) {
        this.id = id
        this.label = label
        this.hint = hint
        this.keywords = keywords
    }
}

public class PaletteAreaCandidate {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        this.id = id
        this.name = name
    }
}

public class PaletteRecentRef {
    public let refType: String
    public let id: String

    public init(refType: String, id: String) {
        this.refType = refType
        this.id = id
    }

    public func key(): String {
        "${refType}:${id}"
    }
}

public class MatchHit {
    public let score: Int64
    public let field: String

    public init(score: Int64, field: String) {
        this.score = score
        this.field = field
    }
}

public class RankedItem {
    public let candidate: PaletteItemCandidate
    public let hit: MatchHit

    public init(candidate: PaletteItemCandidate, hit: MatchHit) {
        this.candidate = candidate
        this.hit = hit
    }
}

public class PaletteResults {
    public let recent: Array<PaletteRecentRef>
    public let commands: Array<PaletteCommandCandidate>
    public let items: Array<RankedItem>
    public let areas: Array<PaletteAreaCandidate>

    public init(
        recent: Array<PaletteRecentRef>,
        commands: Array<PaletteCommandCandidate>,
        items: Array<RankedItem>,
        areas: Array<PaletteAreaCandidate>
    ) {
        this.recent = recent
        this.commands = commands
        this.items = items
        this.areas = areas
    }
}

func normalizeQuery(value: String): String {
    value.trimAscii().toAsciiLower()
}

/** Ranked score desc, then title byte order (`rankItems`, fuzzy.ts:114-116). */
func compareRanked(left: RankedItem, right: RankedItem): Bool {
    if (left.hit.score != right.hit.score) {
        return left.hit.score > right.hit.score
    }
    compareText(left.candidate.title, right.candidate.title) < 0
}

/** Command score desc, then declaration order (stable). */
func compareCommandScore(left: (Int64, Int64, PaletteCommandCandidate),
    right: (Int64, Int64, PaletteCommandCandidate)): Bool {
    if (left[0] != right[0]) {
        return left[0] > right[0]
    }
    left[1] < right[1]
}

/** Area score desc, then declaration order (stable). */
func compareAreaScore(left: (Int64, Int64, PaletteAreaCandidate), right: (Int64, Int64, PaletteAreaCandidate)): Bool {
    if (left[0] != right[0]) {
        return left[0] > right[0]
    }
    left[1] < right[1]
}

/** `scoreItem` (fuzzy.ts:75-99). */
public func scorePaletteItem(query: String, candidate: PaletteItemCandidate): ?MatchHit {
    let keyword = normalizeQuery(query)
    if (keyword.isEmpty()) {
        return None
    }
    let title = candidate.title.toAsciiLower()
    if (title == keyword) {
        return Some(MatchHit(1000, "title"))
    }
    if (title.startsWith(keyword)) {
        return Some(MatchHit(900 - min(Int64(Int64(title.size) - Int64(keyword.size)), 50), "title"))
    }
    match (title.indexOf(keyword)) {
        case Some(index) => return Some(MatchHit(700 - min(index, 100), "title"))
        case None => ()
    }
    for (tag in candidate.tags) {
        let lower = tag.toAsciiLower()
        if (lower == keyword) {
            return Some(MatchHit(500, "tag"))
        }
        if (lower.indexOf(keyword).isSome()) {
            return Some(MatchHit(450, "tag"))
        }
    }
    if (candidate.pathTitles.size > 1) {
        let parents = candidate.pathTitles[0..candidate.pathTitles.size - 1]
        let path = String.join(parents, delimiter: " / ").toAsciiLower()
        if (path.indexOf(keyword).isSome()) {
            return Some(MatchHit(300, "path"))
        }
    }
    None
}

/** `rankItems` (fuzzy.ts:102-118): score desc, then title by deterministic byte order. */
public func rankPaletteItems(query: String, candidates: Array<PaletteItemCandidate>): Array<RankedItem> {
    let ranked = ArrayList<RankedItem>()
    for (candidate in candidates) {
        match (scorePaletteItem(query, candidate)) {
            case Some(hit) => ranked.add(RankedItem(candidate, hit))
            case None => ()
        }
    }
    let ordered = ranked.toArray()
    sort(
        ordered,
        lessThan: compareRanked,
        stable: true
    )
    let limit = if (Int64(ordered.size) > PALETTE_ITEM_LIMIT) {
        PALETTE_ITEM_LIMIT
    } else {
        Int64(ordered.size)
    }
    ordered[0..limit]
}

/** `scoreCommand` (fuzzy.ts:121-134). */
public func scorePaletteCommand(query: String, command: PaletteCommandCandidate): ?Int64 {
    let keyword = normalizeQuery(query)
    if (keyword.isEmpty()) {
        return None
    }
    let label = command.label.toAsciiLower()
    if (label == keyword) {
        return Some(900)
    }
    if (label.startsWith(keyword)) {
        return Some(800 - min(Int64(Int64(label.size) - Int64(keyword.size)), 40))
    }
    if (label.indexOf(keyword).isSome()) {
        return Some(600)
    }
    for (item in command.keywords) {
        let lower = item.toAsciiLower()
        if (lower == keyword) {
            return Some(450)
        }
        if (lower.indexOf(keyword).isSome()) {
            return Some(400)
        }
    }
    None
}

/** `scoreArea` (fuzzy.ts:137-145). */
public func scorePaletteArea(query: String, area: PaletteAreaCandidate): ?Int64 {
    let keyword = normalizeQuery(query)
    if (keyword.isEmpty()) {
        return None
    }
    let name = area.name.toAsciiLower()
    if (name == keyword) {
        return Some(800)
    }
    if (name.startsWith(keyword)) {
        return Some(700)
    }
    if (name.indexOf(keyword).isSome()) {
        return Some(500)
    }
    None
}

/** `buildPaletteResults` (fuzzy.ts:178-207). */
public func buildPaletteResults(
    query: String,
    commands: Array<PaletteCommandCandidate>,
    items: Array<PaletteItemCandidate>,
    areas: Array<PaletteAreaCandidate>,
    recent: Array<PaletteRecentRef>
): PaletteResults {
    let keyword = query.trimAscii()
    if (keyword.isEmpty()) {
        return PaletteResults(resolveRecentRefs(recent, commands, items, areas), commands, [], [])
    }
    let matchedCommands = ArrayList<PaletteCommandCandidate>()
    let commandScores = ArrayList<(Int64, Int64, PaletteCommandCandidate)>()
    var commandIndex = 0
    for (command in commands) {
        match (scorePaletteCommand(keyword, command)) {
            case Some(score) => commandScores.add((score, commandIndex, command))
            case None => ()
        }
        commandIndex += 1
    }
    let orderedCommands = commandScores.toArray()
    sort(
        orderedCommands,
        lessThan: compareCommandScore,
        stable: true
    )
    for (entry in orderedCommands) {
        matchedCommands.add(entry[2])
    }
    let matchedAreas = ArrayList<(Int64, Int64, PaletteAreaCandidate)>()
    var areaIndex = 0
    for (area in areas) {
        match (scorePaletteArea(keyword, area)) {
            case Some(score) => matchedAreas.add((score, areaIndex, area))
            case None => ()
        }
        areaIndex += 1
    }
    let orderedAreas = matchedAreas.toArray()
    sort(
        orderedAreas,
        lessThan: compareAreaScore,
        stable: true
    )
    let areaResults = ArrayList<PaletteAreaCandidate>()
    for (entry in orderedAreas) {
        areaResults.add(entry[2])
    }
    PaletteResults([], matchedCommands.toArray(), rankPaletteItems(keyword, items), areaResults.toArray())
}

/** `resolveRecentRefs` (fuzzy.ts:148-171): drop stale refs, dedupe, cap at 6. */
public func resolveRecentRefs(
    recent: Array<PaletteRecentRef>,
    commands: Array<PaletteCommandCandidate>,
    items: Array<PaletteItemCandidate>,
    areas: Array<PaletteAreaCandidate>
): Array<PaletteRecentRef> {
    let rows = ArrayList<PaletteRecentRef>()
    let seen = HashSet<String>()
    for (ref in recent) {
        if (seen.contains(ref.key())) {
            continue
        }
        seen.add(ref.key())
        var alive = false
        match (ref.refType) {
            case "command" =>
                for (command in commands) {
                    if (command.id == ref.id) {
                        alive = true
                    }
                }
            case "item" =>
                for (item in items) {
                    if (item.id == ref.id) {
                        alive = true
                    }
                }
            case _ =>
                for (area in areas) {
                    if (area.id == ref.id) {
                        alive = true
                    }
                }
        }
        if (alive) {
            rows.add(ref)
        }
        if (Int64(rows.size) >= RECENT_LIMIT) {
            break
        }
    }
    rows.toArray()
}

/** `pushRecentRef` (fuzzy.ts:230-236): front-insert after dedupe, cap 6. */
public func pushRecentRef(ref: PaletteRecentRef, current: Array<PaletteRecentRef>): Array<PaletteRecentRef> {
    let next = ArrayList<PaletteRecentRef>()
    next.add(ref)
    for (entry in current) {
        if (entry.key() != ref.key()) {
            next.add(entry)
        }
    }
    let limit = if (Int64(next.size) > RECENT_LIMIT) {
        RECENT_LIMIT
    } else {
        Int64(next.size)
    }
    next.toArray()[0..limit]
}

/** `highlightSegments` (fuzzy.ts:215-227): first substring hit only. */
public class HighlightSegment {
    public let text: String
    public let matched: Bool

    public init(text: String, matched: Bool) {
        this.text = text
        this.matched = matched
    }
}

public func highlightSegments(text: String, query: String): Array<HighlightSegment> {
    let keyword = query.trimAscii()
    if (keyword.isEmpty()) {
        return [HighlightSegment(text, false)]
    }
    match (text.toAsciiLower().indexOf(keyword.toAsciiLower())) {
        case Some(index) =>
            let segments = ArrayList<HighlightSegment>()
            if (index > 0) {
                segments.add(HighlightSegment(text[0..index], false))
            }
            let end = index + Int64(keyword.size)
            segments.add(HighlightSegment(text[index..end], true))
            if (end < Int64(text.size)) {
                segments.add(HighlightSegment(text[end..text.size], false))
            }
            segments.toArray()
        case None => [HighlightSegment(text, false)]
    }
}
