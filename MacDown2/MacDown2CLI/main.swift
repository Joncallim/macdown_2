import FileCore
import Foundation

/// Placeholder-level CLI. Real argument parsing (swift-argument-parser) lands
/// in EPIC-17 (#18). `formats` exists as the EPIC-11 format-behavior evidence:
/// the CLI's format list must never drift from the registry.
let arguments = CommandLine.arguments

if arguments.count >= 2, arguments[1] == "formats" {
    let registry = FileFormatRegistry()
    for format in registry.formats {
        let extensions = format.extensions.joined(separator: ",")
        let preview = String(describing: format.previewCapability)
        print("\(format.id)\textensions=\(extensions)\tpreview=\(preview)")
    }
    exit(0)
}

print("macdown2: CLI placeholder — see EPIC-17 (try `macdown2 formats`)")
