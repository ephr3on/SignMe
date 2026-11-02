import SwiftUI
import SwiftData

@main
struct SignMeApp: App {
    let modelContainer: ModelContainer = {
        let schema = Schema([Job.self, Project.self, WorkEntry.self, SavedSignature.self, RecurringShift.self, PlannedTask.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create SignMe's ModelContainer: \(error)")
        }
    }()

    @State private var timerStore = TimerStore()
    /// Handles taps on planned-task reminders.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        AppFonts.register()
        Theme.configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(timerStore)
        }
        .modelContainer(modelContainer)
    }
}

/// Applies the user's appearance (Light/Dark/System), theme accent and app font.
/// Lives in a View (not the Scene) so it redraws immediately when the theme changes.
private struct RootView: View {
    @AppStorage(AppSettings.Keys.theme) private var themeRawValue = AppSettings.Defaults.theme

    private var appearance: AppTheme { AppTheme(rawValue: themeRawValue) ?? .light }

    var body: some View {
        ContentView()
            .preferredColorScheme(appearance.colorScheme)
            .tint(Theme.gold)
            .font(.app(.body))
    }
}
