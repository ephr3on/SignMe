import XCTest
import SwiftData
@testable import SignMe

@MainActor
final class PlannedTaskTests: XCTestCase {
    private var context: ModelContext!
    private var container: ModelContainer!
    private let calendar = Calendar(identifier: .gregorian)

    override func setUp() async throws {
        let schema = Schema([Job.self, Project.self, WorkEntry.self, SavedSignature.self, RecurringShift.self, PlannedTask.self, ExportTemplate.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = container.mainContext
    }

    private func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    func testOffsetsAreUniqueAndSorted() {
        let task = PlannedTask(projectID: UUID(), start: date(10, 14), taskDescription: "Event", reminderOffsets: [60, 1440, 60, 0, -5])
        XCTAssertEqual(task.reminderOffsets, [1440, 60, 0])
    }

    func testUpcomingRemindersSkipPast() {
        let task = PlannedTask(projectID: UUID(), start: date(10, 14), taskDescription: "Event", reminderOffsets: [1440, 60, 0])
        let reminders = task.upcomingReminders(now: date(10, 12))
        XCTAssertEqual(reminders.map(\.offset), [60, 0])
        XCTAssertEqual(reminders.first?.date, date(10, 13))
    }

    func testOptionalEndAndOvernight() {
        let noEnd = PlannedTask(projectID: UUID(), start: date(10, 14), taskDescription: "A")
        XCTAssertNil(noEnd.effectivePlannedEnd)
        XCTAssertEqual(noEnd.logReminderDate(now: date(9, 9)), date(10, 16))

        let overnight = PlannedTask(projectID: UUID(), start: date(10, 22), plannedEnd: date(10, 2), taskDescription: "B")
        XCTAssertEqual(overnight.effectivePlannedEnd, date(11, 2))
        XCTAssertEqual(overnight.plannedHours ?? 0, 4, accuracy: 0.001)
    }

    func testStages() {
        let task = PlannedTask(projectID: UUID(), start: date(10, 14), taskDescription: "Event")
        XCTAssertEqual(task.stage(now: date(9, 23), calendar: calendar), .upcoming)
        XCTAssertEqual(task.stage(now: date(10, 8), calendar: calendar), .awaitingConfirmation)
        XCTAssertEqual(task.stage(now: date(12, 8), calendar: calendar), .awaitingConfirmation)
    }

    func testValidation() {
        let now = date(10, 18)
        XCTAssertNil(PlannedTask.validationMessage(start: date(10, 14), end: date(10, 17), breakMinutes: 30, now: now))
        XCTAssertNotNil(PlannedTask.validationMessage(start: date(10, 14), end: date(10, 13), breakMinutes: 0, now: now))
        XCTAssertNotNil(PlannedTask.validationMessage(start: date(10, 14), end: date(10, 19), breakMinutes: 0, now: now))
        XCTAssertNotNil(PlannedTask.validationMessage(start: date(10, 14), end: date(10, 15), breakMinutes: 60, now: now))
    }

    func testCompleteAddsEntryAndStopsReminders() {
        let job = Job(name: "Kolleg")
        let project = Project(name: "Events")
        context.insert(job)
        context.insert(project)
        job.projects.append(project)

        let task = PlannedTask(projectID: project.id, start: date(10, 14), plannedEnd: date(10, 17), taskDescription: "Event", reminderOffsets: [60])
        context.insert(task)
        let entry = task.complete(start: date(10, 14), end: date(10, 16, 30), breakMinutes: 30, description: "Event", project: project, context: context, now: date(10, 18))

        XCTAssertEqual(task.status, .done)
        XCTAssertEqual(task.completedEntryID, entry.id)
        XCTAssertEqual(entry.durationHours, 2, accuracy: 0.001)
        XCTAssertEqual(project.entries.count, 1)
        XCTAssertTrue(task.upcomingReminders(now: date(1, 0)).isEmpty)
        XCTAssertNil(task.logReminderDate(now: date(1, 0)))
        XCTAssertEqual(task.stage(now: date(10, 18), calendar: calendar), .done)
    }

    func testReminderText() {
        XCTAssertEqual(PlannedTask.reminderText(0), "At start time")
        XCTAssertEqual(PlannedTask.reminderText(30), "30 min before")
        XCTAssertEqual(PlannedTask.reminderText(120), "2 hours before")
        XCTAssertEqual(PlannedTask.reminderText(1440), "1 day before")
        XCTAssertEqual(PlannedTask.reminderText(10080), "1 week before")
    }
}
