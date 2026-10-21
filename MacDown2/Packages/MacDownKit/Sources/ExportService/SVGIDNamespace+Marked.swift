import Foundation

extension SVGIDNamespace {
    struct MarkedRoot: Sendable {
        let startMarker: String
        let endMarker: String
        let rootID: String
        let ownedIDs: Set<String>
    }

    struct MarkedFragment: Sendable {
        let html: String
        let roots: [MarkedRoot]
    }

    /// The private assembly probe marks each rewritten root with an
    /// unguessable, one-render comment pair. These markers never reach export;
    /// the final validator strips them only after checking the complete DOM.
    static func rewriteMarked(_ html: String, occurrence: Int) -> MarkedFragment? {
        let scalars = Array(html.unicodeScalars)
        guard let ranges = findRoots(in: scalars), !ranges.isEmpty else { return nil }
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var output = ""
        var copiedThrough = 0
        var roots: [MarkedRoot] = []
        for (ordinal, range) in ranges.enumerated() {
            output += String(String.UnicodeScalarView(scalars[copiedThrough ..< range.lowerBound]))
            let source = String(String.UnicodeScalarView(scalars[range]))
            let prefix = "mt117-svg-\(occurrence)-\(ordinal)-"
            guard let rewritten = rewriteRoot(source, prefix: prefix) else { return nil }
            let rewrittenScalars = Array(rewritten.unicodeScalars)
            guard let ownedIDs = collectIDs(in: rewrittenScalars),
                  let root = HTMLTagScanner.parseTag(at: 0, in: rewrittenScalars),
                  let rootID = root.attributes.first(where: { $0.name == "id" })?.value,
                  ownedIDs.contains(rootID), ownedIDs.allSatisfy({ $0.hasPrefix(prefix) })
            else { return nil }
            let start = "<!--MT117-SVG-\(nonce)-\(ordinal)-BEGIN-->"
            let end = "<!--MT117-SVG-\(nonce)-\(ordinal)-END-->"
            output += start + rewritten + end
            roots.append(MarkedRoot(startMarker: start, endMarker: end,
                                    rootID: rootID, ownedIDs: ownedIDs))
            copiedThrough = range.upperBound
        }
        output += String(String.UnicodeScalarView(scalars[copiedThrough...]))
        return MarkedFragment(html: output, roots: roots)
    }
}
