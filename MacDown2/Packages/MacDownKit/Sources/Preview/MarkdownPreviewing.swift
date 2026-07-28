import MarkdownEngine
import SwiftUI

/// A SwiftUI view that renders a Markdown preview.
///
/// Conforming types isolate the underlying rendering engine (Textual) from the
/// app target so churn in Textual's pre-1.0 API stays inside the `Preview`
/// module.
@MainActor
public protocol MarkdownPreviewing: View {
    /// The parsed document, if a parse has completed.
    var document: MarkdownDocument? { get }

    /// The source text that produced `document`.
    var text: String? { get }
}
