import Foundation

/// A per-document choice of syntax mode that differs from what the file's
/// extension implies (EPIC-22 §17, Slice 9d). It changes only how the source
/// is *edited* — highlighting grammar and `LanguageEditingProfile` — never the
/// document's `FileFormat`, so preview routing, Save As naming and every file
/// write are unaffected.
///
/// The override records the format it was made against. It applies only while
/// the document still has that base format, so a Save As or rename to a
/// different format silently retires it with no lifecycle hook to forget.
public struct SyntaxModeOverride: Codable, Sendable, Equatable {
    public let modeFormatID: String
    public let baseFormatID: String

    public init(modeFormatID: String, baseFormatID: String) {
        self.modeFormatID = modeFormatID
        self.baseFormatID = baseFormatID
    }
}

public extension FileFormatRegistry {
    /// The format whose highlighting and editing profile drive the editor for
    /// a document of `format` under `override`. Falls back to `format` when
    /// there is no override, it was made against a different base format, or
    /// its mode is not a registered format (e.g. a restored session written
    /// by a build that knew more formats).
    func syntaxFormat(for format: FileFormat, override: SyntaxModeOverride?) -> FileFormat {
        guard let override,
              override.baseFormatID == format.id,
              let mode = formats.first(where: { $0.id == override.modeFormatID })
        else { return format }
        return mode
    }

    /// Whether `override` is currently in force for a document of `format`.
    func isActive(_ override: SyntaxModeOverride?, for format: FileFormat) -> Bool {
        syntaxFormat(for: format, override: override).id != format.id
    }
}
