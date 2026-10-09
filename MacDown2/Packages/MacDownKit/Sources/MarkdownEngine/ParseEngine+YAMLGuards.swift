import Foundation
import Yams

extension ParseEngine {
    /// Yams expands every alias into a full copy, so a few hundred bytes of
    /// nested anchors ("billion laughs") expand to gigabytes and hang the shared
    /// parse actor. Total alias references bound the expansion (each level
    /// multiplies by at most its own fan-out, which is bounded by the total), so
    /// front matter with more than this many is left unparsed — its raw text and
    /// range are still reported — rather than expanded.
    static let maximumYAMLAliasReferences = 16

    /// libyaml accepts any non-space, non-flow-indicator character in an anchor
    /// name (`&-a`, `*.x`, `*é`), so the budget must not assume a letter.
    private static func canStartAnchorName(_ character: Character) -> Bool {
        !(character.isWhitespace || ",[]{}*".contains(character))
    }

    static func exceedsYAMLAliasBudget(_ raw: String) -> Bool {
        guard raw.contains("&") else { return false }
        var aliases = 0
        var previous: Character = "\n"
        var index = raw.startIndex
        while index < raw.endIndex {
            let character = raw[index]
            if character == "*", !(previous.isLetter || previous.isNumber || previous == "\\") {
                let next = raw.index(after: index)
                if next < raw.endIndex, Self.canStartAnchorName(raw[next]) {
                    aliases += 1
                    if aliases > maximumYAMLAliasReferences {
                        return true
                    }
                }
            }
            previous = character
            index = raw.index(after: index)
        }
        return false
    }

    static let maximumYAMLExpandedNodes = 50000

    /// The alias COUNT budget alone still allows doubling chains (`a1: [*a0, *a0]` … `a8: [*a7, *a7]`: 16 aliases,
    /// 256x), so a ~20 KB front matter expanded to 324 MB and several seconds on every parse. This sizes the
    /// expanded tree from the composed (unexpanded) one, memoising each anchor, and stops at the first overflow.
    static func exceedsYAMLExpansionBudget(_ root: Node) -> Bool {
        var sizes: [Anchor: Int] = [:]
        var overflow = false
        func size(_ node: Node) -> Int {
            guard !overflow else { return 0 }
            var total = 1
            switch node {
            case let .alias(alias):
                return sizes[alias.anchor] ?? 1
            case let .mapping(mapping):
                for (key, value) in mapping {
                    total += size(key) + size(value)
                    if total > maximumYAMLExpandedNodes {
                        overflow = true; return 0
                    }
                }
            case let .sequence(sequence):
                for child in sequence {
                    total += size(child)
                    if total > maximumYAMLExpandedNodes {
                        overflow = true; return 0
                    }
                }
            case .scalar:
                break
            }
            if let anchor = node.anchor {
                sizes[anchor] = total
            }
            return total
        }
        _ = size(root)
        return overflow
    }

    /// Iterative so a deeply nested document cannot exhaust the stack here either.
    static func hasOnlyScalarKeys(_ root: Node) -> Bool {
        var pending = [root]
        while let node = pending.popLast() {
            switch node {
            case let .mapping(mapping):
                for (key, value) in mapping {
                    guard case .scalar = key else { return false }
                    pending.append(value)
                }
            case let .sequence(sequence):
                pending.append(contentsOf: sequence)
            case .scalar, .alias:
                break
            }
        }
        return true
    }
}
