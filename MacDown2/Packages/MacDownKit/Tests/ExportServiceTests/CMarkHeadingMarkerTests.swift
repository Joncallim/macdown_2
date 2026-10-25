@testable import ExportService
import Foundation
import Testing

@Suite("Generated heading markers")
struct CMarkHeadingMarkerTests {
    @Test func optInMarkersIdentifyOnlyGeneratedHeadingsAndRestoreExactOutput() throws {
        let source = """
        # Repeat

        <h1 id="authored">Raw heading</h1>

        <!--MT117-forged-0-->

        <script>let example = '<b id=scripted>'</script>

        # Repeat
        """
        let options = CMarkGFM.optUnsafe | CMarkGFM.optSmart
        let ordinary = try CMarkGFM.render(source, options: options)
        let marked = try CMarkGFM.render(source, options: options, headingAnalysis: .marked)

        #expect(ordinary.headingMarkers.isEmpty)
        #expect(ordinary.headingLocations.isEmpty)
        #expect(ordinary.headingSourceSHA256 == nil)
        #expect(marked.headingMarkers.count == 2)
        #expect(marked.headingMarkers.map(\.location) == marked.headingLocations)
        #expect(Set(marked.headingMarkers.map(\.comment)).count == 2)

        var restored = marked.html
        for marker in marked.headingMarkers {
            let exact = "<h\(marker.location.level)>\(marker.comment)"
            #expect(restored.components(separatedBy: exact).count == 2)
            restored = restored.replacingOccurrences(of: exact, with: "<h\(marker.location.level)>")
        }
        #expect(restored == ordinary.html)
        #expect(restored.contains("<h1 id=\"authored\">Raw heading</h1>"))
        #expect(restored.contains("<!--MT117-forged-0-->"))
    }

    @Test func markersTrackSetextAndNestedHeadingNodes() throws {
        let source = """
        Setext
        ======

        > ## Quoted
        """
        let marked = try CMarkGFM.render(source, options: CMarkGFM.optDefault, headingAnalysis: .marked)
        #expect(marked.headingMarkers.map(\.location.level) == [1, 2])
        #expect(marked.headingMarkers.map(\.location.line) == [1, 4])
        for marker in marked.headingMarkers {
            #expect(marked.html.contains("<h\(marker.location.level)>\(marker.comment)"))
        }
    }
}
