package textura.shell

import std.collection.*
import std.unicode.*
import textura.core.data.*

/*
 * `src/modules/appshell/captureParser.ts` — the pure capture syntax parser.
 *
 *   #标签      several, CJK/latin/digits/underscore/hyphen
 *   @场景      several, the first one becomes `gtd.context`
 *   !高能/!低能/!中能 (also !high/!low/!medium)   gtd.energy
 *   /今天 /明天 /后天 /本周 /下周 /周一…/周日   gantt.end
 *
 * Tokens are stripped from the title; a string made only of syntax tokens has no title
 * and therefore cannot be submitted. The date computation is anchored on `ViewContext.today`
 * (never the wall clock) so the desktop port keeps parity determinism.
 */

public class ParsedCapture {
    public let raw: String
    public let title: String
    public let tags: Array<String>
    public let contexts: Array<String>
    public let context: ?String
    public let energy: ?Energy
    public let datePhrase: ?String
    public let date: ?String
    public let hasContent: Bool

    public init(
        raw: String,
        title: String,
        tags: Array<String>,
        contexts: Array<String>,
        context: ?String,
        energy: ?Energy,
        datePhrase: ?String,
        date: ?String,
        hasContent: Bool
    ) {
        this.raw = raw
        this.title = title
        this.tags = tags
        this.contexts = contexts
        this.context = context
        this.energy = energy
        this.datePhrase = datePhrase
        this.date = date
        this.hasContent = hasContent
    }
}

/** `parseCapture(input, now)` with `today` as the frozen local date key. */
public func parseCapture(input: String, today: String): ParsedCapture {
    let raw = input
    let runes = raw.toRuneArray()
    let titleParts = StringBuilder()
    let tags = ArrayList<String>()
    let contexts = ArrayList<String>()
    var energy: ?Energy = None
    var datePhrase: ?String = None
    var index = 0
    while (index < runes.size) {
        let rune = runes[index]
        let atBoundary = index == 0 || isCaptureSpace(runes[index - 1])
        if (atBoundary && (rune == r'#' || rune == r'@' || rune == r'!' || rune == r'/')) {
            let start = index + 1
            var end = start
            while (end < runes.size && isCaptureTokenRune(runes[end])) {
                end += 1
            }
            let token = String(runes[start..end])
            let consumed = match (rune) {
                case r'#' =>
                    if (token.isEmpty()) {
                        false
                    } else {
                        if (!tags.contains(token)) {
                            tags.add(token)
                        }
                        true
                    }
                case r'@' =>
                    if (token.isEmpty()) {
                        false
                    } else {
                        if (!contexts.contains(token)) {
                            contexts.add(token)
                        }
                        true
                    }
                case r'!' =>
                    let found = normalizeCaptureEnergy(token)
                    match (found) {
                        case Some(value) =>
                            if (energy.isNone()) {
                                energy = Some(value)
                            }
                            true
                        case None => false
                    }
                case r'/' =>
                    if (isCaptureDatePhrase(token) && datePhrase.isNone()) {
                        datePhrase = Some(token)
                        true
                    } else {
                        false
                    }
                case _ => false
            }
            if (consumed) {
                titleParts.append(" ")
                index = end
                continue
            }
        }
        titleParts.append(String([rune]))
        index += 1
    }
    let title = collapseCaptureSpaces(titleParts.toString())
    let date: ?String = match (datePhrase) {
        case Some(phrase) => Some(resolveDatePhrase(phrase, today))
        case _ => None
    }
    ParsedCapture(
        raw,
        title,
        tags.toArray(),
        contexts.toArray(),
        if (contexts.isEmpty()) {
            None
        } else {
            Some(contexts[0])
        },
        energy,
        match (datePhrase) {
            case Some(phrase) => Some("/${phrase}")
            case None => None
        },
        date,
        !title.isEmpty()
    )
}

func isCaptureSpace(rune: Rune): Bool {
    let code = Int64(UInt32(rune))
    if (code == 0x09 || code == 0x0A || code == 0x0B || code == 0x0C || code == 0x0D) {
        return true
    }
    if (code == 0x20 || code == 0xA0 || code == 0x1680) {
        return true
    }
    if (code >= 0x2000 && code <= 0x200A) {
        return true
    }
    return code == 0x2028 || code == 0x2029 || code == 0x202F || code == 0x205F || code == 0x3000
}

/** `[\p{L}\p{N}_-]+` from the Web regexes. */
func isCaptureTokenRune(rune: Rune): Bool {
    rune.isLetter() || rune.isNumber() || rune == r'_' || rune == r'-'
}

func collapseCaptureSpaces(value: String): String {
    let runes = value.toRuneArray()
    let out = StringBuilder()
    var pendingSpace = false
    for (rune in runes) {
        if (isCaptureSpace(rune)) {
            pendingSpace = true
        } else {
            if (pendingSpace && out.size > 0) {
                out.append(" ")
            }
            out.append(String([rune]))
            pendingSpace = false
        }
    }
    out.toString()
}

func normalizeCaptureEnergy(token: String): ?Energy {
    let lower = token.toAsciiLower()
    match (lower) {
        case "高能" | "high" => Some(Energy.High)
        case "低能" | "low" => Some(Energy.Low)
        case "中能" | "medium" => Some(Energy.Medium)
        case _ => None
    }
}

func isCaptureDatePhrase(token: String): Bool {
    match (token) {
        case "今天" | "明天" | "后天" | "本周" | "下周" => true
        case "周一" | "周二" | "周三" | "周四" | "周五" | "周六" | "周日" | "周天" => true
        case _ => false
    }
}

/** `resolveDatePhrase` (captureParser.ts:87-112) on local date keys. */
public func resolveDatePhrase(phrase: String, today: String): String {
    match (phrase) {
        case "今天" => today
        case "明天" => addDaysToKey(today, 1)
        case "后天" => addDaysToKey(today, 2)
        case "本周" => endOfWeekKey(today)
        case "下周" => addDaysToKey(endOfWeekKey(today), 7)
        case _ =>
            let weekday = captureWeekday(phrase)
            let current = match (parseDateKey(Some(today))) {
                case Some(millis) => dayOfWeek(millis)
                case None => Int64(0)
            }
            let target = match (weekday) {
                case Some(value) => value
                case None => Int64(0)
            }
            let diff = floorModulo(target - current, 7)
            addDaysToKey(today, diff)
    }
}

func captureWeekday(phrase: String): ?Int64 {
    let runes = phrase.toRuneArray()
    if (runes.size < 2) {
        return None
    }
    let last = String([runes[runes.size - 1]])
    match (last) {
        case "一" => Some(1)
        case "二" => Some(2)
        case "三" => Some(3)
        case "四" => Some(4)
        case "五" => Some(5)
        case "六" => Some(6)
        case "日" | "天" => Some(0)
        case _ => None
    }
}

func floorModulo(value: Int64, modulus: Int64): Int64 {
    let remainder = value % modulus
    if (remainder < 0) {
        remainder + modulus
    } else {
        remainder
    }
}
