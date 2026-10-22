package textura.core.data

import std.collection.*
import std.convert.*

/**
 * A minimal JSON model + reader/writer.
 *
 * The Cangjie 1.2 standard library ships no JSON codec, and the workspace
 * document must stay byte-compatible with `JSON.stringify(value, null, 2)` from
 * the Web build. Owning the codec here gives three things at once:
 *
 * 1. object key order is preserved (JavaScript objects behave the same way), so
 *    a load/save round trip of `tools/parity/workspace.json` is byte-stable;
 * 2. numbers keep their JSON token shape (`1` vs `1.5`) instead of being
 *    reformatted by a foreign serializer;
 * 3. unknown fields can be carried through untouched (see `codec.cj`).
 */
public enum JsonValue {
    | JsonNull
    | JsonBool(Bool)
    | JsonInt(Int64)
    | JsonFloat(Float64)
    | JsonString(String)
    | JsonArray(Array<JsonValue>)
    | JsonObject(Array<(String, JsonValue)>)

    public operator func ==(right: JsonValue): Bool {
        writeJsonCompact(this) == writeJsonCompact(right)
    }

    public operator func !=(right: JsonValue): Bool {
        writeJsonCompact(this) != writeJsonCompact(right)
    }
}

public class JsonError <: Exception {
    public let position: Int64

    public init(message: String, position: Int64) {
        super(message)
        this.position = position
    }
}

/* ------------------------------------------------------------------ */
/* Parsing                                                             */
/* ------------------------------------------------------------------ */

class JsonReader {
    let text: String
    var cursor: Int64 = 0
    let size: Int64

    init(text: String) {
        this.text = text
        this.size = text.size
    }

    func fail(message: String): Nothing {
        throw JsonError("${message} at byte ${cursor}", cursor)
    }

    func skipWhitespace(): Unit {
        while (cursor < size) {
            let byte = text[cursor]
            if (byte == UInt8(32) || byte == UInt8(9) || byte == UInt8(10) || byte == UInt8(13)) {
                cursor += 1
            } else {
                break
            }
        }
    }

    func parseValue(): JsonValue {
        skipWhitespace()
        if (cursor >= size) {
            fail("unexpected end of JSON input")
        }
        match (Int64(text[cursor])) {
            case 123 => parseObject()
            case 91 => parseArray()
            case 34 => JsonString(parseString())
            case 116 => expectLiteral("true", JsonBool(true))
            case 102 => expectLiteral("false", JsonBool(false))
            case 110 => expectLiteral("null", JsonNull)
            case _ => parseNumber()
        }
    }

    func expectLiteral(literal: String, value: JsonValue): JsonValue {
        if (cursor + literal.size > size || text[cursor..cursor + literal.size] != literal) {
            fail("invalid literal")
        }
        cursor += literal.size
        value
    }

    func parseObject(): JsonValue {
        cursor += 1
        let entries = ArrayList<(String, JsonValue)>()
        skipWhitespace()
        if (cursor < size && text[cursor] == UInt8(125)) {
            cursor += 1
            return JsonObject(entries.toArray())
        }
        while (true) {
            skipWhitespace()
            if (cursor >= size || text[cursor] != UInt8(34)) {
                fail("expected object key")
            }
            let key = parseString()
            skipWhitespace()
            if (cursor >= size || text[cursor] != UInt8(58)) {
                fail("expected ':'")
            }
            cursor += 1
            let value = parseValue()
            var replaced = false
            for (index in 0..entries.size) {
                let (existingKey, _) = entries[index]
                if (existingKey == key) {
                    // JavaScript keeps the first insertion position, last value.
                    entries[index] = (key, value)
                    replaced = true
                    break
                }
            }
            if (!replaced) {
                entries.add((key, value))
            }
            skipWhitespace()
            if (cursor >= size) {
                fail("unterminated object")
            }
            let next = text[cursor]
            if (next == UInt8(44)) {
                cursor += 1
                continue
            }
            if (next == UInt8(125)) {
                cursor += 1
                return JsonObject(entries.toArray())
            }
            fail("expected ',' or '}'")
        }
        JsonObject(entries.toArray())
    }

