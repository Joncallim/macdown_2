import AppKit
import MarkdownEngine
import SwiftUI
import Textual
import Themes

/// A block-sliced Markdown preview backed by Textual.
///
/// The document is rendered one top-level block at a time so that scroll sync
/// can map editor source lines to preview geometry. If Textual fails on a
/// block, that block degrades to plain text rather than crashing the preview.
public struct TextualMarkdownPreview: MarkdownPreviewing {
    public let document: MarkdownDocument?
    public let text: String?
    public let theme: PreviewTheme
    public let linkResolver: PreviewLinkResolver
    public let controller: ScrollSyncController

    /// Pre-computed preview blocks, if the caller caches them. When `nil`
    /// (the default) blocks are sliced lazily from `document`/`text`.
    public let blocks: [PreviewBlock]?

    /// Pre-computed link reference definitions, if the caller caches them.
    /// When `nil` (the default) they are extracted lazily from `text`. See
    /// ``PreviewLinkDefinitions`` for why every block needs these.
    public let linkDefinitions: [String]?

    public init(
        document: MarkdownDocument?,
        text: String?,
        theme: PreviewTheme,
        linkResolver: PreviewLinkResolver = PreviewLinkResolver(),
        controller: ScrollSyncController = ScrollSyncController(),
        blocks: [PreviewBlock]? = nil,
        linkDefinitions: [String]? = nil
    ) {
        self.document = document
        self.text = text
        self.theme = theme
        self.linkResolver = linkResolver
        self.controller = controller
        self.blocks = blocks
        self.linkDefinitions = linkDefinitions
    }

    /// Per-block measured heights, keyed by position in ``displayBlocks``.
    /// Fed to ``ScrollSyncController`` so it can map editor lines to preview
    /// scroll offsets. Cleared whenever the block list changes.
    @State private var measuredBlockHeights: [Int: Double] = [:]

    private var displayBlocks: [PreviewBlock] {
        blocks ?? computedBlocks
    }

    private var computedBlocks: [PreviewBlock] {
        guard let document, let text else { return [] }
        return PreviewBlock.blocks(from: document, text: text)
    }

    private var displayLinkDefinitions: [String] {
        linkDefinitions ?? computedLinkDefinitions
    }

    private var computedLinkDefinitions: [String] {
        guard let text else { return [] }
        return PreviewLinkDefinitions.extract(from: text)
    }

