@testable import FileCore
import Foundation
import Testing

@Test func caseSensitiveFallbackDoesNotRetargetOrCloseDifferentCasePaths() {
    let lower = URL(fileURLWithPath: "/case-sensitive/foo.md")
    let upper = URL(fileURLWithPath: "/case-sensitive/FOO.md")

    let lowerIdentity = PhysicalFileIdentity(url: lower, volumeSupportsCaseSensitiveNames: true)
    let upperIdentity = PhysicalFileIdentity(url: upper, volumeSupportsCaseSensitiveNames: true)

    #expect(!PhysicalFileIdentity.matches(lowerIdentity, upperIdentity))
}

@Test func unknownVolumeFallbackDoesNotFoldUnicodeOrCase() {
    let composed = URL(fileURLWithPath: "/unknown/Café.md")
    let unaccented = URL(fileURLWithPath: "/unknown/Cafe.md")
    let upper = URL(fileURLWithPath: "/unknown/CAFÉ.md")

    let original = PhysicalFileIdentity(url: composed, volumeSupportsCaseSensitiveNames: nil)
    #expect(!PhysicalFileIdentity.matches(
        original,
        PhysicalFileIdentity(url: unaccented, volumeSupportsCaseSensitiveNames: nil)
    ))
    #expect(!PhysicalFileIdentity.matches(
        original,
        PhysicalFileIdentity(url: upper, volumeSupportsCaseSensitiveNames: nil)
    ))
}
