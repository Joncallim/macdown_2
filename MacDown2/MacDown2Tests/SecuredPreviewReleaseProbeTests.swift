import Darwin
import FileCore
import Foundation
@testable import MacDown2
import Testing

/// Opt-in Release workload measurement. It records the test process high-water RSS while hardening the largest
/// admitted HTML source; it is not a claim about WebKit's separate process or a stable CI timing threshold.
@Suite("Preview Release resource probe", .enabled(if:
    ProcessInfo.processInfo.environment["MOSTLYTEXT_PREVIEW_RELEASE_PROBE"] == "1"))
@MainActor
struct SecuredPreviewReleaseProbeTests {
    @Test func largestHTMLSourceHasMeasuredTimeAndProcessMemory() throws {
        let document = FileDocument(fileURL: URL(fileURLWithPath: "/tmp/probe.html"))
        let prefix = "<html><head><title>Probe</title></head><body>"
        let source = prefix + String(
            repeating: "x", count: BoundedHTMLPreviewLoad.sourceLimit - prefix.utf8.count
        )
        let before = peakResidentBytes()
        let start = ContinuousClock.now
        let loads = try (0 ..< 3).map { _ in
            try BoundedHTMLPreviewLoad(document: document, source: source, grant: nil)
        }
        let elapsed = start.duration(to: .now)
        let after = peakResidentBytes()
        #expect(loads.allSatisfy { $0.mainData.count <= BoundedHTMLPreviewLoad.encodedLimit })
        #expect(throws: BoundedHTMLPreviewError.self) {
            _ = try BoundedHTMLPreviewLoad(document: document, source: source, grant: nil)
        }
        print("PREVIEW_RELEASE_PROBE sourceBytes=\(source.utf8.count) "
            + "characterStride=\(MemoryLayout<Character>.stride) "
            + "loads=\(loads.count) elapsedSeconds=\(elapsed.components.seconds) "
            + "elapsedAttoseconds=\(elapsed.components.attoseconds) peakRSSBeforeBytes=\(before) "
            + "peakRSSAfterBytes=\(after)")
    }

    private func peakResidentBytes() -> Int64 {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return -1 }
        return Int64(usage.ru_maxrss)
    }
}
