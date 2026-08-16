@testable import FileCore
import Foundation
import Highlighting
import Testing
import UniformTypeIdentifiers

/// EPIC-11 Gate 0 — registry consistency validation between
/// `FileFormatRegistry` and `FormatManifest` (the project.yml mirror).
@Suite("FormatRegistryConsistency")
struct FormatRegistryConsistencyTests {
    private func validate(_ supported: Set<String>) -> FormatRegistryConsistency.Report {
        FormatRegistryConsistency.validate(
            registry: FileFormatRegistry(),
            manifest: FormatManifest.current,
            highlightLanguageSupported: { id in
                guard let id else { return true }
                return supported.contains(id)
            }
        )
    }

    @MainActor
    @Test func defaultRegistryIsConsistentAgainstCurrentManifest() {
        // Every advertised highlight language must resolve in the shipped
        // grammar registry (Gate 5 completeness). The registry caches failed
        // builds as nil, so `supportedLanguageIDs` is exactly what ships.
        let supported = GrammarRegistry().supportedLanguageIDs
        let report = validate(supported)
        #expect(report.isConsistent, Comment(rawValue: report.issues.joined(separator: "; ")))
    }

    @Test func everyFormatExtensionIsDeclaredInTheManifest() {
        let declared = Set(FormatManifest.current.documentTypes.flatMap(\.extensions))
        for format in FileFormatRegistry().formats {
            for ext in format.extensions {
                #expect(declared.contains(ext), "\(format.id) extension '\(ext)' missing from manifest")
            }
        }
    }

    @Test func everyDeclaredExtensionBelongsToExactlyOneFormat() {
        var owners: [String: String] = [:]
        for format in FileFormatRegistry().formats {
            for ext in format.extensions {
                #expect(owners[ext] == nil, "extension '\(ext)' duplicated across formats")
                owners[ext] = format.id
            }
        }
        let declared = Set(FormatManifest.current.documentTypes.flatMap(\.extensions))
        for ext in declared {
            #expect(owners[ext] != nil, "manifest declares unknown extension '\(ext)'")
        }
    }

    @Test func formatUTTypeResolvesFromItsOwnExtensions() {
        for format in FileFormatRegistry().formats {
            guard let first = format.extensions.first else { continue }
            let expected = UTType(filenameExtension: first)
            #expect(format.utType == expected || format.utType == .plainText,
                    "\(format.id): UTType does not resolve from its extensions")
            // Every extension must map to *some* system type so the OS can
            // route the file; exact conformance varies with system type
            // hierarchies (e.g. jsx vs js), so only presence is asserted.
            for ext in format.extensions {
                #expect(UTType(filenameExtension: ext) != nil,
                        "\(format.id): no system type resolves extension '\(ext)'")
            }
        }
    }

    @Test func formatsWithCapabilitiesDeclareModesAndViceVersa() throws {
        for format in FileFormatRegistry().formats {
            switch format.previewCapability {
            case .none:
                #expect(format.defaultPreviewMode == nil)
                #expect(format.supportedPreviewModes.isEmpty)
            case .markdown, .htmlSourceAndRendered, .jsonOutline:
                #expect(format.defaultPreviewMode != nil)
                #expect(!format.supportedPreviewModes.isEmpty)
                let defaultMode = try #require(format.defaultPreviewMode)
                #expect(format.supportedPreviewModes.contains(defaultMode))
            }
        }
    }

    @Test func projectYmlMatchesManifest() throws {
        // The manifest must mirror project.yml's CFBundleDocumentTypes. SPM
        // tests run with the package directory as cwd; the repo layout is
        // MacDown2/Packages/MacDownKit so project.yml sits two levels up.
        let projectYML = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("../../project.yml")
        guard FileManager.default.fileExists(atPath: projectYML.path) else {
            // Test runs outside the repo checkout (e.g. a packaged CI cache)
            // cannot verify the file; the in-repo runs always can.
            return
        }
        let contents = try String(contentsOf: projectYML, encoding: .utf8)

        for declaration in FormatManifest.current.documentTypes {
            for ext in declaration.extensions {
                // Indentation varies between CFBundleDocumentTypes entries
                // (10 spaces) and UTExportedTypeDeclarations (12 spaces), so
                // match on the list item regardless of leading whitespace.
                #expect(contents.contains("- \(ext)\n"),
                        "project.yml is missing declared extension '\(ext)' for \(declaration.formatID)")
            }
            for contentType in declaration.itemContentTypes {
                if declaration.formatID == "toml" {
                    #expect(contents.contains("UTTypeIdentifier: \(contentType)"),
                            "project.yml missing exported type \(contentType)")
                } else {
                    #expect(contents.contains("- \(contentType)"),
                            "project.yml is missing declared content type '\(contentType)'")
                }
            }
        }
    }

    @Test func validationDetectsUnsupportedHighlightID() {
        let report = FormatRegistryConsistency.validate(
            registry: FileFormatRegistry(),
            manifest: FormatManifest.current,
            highlightLanguageSupported: { id in
                // Claim nothing resolves: every advertised id is drift.
                id == nil
            }
        )
        #expect(!report.isConsistent)
        #expect(report.issues.contains { $0.contains("highlight language") })
    }

    @Test func validationDetectsCapabilityModeDrift() {
        var formats = FileFormatRegistry.defaultFormats
        formats = formats.map { format in
            if format.id == "markdown" {
                return FileFormat(
                    id: format.id,
                    name: format.name,
                    utType: format.utType,
                    extensions: format.extensions,
                    highlightLanguageID: format.highlightLanguageID,
                    previewCapability: .markdown,
                    defaultPreviewMode: nil,
                    supportedPreviewModes: []
                )
            }
            return format
        }
        let report = FormatRegistryConsistency.validate(
            registry: FileFormatRegistry(formats: formats),
            manifest: FormatManifest.current,
            highlightLanguageSupported: { _ in true }
        )
        #expect(report.issues.contains { $0.contains("markdown: capability") })
    }
}
