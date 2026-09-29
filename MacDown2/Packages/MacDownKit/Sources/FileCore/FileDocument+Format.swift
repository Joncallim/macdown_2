import Foundation

extension FileDocument {
    static func format(for url: URL) -> FileFormat {
        FileFormat.format(for: url, in: FileFormatRegistry())
            ?? FileFormatRegistry.defaultFormats.first { $0.id == "plaintext" }
            ?? FileFormat(id: "plaintext", name: "Plain Text", utType: .plainText, extensions: ["txt"])
    }
}
