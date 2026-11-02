import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case home, jobs, search, settings
}

/// Root navigation: a native TabView (each tab keeps its own NavigationStack and
/// scroll position) with the system tab bar hidden and our own bar in its place —
/// Home, Jobs, a raised gold "+" that opens a new entry from anywhere, Search, Settings.
///
/// The bar is a fixed layer at the bottom of the window. Its measured height is
/// handed to every screen through the `tabBarInset` environment value, and each
/// screen reserves that much room at its bottom with `.tabBarSpace()` — so the last
/// row of every list, form and page always ends above the bar instead of under it.
/// (Insets set outside a TabView or NavigationStack don't reliably reach the
/// screens inside, so each screen reserves the space itself.)
/// The bar steps aside while the keyboard is up.
///
/// Tapping the tab you're already on takes you back to that tab's first screen
/// (e.g. Jobs › job › project → tap Jobs → the Jobs list).
struct ContentView: View {
    @State private var selectedTab: AppTab = .home
    @State private var showingNewEntry = false
    @State private var keyboardVisible = false
    @State private var tabBarHeight: CGFloat = 96
    /// Bumped to rebuild a tab's NavigationStack, which returns it to its first screen.
    @State private var stackGeneration: [AppTab: Int] = [:]
    /// Tabs currently showing their first screen (nothing pushed on top).
    @State private var tabsAtRoot: Set<AppTab> = [.home, .jobs, .search, .settings]

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                tab(.home) { DashboardView() }
                tab(.jobs) { JobListView() }
                tab(.search) { SearchWorkEntryView() }
                tab(.settings) { SettingsView() }
            }
            .environment(\.tabBarInset, keyboardVisible ? 0 : tabBarHeight)

            if !keyboardVisible {
                AppTabBar(selection: $selectedTab, onReselect: popToRoot) { showingNewEntry = true }
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { tabBarHeight = proxy.size.height }
                                .onChange(of: proxy.size.height) { _, height in tabBarHeight = height }
                        }
                    )
                    .transition(.opacity)
            }
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
        let generation = stackGeneration[tab, default: 0]
        return NavigationStack {
            content()
                // The first screen disappears when something is pushed on top of it
                // (or the tab is left) and reappears when it's visible again.
                .onAppear { tabsAtRoot.insert(tab) }
                .onDisappear {
                    // Ignore the old stack's first screen going away after a reset.
                    if stackGeneration[tab, default: 0] == generation { tabsAtRoot.remove(tab) }
                }
        }
        .id(generation)
        .tag(tab)
        .toolbar(.hidden, for: .tabBar)
    }

    /// Tapping the selected tab again: go back to its first screen.
    private func popToRoot(_ tab: AppTab) {
        guard !tabsAtRoot.contains(tab) else { return }
        stackGeneration[tab, default: 0] += 1
        tabsAtRoot.insert(tab)
    }
}

// MARK: - Reserving room for the tab bar

private struct TabBarInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Height of the app's bottom tab bar above the home-indicator area (0 when hidden,
    /// e.g. while the keyboard is up or inside sheets).
    var tabBarInset: CGFloat {
        get { self[TabBarInsetKey.self] }
        set { self[TabBarInsetKey.self] = newValue }
    }
}

private struct TabBarSpaceModifier: ViewModifier {
    @Environment(\.tabBarInset) private var inset

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: inset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Keeps this screen's content above the app's tab bar. Apply it to every
    /// screen shown inside a tab (root and pushed screens); sheets don't need it.
    func tabBarSpace() -> some View {
        modifier(TabBarSpaceModifier())
    }
}

/// Bottom tab bar: Home, Jobs, [+], Search, Settings.
struct AppTabBar: View {
    @Binding var selection: AppTab
    /// Called when the already-selected tab is tapped again.
    var onReselect: (AppTab) -> Void = { _ in }
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
            if isSelected {
                onReselect(tab)
            } else {
                selection = tab
            }
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
        .accessibilityHint(isSelected ? "Goes back to the first \(title) screen" : "")
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
