import Foundation
import SwiftSoup

extension SVGAssemblyOwnership {
    static func validateOutside(
        elements: [Element], roots: [Element],
        generatedIDs: Set<String>, auditedHeadCSS: AuditedHeadCSS?, requiredCSP: String?
    ) -> Bool {
        // A base changes URL resolution after admission. A refresh navigates
        // despite a resource CSP, and scripts are outside this publication policy.
        guard !elements.contains(where: {
            ["base", "script"].contains($0.tagNameNormal())
                || ($0.tagNameNormal() == "meta"
                    && (try? $0.attr("http-equiv").lowercased()) == "refresh")
        }) else { return false }
        guard requiredCSP == nil || elements.filter({ isCSP($0) }).count == 1 else { return false }
        var matchedCSS = false
        var matchedCSP = false
        for element in elements where !roots.contains(where: { isInside(element, root: $0) }) {
            if isCSP(element) {
                guard validCSP(element, required: requiredCSP, alreadyMatched: matchedCSP) else { return false }
                matchedCSP = requiredCSP != nil
            } else if element.tagNameNormal() == "style" {
                guard validStyle(element, audited: auditedHeadCSS, alreadyMatched: matchedCSS) else { return false }
                matchedCSS = matchedCSS
                    || !element.data().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } else if !safeOutsideElement(element, generatedIDs: generatedIDs) {
                return false
            }
        }
        return (auditedHeadCSS == nil || matchedCSS) && (requiredCSP == nil || matchedCSP)
    }

    private static func isCSP(_ element: Element) -> Bool {
        element.tagNameNormal() == "meta"
            && (try? element.attr("http-equiv").lowercased()) == "content-security-policy"
    }

    private static func validCSP(_ element: Element, required: String?, alreadyMatched: Bool) -> Bool {
        guard let required else { return true }
        return !alreadyMatched && element.parent()?.tagNameNormal() == "head"
            && (try? element.attr("content")) == required
    }

    private static func validStyle(_ element: Element, audited: AuditedHeadCSS?,
                                   alreadyMatched: Bool) -> Bool {
        // Only the exact bundled structural sheet and colour variables have
        // been reviewed for non-interference with generated SVG paint.
        guard element.parent()?.tagNameNormal() == "head",
              element.getAttributes()?.asList().isEmpty ?? true else { return false }
        let css = element.data()
        return css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (!alreadyMatched && css == audited?.emittedStyleData)
    }

    private static func safeOutsideElement(_ element: Element, generatedIDs: Set<String>) -> Bool {
        guard let refs = referenceTargets(in: [element], allowExternal: true),
              refs.isDisjoint(with: generatedIDs) else { return false }
        let attributes = element.getAttributes()?.asList() ?? []
        guard !attributes.contains(where: {
            $0.getKey().lowercased() == "style"
                && !$0.getValue().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else { return false }
        guard !attributes.contains(where: {
            $0.getValue().lowercased().contains("mt117-svg-") || $0.getValue().contains("\\")
        }) else { return false }
        if element.tagNameNormal() == "link",
           (try? element.attr("rel").lowercased().split(whereSeparator: \.isWhitespace)
               .contains("stylesheet")) == true {
            // Separate stylesheet bytes are not covered by this receipt.
            return false
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
}
