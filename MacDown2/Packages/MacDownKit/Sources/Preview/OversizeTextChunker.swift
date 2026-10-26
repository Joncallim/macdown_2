import Foundation

/// Groups exact source at newline or grapheme boundaries, then produces
/// bounded display units. An indivisible grapheme exceeding the layout
/// limit is represented by an explicit preview-only omission marker;
/// its original scalars remain intact in the document and source chunks.
enum OversizeTextChunker {
    /// Keeps each fallback `Text` well below the size at which CoreText's
    /// bounding-rect work becomes superlinear in the native acceptance ladder.
    static let defaultMaxUTF16Length = 16 * 1024

    /// Targets the limit without splitting a grapheme. A single overlong
    /// grapheme must exceed it to preserve exact source; use ``displayChunks``
    /// for the hard rendering bound and its visible omission fallback.
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
    /// second line break between adjacent views. The final chunk retains its
    /// authored line ending. An oversized grapheme is omitted visibly rather
    /// than split into scalars that could change its shaping across views.
    static func displayChunks(_ source: String, maxUTF16Length: Int = defaultMaxUTF16Length) -> [String] {
        let limit = max(1, maxUTF16Length)
        let renderable = chunks(source, maxUTF16Length: limit).flatMap { chunk in
            if chunk.utf16.count > limit {
                // Source chunking isolates an indivisible overlong Character.
                // Chunk the ASCII marker too when a caller uses a tiny limit.
                chunks("[Preview omitted one oversized grapheme]", maxUTF16Length: limit)
            } else {
                [chunk]
            }
        }
        return renderable.enumerated().map { index, chunk in
            var display = chunk
            if index < renderable.count - 1,
               chunk.hasSuffix("\r\n") || chunk.hasSuffix("\n") || chunk.hasSuffix("\r") {
                // CRLF is one Swift Character, so remove exactly one Character.
                display.removeLast()
            }
            return display.isEmpty ? "\u{200B}" : display
        }
    }
}
