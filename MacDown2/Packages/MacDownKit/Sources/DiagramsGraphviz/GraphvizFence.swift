import Foundation

/// One fenced ```dot```/```graphviz``` block found in a document
/// (epic-21-implementation.md §3.2), mirroring `MermaidFence`'s shape.
public struct GraphvizFence: Sendable, Equatable {
    public let source: String
    public let sourceRange: Range<Int>

    public init(source: String, sourceRange: Range<Int>) {
        self.source = source
        self.sourceRange = sourceRange
    }
}
