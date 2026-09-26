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
    /// The SwiftUI-observed document text: used ONLY as a reactive trigger
    /// (`.onChange(of: text)` below) so a live edit re-runs the search.
    /// Never read directly to build the search input — see `resolvedText`.
    let text: String
    /// Returns the text to actually search, read fresh at the moment of
    /// each search rather than captured once. Callers pass
    /// `editorStore.existingSystem(for:)?.text`, the live `EditorTextSystem`'s
    /// own text — NOT this view's own `text` prop above: `DocumentEditorSplitView`'s
    /// own established precedent (`EditorStatusBarView(text: system.text, ...)`,
    /// with a doc comment on exactly this) is that the SwiftUI `text`
    /// binding can trail the live text system by up to one render pass
    /// while `EditorTextSystem.isPerformingProgrammaticTextUpdate` is set
    /// (an external file reload/conflict-resolution replacement
    /// deliberately skips publishing it, `EditorView.swift`'s
    /// `textDidChange`) — searching that stale snapshot instead of the
    /// live text could highlight/select the wrong location for one frame.
    let resolvedText: () -> String
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
    /// EPIC-22 §6.14, Slice 5b: called with the transaction Replace/Replace
    /// All built (`EditorFindModel.replaceCurrentTransaction(with:)`/
    /// `replaceAllTransaction(with:)`) so the caller can apply it to the
    /// live `EditorTextSystem` — this view never mutates text itself,
    /// matching `EditorFindModel`'s own "never mutates live text" contract.
    let onReplace: (EditorEditTransaction) -> Void

    @FocusState private var isQueryFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
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

                if model.isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityIdentifier("findBarSearching")
                }

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

            replaceRow
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

    /// Always shown alongside the query row (not a collapsible "expand for
    /// replace" toggle — the simplest complete shape for this slice, and a
    /// standard one: e.g. Sublime Text's default Find bar does the same).
    private var replaceRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.secondary)
                TextField("Replace", text: $model.replacementText)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("findBarReplaceField")
                    .onKeyPress(phases: .down) { press in
                        switch press.key {
                        case .return:
                            replaceCurrent()
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

            Button("Replace") {
                replaceCurrent()
            }
            .buttonStyle(.bordered)
            .disabled(model.currentMatch == nil || model.isSearching)
            .accessibilityIdentifier("findBarReplaceButton")

            Button("Replace All") {
                replaceAll()
            }
            .buttonStyle(.bordered)
            .disabled(model.matchCount == 0 || model.isSearching)
            .accessibilityIdentifier("findBarReplaceAllButton")

            Spacer(minLength: 0)
        }
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

    /// `updateMatches(in:)` runs off-main and can be superseded by a later
    /// call before it resolves (rapid typing, or a slow/pathological regex
    /// still in flight) — see that method's own doc comment. When that
    /// happens it returns `false` and this skips `onMatchesChanged()`
    /// entirely, since `model`'s own state was left untouched by the
    /// discarded call and re-announcing it would be a redundant, no-op
    /// re-application of whatever the current, still-authoritative state
    /// already is.
    private func recomputeMatches(anchor: Int?) {
        let text = resolvedText()
        Task {
            guard await model.updateMatches(in: text, preferringLocationNear: anchor) else { return }
            onMatchesChanged()
        }
    }

    /// A no-op (not an error) when there's no current match to replace, or
    /// while a search is still in flight — mirrors the disabled state of
    /// the "Replace" button, but this guard is what actually matters: the
    /// Return key inside the replace field calls this method directly,
    /// bypassing the button's own `.disabled` modifier entirely. Without
    /// the `isSearching` check, a Replace fired while `updateMatches(in:)`
    /// is still resolving (e.g. a slow regex, or the user kept typing) would
    /// build a transaction from the OLD, pre-edit `matches`/`currentMatch` —
    /// positions computed against text or a query that no longer applies —
    /// and apply it straight to the CURRENT live text, silently replacing
    /// whatever unrelated content now sits at that stale offset. A hostile
    /// review of this exact slice found this gap; §6.14 never disclosed it
    /// as an accepted risk, so this is a genuine fix, not new scope.
    private func replaceCurrent() {
        guard !model.isSearching, let transaction = model.replaceCurrentTransaction(with: model.replacementText)
        else { return }
        onReplace(transaction)
    }

    /// See `replaceCurrent()`'s own doc comment — the same staleness risk
    /// applies here, at N matches instead of one.
    private func replaceAll() {
        guard !model.isSearching, let transaction = model.replaceAllTransaction(with: model.replacementText) else {
            return
        }
        onReplace(transaction)
    }
}
