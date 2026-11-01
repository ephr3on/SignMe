import Foundation
import SwiftData

@Model
final class WorkEntry {
    var id: UUID
    var date: Date
    var startTime: Date
    var endTime: Date
    /// Unpaid break in minutes, subtracted from the worked duration.
    /// Declared with a default so SwiftData migrates existing stores automatically.
    var breakMinutes: Int = 0
    var durationHours: Double
    var taskDescription: String
    var project: Project?
    var createdAt: Date
    var updatedAt: Date

    /// Creates an entry that isn't attached to a project yet. Insert it into a
    /// `ModelContext`, then attach it with `project.entries.append(entry)` —
    /// SwiftData sets `entry.project` automatically through the inverse relationship.
    init(
        id: UUID = UUID(),
        date: Date,
        startTime: Date,
        endTime: Date,
        breakMinutes: Int = 0,
        taskDescription: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.breakMinutes = breakMinutes
        self.durationHours = DateDurationService.durationHours(from: startTime, to: endTime, breakMinutes: breakMinutes)
        self.taskDescription = taskDescription
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Recomputes the stored duration after start, end, or break changes.
    func recalculateDuration() {
        durationHours = DateDurationService.durationHours(from: startTime, to: endTime, breakMinutes: breakMinutes)
    }

    /// A detached copy with the same times and description (new id, new timestamps).
    func duplicate() -> WorkEntry {
        WorkEntry(
            date: date,
            startTime: startTime,
            endTime: endTime,
            breakMinutes: breakMinutes,
            taskDescription: taskDescription
        )
    }
}
