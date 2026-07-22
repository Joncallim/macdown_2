import Testing
@testable import Themes

struct ColorParsingTests {
    // MARK: - Hex forms

    @Test func hex3Digit() {
        let color = ThemeColor(cssString: "#f00")
        #expect(color?.red == 1.0)
        #expect(color?.green == 0.0)
        #expect(color?.blue == 0.0)
        #expect(color?.alpha == 1.0)
    }

    @Test func hex4Digit() {
        let color = ThemeColor(cssString: "#f008")
        #expect(color?.red == 1.0)
        #expect(color?.green == 0.0)
        #expect(color?.blue == 0.0)
        #expect(abs((color?.alpha ?? 0.0) - 0.533) < 0.001)
    }

    @Test func hex6Digit() {
        let color = ThemeColor(cssString: "#00ff00")
        #expect(color?.red == 0.0)
        #expect(color?.green == 1.0)
        #expect(color?.blue == 0.0)
        #expect(color?.alpha == 1.0)
    }

    @Test func hex8Digit() {
        let color = ThemeColor(cssString: "#0000ff80")
        #expect(color?.red == 0.0)
        #expect(color?.green == 0.0)
        #expect(color?.blue == 1.0)
        #expect(abs((color?.alpha ?? 0.0) - 0.502) < 0.001)
    }

    @Test func hexRequiresHash() {
        #expect(ThemeColor(cssString: "ff0000") == nil)
    }

    @Test func malformedHexReturnsNil() {
        #expect(ThemeColor(cssString: "#12") == nil)
        #expect(ThemeColor(cssString: "#gggggg") == nil)
    }

    // MARK: - rgb/rgba

    @Test func rgbIntegers() {
        let color = ThemeColor(cssString: "rgb(255,128,0)")
        #expect(color?.red == 1.0)
        #expect(abs((color?.green ?? 0.0) - 0.502) < 0.001)
        #expect(color?.blue == 0.0)
        #expect(color?.alpha == 1.0)
    }

    @Test func rgbaFloatAlpha() {
        let color = ThemeColor(cssString: "rgba(0,0,0,0.5)")
        #expect(color?.red == 0.0)
        #expect(color?.green == 0.0)
        #expect(color?.blue == 0.0)
        #expect(color?.alpha == 0.5)
    }

    @Test func rgbMissingComponentsReturnsNil() {
        #expect(ThemeColor(cssString: "rgb(255,128)") == nil)
        #expect(ThemeColor(cssString: "rgba(0,0,0)") == nil)
    }

    // MARK: - Named colours

    @Test func namedBasic() {
        let red = ThemeColor(cssString: "red")
        #expect(red?.red == 1.0)
        #expect(red?.green == 0.0)
        #expect(red?.blue == 0.0)
        #expect(red?.alpha == 1.0)
    }

    @Test func namedCaseInsensitive() {
        let blue = ThemeColor(cssString: "BLUE")
        #expect(blue?.red == 0.0)
        #expect(blue?.green == 0.0)
        #expect(blue?.blue == 1.0)
    }

    @Test func namedGrayVariants() {
        let gray = ThemeColor(cssString: "gray")
        let grey = ThemeColor(cssString: "grey")
        #expect(gray == grey)
    }

    @Test func invalidNameReturnsNil() {
        #expect(ThemeColor(cssString: "potato") == nil)
    }

    // MARK: - Edge cases

    @Test func emptyStringReturnsNil() {
        #expect(ThemeColor(cssString: "") == nil)
    }

    @Test func whitespaceTrimmed() {
        let color = ThemeColor(cssString: "  #ffffff  ")
        #expect(color?.red == 1.0)
        #expect(color?.green == 1.0)
        #expect(color?.blue == 1.0)
    }

    // MARK: - Legacy port parity

    @Test func legacyHexStringToColor() {
        let color = ThemeColor(cssString: "#123456")
        #expect(color?.red == 0x12 / 255.0)
        #expect(color?.green == 0x34 / 255.0)
        #expect(color?.blue == 0x56 / 255.0)
    }
}
