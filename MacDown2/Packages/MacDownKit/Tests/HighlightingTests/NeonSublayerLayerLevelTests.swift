import Foundation
@testable import Highlighting
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Testing

/// DEP-TRIAL ONLY (stage C2, `planning/downstream/evidence/h5-neon-resolve/`).
///
/// Classifies the editor-level residuals of ``NeonSublayerResolveTests`` without
/// Neon: the same single edit is applied to a `LanguageLayer` directly and the
/// highlight captures (per UTF-16 unit, all layers) are compared with a fresh
/// layer's. Variables:
/// - points: `bytes` (what tree-sitter expects), `utf16` (the app's
///   `locationTransformer`: UTF-16 columns), `neon` (`utf16`, and the old end
///   point computed from the post-edit text, as `TextViewHighlighter` does);
/// - resolve: `changed` (resolve sublayers over the set `didChangeContent`
///   returned, as the stage C2 Neon fix does) or `whole` (whole document).
/// A `root` line compares a layer with no sublayers (block grammar only).
///
/// Opt-in: `MACDOWN_NEON_RESOLVE_TRIAL=1`. Reports; asserts only with
/// `MACDOWN_NEON_LAYER_STRICT=1` (bytes points, changed resolve).
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MACDOWN_NEON_RESOLVE_TRIAL"] == "1"))
struct NeonSublayerLayerLevelTests {
    typealias Edit = NeonBufferedInvalidationTests.Edit
    typealias R = NeonSublayerResolveTests

    static func cases() -> [(String, Edit)] {
        [
            ("insertSplitParagraph", .insert("\n\n# New *heading*\n\n", at: R.at("text and a"))),
            ("deleteParagraph", .delete(R.range(of: "Some *emphasis*, **strong** text and a [link](https://example.com) here.\n\n"))),
            ("openFence", .insert("```\n", at: R.at("Some *emphasis*"))),
            ("removeOpeningFence", .delete(R.range(of: "```\nfenced"))),
            ("wholeBlockDeletion", .delete(NSRange(location: 2 * R.blockLength, length: 3 * R.blockLength))),
            ("typingInLastFence", .insert(" **strong** tail", at: (R.blockCount - 1) * R.blockLength + R.block.range(of: "fenced code line").location + 9)),
            ("largePaste", .insert(R.pasteText, at: R.at("text and a"))),
            ("largePasteFence", .insert("```\n" + String(repeating: "code *not em*\n", count: 160) + "```\n", at: R.at("Some *emphasis*"))),
            ("replaceSelectionSameTextPlusY", {
                let range = NSRange(location: (R.text as NSString).length / 2, length: 600)
                return .replace(range, (R.text as NSString).substring(with: range) + "y")
            }()),
            ("deleteEmphasis", .delete(R.range(of: "*emphasis*"))),
        ]
    }

    enum Points: String, CaseIterable {
        case bytes, utf16, neon
    }

    static func point(_ offset: Int, in text: NSString, bytes: Bool) -> Point {
        let prefix = text.substring(to: offset) as NSString
        let lastNewline = prefix.range(of: "\n", options: .backwards)
        var row = 0
        prefix.enumerateSubstrings(in: NSRange(location: 0, length: prefix.length), options: [.byComposedCharacterSequences]) { s, _, _, _ in
            if s == "\n" { row += 1 }
        }
        let column = lastNewline.location == NSNotFound ? offset : offset - NSMaxRange(lastNewline)
        return Point(row: row, column: column * (bytes ? 2 : 1))
    }

    static func layer(_ text: String, sublayers: Bool) throws -> LanguageLayer {
        let registry = GrammarRegistry()
        let config = try #require(registry.configuration(for: "markdown"))
        let layer = try LanguageLayer(
            languageConfig: config,
            configuration: .init(maximumLanguageDepth: sublayers ? 4 : 0, languageProvider: sublayers ? registry.languageProvider : { _ in nil })
        )
        let content = LanguageLayer.Content(string: text)
        let length = (text as NSString).length
        _ = layer.didChangeContent(content, using: InputEdit(
            startByte: 0, oldEndByte: 0, newEndByte: length * 2,
            startPoint: .zero, oldEndPoint: .zero, newEndPoint: point(length, in: text as NSString, bytes: true)
        ), resolveSublayers: false)
        return layer
    }

