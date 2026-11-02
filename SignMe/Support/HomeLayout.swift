import SwiftUI

/// A card on the Home screen that can be shown, hidden and reordered.
enum HomeSection: String, CaseIterable, Identifiable {
    case timer
    case target
    case week
    case calendar
    case recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timer: "Timer"
        case .target: "Monthly target"
        case .week: "This week"
        case .calendar: "Calendar"
        case .recent: "Recent entries"
        }
    }

    var subtitle: String {
        switch self {
        case .timer: "Clock in and out"
        case .target: "Progress towards your monthly hours"
        case .week: "Hours per day this week"
        case .calendar: "This month at a glance"
        case .recent: "Your latest entries"
        }
    }

    var icon: String {
        switch self {
        case .timer: "timer"
        case .target: "target"
        case .week: "chart.bar.fill"
        case .calendar: "calendar"
        case .recent: "clock.arrow.circlepath"
        }
    }
}

/// Which Home cards show, and in what order. Stored in UserDefaults as two
/// comma-separated lists so new cards added in later versions appear automatically.
struct HomeLayout: Equatable {
    var order: [HomeSection]
    var hidden: Set<HomeSection>

    static let `default` = HomeLayout(order: HomeSection.allCases, hidden: [])

    var visible: [HomeSection] { order.filter { !hidden.contains($0) } }

    init(order: [HomeSection], hidden: Set<HomeSection>) {
        self.order = order
        self.hidden = hidden
    }

    /// Parses stored values; unknown names are dropped and missing cards are appended.
    init(orderRaw: String, hiddenRaw: String) {
        var seen = Set<HomeSection>()
        var order: [HomeSection] = []
        for name in orderRaw.split(separator: ",") {
            if let section = HomeSection(rawValue: String(name)), seen.insert(section).inserted {
                order.append(section)
            }
        }
        for section in HomeSection.allCases where !seen.contains(section) {
            order.append(section)
        }
        self.order = order
        self.hidden = Set(hiddenRaw.split(separator: ",").compactMap { HomeSection(rawValue: String($0)) })
    }

    var orderRaw: String { order.map(\.rawValue).joined(separator: ",") }
    var hiddenRaw: String { order.filter { hidden.contains($0) }.map(\.rawValue).joined(separator: ",") }
}

/// Show/hide and drag to reorder the Home cards.
struct HomeCustomizeView: View {
    @AppStorage(AppSettings.Keys.homeOrder) private var orderRaw = AppSettings.Defaults.homeOrder
    @AppStorage(AppSettings.Keys.homeHidden) private var hiddenRaw = AppSettings.Defaults.homeHidden

    private var layout: HomeLayout { HomeLayout(orderRaw: orderRaw, hiddenRaw: hiddenRaw) }

    private func save(_ layout: HomeLayout) {
        orderRaw = layout.orderRaw
        hiddenRaw = layout.hiddenRaw
    }

    var body: some View {
        List {
            Section {
                ForEach(layout.order) { section in
                    Toggle(isOn: binding(for: section)) {
                        HStack(spacing: 12) {
                            Image(systemName: section.icon)
                                .font(.app(.subheadline, .semibold))
                                .foregroundStyle(Theme.onGold)
                                .frame(width: 32, height: 32)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.goldFill))
                                .opacity(layout.hidden.contains(section) ? 0.45 : 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title)
                                    .font(.app(.body, .semibold))
                                    .foregroundStyle(layout.hidden.contains(section) ? Theme.textTertiary : Theme.textPrimary)
                                Text(section.subtitle)
                                    .font(.app(.footnote))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .tint(Theme.goldFill)
                    .themedRow()
                }
                .onMove { from, to in
                    var updated = layout
                    updated.order.move(fromOffsets: from, toOffset: to)
                    save(updated)
                }
            } header: {
                SettingsHeader("Cards")
            } footer: {
                Text("Switch cards on or off, and drag ≡ to change their order.")
                    .font(.app(.footnote))
            }

            Section {
                Button("Reset to default") {
                    withAnimation { save(.default) }
                }
                .font(.app(.body, .semibold))
                .foregroundStyle(Theme.gold)
                .disabled(layout == .default)
                .themedRow()
            }
        }
        .environment(\.editMode, .constant(.active))
        .themedScreen()
        .navigationTitle("Customize Home")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(for section: HomeSection) -> Binding<Bool> {
        Binding(
            get: { !layout.hidden.contains(section) },
            set: { isOn in
                var updated = layout
                if isOn { updated.hidden.remove(section) } else { updated.hidden.insert(section) }
                withAnimation { save(updated) }
            }
        )
    }
}

#Preview {
    NavigationStack { HomeCustomizeView() }
}
