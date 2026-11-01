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

    init() {
        Theme.configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(timerStore)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
        }
        .modelContainer(modelContainer)
    }
}
