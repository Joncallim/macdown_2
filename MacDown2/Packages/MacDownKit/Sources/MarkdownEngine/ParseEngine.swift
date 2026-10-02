import Dispatch
import Foundation
import Markdown
import Yams

/// The parse owner. An actor so work is serialised and OFF the main thread.
/// The ONLY file that imports Markdown and Yams (D1, D3).
public actor ParseEngine: ParseExecuting {
    public init() {}

    /// Pure: text in → document out.
    public func parse(
        _ text: String,
        options: MarkdownParseOptions = .default,
        revision: Int
    ) async throws -> MarkdownDocument {
        dispatchPrecondition(condition: .notOnQueue(.main))

        try Task.checkCancellation()

        // swift-markdown, the block converter and Yams all recurse once per
        // nesting level. On a cooperative-pool thread (≈512 KB of stack) a few
        // KB of hostile or accidental input — `>` repeated ~700 times, deeply
        // nested emphasis or lists, a YAML flow sequence ~350 deep — overflows
        // it and kills the app, and a crash during open or session restore
        // repeats on every relaunch. The synchronous work therefore runs on a
        // dedicated thread with a large (lazily committed) stack.
        let document = await Self.runOnLargeStack { [self] in
            parseSynchronously(text, options: options, revision: revision)
        }

        try Task.checkCancellation()
        return document
    }

    /// Stack for the parse thread. Only touched pages are committed.
    static let parseThreadStackSize = 1 << 30

    private static func runOnLargeStack<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let thread = Thread { continuation.resume(returning: work()) }
            thread.stackSize = parseThreadStackSize
            thread.qualityOfService = .userInitiated
            thread.name = "MarkdownEngine.parse"
            thread.start()
        }
    }

    private nonisolated func parseSynchronously(
        _ text: String,
        options: MarkdownParseOptions,
        revision: Int
    ) -> MarkdownDocument {
        let sourceMap = SourceMap(text: text)

        let extraction = FrontMatterExtractor.extract(from: text)
        let bodyText = extraction?.body ?? text
        let bodyLineOffset = extraction?.closingLineNumber ?? 0
        let frontMatter = extraction.map { ext in
            FrontMatter(
                raw: ext.raw,
                lineRange: 1 ... ext.closingLineNumber,
                values: parseYAML(ext.raw)
            )
        }

        // Only `blockDirectives` maps to a swift-markdown `ParseOption` in 0.8.0;
        // the remaining GFM features are always enabled together.
        var parseOptions: ParseOptions = []
        if options.blockDirectives {
            parseOptions.insert(.parseBlockDirectives)
        }
        let document = Document(parsing: bodyText, options: parseOptions)

        let fallbackRange = 1 ... max(1, sourceMap.lineCount)
        let converter = BlockConverter(bodyLineOffset: bodyLineOffset)
        let result = converter.convert(document, parentRange: fallbackRange)

        return MarkdownDocument(
            body: bodyText,
            bodyLineOffset: bodyLineOffset,
            blocks: result.blocks,
            headings: result.headings,
            frontMatter: frontMatter,
            sourceMap: sourceMap,
            revision: revision,
            options: options
        )
    }

    // MARK: - YAML front matter

    /// Yams expands every alias into a full copy, so a few hundred bytes of
    /// nested anchors ("billion laughs") expand to gigabytes and hang the shared
    /// parse actor. Total alias references bound the expansion (each level
    /// multiplies by at most its own fan-out, which is bounded by the total), so
    /// front matter with more than this many is left unparsed — its raw text and
    /// range are still reported — rather than expanded.
    static let maximumYAMLAliasReferences = 16

    static func exceedsYAMLAliasBudget(_ raw: String) -> Bool {
        guard raw.contains("&") else { return false }
        var aliases = 0
        var previous: Character = "\n"
        var index = raw.startIndex
        while index < raw.endIndex {
            let character = raw[index]
            if character == "*", !(previous.isLetter || previous.isNumber || previous == "\\") {
                let next = raw.index(after: index)
                if next < raw.endIndex, raw[next].isLetter || raw[next].isNumber || raw[next] == "_" {
                    aliases += 1
                    if aliases > maximumYAMLAliasReferences {
                        return true
                    }
                }
            }
            previous = character
            index = raw.index(after: index)
        }
        return false
    }

    private nonisolated func parseYAML(_ raw: String) -> [String: FrontMatterValue]? {
        guard !Self.exceedsYAMLAliasBudget(raw) else { return nil }
        guard let root = try? Yams.load(yaml: raw) else {
            return nil
        }
        guard let mapping = root as? [String: Any] else {
            return nil
        }
        return mapping.compactMapValues { convertYAMLValue($0) }
    }

    private nonisolated func convertYAMLValue(_ value: Any) -> FrontMatterValue? {
        switch value {
        case let string as String:
            .string(string)
        // Yams 6.2.2 returns native Swift scalars on this platform, so the
        // Bool/Int/Double cases below are the normal path. NSNumber is kept
        // defensively for configurations or future Yams versions that bridge
        // numeric/boolean scalars to Foundation.
        case let bool as Bool:
            .bool(bool)
        case let int as Int:
            .int(int)
        case let double as Double:
            .number(double)
        case let number as NSNumber:
            convertNSNumber(number)
        case let array as [Any]:
            .array(array.compactMap { convertYAMLValue($0) })
        case let dictionary as [String: Any]:
            .dictionary(dictionary.compactMapValues { convertYAMLValue($0) })
        case is NSNull:
            .null
        default:
            nil
        }
    }

    /// Defensive NSNumber→FrontMatterValue bridge. Internal (not private) so
    /// the unsigned-int range guard is testable via `@testable import`.
    nonisolated func convertNSNumber(_ number: NSNumber) -> FrontMatterValue {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .bool(number.boolValue)
        }
        if CFNumberIsFloatType(number) {
            return .number(number.doubleValue)
        }
        // Yams returns native Swift scalars on this platform, so NSNumber is
        // only a defensive bridge. Use the original scalar encoding so unsigned
        // integers are checked against UInt64 bounds and signed integers against
        // Int64 bounds; fall back to Double when the value does not fit in Int.
        let encoding = String(cString: number.objCType)
        switch encoding {
        case "C", "S", "I", "L", "Q":
            let unsigned = number.uint64Value
            if unsigned <= UInt64(Int.max) {
                return .int(Int(unsigned))
            }
        default:
            let signed = number.int64Value
            if signed >= Int64(Int.min), signed <= Int64(Int.max) {
                return .int(Int(signed))
            }
        }
        return .number(number.doubleValue)
    }
}