    func parseArray(): JsonValue {
        cursor += 1
        let items = ArrayList<JsonValue>()
        skipWhitespace()
        if (cursor < size && text[cursor] == UInt8(93)) {
            cursor += 1
            return JsonArray(items.toArray())
        }
        while (true) {
            items.add(parseValue())
            skipWhitespace()
            if (cursor >= size) {
                fail("unterminated array")
            }
            let next = text[cursor]
            if (next == UInt8(44)) {
                cursor += 1
                continue
            }
            if (next == UInt8(93)) {
                cursor += 1
                return JsonArray(items.toArray())
            }
            fail("expected ',' or ']'")
        }
        JsonArray(items.toArray())
    }

    func parseString(): String {
        cursor += 1
        var escaped = false
        let start = cursor
        while (cursor < size) {
            let byte = text[cursor]
            if (byte == UInt8(92)) {
                escaped = true
                cursor += 2
                continue
            }
            if (byte == UInt8(34)) {
                let end = cursor
                cursor += 1
                if (!escaped) {
                    return text[start..end]
                }
                return decodeEscaped(start, end)
            }
            cursor += 1
        }
        fail("unterminated string")
    }

    func decodeEscaped(start: Int64, end: Int64): String {
        let bytes = ArrayList<UInt8>()
        var index = start
        while (index < end) {
            let byte = text[index]
            if (byte != UInt8(92)) {
                bytes.add(byte)
                index += 1
                continue
            }
            index += 1
            let marker = Int64(text[index])
            index += 1
            match (marker) {
                case 34 => bytes.add(UInt8(34))
                case 92 => bytes.add(UInt8(92))
                case 47 => bytes.add(UInt8(47))
                case 98 => bytes.add(UInt8(8))
                case 102 => bytes.add(UInt8(12))
                case 110 => bytes.add(UInt8(10))
                case 114 => bytes.add(UInt8(13))
                case 116 => bytes.add(UInt8(9))
                case 117 =>
                    var codePoint = hexValue(index, 4)
                    index += 4
                    if (codePoint >= 0xD800 && codePoint <= 0xDBFF && index + 6 <= end &&
                        text[index] == UInt8(92) && text[index + 1] == UInt8(117)) {
                        let low = hexValue(index + 2, 4)
                        if (low >= 0xDC00 && low <= 0xDFFF) {
                            codePoint = 0x10000 + ((codePoint - 0xD800) << 10) + (low - 0xDC00)
                            index += 6
                        }
                    }
                    appendUtf8(codePoint, bytes)
                case _ => fail("invalid escape")
            }
        }
        String.fromUtf8(bytes.toArray())
    }

    func hexValue(start: Int64, digits: Int64): Int64 {
        var value = 0
        var index = start
        while (index < start + digits) {
            if (index >= size) {
                fail("truncated unicode escape")
            }
            let byte = Int64(text[index])
            let digit = if (byte >= 48 && byte <= 57) {
                byte - 48
            } else if (byte >= 65 && byte <= 70) {
                byte - 55
            } else if (byte >= 97 && byte <= 102) {
                byte - 87
            } else {
                fail("invalid unicode escape")
            }
            value = value * 16 + digit
            index += 1
        }
        value
    }

    func parseNumber(): JsonValue {
        let start = cursor
        if (cursor < size && text[cursor] == UInt8(45)) {
            cursor += 1
        }
        var isFloat = false
        while (cursor < size) {
            let byte = text[cursor]
            if (byte >= UInt8(48) && byte <= UInt8(57)) {
                cursor += 1
                continue
            }
            if (byte == UInt8(46)) {
                isFloat = true
                cursor += 1
                continue
            }
            if (byte == UInt8(101) || byte == UInt8(69)) {
                isFloat = true
                cursor += 1
                if (cursor < size && (text[cursor] == UInt8(43) || text[cursor] == UInt8(45))) {
                    cursor += 1
                }
                continue
            }
            break
        }
        if (cursor == start) {
            fail("unexpected character in JSON")
        }
        let raw = text[start..cursor]
        if (!isFloat) {
            match (Int64.tryParse(raw)) {
                case Some(value) => return JsonInt(value)
                case None => ()
            }
        }
        match (Float64.tryParse(raw)) {
            case Some(value) => JsonFloat(value)
            case None => fail("invalid number '${raw}'")
        }
    }
}

/** Parses `text` into a `JsonValue`; throws `JsonError` on malformed input. */
public func parseJson(text: String): JsonValue {
    let reader = JsonReader(text)
    let value = reader.parseValue()
    reader.skipWhitespace()
    if (reader.cursor != reader.size) {
        reader.fail("unexpected trailing characters")
    }
    value
}

/* ------------------------------------------------------------------ */
/* Writing                                                             */
/* ------------------------------------------------------------------ */

