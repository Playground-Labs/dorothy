import XCTest
import DorothyCore

final class ThemeTests: XCTestCase {
    func testStoredAppearanceParsing() {
        XCTAssertEqual(Appearance(stored: nil), .light)
        XCTAssertEqual(Appearance(stored: "bogus"), .light)
        XCTAssertEqual(Appearance(stored: "dark"), .dark)
        XCTAssertEqual(Appearance(stored: "system"), .system)
        XCTAssertEqual(Appearance(stored: "light"), .light)
        XCTAssertEqual(Appearance.defaultsKey, "appearance")
    }

    func testAllCasesOrderAndLabels() {
        XCTAssertEqual(Appearance.allCases, [.system, .light, .dark])
        XCTAssertEqual(Appearance.allCases.map(\.label), ["System", "Light", "Dark"])
    }

    func testIsDarkResolution() {
        XCTAssertTrue(Appearance.dark.isDark(systemDark: false))
        XCTAssertTrue(Appearance.dark.isDark(systemDark: true))
        XCTAssertFalse(Appearance.light.isDark(systemDark: false))
        XCTAssertFalse(Appearance.light.isDark(systemDark: true))
        XCTAssertTrue(Appearance.system.isDark(systemDark: true))
        XCTAssertFalse(Appearance.system.isDark(systemDark: false))
    }

    func testLightPaletteMatchesOriginalColors() {
        XCTAssertEqual(Palette.light.paper, "#FFFFFF")
        XCTAssertEqual(Palette.light.line, "#111111")
        XCTAssertEqual(Palette.light.doneBG, "#F2F2F2")
        XCTAssertEqual(Palette.light.yellow, "#FFD60A")
    }

    func testDarkPaletteInvertsSurfacesKeepsAccents() {
        let l = Palette.light, d = Palette.dark
        XCTAssertNotEqual(d.paper, l.paper)
        XCTAssertNotEqual(d.line, l.line)
        XCTAssertEqual([d.yellow, d.pink, d.orange, d.cobalt, d.mint], [l.yellow, l.pink, l.orange, l.cobalt, l.mint])
        XCTAssertEqual(d.onAccent, "#111111")
        XCTAssertEqual(Palette.forDark(true), .dark)
        XCTAssertEqual(Palette.forDark(false), .light)
    }

    func testContrast() {
        for p in [Palette.light, .dark] {
            XCTAssertGreaterThanOrEqual(contrast(p.line, p.paper), 4.5)
            XCTAssertGreaterThanOrEqual(contrast(p.muted, p.paper), 4.5)
            XCTAssertGreaterThanOrEqual(contrast(p.onAccent, p.yellow), 4.5)
            XCTAssertGreaterThanOrEqual(contrast(p.line, p.ground), 4.5)
        }
        // Selected labels (onInk): yellow on black in light, dark ink on yellow in dark.
        XCTAssertGreaterThanOrEqual(contrast(Palette.light.yellow, Palette.light.inkFill), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(Palette.dark.onAccent, Palette.dark.inkFill), 4.5)
    }

    func testDarkShadowsStayDarkerThanSurfaces() {
        let d = Palette.dark
        XCTAssertNotEqual(d.shadow, d.line)
        XCTAssertLessThan(luminance(d.shadow), luminance(d.ground))
        XCTAssertLessThan(luminance(d.ground), luminance(d.paper))
    }

    private func luminance(_ hex: String) -> Double {
        let v = UInt32(hex.dropFirst(), radix: 16)!
        let c = [v >> 16 & 255, v >> 8 & 255, v & 255].map { ch -> Double in
            let s = Double(ch) / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    }

    private func contrast(_ a: String, _ b: String) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
