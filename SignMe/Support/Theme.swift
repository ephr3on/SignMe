import SwiftUI
import UIKit

/// The user's appearance choice in Settings. Light is the default.
enum AppTheme: String, CaseIterable, Identifiable {
    case light, dark, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }

    /// nil = follow the iPhone's own setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

/// SignMe's visual language, taken from the app icon, in two variants:
/// - Light (default): warm off-white paper, white cards, navy ink, deep-gold accents.
/// - Dark: deep navy surfaces with bright gold accents.
/// Every token adapts automatically to the active appearance.
enum Theme {
    // MARK: Colors

    static let background = adaptive(light: 0xF5F2EA, dark: 0x0B1628)
    static let backgroundDeep = adaptive(light: 0xEDE8DC, dark: 0x060E1B)
    static let tabBar = adaptive(light: 0xFFFFFF, dark: 0x0E1B31)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x13223A)
    static let surfaceRaised = adaptive(light: 0xEEE9DD, dark: 0x1A2B48)
    static let track = adaptive(light: 0xE6E0D2, dark: 0x22365A)
    static let bar = adaptive(light: 0xAFBDD4, dark: 0x2C4470)
    /// Empty calendar days.
    static let dayEmpty = adaptive(light: 0xEFEBE1, dark: 0x101D33)
    /// Gold for text, icons and outlines (darker in light mode so it stays readable).
    static let gold = adaptive(light: 0x7A5C12, dark: 0xD4AF37)
    static let goldBright = adaptive(light: 0x8A6714, dark: 0xE8C964)
    /// Gold for filled shapes: buttons, the + button, selected chips, chart highlights.
    static let goldFill = Color(hex: 0xD4AF37)
    /// Text and icons placed on `goldFill`.
    static let onGold = Color(hex: 0x0B1628)
    static let textPrimary = adaptive(light: 0x1B2333, dark: 0xF3EEDF)
    static let textSecondary = adaptive(light: 0x596273, dark: 0xA9B4C8)
    static let textTertiary = adaptive(light: 0x626A7A, dark: 0x8C98AE)
    static let success = adaptive(light: 0x27704F, dark: 0x5FD3A0)
    static let warning = adaptive(light: 0x86580D, dark: 0xF2B45A)
    static let danger = adaptive(light: 0xA83E1B, dark: 0xFF8A7A)
    static let paper = Color(hex: 0xFBF8F1)
    static let paperLine = Color(hex: 0xB9B09C)
    static let hairline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.08) : UIColor.black.withAlphaComponent(0.08)
    })
    /// Thin outline around cards — only visible in light mode, where white cards sit on off-white.
    static let cardBorder = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .clear : UIColor.black.withAlphaComponent(0.06)
    })

    /// Ink used for drawn signatures (dark blue, like a ballpoint pen).
    static let inkUIColor = UIColor(red: 0x1B / 255, green: 0x2B / 255, blue: 0x6B / 255, alpha: 1)

    /// A color that switches between a light-mode and a dark-mode hex value.
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: adaptiveUIColor(light: light, dark: dark))
    }

    private static func adaptiveUIColor(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        }
    }

    // MARK: Type

    /// Serif display type for titles (Apple's "New York").
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    static let sectionLabel = Font.system(.caption, weight: .semibold)

    // MARK: UIKit appearance

    /// Navigation bars and segmented controls in the theme colors (adapting to light/dark).
    /// Called once at launch.
    static func configureAppearance() {
        let backgroundUI = adaptiveUIColor(light: 0xF5F2EA, dark: 0x0B1628)
        let textPrimaryUI = adaptiveUIColor(light: 0x1B2333, dark: 0xF3EEDF)
        let textSecondaryUI = adaptiveUIColor(light: 0x596273, dark: 0xA9B4C8)
        let goldUI = adaptiveUIColor(light: 0x7A5C12, dark: 0xD4AF37)

        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = backgroundUI
        navigation.shadowColor = .clear
        navigation.largeTitleTextAttributes = [
            .foregroundColor: textPrimaryUI,
            .font: serifFont(size: 32, weight: .semibold)
        ]
        navigation.titleTextAttributes = [
            .foregroundColor: textPrimaryUI,
            .font: serifFont(size: 17, weight: .semibold)
        ]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().tintColor = goldUI

        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = adaptiveUIColor(light: 0xFFFFFF, dark: 0x22365A)
        segmented.backgroundColor = adaptiveUIColor(light: 0xE6E0D2, dark: 0x13223A)
        segmented.setTitleTextAttributes([.foregroundColor: textSecondaryUI], for: .normal)
        segmented.setTitleTextAttributes([.foregroundColor: textPrimaryUI], for: .selected)
    }

    private static func serifFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Reusable building blocks

/// Small uppercase label above a group of controls, e.g. "TIME".
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.sectionLabel)
            .tracking(1.2)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CardModifier: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat
    var highlighted: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(highlighted ? Theme.gold.opacity(0.45) : Theme.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    /// A navy surface card with rounded corners.
    func card(padding: CGFloat = 16, radius: CGFloat = 20, highlighted: Bool = false) -> some View {
        modifier(CardModifier(padding: padding, radius: radius, highlighted: highlighted))
    }

    /// Navy background for a whole screen, including Lists and Forms.
    func themedScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }

    /// Row background for List/Form rows on a themed screen.
    func themedRow() -> some View {
        listRowBackground(Theme.surface)
    }
}

/// Filled gold button — the primary action on a screen.
struct GoldButtonStyle: ButtonStyle {
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        GoldButtonBody(configuration: configuration, height: height)
    }

    private struct GoldButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let height: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(Theme.onGold.opacity(isEnabled ? 1 : 0.6))
                .frame(maxWidth: .infinity, minHeight: height)
                .background(
                    Theme.goldFill.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// Outlined secondary button.
struct OutlineButtonStyle: ButtonStyle {
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(configuration.isPressed ? Theme.surfaceRaised : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.2), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A pill-shaped choice, filled gold when selected (day, break and similar pickers).
struct ChoiceChip: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.footnote.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(isSelected ? .bold : .semibold))
            }
            .foregroundStyle(isSelected ? Theme.onGold : Theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(
                Capsule().fill(isSelected ? Theme.goldFill : Color.clear)
            )
            .overlay(
                Capsule().strokeBorder(isSelected ? Color.clear : Theme.textPrimary.opacity(0.22), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A gold progress ring with a centered label.
struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 9
    var label: String

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Theme.goldFill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((min(max(progress, 0), 1) * 100).rounded())) percent of monthly target")
    }
}
