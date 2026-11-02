import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case home, jobs, search, settings
}

/// Root navigation: a native TabView (each tab keeps its own NavigationStack and
/// scroll position) with the system tab bar hidden and our own bar in its place —
/// Home, Jobs, a raised gold "+" that opens a new entry from anywhere, Search, Settings.
///
/// The bar is attached inside every tab, directly on its NavigationStack. A TabView
/// doesn't pass an outer safe-area inset down to its tabs, so attaching it there is
/// what makes every screen (including pushed ones) end its content above the bar
/// instead of scrolling underneath it. The bar steps aside while the keyboard is up.
struct ContentView: View {
    @State private var selectedTab: AppTab = .home
    @State private var showingNewEntry = false
    @State private var keyboardVisible = false

    var body: some View {
        TabView(selection: $selectedTab) {
            tab(.home) { DashboardView() }
            tab(.jobs) { JobListView() }
            tab(.search) { SearchWorkEntryView() }
            tab(.settings) { SettingsView() }
        }
        .background(Theme.background.ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.15)) { keyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.15)) { keyboardVisible = false }
        }
        .sheet(isPresented: $showingNewEntry) {
            EntryFormView()
        }
    }

    private func tab<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack { content() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !keyboardVisible {
                    AppTabBar(selection: $selectedTab) { showingNewEntry = true }
                        .transition(.opacity)
                }
            }
            .tag(tab)
            .toolbar(.hidden, for: .tabBar)
    }
}

/// Bottom tab bar: Home, Jobs, [+], Search, Settings.
struct AppTabBar: View {
    @Binding var selection: AppTab
    let onAdd: () -> Void

    /// How far the round + button rises above the bar.
    private static let addButtonRise: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            // Transparent room for the raised + button, so it's part of the reserved
            // space: content stops above the button instead of hiding behind it.
            Color.clear
                .frame(height: Self.addButtonRise)
                .allowsHitTesting(false)

            HStack(alignment: .top, spacing: 0) {
                item(.home, title: "Home", icon: "house", selectedIcon: "house.fill")
                item(.jobs, title: "Jobs", icon: "briefcase", selectedIcon: "briefcase.fill")
                addButton
                item(.search, title: "Search", icon: "magnifyingglass", selectedIcon: "magnifyingglass")
                item(.settings, title: "Settings", icon: "gearshape", selectedIcon: "gearshape.fill")
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .background(
                Theme.tabBar
                    .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    private func item(_ tab: AppTab, title: String, icon: String, selectedIcon: String) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? selectedIcon : icon)
                    .font(.system(size: 21, weight: .medium))
                    .frame(height: 26)
                Text(title)
                    .font(.app(.caption2, .semibold))
            }
            .foregroundStyle(isSelected ? Theme.gold : Theme.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.onGold)
                .frame(width: 58, height: 58)
                .background(Circle().fill(Theme.goldFill))
                .overlay(Circle().strokeBorder(Theme.background, lineWidth: 4))
                .offset(y: -Self.addButtonRise)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 48)
        .zIndex(1)
        .accessibilityLabel("Add entry")
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewSupport.container)
        .environment(TimerStore(defaults: UserDefaults(suiteName: "preview")!))
        .preferredColorScheme(.dark)
}
