import SwiftUI
import UIKit

/// SignMe's navy & gold visual language, taken from the app icon.
/// Every screen uses these tokens instead of system colors so the look stays consistent.
enum Theme {
    // MARK: Colors

    static let background = Color(hex: 0x0B1628)
    static let backgroundDeep = Color(hex: 0x060E1B)
    static let tabBar = Color(hex: 0x0E1B31)
    static let surface = Color(hex: 0x13223A)
    static let surfaceRaised = Color(hex: 0x1A2B48)
    static let track = Color(hex: 0x22365A)
    static let bar = Color(hex: 0x2C4470)
    static let gold = Color(hex: 0xD4AF37)
    static let goldBright = Color(hex: 0xE8C964)
    static let textPrimary = Color(hex: 0xF3EEDF)
    static let textSecondary = Color(hex: 0xA9B4C8)
    static let textTertiary = Color(hex: 0x8C98AE)
    static let success = Color(hex: 0x5FD3A0)
    static let warning = Color(hex: 0xF2B45A)
    static let danger = Color(hex: 0xFF8A7A)
    static let paper = Color(hex: 0xFBF8F1)
    static let paperLine = Color(hex: 0xB9B09C)
    static let hairline = Color.white.opacity(0.08)

    /// Ink used for drawn signatures (dark blue, like a ballpoint pen).
    static let inkUIColor = UIColor(red: 0x1B / 255, green: 0x2B / 255, blue: 0x6B / 255, alpha: 1)

    // MARK: Type

    /// Serif display type for titles (Apple's "New York").
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    static let sectionLabel = Font.system(.caption, weight: .semibold)

    // MARK: UIKit appearance

    /// Navigation bars and segmented controls in navy & gold. Called once at launch.
    static func configureAppearance() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = UIColor(background)
        navigation.shadowColor = .clear
        navigation.largeTitleTextAttributes = [
            .foregroundColor: UIColor(textPrimary),
            .font: serifFont(size: 32, weight: .semibold)
        ]
        navigation.titleTextAttributes = [
            .foregroundColor: UIColor(textPrimary),
            .font: serifFont(size: 17, weight: .semibold)
        ]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().tintColor = UIColor(gold)

        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = UIColor(track)
        segmented.backgroundColor = UIColor(surface)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(textSecondary)], for: .normal)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(textPrimary)], for: .selected)
    }

    private static func serifFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
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
                    .strokeBorder(highlighted ? Theme.gold.opacity(0.45) : Color.clear, lineWidth: 1)
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
                .foregroundStyle(Theme.background)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(
                    Theme.gold.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35),
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
            .foregroundStyle(isSelected ? Theme.background : Theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(
                Capsule().fill(isSelected ? Theme.gold : Color.clear)
            )
            .overlay(
                Capsule().strokeBorder(isSelected ? Color.clear : Theme.textPrimary.opacity(0.18), lineWidth: 1)
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
                .stroke(Theme.gold, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
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
