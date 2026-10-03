import Foundation

/// The document's link reference definitions, indexed by normalised label once so each block can pick
/// out the few it actually references in time proportional to its own size (not the definition count).
public struct PreviewLinkDefinitionIndex: Sendable {
    private let lines: [String]
    private let indicesByLabel: [String: [Int]]
    private let unlabeled: [Int]

    public init(_ definitions: [String]) {
        lines = definitions
        var byLabel: [String: [Int]] = [:]
        var loose: [Int] = []
        for (index, line) in definitions.enumerated() {
            if let label = Self.label(ofDefinition: line) {
                byLabel[label, default: []].append(index)
            } else {
                loose.append(index)
            }
        }
        indicesByLabel = byLabel
        unlabeled = loose
    }

    public var isEmpty: Bool {
        lines.isEmpty
    }

    /// `source` with the definitions it references prepended, separated by a BLANK line (a single newline
    /// let a block that begins `(…)`, `"…"` or `'…'` be read as the optional title of the last definition).
    public func prefixed(_ source: String) -> String {
        guard !lines.isEmpty else { return source }
        var chosen = Set(unlabeled)
        for token in Self.bracketedLabels(in: source) {
            if let indices = indicesByLabel[token] {
                chosen.formUnion(indices)
            }
        }
        guard !chosen.isEmpty else { return source }
        return chosen.sorted().map { lines[$0] }.joined(separator: "\n") + "\n\n" + source
    }

    /// CommonMark label matching: case-folded, with runs of whitespace collapsed and the ends trimmed.
    static func normalized(_ label: String) -> String {
        label.folding(options: .caseInsensitive, locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func label(ofDefinition definition: String) -> String? {
        guard let open = definition.firstIndex(of: "["),
              let close = definition[open...].firstIndex(of: "]")
        else { return nil }
        return normalized(String(definition[definition.index(after: open) ..< close]))
    }

    /// Every `[…]` token in `text` (a label may span lines), normalised. One linear scan.
    private static func bracketedLabels(in text: String) -> [String] {
        var labels: [String] = []
        var current: String?
        for character in text {
            switch character {
            case "[":
                current = ""
            case "]":
                if let label = current {
                    labels.append(normalized(label))
                }
                current = nil
            default:
                current?.append(character)
            }
        }
        return labels
    }
}
