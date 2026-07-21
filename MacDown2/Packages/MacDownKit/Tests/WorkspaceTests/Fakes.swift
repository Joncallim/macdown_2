import Foundation
import Workspace

@MainActor
final class FakeStateStore: WorkspaceStateStoring {
    var sidebarVisible: Bool = true
    var sidebarSectionExpanded: [String: Bool] = [:]
}

@MainActor
final class FakeSessionStore: WorkspaceSessionStoring {
    private(set) var savedSession: WorkspaceSession?

    func loadSession() -> WorkspaceSession? {
        savedSession
    }

    func saveSession(_ session: WorkspaceSession) {
        savedSession = session
    }
}

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}
