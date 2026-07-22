import AppKit
import Foundation
import Highlighting
import Themes
import Workspace

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var coordinator: WindowCoordinator!
    private(set) var themeController: ThemeController!
    private(set) var grammarRegistry: GrammarRegistry!
    private let sessionStore: WorkspaceSessionStoring
    private let launchURLs: [URL]
    private var hasPendingDocumentOpen = false

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
        themeController = ThemeController()
        grammarRegistry = GrammarRegistry()
        super.init()

        coordinator = WindowCoordinator(
            sessionStore: sessionStore,
            panelProvider: NSFilePanelProvider(),
            themeController: themeController,
            grammarRegistry: grammarRegistry
        )
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        syncThemeAppearance()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemAppearanceChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )

        // Close any placeholder SwiftUI windows so we can manage document
        // windows ourselves. The `WindowGroup { EmptyView() }` scene creates
        // one or more windows that do not have a `WindowController` delegate.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            for window in NSApp.windows where !(window.delegate is WindowController) {
                window.close()
            }
        }

        Task { @MainActor in
            if !launchURLs.isEmpty {
                for url in launchURLs {
                    await coordinator.openDocument(at: url)
                }
            } else {
                // Give `application(_:openFiles:)` a few run-loop ticks to arrive
                // before we fall back to creating an empty untitled document.
                try? await Task.sleep(for: .milliseconds(200))
                if !hasPendingDocumentOpen {
                    await coordinator.restoreSessionIfNeeded()
                }
            }
        }
    }

    @objc private func systemAppearanceChanged() {
        syncThemeAppearance()
    }

    private func syncThemeAppearance() {
        themeController.setAppearance(NSApp.effectiveAppearance.themeAppearance)
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

    func application(_: NSApplication, openFiles filenames: [String]) {
        hasPendingDocumentOpen = true
        Task { @MainActor in
            for filename in filenames {
                await coordinator.openDocument(at: URL(fileURLWithPath: filename))
            }
        }
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

extension NSAppearance {
    var themeAppearance: ThemeAppearance {
        if bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return .dark
        }
        return .light
    }
}
