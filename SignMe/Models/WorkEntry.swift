import Foundation
import SwiftData

@Model
final class WorkEntry {
    var id: UUID
    var date: Date
    var startTime: Date
    var endTime: Date
    var durationHours: Double
    var taskDescription: String
    var project: Project?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        startTime: Date,
        endTime: Date,
        taskDescription: String,
        project: Project? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.durationHours = DateDurationService.durationHours(from: startTime, to: endTime)
        self.taskDescription = taskDescription
        self.project = project
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
