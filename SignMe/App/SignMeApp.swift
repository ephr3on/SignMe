import SwiftUI
import SwiftData

// App Icon suggestion: a rounded-square icon in the app's accent blue,
// featuring a simple clock face with a checkmark tick at the 2 o'clock
// position (evokes "signing off" on tracked time). Keep it flat and
// high-contrast so it reads well at small sizes; avoid text in the icon.

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