    static func captures(_ layer: LanguageLayer, _ text: String) throws -> [String] {
        let length = (text as NSString).length
        let ranges = try layer.executeQuery(.highlights, in: IndexSet(integersIn: 0 ..< length)).resolve(with: .init(textProvider: text.predicateTextProvider)).highlights()
        var names = [[String]](repeating: [], count: length)
        for named in ranges {
            let r = NSIntersectionRange(named.range, NSRange(location: 0, length: length))
            guard r.length > 0 else { continue }
            for index in r.location ..< NSMaxRange(r) { names[index].append(named.name) }
        }
        return names.map { Set($0).sorted().joined(separator: "+") }
    }

    static func diff(_ a: [String], _ b: [String]) -> String {
        guard a.count == b.count else { return "length \(a.count) vs \(b.count)" }
        let differing = a.indices.filter { a[$0] != b[$0] }
        guard let first = differing.first else { return "0" }
        return "\(differing.count) (first=\(first) edited='\(a[first])' fresh='\(b[first])')"
    }

    @Test(arguments: 0 ..< 10)
    func layerLevel(index: Int) throws {
        let (name, edit) = Self.cases()[index]
        let old = R.text as NSString
        let newText = old.replacingCharacters(in: edit.range, with: edit.text)
        let new = newText as NSString
        let newEnd = edit.range.location + (edit.text as NSString).length
        let content = LanguageLayer.Content(string: newText)
        var strictFailure: String?
        for points in Points.allCases {
            let bytes = points == .bytes
            let oldEndPoint = points == .neon
                ? Self.point(newEnd, in: new, bytes: false)
                : Self.point(NSMaxRange(edit.range), in: old, bytes: bytes)
            let inputEdit = InputEdit(
                startByte: edit.range.location * 2, oldEndByte: NSMaxRange(edit.range) * 2, newEndByte: newEnd * 2,
                startPoint: Self.point(edit.range.location, in: old, bytes: bytes), oldEndPoint: oldEndPoint,
                newEndPoint: Self.point(newEnd, in: new, bytes: bytes)
            )
            // block grammar only
            let root = try Self.layer(R.text, sublayers: false)
            _ = root.didChangeContent(content, using: inputEdit, resolveSublayers: false)
            let freshRoot = try Self.layer(newText, sublayers: false)
            let rootDiff = try Self.diff(Self.captures(root, newText), Self.captures(freshRoot, newText))

            var line = "H5-LAYER case=\(name) points=\(points) root=\(rootDiff)"
            let fresh = try Self.layer(newText, sublayers: true)
            _ = try fresh.resolveSublayers(with: content, in: IndexSet(integersIn: 0 ..< new.length))
            let expected = try Self.captures(fresh, newText)
            for resolve in ["changed", "changed+point", "pieces", "whole"] {
                let layer = try Self.layer(R.text, sublayers: true)
                _ = try layer.resolveSublayers(with: LanguageLayer.Content(string: R.text), in: IndexSet(integersIn: 0 ..< old.length))
                let invalidated = layer.didChangeContent(content, using: inputEdit, resolveSublayers: false)
                var set = resolve == "whole" ? IndexSet(integersIn: 0 ..< new.length) : invalidated
                if resolve != "changed", resolve != "whole" {
                    set.insert(integersIn: max(0, edit.range.location - 1) ..< min(new.length, newEnd + 1))
                }
                if points == .bytes, resolve != "whole" {
                    print("H5-LAYER-SET case=\(name) \(resolve) \(set.rangeView.map { "\($0.lowerBound)..<\($0.upperBound)" }.prefix(8))")
                }
                if resolve == "pieces" {
                    // as Neon's sublayer validator does: one contiguous range at a time
                    for range in set.rangeView {
                        _ = try layer.resolveSublayers(with: content, in: IndexSet(integersIn: range))
                    }
                } else {
                    _ = try layer.resolveSublayers(with: content, in: set)
                }
                let result = try Self.diff(Self.captures(layer, newText), expected)
                line += " \(resolve)=\(result)"
                if points == .bytes, resolve == "changed", result != "0" {
                    strictFailure = result
                }
            }
            print(line)
        }
        if ProcessInfo.processInfo.environment["MACDOWN_NEON_LAYER_STRICT"] == "1" {
            #expect(strictFailure == nil, "\(name): \(strictFailure ?? "")")
        }
    }
}
