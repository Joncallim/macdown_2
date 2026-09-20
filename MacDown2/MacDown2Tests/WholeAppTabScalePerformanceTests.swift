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

/// E15 whole-app performance evidence: a real, non-mocked measurement of the
/// two operations that are actually expensive when many tabs are open.
///
/// `TabStore` itself does no parsing/highlighting/layout -- it is pure state.
/// The real cost lives in `WindowController`'s per-tab-identity caches
/// (`EditorTextSystemStore`, `SyntaxHighlightStore`): the *first* visit to a
/// tab builds a real `EditorTextSystem` (NSTextView/NSTextLayoutManager
/// graph) and a real `NeonSyntaxHighlighter` (tree-sitter grammar setup);
/// every later visit is a dictionary hit. So the meaningful evidence is (1)
/// how long materializing a realistic 20-tab session takes, and (2) that
/// re-visiting those same 20 tabs (a "switch") is dramatically cheaper,
/// proving the cache actually avoids re-parsing/re-highlighting rather than
/// assuming the architecture works as documented.
@MainActor
@Suite("Whole-app tab-scale performance (E15)")
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
        let tabs: [SyntheticTab]
    }

    private static func makeFixture(tabCount: Int) -> Fixture {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let recoveryBuffer = RecoveryBuffer(recoveryDirectory: rootDirectory.appendingPathComponent("Recovery"))
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            recoveryBuffer: recoveryBuffer,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            appSettings: AppSettingsModel()
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
        return Fixture(controller: controller, rootDirectory: rootDirectory, tabs: tabs)
    }

    /// Releases the real `EditorTextSystem`/`NeonSyntaxHighlighter` graphs
    /// `materialize` builds (up to `tabCount` of each — genuine
    /// `NSTextView`/tree-sitter objects, not lightweight fakes), exactly as
    /// `WindowController.windowWillClose` does. Left uncollected, they
    /// stay live for the rest of this process's test run (Swift Testing
    /// runs every suite in one process) and starve later suites of the
    /// same real AppKit/tree-sitter resources this test intentionally
    /// exercises at scale -- this was caught as a real, reproduced failure
    /// in `PaletteOriginTargetingTests` on CI before this teardown existed.
    private static func tearDown(_ fixture: Fixture) {
        fixture.controller.editorStore.evictAll()
        fixture.controller.highlightStore.evictAll()
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

    @Test func materializingTwentyTabsCompletesWithinBudget() {
        let fixture = Self.makeFixture(tabCount: Self.tabCount)
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

    @Test func switchingAcrossTwentyAlreadyOpenTabsIsCheapRelativeToFirstOpen() {
        let fixture = Self.makeFixture(tabCount: Self.tabCount)
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
