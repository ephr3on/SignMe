import SwiftUI

/// Root tab navigation: Dashboard, Jobs, Search, Settings — each with its own
/// independent NavigationStack so pushed screens don't leak between tabs.
struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
            }
            .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }

            NavigationStack {
                JobListView()
            }
            .tabItem { Label("Jobs", systemImage: "briefcase.fill") }

            NavigationStack {
                SearchWorkEntryView()
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewSupport.container)
}
