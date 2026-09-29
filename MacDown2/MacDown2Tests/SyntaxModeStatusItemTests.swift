import FileCore
@testable import MacDown2
import Testing

@Suite("SyntaxModeStatusItem (Slice 9d)")
struct SyntaxModeStatusItemTests {
    private func format(_ id: String) throws -> FileFormat {
        try #require(FileFormatRegistry.defaultFormats.first { $0.id == id })
    }

    private func item(
        auto: String,
        syntax: String,
        onSelect: @escaping (String?) -> Void = { _ in }
    ) throws -> SyntaxModeStatusItem {
        try SyntaxModeStatusItem(
            autoFormat: format(auto),
            syntaxFormat: format(syntax),
            onSelect: onSelect
        )
    }

    @Test func automaticDetectionReportsTheFilesOwnFormat() throws {
        let status = try item(auto: "markdown", syntax: "markdown")
        #expect(!status.isOverridden)
        #expect(status.effective == status.automatic)
    }

    @Test func anOverrideIsFlaggedAndKeepsTheAutomaticFormatAvailable() throws {
        let status = try item(auto: "markdown", syntax: "python")
        #expect(status.isOverridden)
        #expect(status.effective.id == "python")
        #expect(status.automatic.id == "markdown")
    }

    @Test func choicesCoverEveryRegisteredFormatSortedByName() throws {
        let status = try item(auto: "markdown", syntax: "markdown")
        #expect(Set(status.choices.map(\.id)) == Set(FileFormatRegistry.defaultFormats.map(\.id)))
        let names = status.choices.map(\.name)
        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    @Test func selectionForwardsTheChosenIDOrNilForAutomatic() throws {
        var received: [String?] = []
        let status = try item(auto: "markdown", syntax: "markdown") { received.append($0) }
        status.onSelect("tex")
        status.onSelect(nil)
        #expect(received == ["tex", nil])
    }
}
