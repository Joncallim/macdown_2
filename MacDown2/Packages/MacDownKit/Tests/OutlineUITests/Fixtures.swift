import MarkdownEngine

/// Deterministic fixtures and helpers for OutlineUI tests. Mirrors
/// `MarkdownEngineTests/Fixtures.swift`'s style — inline builders, no fixture
/// files on disk.
enum Fixtures {
    /// A `HeadingItem` with a one-line range starting at `line`.
    static func heading(level: Int, title: String, line: Int) -> HeadingItem {
        HeadingItem(level: level, title: title, lineRange: line ... line)
    }

    /// H1 → H2 → H3, strictly increasing depth.
    static let simpleNesting: [HeadingItem] = [
        heading(level: 1, title: "One", line: 1),
        heading(level: 2, title: "Two", line: 2),
        heading(level: 3, title: "Three", line: 3),
    ]

    /// H1 → H3, skipping H2 (D3).
    static let skippedLevel: [HeadingItem] = [
        heading(level: 1, title: "One", line: 1),
        heading(level: 3, title: "Three", line: 2),
    ]

    /// Opens at H3, later has H1 — two roots in document order.
    static let opensDeepThenShallow: [HeadingItem] = [
        heading(level: 3, title: "Deep", line: 1),
        heading(level: 1, title: "Shallow", line: 2),
    ]

    /// A `MarkdownDocument` wrapping `headings` with a `SourceMap` built from
    /// `text`. `text` should have one line per heading's `lineRange` for the
    /// map to be meaningful; callers that only need `headings` and `revision`
    /// can pass a placeholder.
    static func document(
        headings: [HeadingItem],
        text: String,
        revision: Int = 1
    ) -> MarkdownDocument {
        MarkdownDocument(
            body: text,
            bodyLineOffset: 0,
            blocks: [],
            headings: headings,
            frontMatter: nil,
            sourceMap: SourceMap(text: text),
            revision: revision,
            options: .default
        )
    }
}
