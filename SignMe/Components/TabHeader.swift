import SwiftUI

/// The title block at the top of a tab's first screen (Jobs, Search, Settings),
/// matching Home. It's part of the page content, so every tab opens exactly at
/// its top — the system large title could open partly collapsed, which looked
/// like the page was already scrolled down a little.
struct TabHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.display(.title))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.app(.subheadline))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension TabHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = { EmptyView() }
    }
}

/// Round icon used for header buttons (same look as on Home).
struct HeaderIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.app(.body, .semibold))
            .foregroundStyle(Theme.gold)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Theme.surface))
            .overlay(Circle().strokeBorder(Theme.gold.opacity(0.35), lineWidth: 1))
            .contentShape(Circle())
    }
}

/// A search field that sits in the page and never hides.
struct InlineSearchField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .font(.app(.body))
                .foregroundStyle(Theme.textPrimary)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minHeight: 46)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(focused ? Theme.gold.opacity(0.6) : Theme.cardBorder, lineWidth: focused ? 1.5 : 1)
        )
    }
}
