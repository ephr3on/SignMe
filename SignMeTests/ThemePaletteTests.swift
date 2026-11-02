import XCTest
import UIKit
@testable import SignMe

final class ThemePaletteTests: XCTestCase {

    private func assertReadable(_ palette: ThemePalette, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        for (mode, t) in [("light", palette.light), ("dark", palette.dark)] {
            for surface in [t.background, t.surface, t.surfaceRaised] {
                XCTAssertGreaterThanOrEqual(Contrast.ratio(t.textPrimary, surface), 7, "\(name) \(mode) primary text", file: file, line: line)
                XCTAssertGreaterThanOrEqual(Contrast.ratio(t.textSecondary, surface), 4.5, "\(name) \(mode) secondary text", file: file, line: line)
                XCTAssertGreaterThanOrEqual(Contrast.ratio(t.accent, surface), 4.5, "\(name) \(mode) accent text", file: file, line: line)
            }
            XCTAssertGreaterThanOrEqual(Contrast.ratio(t.onAccent, t.accentFill), 3, "\(name) \(mode) button label", file: file, line: line)
        }
    }

    func testEveryBuiltInThemeIsReadable() {
        for preset in ThemePreset.allCases {
            assertReadable(preset.palette(custom: .default), preset.title)
        }
    }

    func testExtremeCustomColorsStayReadable() {
        let extremes: [(UInt32, UInt32, Double)] = [
            (0xFFFFFF, 0xFFEE00, 1.0),   // white tint, bright yellow accent
            (0x000000, 0x000000, 1.0),   // black everything
            (0xFF0000, 0x00FF00, 1.0),   // saturated red / green
            (0x808080, 0x808080, 0.0)    // flat grey
        ]
        for (tint, accent, strength) in extremes {
            let palette = ThemePalette.generated(tint: UIColor(hex: tint), accent: UIColor(hex: accent), strength: strength)
            assertReadable(palette, "custom \(UIColor(hex: tint).hexString)/\(UIColor(hex: accent).hexString)")
        }
    }

    func testHexRoundTrip() {
        XCTAssertEqual(UIColor(hex: 0xD4AF37).hexString, "#D4AF37")
        XCTAssertEqual(UIColor(hexString: "#1B2333")?.hexString, "#1B2333")
        XCTAssertNil(UIColor(hexString: "nope"))
    }

    func testCustomSettingsPersist() {
        let suite = "SignMeTests.Theme"
        UserDefaults().removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite)!
        let manager = ThemeManager(defaults: defaults)
        XCTAssertEqual(manager.preset, .classic)

        manager.updateCustom(CustomThemeSettings(accent: UIColor(hex: 0xC2643A), tint: UIColor(hex: 0x6F8A68), strength: 0.3))
        let reloaded = ThemeManager(defaults: defaults)
        XCTAssertEqual(reloaded.preset, .custom)
        XCTAssertEqual(reloaded.custom.accent.hexString, "#C2643A")
        XCTAssertEqual(reloaded.custom.tint.hexString, "#6F8A68")
        XCTAssertEqual(reloaded.custom.strength, 0.3, accuracy: 0.0001)
        UserDefaults().removePersistentDomain(forName: suite)
    }
}
