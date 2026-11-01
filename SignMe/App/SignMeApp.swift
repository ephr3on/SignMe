import SwiftUI
import SwiftData

@main
struct SignMeApp: App {
    let modelContainer: ModelContainer = {
        let schema = Schema([Job.self, Project.self, WorkEntry.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create SignMe's ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
