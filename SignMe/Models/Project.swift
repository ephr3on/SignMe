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

    init(id: UUID = UUID(), name: String, createdAt: Date = .now, job: Job? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.job = job
    }

    var totalHours: Double {
        entries.reduce(0) { $0 + $1.durationHours }
    }

    var lastEntryDate: Date? {
        entries.map(\.date).max()
    }
}
