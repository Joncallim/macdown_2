import AppKit
import Foundation
import Workspace

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var coordinator: WindowCoordinator!
    private let sessionStore: WorkspaceSessionStoring
    private let launchURLs: [URL]

    override init() {
        let args = ProcessInfo.processInfo.arguments
        let isUITesting = args.contains("-UITesting")

        if isUITesting {
            let sessionDir = Self.sessionDirectory(from: args)
            try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
            sessionStore = WorkspaceSessionStore(fileURL: sessionDir.appendingPathComponent("session.json"))
        } else {
            sessionStore = WorkspaceSessionStore()
        }

        launchURLs = Self.openFilesPaths(from: args).map { URL(fileURLWithPath: $0) }
        super.init()

        coordinator = WindowCoordinator(
            sessionStore: sessionStore,
            panelProvider: NSFilePanelProvider()
        )
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true

        // Close the placeholder SwiftUI window so we can manage document
        // windows ourselves.
        NSApp.windows.first?.close()

        Task { @MainActor in
            if !launchURLs.isEmpty {
                for url in launchURLs {
                    await coordinator.openDocument(at: url)
                }
            } else {
                await coordinator.restoreSessionIfNeeded()
            }
        }
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await coordinator.saveSession()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            coordinator.newDocument()
        }
        return true
    }

    // MARK: - Launch argument parsing

    private static func sessionDirectory(from args: [String]) -> URL {
        if let index = args.firstIndex(of: "-sessionDir"), index + 1 < args.count {
            return URL(fileURLWithPath: args[index + 1])
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private static func openFilesPaths(from args: [String]) -> [String] {
        if let index = args.firstIndex(of: "-openFiles"), index + 1 < args.count {
            let remainder = args[index + 1]
            return remainder.split(separator: ",", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        if let arg = args.first(where: { $0.hasPrefix("-openFiles") }) {
            let prefix = "-openFiles"
            let remainder = String(arg.dropFirst(prefix.count))
            return remainder.split(separator: ",", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        return []
    }
}
