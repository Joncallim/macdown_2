import FileCore
import Foundation

/// Content-derived status metrics (#183 F16). Computed once per content
/// change and reused by every selection-only re-render.
public struct EditorDocumentMetrics: Equatable, Sendable {
    public let characterCount: Int
    public let wordCount: Int
    public let lineEndings: LineEndingProfile

    public init(of text: String) {
        characterCount = text.count
        wordCount = Self.wordCount(in: text)
        lineEndings = LineEndingProfile(detecting: text)
    }

    /// Foundation's own word-boundary logic. `nonisolated` is required:
    /// `enumerateSubstrings` may invoke its block off the actor executor.
    public nonisolated static func wordCount(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }
}

/// Memoizes `EditorDocumentMetrics` against the text system's content
/// revision (and length, as a belt-and-braces check).
@MainActor
final class EditorDocumentMetricsCache {
    private var revision: UInt64?
    private var length = 0
    private var cached: EditorDocumentMetrics?
    /// How many whole-document scans have run (test-observable).
    private(set) var computationCount = 0

    func metrics(revision: UInt64, length: Int, text: () -> String) -> EditorDocumentMetrics {
        if let cached, self.revision == revision, self.length == length {
            return cached
        }
        let computed = EditorDocumentMetrics(of: text())
        computationCount += 1
        self.revision = revision
        self.length = length
        cached = computed
        return computed
    }
}

public extension EditorTextSystem {
    /// The document's metrics; the whole-document scan runs only when the
    /// content changed since the last call, never for a selection-only change.
    func documentMetrics() -> EditorDocumentMetrics {
        metricsCache.metrics(revision: editRevision, length: liveUTF16Length) { text }
    }

    /// The live text as an `NSString` without a whole-document `String` copy.
    var liveTextSource: NSString {
        assistTextSource ?? (text as NSString)
    }

    private var liveUTF16Length: Int {
        assistTextSource?.length ?? (text as NSString).length
    }
}
