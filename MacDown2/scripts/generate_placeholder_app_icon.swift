import AppKit
import Foundation

// Generates the functional placeholder app icon for MacDown 2's
// AppIcon.appiconset. This is NOT a final design — swap it out (and delete
// this script, or repoint it at real artwork) once a real icon exists.
//
// Usage: swift scripts/generate_placeholder_app_icon.swift <output-dir>
// Then copy the resulting PNGs over MacDown2/Assets.xcassets/AppIcon.appiconset/.

func makeIcon(pixelSize: Int) -> NSBitmapImageRep {
    // NSImage.lockFocus() renders into the *screen's* backing scale (2x on
    // a Retina display), silently doubling every pixel dimension regardless
    // of the NSSize passed to NSImage(size:) — confirmed empirically via
    // sips after actool's own dimension-mismatch warnings. Drawing into an
    // explicit NSBitmapImageRep-backed graphics context at the exact pixel
    // count sidesteps that entirely.
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not create bitmap for size \(pixelSize)")
    }
    bitmap.size = NSSize(width: pixelSize, height: pixelSize)

    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create graphics context for size \(pixelSize)")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let rect = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
    // macOS icons render their own corner rounding from a square canvas at
    // the system level, but drawing a rounded rect background ourselves
    // keeps a plain PNG preview (e.g. Finder icon view without the mask)
    // looking intentional rather than like a bare square.
    let cornerRadius = CGFloat(pixelSize) * 0.2237 // Apple's macOS icon corner-radius ratio
    let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    let topColor = NSColor(calibratedRed: 0.20, green: 0.47, blue: 0.95, alpha: 1.0)
    let bottomColor = NSColor(calibratedRed: 0.10, green: 0.28, blue: 0.70, alpha: 1.0)
    let gradient = NSGradient(starting: topColor, ending: bottomColor)
    gradient?.draw(in: backgroundPath, angle: -90)

    // A centered document glyph, forced to a flat white tone via an
    // explicit palette configuration (SF Symbols' documented, reliable
    // way to override a symbol's own default hierarchical/multicolor
    // rendering) rather than relying on legacy NSImage template tinting,
    // which vector symbol content does not reliably respect.
    if let symbol = NSImage(systemSymbolName: "doc.plaintext", accessibilityDescription: nil) {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: CGFloat(pixelSize) * 0.5, weight: .regular)
            .applying(.init(paletteColors: [.white]))
        let configured = symbol.withSymbolConfiguration(symbolConfig) ?? symbol
        let symbolSize = configured.size
        let origin = NSPoint(
            x: (CGFloat(pixelSize) - symbolSize.width) / 2,
            y: (CGFloat(pixelSize) - symbolSize.height) / 2
        )
        let destinationRect = NSRect(origin: origin, size: symbolSize)
        configured.draw(in: destinationRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

func writePNG(_ bitmap: NSBitmapImageRep, to url: URL, pixelSize: Int) {
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("Failed to encode PNG for \(url.lastPathComponent)\n".utf8))
        exit(1)
    }
    try? png.write(to: url)
    print("Wrote \(url.lastPathComponent) (\(pixelSize)x\(pixelSize))")
}

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError
        .write(Data("Usage: swift generate_placeholder_app_icon.swift <output-dir>\n".utf8))
    exit(1)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

/// (fileNameSuffix, pixelSize)
let sizes: [(String, Int)] = [
    ("16x16", 16),
    ("16x16@2x", 32),
    ("32x32", 32),
    ("32x32@2x", 64),
    ("128x128", 128),
    ("128x128@2x", 256),
    ("256x256", 256),
    ("256x256@2x", 512),
    ("512x512", 512),
    ("512x512@2x", 1024),
]

for (suffix, pixelSize) in sizes {
    let icon = makeIcon(pixelSize: pixelSize)
    let url = outputDir.appendingPathComponent("icon_\(suffix).png")
    writePNG(icon, to: url, pixelSize: pixelSize)
}
