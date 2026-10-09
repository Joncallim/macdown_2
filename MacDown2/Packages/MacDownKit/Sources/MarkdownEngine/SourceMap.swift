import Foundation

/// Line ↔ UTF-16 offset conversion for the ORIGINAL source (D4).
///
/// Built in one O(n) pass. A line ends at `\n`, `\r\n` or a lone `\r`
/// (CommonMark's three line endings, and what the parser's own line numbers
/// count); a CRLF pair is ONE terminator, so a line start is never between its
/// two units. Offsets count UTF-16 units and are those of the original text.
public struct SourceMap: Sendable, Equatable {
    public let lineCount: Int

    /// UTF-16 offset at which each 1-based line starts. `lineStartOffsets[0]`
    /// is line 1 and is always 0. Count == lineCount.
    public let lineStartOffsets: [Int]

    /// UTF-16 length of the terminator that ends each line (0 for the last
    /// line when the text does not end with one). Count == lineCount.
    private let terminatorLengths: [Int]

    /// Total UTF-16 length of the source.
    public let utf16Length: Int

    public init(text: String) {
        var offsets = [0]
        var terminators: [Int] = []
        var offset = 0
        var previousWasCarriageReturn = false

        for unit in text.utf16 {
            offset += 1
            if unit == 0x000A { // \n
                if previousWasCarriageReturn {
                    // CRLF: the CR already opened a line start; move it past the LF
                    // and widen that line's terminator to two units.
                    offsets[offsets.count - 1] = offset
                    terminators[terminators.count - 1] = 2
                } else {
                    terminators.append(1)
                    offsets.append(offset)
                }
                previousWasCarriageReturn = false
            } else if unit == 0x000D { // \r
                terminators.append(1)
                offsets.append(offset)
                previousWasCarriageReturn = true
            } else {
                previousWasCarriageReturn = false
            }
        }
        terminators.append(0)

        // Empty text is a single empty line.
        if text.isEmpty {
            offsets = [0]
            terminators = [0]
        }

        lineStartOffsets = offsets
        terminatorLengths = terminators
        lineCount = offsets.count
        utf16Length = offset
    }

    /// UTF-16 range covering the given original-source lines, clamped to the
    /// document. The range of the last line extends to `utf16Length`; any other
    /// range ends before the WHOLE terminator of its last line (never splitting
    /// a CRLF pair, which would make it unconvertible to a Swift `Range`).
    public func utf16Range(ofLines lines: ClosedRange<Int>) -> NSRange {
        let lower = max(lines.lowerBound, 1)
        let upper = min(lines.upperBound, lineCount)
        guard lower <= upper else {
            return lower > lineCount
                ? NSRange(location: utf16Length, length: 0)
                : NSRange(location: 0, length: 0)
        }

        let startOffset = lineStartOffsets[lower - 1]
        let endOffset: Int = if upper < lineCount {
            lineStartOffsets[upper] - terminatorLengths[upper - 1]
        } else {
            utf16Length
        }

        let length = max(0, endOffset - startOffset)
        return NSRange(location: startOffset, length: length)
    }

    /// 1-based line containing the given UTF-16 offset (binary search).
    /// Offsets ≥ utf16Length return lineCount; negative offsets return 1.
    public func line(atUTF16Offset offset: Int) -> Int {
        guard offset >= 0 else {
            return 1
        }
        guard offset < utf16Length else {
            return lineCount
        }

        var low = 0
        var high = lineStartOffsets.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStartOffsets[mid] <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low + 1
    }
}
