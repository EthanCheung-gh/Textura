package textura.core.data

import std.fs.*

/**
 * Cheap, dependency-free digest of a workspace document, used by the parity CLI
 * and the snapshot pipeline. The three summary fields are a frozen contract:
 *
 * - `byteCount`: raw file size in bytes;
 * - `hash`: FNV-1a 64 over the raw bytes (so it proves *which* input produced a
 *   snapshot, independent of how the document is parsed);
 * - `anchorDate`: the date part of the document's `updatedAt`, which freezes
 *   "today" for parity runs instead of reading the system clock.
 */
public class WorkspaceDigest {
    public let path: String
    public let byteCount: Int64
    public let hash: UInt64
    public let anchorDate: String

    public init(path: String, byteCount: Int64, hash: UInt64, anchorDate: String) {
        this.path = path
        this.byteCount = byteCount
        this.hash = hash
        this.anchorDate = anchorDate
    }

    public func describe(): String {
        "bytes=${byteCount}, fnv1a64=${hash}, anchor=${anchorDate}"
    }
}

/** Reads `path` and derives its digest. Throws when the file is unreadable. */
public func inspectWorkspace(path: String): WorkspaceDigest {
    let bytes = File.readFrom(path)
    let text = String.fromUtf8(bytes)
    WorkspaceDigest(path, Int64(bytes.size), fnv1a64(bytes), extractAnchorDate(text))
}

/**
 * Picks the date part of the last `"updatedAt"` value.
 *
 * Deliberately textual (not parsed): it must keep working on a document that
 * fails JSON parsing but is still previewable, and the parity fixture's digest
 * is frozen against this exact behavior.
 */
public func extractAnchorDate(text: String): String {
    let marker = "\"updatedAt\""
    match (text.lastIndexOf(marker)) {
        case Some(index) =>
            var cursor = index + marker.size
            // Tolerate both compact JSON and pretty-printed JSON:
            //   "updatedAt":"2026-..."      "updatedAt": "2026-..."
            while (cursor < text.size) {
                let byte = text[cursor]
                if (byte == UInt8(32) || byte == UInt8(9) || byte == UInt8(10) || byte == UInt8(13) || byte == UInt8(58)) {
                    cursor += 1
                } else {
                    break
                }
            }
            if (cursor < text.size && text[cursor] == UInt8(34) && cursor + 11 <= text.size) {
                let start = cursor + 1
                text[start..start + 10]
            } else {
                "unknown"
            }
        case None => "unknown"
    }
}
