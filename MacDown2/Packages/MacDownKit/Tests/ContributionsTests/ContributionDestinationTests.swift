@testable import Contributions
import Testing

@Suite("Contribution destination admission")
struct ContributionDestinationTests {
    @Test func markdownCanBePresentedAtEveryDestination() {
        let markdown = ContributionRepresentation.markdown("**text**")
        for destination in destinations {
            #expect(markdown.admission(to: destination) == .accepted)
        }
    }

    @Test func passiveHTMLIsRestrictedToStaticDestinations() {
        let html = ContributionRepresentation.html("<span>text</span>")
        #expect(html.admission(to: .nativePreview) == .unsupported(.nativePreview))
        #expect(html.admission(to: .htmlExport) == .accepted)
        #expect(html.admission(to: .pdfExport) == .accepted)
        #expect(html.admission(to: .quickLook) == .accepted)
    }

    private var destinations: [ContributionDestination] {
        [.nativePreview, .htmlExport, .pdfExport, .quickLook]
    }
}