    /// The stack must be eager (`VStack`), not `LazyVStack`, for two
    /// independent reasons:
    ///
    /// 1. Textual's `StructuredText` populates its content asynchronously
    ///    after first layout, and lazy stacks never realize those zero-height
    ///    children, so the preview renders blank.
    /// 2. Scroll sync (``ScrollSyncController``) sums measured heights across
    ///    every block in the document to convert between editor lines and
    ///    preview scroll position — a block a `LazyVStack` never realized
    ///    because it was off-screen would report a height of zero, silently
    ///    corrupting that math for every block after it. Eager rendering is
    ///    what guarantees every block reports a real frame, not just the
    ///    visible ones.
    public var body: some View {
        // `GeometryReader` measures the viewport OUTSIDE the `ScrollView`,
        // not as its direct child. A `GeometryReader` placed directly inside
        // a `ScrollView` has no intrinsic content size of its own, so it
        // collapses to the viewport's height and reports that fixed size
        // upward — the scroll view then believes the content is exactly
        // viewport-tall even though the `VStack` inside actually overflows
        // it, and never becomes scrollable for documents taller than one
        // screen. Measuring here and passing the value down as a `minHeight`
        // floor (not the content's actual height) avoids that collapse while
        // still filling the viewport for short documents.
        GeometryReader { viewportGeometry in
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        // Fill the entire scrollable document view with the
                        // theme background. Without this, an empty document
                        // leaves the NSScrollView's default material/clear
                        // content area visible, which produces a vertical band
                        // in dark mode.
                        theme.background.swiftUIColor
                            .frame(
                                minWidth: 0,
                                maxWidth: .infinity,
                                minHeight: viewportGeometry.size.height
                            )

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(displayBlocks.enumerated()), id: \.element.id) { index, block in
                                BlockView(
                                    block: block,
                                    theme: theme,
                                    linkResolver: linkResolver,
                                    linkDefinitions: displayLinkDefinitions
                                )
                                .id(block.id)
                                // Inter-block spacing. Applied here, above the
                                // measurement below, so the gap is part of the
                                // frame the scroll-sync map sees. The first
                                // block gets none — the container's own padding
                                // already provides the top margin.
                                .padding(.top, index == 0 ? 0 : PreviewTypography.gapAbove(block.kind))
                                // Measured with `onGeometryChange` rather than a
                                // `GeometryReader` writing a `PreferenceKey`.
                                // Every block wrote its own entry into one
                                // dictionary-valued preference, all reduced
                                // together, so SwiftUI logged "Bound preference
                                // BlockFramePreferenceKey tried to update
                                // multiple times per frame" on every layout pass
                                // — a preference write that itself triggers the
                                // re-layout that writes it again. This reports
                                // per block, outside the preference system, and
                                // only the height is needed.
                                .onGeometryChange(for: CGFloat.self) { proxy in
                                    proxy.size.height
                                } action: { newHeight in
                                    measuredBlockHeights[index] = Double(newHeight)
                                    controller.update(blockHeights: measuredBlockHeights)
                                }
                            }
                        }
                        // Textual reads the ambient `.font` as its "1x" scale for
                        // headings/code/etc., so setting a comfortable base size
                        // here (SwiftUI's `.body` default is ~13pt — cramped for
                        // an article-reading pane) scales the whole hierarchy
                        // proportionally rather than just the paragraph text.
                        .font(.system(size: PreviewTypography.baseFontSize))
                        // Textual's own default paragraph line-spacing (0.23x
                        // font size) is a noticeable outlier next to its other
                        // block styles — block quotes use 0.471x, code blocks
                        // 0.39x — and paragraphs are most of a typical document,
                        // so that mismatch reads as "the whole preview is
                        // cramped." Bring it in line with the rest of the scale.
                        .textual.paragraphStyle(PreviewTypography.ParagraphStyle())
                        // Same reasoning, for the gap below a heading and
                        // above the body text that follows it.
                        .textual.headingStyle(PreviewTypography.HeadingStyle())
                        .padding(16)
                        .frame(
                            minWidth: 0,
                            maxWidth: .infinity,
                            minHeight: viewportGeometry.size.height,
                            alignment: .topLeading
                        )
                        .background(theme.background.swiftUIColor)
                    }
                }
                .background(theme.background.swiftUIColor)
                .onScrollGeometryChange(for: Double.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, newOffset in
                    controller.previewContentOffsetDidChange(newOffset)
                }
                .onChange(of: displayBlocks) { _, newBlocks in
                    // Drop only the stale *tail* — entries past the new block
                    // count would otherwise inflate the scroll map's totals
                    // once the document gets shorter. Surviving entries are
                    // kept deliberately: `onGeometryChange` only fires when a
                    // block's height actually changes, so clearing the whole
                    // dictionary here (as this first did) left every height at
                    // zero until something happened to resize, and a zeroed
                    // map makes every preview scroll resolve to the last
                    // block — which drags the editor to the end of the
                    // document on every sync.
                    measuredBlockHeights = measuredBlockHeights.filter { $0.key < newBlocks.count }
                    controller.update(map: ScrollSyncMap(blocks: newBlocks))
                    controller.update(blockHeights: measuredBlockHeights)
                }
                .onChange(of: controller.targetPreviewFraction) { _, fraction in
                    guard let fraction else { return }
                    let animated = controller.animatesNextPreviewScroll
                    let preciseBlock = controller.targetPreviewBlock
                    controller.animatesNextPreviewScroll = false
                    scroll(
                        to: fraction,
                        preciseBlock: preciseBlock,
                        animated: animated,
                        using: proxy,
                        viewportHeight: Double(viewportGeometry.size.height)
                    )
                    controller.targetPreviewFraction = nil
                    controller.targetPreviewBlock = nil
                }
            }
        }
    }

    /// Scrolls to the position `fraction` names — not always the containing
    /// block's *top* edge, but the point `fraction` falls at *within* that
    /// block, via a proportional `anchor`. Always snapping to the block's top
    /// (the first version of this) discarded that position entirely: for a
    /// block shorter than the viewport the difference is invisible, but for
    /// one taller than the viewport (a long paragraph, a big table), each
    /// small onward scroll re-snapped to the very top of the *same* block, or
    /// jumped to the top of the *next* block the moment the source line
    /// crossed into it — so the block's lower portion could never be brought
    /// into view at all.
    ///
    /// A precise pixel offset (via SwiftUI's `ScrollPosition`) was tried
    /// next, and fixed that — but writing to `ScrollPosition` at the rate
    /// live scroll-sync calls this (many times a second, continuously)
    /// triggered spurious re-layout that Textual's `StructuredText` responds
    /// to by reporting drastically smaller measured heights for blocks far
    /// from the new position, corrupting `blockHeights` for every block
    /// after them and producing wild, wrong jumps — confirmed by the same
    /// corruption never occurring under genuine user-driven preview
    /// scrolling, which never writes to `ScrollPosition` at all. Block-id
    /// anchored `scrollTo` does not share this: it is the same mechanism
    /// genuine user scrolling already proved stable under, just with a
    /// proportional anchor instead of a fixed `.top`.
    ///
    /// `animated` is true only for the outline sidebar's jump-to-heading
    /// (see `ScrollSyncController.jump(toLine:)`); ordinary live scroll-sync
    /// leaves it false so the preview snaps instantly and keeps pace with
    /// the user's own scroll gesture rather than trailing an animation.
    ///
    /// See `ScrollSyncController.previewScrollTarget(forFraction:viewportHeight:preciseBlock:)`
    /// for why the anchor it returns is 0 (`.top`-equivalent) except when the
    /// target block genuinely overflows the viewport, and why `preciseBlock`
    /// — when the caller has one — is used instead of deriving the block
    /// from `fraction`.
    private func scroll(
        to fraction: Double,
        preciseBlock: PreviewBlockTarget?,
        animated: Bool,
        using proxy: ScrollViewProxy,
        viewportHeight: Double
    ) {
        guard let target = controller.previewScrollTarget(
            forFraction: fraction,
            viewportHeight: viewportHeight,
            preciseBlock: preciseBlock
        ), let blockID = displayBlocks[safe: target.blockIndex]?.id
        else {
            return
        }
        let anchor = UnitPoint(x: 0, y: target.anchorY)
        if animated {
            withAnimation(.easeInOut(duration: ScrollSyncController.jumpAnimationDuration)) {
                proxy.scrollTo(blockID, anchor: anchor)
            }
        } else {
            proxy.scrollTo(blockID, anchor: anchor)
        }
    }
}

