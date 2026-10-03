@testable import FileCore
import Foundation
import Testing

/// Detection names an encoding only on strong, checkable evidence; ambiguous
/// bytes return nil so the caller must ask the user.
struct ConservativeEncodingDetectionTests {
    private func detect(_ data: Data) -> FileEncodingMetadata? {
        FileStore.conservativelyDetectedEncoding(of: data)
    }

    @Test func bomLessUTF16LittleEndianAsciiTextIsDetected() throws {
        let data = try #require("Hello, world\nsecond line\n".data(using: .utf16LittleEndian))
        #expect(detect(data) == FileEncodingMetadata(encoding: .utf16LittleEndian, bom: .none))
    }

    @Test func bomLessUTF16BigEndianLatinTextIsDetected() throws {
        let data = try #require("café au lait\n".data(using: .utf16BigEndian))
        #expect(detect(data) == FileEncodingMetadata(encoding: .utf16BigEndian, bom: .none))
    }

    @Test func legacySingleByteTextIsNeverGuessed() {
        // "café" in Latin-1: valid text in many encodings — the user must choose.
        #expect(detect(Data([0x63, 0x61, 0x66, 0xE9, 0x0A])) == nil)
        #expect(detect(Data([0x63, 0x61, 0x66, 0xE9])) == nil)
    }

    @Test func cjkUTF16WithoutZeroBytesIsNotGuessed() throws {
        let data = try #require("日本語のテキスト".data(using: .utf16LittleEndian))
        #expect(detect(data) == nil)
    }

    @Test func binaryWithEmbeddedNULsIsNotTextEvenIfPatterned() {
        #expect(detect(Data([0x41, 0x00, 0x00, 0x00, 0x42, 0x00])) == nil)
    }

    @Test func tooShortOrOddLengthInputIsRejected() {
        #expect(detect(Data()) == nil)
        #expect(detect(Data([0x41])) == nil)
        #expect(detect(Data([0x41, 0x00, 0x42])) == nil)
    }
}
