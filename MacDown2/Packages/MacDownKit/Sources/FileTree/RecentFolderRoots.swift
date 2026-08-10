import FileCore
import Foundation
import Observation

@MainActor @Observable
public final class RecentFolderRoots {
    private struct StoredRoot: Codable {
        let bookmark: Data
        let lexicalURL: URL
    }

    public private(set) var roots: [URL] = []
    private let preferences: FileTreePreferences
    private var bookmarks: [Data] = []
    public init(preferences: FileTreePreferences) {
        self.preferences = preferences; reload()
    }

    public func record(_ url: URL) {
        let standardized = url.standardizedFileURL
        // Store access against the physical object, while retaining the lexical
        // URL as the user-facing label and tree root.
        let physical = standardized.resolvingSymlinksInPath().standardizedFileURL
        guard let bookmark = try? physical.bookmarkData(options: .withSecurityScope) else { return }
        var updated = zip(roots, bookmarks).filter { !PhysicalFileIdentity.matches($0.0, standardized) }
        updated.insert((standardized, stored(bookmark: bookmark, lexicalURL: standardized)), at: 0)
        updated = Array(updated.prefix(10))
        roots = updated.map(\.0)
        bookmarks = updated.map(\.1)
        save()
    }

    public func resolve(_ url: URL) -> URL? {
        guard let index = roots.firstIndex(where: { PhysicalFileIdentity.matches($0, url) })
        else { return nil }
        var stale = false
        let record = unpack(bookmarks[index], fallbackLexicalURL: roots[index])
        guard let resolved = try? URL(
            resolvingBookmarkData: record.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            roots.remove(at: index)
            bookmarks.remove(at: index)
            save()
            return nil
        }
        let scope = FolderAccessScope(url: resolved)
        let standardized = resolved.standardizedFileURL
        // The lexical alias remains the displayed/reopened root when it still
        // refers to the bookmark's physical target.
        if !PhysicalFileIdentity.matches(roots[index], standardized) {
            roots[index] = standardized
        }
        if stale, let refreshed = try? standardized.bookmarkData(options: .withSecurityScope) {
            bookmarks[index] = stored(bookmark: refreshed, lexicalURL: roots[index])
            save()
        }
        _ = scope
        return standardized
    }

    public func clear() {
        roots = []; bookmarks = []
        storeBookmarks([])
    }

    public func remap(from old: URL, to new: URL) {
        let oldComponents = old.standardizedFileURL.pathComponents
        var changed = false
        roots = roots.map { root in
            let components = root.standardizedFileURL.pathComponents
            guard components.starts(with: oldComponents) else { return root }
            changed = true
            let suffix = components.dropFirst(oldComponents.count).joined(separator: "/")
            return suffix.isEmpty
                ? new.standardizedFileURL
                : new.appendingPathComponent(suffix, isDirectory: true).standardizedFileURL
        }
        if changed {
            // A root move invalidates an old path bookmark. Keep it until the
            // replacement succeeds, so a bookmark generation failure cannot
            // discard the last valid access grant.
            for index in roots.indices {
                let physical = roots[index].resolvingSymlinksInPath().standardizedFileURL
                if let refreshed = try? physical.bookmarkData(options: .withSecurityScope) {
                    bookmarks[index] = stored(bookmark: refreshed, lexicalURL: roots[index])
                }
            }
            save()
        }
    }

    private func reload() {
        roots = []
        bookmarks = []
        var changed = false
        var seen: [URL] = []
        for data in storedBookmarks() {
            let record = unpack(data, fallbackLexicalURL: nil)
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: record.bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else {
                changed = true
                continue
            }
            let resolved = url.standardizedFileURL
            let lexical = record.lexicalURL ?? resolved
            guard !seen.contains(where: { PhysicalFileIdentity.matches($0, lexical) }), roots.count < 10 else {
                changed = true
                continue
            }
            seen.append(lexical)
            roots.append(lexical)
            let scope = FolderAccessScope(url: resolved)
            if stale, let refreshed = try? resolved.bookmarkData(options: .withSecurityScope) {
                bookmarks.append(stored(bookmark: refreshed, lexicalURL: lexical))
                changed = true
            } else {
                bookmarks.append(data)
            }
            _ = scope
        }
        if changed {
            save()
        }
    }

    private func save() {
        storeBookmarks(bookmarks)
    }

    private func stored(bookmark: Data, lexicalURL: URL) -> Data {
        let record = StoredRoot(bookmark: bookmark, lexicalURL: lexicalURL)
        return (try? JSONEncoder().encode(record)) ?? bookmark
    }

    private func unpack(_ data: Data, fallbackLexicalURL: URL?) -> (bookmark: Data, lexicalURL: URL?) {
        if let record = try? JSONDecoder().decode(StoredRoot.self, from: data) {
            return (record.bookmark, record.lexicalURL)
        }
        return (data, fallbackLexicalURL)
    }

    private func storedBookmarks() -> [Data] {
        preferences.recentRootBookmarks()
    }

    private func storeBookmarks(_ bookmarks: [Data]) {
        preferences.storeRecentRootBookmarks(bookmarks)
    }
}

@MainActor private extension FileTreePreferences {
    func recentRootBookmarks() -> [Data] {
        store.recentRootBookmarks
    }

    func storeRecentRootBookmarks(_ bookmarks: [Data]) {
        store.recentRootBookmarks = bookmarks
    }
}
