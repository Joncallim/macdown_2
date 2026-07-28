import Foundation
import MarkdownEngine

enum PreviewFixtures {
    static func document(_ text: String) -> MarkdownDocument {
        MarkdownDocument(
            body: text,
            bodyLineOffset: 0,
            blocks: [],
            headings: [],
            frontMatter: nil,
            sourceMap: SourceMap(text: text),
            revision: 1,
            options: .default
        )
    }

    static func documentWithBlocks(text: String, blocks: [MarkdownBlock]) -> MarkdownDocument {
        MarkdownDocument(
            body: text,
            bodyLineOffset: 0,
            blocks: blocks,
            headings: [],
            frontMatter: nil,
            sourceMap: SourceMap(text: text),
            revision: 1,
            options: .default
        )
    }
}
