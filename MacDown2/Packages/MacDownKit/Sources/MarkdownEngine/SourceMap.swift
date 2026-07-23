import Foundation

/// Line ↔ UTF-16 offset conversion for the ORIGINAL source (D4).
///
/// Built in one O(n) pass; `\n` terminates lines; a `\r` before `\n` belongs
/// to the preceding line's content (offsets count UTF-16 units, so CRLF is
/// handled by construction, not by special cases).
public struct SourceMap: Sendable, Equatable {
    public let lineCount: Int

    /// UTF-16 offset at which each 1-based line starts. `lineStartOffsets[0]`
    /// is line 1 and is always 0. Count == lineCount.
    public let lineStartOffsets: [Int]

    /// Total UTF-16 length of the source.
    public let utf16Length: Int

    public init(text: String) {
        var offsets = [0]
        var offset = 0

        let utf16 = text.utf16
        for index in utf16.indices {
            offset += 1
            if utf16[index] == 0x000A { // \n
                offsets.append(offset)
            }
        }

        // Empty text is a single empty line.
        if text.isEmpty {
            offsets = [0]
        }

        lineStartOffsets = offsets
        lineCount = offsets.count
        utf16Length = offset
    }

    /// UTF-16 range covering the given original-source lines, clamped to the
    /// document. The range of the last line extends to `utf16Length`.
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
            lineStartOffsets[upper] - 1
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
