import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID
    var name: String
    var createdAt: Date
    var job: Job?

    @Relationship(deleteRule: .cascade, inverse: \WorkEntry.project)
    var entries: [WorkEntry] = []

    /// Creates a project that isn't attached to a job yet. Insert it into a
    /// `ModelContext`, then attach it with `job.projects.append(project)` —
    /// SwiftData sets `project.job` automatically through the inverse relationship.
    init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }

    var totalHours: Double {
        entries.reduce(0) { $0 + $1.durationHours }
    }

    var lastEntryDate: Date? {
        entries.map(\.date).max()
    }
}
