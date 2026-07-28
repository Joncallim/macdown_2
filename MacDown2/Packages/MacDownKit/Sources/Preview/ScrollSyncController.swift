import Foundation

/// Coordinates editor ↔ preview scroll positions using a structural map and
/// measured preview block heights.
///
/// The controller is main-actor isolated because it is updated from SwiftUI
/// geometry preferences and drives scroll views on the main thread. Callers
/// must set `isEditorLeading` during a sync to prevent feedback loops.
@MainActor
@Observable
public final class ScrollSyncController {
    public private(set) var map: ScrollSyncMap
    public private(set) var blockHeights: [Int: Double]

    /// Set to `true` while the editor is driving the preview scroll, or
    /// `false` while the preview is driving the editor. Cleared when no sync is
    /// active. This prevents recursive scroll updates.
    public var isEditorLeading: Bool = false

    /// The preview scroll fraction the editor wants the preview to adopt.
    /// Consumers should clear this after acting on it.
    public var targetPreviewFraction: Double?

    /// The source line the preview wants the editor to scroll to.
    /// Consumers should clear this after acting on it.
    public var targetSourceLine: Int?

    public init(map: ScrollSyncMap = ScrollSyncMap(blocks: []), blockHeights: [Int: Double] = [:]) {
        self.map = map
        self.blockHeights = blockHeights
    }

    public func update(map: ScrollSyncMap) {
        guard self.map != map else { return }
        self.map = map
    }

    public func update(blockHeights: [Int: Double]) {
        guard self.blockHeights != blockHeights else { return }
        self.blockHeights = blockHeights
    }

    /// Returns the preview scroll fraction (0...1) for the given editor line.
    public func previewFraction(forLine line: Int) -> Double? {
        guard let blockIndex = map.blockIndex(forLine: line) else { return nil }
        let total = totalHeight
        guard total > 0 else { return nil }

        let offset = offsetUpTo(blockIndex: blockIndex)
        let blockHeight = height(for: blockIndex)
        let entry = map.entries.first { $0.blockIndex == blockIndex }
        let localProgress = localProgress(in: entry?.lineRange ?? (line ... line), for: line)
        return (offset + blockHeight * localProgress) / total
    }

    /// Returns the editor source line corresponding to a preview scroll fraction.
    public func line(forPreviewFraction fraction: Double) -> Int? {
        let total = totalHeight
        guard total > 0, !map.entries.isEmpty else { return nil }

        let target = fraction * total
        var accumulated: Double = 0
        for entry in map.entries {
            let height = height(for: entry.blockIndex)
            let next = accumulated + height
            if next >= target {
                let local = height > 0 ? (target - accumulated) / height : 0
                let lineCount = entry.lineRange.count
                let offset = Int((Double(lineCount) * local).rounded(.down))
                return min(entry.lineRange.lowerBound + offset, entry.lineRange.upperBound)
            }
            accumulated = next
        }
        return map.entries.last?.lineRange.upperBound
    }

    // MARK: - Internal helpers

    private var totalHeight: Double {
        map.entries.reduce(0) { $0 + height(for: $1.blockIndex) }
    }

    private func offsetUpTo(blockIndex: Int) -> Double {
        var offset: Double = 0
        for entry in map.entries {
            if entry.blockIndex == blockIndex {
                return offset
            }
            offset += height(for: entry.blockIndex)
        }
        return offset
    }

    private func height(for blockIndex: Int) -> Double {
        blockHeights[blockIndex, default: 0]
    }

    private func localProgress(in lineRange: ClosedRange<Int>, for line: Int) -> Double {
        let clamped = min(max(line, lineRange.lowerBound), lineRange.upperBound)
        let count = max(lineRange.count - 1, 1)
        return Double(clamped - lineRange.lowerBound) / Double(count)
    }
}
