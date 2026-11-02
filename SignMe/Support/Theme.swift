import SwiftUI
import UIKit
import CoreText

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

/// SignMe's design tokens. Colors come from the active `ThemePalette`
/// (chosen in Settings › Appearance › Theme) and adapt automatically to light/dark.
/// Because each accessor reads `ThemeManager.shared.palette`, SwiftUI's Observation
/// redraws every view that uses a color as soon as the theme changes.
///
/// Naming: `gold` = the theme's accent (it was gold in the original design).
enum Theme {
    // MARK: Colors

    static var background: Color { color(\.background) }
    static var backgroundDeep: Color { color(\.backgroundDeep) }
    static var tabBar: Color { color(\.tabBar) }
    static var surface: Color { color(\.surface) }
    static var surfaceRaised: Color { color(\.surfaceRaised) }
    static var track: Color { color(\.track) }
    static var bar: Color { color(\.bar) }
    /// Empty calendar days.
    static var dayEmpty: Color { color(\.dayEmpty) }
    /// Accent for text, icons and outlines (readable on every surface).
    static var gold: Color { color(\.accent) }
    static var goldBright: Color { color(\.accentBright) }
    /// Accent for filled shapes: buttons, the + button, selected chips, chart highlights.
    static var goldFill: Color { color(\.accentFill) }
    /// Text and icons placed on `goldFill`.
    static var onGold: Color { color(\.onAccent) }
    static var textPrimary: Color { color(\.textPrimary) }
    static var textSecondary: Color { color(\.textSecondary) }
    static var textTertiary: Color { color(\.textTertiary) }
    static var success: Color { color(\.success) }
    static var warning: Color { color(\.warning) }
    static var danger: Color { color(\.danger) }
    static var hairline: Color { color(\.hairline) }
    /// Thin outline around cards — only visible in light mode, where white cards sit on tinted backgrounds.
    static var cardBorder: Color { color(\.cardBorder) }

    /// Signatures and the PDF preview always sit on paper, whatever the theme.
    static let paper = Color(hex: 0xFBF8F1)
    static let paperLine = Color(hex: 0xB9B09C)

    /// Ink used for drawn signatures (dark blue, like a ballpoint pen).
    static let inkUIColor = UIColor(red: 0x1B / 255, green: 0x2B / 255, blue: 0x6B / 255, alpha: 1)

    /// A SwiftUI color for one token of the active palette, switching with light/dark.
    static func color(_ token: KeyPath<ThemeTokens, UIColor>) -> Color {
        Color(uiColor: uiColor(token))
    }

    /// The UIKit version (reads the palette now, so Observation tracks it in SwiftUI bodies).
    static func uiColor(_ token: KeyPath<ThemeTokens, UIColor>) -> UIColor {
        let palette = ThemeManager.shared.palette
        return UIColor { traits in palette.tokens(for: traits)[keyPath: token] }
    }

    // MARK: Type

    /// Serif display type for titles (Source Serif 4).
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .display(style, weight == .bold || weight == .heavy || weight == .black ? .bold : .semibold)
    }

    static let sectionLabel = Font.app(.caption, .bold)

    // MARK: UIKit appearance

    /// Selected segment: white in light mode, a raised surface in dark mode.
    private static var segmentSelectedColor: UIColor {
        let palette = ThemeManager.shared.palette
        return UIColor { traits in
            traits.userInterfaceStyle == .dark ? palette.dark.surfaceRaised : palette.light.surface
        }
    }

    /// Navigation bars and segmented controls in the theme colors (adapting to light/dark).
    /// Called at launch and again whenever the theme changes.
    static func configureAppearance() {
        let backgroundUI = uiColor(\.background)
        let textPrimaryUI = uiColor(\.textPrimary)
        let textSecondaryUI = uiColor(\.textSecondary)
        let goldUI = uiColor(\.accent)

        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = backgroundUI
        navigation.shadowColor = .clear
        navigation.largeTitleTextAttributes = [
            .foregroundColor: textPrimaryUI,
            .font: AppFonts.uiFont(AppFonts.serifSemiBold, size: 32, textStyle: .largeTitle)
        ]
        navigation.titleTextAttributes = [
            .foregroundColor: textPrimaryUI,
            .font: AppFonts.uiFont(AppFonts.serifSemiBold, size: 18, textStyle: .headline)
        ]
        let barButtonFont = AppFonts.uiFont(AppFonts.sans(.semibold), size: 17, textStyle: .body)
        let buttonAppearance = UIBarButtonItemAppearance()
        buttonAppearance.normal.titleTextAttributes = [.font: barButtonFont]
        navigation.buttonAppearance = buttonAppearance
        navigation.doneButtonAppearance = buttonAppearance
        navigation.backButtonAppearance = buttonAppearance

        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().tintColor = goldUI

        // The app draws its own tab bar (see AppTabBar); keep the system one hidden everywhere.
        UITabBar.appearance().isHidden = true

        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = segmentSelectedColor
        segmented.backgroundColor = uiColor(\.track)
        segmented.setTitleTextAttributes([
            .foregroundColor: textSecondaryUI,
            .font: AppFonts.uiFont(AppFonts.sans(.medium), size: 14, textStyle: .subheadline)
        ], for: .normal)
        segmented.setTitleTextAttributes([
            .foregroundColor: textPrimaryUI,
            .font: AppFonts.uiFont(AppFonts.sans(.bold), size: 14, textStyle: .subheadline)
        ], for: .selected)
    }

    /// Appearance proxies only affect views created later, so after a theme change
    /// re-style the navigation bars and segmented controls that are already on screen.
    static func refreshExistingUIKitViews() {
        let navigationProxy = UINavigationBar.appearance()
        let segmentedProxy = UISegmentedControl.appearance()
        let normalAttributes = segmentedProxy.titleTextAttributes(for: .normal)
        let selectedAttributes = segmentedProxy.titleTextAttributes(for: .selected)

        func visit(_ view: UIView) {
            if let bar = view as? UINavigationBar {
                bar.standardAppearance = navigationProxy.standardAppearance
                bar.scrollEdgeAppearance = navigationProxy.scrollEdgeAppearance
                bar.compactAppearance = navigationProxy.compactAppearance
                bar.tintColor = navigationProxy.tintColor
            } else if let control = view as? UISegmentedControl {
                control.selectedSegmentTintColor = segmentedProxy.selectedSegmentTintColor
                control.backgroundColor = segmentedProxy.backgroundColor
                control.setTitleTextAttributes(normalAttributes, for: .normal)
                control.setTitleTextAttributes(selectedAttributes, for: .selected)
            }
            view.subviews.forEach(visit)
        }

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                visit(window)
                window.tintColor = uiColor(\.accent)
            }
        }
    }
}

