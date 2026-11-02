import SwiftUI
import UIKit
import Observation

/// Every color the UI uses, for one appearance (light or dark).
/// "accent" replaces the original "gold": `accent` is for text/icons/outlines,
/// `accentFill` for filled shapes, `onAccent` for content placed on `accentFill`.
struct ThemeTokens {
    var background: UIColor
    var backgroundDeep: UIColor
    var tabBar: UIColor
    var surface: UIColor
    var surfaceRaised: UIColor
    var track: UIColor
    var bar: UIColor
    var dayEmpty: UIColor
    var accent: UIColor
    var accentBright: UIColor
    var accentFill: UIColor
    var onAccent: UIColor
    var textPrimary: UIColor
    var textSecondary: UIColor
    var textTertiary: UIColor
    var success: UIColor
    var warning: UIColor
    var danger: UIColor
    var hairline: UIColor
    var cardBorder: UIColor
}

/// A complete theme: a light and a dark variant.
struct ThemePalette {
    var light: ThemeTokens
    var dark: ThemeTokens

    func tokens(for traits: UITraitCollection) -> ThemeTokens {
        traits.userInterfaceStyle == .dark ? dark : light
    }
}

/// The built-in themes plus "Custom".
enum ThemePreset: String, CaseIterable, Identifiable {
    case classic, sage, ocean, terracotta, lavender, rose, graphite, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .sage: return "Sage"
        case .ocean: return "Ocean"
        case .terracotta: return "Terracotta"
        case .lavender: return "Lavender"
        case .rose: return "Rose"
        case .graphite: return "Graphite"
        case .custom: return "Custom"
        }
    }

    var subtitle: String {
        switch self {
        case .classic: return "Navy & gold, from the app icon"
        case .sage: return "Calm greens, soft on the eyes"
        case .ocean: return "Cool blues and teal"
        case .terracotta: return "Warm clay and sand"
        case .lavender: return "Gentle violet"
        case .rose: return "Muted pink and berry"
        case .graphite: return "Neutral greys, blue accent"
        case .custom: return "Your own colours"
        }
    }

    /// Seeds for the generated themes: (background tint, accent, tint strength).
    fileprivate var seeds: (tint: UInt32, accent: UInt32, strength: Double)? {
        switch self {
        case .classic, .custom: return nil
        case .sage: return (0x6F8A68, 0x4F7D43, 0.7)
        case .ocean: return (0x3E6A8E, 0x1A7888, 0.75)
        case .terracotta: return (0xB0806A, 0xB5582F, 0.7)
        case .lavender: return (0x7E70AE, 0x7B5CC9, 0.7)
        case .rose: return (0xAF7C8A, 0xC24F6E, 0.65)
        case .graphite: return (0x6B7280, 0x3B6FD8, 0.25)
        }
    }

    func palette(custom: CustomThemeSettings) -> ThemePalette {
        switch self {
        case .classic:
            return .classic
        case .custom:
            return ThemePalette.generated(tint: custom.tint, accent: custom.accent, strength: custom.strength)
        default:
            return ThemePreset.presetPalettes[self] ?? .classic
        }
    }

    /// Generated once: the built-in palettes never change.
    private static let presetPalettes: [ThemePreset: ThemePalette] = {
        var result: [ThemePreset: ThemePalette] = [:]
        for preset in ThemePreset.allCases {
            guard let seed = preset.seeds else { continue }
            result[preset] = ThemePalette.generated(tint: UIColor(hex: seed.tint), accent: UIColor(hex: seed.accent), strength: seed.strength)
        }
        return result
    }()
}

/// The user's custom theme choices.
struct CustomThemeSettings: Equatable {
    var accent: UIColor
    var tint: UIColor
    /// 0 = almost neutral backgrounds, 1 = clearly tinted.
    var strength: Double

    static let `default` = CustomThemeSettings(accent: UIColor(hex: 0xD4AF37), tint: UIColor(hex: 0x3E5A8A), strength: 0.6)
}

// MARK: - Theme manager

/// Holds the active palette. Views read colors through `Theme.*`, which read
/// `ThemeManager.shared.palette` — SwiftUI's Observation tracking then redraws
/// everything automatically when the theme changes.
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    private enum Keys {
        static let preset = "theme.preset"
        static let customAccent = "theme.custom.accent"
        static let customTint = "theme.custom.tint"
        static let customStrength = "theme.custom.strength"
    }

    private(set) var preset: ThemePreset
    private(set) var custom: CustomThemeSettings
    private(set) var palette: ThemePalette

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let preset = ThemePreset(rawValue: defaults.string(forKey: Keys.preset) ?? "") ?? .classic
        var custom = CustomThemeSettings.default
        if let hex = defaults.string(forKey: Keys.customAccent), let color = UIColor(hexString: hex) { custom.accent = color }
        if let hex = defaults.string(forKey: Keys.customTint), let color = UIColor(hexString: hex) { custom.tint = color }
        if defaults.object(forKey: Keys.customStrength) != nil { custom.strength = defaults.double(forKey: Keys.customStrength) }
        self.preset = preset
        self.custom = custom
        self.palette = preset.palette(custom: custom)
    }

    func select(_ preset: ThemePreset) {
        self.preset = preset
        defaults.set(preset.rawValue, forKey: Keys.preset)
        rebuild()
    }

    /// Updates the custom colors and switches to the Custom theme.
    func updateCustom(_ custom: CustomThemeSettings) {
        self.custom = custom
        defaults.set(custom.accent.hexString, forKey: Keys.customAccent)
        defaults.set(custom.tint.hexString, forKey: Keys.customTint)
        defaults.set(custom.strength, forKey: Keys.customStrength)
        if preset != .custom {
            preset = .custom
            defaults.set(ThemePreset.custom.rawValue, forKey: Keys.preset)
        }
        rebuild()
    }

    private func rebuild() {
        palette = preset.palette(custom: custom)
        Theme.configureAppearance()
        Theme.refreshExistingUIKitViews()
    }
}

