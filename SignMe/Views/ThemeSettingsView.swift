import SwiftUI
import UIKit

/// Settings › Appearance: Light/Dark/System plus a gallery of themes and a Custom theme.
struct ThemeSettingsView: View {
    @AppStorage(AppSettings.Keys.theme) private var appearanceRaw = AppSettings.Defaults.theme
    @Environment(\.colorScheme) private var colorScheme

    private var manager: ThemeManager { ThemeManager.shared }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Mode")
                    Picker("Mode", selection: $appearanceRaw) {
                        ForEach(AppTheme.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Every theme has a light and a dark version. System follows your iPhone.")
                        .font(.app(.footnote))
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Theme")
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(ThemePreset.allCases.filter { $0 != .custom }) { preset in
                            ThemeCard(
                                preset: preset,
                                palette: preset.palette(custom: manager.custom),
                                isDark: colorScheme == .dark,
                                isSelected: manager.preset == preset
                            ) {
                                withAnimation(.easeInOut(duration: 0.25)) { manager.select(preset) }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Your own")
                    NavigationLink {
                        CustomThemeEditor()
                    } label: {
                        HStack(spacing: 14) {
                            ThemeSwatch(palette: ThemePreset.custom.palette(custom: manager.custom), isDark: colorScheme == .dark)
                                .frame(width: 76, height: 56)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Custom theme")
                                    .font(.app(.body, .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(manager.preset == .custom ? "In use · tap to edit colours" : "Pick your own accent and background")
                                    .font(.app(.footnote))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            if manager.preset == .custom {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.app(.title3))
                                    .foregroundStyle(Theme.onGold, Theme.goldFill)
                            }
                            Image(systemName: "chevron.right")
                                .font(.app(.footnote, .semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .card(padding: 12, radius: 18, highlighted: manager.preset == .custom)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .themedScreen()
        .tabBarSpace()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A selectable theme preview in the gallery.
private struct ThemeCard: View {
    let preset: ThemePreset
    let palette: ThemePalette
    let isDark: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ThemeSwatch(palette: palette, isDark: isDark)
                    .frame(height: 92)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title)
                        .font(.app(.subheadline, .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(preset.subtitle)
                        .font(.app(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2, reservesSpace: true)
                }
            }
            .padding(8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Theme.gold : Theme.cardBorder, lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.app(.title3))
                        .foregroundStyle(Theme.onGold, Theme.goldFill)
                        .padding(12)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.title) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A miniature screen drawn with a palette (not the active theme), so themes can be compared.
struct ThemeSwatch: View {
    let palette: ThemePalette
    let isDark: Bool

    private var t: ThemeTokens { isDark ? palette.dark : palette.light }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                Color(uiColor: t.background)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(Color(uiColor: t.textPrimary)).frame(width: width * 0.45, height: 6)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            RoundedRectangle(cornerRadius: 2).fill(Color(uiColor: t.textSecondary)).frame(width: width * 0.32, height: 4)
                            Spacer()
                            RoundedRectangle(cornerRadius: 2).fill(Color(uiColor: t.accent)).frame(width: width * 0.14, height: 4)
                        }
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach([0.5, 0.8, 0.4, 1.0, 0.3], id: \.self) { h in
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color(uiColor: h == 1.0 ? t.accentFill : t.bar))
                                    .frame(width: 6, height: 16 * h)
                            }
                        }
                        .frame(height: 16, alignment: .bottom)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: t.surface), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Capsule()
                        .fill(Color(uiColor: t.accentFill))
                        .frame(height: 10)
                        .overlay(Capsule().fill(Color(uiColor: t.onAccent)).frame(width: width * 0.22, height: 3))
                }
                .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// Pick an accent color, a background tint and how strong the tint is.
/// Changes apply instantly (the Custom theme becomes active) and stay readable,
/// because text and accent shades are adjusted automatically for contrast.
struct CustomThemeEditor: View {
    @State private var accent: Color
    @State private var tint: Color
    @State private var strength: Double

    private var manager: ThemeManager { ThemeManager.shared }

    private static let accentSuggestions: [UInt32] = [0xD4AF37, 0xC2643A, 0xC24F6E, 0x7B5CC9, 0x3B6FD8, 0x1F8A9B, 0x4F7D43, 0x1B2333]
    private static let tintSuggestions: [UInt32] = [0x3E5A8A, 0x6F8A68, 0x3E6A8E, 0xB0806A, 0x7E70AE, 0xAF7C8A, 0x6B7280, 0x8A7A5C]

    init() {
        let custom = ThemeManager.shared.custom
        _accent = State(initialValue: Color(uiColor: custom.accent))
        _tint = State(initialValue: Color(uiColor: custom.tint))
        _strength = State(initialValue: custom.strength)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    preview(isDark: false, label: "Light")
                    preview(isDark: true, label: "Dark")
                }

                if manager.preset != .custom {
                    Button("Use this theme", action: apply)
                        .buttonStyle(GoldButtonStyle(height: 50))
                }

                colorSection(
                    title: "Accent colour",
                    hint: "Buttons, highlights, totals and the + button.",
                    selection: $accent,
                    suggestions: Self.accentSuggestions
                )

                colorSection(
                    title: "Background tint",
                    hint: "The hue mixed into backgrounds and cards.",
                    selection: $tint,
                    suggestions: Self.tintSuggestions
                )

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Tint strength")
                    HStack(spacing: 12) {
                        Text("Subtle").font(.app(.footnote)).foregroundStyle(Theme.textSecondary)
                        Slider(value: $strength, in: 0...1) { editing in
                            if !editing { apply() }
                        }
                        .accessibilityLabel("Tint strength")
                        Text("Strong").font(.app(.footnote)).foregroundStyle(Theme.textSecondary)
                    }
                    .card(padding: 14, radius: 16)
                }

                Button("Reset custom colours") {
                    let defaults = CustomThemeSettings.default
                    accent = Color(uiColor: defaults.accent)
                    tint = Color(uiColor: defaults.tint)
                    strength = defaults.strength
                    apply()
                }
                .font(.app(.subheadline, .semibold))
                .foregroundStyle(Theme.gold)
                .frame(maxWidth: .infinity)

                Text("Text colours are adjusted automatically so everything stays easy to read, whatever you pick.")
                    .font(.app(.footnote))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .themedScreen()
        .tabBarSpace()
        .navigationTitle("Custom theme")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: accent) { _, _ in apply() }
        .onChange(of: tint) { _, _ in apply() }

    }

    private var draft: CustomThemeSettings {
        CustomThemeSettings(accent: UIColor(accent), tint: UIColor(tint), strength: strength)
    }

    private func apply() {
        manager.updateCustom(draft)
    }

    private func preview(isDark: Bool, label: String) -> some View {
        VStack(spacing: 6) {
            ThemeSwatch(palette: ThemePreset.custom.palette(custom: draft), isDark: isDark)
                .frame(height: 110)
            Text(label)
                .font(.app(.caption, .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func colorSection(title: String, hint: String, selection: Binding<Color>, suggestions: [UInt32]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(suggestions, id: \.self) { hex in
                        let color = Color(hex: hex)
                        let isSelected = UIColor(selection.wrappedValue).hexString == UIColor(hex: hex).hexString
                        Button {
                            selection.wrappedValue = color
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 1))
                                .overlay(
                                    Circle()
                                        .strokeBorder(Theme.textPrimary, lineWidth: isSelected ? 2 : 0)
                                        .padding(-4)
                                )
                                .frame(width: 34, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Colour \(UIColor(hex: hex).hexString)")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                Divider().overlay(Theme.hairline)
                ColorPicker(selection: selection, supportsOpacity: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Any colour…")
                            .font(.app(.body, .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text(hint)
                            .font(.app(.caption))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .card(padding: 14, radius: 16)
        }
    }
}

#Preview {
    NavigationStack {
        ThemeSettingsView()
    }
}
