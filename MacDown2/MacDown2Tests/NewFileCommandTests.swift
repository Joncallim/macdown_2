@testable import MacDown2
import Testing

/// Review pass 1: ⌘N was disabled whenever no folder was open — i.e. dead on a
/// fresh launch. It now falls back to a blank document.
@MainActor
struct NewFileCommandTests {
    @Test func withAFolderOpenNewFileCreatesInThatFolder() {
        #expect(WindowCoordinator.NewFileTarget.resolve(hasKeyFolder: true) == .fileInKeyFolder)
    }

    @Test func withNoFolderNewFileOpensABlankDocument() {
        #expect(WindowCoordinator.NewFileTarget.resolve(hasKeyFolder: false) == .blankDocument)
    }
}
