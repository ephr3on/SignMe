import Foundation
import SwiftData

@Model
final class Job {
    var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Project.job)
    var projects: [Project] = []

    init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }

    var totalHours: Double {
        projects.reduce(0) { $0 + $1.totalHours }
    }

    var totalEntryCount: Int {
        projects.reduce(0) { $0 + $1.entries.count }
    }

    var lastActivityDate: Date? {
        projects.compactMap(\.lastEntryDate).max()
    }

    /// Returns a name guaranteed not to collide with an existing project in this job,
    /// appending "Copy" / "Copy 2" / … as needed.
    func uniqueProjectName(base: String) -> String {
        let existing = Set(projects.map { $0.name.lowercased() })
        guard existing.contains(base.lowercased()) else { return base }

        var candidate = "\(base) Copy"
        var counter = 2
        while existing.contains(candidate.lowercased()) {
            candidate = "\(base) Copy \(counter)"
            counter += 1
        }
        return candidate
    }
}
