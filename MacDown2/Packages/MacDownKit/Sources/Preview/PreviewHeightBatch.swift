import Foundation

/// Coalesces geometry callbacks emitted by eager preview blocks in one layout
/// pass. Keeping this reference type outside SwiftUI state means an individual
/// block measurement does not replace a dictionary-valued `@State` and redraw
/// the entire preview hierarchy.
@MainActor
final class PreviewHeightBatch {
    private var heightsByID: [UUID: Double] = [:]
    private var idsByIndex: [Int: UUID] = [:]
    private var publishTask: Task<Void, Never>?

    deinit {
        publishTask?.cancel()
    }

    func record(_ height: Double, for blockIndex: Int, controller: ScrollSyncController) {
        let id = idsByIndex[blockIndex] ?? UUID()
        idsByIndex[blockIndex] = id
        record(height, for: id, at: blockIndex, controller: controller)
    }

    func record(_ height: Double, for id: UUID, at index: Int, controller: ScrollSyncController) {
        guard heightsByID[id] != height else { return }
        idsByIndex[index] = id
        heightsByID[id] = height
        schedulePublish(to: controller)
    }

    func reconcile(with blocks: [PreviewBlock], controller: ScrollSyncController) {
        let validIDs = Set(blocks.map(\.id))
        heightsByID = heightsByID.filter { validIDs.contains($0.key) }
        idsByIndex = Dictionary(uniqueKeysWithValues: blocks.enumerated().map { ($0.offset, $0.element.id) })
        flush(to: controller)
    }

    func retainEntries(before count: Int, controller: ScrollSyncController) {
        let retainedIDs = Set(idsByIndex.filter { $0.key < count }.map(\.value))
        heightsByID = heightsByID.filter { retainedIDs.contains($0.key) }
        idsByIndex = idsByIndex.filter { $0.key < count }
        flush(to: controller)
    }

    func flush(to controller: ScrollSyncController) {
        publishTask?.cancel()
        publishTask = nil
        controller.update(blockHeights: currentHeights)
    }

    private func schedulePublish(to controller: ScrollSyncController) {
        guard publishTask == nil else { return }
        publishTask = Task { @MainActor [weak self, weak controller] in
            // Let all `onGeometryChange` callbacks in the current turn join
            // the same immutable snapshot before publishing it once.
            await Task.yield()
            guard !Task.isCancelled, let self, let controller else { return }
            publishTask = nil
            controller.update(blockHeights: currentHeights)
        }
    }

    private var currentHeights: [Int: Double] {
        idsByIndex.reduce(into: [Int: Double]()) { result, item in
            if let height = heightsByID[item.value] {
                result[item.key] = height
            }
        }
    }
}
