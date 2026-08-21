import cmark_gfm
import cmark_gfm_extensions
import Foundation

/// How the bridge should treat an authored link/image URL during rendering.
enum URLDisposition: Equatable {
    /// Leave the URL exactly as authored.
    case keep
    /// Replace the URL with a new value (e.g. a content-addressed resource).
    case rewrite(String)
    /// Empty the URL — used to neutralise a dangerous authored scheme.
    case blank
}

/// Isolates every byte of cmark-gfm C interop behind one type.
///
/// The architecture contract (issue #49) requires a *correct* cmark lifecycle:
/// GFM extensions are registered once and attached to the parser before any
/// feed/finish; the parser, node tree, iterator and render buffer are all
/// invocation-local and freed on every path (including thrown errors), never
/// leaked and never shared between calls. This type is that guarantee.
///
/// It is deliberately an `enum` namespace with pure static functions: there is
/// no stored C state, so nothing can outlive a single call.
enum CMarkGFM {
    /// Option bitmask values, forwarded from cmark-gfm.h.
    static let optDefault: Int32 = CMARK_OPT_DEFAULT
    static let optUnsafe: Int32 = CMARK_OPT_UNSAFE
    static let optSmart: Int32 = CMARK_OPT_SMART

    /// A deterministic replacement performed after parsing but before rendering:
    /// the authored range was already substituted with `sentinel` in the source
    /// handed to the parser, and this spec turns that sentinel back into a
    /// custom cmark node carrying the derived `html`.
    struct CustomNodeSpec: Sendable, Equatable {
        let sentinel: String
        let isBlock: Bool
        let html: String

        init(sentinel: String, isBlock: Bool, html: String) {
            self.sentinel = sentinel
            self.isBlock = isBlock
            self.html = html
        }
    }

    /// What one render produced: the HTML fragment plus the structural facts the
    /// composer needs in order to apply its target policy. Reported from the same
    /// tree walk that does the substitutions, so no extra pass is needed.
    struct Rendered {
        let html: String
        /// `true` when the source contained an authored raw-HTML block or inline
        /// span. Self-contained export treats this as fatal; PDF warns.
        let containsRawHTML: Bool
    }

    private static let coreExtensionNames = ["table", "strikethrough", "autolink", "tagfilter", "tasklist"]

    /// cmark-gfm's `ensure_registered` mutates a process-global registry behind a
    /// plain `int` guard, so concurrent exports must not race it. A `static let`
    /// initialiser is run exactly once under the Swift runtime's own lock, which
    /// is the guarantee cmark itself does not provide.
    private static let extensionsRegistered: Void = {
        cmark_gfm_core_extensions_ensure_registered()
    }()

    /// Parses `text`, applies `customNodes` and `urlTransformer`, and renders an
    /// HTML fragment.
    ///
    /// `options` is the exact cmark render option bitmask. When it includes
    /// `CMARK_OPT_UNSAFE`, authored raw HTML is preserved and the `tagfilter`
    /// extension (always attached) still strips dangerous tags.
    ///
    /// `urlTransformer` is called for every image/link URL; it runs on the
    /// caller's thread during the single tree walk.
    static func render(
        _ text: String,
        options: Int32,
        customNodes: [CustomNodeSpec] = [],
        urlTransformer: ((String, Bool) -> URLDisposition)? = nil
    ) throws -> Rendered {
        // Reading the `static let` runs its initialiser exactly once under the
        // Swift runtime's own lock. `precondition` is not used here because it
        // is stripped in `-Ounchecked` builds, which would drop registration.
        _ = extensionsRegistered

        guard let parser = cmark_parser_new(options) else {
            throw CMarkError.parserCreationFailed
        }
        defer { cmark_parser_free(parser) }

        for name in coreExtensionNames {
            guard let extensionPointer = cmark_find_syntax_extension(name) else { continue }
            cmark_parser_attach_syntax_extension(parser, extensionPointer)
        }

        // Feed from the string's own contiguous UTF-8 storage. `withCString`
        // would copy the whole document to append a NUL terminator that
        // `cmark_parser_feed` never reads, since the length is explicit.
        var source = text
        source.withUTF8 { buffer in
            guard let base = buffer.baseAddress, !buffer.isEmpty else { return }
            base.withMemoryRebound(to: CChar.self, capacity: buffer.count) { chars in
                cmark_parser_feed(parser, chars, buffer.count)
            }
        }

        guard let root = cmark_parser_finish(parser) else {
            throw CMarkError.parseProducedNoDocument
        }
        defer { cmark_node_free(root) }

        var walkResult = WalkResult()
        transform(root, customNodes: customNodes, urlTransformer: urlTransformer, result: &walkResult)

        // tagfilter/table/tasklist rendering reads the parser's extension list,
        // so it must be taken from the parser while it is still alive.
        let extensions = cmark_parser_get_syntax_extensions(parser)
        guard let rendered = cmark_render_html(root, options, extensions) else {
            throw CMarkError.renderFailed
        }
        defer { free(rendered) }

        return Rendered(html: String(cString: rendered), containsRawHTML: walkResult.sawRawHTML)
    }

