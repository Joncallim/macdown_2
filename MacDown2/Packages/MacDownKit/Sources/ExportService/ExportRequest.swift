import Foundation
import Themes

/// A self-contained export request: the live editor snapshot plus the inputs
/// the composer needs. No layout, resource-root, budget, metadata-policy, or
/// template identity may be supplied — those are fixed by the composer.
public struct ExportRequest: Sendable, Equatable {
    /// The full document text as it exists in the editor at export time.
    public let text: String

    /// `FileDocument.mutationGeneration` of the snapshot. Kept as `UInt` here;
    /// the exact `Int` conversion happens only at the `ParseExecuting` call.
    public let sourceGeneration: UInt

    /// The preview/export theme. Supplies the CSS variable block.
    public let theme: Theme

    /// The directory of the source document, used only to resolve relative
    /// resource references (e.g. `![alt](images/foo.png)`). `nil` for untitled
    /// documents, for which no local resource is resolvable.
    public let documentDirectory: URL?

    /// Renderer-neutral derived-content contributions (E19 inline math,
    /// E20 block diagrams) that this export must place. Empty for ordinary
    /// Markdown.
    public let contributions: [ExportDerivedContribution]

    public init(
        text: String,
        sourceGeneration: UInt,
        theme: Theme,
        documentDirectory: URL? = nil,
        contributions: [ExportDerivedContribution] = []
    ) {
        self.text = text
        self.sourceGeneration = sourceGeneration
        self.theme = theme
        self.documentDirectory = documentDirectory
        self.contributions = contributions
    }
}