// MARK: - Fonts

/// Weights available in the bundled UI font.
enum AppWeight {
    case regular, medium, semibold, bold

    init(_ weight: Font.Weight) {
        switch weight {
        case .ultraLight, .thin, .light, .regular: self = .regular
        case .medium: self = .medium
        case .semibold: self = .semibold
        default: self = .bold
        }
    }
}

/// The app's two bundled typefaces (SIL Open Font License, files in Resources/Fonts):
/// - Plus Jakarta Sans — friendly, very legible UI text with tabular figures.
/// - Source Serif 4 — calm serif for titles.
/// Every size scales with the user's Dynamic Type setting.
enum AppFonts {
    static let serifSemiBold = "SourceSerif4-SemiBold"
    static let serifBold = "SourceSerif4-Bold"

    static func sans(_ weight: AppWeight) -> String {
        switch weight {
        case .regular: return "PlusJakartaSans-Regular"
        case .medium: return "PlusJakartaSans-Medium"
        case .semibold: return "PlusJakartaSans-SemiBold"
        case .bold: return "PlusJakartaSans-Bold"
        }
    }

    /// Base point sizes at the default text size (close to Apple's, a touch larger
    /// for the smallest styles so small labels stay comfortable to read).
    static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline: return 17
        case .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13.5
        case .caption: return 12.5
        case .caption2: return 11.5
        @unknown default: return 17
        }
    }

    /// Registers the bundled font files with the system. Call once, before any UI is built.
    static func register() {
        let names = ["PlusJakartaSans-Regular", "PlusJakartaSans-Medium", "PlusJakartaSans-SemiBold",
                     "PlusJakartaSans-Bold", "SourceSerif4-SemiBold", "SourceSerif4-Bold"]
        for name in names {
            guard UIFont(name: name, size: 12) == nil,
                  let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// A UIKit font that follows Dynamic Type, falling back to the system font.
    static func uiFont(_ name: String, size: CGFloat, textStyle: UIFont.TextStyle) -> UIFont {
        let base = UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: name.contains("Bold") ? .bold : .regular)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
    }
}

extension Font {
    /// UI text in Plus Jakarta Sans. Headlines default to semibold, everything else to regular.
    static func app(_ style: Font.TextStyle, _ weight: AppWeight? = nil) -> Font {
        let resolved = weight ?? (style == .headline ? .semibold : .regular)
        return .custom(AppFonts.sans(resolved), size: AppFonts.baseSize(style), relativeTo: style)
    }

    /// UI text at a specific size (still scales with Dynamic Type relative to `relativeTo`).
    static func appSize(_ size: CGFloat, _ weight: AppWeight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(AppFonts.sans(weight), size: size, relativeTo: style)
    }

    /// Titles in Source Serif 4.
    static func display(_ style: Font.TextStyle, _ weight: AppWeight = .semibold) -> Font {
        let name = weight == .bold ? AppFonts.serifBold : AppFonts.serifSemiBold
        return .custom(name, size: AppFonts.baseSize(style), relativeTo: style)
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
                .font(.app(.headline, .bold))
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
            .font(.app(.headline, .bold))
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
                    Image(systemName: systemImage).font(.app(.footnote, .semibold))
                }
                Text(title)
                    .font(.app(.subheadline, isSelected ? .bold : .semibold))
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
                .font(.app(.subheadline, .bold))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((min(max(progress, 0), 1) * 100).rounded())) percent of monthly target")
    }
}
