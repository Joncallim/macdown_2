import CryptoKit
import Foundation
import SwiftSoup

/// Private acceptance boundary for opt-in SVG contributions. The ordinary
/// export writers never call this path. A receipt covers one exact assembled
/// document and cannot be reused after body, head or template recomposition.
enum SVGAssemblyOwnership {
    struct Manifest: Sendable {
        fileprivate let markedSHA256: String
        fileprivate let fragmentSHA256: String
        fileprivate let fragmentRoots: [SVGIDNamespace.MarkedRoot]
        fileprivate let roots: [RootInspection]
    }

    struct Publication: Sendable {
        let html: String
        fileprivate let sha256: String
    }

    fileprivate struct RootInspection: Sendable, Equatable {
        let rootID: String
        let ownedIDs: Set<String>
        let references: Set<String>
        let keyframes: Set<String>
        let fontFamilies: Set<String>
        let ancestorTags: [String]
        let elementIndex: Int
        let subtreeTags: [String]
    }

    private static let parserLock = NSLock()
    private static let maximumAnalyzedBytes = 8 * 1024 * 1024
    private static let maximumRoots = 64
    private static let maximumOwnedIDs = 4096

    static func inspect(
        markedDocument: String, fragment: SVGIDNamespace.MarkedFragment
    ) -> Manifest? {
        guard markedDocument.utf8.count <= maximumAnalyzedBytes,
              !fragment.roots.isEmpty, fragment.roots.count <= maximumRoots,
              markedDocument.components(separatedBy: fragment.html).count == 2,
              fragment.roots.allSatisfy({
                  markedDocument.components(separatedBy: $0.startMarker).count == 2
                      && markedDocument.components(separatedBy: $0.endMarker).count == 2
              })
        else { return nil }
        return parserLock.withLock {
            guard let document = try? SwiftSoup.parse(markedDocument),
                  let roots = inspect(document, expected: fragment.roots, markersRequired: true),
                  let rawAncestors = rawAncestorMap(
                      for: fragment.roots.map(\.startMarker), in: markedDocument
                  )
            else { return nil }
            for (item, root) in zip(fragment.roots, roots) {
                guard let raw = rawAncestors[item.startMarker],
                      raw == root.ancestorTags.reversed().filter({ $0 != "#root" })
                else { return nil }
            }
            return Manifest(markedSHA256: sha256(markedDocument),
                            fragmentSHA256: sha256(fragment.html),
                            fragmentRoots: fragment.roots, roots: roots)
        }
    }

    /// Only these returned bytes may be published. Parse again after removing
    /// the private markers; browser repair or changed definitions invalidate
    /// the receipt rather than silently changing the accepted ownership graph.
    static func publish(
        markedDocument: String, fragment: SVGIDNamespace.MarkedFragment,
        inspected: Manifest
    ) -> Publication? {
        guard inspected.markedSHA256 == sha256(markedDocument),
              inspected.fragmentSHA256 == sha256(fragment.html),
              inspected.fragmentRoots == fragment.roots else { return nil }
        guard let publishable = strippedMarkers(from: markedDocument, roots: fragment.roots) else { return nil }
        guard publishable.utf8.count <= maximumAnalyzedBytes else { return nil }
        return parserLock.withLock {
            guard let document = try? SwiftSoup.parse(publishable),
                  let roots = inspect(document, expected: fragment.roots, markersRequired: false),
                  roots == inspected.roots else { return nil }
            return Publication(html: publishable, sha256: sha256(publishable))
        }
    }

    static func stillMatches(_ html: String, publication: Publication) -> Bool {
        publication.sha256 == sha256(html)
    }

    private static func strippedMarkers(
        from marked: String, roots: [SVGIDNamespace.MarkedRoot]
    ) -> String? {
        var output = ""
        var cursor = marked.startIndex
        for root in roots {
            for marker in [root.startMarker, root.endMarker] {
                guard let range = marked.range(of: marker, range: cursor ..< marked.endIndex),
                      marked[range.upperBound...].range(of: marker) == nil else { return nil }
                output += marked[cursor ..< range.lowerBound]
                cursor = range.upperBound
            }
        }
        output += marked[cursor...]
        return output
    }

