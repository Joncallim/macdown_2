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

    public init(
        document: MarkdownDocument?,
        text: String?,
        theme: PreviewTheme,
        linkResolver: PreviewLinkResolver = PreviewLinkResolver(),
        controller: ScrollSyncController = ScrollSyncController(),
        blocks: [PreviewBlock]? = nil
    ) {
        self.document = document
        self.text = text
        self.theme = theme
        self.linkResolver = linkResolver
        self.controller = controller
        self.blocks = blocks
    }

    private var displayBlocks: [PreviewBlock] {
        blocks ?? computedBlocks
    }

    private var computedBlocks: [PreviewBlock] {
        guard let document, let text else { return [] }
        return PreviewBlock.blocks(from: document, text: text)
    }

    /// The stack must be eager (`VStack`), not `LazyVStack`: Textual's
    /// `StructuredText` populates its content asynchronously after first
    /// layout, and lazy stacks never realize those zero-height children, so
    /// the preview renders blank. Eager rendering is also required for scroll
    /// sync — every block must report its frame, not just the visible ones.
    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { geometry in
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
                                minHeight: geometry.size.height
                            )

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(displayBlocks) { block in
                                BlockView(
                                    block: block,
                                    theme: theme,
                                    linkResolver: linkResolver
                                )
                                .id(block.id)
                                .background(
                                    GeometryReader { blockGeometry in
                                        Color.clear
                                            .preference(
                                                key: BlockFramePreferenceKey.self,
                                                value: [block.id: blockGeometry.frame(in: .named("previewContent"))]
                                            )
                                    }
                                )
                            }
                        }
                        .padding(16)
                        .frame(
                            minWidth: 0,
                            maxWidth: .infinity,
                            minHeight: geometry.size.height,
                            alignment: .topLeading
                        )
                        .background(theme.background.swiftUIColor)
                    }
                    .coordinateSpace(name: "previewContent")
                    .onPreferenceChange(BlockFramePreferenceKey.self) { frames in
                        updateBlockHeights(frames: frames)
                    }
                }
            }
            .background(theme.background.swiftUIColor)
            .onChange(of: displayBlocks) { _, newBlocks in
                controller.update(map: ScrollSyncMap(blocks: newBlocks))
            }
            .onChange(of: controller.targetPreviewFraction) { _, fraction in
                guard let fraction else { return }
                scroll(to: fraction, using: proxy)
                controller.targetPreviewFraction = nil
            }
        }
    }

    private func updateBlockHeights(frames: [UUID: CGRect]) {
        var heights: [Int: Double] = [:]
        for (index, block) in displayBlocks.enumerated() {
            heights[index] = Double(frames[block.id]?.height ?? 0)
        }
        controller.update(blockHeights: heights)
    }

    private func scroll(to fraction: Double, using proxy: ScrollViewProxy) {
        guard let line = controller.line(forPreviewFraction: fraction),
              let blockIndex = controller.map.blockIndex(forLine: line),
              let blockID = displayBlocks[safe: blockIndex]?.id
        else {
            return
        }
        withAnimation(.none) {
            proxy.scrollTo(blockID, anchor: .top)
        }
    }
}

// MARK: - Block view

private struct BlockView: View {
    let block: PreviewBlock
    let theme: PreviewTheme
    let linkResolver: PreviewLinkResolver

    var body: some View {
        StructuredText(block.source, parser: PreviewMarkupParser())
            .foregroundStyle(theme.foreground.swiftUIColor)
            .tint(theme.linkColor.swiftUIColor)
            .environment(
                \.openURL,
                OpenURLAction { url in
                    let resolved = linkResolver.resolve(url)
                    NSWorkspace.shared.open(resolved)
                    return .handled
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Geometry preference

private struct BlockFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] {
        [:]
    }

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
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
