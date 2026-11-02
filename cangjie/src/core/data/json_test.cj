package textura.core.data

import std.unittest.*
import std.unittest.testmacro.*

/**
 * JSON codec tests. The writer must match `JSON.stringify(value, null, 2)` so a
 * workspace round trip stays byte-identical to the Web build's output.
 */

@Test
func jsonPrettyPrintMatchesJavaScript(): Unit {
    let source = "{\"version\":1,\"items\":[],\"flag\":true,\"nothing\":null,\"name\":\"织理\"}"
    let value = parseJson(source)
    let expected = "{\n" +
        "  \"version\": 1,\n" +
        "  \"items\": [],\n" +
        "  \"flag\": true,\n" +
        "  \"nothing\": null,\n" +
        "  \"name\": \"织理\"\n" +
        "}"
    @Expect(writeJson(value), expected)
}

@Test
func jsonNumberFormattingFollowsJavaScript(): Unit {
    @Expect(formatJsonNumber(1.0), "1")
    @Expect(formatJsonNumber(3.0), "3")
    @Expect(formatJsonNumber(2.1), "2.1")
    @Expect(formatJsonNumber(2.35), "2.35")
    @Expect(formatJsonNumber(-0.5), "-0.5")
    @Expect(formatJsonNumber(1450.0), "1450")
    @Expect(formatJsonNumber(0.0), "0")
    @Expect(formatJsonNumber(0.1 + 0.2), "0.30000000000000004")
    @Expect(formatJsonNumber(1.0e21), "1e+21")
}

@Test
func jsonStringEscapingMatchesJavaScript(): Unit {
    @Expect(quoteJsonString("a\"b"), "\"a\\\"b\"")
    @Expect(quoteJsonString("a\\b"), "\"a\\\\b\"")
    @Expect(quoteJsonString("a\nb"), "\"a\\nb\"")
    @Expect(quoteJsonString("a\tb"), "\"a\\tb\"")
    @Expect(quoteJsonString("\u{1}"), "\"\\u0001\"")
    // Multi-byte characters stay raw, never escaped and never split.
    @Expect(quoteJsonString("仓颉"), "\"仓颉\"")
    match (parseJson(quoteJsonString("仓颉\n中"))) {
        case JsonString(text) => @Expect(text, "仓颉\n中")
        case _ => @Expect(false, true)
    }
}

@Test
func jsonParsesUnicodeEscapes(): Unit {
    match (parseJson("\"\\u4ed3\\u9898\"")) {
        case JsonString(text) => @Expect(text, "仓题")
        case _ => @Expect(false, true)
    }
    // Surrogate pair (U+1F600) must decode into one 4-byte sequence.
    match (parseJson("\"\\ud83d\\ude00\"")) {
        case JsonString(text) => @Expect(text.size, 4)
        case _ => @Expect(false, true)
    }
}

@Test
func jsonPreservesObjectKeyOrder(): Unit {
    let value = parseJson("{\"b\":1,\"a\":2}")
    @Expect(writeJson(value), "{\n  \"b\": 1,\n  \"a\": 2\n}")
}

@Test
func jsonDuplicateKeysKeepFirstPositionLastValue(): Unit {
    let value = parseJson("{\"a\":1,\"b\":2,\"a\":3}")
    @Expect(writeJsonCompact(value), "{\"a\":3,\"b\":2}")
}

@Test
func jsonRejectsMalformedInput(): Unit {
    var raised = false
    try {
        parseJson("{\"a\":}")
    } catch (_: JsonError) {
        raised = true
    }
    @Expect(raised, true)

    var trailing = false
    try {
        parseJson("{} {}")
    } catch (_: JsonError) {
        trailing = true
    }
    @Expect(trailing, true)
}

@Test
func jsonIntegerAndFloatStayDistinct(): Unit {
    match (parseJson("3")) {
        case JsonInt(value) => @Expect(value, 3)
        case _ => @Expect(false, true)
    }
    match (parseJson("3.0")) {
        case JsonFloat(value) => @Expect(value, 3.0)
        case _ => @Expect(false, true)
    }
    // Both render like JavaScript (`3.0` parses to the number 3).
    @Expect(writeJsonCompact(parseJson("3.0")), "3")
}