// MARK: - Block conversion

private struct ConversionResult {
    let blocks: [MarkdownBlock]
    let headings: [HeadingItem]
}

private struct BlockConverter {
    /// Nesting deeper than this is never authored by hand. The converted tree is
    /// a nested value type that every consumer walks — and whose release —
    /// recurses once per level, on whatever (small) thread drops the last
    /// reference, so the depth is bounded here rather than trusted.
    static let maxDepth = 128

    let bodyLineOffset: Int

    func convert(_ document: Document, parentRange: ClosedRange<Int>) -> ConversionResult {
        var blocks: [MarkdownBlock] = []
        var headings: [HeadingItem] = []
        for child in document.children {
            guard let block = child as? BlockMarkup else { continue }
            let result = convert(block, parentRange: parentRange, depth: 0)
            blocks.append(result.block)
            headings.append(contentsOf: result.headings)
        }
        return ConversionResult(blocks: blocks, headings: headings)
    }

    func convert(
        _ node: BlockMarkup,
        parentRange: ClosedRange<Int>,
        depth: Int
    ) -> (block: MarkdownBlock, headings: [HeadingItem]) {
        let range = originalLineRange(for: node) ?? parentRange
        var childBlocks: [MarkdownBlock] = []
        var headings: [HeadingItem] = []

        if let heading = node as? Heading {
            headings.append(HeadingItem(
                level: heading.level,
                title: heading.plainText,
                lineRange: range
            ))
        }

        for child in node.children where depth < Self.maxDepth {
            guard let block = child as? BlockMarkup else { continue }
            let result = convert(block, parentRange: range, depth: depth + 1)
            childBlocks.append(result.block)
            headings.append(contentsOf: result.headings)
        }

        return (
            block: MarkdownBlock(kind: kind(for: node), lineRange: range, children: childBlocks),
            headings: headings
        )
    }

    private func kind(for node: BlockMarkup) -> BlockKind {
        if let listKind = listKind(for: node) {
            return listKind
        }

        switch node {
        case is Heading:
            return .heading(level: (node as? Heading)?.level ?? 1)
        case is Paragraph:
            return .paragraph
        case let codeBlock as CodeBlock:
            let language = codeBlock.language.flatMap { languageToken(from: $0) }
            return .codeBlock(language: language)
        case is BlockQuote:
            return .blockQuote
        case let table as Table:
            return .table(columnCount: table.maxColumnCount)
        case is ThematicBreak:
            return .thematicBreak
        case is HTMLBlock:
            return .htmlBlock
        default:
            return .custom(String(describing: type(of: node)))
        }
    }

    private func listKind(for node: BlockMarkup) -> BlockKind? {
        switch node {
        case let orderedList as OrderedList:
            return .orderedList(startIndex: Int(orderedList.startIndex))
        case is UnorderedList:
            return .unorderedList
        case let listItem as ListItem:
            let taskState: BlockKind.TaskState? = listItem.checkbox.map {
                $0 == .checked ? .checked : .unchecked
            }
            return .listItem(taskState: taskState)
        default:
            return nil
        }
    }

    private func languageToken(from infoString: String) -> String? {
        let token = infoString.split(separator: " ", omittingEmptySubsequences: true).first
        return token.map { String($0).lowercased() }
    }

    private func originalLineRange(for node: Markup) -> ClosedRange<Int>? {
        guard let range = node.range else { return nil }
        let startLine = max(1, range.lowerBound.line + bodyLineOffset)
        // swift-markdown SourceRange upperBound is exclusive. When it sits at
        // column 1 it points to the line after the content; otherwise it sits
        // on the content's last line (e.g. a single-line node with no trailing
        // newline reports upperBound.line == lowerBound.line).
        let rawEndLine = range.upperBound.line
        let endLine = max(startLine, (range.upperBound.column == 1 ? rawEndLine - 1 : rawEndLine) + bodyLineOffset)
        return startLine ... endLine
    }
}