// MARK: - Palettes

extension ThemePalette {
    /// The original navy & gold design, hand-tuned.
    static let classic = ThemePalette(
        light: ThemeTokens(
            background: UIColor(hex: 0xF5F2EA), backgroundDeep: UIColor(hex: 0xEDE8DC), tabBar: UIColor(hex: 0xFFFFFF),
            surface: UIColor(hex: 0xFFFFFF), surfaceRaised: UIColor(hex: 0xEEE9DD), track: UIColor(hex: 0xE6E0D2),
            bar: UIColor(hex: 0xAFBDD4), dayEmpty: UIColor(hex: 0xEFEBE1),
            accent: UIColor(hex: 0x7A5C12), accentBright: UIColor(hex: 0x8A6714),
            accentFill: UIColor(hex: 0xD4AF37), onAccent: UIColor(hex: 0x0B1628),
            textPrimary: UIColor(hex: 0x1B2333), textSecondary: UIColor(hex: 0x596273), textTertiary: UIColor(hex: 0x626A7A),
            success: UIColor(hex: 0x27704F), warning: UIColor(hex: 0x86580D), danger: UIColor(hex: 0xA83E1B),
            hairline: UIColor.black.withAlphaComponent(0.08), cardBorder: UIColor.black.withAlphaComponent(0.06)
        ),
        dark: ThemeTokens(
            background: UIColor(hex: 0x0B1628), backgroundDeep: UIColor(hex: 0x060E1B), tabBar: UIColor(hex: 0x0E1B31),
            surface: UIColor(hex: 0x13223A), surfaceRaised: UIColor(hex: 0x1A2B48), track: UIColor(hex: 0x22365A),
            bar: UIColor(hex: 0x2C4470), dayEmpty: UIColor(hex: 0x101D33),
            accent: UIColor(hex: 0xD4AF37), accentBright: UIColor(hex: 0xE8C964),
            accentFill: UIColor(hex: 0xD4AF37), onAccent: UIColor(hex: 0x0B1628),
            textPrimary: UIColor(hex: 0xF3EEDF), textSecondary: UIColor(hex: 0xA9B4C8), textTertiary: UIColor(hex: 0x8C98AE),
            success: UIColor(hex: 0x5FD3A0), warning: UIColor(hex: 0xF2B45A), danger: UIColor(hex: 0xFF8A7A),
            hairline: UIColor.white.withAlphaComponent(0.08), cardBorder: .clear
        )
    )

