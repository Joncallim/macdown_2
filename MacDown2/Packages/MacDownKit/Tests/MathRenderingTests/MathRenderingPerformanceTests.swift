import AppKit
import Foundation
import Math
import MathRendering
import Testing

/// Closes E19's long-disclosed performance-evidence gap ("a large-equation-
/// document Release performance measurement was never run" —
/// `RELEASE_EVIDENCE.md`, inherited into E15's own scope). Real,
/// non-mocked `MathImageRenderer` calls — the same real `SwiftUIMath`
/// `ImageRenderer` path `MathImageRendererTests` already proves reliable in
/// a plain SPM test target — run at a volume representative of a genuinely
/// math-heavy document, not a two-equation smoke test.
@Suite("MathRendering performance")
@MainActor
struct MathRenderingPerformanceTests {
    private static let context = ExportMathRenderContext(
        foregroundRed: 0.1, foregroundGreen: 0.1, foregroundBlue: 0.1, pixelScale: 2
    )

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1000.0 + Double(components.attoseconds) / 1e15
    }

    /// A representative mix of inline and display equations of varying
    /// complexity, not 100 copies of the same trivial expression — repeated
    /// identical input could hide a cost that only shows up with real
    /// variety (different glyph sets, fractions, roots, sums, matrices).
    private static let sampleLatex: [(String, MathSpan.Style)] = [
        ("x = 1", .inline),
        ("E = mc^2", .inline),
        ("\\frac{a}{b} + \\frac{c}{d}", .inline),
        ("\\sqrt{x^2 + y^2}", .inline),
        ("\\sum_{i=1}^{n} i^2 = \\frac{n(n+1)(2n+1)}{6}", .display),
        ("\\int_0^\\infty e^{-x^2} \\, dx = \\frac{\\sqrt{\\pi}}{2}", .display),
        ("\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}", .display),
        ("\\alpha + \\beta = \\gamma \\cdot \\delta", .inline),
        ("\\lim_{x \\to 0} \\frac{\\sin x}{x} = 1", .display),
        ("\\nabla \\times \\vec{F} = 0", .inline),
    ]

    /// 100 equations: a genuinely math-heavy document (occasional inline math
    /// throughout many pages of technical writing), not a pathological case.
    @Test func renderingOneHundredEquationsCompletesWithinBudget() throws {
        let duration = try ContinuousClock().measure {
            for index in 0 ..< 100 {
                let (latex, style) = Self.sampleLatex[index % Self.sampleLatex.count]
                let span = MathSpan(range: 0 ..< latex.count, style: style, latex: latex)
                _ = try MathImageRenderer.render(span: span, context: Self.context)
            }
        }

        let durationMilliseconds = milliseconds(duration)
        #expect(
            durationMilliseconds < 10000,
            "rendering 100 equations took \(durationMilliseconds) ms (budget 10000 ms)"
        )
    }

    /// A single equation must never itself be slow enough to visibly stall
    /// typing — this is the per-equation budget the 100-equation test above
    /// would otherwise average away.
    @Test func renderingASingleEquationCompletesWithinBudget() throws {
        let span = MathSpan(range: 0 ..< 20, style: .display, latex: "\\sum_{i=1}^{n} i^2 = \\frac{n(n+1)(2n+1)}{6}")
        let duration = try ContinuousClock().measure {
            _ = try MathImageRenderer.render(span: span, context: Self.context)
        }
        let durationMilliseconds = milliseconds(duration)
        #expect(durationMilliseconds < 500, "a single equation took \(durationMilliseconds) ms (budget 500 ms)")
    }
}
