import Foundation
import SwiftData

/// Seeds an in-memory `ModelContainer` with sample data so every `#Preview`
/// across the app can render realistic content without touching real user data.
@MainActor
enum PreviewSupport {
    static let container: ModelContainer = {
        let schema = Schema([Job.self, Project.self, WorkEntry.self, SavedSignature.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let job = Job(name: "Acme Studio")
        context.insert(job)

        let websiteProject = Project(name: "Website Redesign")
        let appProject = Project(name: "Mobile App")
        context.insert(websiteProject)
        context.insert(appProject)
        job.projects = [websiteProject, appProject]

        let calendar = Calendar.current
        let descriptions = [
            "Implemented new component library",
            "Client review call and feedback notes",
            "Fixed responsive layout issues",
            "Wrote onboarding flow copy",
            "Set up analytics dashboard",
            "Pair programming on checkout flow"
        ]

        for offset in 0..<descriptions.count {
            let day = calendar.date(byAdding: .day, value: -offset * 4, to: .now) ?? .now
            let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
            let end = calendar.date(bySettingHour: 12, minute: 30, second: 0, of: day) ?? day
            let entry = WorkEntry(
                date: day,
                startTime: start,
                endTime: end,
                breakMinutes: offset == 0 ? 30 : 0,
                taskDescription: descriptions[offset]
            )
            context.insert(entry)
            websiteProject.entries.append(entry)
        }

        let secondJob = Job(name: "Personal")
        let learningProject = Project(name: "Learning SwiftUI")
        context.insert(secondJob)
        context.insert(learningProject)
        secondJob.projects = [learningProject]

        try? context.save()
        return container
    }()

    static var sampleJob: Job {
        (try? container.mainContext.fetch(FetchDescriptor<Job>(sortBy: [SortDescriptor(\.createdAt)])))?.first
            ?? Job(name: "Sample Job")
    }

    static var sampleProject: Project {
        sampleJob.projects.first ?? Project(name: "Sample Project")
    }
}
