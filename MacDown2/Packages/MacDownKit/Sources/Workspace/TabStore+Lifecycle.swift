import FileCore
import Foundation

@MainActor
extension TabStore {
    func tabIndex(of id: UUID) -> Int? {
        tabs.firstIndex { $0.id == id }
    }

    func removeTab(at index: Int) {
        let removedID = tabs[index].id
        tabs.remove(at: index)
        if activeTabID == removedID {
            activeTabID = nextActiveTabID(afterRemovingTabAt: index)
        }
    }

    func nextActiveTabID(afterRemovingTabAt removedIndex: Int) -> UUID? {
        for offset in 1 ..< max(removedIndex + 1, tabs.count - removedIndex + 1) {
            let leftIndex = removedIndex - offset
            if leftIndex >= 0, leftIndex < tabs.count {
                return tabs[leftIndex].id
            }
            let rightIndex = removedIndex + offset - 1
            if rightIndex >= 0, rightIndex < tabs.count {
                return tabs[rightIndex].id
            }
        }
        return nil
    }

    func persist() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self else { return }
            saveTask = nil
            await saveSession()
        }
    }
}
