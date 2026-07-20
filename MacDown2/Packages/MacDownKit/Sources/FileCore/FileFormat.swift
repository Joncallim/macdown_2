import Foundation
import UniformTypeIdentifiers

/// The preview capability a format advertises.
public enum PreviewCapability: Sendable, Equatable {
    /// A rendered preview is the primary view (e.g. Markdown, HTML).
    case rendered
    /// A preview can be toggled but is not the default (e.g. JSON outline).
    case toggleable
    /// No preview is available for this format (e.g. plain text or source-only).
    case none
}

/// Metadata describing a file format MacDown 2 understands.
public struct FileFormat: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let utType: UTType
    public let extensions: [String]
    public let highlightLanguageID: String?
    public let previewCapability: PreviewCapability

    public init(
        id: String,
        name: String,
        utType: UTType,
        extensions: [String],
        highlightLanguageID: String? = nil,
        previewCapability: PreviewCapability = .none
    ) {
        self.id = id
        self.name = name
        self.utType = utType
        self.extensions = extensions
        self.highlightLanguageID = highlightLanguageID
        self.previewCapability = previewCapability
    }

    /// Returns the first format whose extension list matches the URL's path extension.
    public static func format(for url: URL, in registry: FileFormatRegistry) -> FileFormat? {
        let pathExtension = url.pathExtension.lowercased()
        guard !pathExtension.isEmpty else { return nil }
        return registry.formats.first { format in
            format.extensions.contains(pathExtension)
        }
    }
}

/// The canonical registry of formats supported by MacDown 2.
public final class FileFormatRegistry: Sendable {
    public let formats: [FileFormat]

    public init(formats: [FileFormat] = FileFormatRegistry.defaultFormats) {
        self.formats = formats
    }

    /// Built-in format list. Mirror additions here in `project.yml` `CFBundleDocumentTypes`
    /// and in the app target's `Info.plist` so the OS knows which files MacDown 2 can open.
    public static let defaultFormats: [FileFormat] = [
        // Primary editable formats
        FileFormat(
            id: "markdown",
            name: "Markdown",
            utType: UTType(filenameExtension: "md") ?? .plainText,
            extensions: ["md", "markdown", "mdown", "mkd", "mkdn"],
            highlightLanguageID: "markdown",
            previewCapability: .rendered
        ),
        FileFormat(
            id: "html",
            name: "HTML",
            utType: UTType(filenameExtension: "html") ?? .plainText,
            extensions: ["html", "htm"],
            highlightLanguageID: "html",
            previewCapability: .rendered
        ),
        FileFormat(
            id: "json",
            name: "JSON",
            utType: UTType(filenameExtension: "json") ?? .plainText,
            extensions: ["json"],
            highlightLanguageID: "json",
            previewCapability: .toggleable
        ),
        FileFormat(
            id: "yaml",
            name: "YAML",
            utType: UTType(filenameExtension: "yaml") ?? .plainText,
            extensions: ["yaml", "yml"],
            highlightLanguageID: "yaml"
        ),
        FileFormat(
            id: "toml",
            name: "TOML",
            utType: UTType(filenameExtension: "toml") ?? .plainText,
            extensions: ["toml"],
            highlightLanguageID: "toml"
        ),

        // Highlight-only source formats
        FileFormat(
            id: "javascript",
            name: "JavaScript",
            utType: UTType(filenameExtension: "js") ?? .plainText,
            extensions: ["js", "jsx"],
            highlightLanguageID: "javascript"
        ),
        FileFormat(
            id: "typescript",
            name: "TypeScript",
            utType: UTType(filenameExtension: "ts") ?? .plainText,
            extensions: ["ts", "tsx"],
            highlightLanguageID: "typescript"
        ),
        FileFormat(
            id: "python",
            name: "Python",
            utType: UTType(filenameExtension: "py") ?? .plainText,
            extensions: ["py"],
            highlightLanguageID: "python"
        ),
        FileFormat(
            id: "ruby",
            name: "Ruby",
            utType: UTType(filenameExtension: "rb") ?? .plainText,
            extensions: ["rb"],
            highlightLanguageID: "ruby"
        ),
        FileFormat(
            id: "css",
            name: "CSS",
            utType: UTType(filenameExtension: "css") ?? .plainText,
            extensions: ["css"],
            highlightLanguageID: "css"
        ),
        FileFormat(
            id: "swift",
            name: "Swift",
            utType: UTType(filenameExtension: "swift") ?? .plainText,
            extensions: ["swift"],
            highlightLanguageID: "swift"
        ),
        FileFormat(
            id: "c",
            name: "C/C++",
            utType: UTType(filenameExtension: "c") ?? .plainText,
            extensions: ["c", "cpp", "cc", "cxx", "h", "hpp"],
            highlightLanguageID: "cpp"
        ),
        FileFormat(
            id: "bash",
            name: "Bash",
            utType: UTType(filenameExtension: "sh") ?? .plainText,
            extensions: ["sh", "bash", "zsh"],
            highlightLanguageID: "bash"
        ),
        FileFormat(
            id: "sql",
            name: "SQL",
            utType: UTType(filenameExtension: "sql") ?? .plainText,
            extensions: ["sql"],
            highlightLanguageID: "sql"
        ),
        FileFormat(
            id: "xml",
            name: "XML",
            utType: UTType(filenameExtension: "xml") ?? .plainText,
            extensions: ["xml"],
            highlightLanguageID: "xml"
        ),
        FileFormat(
            id: "plaintext",
            name: "Plain Text",
            utType: .plainText,
            extensions: ["txt"],
            highlightLanguageID: nil
        ),
    ]
}
