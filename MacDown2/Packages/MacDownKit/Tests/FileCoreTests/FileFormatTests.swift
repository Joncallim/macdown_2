@testable import FileCore
import Foundation
import Testing
import UniformTypeIdentifiers

@Test func registryIncludesMarkdown() {
    let registry = FileFormatRegistry()
    let format = registry.formats.first { $0.id == "markdown" }
    #expect(format != nil)
    #expect(format?.extensions.contains("md") == true)
    #expect(format?.previewCapability == .rendered)
    #expect(format?.utType == UTType(filenameExtension: "md"))
}

@Test func registryIncludesHTMLAndJSON() {
    let registry = FileFormatRegistry()
    #expect(registry.formats.first { $0.id == "html" }?.previewCapability == .rendered)
    #expect(registry.formats.first { $0.id == "json" }?.previewCapability == .toggleable)
}

@Test func formatForURLUsesPathExtension() {
    let registry = FileFormatRegistry()
    let mdURL = URL(fileURLWithPath: "/tmp/readme.md")
    let format = FileFormat.format(for: mdURL, in: registry)
    #expect(format?.id == "markdown")
}

@Test func formatForUnknownExtensionFallsBackToNil() {
    let registry = FileFormatRegistry()
    let unknownURL = URL(fileURLWithPath: "/tmp/archive.unknown")
    #expect(FileFormat.format(for: unknownURL, in: registry) == nil)
}

@Test func allRegisteredExtensionsAreLowercased() {
    let registry = FileFormatRegistry()
    for format in registry.formats {
        for ext in format.extensions {
            #expect(ext == ext.lowercased(), "Extension '\(ext)' for \(format.id) must be lowercased")
        }
    }
}

@Test func everyFormatHasAName() {
    let registry = FileFormatRegistry()
    for format in registry.formats {
        #expect(!format.name.isEmpty)
    }
}
