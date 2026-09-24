import EditorCore
import Foundation
import SwiftUI

/// The editor status bar (epic-22-implementation.md §6.7, §17 Slice 2b).
///
/// Shows line/column, selected/document character and word count, and
/// indentation mode/width — the three status items with no forward
/// dependency on a later slice. §6.7's scope-correction note records why
/// the epic issue's other status-bar items (multi-selection count,
/// line-ending state, encoding, syntax mode) are deliberately deferred to
/// Slices 3/8/9 rather than stubbed here.
struct EditorStatusBarView: View {
    let text: String
    let selectedRange: NSRange
    let lineIndex: EditorLineIndex
    let indentationWidth: Int
    let convertsTabsToSpaces: Bool
    let onGoToLine: () -> Void

    /// Not `private`: read directly by `EditorStatusBarViewTests`, which
    /// tests these pure computations without needing a full SwiftUI render
    /// pass (epic-22-implementation.md §6.7's promised status-bar test
    /// coverage).
    var lineColumnText: String {
        let nsText = text as NSString
        let line = lineIndex.line(atUTF16Offset: selectedRange.location)
        let column = lineIndex.column(atUTF16Offset: selectedRange.location, onLine: line, in: nsText)
        return String(localized: "Ln \(line), Col \(column)", bundle: .main)
    }

    var countText: String {
        if selectedRange.length > 0, let range = Range(selectedRange, in: text) {
            let selectedCharacterCount = text.distance(from: range.lowerBound, to: range.upperBound)
            return String(localized: "\(selectedCharacterCount) selected", bundle: .main)
        }
        let words = Self.wordCount(in: text)
        return String(localized: "\(text.count) characters, \(words) words", bundle: .main)
    }

    var indentationText: String {
        convertsTabsToSpaces
            ? String(localized: "Spaces: \(indentationWidth)", bundle: .main)
            : String(localized: "Tabs: \(indentationWidth)", bundle: .main)
    }

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onGoToLine) {
                Text(lineColumnText)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("statusBarLineColumn")
            .help("Go to Line/Column")

            Text(countText)
                .accessibilityIdentifier("statusBarCount")

            Spacer()

            Text(indentationText)
                .accessibilityIdentifier("statusBarIndentation")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editorStatusBar")
    }

    /// Foundation's own word-boundary logic (`enumerateSubstrings`,
    /// `.byWords`) — no new tokenizer, matching this codebase's established
    /// "reuse Foundation before inventing" pattern elsewhere. Not `private`:
    /// read directly by `EditorStatusBarViewTests`.
    ///
    /// `nonisolated` is required, not cosmetic: as a `static` member of a
    /// `View`-conforming type, this would otherwise inherit `@MainActor`
    /// isolation, and `NSString.enumerateSubstringsInRange:options:usingBlock:`
    /// can invoke its block from a thread that never went through Swift's
    /// executor-hopping machinery (confirmed via crash-log analysis: a real,
    /// intermittent `EXC_BREAKPOINT` in `swift_task_checkIsolatedSwift`,
    /// reproduced by `EditorStatusBarViewTests`). This function touches no
    /// actor-isolated state — only its own parameter and a local variable —
    /// so removing the inherited isolation is correct, not a workaround.
    nonisolated static func wordCount(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }
}
