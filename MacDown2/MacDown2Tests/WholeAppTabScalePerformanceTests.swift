import AppSettings
import EditorCore
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// E15 measures real text-system/highlighter cache construction and subsequent cache hits for 20 identities in
/// one window controller. It does not measure opening or switching 20 native NSWindow tabs; that requires the
/// native UI matrix. `TabStore` is pure state, while these caches build real AppKit and tree-sitter objects.
@MainActor
@Suite("Window cache materialization performance (E15)")
struct WholeAppTabScalePerformanceTests {
    private static let tabCount = 20

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1000.0 + Double(components.attoseconds) / 1e15
    }

    /// Deterministic, varied-size Markdown so the 20 tabs aren't 20 copies of
    /// one string -- mirrors a real editing session with documents of
    /// different lengths. Same generator shape as
    /// `MarkdownEngineTests/Fixtures.swift.markdown(targetByteCount:)`;
    /// duplicated locally because SPM test targets cannot import each
    /// other's internal fixtures.
    private static func markdown(targetByteCount: Int) -> String {
        let paragraph = "The quick brown fox jumps over the lazy dog.\n\n"
        let paragraphCount = max(1, targetByteCount / paragraph.utf8.count)
        var result = ""
        result.reserveCapacity(targetByteCount)
        for index in 0 ..< paragraphCount {
            switch index % 6 {
            case 0:
                result += "# Heading \(index)\n\n"
                result += paragraph
            case 1:
                result += "- List item \(index)-a\n- List item \(index)-b\n\n"
            case 2:
                result += "> A blockquote that spans a few words.\n\n"
            case 3:
                result += "```swift\nlet x = \(index)\nlet y = x + 1\n```\n\n"
            case 4:
                result += "| A | B |\n|---|---|\n| 1 | 2 |\n\n"
            default:
                result += paragraph
            }
            if result.utf8.count >= targetByteCount {
                break
            }
        }
        return result
    }

    private struct SyntheticTab {
        let identity: String
        let document: FileDocument
    }

    private struct Fixture {
        let controller: WindowController
        let rootDirectory: URL
        let preferencesSuite: String
        let tabs: [SyntheticTab]
    }

    private static func makeFixture(tabCount: Int) throws -> Fixture {
        let preferencesSuite = "com.joncallim.macdown2.tab-scale-test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: preferencesSuite))
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let recoveryBuffer = RecoveryBuffer(recoveryDirectory: rootDirectory.appendingPathComponent("Recovery"))
        let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        let coordinator = WindowCoordinator(
            sessionStore: LaunchSessionStore(session: .empty),
            recoveryBuffer: recoveryBuffer,
            themeController: ThemeController(
                preferenceStore: UserDefaultsThemePreferenceStore(suiteName: preferencesSuite)
            ),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel(store: UserDefaultsAppSettingsStore(defaults: defaults)),
            workspaceStateStore: WorkspaceStateStore(defaults: defaults)
        )
        let controller = WindowController(
            model: coordinator.makeWindowModel(),
            coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]

        // Realistic 20-25 KB-200 KB spread, not 20 identical documents.
        let tabs = (0 ..< tabCount).map { index -> SyntheticTab in
            let targetByteCount = 20000 + index * 9000
            let document = FileDocument(
                text: markdown(targetByteCount: targetByteCount),
                recoveryBuffer: recoveryBuffer
            )
            let id = UUID()
            controller.model.tabStore.newTab(id: id, document: document)
            return SyntheticTab(identity: id.uuidString, document: document)
        }
        return Fixture(
            controller: controller, rootDirectory: rootDirectory, preferencesSuite: preferencesSuite, tabs: tabs
        )
    }

    /// Retire the real window through its normal lifecycle. Evicting only the editor/highlighter caches leaves
    /// its hosted preview, parse sessions and observers alive, doing work during later tests in the same process.
    private static func tearDown(_ fixture: Fixture) {
        fixture.controller.coordinator?.removeController(fixture.controller)
        fixture.controller.close()
        UserDefaults.standard.removePersistentDomain(forName: fixture.preferencesSuite)
        try? FileManager.default.removeItem(at: fixture.rootDirectory)
    }

    /// Builds the real per-tab caches exactly as `WindowController` does for
    /// the active tab in production (`makeSessionsForActiveTab`), applied
    /// here to every tab instead of just the active one.
    private static func materialize(_ tab: SyntheticTab, in controller: WindowController) {
        let textSystem = controller.editorStore.system(
            for: tab.identity,
            initialText: tab.document.text,
            configuration: .default
        )
        _ = controller.highlightStore.highlighter(
            for: tab.identity,
            textSystem: textSystem,
            languageID: tab.document.format.highlightLanguageID,
            theme: controller.themeController.current
        )
    }

    @Test func teardownRetiresTheWindowAndItsBackgroundWork() throws {
        let fixture = try Self.makeFixture(tabCount: 1)
        let coordinator = try #require(fixture.controller.coordinator)
        defer {
            coordinator.removeController(fixture.controller)
            fixture.controller.close()
        }
        _ = fixture.controller.parseStore.session(for: "teardown-probe")

        Self.tearDown(fixture)

        #expect(fixture.controller.isClosed)
        #expect(fixture.controller.externalFileController.disposed)
        #expect(!coordinator.controllers.contains { $0 === fixture.controller })
        #expect(fixture.controller.parseStore.existingSession(for: "teardown-probe") == nil)
    }

    @Test func materializingTwentyTabsCompletesWithinBudget() throws {
        let fixture = try Self.makeFixture(tabCount: Self.tabCount)
        defer { Self.tearDown(fixture) }

        let duration = ContinuousClock().measure {
            for tab in fixture.tabs {
                Self.materialize(tab, in: fixture.controller)
            }
        }

        let elapsedMS = Self.milliseconds(duration)
        #expect(elapsedMS < 5000, "Materializing \(Self.tabCount) tabs took \(elapsedMS) ms (budget 5000 ms)")
        #expect(fixture.controller.editorStore.liveIdentities.count == Self.tabCount)
    }

    @Test func switchingAcrossTwentyAlreadyOpenTabsIsCheapRelativeToFirstOpen() throws {
        let fixture = try Self.makeFixture(tabCount: Self.tabCount)
        defer { Self.tearDown(fixture) }

        let firstOpenDuration = ContinuousClock().measure {
            for tab in fixture.tabs {
                Self.materialize(tab, in: fixture.controller)
            }
        }

        // Revisiting every tab a second time is what a real tab switch does:
        // both stores must hit their cache rather than rebuild anything.
        let switchDuration = ContinuousClock().measure {
            for tab in fixture.tabs {
                Self.materialize(tab, in: fixture.controller)
            }
        }

        let firstOpenMS = Self.milliseconds(firstOpenDuration)
        let switchMS = Self.milliseconds(switchDuration)
        #expect(
            switchMS < 50,
            "Re-visiting \(Self.tabCount) already-open tabs took \(switchMS) ms (budget 50 ms, must stay a cache hit)"
        )
        #expect(
            switchMS < firstOpenMS,
            "Switching (\(switchMS) ms) should be cheaper than first materialization (\(firstOpenMS) ms)"
        )
    }
}