/**
 * Formats a Float64 the way `JSON.stringify` does for the value ranges the
 * workspace can contain: integral values lose the fraction, everything else
 * uses the shortest decimal form that parses back to the same Float64.
 *
 * Non-finite numbers become `null`, matching JavaScript.
 */
public func formatJsonNumber(value: Float64): String {
    if (value != value) {
        return "null"
    }
    if (value > 1.7976931348623157e308 || value < -1.7976931348623157e308) {
        return "null"
    }
    if (value == 0.0) {
        return "0"
    }
    let magnitude = if (value < 0.0) {
        -value
    } else {
        value
    }
    if (magnitude < 9.007199254740992e15 && value == Float64(Int64(value))) {
        return Int64(value).toString()
    }
    if (magnitude < 1000000000.0 && magnitude >= 1.0e-6) {
        match (shortestFixed(value)) {
            case Some(text) => return text
            case None => ()
        }
    }
    // JavaScript switches to exponent notation outside [1e-6, 1e21); the
    // workspace never contains such values, but staying finite beats throwing.
    scientific(value)
}

/** Shortest fixed-point text in 1..17 decimals that parses back to `value`. */
func shortestFixed(value: Float64): ?String {
    for (digits in 1..=17) {
        let candidate = fixedDigits(value, digits)
        match (Float64.tryParse(candidate)) {
            case Some(parsed) => if (parsed == value) {
                return Some(candidate)
            }
            case None => ()
        }
    }
    None
}

func scientific(value: Float64): String {
    var mantissa = value
    var exponent = 0
    let negative = value < 0.0
    if (negative) {
        mantissa = -mantissa
    }
    while (mantissa >= 10.0 && exponent < 400) {
        mantissa = mantissa / 10.0
        exponent += 1
    }
    while (mantissa < 1.0 && exponent > -400) {
        mantissa = mantissa * 10.0
        exponent -= 1
    }
    let body = match (shortestFixed(mantissa)) {
        case Some(text) => text
        case None => fixedDigits(mantissa, 17)
    }
    let sign = if (negative) {
        "-"
    } else {
        ""
    }
    let exponentSign = if (exponent < 0) {
        "-"
    } else {
        "+"
    }
    let exponentValue = if (exponent < 0) {
        -exponent
    } else {
        exponent
    }
    "${sign}${body}e${exponentSign}${exponentValue}"
}

func fixedDigits(value: Float64, digits: Int64): String {
    var scale = 1.0
    var index = 0
    while (index < digits) {
        scale = scale * 10.0
        index += 1
    }
    let scaled = value * scale
    let rounded = if (scaled < 0.0) {
        -Int64(-scaled + 0.5)
    } else {
        Int64(scaled + 0.5)
    }
    let negative = rounded < 0
    let digitsText = if (negative) {
        (-rounded).toString()
    } else {
        rounded.toString()
    }
    let padded = if (digitsText.size <= digits) {
        repeatText("0", digits - digitsText.size) + digitsText
    } else {
        digitsText
    }
    let split = padded.size - digits
    let whole = if (split == 0) {
        "0"
    } else {
        padded[0..split]
    }
    var fraction = padded[split..padded.size]
    while (fraction.size > 0 && fraction[fraction.size - 1] == UInt8(48)) {
        fraction = fraction[0..fraction.size - 1]
    }
    let sign = if (negative) {
        "-"
    } else {
        ""
    }
    if (fraction.isEmpty()) {
        "${sign}${whole}"
    } else {
        "${sign}${whole}.${fraction}"
    }
}

func appendUtf8(codePoint: Int64, out: ArrayList<UInt8>): Unit {
    if (codePoint < 0x80) {
        out.add(UInt8(codePoint))
    } else if (codePoint < 0x800) {
        out.add(UInt8(0xC0 + (codePoint >> 6)))
        out.add(UInt8(0x80 + (codePoint & 0x3F)))
    } else if (codePoint < 0x10000) {
        out.add(UInt8(0xE0 + (codePoint >> 12)))
        out.add(UInt8(0x80 + ((codePoint >> 6) & 0x3F)))
        out.add(UInt8(0x80 + (codePoint & 0x3F)))
    } else {
        out.add(UInt8(0xF0 + (codePoint >> 18)))
        out.add(UInt8(0x80 + ((codePoint >> 12) & 0x3F)))
        out.add(UInt8(0x80 + ((codePoint >> 6) & 0x3F)))
        out.add(UInt8(0x80 + (codePoint & 0x3F)))
    }
}

