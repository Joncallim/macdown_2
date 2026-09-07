import Foundation
import Testing
@testable import TextFilters

@Suite("TextFilterLaunchContext")
struct TextFilterLaunchContextTests {
    private static let home = URL(fileURLWithPath: "/Users/fixture-home")
    private static let tmp = URL(fileURLWithPath: "/private/tmp/fixture-tmp")

    @Test func usesTheDocumentsContainingFolderAsWorkingDirectory() {
        let documentURL = URL(fileURLWithPath: "/Users/fixture-home/Documents/notes.md")
        let context = TextFilterLaunchContext(
            documentURL: documentURL, selectionLength: 0, homeDirectoryURL: Self.home, temporaryDirectoryURL: Self.tmp
        )
        #expect(context.workingDirectoryURL == URL(fileURLWithPath: "/Users/fixture-home/Documents", isDirectory: true))
    }

    @Test func usesHomeDirectoryForAnUntitledDocument() {
        let context = TextFilterLaunchContext(
            documentURL: nil, selectionLength: 0, homeDirectoryURL: Self.home, temporaryDirectoryURL: Self.tmp
        )
        #expect(context.workingDirectoryURL == Self.home)
    }

    @Test func environmentIsExactlyTheDocumentedFixedSet() {
        let documentURL = URL(fileURLWithPath: "/Users/fixture-home/notes.md")
        let context = TextFilterLaunchContext(
            documentURL: documentURL, selectionLength: 42, homeDirectoryURL: Self.home, temporaryDirectoryURL: Self.tmp
        )

        #expect(Set(context.environment.keys) == [
            "PATH",
            "HOME",
            "TMPDIR",
            "MACDOWN_DOCUMENT_PATH",
            "MACDOWN_SELECTION_LENGTH",
        ])
        #expect(context.environment["PATH"] == "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin")
        #expect(context.environment["HOME"] == Self.home.path)
        #expect(context.environment["TMPDIR"] == Self.tmp.path)
        #expect(context.environment["MACDOWN_DOCUMENT_PATH"] == documentURL.path)
        #expect(context.environment["MACDOWN_SELECTION_LENGTH"] == "42")
    }

    @Test func omitsDocumentPathForAnUntitledDocument() {
        let context = TextFilterLaunchContext(
            documentURL: nil, selectionLength: 0, homeDirectoryURL: Self.home, temporaryDirectoryURL: Self.tmp
        )
        #expect(context.environment["MACDOWN_DOCUMENT_PATH"] == nil)
        #expect(Set(context.environment.keys) == ["PATH", "HOME", "TMPDIR", "MACDOWN_SELECTION_LENGTH"])
    }
}
