import JSONSupport
import MarkdownEngine
import Observation

/// Per-window outline state (D8). Main-actor isolated: it is written from
/// SwiftUI event handlers and read from view bodies.
///
/// No parsing happens here (D2): `update(...)` is a pure function of the
/// `MarkdownDocument` the caller already has from the shared parse session.
@MainActor
@Observable
public final class OutlineController {
    public private(set) var items: [OutlineItem]
    public private(set) var availability: OutlineAvailability

    /// Where the caret/viewport is (D5). Distinct from `selectedItemID`.
    public private(set) var currentItemID: Int?

    /// The user's navigation cursor — bound to `List(selection:)` (D6).
    public var selectedItemID: Int?

    /// Collapsed nodes, by `OutlineItem.id`. In-memory only, and remapped
    /// through `OutlineIdentityMap` on every rebuild (D4).
    public var collapsedItemIDs: Set<Int>

    /// Set by `activate(_:)`; the app consumes it, drives the editor, and
    /// clears it. Same consume-and-clear contract as
    /// `ScrollSyncController.targetSourceLine`.
    public var pendingJumpLineRange: ClosedRange<Int>?

    /// Bumped by `requestFocus()` (D11). `SidebarView` observes and focuses.
    public private(set) var focusRequestID: Int

    // MARK: JSON channel (EPIC-11 §3.4)

    // Setters are `internal(set)` because the channel methods live in
    // `OutlineController+JSON.swift` (a separate file for the lint body
    // budget). The app target is a different module and can only read these;
    // the mutable selections/collapse follow the Markdown channel's `public
    // var` precedent.

    /// The JSON outline tree for a valid JSON document; empty otherwise.
    public internal(set) var jsonItems: [ContentOutlineItem]
    /// Availability of the JSON channel, for sidebar/preview placeholders.
    public internal(set) var jsonAvailability: OutlineAvailability
    /// The parser's diagnostic for an invalid JSON document, or `nil`.
    public internal(set) var jsonDiagnostic: JSONDiagnostic?
    /// Where the caret/viewport is, as the deepest outline node containing
    /// the UTF-16 reference offset.
    public internal(set) var jsonCurrentItemID: String?
    /// The user's navigation cursor in the JSON tree.
    public var jsonSelectedItemID: String?
    /// Collapsed JSON nodes, by path ID. In-memory only; path IDs are stable
    /// across edits and formatting, so state survives rebuilds unchanged.
    public var jsonCollapsedItemIDs: Set<String>
    /// Bumped by `requestJSONFocus()`.
    public internal(set) var jsonFocusRequestID: Int
    /// Set by `activateJSON(_:)`; the app consumes it, drives the editor
    /// jump, and clears it. Same consume-and-clear contract as
    /// `pendingJumpLineRange`.
    public var pendingJSONJumpSourceRange: Range<Int>?
    /// Rebuild counter for the JSON channel; exists for no-op tests.
    public internal(set) var jsonRebuildCount: Int

    /// The JSON text that produced the current `jsonItems`, used to skip
    /// redundant rebuilds.
    var lastAppliedJSONText: String?
    /// The last editor caret/viewport offset, re-translated through the
    /// current JSON tree on every rebuild.
    var jsonReferenceOffset: Int?

    /// The headings behind the current `items`, kept so the *next* rebuild
    /// can remap ordinal-keyed state against them (D4).
    private var lastHeadings: [HeadingItem]
    private var lastSourceMap: SourceMap?
    private var lastAppliedRevision: Int?

    /// The last editor caret/viewport offset (D5), re-translated through
    /// whichever `SourceMap` is current every time `update(...)` runs.
    private var referenceOffset: Int?

    public init() {
        items = []
        availability = .notParsed
        currentItemID = nil
        selectedItemID = nil
        collapsedItemIDs = []
        pendingJumpLineRange = nil
        focusRequestID = 0
        lastHeadings = []
        lastSourceMap = nil
        lastAppliedRevision = nil
        referenceOffset = nil
        jsonItems = []
        jsonAvailability = .notParsed
        jsonDiagnostic = nil
        jsonCurrentItemID = nil
        jsonSelectedItemID = nil
        jsonCollapsedItemIDs = []
        jsonFocusRequestID = 0
        pendingJSONJumpSourceRange = nil
        jsonRebuildCount = 0
        lastAppliedJSONText = nil
        jsonReferenceOffset = nil
    }