    private static func inspect(
        _ document: Document, expected: [SVGIDNamespace.MarkedRoot], markersRequired: Bool
    ) -> [RootInspection]? {
        guard let elements = try? document.getAllElements().array() else { return nil }
        let expectedIDs = expected.reduce(into: Set<String>()) { $0.formUnion($1.ownedIDs) }
        guard expectedIDs.count <= maximumOwnedIDs,
              expectedIDs.count == expected.reduce(0, { $0 + $1.ownedIDs.count }) else { return nil }
        var globalIDs: [String: [Element]] = [:]
        for element in elements where element.hasAttr("id") {
            guard let id = try? element.attr("id") else { return nil }
            if id.hasPrefix("mt117-svg-") {
                guard expectedIDs.contains(id) else { return nil }
                globalIDs[id, default: []].append(element)
            }
        }
        guard expectedIDs.allSatisfy({ globalIDs[$0]?.count == 1 }) else { return nil }

        var inspections: [RootInspection] = []
        var rootElements: [Element] = []
        for item in expected {
            guard let root = globalIDs[item.rootID]?.first,
                  let inspection = inspectRoot(root, expected: item, markersRequired: markersRequired)
            else { return nil }
            inspections.append(inspection)
            rootElements.append(root)
        }
        guard validateOutside(elements: elements, roots: rootElements, inspections: inspections,
                              generatedIDs: expectedIDs) else { return nil }
        return inspections
    }

    private static func inspectRoot(
        _ root: Element, expected: SVGIDNamespace.MarkedRoot, markersRequired: Bool
    ) -> RootInspection? {
        guard root.tagNameNormal() == "svg", let parent = root.parent(),
              let subtree = try? root.getAllElements().array(),
              let location = parent.children().array().firstIndex(where: { $0 === root })
        else { return nil }
        let ids = subtree.compactMap { element -> String? in
            guard element.hasAttr("id") else { return nil }
            return try? element.attr("id")
        }
        guard ids.count == expected.ownedIDs.count, Set(ids) == expected.ownedIDs,
              markerPairIsValid(around: root, in: parent, item: expected, required: markersRequired),
              let refs = referenceTargets(in: subtree), refs.isSubset(of: expected.ownedIDs),
              let definitions = definitions(in: subtree)
        else { return nil }
        var ancestors: [String] = []
        var cursor: Element? = parent
        while let node = cursor {
            ancestors.append(node.tagNameNormal())
            cursor = node.parent()
        }
        return RootInspection(
            rootID: expected.rootID, ownedIDs: expected.ownedIDs, references: refs,
            keyframes: definitions.keyframes, fontFamilies: definitions.fontFamilies,
            ancestorTags: ancestors, elementIndex: location,
            subtreeTags: subtree.map { $0.tagNameNormal() }
        )
    }

    private static func markerPairIsValid(
        around root: Element, in parent: Element,
        item: SVGIDNamespace.MarkedRoot, required: Bool
    ) -> Bool {
        // childNodesCopy() deep-copies SwiftSoup nodes, breaking identity.
        // This read-only pass must inspect the actual parsed siblings.
        let nodes = parent.getChildNodes()
        guard let index = nodes.firstIndex(where: { $0 === root }) else { return false }
        if !required {
            return true
        }
        guard index > 0, index + 1 < nodes.count,
              let before = nodes[index - 1] as? Comment,
              let after = nodes[index + 1] as? Comment else { return false }
        return item.startMarker == "<!--\(before.getData())-->"
            && item.endMarker == "<!--\(after.getData())-->"
    }

    private static func validateOutside(
        elements: [Element], roots: [Element], inspections: [RootInspection], generatedIDs: Set<String>
    ) -> Bool {
        let generatedKeyframes = inspections.reduce(into: Set<String>()) { $0.formUnion($1.keyframes) }
        let generatedFonts = inspections.reduce(into: Set<String>()) { $0.formUnion($1.fontFamilies) }
        for element in elements where !roots.contains(where: { isInside(element, root: $0) }) {
            guard let refs = referenceTargets(in: [element], allowExternal: true),
                  refs.isDisjoint(with: generatedIDs) else { return false }
            if element.getAttributes()?.asList().contains(where: {
                $0.getValue().lowercased().contains("mt117-svg-") || $0.getValue().contains("\\")
            }) == true {
                return false
            }
            if element.tagNameNormal() == "link",
               (try? element.attr("rel").lowercased().split(whereSeparator: \.isWhitespace).contains("stylesheet")) ==
               true {
                // A companion stylesheet is a separate byte stream and needs
                // its own bound inventory before this path can accept it.
                return false
            }
            guard element.tagNameNormal() == "style" else { continue }
            let css = element.data()
            guard !css.lowercased().contains("mt117-svg-"), !css.lowercased().contains("@import"),
                  let definitions = definitions(in: [element]),
                  definitions.keyframes.isDisjoint(with: generatedKeyframes),
                  definitions.fontFamilies.isDisjoint(with: generatedFonts) else { return false }
        }
        return true
    }

    private static func isInside(_ element: Element, root: Element) -> Bool {
        var cursor: Element? = element
        while let node = cursor {
            if node === root {
                return true
            }
            cursor = node.parent()
        }
        return false
    }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
