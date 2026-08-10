import Foundation
import Observation

@MainActor
public protocol FileTreePreferenceStoring: Sendable {
    var filter: FileTreeFilter { get set }
    var opensOnSingleClick: Bool { get set }
    var recentRootBookmarks: [Data] { get set }
}

@MainActor
public struct UserDefaultsFileTreePreferenceStore: FileTreePreferenceStoring {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var filter: FileTreeFilter {
        get {
            defaults.data(forKey: "fileTree.filter")
                .flatMap { try? JSONDecoder().decode(FileTreeFilter.self, from: $0) } ?? FileTreeFilter()
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "fileTree.filter") }
    }

    public var opensOnSingleClick: Bool {
        get { defaults.bool(forKey: "fileTree.opensOnSingleClick") }
        set { defaults.set(newValue, forKey: "fileTree.opensOnSingleClick") }
    }

    public var recentRootBookmarks: [Data] {
        get { defaults.array(forKey: "fileTree.recentRoots") as? [Data] ?? [] }
        set { defaults.set(newValue, forKey: "fileTree.recentRoots") }
    }
}

@MainActor @Observable
public final class FileTreePreferences {
    public var filter: FileTreeFilter {
        didSet { store.filter = filter; notifyObservers() }
    }

    public var opensOnSingleClick: Bool {
        didSet { store.opensOnSingleClick = opensOnSingleClick; notifyObservers() }
    }

    var store: any FileTreePreferenceStoring
    private var observers: [UUID: @MainActor () -> Void] = [:]
    public init(store: any FileTreePreferenceStoring = UserDefaultsFileTreePreferenceStore()) {
        self.store = store; filter = store.filter; opensOnSingleClick = store.opensOnSingleClick
    }

    @discardableResult
    public func addObserver(_ observer: @escaping @MainActor () -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }

    public func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    private func notifyObservers() {
        for observer in observers.values {
            observer()
        }
    }
}
