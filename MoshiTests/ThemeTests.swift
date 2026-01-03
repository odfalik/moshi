import XCTest
import SwiftUI
@testable import Moshi

final class ThemeTests: XCTestCase {

    // MARK: - Theme Color Tests

    func testThemeColorFromHex6() {
        let color = ThemeColor(hex: "#FF5500")

        XCTAssertEqual(color.red, 1.0, accuracy: 0.01)
        XCTAssertEqual(color.green, 85.0/255.0, accuracy: 0.01)
        XCTAssertEqual(color.blue, 0.0, accuracy: 0.01)
        XCTAssertEqual(color.alpha, 1.0, accuracy: 0.01)
    }

    func testThemeColorFromHex8() {
        let color = ThemeColor(hex: "#FF550080")

        XCTAssertEqual(color.red, 1.0, accuracy: 0.01)
        XCTAssertEqual(color.green, 85.0/255.0, accuracy: 0.01)
        XCTAssertEqual(color.blue, 0.0, accuracy: 0.01)
        XCTAssertEqual(color.alpha, 128.0/255.0, accuracy: 0.01)
    }

    func testThemeColorToSwiftUI() {
        let themeColor = ThemeColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0)
        let color = themeColor.color

        XCTAssertNotNil(color)
    }

    func testThemeColorToUIColor() {
        let themeColor = ThemeColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        let uiColor = themeColor.uiColor

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        XCTAssertEqual(r, 0.5, accuracy: 0.01)
        XCTAssertEqual(g, 0.5, accuracy: 0.01)
        XCTAssertEqual(b, 0.5, accuracy: 0.01)
        XCTAssertEqual(a, 1.0, accuracy: 0.01)
    }

    // MARK: - Terminal Theme Tests

    func testBuiltInThemesNotEmpty() {
        XCTAssertFalse(TerminalTheme.allThemes.isEmpty)
    }

    func testSolarizedDarkTheme() {
        let theme = TerminalTheme.solarizedDark

        XCTAssertEqual(theme.name, "Solarized Dark")
        XCTAssertEqual(theme.palette.count, 16)
    }

    func testDraculaTheme() {
        let theme = TerminalTheme.dracula

        XCTAssertEqual(theme.name, "Dracula")
        XCTAssertEqual(theme.palette.count, 16)
    }

    func testNordTheme() {
        let theme = TerminalTheme.nord

        XCTAssertEqual(theme.name, "Nord")
        XCTAssertEqual(theme.palette.count, 16)
    }

    func testTokyoNightTheme() {
        let theme = TerminalTheme.tokyoNight

        XCTAssertEqual(theme.name, "Tokyo Night")
        XCTAssertEqual(theme.palette.count, 16)
    }

    func testGruvboxDarkTheme() {
        let theme = TerminalTheme.gruvboxDark

        XCTAssertEqual(theme.name, "Gruvbox Dark")
        XCTAssertEqual(theme.palette.count, 16)
    }

    func testMonokaiTheme() {
        let theme = TerminalTheme.monokai

        XCTAssertEqual(theme.name, "Monokai Pro")
        XCTAssertEqual(theme.palette.count, 16)
    }

    // MARK: - Theme Color Index Tests

    func testColorForIndexValid() {
        let theme = TerminalTheme.dracula

        let color0 = theme.colorForIndex(0)
        let color7 = theme.colorForIndex(7)
        let color15 = theme.colorForIndex(15)

        XCTAssertNotNil(color0)
        XCTAssertNotNil(color7)
        XCTAssertNotNil(color15)
    }

    func testColorForIndexInvalid() {
        let theme = TerminalTheme.dracula

        // Out of range should return foreground color
        let color = theme.colorForIndex(100)
        XCTAssertNotNil(color)
    }

    func testColorForIndexNegative() {
        let theme = TerminalTheme.dracula

        let color = theme.colorForIndex(-1)
        XCTAssertNotNil(color) // Should return foreground
    }

    // MARK: - Theme Encoding/Decoding Tests

    func testThemeEncodingDecoding() throws {
        let original = TerminalTheme.dracula

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TerminalTheme.self, from: data)

        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.palette.count, original.palette.count)
    }

    // MARK: - Terminal Font Tests

    func testTerminalFontDefault() {
        let font = TerminalFont()

        XCTAssertEqual(font.name, "Menlo")
        XCTAssertEqual(font.size, 14)
    }

    func testTerminalFontCustom() {
        let font = TerminalFont(name: "Monaco", size: 16)

        XCTAssertEqual(font.name, "Monaco")
        XCTAssertEqual(font.size, 16)
    }

    func testTerminalFontAvailable() {
        XCTAssertFalse(TerminalFont.availableFonts.isEmpty)
        XCTAssertTrue(TerminalFont.availableFonts.contains("Menlo"))
    }

    func testTerminalFontUIFont() {
        let font = TerminalFont(name: "Menlo", size: 14)
        let uiFont = font.uiFont

        XCTAssertEqual(uiFont.pointSize, 14)
    }

    func testTerminalFontEncodingDecoding() throws {
        let original = TerminalFont(name: "Monaco", size: 18)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TerminalFont.self, from: data)

        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.size, original.size)
    }

    // MARK: - Theme Equatable Tests

    func testThemeEquatable() {
        let theme1 = TerminalTheme.dracula
        let theme2 = TerminalTheme.dracula
        let theme3 = TerminalTheme.nord

        XCTAssertEqual(theme1, theme2)
        XCTAssertNotEqual(theme1, theme3)
    }

    func testThemeColorEquatable() {
        let color1 = ThemeColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0)
        let color2 = ThemeColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0)
        let color3 = ThemeColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)

        XCTAssertEqual(color1, color2)
        XCTAssertNotEqual(color1, color3)
    }
}
