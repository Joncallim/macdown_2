import Diagrams
import Foundation

extension MermaidRenderContext {
    var foregroundHex: String {
        hex(red: foregroundRed, green: foregroundGreen, blue: foregroundBlue)
    }

    var backgroundHex: String {
        hex(red: backgroundRed, green: backgroundGreen, blue: backgroundBlue)
    }

    private func hex(red: Double, green: Double, blue: Double) -> String {
        let components = [red, green, blue].map { value in
            let finite = value.isFinite ? value : 0
            return UInt8((min(max(finite, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", components[0], components[1], components[2])
    }
}
