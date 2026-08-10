import Foundation

public final class FolderAccessScope: @unchecked Sendable {
    public let url: URL
    public let started: Bool
    public init(url: URL) {
        self.url = url; started = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if started {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
