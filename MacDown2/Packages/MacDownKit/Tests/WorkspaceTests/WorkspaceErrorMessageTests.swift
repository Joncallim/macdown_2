import Foundation
import Testing
@testable import Workspace

/// Review pass 7: text starting with an invisible U+FEFF can never be saved without a BOM, but the error said only
/// "cannot be saved as UTF-8 without losing characters" — wrong for UTF-8 and giving no hint which character was the
/// problem (an invisible one), so the user could not save and could not tell why.
struct WorkspaceErrorMessageTests {
    @Test func theUnrepresentableTextMessageNamesTheInvisibleLeadingCharacters() throws {
        let message = try #require(WorkspaceError.textNotRepresentable(encodingName: "UTF-8").errorDescription)

        #expect(message.contains("UTF-8"))
        #expect(message.contains("U+FEFF"))
        #expect(message.contains("U+FFFE"))
    }
}
