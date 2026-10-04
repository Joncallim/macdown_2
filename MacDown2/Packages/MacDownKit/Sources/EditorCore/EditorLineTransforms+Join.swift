import Foundation

extension EditorLineTransforms {
    /// A single-line group on the last line has no following line to join and is dropped, but its selection must
    /// still carry over (shifted by every earlier join), or `makeTransaction` finds an original index missing and
    /// the whole command silently does nothing.
    static func carryOverDroppedSelections(
        groups: [LineBlockGroup],
        selection: EditorSelectionSet,
        delta: Int,
        into results: inout [Int: NSRange]
    ) {
        let keptIndices = Set(groups.flatMap(\.memberIndices))
        for index in selection.ranges.indices where !keptIndices.contains(index) {
            let original = selection.ranges[index]
            results[index] = NSRange(location: original.location + delta, length: original.length)
        }
    }
}
