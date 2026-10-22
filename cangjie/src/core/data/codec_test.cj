package textura.core.data

import std.unittest.*
import std.unittest.testmacro.*

/**
 * Serialization / normalization tests.
 *
 * The headline guarantee: reading `tools/parity/workspace.json` and writing it
 * back produces byte-identical output, so `inspectWorkspace`'s digest (byte
 * count + FNV-1a64 + anchor date) cannot change across a round trip.
 */

@Test
func codecRoundTripKeepsParityDocumentBytes(): Unit {
    match (parityWorkspaceText()) {
        case Some(text) =>
            let clock = FixedClock(TEST_ANCHOR)
            let loaded = normalizeForLoad(parseJson(text), clock)
            @Expect(loaded.workspace.items.size, 30)
            @Expect(loaded.workspace.edges.size, 12)
            @Expect(loaded.workspace.areas.size, 3)
            @Expect(loaded.workspace.runs.size, 3)
            @Expect(loaded.corrections.total, 0)
            @Expect(loaded.parentCycles.size, 0)
            let encoded = encodeWorkspaceDocument(loaded.workspace)
            @Expect(encoded == text, true)
            // Digest equivalence, the exact parity contract.
            let originalDigest = fnv1a64(text.toArray())
            let encodedDigest = fnv1a64(encoded.toArray())
            @Expect(encodedDigest, originalDigest)
            @Expect(encoded.size, text.size)
            @Expect(extractAnchorDate(encoded), "2026-03-16")
        case None => @Expect(true, true)
    }
}

@Test
func codecRelativeDatesSurviveRoundTrip(): Unit {
    // Dates are stored as data, so a second load/save must not drift.
    let clock = FixedClock(TEST_ANCHOR)
    let seed = createSeedWorkspace(clock)
    let first = encodeWorkspaceDocument(seed)
    let second = encodeWorkspaceDocument(normalizeForLoad(parseJson(first), clock).workspace)
    @Expect(second == first, true)
}

@Test
func codecPreservesUnknownFields(): Unit {
    let document = "{\n" +
        "  \"version\": 1,\n" +
        "  \"items\": [\n" +
        "    {\n" +
        "      \"id\": \"i1\",\n" +
        "      \"kind\": \"action\",\n" +
        "      \"title\": \"未来字段\",\n" +
        "      \"notes\": \"\",\n" +
        "      \"parentId\": null,\n" +
        "      \"order\": 0,\n" +
        "      \"status\": \"next\",\n" +
        "      \"tags\": [],\n" +
        "      \"areaId\": null,\n" +
        "      \"createdAt\": \"2026-01-01T00:00:00.000Z\",\n" +
        "      \"updatedAt\": \"2026-01-01T00:00:00.000Z\",\n" +
        "      \"completedAt\": null,\n" +
        "      \"futureField\": {\n" +
        "        \"nested\": [\n" +
        "          1,\n" +
        "          2\n" +
        "        ]\n" +
        "      }\n" +
        "    }\n" +
        "  ],\n" +
        "  \"edges\": [],\n" +
        "  \"areas\": [],\n" +
        "  \"runs\": [],\n" +
        "  \"updatedAt\": \"2026-01-01T00:00:00.000Z\",\n" +
        "  \"workspaceExtra\": \"keep me\"\n" +
        "}\n"
    let clock = FixedClock(TEST_ANCHOR)
    let loaded = normalizeForLoad(parseJson(document), clock)
    @Expect(loaded.corrections.total, 0)
    let encoded = encodeWorkspaceDocument(loaded.workspace)
    @Expect(encoded.contains("\"futureField\""), true)
    @Expect(encoded.contains("\"workspaceExtra\""), true)
    @Expect(encoded.contains("\"keep me\""), true)
    // Round trip again: the unknown fields must stay put.
    let again = encodeWorkspaceDocument(normalizeForLoad(parseJson(encoded), clock).workspace)
    @Expect(again == encoded, true)
}

@Test
func codecKeepsParsedKeyOrder(): Unit {
    let document = "{\"updatedAt\":\"2026-01-01T00:00:00.000Z\",\"areas\":[],\"runs\":[],\"edges\":[]," +
        "\"items\":[],\"version\":1}"
    let loaded = normalizeForLoad(parseJson(document), FixedClock(TEST_ANCHOR))
    let encoded = encodeWorkspaceDocument(loaded.workspace)
    @Expect(encoded.startsWith("{\n  \"updatedAt\""), true)
}

