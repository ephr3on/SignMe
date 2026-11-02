import Foundation
import SwiftData

/// A task planned for later on a project, e.g. "Prepare the welcome event —
/// Thu 6 Nov, 14:00–17:00", with reminders before it starts.
///
/// Life cycle:
/// 1. **Planned** – has a start, an optional planned end, a description and any
///    number of reminders (minutes before the start). Notifications are scheduled.
/// 2. **Waiting for confirmation** – from the task's day onwards it can be logged:
///    the user sets the real start/end (and break) and must tick "This task is done".
/// 3. **Done** – a WorkEntry was added to the project; reminders are removed.
/// Nothing is added to the working hours until step 2 is confirmed.
@Model
final class PlannedTask {
    var id: UUID
    /// The project the task belongs to (looked up by id, like RecurringShift).
    var projectID: UUID
    var start: Date
    /// Optional planned end; when it's earlier than the start time it means the next day.
    var plannedEnd: Date?
    var taskDescription: String
    /// Reminder offsets in minutes before the start, stored as "1440,60,0".
    var reminderOffsetsRaw: String
    /// Also send a "Did you finish it?" notification after the task (at its planned
    /// end, or two hours after the start when no end is set).
    var remindToLog: Bool
    /// "planned" or "done".
    var statusRaw: String
    /// The WorkEntry created when the task was confirmed.
    var completedEntryID: UUID?
    var completedAt: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        projectID: UUID,
        start: Date,
        plannedEnd: Date? = nil,
        taskDescription: String,
        reminderOffsets: [Int] = [60],
        remindToLog: Bool = true,
        createdAt: Date = .now
    ) {
        self.id = id
        self.projectID = projectID
        self.start = start
        self.plannedEnd = plannedEnd
        self.taskDescription = taskDescription
        self.reminderOffsetsRaw = PlannedTask.encode(reminderOffsets)
        self.remindToLog = remindToLog
        self.statusRaw = Status.planned.rawValue
        self.completedEntryID = nil
        self.completedAt = nil
        self.createdAt = createdAt
    }

    enum Status: String {
        case planned
        case done
    }

    /// Where the task stands right now (for grouping and badges).
    enum Stage: Equatable {
        /// Its day hasn't come yet.
        case upcoming
        /// It's the task's day (or later) and it hasn't been confirmed yet.
        case awaitingConfirmation
        case done
    }

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    /// Unique offsets, longest first ("1 day before" before "1 hour before").
    var reminderOffsets: [Int] {
        get { PlannedTask.decode(reminderOffsetsRaw) }
        set { reminderOffsetsRaw = PlannedTask.encode(newValue) }
    }

    static func encode(_ offsets: [Int]) -> String {
        Array(Set(offsets.filter { $0 >= 0 })).sorted(by: >).map(String.init).joined(separator: ",")
    }

    static func decode(_ raw: String) -> [Int] {
        Array(Set(raw.split(separator: ",").compactMap { Int($0) }.filter { $0 >= 0 })).sorted(by: >)
    }

    // MARK: Times

    /// The planned end as a concrete date (next day when it's not after the start).
    var effectivePlannedEnd: Date? {
        guard let plannedEnd else { return nil }
        return plannedEnd > start ? plannedEnd : plannedEnd.addingTimeInterval(24 * 3600)
    }

    var plannedHours: Double? {
        effectivePlannedEnd.map { $0.timeIntervalSince(start) / 3600 }
    }

    // MARK: State

    func stage(now: Date = .now, calendar: Calendar = .current) -> Stage {
        if status == .done { return .done }
        return canConfirm(now: now, calendar: calendar) ? .awaitingConfirmation : .upcoming
    }

    /// A task can be logged from the start of its day onwards.
    func canConfirm(now: Date = .now, calendar: Calendar = .current) -> Bool {
        status == .planned && now >= calendar.startOfDay(for: start)
    }

    // MARK: Notifications

    /// Reminders still ahead of `now`, as (offset, fire date), soonest last.
    func upcomingReminders(now: Date = .now) -> [(offset: Int, date: Date)] {
        guard status == .planned else { return [] }
        return reminderOffsets
            .map { (offset: $0, date: start.addingTimeInterval(-Double($0) * 60)) }
            .filter { $0.date > now }
    }

    /// When to ask "Did you finish it?", if that's on and still ahead.
    func logReminderDate(now: Date = .now) -> Date? {
        guard status == .planned, remindToLog else { return nil }
        let date = effectivePlannedEnd ?? start.addingTimeInterval(2 * 3600)
        return date > now ? date : nil
    }

    // MARK: Completing

    /// Problems with the times entered when logging the task, or nil if they're fine.
    static func validationMessage(start: Date, end: Date, breakMinutes: Int, now: Date = .now) -> String? {
        if end <= start { return "The end must be after the start." }
        if end > now.addingTimeInterval(60) { return "The end can't be in the future — log the task once it's done." }
        let minutes = Int(end.timeIntervalSince(start) / 60)
        if breakMinutes >= minutes { return "The break is longer than the task." }
        if minutes > 24 * 60 { return "A single entry can't be longer than 24 hours." }
        return nil
    }

    /// Adds the confirmed task to the project's working hours and marks it done.
    /// Callers must only do this after the user confirmed the task was done.
    @discardableResult
    func complete(
        start actualStart: Date,
        end actualEnd: Date,
        breakMinutes: Int,
        description: String,
        project: Project,
        context: ModelContext,
        now: Date = .now
    ) -> WorkEntry {
        let entry = WorkEntry(
            date: actualStart,
            startTime: actualStart,
            endTime: actualEnd,
            breakMinutes: breakMinutes,
            taskDescription: description
        )
        context.insert(entry)
        project.entries.append(entry)
        status = .done
        completedEntryID = entry.id
        completedAt = now
        return entry
    }

    // MARK: Text

    /// "1 day before", "2 hours before", "30 min before", "At start time"
    static func reminderText(_ offset: Int) -> String {
        if offset == 0 { return "At start time" }
        if offset % 1440 == 0 {
            let days = offset / 1440
            if days % 7 == 0 { return days == 7 ? "1 week before" : "\(days / 7) weeks before" }
            return days == 1 ? "1 day before" : "\(days) days before"
        }
        if offset % 60 == 0 {
            let hours = offset / 60
            return hours == 1 ? "1 hour before" : "\(hours) hours before"
        }
        return "\(offset) min before"
    }

    /// "Thu 6 Nov, 14:00–17:00" or "Thu 6 Nov, 14:00"
    var whenText: String {
        let day = start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let startTime = start.formatted(date: .omitted, time: .shortened)
        if let end = effectivePlannedEnd {
            return "\(day), \(startTime)–\(end.formatted(date: .omitted, time: .shortened))"
        }
        return "\(day), \(startTime)"
    }
}
