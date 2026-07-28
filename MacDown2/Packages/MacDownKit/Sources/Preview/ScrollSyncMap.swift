import Foundation
import MarkdownEngine

/// Maps editor source lines to preview block indices.
///
/// The map is built from the document structure alone; measured block heights
/// are supplied separately (via ``ScrollSyncController``) when converting
/// between editor and preview scroll positions.
public struct ScrollSyncMap: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        /// Original-source line range covered by this entry.
        public let lineRange: ClosedRange<Int>

        /// Index of the corresponding block in the preview's block list.
        public let blockIndex: Int

        public init(lineRange: ClosedRange<Int>, blockIndex: Int) {
            self.lineRange = lineRange
            self.blockIndex = blockIndex
        }
    }

    public let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    public init(blocks: [PreviewBlock]) {
        entries = blocks.enumerated().map { index, block in
            Entry(lineRange: block.lineRange, blockIndex: index)
        }
    }

    /// Returns the preview block index whose source range contains `line`,
    /// or the nearest block if the line falls between blocks.
    public func blockIndex(forLine line: Int) -> Int? {
        guard !entries.isEmpty else { return nil }

        if let exact = entries.first(where: { $0.lineRange.contains(line) }) {
            return exact.blockIndex
        }

        // Between blocks: pick the nearest boundary.
        let nearest = entries.min { lhs, rhs in
            abs(lhs.lineRange.lowerBound - line) < abs(rhs.lineRange.lowerBound - line)
        }
        return nearest?.blockIndex
    }

    /// Returns the source line at the start of the block at `index`, if any.
    public func line(forBlockIndex index: Int) -> Int? {
        entries.first { $0.blockIndex == index }?.lineRange.lowerBound
    }

    /// The block index covering the first source line, or `nil` if empty.
    public var firstBlockIndex: Int? {
        entries.first?.blockIndex
    }

    /// The block index covering the last source line, or `nil` if empty.
    public var lastBlockIndex: Int? {
        entries.last?.blockIndex
    }
}