// MARK: - Block view

private struct BlockView: View {
    let block: PreviewBlock
    let theme: PreviewTheme
    let linkResolver: PreviewLinkResolver
    let linkDefinitions: [String]

    /// The block's source with every document-wide link reference definition
    /// prepended, so a `[text][label]` reference in this block resolves even
    /// when `label` is defined in a different block. See
    /// ``PreviewLinkDefinitions``. Oversize blocks skip this — they already
    /// bypass Textual entirely.
    private var renderedSource: String {
        guard !linkDefinitions.isEmpty else { return block.source }
        return (linkDefinitions + [block.source]).joined(separator: "\n")
    }

    var body: some View {
        Group {
            if block.isOversize {
                // Oversize blocks skip Textual entirely: it has no size limit
                // of its own and is documented to freeze/crash on inputs
                // around 100 KB (see ``PreviewBlock/oversizeByteThreshold``).
                Text(block.source)
                    .font(.system(.body, design: .monospaced))
            } else {
                // `baseURL` resolves relative image sources (e.g.
                // `![plot](images/plot.png)`) during parsing. `linkResolver`
                // carries the same document base URL used to resolve clicked
                // links, so both paths agree on what "relative" means.
                StructuredText(renderedSource, parser: PreviewMarkupParser(baseURL: linkResolver.baseURL))
                    .tint(theme.linkColor.swiftUIColor)
                    .environment(
                        \.openURL,
                        OpenURLAction { url in
                            let resolved = linkResolver.resolve(url)
                            NSWorkspace.shared.open(resolved)
                            return .handled
                        }
                    )
            }
        }
        .foregroundStyle(theme.foreground.swiftUIColor)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Helpers

private extension ThemeColor {
    var swiftUIColor: Color {
        Color(nsColor: nsColor)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
