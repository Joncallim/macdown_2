import CryptoKit
import Foundation

/// Maps original body UTF-16 offsets to the exact body cmark parses after
/// accepted derived-content substitutions. Replaced source has no faithful
/// output coordinate; callers must reject a heading whose required position
/// lands inside one of those ranges.
struct SplicedBodySourceMap {
    let sourceSHA256: String

    private struct Replacement {
        let sourceRange: Range<Int>
        let deltaAfter: Int
    }

    private let sourceUTF16Length: Int
    private let renderedUTF16Length: Int
    private let replacements: [Replacement]
    private let isValid: Bool

    init(sourceText: String, renderedText: String, splices: [DerivedContentComposer.Splice]) {
        sourceSHA256 = SHA256.hash(data: Data(sourceText.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let sourceUTF16Length = sourceText.utf16.count
        let renderedUTF16Length = renderedText.utf16.count
        self.sourceUTF16Length = sourceUTF16Length
        self.renderedUTF16Length = renderedUTF16Length

        var entries: [Replacement] = []
        entries.reserveCapacity(splices.count)
        var previousEnd = 0
        var delta = 0
        var valid = sourceUTF16Length >= 0 && renderedUTF16Length >= 0
        for splice in splices {
            let range = splice.range
            guard range.lowerBound >= previousEnd, range.lowerBound < range.upperBound,
                  range.upperBound <= sourceUTF16Length else {
                valid = false
                break
            }
            delta += splice.renderedText.utf16.count - range.count
            entries.append(Replacement(sourceRange: range, deltaAfter: delta))
            previousEnd = range.upperBound
        }
        replacements = entries
        isValid = valid && sourceUTF16Length + delta == renderedUTF16Length
    }

    /// `nil` means the offset is outside the original body, inside replaced
    /// source, or the recorded substitutions do not describe the rendered body.
    func renderedOffset(forOriginalOffset offset: Int) -> Int? {
        guard isValid, (0 ... sourceUTF16Length).contains(offset) else { return nil }

        // Number of replacements ending at or before this offset. A binary
        // search keeps matching many headings against many diagrams linear in
        // the heading count rather than quadratic in the contribution count.
        var low = 0
        var high = replacements.count
        while low < high {
            let middle = low + (high - low) / 2
            if replacements[middle].sourceRange.upperBound <= offset {
                low = middle + 1
            } else {
                high = middle
            }
        }
        if low < replacements.count, replacements[low].sourceRange.contains(offset) {
            return nil
        }
        let delta = low == 0 ? 0 : replacements[low - 1].deltaAfter
        let rendered = offset + delta
        return (0 ... renderedUTF16Length).contains(rendered) ? rendered : nil
    }
}
