#if ISSUE117_NATIVE_ACCEPTANCE
    import AppKit
    import ExportService
    import Foundation

    /// Compiled only into the isolated, locally retained #117 acceptance app.
    /// Ordinary Release and Debug builds have no command or caller for this route.
    @MainActor
    enum Issue117NativeAcceptance {
        private static let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MostlyText-Issue117-Acceptance.log")

        static func run(from coordinator: WindowCoordinator?) {
            guard let coordinator, let model = coordinator.keyModel else {
                record("No key document; no export started")
                return
            }
            guard let operation = coordinator.beginValidatedSVGExportUsingPanel() else {
                record("Key document could not be captured; no export started")
                return
            }
            record("Captured key document; Save sheet requested")

            Task { @MainActor in
                let watchdog = Task { @MainActor in
                    do {
                        try await Task.sleep(for: .seconds(180))
                        record("Three-minute watchdog cancelled the export task")
                        operation.cancel()
                        try await Task.sleep(for: .seconds(5))
                        if coordinator.isExporting(model) {
                            record("Export guard still active five seconds after watchdog cancellation")
                        }
                    } catch is CancellationError {
                        // The operation settled before the watchdog fired.
                    } catch {
                        record("Watchdog error: \(error.localizedDescription)")
                    }
                }
                defer { watchdog.cancel() }

                do {
                    guard let result = try await operation.value else {
                        record("Save sheet cancelled; guard clear: \(!coordinator.isExporting(model))")
                        return
                    }
                    record(
                        "Published \(result.primaryFile.path); companions: \(result.companionFiles.count); "
                            + "guard clear: \(!coordinator.isExporting(model))"
                    )
                } catch is CancellationError {
                    record("Origin revoked or task cancelled; guard clear: \(!coordinator.isExporting(model))")
                } catch {
                    record("Export failed: \(error.localizedDescription); "
                        + "guard clear: \(!coordinator.isExporting(model))")
                }
            }
        }

        static func showLog() {
            if !FileManager.default.fileExists(atPath: logURL.path) {
                record("No export result yet")
            }
            if FileManager.default.fileExists(atPath: logURL.path) {
                NSWorkspace.shared.activateFileViewerSelecting([logURL])
            }
        }

        private static func record(_ message: String) {
            let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
            let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path)
            let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            var data = size <= 16 * 1024 ? ((try? Data(contentsOf: logURL)) ?? Data()) : Data()
            data.append(Data(line.utf8))
            do {
                try data.write(to: logURL, options: .atomic)
            } catch {
                NSLog("#117 acceptance log unavailable: %@", error.localizedDescription)
            }
        }
    }
#endif
