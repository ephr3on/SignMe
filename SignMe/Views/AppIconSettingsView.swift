import SwiftUI
import UIKit

/// The app icons you can choose: the same Eye of Horus (a clock for an iris)
/// in each theme's colours plus a few Egyptian extras.
/// Classic is the primary icon; the others are alternate icons in the asset
/// catalog ("AppIcon-<Name>"), with small previews in "IconPreview-<Name>".
enum AppIconChoice: String, CaseIterable, Identifiable {
    case classic, ivory, lapis, papyrus, sage, ocean, terracotta, lavender, rose, graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .ivory: "Ivory"
        case .lapis: "Lapis"
        case .papyrus: "Papyrus"
        case .sage: "Sage"
        case .ocean: "Ocean"
        case .terracotta: "Terracotta"
        case .lavender: "Lavender"
        case .rose: "Rose"
        case .graphite: "Graphite"
        }
    }

    /// Name of the alternate icon set; nil for the primary icon.
    var alternateName: String? {
        self == .classic ? nil : "AppIcon-\(title)"
    }

    var previewName: String { "IconPreview-\(title)" }

    init(alternateName: String?) {
        self = AppIconChoice.allCases.first { $0.alternateName == alternateName } ?? .classic
    }

    /// The icon that goes with a theme (nil for a custom theme: keep the current icon).
    init?(theme: ThemePreset) {
        switch theme {
        case .classic: self = .classic
        case .sage: self = .sage
        case .ocean: self = .ocean
        case .terracotta: self = .terracotta
        case .lavender: self = .lavender
        case .rose: self = .rose
        case .graphite: self = .graphite
        case .custom: return nil
        }
    }
}

@MainActor
enum AppIconManager {
    static var isSupported: Bool { UIApplication.shared.supportsAlternateIcons }

    static var current: AppIconChoice { AppIconChoice(alternateName: UIApplication.shared.alternateIconName) }

    /// Switches the home-screen icon (iOS shows a short confirmation).
    static func apply(_ choice: AppIconChoice) async -> Bool {
        guard isSupported, current != choice else { return true }
        do {
            try await UIApplication.shared.setAlternateIconName(choice.alternateName)
            return true
        } catch {
            return false
        }
    }

    /// Called when the theme changes: follows it if "Match theme" is on.
    nonisolated static func themeDidChange(to preset: ThemePreset) {
        guard UserDefaults.standard.bool(forKey: AppSettings.Keys.iconFollowsTheme),
              let choice = AppIconChoice(theme: preset) else { return }
        Task { @MainActor in _ = await apply(choice) }
    }
}

/// Settings › Appearance › App icon.
struct AppIconSettingsView: View {
    @AppStorage(AppSettings.Keys.iconFollowsTheme) private var followsTheme = AppSettings.Defaults.iconFollowsTheme
    @State private var selected: AppIconChoice = .classic
    @State private var failed = false

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 120), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(AppIconChoice.allCases) { choice in
                        tile(choice)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $followsTheme) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Match my theme")
                                .font(.app(.body, .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Changes the icon when you pick a theme. Ivory, Lapis and Papyrus are chosen by hand.")
                                .font(.app(.footnote))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .tint(Theme.goldFill)
                    .onChange(of: followsTheme) { _, isOn in
                        if isOn { AppIconManager.themeDidChange(to: ThemeManager.shared.preset) }
                    }
                }
                .card(padding: 16, radius: 18)

                Text("The eye of Horus keeps your hours: its iris is a clock, and the hands form a tick for work that's done. iOS confirms each change with a short message.")
                    .font(.app(.footnote))
                    .foregroundStyle(Theme.textSecondary)

                if failed {
                    Label("The icon couldn't be changed. Try again.", systemImage: "exclamationmark.triangle.fill")
                        .font(.app(.footnote, .semibold))
                        .foregroundStyle(Theme.warning)
                }
            }
            .padding(20)
        }
        .themedScreen()
        .tabBarSpace()
        .navigationTitle("App icon")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selected = AppIconManager.current }
    }

    private func tile(_ choice: AppIconChoice) -> some View {
        let isSelected = selected == choice
        return Button {
            Task {
                let ok = await AppIconManager.apply(choice)
                failed = !ok
                if ok {
                    withAnimation(.easeInOut(duration: 0.15)) { selected = choice }
                    // Picking by hand stops the icon from following the theme.
                    if AppIconChoice(theme: ThemeManager.shared.preset) != choice { followsTheme = false }
                }
            }
        } label: {
            VStack(spacing: 8) {
                Image(choice.previewName)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 1)
                    )
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(isSelected ? Theme.gold : Color.clear, lineWidth: 3)
                    )
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.app(.title3))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Theme.onGold, Theme.goldFill)
                                .offset(x: 6, y: -6)
                        }
                    }
                Text(choice.title)
                    .font(.app(.footnote, isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Theme.gold : Theme.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(choice.title) icon")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    NavigationStack { AppIconSettingsView() }
}