    /// Convenience for callers that only need the HTML fragment.
    static func renderHTML(
        _ text: String,
        options: Int32,
        customNodes: [CustomNodeSpec] = [],
        urlTransformer: ((String, Bool) -> URLDisposition)? = nil
    ) throws -> String {
        try render(text, options: options, customNodes: customNodes, urlTransformer: urlTransformer).html
    }

    // MARK: - Tree transformation

    /// Facts gathered while walking the tree, so the composer never needs a
    /// second pass over the document to learn them.
    private struct WalkResult {
        var sawRawHTML = false
    }

    /// A manual recursive walk (not a cmark iterator) so that leaf nodes — in
    /// particular `TEXT`, which the iterator never exits — can be mutated
    /// safely. The next sibling is captured before any mutation; replaced
    /// nodes are never recursed into because their replacements are already
    /// fully built and clean.
    private static func transform(
        _ root: UnsafeMutablePointer<cmark_node>,
        customNodes: [CustomNodeSpec],
        urlTransformer: ((String, Bool) -> URLDisposition)?,
        result: inout WalkResult
    ) {
        let blockSpecs = Dictionary(uniqueKeysWithValues: customNodes.filter(\.isBlock).map { ($0.sentinel, $0) })
        let inlineSpecs = InlineSentinelIndex(customNodes.filter { !$0.isBlock })
        walk(root, blockSpecs: blockSpecs, inlineSpecs: inlineSpecs, urlTransformer: urlTransformer, result: &result)
    }

    private static func walk(
        _ node: UnsafeMutablePointer<cmark_node>,
        blockSpecs: [String: CustomNodeSpec],
        inlineSpecs: InlineSentinelIndex,
        urlTransformer: ((String, Bool) -> URLDisposition)?,
        result: inout WalkResult
    ) {
        applyNodePolicy(node, urlTransformer: urlTransformer, result: &result)

        var child = cmark_node_first_child(node)
        while let current = child {
            let next = cmark_node_next(current)
            let childKind = cmark_node_get_type(current)

            if childKind == CMARK_NODE_TEXT {
                // Text nodes are leaves; there is nothing below them to walk.
                substituteInlineSentinels(current, inlineSpecs: inlineSpecs)
            } else if childKind == CMARK_NODE_PARAGRAPH,
                      let spec = blockSpec(for: current, bySentinel: blockSpecs) {
                replace(current, withCustom: spec)
            } else {
                walk(
                    current,
                    blockSpecs: blockSpecs,
                    inlineSpecs: inlineSpecs,
                    urlTransformer: urlTransformer,
                    result: &result
                )
            }

            child = next
        }
    }

    /// Rewrites one node's URL when it is an image or link, and notes authored
    /// raw HTML when it is not.
    ///
    /// The node type is read as the cmark enum rather than its string name: the
    /// string form allocates a Swift `String` for every node in the document,
    /// which is the hot path of a large export.
    private static func applyNodePolicy(
        _ node: UnsafeMutablePointer<cmark_node>,
        urlTransformer: ((String, Bool) -> URLDisposition)?,
        result: inout WalkResult
    ) {
        let kind = cmark_node_get_type(node)
        if kind == CMARK_NODE_HTML_BLOCK || kind == CMARK_NODE_HTML_INLINE {
            result.sawRawHTML = true
            return
        }
        guard kind == CMARK_NODE_IMAGE || kind == CMARK_NODE_LINK,
              let urlTransformer, let url = cmark_node_get_url(node) else {
            return
        }

        switch urlTransformer(String(cString: url), kind == CMARK_NODE_IMAGE) {
        case .keep:
            break
        case let .rewrite(replacement):
            _ = replacement.withCString { cmark_node_set_url(node, $0) }
        case .blank:
            _ = "".withCString { cmark_node_set_url(node, $0) }
        }
    }

