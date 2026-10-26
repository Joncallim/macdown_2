import Foundation

/// Splits a large plain-text preview into bounded layout units without
/// changing the authored source. Newline boundaries are preferred, but a
/// pathological line is still split at a grapheme-cluster boundary so
/// CoreText never receives one multi-hundred-kilobyte run.
enum OversizeTextChunker {
    /// Keeps each fallback `Text` well below the size at which CoreText's
    /// bounding-rect work becomes superlinear in the native acceptance ladder.
    static let defaultMaxUTF16Length = 16 * 1024

    static func chunks(_ source: String, maxUTF16Length: Int = defaultMaxUTF16Length) -> [String] {
        guard !source.isEmpty else { return [] }
        let limit = max(1, maxUTF16Length)
        var result: [String] = []
        var chunkStart = source.startIndex
        var cursor = chunkStart
        var chunkUTF16Length = 0
        var lastLineEndingEnd: String.Index?

        while cursor < source.endIndex {
            let next = source.index(after: cursor)
            let character = source[cursor]
            let characterUTF16Length = source[cursor ..< next].utf16.count

            if chunkUTF16Length > 0, chunkUTF16Length + characterUTF16Length > limit {
                // Re-process the current character in the next chunk. If a
                // line ending already fit, keep it with the preceding chunk;
                // otherwise split the long line at the previous Character.
                let split = lastLineEndingEnd ?? cursor
                if split > chunkStart {
                    result.append(String(source[chunkStart ..< split]))
                    chunkStart = split
                    cursor = split
                    chunkUTF16Length = 0
                    lastLineEndingEnd = nil
                    continue
                }
            }

            chunkUTF16Length += characterUTF16Length
            cursor = next
            if character.unicodeScalars.contains(where: { $0.value == 0x0A || $0.value == 0x0D }) {
                // A CRLF pair is one Character in Swift, so this boundary
                // cannot separate the two code points.
                lastLineEndingEnd = cursor
            }
        }

        if chunkStart < source.endIndex {
            result.append(String(source[chunkStart ..< source.endIndex]))
        }
        return result
    }

    /// Converts exact source chunks into separate text views without adding a
    /// second line break at the boundary between adjacent views. The exact
    /// source-preserving chunks remain available through ``chunks``.
    static func displayChunks(_ source: String, maxUTF16Length: Int = defaultMaxUTF16Length) -> [String] {
        chunks(source, maxUTF16Length: maxUTF16Length).map { chunk in
            let withoutBoundary = if chunk.hasSuffix("\r\n") {
                String(chunk.dropLast(2))
            } else if chunk.hasSuffix("\n") || chunk.hasSuffix("\r") {
                String(chunk.dropLast())
            } else {
                chunk
            }
            return withoutBoundary.isEmpty ? "\u{200B}" : withoutBoundary
        }
    }
}
