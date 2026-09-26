import EditorCore
import SwiftUI
import TextSearch

/// The current-document Find bar (EPIC-22 §6.14, Slice 5a): an inline bar
/// docked above the editor — not a floating `NSPanel` like `GoToLinePanel`/
/// `CommandPalettePanel` — matching every comparable editor's own find UI
/// and §6.14's explicit departure from this codebase's two existing
/// floating-panel precedents. Pure presentation: all find/navigate state and
/// logic lives in the bound `EditorFindModel`; this view's own job is typing
/// query/option changes into it, re-running the search whenever the query,
/// options, or underlying document text changes, and reporting the result
/// back up via `onMatchesChanged` so the caller can push highlight ranges to
/// the text view and reveal the current match.
struct FindBarView: View {
    @Bindable var model: EditorFindModel
    /// The live document text, re-read on every change so an edit made
    /// while the bar is open keeps match positions correct.
    let text: String
    /// The caret location at the moment the bar was shown, used ONLY by the
    /// very first search on `.onAppear` — so opening Find starts searching
    /// forward from where the user actually was, matching every comparable
    /// editor's own convention, rather than always jumping to the first
    /// match in the document. Every later re-search (query/option/text
    /// change, or explicit Find Next/Previous) anchors off `model`'s own
    /// current match instead, per `recomputeMatches`.
    let initialAnchor: Int
    /// Called after `model.matches`/`model.currentIndex` changes for any
    /// reason (query edit, option toggle, live text edit, Find Next/
    /// Previous) so the caller can push highlight ranges to the text view
    /// and reveal the new current match. Never called with stale state —
    /// this view always updates `model` first, synchronously, before
    /// calling this.
    let onMatchesChanged: () -> Void
    let onClose: () -> Void

    @FocusState private var isQueryFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Find", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($isQueryFocused)
                    .accessibilityIdentifier("findBarQueryField")
                    .onKeyPress(phases: .down) { press in
                        switch press.key {
                        case .return:
                            if press.modifiers.contains(.shift) {
                                navigate(model.findPrevious)
                            } else {
                                navigate(model.findNext)
                            }
                            return .handled
                        case .escape:
                            onClose()
                            return .handled
                        default:
                            return .ignored
                        }
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .frame(minWidth: 200, maxWidth: 320)

            optionToggle("Aa", isOn: $model.options.isCaseSensitive, help: "Case Sensitive")
            optionToggle("W", isOn: $model.options.isWholeWord, help: "Whole Word")
            optionToggle(".*", isOn: $model.options.isRegex, help: "Regular Expression")

            statusLabel

            Spacer(minLength: 0)

            Button {
                navigate(model.findPrevious)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(model.matchCount == 0)
            .help("Find Previous")
            .accessibilityIdentifier("findBarPreviousButton")

            Button {
                navigate(model.findNext)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(model.matchCount == 0)
            .help("Find Next")
            .accessibilityIdentifier("findBarNextButton")

            Divider().frame(height: 16)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
            }
            .help("Close (Esc)")
            .accessibilityIdentifier("findBarCloseButton")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("findBar")
        .onAppear {
            isQueryFocused = true
            recomputeMatches(anchor: model.currentMatch?.range.location ?? initialAnchor)
        }
        .onChange(of: model.query) { _, _ in recomputeMatches(anchor: model.currentMatch?.range.location) }
        .onChange(of: model.options) { _, _ in recomputeMatches(anchor: model.currentMatch?.range.location) }
        .onChange(of: text) { _, _ in recomputeMatches(anchor: model.currentMatch?.range.location) }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if let error = model.error {
            Text(errorMessage(for: error))
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
                .accessibilityIdentifier("findBarError")
        } else if model.query.isEmpty {
            EmptyView()
        } else if model.matchCount == 0 {
            Text("No Results")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("findBarStatus")
        } else {
            Text("\((model.currentIndex ?? 0) + 1) of \(model.matchCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("findBarStatus")
        }
    }

    private func errorMessage(for error: SearchQueryError) -> String {
        switch error {
        case let .invalidRegex(message): message
        }
    }

    private func optionToggle(_ title: String, isOn: Binding<Bool>, help: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(minWidth: 20)
        }
        .buttonStyle(.bordered)
        .tint(isOn.wrappedValue ? Color.accentColor : Color.clear)
        .help(help)
    }

    /// Runs `navigation` (`model.findNext`/`findPrevious`), then reports the
    /// resulting state up — used by both the keyboard (Return/Shift-Return)
    /// and the toolbar chevron buttons so both paths behave identically.
    private func navigate(_ navigation: () -> SearchMatch?) {
        _ = navigation()
        onMatchesChanged()
    }

    private func recomputeMatches(anchor: Int?) {
        model.updateMatches(in: text, preferringLocationNear: anchor)
        onMatchesChanged()
    }
}
