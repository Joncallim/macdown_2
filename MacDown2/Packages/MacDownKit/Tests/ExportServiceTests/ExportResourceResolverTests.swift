@testable import ExportService
import Foundation
import Testing

/// Resource resolution: root containment, reference decoding, deduplication and
/// the export budgets.
struct ExportResourceResolverTests {
    private func resolver(
        root: URL?,
        fatal: Bool = false,
        budget: ExportResourceBudget = .standard
    ) -> ExportResourceResolver {
        ExportResourceResolver(documentDirectory: root, unresolvedIsFatal: fatal, budget: budget)
    }

    @Test func resolvesAnImageInsideTheDocumentFolder() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try ExportTestSupport.writeFixture(named: "images/a.png", in: directory, bytes: Data([0x89, 0x50]))

        let subject = resolver(root: directory)
        #expect(subject.disposition(for: "images/a.png", isImage: true) != .keep)
        #expect(subject.diagnostics.isEmpty)
    }

    @Test func refusesToReadOutsideTheDocumentFolder() throws {
        let base = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        // A real, readable file that the document has no business embedding.
        try ExportTestSupport.writeFixture(named: "secret.png", in: base, bytes: Data([0x89, 0x50]))
        let documentDirectory = base.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: documentDirectory, withIntermediateDirectories: true)

        let subject = resolver(root: documentDirectory)
        #expect(subject.disposition(for: "../secret.png", isImage: true) == .keep)
        #expect(subject.diagnostics.contains { $0.message.contains("outside the document's folder") })
    }

    @Test func decodesPercentEncodedFilenames() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try ExportTestSupport.writeFixture(named: "my image.png", in: directory, bytes: Data([0x89, 0x50]))

        // Editors write spaces as %20; the file on disk still has a space.
        let subject = resolver(root: directory)
        #expect(subject.disposition(for: "my%20image.png", isImage: true) != .keep)
        #expect(subject.diagnostics.isEmpty)
    }

    @Test func repeatedReferencesShareOneResourceAndOneDiagnostic() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try ExportTestSupport.writeFixture(named: "a.png", in: directory, bytes: Data([0x89, 0x50]))

        let subject = resolver(root: directory)
        let first = subject.disposition(for: "a.png", isImage: true)
        let second = subject.disposition(for: "a.png", isImage: true)
        #expect(first == second)
        #expect(subject.frozenManifest().resources.count == 1)

        _ = subject.disposition(for: "missing.png", isImage: true)
        _ = subject.disposition(for: "missing.png", isImage: true)
        #expect(subject.diagnostics.count == 1)
    }

    @Test func rejectsAResourceLargerThanTheSingleFileBudget() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try ExportTestSupport.writeFixture(named: "big.png", in: directory, bytes: Data(repeating: 0x41, count: 64))

        let tiny = ExportResourceBudget(
            maxSourceUTF8Bytes: 1024,
            maxResourceCount: 8,
            maxSingleResourceBytes: 16,
            maxAggregateResourceBytes: 1024,
            maxDerivedFragmentCount: 8,
            maxAggregateDerivedHTMLBytes: 1024,
            maxPreparedHTMLUTF8Bytes: 1024
        )
        let subject = resolver(root: directory, budget: tiny)
        #expect(subject.disposition(for: "big.png", isImage: true) == .keep)
        #expect(subject.diagnostics.contains { $0.message.contains("per-file export limit") })
        #expect(subject.frozenManifest().resources.isEmpty)
    }

    @Test func rejectsResourcesPastTheCountBudget() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for index in 0 ..< 3 {
            try ExportTestSupport.writeFixture(
                named: "img\(index).png",
                in: directory,
                bytes: Data([0x89, UInt8(index)])
            )
        }

        let capped = ExportResourceBudget(
            maxSourceUTF8Bytes: 1024,
            maxResourceCount: 2,
            maxSingleResourceBytes: 1024,
            maxAggregateResourceBytes: 1024,
            maxDerivedFragmentCount: 8,
            maxAggregateDerivedHTMLBytes: 1024,
            maxPreparedHTMLUTF8Bytes: 1024
        )
        let subject = resolver(root: directory, budget: capped)
        for index in 0 ..< 3 {
            _ = subject.disposition(for: "img\(index).png", isImage: true)
        }
        #expect(subject.frozenManifest().resources.count == 2)
        #expect(subject.diagnostics.contains { $0.message.contains("2-resource limit") })
    }

    @Test func unresolvedIsAWarningOrAnErrorByTarget() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let lenient = resolver(root: directory, fatal: false)
        _ = lenient.disposition(for: "missing.png", isImage: true)
        #expect(lenient.diagnostics.allSatisfy { $0.severity == .warning })

        let strict = resolver(root: directory, fatal: true)
        _ = strict.disposition(for: "missing.png", isImage: true)
        #expect(strict.diagnostics.allSatisfy { $0.severity == .error })
    }

    @Test func navigationLinksAndFragmentsAreNeverPackaged() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let subject = resolver(root: directory, fatal: true)
        #expect(subject.disposition(for: "https://example.com", isImage: false) == .keep)
        #expect(subject.disposition(for: "#anchor", isImage: true) == .keep)
        #expect(subject.frozenManifest().resources.isEmpty)
    }

    @Test func blankedSchemesAreReported() throws {
        // A neutralised link must not just silently lose its target.
        let subject = resolver(root: nil, fatal: true)
        #expect(subject.disposition(for: "javascript:alert(1)", isImage: false) == .blank)
        #expect(subject.disposition(for: "data:image/png;base64,AAAA", isImage: true) == .blank)
        #expect(subject.diagnostics.count == 2)
        #expect(subject.diagnostics.allSatisfy { $0.severity == .warning })
    }
}
