import Foundation
@testable import Highlighting
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Testing

/// Opt-in experiment for register row H5: reconciles the earlier "inline
/// sublayer resolution ≈ 3–9 ms" observation with PR #472's 6.2 s keystroke
/// at 1 MB by timing, at the `LanguageLayer` level, what each one could have
/// measured:
///
/// - `resolve(viewport)` / `resolve(edit)`: resolving the inline injection over
///   a 4 KB viewport, or over just the edited range after an edit.
/// - `edit(root only)`: a one-character edit with no inline sublayer resolved.
/// - `edit(viewport resolved)` / `edit(all resolved)`: the same edit after the
///   inline sublayer was resolved over a viewport, or the whole document (what
///   Neon does as the app is wired: `TextViewHighlighter.init` validates `.all`).
///
///     MACDOWN_INLINE_RECONCILE=1 swift test -c release -Xswiftc -enable-testing \
///         --no-parallel --filter InlineResolutionReconciliationTests
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MACDOWN_INLINE_RECONCILE"] == "1"))
struct InlineResolutionReconciliationTests {
    static func workloads() -> [(String, (Int) -> String)] {
        [
            ("heading-line", {
                Fixtures.markdownRepeating(line: "# Heading\n\nSome `code` and **bold** text.\n\n", totalBytes: $0)
            }),
            ("stall-block", { StallFixtures.markdown(utf8Bytes: $0) }),
        ]
    }

    @Test(arguments: [64 * 1024, 256 * 1024, 1024 * 1024])
    func reconcile(utf8Bytes: Int) throws {
        for (name, make) in Self.workloads() {
            let text = make(utf8Bytes)
            let length = (text as NSString).length
            var line = "H5-RECONCILE workload=\(name) KB=\(utf8Bytes / 1024) utf16=\(length)"

            let root = try Self.parsedLayer(text)
            try line += " | edit(root only) \(Self.ms(Self.medianEdit(root, text)))"

            let viewport = try Self.parsedLayer(text)
            let resolveViewport = try Self.time { _ = try viewport.layer.resolveSublayers(
                with: viewport.content, in: NSRange(location: 0, length: min(4096, length))
            ) }
            line += " | resolve(viewport 4 KB) \(Self.ms(resolveViewport))"
            try line += " | edit(viewport resolved) \(Self.ms(Self.medianEdit(viewport, text)))"

            let all = try Self.parsedLayer(text)
            let resolveAll = try Self.time { _ = try all.layer.resolveSublayers(
                with: all.content, in: NSRange(location: 0, length: length)
            ) }
            line += " | resolve(all) \(Self.ms(resolveAll))"
            let (editAll, resolveEdit) = try Self.medianEditAndResolve(all, text)
            line += " | edit(all resolved) \(Self.ms(editAll)) | resolve(edited range) \(Self.ms(resolveEdit))"
            print(line)
        }
    }

    private struct Parsed {
        let layer: LanguageLayer
        let content: LanguageLayer.Content
    }

    private static func parsedLayer(_ text: String) throws -> Parsed {
        let registry = GrammarRegistry()
        let config = try #require(registry.configuration(for: "markdown"))
        let layer = try LanguageLayer(
            languageConfig: config,
            configuration: .init(maximumLanguageDepth: 4, languageProvider: registry.languageProvider)
        )
        let content = LanguageLayer.Content(string: text)
        let length = (text as NSString).length
        _ = layer.didChangeContent(content, using: InputEdit(
            startByte: 0, oldEndByte: 0, newEndByte: length * 2,
            startPoint: .zero, oldEndPoint: .zero, newEndPoint: point(length, in: text)
        ), resolveSublayers: false)
        return Parsed(layer: layer, content: content)
    }

    /// Median of 5 one-character edits (insert / delete alternately) in the
    /// middle, with sublayer resolution deferred as Neon does.
    private static func medianEdit(_ parsed: Parsed, _ text: String) throws -> Duration {
        try medianEditAndResolve(parsed, text, resolveEditedRange: false).edit
    }

    private static func medianEditAndResolve(
        _ parsed: Parsed,
        _ text: String,
        resolveEditedRange: Bool = true
    ) throws -> (edit: Duration, resolve: Duration) {
        var current = text
        var edits: [Duration] = []
        var resolves: [Duration] = []
        let location = (text as NSString).length / 2
        for index in 0 ..< 5 {
            let insert = index.isMultiple(of: 2)
            let old = current as NSString
            let new = insert
                ? old.replacingCharacters(in: NSRange(location: location, length: 0), with: "x")
                : old.replacingCharacters(in: NSRange(location: location, length: 1), with: "")
            let oldEnd = location + (insert ? 0 : 1)
            let newEnd = location + (insert ? 1 : 0)
            let edit = InputEdit(
                startByte: location * 2, oldEndByte: oldEnd * 2, newEndByte: newEnd * 2,
                startPoint: point(location, in: current), oldEndPoint: point(oldEnd, in: current),
                newEndPoint: point(newEnd, in: new)
            )
            let content = LanguageLayer.Content(string: new)
            edits.append(time { _ = parsed.layer.didChangeContent(content, using: edit, resolveSublayers: false) })
            if resolveEditedRange {
                try resolves.append(time { _ = try parsed.layer.resolveSublayers(
                    with: content, in: NSRange(location: max(0, location - 64), length: 128)
                ) })
            }
            current = new
        }
        return (edits.sorted()[2], resolves.isEmpty ? .zero : resolves.sorted()[2])
    }

    private static func point(_ offset: Int, in text: String) -> Point {
        let string = text as NSString
        let prefix = string.substring(to: offset) as NSString
        let lastNewline = prefix.range(of: "\n", options: .backwards)
        let row = prefix.components(separatedBy: "\n").count - 1
        let column = lastNewline.location == NSNotFound ? offset : offset - NSMaxRange(lastNewline)
        return Point(row: row, column: column * 2)
    }

    private static func time(_ body: () throws -> Void) rethrows -> Duration {
        let clock = ContinuousClock()
        let start = clock.now
        try body()
        return clock.now - start
    }

    private static func ms(_ duration: Duration) -> String {
        let components = duration.components
        let value = Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
        return String(format: "%.1f ms", value)
    }
}