    /// Returns the spec for a block sentinel when `node` is a paragraph whose
    /// only child is a text node holding exactly that sentinel.
    private static func blockSpec(
        for node: UnsafeMutablePointer<cmark_node>,
        bySentinel: [String: CustomNodeSpec]
    ) -> CustomNodeSpec? {
        guard !bySentinel.isEmpty else { return nil }
        guard let firstChild = cmark_node_first_child(node) else { return nil }
        guard cmark_node_next(firstChild) == nil else { return nil }
        guard cmark_node_get_type(firstChild) == CMARK_NODE_TEXT else { return nil }
        guard let literal = cmark_node_get_literal(firstChild) else { return nil }
        guard let spec = bySentinel[String(cString: literal)] else { return nil }
        return spec
    }

    /// Replaces every inline sentinel inside a text node, splitting the node into
    /// a sequence of text nodes and custom inline nodes. A no-op when the text
    /// holds no sentinel.
    private static func substituteInlineSentinels(
        _ node: UnsafeMutablePointer<cmark_node>,
        inlineSpecs: InlineSentinelIndex
    ) {
        guard !inlineSpecs.isEmpty, let literal = cmark_node_get_literal(node) else { return }
        let value = String(cString: literal)

        if let spec = inlineSpecs.specsBySentinel[value] {
            replace(node, withCustom: spec)
            return
        }

        // `pending` is the start of the text run not yet emitted; every match
        // ends strictly after it starts, so the walk always advances.
        var pieces: [Piece] = []
        var pending = value.startIndex
        while let found = inlineSpecs.firstMatch(in: value, from: pending) {
            if pending < found.range.lowerBound {
                pieces.append(.text(String(value[pending ..< found.range.lowerBound])))
            }
            pieces.append(.custom(found.spec))
            pending = found.range.upperBound
        }

        // No sentinel matched: leave the node exactly as parsed.
        guard !pieces.isEmpty else { return }
        if pending < value.endIndex {
            pieces.append(.text(String(value[pending...])))
        }

        guard let firstSpec = pieces.first else { return }
        let first = makeNode(for: firstSpec)
        // Insert the whole sequence into the tree before `node`, one node at a
        // time, then unlink and free the original. Building the chain outside
        // the tree first would be undone by `insert_before`, which unlinks its
        // sibling and clears its sibling pointers.
        cmark_node_insert_before(node, first)
        var last = first
        for piece in pieces.dropFirst() {
            let nextNode = makeNode(for: piece)
            cmark_node_insert_after(last, nextNode)
            last = nextNode
        }
        cmark_node_unlink(node)
        cmark_node_free(node)
    }

    private static func makeNode(for piece: Piece) -> UnsafeMutablePointer<cmark_node> {
        switch piece {
        case let .text(string):
            guard let node = cmark_node_new(CMARK_NODE_TEXT) else {
                fatalError("cmark node allocation failed")
            }
            _ = string.withCString { cmark_node_set_literal(node, $0) }
            return node
        case let .custom(spec):
            guard let node = cmark_node_new(CMARK_NODE_CUSTOM_INLINE) else {
                fatalError("cmark node allocation failed")
            }
            setCustomHTML(spec.html, on: node)
            return node
        }
    }

    private static func replace(_ node: UnsafeMutablePointer<cmark_node>, withCustom spec: CustomNodeSpec) {
        let nodeType: cmark_node_type = spec.isBlock ? CMARK_NODE_CUSTOM_BLOCK : CMARK_NODE_CUSTOM_INLINE
        guard let custom = cmark_node_new(nodeType) else { return }
        setCustomHTML(spec.html, on: custom)
        cmark_node_replace(node, custom)
        // `cmark_node_replace` unlinks `node` but does not free it; the node
        // tree is freed wholesale by the root's `cmark_node_free`, which will
        // not reach this unlinked node.
        cmark_node_free(node)
    }

    /// cmark copies both strings, so the C buffers only need to outlive the call.
    private static func setCustomHTML(_ html: String, on node: UnsafeMutablePointer<cmark_node>) {
        _ = html.withCString { cmark_node_set_on_enter(node, $0) }
        _ = "".withCString { cmark_node_set_on_exit(node, $0) }
    }

    private enum Piece {
        case text(String)
        case custom(CustomNodeSpec)
    }

    enum CMarkError: Error, LocalizedError, CustomStringConvertible {
        case parserCreationFailed
        case parseProducedNoDocument
        case renderFailed

        var description: String {
            switch self {
            case .parserCreationFailed: "cmark could not create a parser"
            case .parseProducedNoDocument: "cmark produced no document"
            case .renderFailed: "cmark could not render HTML"
            }
        }

        var errorDescription: String? {
            description
        }
    }
}