    /// Rebuilds from a parse result. No-ops when `document.revision` matches
    /// the last applied revision AND the availability verdict is unchanged, so
    /// SwiftUI body evaluations are free.
    ///
    /// - Parameters:
    ///   - document: the session's latest `MarkdownDocument`, or nil.
    ///   - isMarkdown: the app's format verdict (D7). When false, `items` is
    ///     emptied and no tree is built, whatever `document.headings` holds.
    ///   - formatName: display name for `.unsupportedFormat`.
    ///
    /// On rebuild, in this order (D4, D5):
    /// 1. `collapsedItemIDs` and `selectedItemID` are **remapped** from the
    ///    previous headings to the new ones via `OutlineIdentityMap`, then
    ///    intersected with `OutlineTree.allIDs` as a backstop.
    /// 2. `currentItemID` is recomputed by translating the stored reference
    ///    offset through `document.sourceMap` — the map that just arrived.
    public func update(document: MarkdownDocument?, isMarkdown: Bool, formatName: String) {
        let newAvailability = Self.resolveAvailability(
            document: document,
            isMarkdown: isMarkdown,
            formatName: formatName
        )
        guard document?.revision != lastAppliedRevision || newAvailability != availability else {
            return
        }

        let newHeadings = isMarkdown ? (document?.headings ?? []) : []
        let newItems = OutlineTree.build(from: newHeadings)
        let validIDs = OutlineTree.allIDs(newItems)

        let remappedCollapsed = OutlineIdentityMap.remap(collapsedItemIDs, from: lastHeadings, to: newHeadings)
        let remappedSelected = OutlineIdentityMap.remap(selectedItemID, from: lastHeadings, to: newHeadings)

        items = newItems
        availability = newAvailability
        collapsedItemIDs = remappedCollapsed.intersection(validIDs)
        selectedItemID = remappedSelected.flatMap { validIDs.contains($0) ? $0 : nil }

        lastHeadings = newHeadings
        lastSourceMap = document?.sourceMap
        lastAppliedRevision = document?.revision

        setCurrentItemID(Self.resolveCurrentItemID(
            offset: referenceOffset,
            headings: newHeadings,
            sourceMap: lastSourceMap
        ))
    }

    /// Editor caret or viewport moved (D5) — a UTF-16 offset into the live
    /// text, *not* a line. Stored, translated through the current parse's
    /// `SourceMap`, and re-translated on the next `update(...)`.
    /// Cheap enough to call on every keystroke and every scroll tick.
    public func referenceOffsetDidChange(_ utf16Offset: Int) {
        referenceOffset = utf16Offset
        setCurrentItemID(Self.resolveCurrentItemID(
            offset: utf16Offset,
            headings: lastHeadings,
            sourceMap: lastSourceMap
        ))
    }

    /// Assigns `currentItemID` only when it actually changes.
    ///
    /// `referenceOffsetDidChange` fires on every keystroke and every scroll
    /// tick, but the caret stays under the same heading for the overwhelming
    /// majority of them. `@Observable` sends a change notification on every
    /// *assignment*, not every *value change* — so an unconditional write
    /// here would re-render `SidebarView` (and re-walk its collapse-aware
    /// tree traversal) on every keystroke in the document, whether or not
    /// the outline has anything new to show.
    private func setCurrentItemID(_ newValue: Int?) {
        guard currentItemID != newValue else { return }
        currentItemID = newValue
    }

    /// Outline row activated (click or Return). Publishes `pendingJumpLineRange`
    /// and moves `selectedItemID` to `id`.
    public func activate(_ id: Int) {
        guard let item = OutlineTree.item(withID: id, in: items) else { return }
        pendingJumpLineRange = item.lineRange.lowerBound ... item.lineRange.lowerBound
        selectedItemID = id
    }

    /// ⌃⌘O (D11).
    ///
    /// Also selects a row when nothing is selected yet, defaulting to the
    /// current section if one is tracked. `focusRequestID` alone moves
    /// keyboard focus onto the `List`, but an unselected, focused `List` has
    /// no on-screen highlight — from the user's side, nothing visibly
    /// happened. Selecting a row is what actually shows the shortcut did
    /// something, and it's also what makes the very next arrow-key press
    /// move from somewhere sensible instead of nowhere.
    public func requestFocus() {
        if selectedItemID == nil {
            selectedItemID = currentItemID ?? OutlineTree.visibleRows(items, collapsed: collapsedItemIDs).first?.id
        }
        focusRequestID += 1
    }

    private static func resolveAvailability(
        document: MarkdownDocument?,
        isMarkdown: Bool,
        formatName: String
    ) -> OutlineAvailability {
        guard let document else { return .notParsed }
        guard isMarkdown else { return .unsupportedFormat(formatName: formatName) }
        return document.headings.isEmpty ? .noHeadings : .ready
    }

    private static func resolveCurrentItemID(
        offset: Int?,
        headings: [HeadingItem],
        sourceMap: SourceMap?
    ) -> Int? {
        guard let offset, let sourceMap else { return nil }
        return OutlineSelection.currentItemID(forLine: sourceMap.line(atUTF16Offset: offset), in: headings)
    }
}
