import Foundation

public extension String {
    /// Scalar-for-scalar equality. Swift's `==` treats canonically equivalent
    /// strings (U+212B ANGSTROM SIGN and U+00C5, or a precomposed and a
    /// decomposed é) as equal, which is wrong wherever the exact authored text
    /// decides persistence, dirtiness or what to publish (#183 F02). Display
    /// and name comparisons should keep using `==`.
    func isExactlyEqual(to other: String) -> Bool {
        utf8.elementsEqual(other.utf8)
    }
}
