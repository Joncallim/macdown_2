import Foundation

/// Pure, AppKit-free character-detection logic for invisible-character
/// markers (epic-22-implementation.md §6.8). Scope is exactly issue #112's
/// "spaces, tabs and line endings become visible" — no NBSP or other
/// Unicode space variants, which is a plausible future follow-up but not
/// asked for here.
public enum EditorInvisiblesLayout {
    public struct Marker: Equatable {
        /// UTF-16 offset of the marked character, relative to the start of
        /// the text passed to `markers(in:)` — the caller (an
        /// `NSTextLineFragment`'s own text) is responsible for translating
        /// this into whatever coordinate space its own APIs expect.
        public let localUTF16Offset: Int
        public let glyph: String

        public init(localUTF16Offset: Int, glyph: String) {
            self.localUTF16Offset = localUTF16Offset
            self.glyph = glyph
        }
    }

    public static let spaceGlyph = "\u{00B7}" // ·
    public static let tabGlyph = "\u{203A}" // ›
    public static let returnGlyph = "\u{00AC}" // ¬

    /// Finds markers within `text` — one `NSTextLineFragment`'s own text.
    /// A line terminator (LF, CR, or CRLF) produces exactly one marker at
    /// its start, never one per UTF-16 unit of a CRLF pair, matching
    /// `EditorLineIndex`'s own established LF/CRLF/CR terminator handling.
    public static func markers(in text: String) -> [Marker] {
        var markers: [Marker] = []
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let unit = units[index]
            switch unit {
            case 0x20:
                markers.append(Marker(localUTF16Offset: index, glyph: spaceGlyph))
                index += 1
            case 0x09:
                markers.append(Marker(localUTF16Offset: index, glyph: tabGlyph))
                index += 1
            case 0x0A:
                markers.append(Marker(localUTF16Offset: index, glyph: returnGlyph))
                index += 1
            case 0x0D:
                markers.append(Marker(localUTF16Offset: index, glyph: returnGlyph))
                if index + 1 < units.count, units[index + 1] == 0x0A {
                    index += 2
                } else {
                    index += 1
                }
            default:
                index += 1
            }
        }
        return markers
    }
}