/** Escapes a string exactly like `JSON.stringify` (no HTML escaping). */
public func quoteJsonString(value: String): String {
    let out = StringBuilder()
    out.append("\"")
    var index = 0
    var runStart = 0
    while (index < value.size) {
        let byte = value[index]
        var escape: ?String = None
        match (Int64(byte)) {
            case 34 => escape = Some("\\\"")
            case 92 => escape = Some("\\\\")
            case 8 => escape = Some("\\b")
            case 9 => escape = Some("\\t")
            case 10 => escape = Some("\\n")
            case 12 => escape = Some("\\f")
            case 13 => escape = Some("\\r")
            case _ => if (byte < UInt8(32)) {
                escape = Some("\\u00" + hexPair(Int64(byte)))
            }
        }
        match (escape) {
            case Some(text) =>
                // UTF-8 must be copied in whole sequences: never emit a single
                // continuation byte through String.fromUtf8.
                if (runStart < index) {
                    out.append(value[runStart..index])
                }
                out.append(text)
                runStart = index + 1
            case None => ()
        }
        index += 1
    }
    if (runStart < value.size) {
        out.append(value[runStart..value.size])
    }
    out.append("\"")
    out.toString()
}

func hexPair(value: Int64): String {
    let digits = "0123456789abcdef"
    let high = (value >> 4) & 0xF
    let low = value & 0xF
    "${digits[high..high + 1]}${digits[low..low + 1]}"
}

/** Single-line form, used for diagnostics and correction reports. */
public func writeJsonCompact(value: JsonValue): String {
    match (value) {
        case JsonNull => "null"
        case JsonBool(flag) => if (flag) {
            "true"
        } else {
            "false"
        }
        case JsonInt(number) => number.toString()
        case JsonFloat(number) => formatJsonNumber(number)
        case JsonString(text) => quoteJsonString(text)
        case JsonArray(items) =>
            let out = StringBuilder()
            out.append("[")
            for (index in 0..items.size) {
                if (index > 0) {
                    out.append(",")
                }
                out.append(writeJsonCompact(items[index]))
            }
            out.append("]")
            out.toString()
        case JsonObject(entries) =>
            let out = StringBuilder()
            out.append("{")
            for (index in 0..entries.size) {
                if (index > 0) {
                    out.append(",")
                }
                let (key, member) = entries[index]
                out.append(quoteJsonString(key))
                out.append(":")
                out.append(writeJsonCompact(member))
            }
            out.append("}")
            out.toString()
    }
}

/** Pretty-prints like `JSON.stringify(value, null, 2)`; no trailing newline. */
public func writeJson(value: JsonValue): String {
    let out = StringBuilder()
    writeJsonInto(value, out, 0)
    out.toString()
}

func writeJsonInto(value: JsonValue, out: StringBuilder, depth: Int64): Unit {
    match (value) {
        case JsonNull => out.append("null")
        case JsonBool(flag) => if (flag) {
            out.append("true")
        } else {
            out.append("false")
        }
        case JsonInt(number) => out.append(number.toString())
        case JsonFloat(number) => out.append(formatJsonNumber(number))
        case JsonString(text) => out.append(quoteJsonString(text))
        case JsonArray(items) => if (items.isEmpty()) {
            out.append("[]")
        } else {
            out.append("[\n")
            for (index in 0..items.size) {
                out.append(indent(depth + 1))
                writeJsonInto(items[index], out, depth + 1)
                if (index + 1 < items.size) {
                    out.append(",")
                }
                out.append("\n")
            }
            out.append(indent(depth))
            out.append("]")
        }
        case JsonObject(entries) => if (entries.isEmpty()) {
            out.append("{}")
        } else {
            out.append("{\n")
            for (index in 0..entries.size) {
                let (key, member) = entries[index]
                out.append(indent(depth + 1))
                out.append(quoteJsonString(key))
                out.append(": ")
                writeJsonInto(member, out, depth + 1)
                if (index + 1 < entries.size) {
                    out.append(",")
                }
                out.append("\n")
            }
            out.append(indent(depth))
            out.append("}")
        }
    }
}

func indent(depth: Int64): String {
    repeatText("  ", depth)
}

/** `String.repeat` does not exist in the 1.2 standard library. */
public func repeatText(text: String, count: Int64): String {
    let out = StringBuilder()
    var index = 0
    while (index < count) {
        out.append(text)
        index += 1
    }
    out.toString()
}
