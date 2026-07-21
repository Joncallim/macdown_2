import AppKit
@testable import EditorCore
import Testing

@MainActor
@Suite("EditorConfiguration application")
struct EditorConfigurationTests {
    private func makeSystem(configuration: EditorConfiguration) -> EditorTextSystem {
        EditorTextSystem(
            identity: UUID().uuidString,
            initialText: "hello world",
            configuration: configuration
        )
    }

    @Test("font is applied to the text view")
    func fontApplied() {
        let font = NSFont.monospacedSystemFont(ofSize: 16, weight: .bold)
        let system = makeSystem(configuration: EditorConfiguration(font: font))

        #expect(system.textView.font == font)
    }

    @Test("text insets are applied")
    func insetsApplied() {
        let insets = NSSize(width: 12, height: 16)
        let system = makeSystem(configuration: EditorConfiguration(
            font: .monospacedSystemFont(ofSize: 13, weight: .regular),
            textInsets: insets
        ))

        #expect(system.textView.textContainerInset == insets)
    }

    @Test("word wrap makes container track text view width")
    func wordWrapTracksWidth() {
        let system = EditorTextSystem(
            identity: UUID().uuidString,
            initialText: "",
            configuration: EditorConfiguration(font: .systemFont(ofSize: 13), wrapsLines: true)
        )

        #expect(system.textView.textContainer?.widthTracksTextView == true)
        #expect(system.textView.isHorizontallyResizable == false)
    }

    @Test("no wrap allows horizontal resizing")
    func noWrapAllowsHorizontalResize() {
        let system = makeSystem(configuration: EditorConfiguration(
            font: .systemFont(ofSize: 13),
            wrapsLines: false
        ))

        #expect(system.textView.textContainer?.widthTracksTextView == false)
        #expect(system.textView.isHorizontallyResizable == true)
    }

    @Test("line height multiple is applied as a typing attribute")
    func lineHeightApplied() {
        let system = makeSystem(configuration: EditorConfiguration(
            font: .systemFont(ofSize: 13),
            lineHeightMultiple: 1.5
        ))

        let paragraphStyle = system.textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        #expect(paragraphStyle?.lineHeightMultiple == 1.5)
    }

    @Test("overscroll adds scroll-view height to bottom text inset")
    func overscrollAddsPadding() {
        let insets = NSSize(width: 8, height: 8)
        let configuration = EditorConfiguration(
            font: .systemFont(ofSize: 13),
            textInsets: insets,
            scrollsPastEnd: true
        )
        let system = makeSystem(configuration: configuration)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        system.scrollView = scrollView
        system.apply(configuration)

        #expect(system.textView.textContainerInset == NSSize(
            width: insets.width,
            height: insets.height + 600
        ))
    }

    @Test("overscroll disabled uses only text insets")
    func overscrollDisabled() {
        let insets = NSSize(width: 8, height: 8)
        let configuration = EditorConfiguration(
            font: .systemFont(ofSize: 13),
            textInsets: insets,
            scrollsPastEnd: false
        )
        let system = makeSystem(configuration: configuration)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        system.scrollView = scrollView
        system.apply(configuration)

        #expect(system.textView.textContainerInset == insets)
    }
}
