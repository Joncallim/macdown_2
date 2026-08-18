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

    private static let coreExtensionNames = ["table", "strikethrough", "autolink", "tagfilter", "tasklist"]

    /// Parses `text`, applies `customNodes` and `urlTransformer`, and renders an
    /// HTML fragment.
    ///
    /// `options` is the exact cmark render option bitmask. When it includes
    /// `CMARK_OPT_UNSAFE`, authored raw HTML is preserved and the `tagfilter`
    /// extension (always attached) still strips dangerous tags.
    ///
    /// `urlTransformer` is called for every image/link URL; it runs on the
    /// caller's thread during the single tree walk.
    static func renderHTML(
        _ text: String,
        options: Int32,
        customNodes: [CustomNodeSpec] = [],
        urlTransformer: ((String, Bool) -> URLDisposition)? = nil
    ) throws -> String {
        cmark_gfm_core_extensions_ensure_registered()

        guard let parser = cmark_parser_new(options) else {
            throw CMarkError.parserCreationFailed
        }
        defer { cmark_parser_free(parser) }

        for name in coreExtensionNames {
            guard let extensionPointer = cmark_find_syntax_extension(name) else { continue }
            cmark_parser_attach_syntax_extension(parser, extensionPointer)
        }

        text.withCString { buffer in
            cmark_parser_feed(parser, buffer, text.utf8.count)
        }

        guard let root = cmark_parser_finish(parser) else {
            throw CMarkError.parseProducedNoDocument
        }
        defer { cmark_node_free(root) }

        transform(root, customNodes: customNodes, urlTransformer: urlTransformer)

        // tagfilter/table/tasklist rendering reads the parser's extension list,
        // so it must be taken from the parser while it is still alive.
        let extensions = cmark_parser_get_syntax_extensions(parser)
        guard let rendered = cmark_render_html(root, options, extensions) else {
            throw CMarkError.renderFailed
        }
        defer { free(rendered) }

        return String(cString: rendered)
    }

    // MARK: - Tree transformation

    /// A manual recursive walk (not a cmark iterator) so that leaf nodes — in
    /// particular `TEXT`, which the iterator never exits — can be mutated
    /// safely. The next sibling is captured before any mutation; replaced
    /// nodes are never recursed into because their replacements are already
    /// fully built and clean.
    private static func transform(
        _ root: UnsafeMutablePointer<cmark_node>,
        customNodes: [CustomNodeSpec],
        urlTransformer: ((String, Bool) -> URLDisposition)?
    ) {
        let blockSpecs = Dictionary(uniqueKeysWithValues: customNodes.filter(\.isBlock).map { ($0.sentinel, $0) })
        let inlineSpecs = Dictionary(uniqueKeysWithValues: customNodes.filter { !$0.isBlock }.map { ($0.sentinel, $0) })
        walk(root, blockSpecs: blockSpecs, inlineSpecs: inlineSpecs, urlTransformer: urlTransformer)
    }

    private static func walk(
        _ node: UnsafeMutablePointer<cmark_node>,
        blockSpecs: [String: CustomNodeSpec],
        inlineSpecs: [String: CustomNodeSpec],
        urlTransformer: ((String, Bool) -> URLDisposition)?
    ) {
        // Rewrite the node's own URL when it is an image or link.
        let kind = typeString(node)
        if kind == "image" || kind == "link", let urlTransformer, let url = cmark_node_get_url(node) {
            let original = String(cString: url)
            switch urlTransformer(original, kind == "image") {
            case .keep:
                break
            case let .rewrite(replacement):
                _ = replacement.withCString { cmark_node_set_url(node, $0) }
            case .blank:
                _ = "".withCString { cmark_node_set_url(node, $0) }
            }
        }

        var child = cmark_node_first_child(node)
        while let current = child {
            let next = cmark_node_next(current)
            let childKind = typeString(current)

            if childKind == "text", !inlineSpecs.isEmpty, let literal = cmark_node_get_literal(current) {
                let value = String(cString: literal)
                if let spec = inlineSpecs[value] {
                    replace(current, withCustom: spec)
                } else if containsAnySentinel(value, inlineSpecs) {
                    splitTextNode(current, inlineSpecs: inlineSpecs)
                }
            } else if childKind == "paragraph", let spec = blockSpec(for: current, bySentinel: blockSpecs) {
                replace(current, withCustom: spec)
            } else {
                walk(current, blockSpecs: blockSpecs, inlineSpecs: inlineSpecs, urlTransformer: urlTransformer)
            }

            child = next
        }
    }

    /// Returns the spec for a block sentinel when `node` is a paragraph whose
    /// only child is a text node holding exactly that sentinel.
    private static func blockSpec(
        for node: UnsafeMutablePointer<cmark_node>,
        bySentinel: [String: CustomNodeSpec]
    ) -> CustomNodeSpec? {
        guard let firstChild = cmark_node_first_child(node) else { return nil }
        guard cmark_node_next(firstChild) == nil else { return nil }
        guard typeString(firstChild) == "text" else { return nil }
        guard let literal = cmark_node_get_literal(firstChild) else { return nil }
        guard let spec = bySentinel[String(cString: literal)] else { return nil }
        return spec
    }

    /// Whether any inline sentinel token occurs in `value`.
    private static func containsAnySentinel(_ value: String, _ inlineSpecs: [String: CustomNodeSpec]) -> Bool {
        inlineSpecs.keys.contains { value.contains($0) }
    }

    /// Splits a text node that contains inline sentinels into a sequence of
    /// text nodes and custom inline nodes.
    private static func splitTextNode(_ node: UnsafeMutablePointer<cmark_node>, inlineSpecs: [String: CustomNodeSpec]) {
        guard let literal = cmark_node_get_literal(node) else { return }
        let value = String(cString: literal)

        var pieces: [Piece] = []
        var remaining = Substring(value)
        while !remaining.isEmpty {
            var earliest: (spec: CustomNodeSpec, range: Range<String.Index>)?
            for (token, spec) in inlineSpecs {
                guard let range = remaining.range(of: token) else { continue }
                if earliest.map({ range.lowerBound < $0.range.lowerBound }) ?? true {
                    earliest = (spec, range)
                }
            }
            if let found = earliest {
                let before = String(remaining[remaining.startIndex ..< found.range.lowerBound])
                if !before.isEmpty {
                    pieces.append(.text(before))
                }
                pieces.append(.custom(found.spec))
                remaining = remaining[found.range.upperBound...]
            } else {
                pieces.append(.text(String(remaining)))
                remaining = Substring()
            }
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
            spec.html.withCString { buffer in
                cmark_node_set_on_enter(node, buffer)
                cmark_node_set_on_exit(node, "")
            }
            return node
        }
    }

    private static func replace(_ node: UnsafeMutablePointer<cmark_node>, withCustom spec: CustomNodeSpec) {
        let nodeType: cmark_node_type = spec.isBlock ? CMARK_NODE_CUSTOM_BLOCK : CMARK_NODE_CUSTOM_INLINE
        guard let custom = cmark_node_new(nodeType) else { return }
        spec.html.withCString { buffer in
            cmark_node_set_on_enter(custom, buffer)
            cmark_node_set_on_exit(custom, "")
        }
        cmark_node_replace(node, custom)
        // `cmark_node_replace` unlinks `node` but does not free it; the node
        // tree is freed wholesale by the root's `cmark_node_free`, which will
        // not reach this unlinked node.
        cmark_node_free(node)
    }

    /// The node type as its cmark string name ("text", "paragraph", …). Used
    /// instead of the raw `cmark_node_type` enum so the code is robust to the
    /// importer's case naming and to extension-added node types.
    private static func typeString(_ node: UnsafeMutablePointer<cmark_node>) -> String {
        guard let string = cmark_node_get_type_string(node) else { return "" }
        return String(cString: string)
    }

    private enum Piece {
        case text(String)
        case custom(CustomNodeSpec)
    }

    enum CMarkError: Error, CustomStringConvertible {
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
    }
}
