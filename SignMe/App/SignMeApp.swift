import SwiftUI
import SwiftData

@main
struct SignMeApp: App {
    let modelContainer: ModelContainer = {
        let schema = Schema([Job.self, Project.self, WorkEntry.self, SavedSignature.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create SignMe's ModelContainer: \(error)")
        }
    }()

    @State private var timerStore = TimerStore()
    @AppStorage(AppSettings.Keys.theme) private var themeRawValue = AppSettings.Defaults.theme

    init() {
        Theme.configureAppearance()
    }

    private var theme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .light }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(timerStore)
                .preferredColorScheme(theme.colorScheme)
                .tint(Theme.gold)
        }
        .modelContainer(modelContainer)
    }
}
