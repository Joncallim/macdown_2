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

        try Task.checkCancellation()

        // Only `blockDirectives` maps to a swift-markdown `ParseOption` in 0.8.0;
        // the remaining GFM features are always enabled together.
        var parseOptions: ParseOptions = []
        if options.blockDirectives {
            parseOptions.insert(.parseBlockDirectives)
        }
        let document = Document(parsing: bodyText, options: parseOptions)

        try Task.checkCancellation()

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

    private func parseYAML(_ raw: String) -> [String: FrontMatterValue]? {
        guard let root = try? Yams.load(yaml: raw) else {
            return nil
        }
        guard let mapping = root as? [String: Any] else {
            return nil
        }
        return mapping.compactMapValues { convertYAMLValue($0) }
    }

    private func convertYAMLValue(_ value: Any) -> FrontMatterValue? {
        switch value {
        case let string as String:
            return .string(string)
        // Yams 6.2.2 returns native Swift scalars on this platform, so the
        // Bool/Int/Double cases below are the normal path. NSNumber is kept
        // defensively for configurations or future Yams versions that bridge
        // numeric/boolean scalars to Foundation.
        case let bool as Bool:
            return .bool(bool)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .number(double)
        case let number as NSNumber:
            return convertNSNumber(number)
        case let array as [Any]:
            return .array(array.compactMap { convertYAMLValue($0) })
        case let dictionary as [String: Any]:
            return .dictionary(dictionary.compactMapValues { convertYAMLValue($0) })
        case is NSNull:
            return .null
        default:
            return nil
        }
    }

    private func convertNSNumber(_ number: NSNumber) -> FrontMatterValue {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .bool(number.boolValue)
        }
        if CFNumberIsFloatType(number) {
            return .number(number.doubleValue)
        }
        return .int(number.intValue)
    }
}

// MARK: - Block conversion

private struct ConversionResult {
    let blocks: [MarkdownBlock]
    let headings: [HeadingItem]
}

private struct BlockConverter {
    let bodyLineOffset: Int

    func convert(_ document: Document, parentRange: ClosedRange<Int>) -> ConversionResult {
        var blocks: [MarkdownBlock] = []
        var headings: [HeadingItem] = []
        for child in document.children {
            guard let block = child as? BlockMarkup else { continue }
            let result = convert(block, parentRange: parentRange)
            blocks.append(result.block)
            headings.append(contentsOf: result.headings)
        }
        return ConversionResult(blocks: blocks, headings: headings)
    }

    func convert(
        _ node: BlockMarkup,
        parentRange: ClosedRange<Int>
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

        for child in node.children {
            guard let block = child as? BlockMarkup else { continue }
            let result = convert(block, parentRange: range)
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
