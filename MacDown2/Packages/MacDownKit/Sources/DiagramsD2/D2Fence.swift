import Foundation

/// One fenced ```d2``` block found in a document (epic-21-implementation.md
/// §3.2), mirroring `MermaidFence`'s exact shape.
public struct D2Fence: Sendable, Equatable {
    public let source: String
    public let sourceRange: Range<Int>

    public init(source: String, sourceRange: Range<Int>) {
        self.source = source
        self.sourceRange = sourceRange
    }
}
