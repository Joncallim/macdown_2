import AppKit
import UniformTypeIdentifiers

/// Shared "Copy as SVG" affordance for diagram block views (issue #86):
/// none of Mermaid/D2/Graphviz previously exposed an interactive way to
/// copy just the rendered diagram — only full-document export worked.
/// Writes both a plain-text representation (pastes into any text editor)
/// and, where the pasteboard type is available, a real `public.svg-image`
/// representation for apps that specifically look for vector image data.
enum DiagramClipboard {
    static func copySVG(_ svg: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        var types: [NSPasteboard.PasteboardType] = [.string]
        if let svgType = UTType("public.svg-image") {
            types.append(NSPasteboard.PasteboardType(svgType.identifier))
        }
        pasteboard.declareTypes(types, owner: nil)
        pasteboard.setString(svg, forType: .string)
        if let svgType = UTType("public.svg-image") {
            pasteboard.setData(Data(svg.utf8), forType: NSPasteboard.PasteboardType(svgType.identifier))
        }
    }
}
