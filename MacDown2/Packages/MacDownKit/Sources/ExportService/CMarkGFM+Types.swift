import Foundation

extension CMarkGFM {
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
        /// Collected only when anchor analysis requests generated heading
        /// identity. Raw authored h-tags are never included in this list.
        let headingLocations: [HeadingLocation]
        /// Present only when heading locations were requested, so a later
        /// match can reject a result from a different transformed body.
        let headingSourceSHA256: String?
    }

    struct HeadingLocation: Sendable, Equatable {
        let level: Int
        let line: Int
        let column: Int
    }
}
