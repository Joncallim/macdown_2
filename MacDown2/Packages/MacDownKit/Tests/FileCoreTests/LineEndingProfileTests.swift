import FileCore
import Foundation
import Testing

@Suite("LineEndingProfile")
struct LineEndingProfileTests {
    @Test(arguments: [
        ("", LineEndingProfile.Kind.none),
        ("no terminator", .none),
        ("a\nb\n", .lineFeed),
        ("a\r\nb\r\n", .crlf),
        ("a\rb\r", .carriageReturn),
        ("a\nb\r\n", .mixed),
        ("a\rb\n", .mixed),
        ("a\r\nb\r", .mixed),
    ])
    func classifiesKind(text: String, kind: LineEndingProfile.Kind) {
        #expect(LineEndingProfile(detecting: text).kind == kind)
    }

    @Test func crlfIsOneTerminatorNotAnLFPlusACR() {
        let profile = LineEndingProfile(detecting: "a\r\nb\r\nc")
        #expect(profile.crlfCount == 2)
        #expect(profile.lfCount == 0)
        #expect(profile.crCount == 0)
    }

    @Test func countsEachKindInMixedText() {
        let profile = LineEndingProfile(detecting: "1\n2\n3\r\n4\r5\r\n6\n")
        #expect(profile.lfCount == 3)
        #expect(profile.crlfCount == 2)
        #expect(profile.crCount == 1)
        #expect(profile.dominantEnding == .lineFeed)
    }

    @Test func aTrailingCRFollowedByLFAcrossNoOtherByteIsCRLF() {
        #expect(LineEndingProfile(detecting: "\r\n").kind == .crlf)
        #expect(LineEndingProfile(detecting: "\r\r\n").crCount == 1)
        #expect(LineEndingProfile(detecting: "\r\r\n").crlfCount == 1)
    }

    @Test func unicodeLineSeparatorsAreNotTerminators() {
        #expect(LineEndingProfile(detecting: "a\u{2028}b\u{2029}c\u{85}d").kind == .none)
    }

    @Test func uniformAndDominantEndings() {
        #expect(LineEndingProfile(detecting: "a\r\nb").uniformEnding == .crlf)
        #expect(LineEndingProfile(detecting: "a\nb\r\n").uniformEnding == nil)
        #expect(LineEndingProfile(detecting: "text").dominantEnding == nil)
        #expect(LineEndingProfile(detecting: "a\r\nb\r\nc\n").dominantEnding == .crlf)
    }

    @Test func terminatorText() {
        #expect(LineEnding.lineFeed.text == "\n")
        #expect(LineEnding.crlf.text == "\r\n")
        #expect(LineEnding.carriageReturn.text == "\r")
    }

    @Test(arguments: ["a\nb\n", "a\r\nb\r\n", "a\rb\r", "a\nb\r\nc\rd"])
    func profileIsPreservedAcrossARealFileRoundTrip(text: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.md")

        let store = FileStore()
        try store.write(text, to: url)
        let reread = try store.readSnapshot(from: url)

        #expect(LineEndingProfile(detecting: reread.text) == LineEndingProfile(detecting: text))
        #expect(reread.text == text)
    }

    @Test func aLargeDocumentIsClassifiedCorrectly() {
        let text = String(repeating: "line\r\n", count: 200_000)
        let profile = LineEndingProfile(detecting: text)
        #expect(profile.kind == .crlf)
        #expect(profile.crlfCount == 200_000)
    }
}
