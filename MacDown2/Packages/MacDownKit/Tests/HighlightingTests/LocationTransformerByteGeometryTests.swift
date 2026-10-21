import AppKit
import EditorCore
@testable import Highlighting
import Neon
import SwiftTreeSitter
import Testing

@MainActor
@Suite(.serialized)
struct LocationTransformerByteGeometryTests {
    private struct Observation {
        let offset: Int
        let point: SwiftTreeSitter.Point?
    }

    private final class Recorder {
        var points: [Observation] = []
        var numberRanges: [NSRange] = []
    }

    @Test(arguments: ["[1]", "[\"漢字😀e\u{301}\",1]"])
    func mountedAdapterUsesTheParsersByteColumns(source: String) async throws {
        let oldNumber = try numberNode(in: source)
        let offset = NSMaxRange(oldNumber.range)
        let edited = (source as NSString).replacingCharacters(in: NSRange(location: offset, length: 0), with: "2")
        let newNumber = try numberNode(in: edited)
        let recorder = Recorder()
        let identity = UUID().uuidString
        let store = EditorTextSystemStore()
        let system = store.system(for: identity, initialText: source, configuration: .default)
        let window = mountedWindow(for: system)
        var highlighter: TextViewHighlighter?
        defer {
            system.textView.textStorage?.delegate = nil
            highlighter = nil
            store.evict(identity)
            window.contentView = nil
            window.close()
        }
        try #require(system.textView.window === window)
        try #require(system.textView.textLayoutManager != nil)
        try #require(!system.textView.visibleRect.isEmpty)
        let transform = NeonSyntaxHighlighter.locationTransformer(for: system.textView) { system.contentRevision }
        let configuration = try #require(GrammarRegistry().configuration(for: "json"))
        highlighter = try TextViewHighlighter(textView: system.textView, configuration: .init(
            languageConfiguration: configuration,
            attributeProvider: { token in
                if token.name == "number" {
                    recorder.numberRanges.append(token.range)
                }
                return [.foregroundColor: NSColor.systemRed]
            },
            locationTransformer: { offset in
                let point = transform(offset)
                recorder.points.append(Observation(offset: offset, point: point))
                return point
            }
        ))
        try #require(highlighter != nil)
        try #require(await waitForNumber(oldNumber.range, in: recorder))
        recorder.points.removeAll()
        recorder.numberRanges.removeAll()

        // Both endpoints are supplied by real parser nodes, not a second copy
        // of the host's unit conversion. This same-line insertion deliberately
        // avoids mixing the separate old/new-snapshot problem into the oracle.
        system.textView.insertText("2", replacementRange: NSRange(location: offset, length: 0))
        #expect(system.textView.string == edited)
        let oldCalls = recorder.points.filter { $0.offset == offset }
        let newCalls = recorder.points.filter { $0.offset == offset + 1 }
        try #require(!oldCalls.isEmpty, "the mounted adapter requested the edit's old endpoint")
        try #require(!newCalls.isEmpty, "the mounted adapter requested the edit's new endpoint")
        #expect(oldCalls.allSatisfy { $0.point == oldNumber.pointRange.upperBound })
        #expect(newCalls.allSatisfy { $0.point == newNumber.pointRange.upperBound })
        #expect(await waitForNumber(newNumber.range, in: recorder))
    }

    @Test(arguments: [
        "{\"message\":\"hello\",\"count\":3}",
        "{\n\t\"message\":\"漢字😀e\u{301}\",\n\t\"count\":3\n}",
        "{\r\n\t\"message\":\"😀漢字e\u{301}\",\"count\":3\r\n}\r\n",
    ])
    func hostCoordinatesMatchFreshParserNodes(source: String) throws {
        let tree = try parsedTree(source)
        let root = try #require(tree.rootNode)
        let textView = NSTextView()
        textView.string = source
        let transform = NeonSyntaxHighlighter.locationTransformer(for: textView)
        var mismatches: [String] = []
        for node in descendants(of: root) {
            if transform(node.range.location) != node.pointRange.lowerBound
                || transform(NSMaxRange(node.range)) != node.pointRange.upperBound {
                mismatches.append("\(node.nodeType ?? "unknown") at \(node.range): \(node.pointRange)")
            }
        }
        #expect(mismatches.isEmpty, "host coordinates disagree with parser nodes: \(mismatches)")
    }

    private func parsedTree(_ source: String) throws -> MutableTree {
        let configuration = try #require(GrammarRegistry().configuration(for: "json"))
        let parser = Parser()
        try parser.setLanguage(configuration.language)
        let tree = try #require(parser.parse(source))
        let root = try #require(tree.rootNode)
        #expect(!root.hasError)
        return tree
    }

    private func mountedWindow(for system: EditorTextSystem) -> NSWindow {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 250))
        system.textView.frame = scrollView.bounds
        scrollView.documentView = system.textView
        let window = NSWindow(contentRect: scrollView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = scrollView
        window.orderFront(nil)
        scrollView.layoutSubtreeIfNeeded()
        return window
    }

    private func numberNode(in source: String) throws -> Node {
        let tree = try parsedTree(source)
        let root = try #require(tree.rootNode)
        return try #require(descendants(of: root).first { $0.nodeType == "number" })
    }

    private func descendants(of node: Node) -> [Node] {
        [node] + (0 ..< node.childCount).compactMap { node.child(at: $0) }.flatMap { descendants(of: $0) }
    }

    private func waitForNumber(_ range: NSRange, in recorder: Recorder) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !recorder.numberRanges.contains(range), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return recorder.numberRanges.contains(range)
    }
}
