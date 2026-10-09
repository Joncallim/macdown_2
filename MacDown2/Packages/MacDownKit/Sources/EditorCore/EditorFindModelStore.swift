import Foundation

/// Caches one ``EditorFindModel`` per tab identity (EPIC-22 §6.14, Slice 5a).
///
/// Mirrors ``EditorTextSystemStore``'s own per-identity caching exactly: a
/// single store is owned per window so that switching tabs and back
/// preserves that tab's own find query/options/match state instead of
/// resetting it, and closing a tab evicts its model so a stale query for a
/// document that no longer exists cannot leak into a future tab that
/// happens to reuse the same identity slot.
@MainActor
public final class EditorFindModelStore {
    private var models: [String: EditorFindModel] = [:]

    public init() {}

    /// Returns an existing model for `identity`, or `nil` if one has not been
    /// created yet.
    public func existingModel(for identity: String) -> EditorFindModel? {
        models[identity]
    }

    /// Returns an existing model for `identity`, or creates a fresh
    /// (inactive, empty-query) one.
    public func model(for identity: String) -> EditorFindModel {
        if let existing = models[identity] {
            return existing
        }
        let created = EditorFindModel()
        models[identity] = created
        return created
    }

    /// Removes the cached model for `identity`. Call when the tab closes.
    public func evict(_ identity: String) {
        models.removeValue(forKey: identity)
    }

    /// Removes every cached model. Call when the owning window closes.
    public func evictAll() {
        models.removeAll()
    }

    /// The identities currently held in the cache. Exposed for testing.
    public var liveIdentities: Set<String> {
        Set(models.keys)
    }
}
