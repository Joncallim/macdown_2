import FileCore
import Foundation
@testable import MacDown2
import Testing

/// Review pass 5: `toml` was a registered `FileFormat` with an exported UTI but no `CFBundleDocumentTypes` entry, so
/// Finder's Open With, Dock drops and default-app selection never offered the app for `.toml` files.
struct DocumentTypeRegistrationTests {
    @Test func everyRegisteredFormatExtensionIsADeclaredDocumentType() throws {
        let declared = try #require(Bundle(for: AppDelegate.self).object(
            forInfoDictionaryKey: "CFBundleDocumentTypes"
        ) as? [[String: Any]])
        let extensions = Set(declared.flatMap { ($0["CFBundleTypeExtensions"] as? [String]) ?? [] })

        let missing = FileFormatRegistry().formats.flatMap(\.extensions).filter { !extensions.contains($0) }

        #expect(missing.isEmpty, "undeclared extensions: \(missing)")
    }
}
