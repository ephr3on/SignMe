import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case home, jobs, search, settings
}

/// Root navigation: a native TabView (each tab keeps its own NavigationStack and
/// scroll position) with the system tab bar hidden and our own bar in its place —
/// Home, Jobs, a raised gold "+" that opens a new entry from anywhere, Search, Settings.
/// The custom bar steps aside while the keyboard is up, so typing never hides content.
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardVisible {
                AppTabBar(selection: $selectedTab) { showingNewEntry = true }
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
        NavigationStack { content() }
            .tag(tab)
            .toolbar(.hidden, for: .tabBar)
    }
}

/// Bottom tab bar: Home, Jobs, [+], Search, Settings.
struct AppTabBar: View {
    @Binding var selection: AppTab
    let onAdd: () -> Void

    var body: some View {
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
                .offset(y: -20)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 48)
        .accessibilityLabel("Add entry")
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewSupport.container)
        .environment(TimerStore(defaults: UserDefaults(suiteName: "preview")!))
        .preferredColorScheme(.dark)
}