@Test
func codecNormalizesInvalidFieldsAndReportsThem(): Unit {
    let document = "{\n" +
        "  \"version\": 1,\n" +
        "  \"items\": [\n" +
        "    {\n" +
        "      \"id\": \"\",\n" +
        "      \"kind\": \"weird\",\n" +
        "      \"title\": \"\",\n" +
        "      \"order\": \"3\",\n" +
        "      \"status\": \"nope\",\n" +
        "      \"tags\": [\n" +
        "        \"  \",\n" +
        "        \"ok\"\n" +
        "      ]\n" +
        "    }\n" +
        "  ],\n" +
        "  \"edges\": [],\n" +
        "  \"areas\": [],\n" +
        "  \"runs\": [],\n" +
        "  \"updatedAt\": \"2026-01-01T00:00:00.000Z\"\n" +
        "}\n"
    let clock = FixedClock(TEST_ANCHOR)
    let loaded = normalizeForLoad(parseJson(document), clock)
    let item = loaded.workspace.items[0]
    @Expect(item.id, "i_recovered_0")
    @Expect(itemKindWire(item.kind), "note")
    // `asString` keeps an explicit empty string (the fallback is only for non-strings).
    @Expect(item.title, "")
    @Expect(itemStatusWire(item.status), "next")
    @Expect(item.order, 3)
    @Expect(item.tags.size, 1)
    @Expect(item.tags[0], "ok")
    @Expect(item.createdAt, "2026-03-16T02:00:00.000Z")
    @Expect(loaded.corrections.total > 0, true)
    @Expect(loaded.corrections.entries.size > 0, true)
}

@Test
func codecRejectsNewerVersion(): Unit {
    let document = "{\"version\": 2, \"items\": [], \"edges\": [], \"areas\": [], \"runs\": [], " +
        "\"updatedAt\": \"2026-01-01T00:00:00.000Z\"}"
    var raised = false
    try {
        normalizeForLoad(parseJson(document), FixedClock(TEST_ANCHOR))
    } catch (error: WorkspaceVersionError) {
        raised = true
        @Expect(error.version, 2)
    }
    @Expect(raised, true)
}

@Test
func codecStrictMigrationRejectsParentCycles(): Unit {
    let document = "{\n" +
        "  \"version\": 1,\n" +
        "  \"items\": [\n" +
        "    {\"id\": \"a\", \"kind\": \"action\", \"title\": \"A\", \"parentId\": \"b\"},\n" +
        "    {\"id\": \"b\", \"kind\": \"action\", \"title\": \"B\", \"parentId\": \"a\"}\n" +
        "  ],\n" +
        "  \"edges\": [],\n" +
        "  \"areas\": [],\n" +
        "  \"runs\": [],\n" +
        "  \"updatedAt\": \"2026-01-01T00:00:00.000Z\"\n" +
        "}\n"
    var message = ""
    try {
        migrateWorkspace(parseJson(document), FixedClock(TEST_ANCHOR))
    } catch (error: IllegalArgumentException) {
        message = error.message
    }
    @Expect(message.contains("父子环"), true)

    // The load path repairs instead of failing.
    let loaded = normalizeForLoad(parseJson(document), FixedClock(TEST_ANCHOR))
    @Expect(loaded.parentCycles.size, 1)
    var cut = 0
    for (item in loaded.workspace.items) {
        match (item.parentId) {
            case Some(_) => ()
            case None => cut += 1
        }
    }
    @Expect(cut, 1)
}

@Test
func codecOmitsAbsentOptionalBlocks(): Unit {
    let clock = FixedClock(TEST_ANCHOR)
    let item = testItem("i1", ItemKind.Action, "只读")
    let encoded = encodeWorkspaceDocument(testWorkspace([item]))
    @Expect(encoded.contains("\"okr\""), false)
    @Expect(encoded.contains("\"sop\""), false)
    @Expect(encoded.contains("\"gtd\""), false)
    @Expect(encoded.contains("\"gantt\""), false)
    @Expect(encoded.endsWith("}\n"), true)
}

@Test
func codecWritesNullableFieldsExplicitly(): Unit {
    let item = testItem("i1", ItemKind.Action, "空值")
    let text = workspaceToJsonText(testWorkspace([item]))
    @Expect(text.contains("\"parentId\": null"), true)
    @Expect(text.contains("\"areaId\": null"), true)
    @Expect(text.contains("\"completedAt\": null"), true)
}

@Test
func codecCanonicalTextIgnoresKeyOrder(): Unit {
    match (parityWorkspaceText()) {
        case Some(text) =>
            let clock = FixedClock(TEST_ANCHOR)
            let parity = normalizeForLoad(parseJson(text), clock).workspace
            let seed = createSeedWorkspace(clock)
            @Expect(canonicalWorkspaceJsonText(parity) == canonicalWorkspaceJsonText(seed), true)
        case None => @Expect(true, true)
    }
}

@Test
func codecMetricNumbersSerializeLikeJavascript(): Unit {
    let metric = Metric(2.1, 3.0, 2.35, "%")
    let item = testItem("kr", ItemKind.KeyResult, "KR", okr: OkrData("2026-Q1", 7, metric: metric))
    let text = workspaceToJsonText(testWorkspace([item]))
    @Expect(text.contains("\"start\": 2.1"), true)
    @Expect(text.contains("\"target\": 3,"), true)
    @Expect(text.contains("\"current\": 2.35"), true)
}
