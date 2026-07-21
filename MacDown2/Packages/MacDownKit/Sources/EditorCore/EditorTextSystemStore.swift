import Foundation

/// Caches one ``EditorTextSystem`` per tab identity.
///
/// A single store is owned per window so that tab switches within a window
/// reuse the same text system. Closing a tab must call ``evict(_:)`` to tear
/// down the text system and avoid retaining the underlying NSTextView graph.
@MainActor
public final class EditorTextSystemStore {
    private var systems: [String: EditorTextSystem] = [:]

    public init() {}

    /// Returns an existing system for `identity`, or `nil` if one has not been
    /// created yet.
    public func existingSystem(for identity: String) -> EditorTextSystem? {
        systems[identity]
    }

    /// Returns an existing system for `identity`, or creates one with the given
    /// initial text and configuration.
    public func system(
        for identity: String,
        initialText: String,
        configuration: EditorConfiguration
    ) -> EditorTextSystem {
        if let existing = systems[identity] {
            return existing
        }
        let newSystem = EditorTextSystem(
            identity: identity,
            initialText: initialText,
            configuration: configuration
        )
        systems[identity] = newSystem
        return newSystem
    }

    /// Removes the cached system for `identity` and breaks the reference to the
    /// underlying AppKit objects so they deallocate.
    public func evict(_ identity: String) {
        systems[identity]?.prepareForDeallocation()
        systems.removeValue(forKey: identity)
    }

    /// Removes every cached system. Call when the owning window closes.
    public func evictAll() {
        for system in systems.values {
            system.prepareForDeallocation()
        }
        systems.removeAll()
    }

    /// The identities currently held in the cache. Exposed for testing.
    public var liveIdentities: Set<String> {
        Set(systems.keys)
    }
}
