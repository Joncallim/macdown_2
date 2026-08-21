import ExportService
import Foundation
import Testing
import Themes

/// Shared test helpers for the ExportService test suite.
enum ExportTestSupport {
    static func lightTheme() -> Theme {
        BundledThemes.light
    }

    static func makeTempDirectory(_: String = #function) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Writes a small PNG-looking payload to `relativePath` under `directory`
    /// and returns the directory + the file URL.
    @discardableResult
    static func writeFixture(
        named relativePath: String,
        in directory: URL,
        bytes: Data
    ) throws -> URL {
        let fileURL = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try bytes.write(to: fileURL)
        return fileURL
    }
}