    /// Builds a full light + dark palette from a background tint and an accent color.
    /// Text and accent colors are adjusted until they meet WCAG AA contrast (4.5:1)
    /// against the surfaces they sit on, so any color choice stays readable.
    static func generated(tint: UIColor, accent: UIColor, strength rawStrength: Double) -> ThemePalette {
        let strength = min(max(rawStrength, 0), 1)
        let t = HSB(tint)
        let a = HSB(accent)

        func tinted(_ saturation: Double, _ brightness: Double) -> UIColor {
            UIColor(hue: t.h, saturation: min(1, saturation * (0.25 + 0.75 * strength) * min(1, t.s * 2.2 + 0.15)), brightness: brightness, alpha: 1)
        }

        // Light
        let lBackground = tinted(0.10, 0.965)
        let lSurface = tinted(0.015, 1.0)
        let lRaised = tinted(0.08, 0.935)
        let lightTextBase = tinted(0.45, 0.20)
        let lText2 = Contrast.adjust(tinted(0.25, 0.42), against: [lSurface, lRaised, lBackground], minimum: 4.6, darken: true)
        let lText3 = Contrast.adjust(tinted(0.18, 0.47), against: [lSurface, lRaised, lBackground], minimum: 4.5, darken: true)
        let lAccentFill = accent
        let lAccent = Contrast.adjust(UIColor(hue: a.h, saturation: min(1, a.s * 1.05), brightness: a.b, alpha: 1),
                                      against: [lSurface, lRaised, lBackground, lAccentFill.withAlphaComponent(1).blended(over: lBackground, alpha: 0.12)],
                                      minimum: 4.6, darken: true)
        let light = ThemeTokens(
            background: lBackground,
            backgroundDeep: tinted(0.14, 0.93),
            tabBar: lSurface,
            surface: lSurface,
            surfaceRaised: lRaised,
            track: tinted(0.12, 0.89),
            bar: tinted(0.30, 0.80),
            dayEmpty: tinted(0.07, 0.945),
            accent: lAccent,
            accentBright: lAccent,
            accentFill: lAccentFill,
            onAccent: Contrast.bestOn(lAccentFill, dark: lightTextBase),
            textPrimary: Contrast.adjust(lightTextBase, against: [lSurface, lRaised, lBackground], minimum: 10, darken: true),
            textSecondary: lText2,
            textTertiary: lText3,
            success: UIColor(hex: 0x27704F), warning: UIColor(hex: 0x86580D), danger: UIColor(hex: 0xA83E1B),
            hairline: UIColor.black.withAlphaComponent(0.08),
            cardBorder: UIColor.black.withAlphaComponent(0.06)
        )

        // Dark
        func deep(_ saturation: Double, _ brightness: Double) -> UIColor {
            UIColor(hue: t.h, saturation: min(1, saturation * (0.3 + 0.7 * strength) * min(1, t.s * 2 + 0.2)), brightness: brightness, alpha: 1)
        }
        let dBackground = deep(0.62, 0.15)
        let dSurface = deep(0.55, 0.21)
        let dRaised = deep(0.50, 0.27)
        let darkTextBase = deep(0.08, 0.95)
        let dAccentFill = Contrast.adjust(accent, against: [dBackground], minimum: 3.2, darken: false)
        let dAccent = Contrast.adjust(UIColor(hue: a.h, saturation: a.s * 0.9, brightness: max(a.b, 0.75), alpha: 1),
                                      against: [dSurface, dRaised, dBackground], minimum: 4.6, darken: false)
        let dark = ThemeTokens(
            background: dBackground,
            backgroundDeep: deep(0.66, 0.10),
            tabBar: deep(0.6, 0.18),
            surface: dSurface,
            surfaceRaised: dRaised,
            track: deep(0.45, 0.33),
            bar: deep(0.42, 0.42),
            dayEmpty: deep(0.6, 0.18),
            accent: dAccent,
            accentBright: Contrast.adjust(dAccent, against: [dRaised], minimum: 6, darken: false),
            accentFill: dAccentFill,
            onAccent: Contrast.bestOn(dAccentFill, dark: dBackground),
            textPrimary: Contrast.adjust(darkTextBase, against: [dSurface, dRaised], minimum: 10, darken: false),
            textSecondary: Contrast.adjust(deep(0.18, 0.76), against: [dSurface, dRaised, dBackground], minimum: 4.8, darken: false),
            textTertiary: Contrast.adjust(deep(0.14, 0.64), against: [dSurface, dRaised, dBackground], minimum: 4.5, darken: false),
            success: UIColor(hex: 0x5FD3A0), warning: UIColor(hex: 0xF2B45A), danger: UIColor(hex: 0xFF8A7A),
            hairline: UIColor.white.withAlphaComponent(0.08),
            cardBorder: .clear
        )
        return ThemePalette(light: light, dark: dark)
    }
}

// MARK: - Color math

private struct HSB {
    var h: Double, s: Double, b: Double
    init(_ color: UIColor) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if !color.getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
            var white: CGFloat = 0
            color.getWhite(&white, alpha: &a)
            h = 0; s = 0; b = white
        }
        self.h = Double(h); self.s = Double(s); self.b = Double(b)
    }
}

enum Contrast {
    static func luminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ c: CGFloat) -> Double {
            let v = Double(min(max(c, 0), 1))
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    static func ratio(_ a: UIColor, _ b: UIColor) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Darkens (or lightens) `color` in small steps until it reaches `minimum`
    /// contrast against every background in `backgrounds`.
    static func adjust(_ color: UIColor, against backgrounds: [UIColor], minimum: Double, darken: Bool) -> UIColor {
        var hsb = HSB(color)
        var candidate = color
        for _ in 0..<60 {
            if backgrounds.allSatisfy({ ratio(candidate, $0) >= minimum }) { return candidate }
            if darken {
                hsb.b = max(0, hsb.b - 0.02)
            } else {
                hsb.b = min(1, hsb.b + 0.02)
                if hsb.b >= 1 { hsb.s = max(0, hsb.s - 0.04) }
            }
            candidate = UIColor(hue: hsb.h, saturation: hsb.s, brightness: hsb.b, alpha: 1)
        }
        return candidate
    }

    /// Picks whichever of a dark color or white reads better on `fill`.
    static func bestOn(_ fill: UIColor, dark: UIColor) -> UIColor {
        ratio(dark, fill) >= ratio(.white, fill) ? dark : .white
    }
}

extension UIColor {
    /// "#D4AF37"
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    convenience init?(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        self.init(hex: value)
    }

    /// This color laid over `background` at `alpha`.
    func blended(over background: UIColor, alpha: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        background.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 * alpha + r2 * (1 - alpha), green: g1 * alpha + g2 * (1 - alpha), blue: b1 * alpha + b2 * (1 - alpha), alpha: 1)
    }
}
