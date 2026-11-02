import XCTest
import SwiftData
@testable import SignMe

@MainActor
final class CalendarServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let calendar = Calendar(identifier: .gregorian)

    override func setUp() async throws {
        let schema = Schema([Job.self, Project.self, WorkEntry.self, SavedSignature.self, RecurringShift.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = container.mainContext
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func makeProject() -> Project {
        let job = Job(name: "Uni")
        let project = Project(name: "Lab")
        context.insert(job)
        context.insert(project)
        job.projects.append(project)
        return project
    }

    private func addEntry(_ project: Project, _ start: Date, hours: Double) -> WorkEntry {
        let entry = WorkEntry(date: start, startTime: start, endTime: start.addingTimeInterval(hours * 3600), taskDescription: "Work")
        context.insert(entry)
        project.entries.append(entry)
        return entry
    }

    func testCopyKeepsTimeOfDayAndProject() {
        let project = makeProject()
        let source = addEntry(project, date(2026, 10, 5, 9, 30), hours: 3)
        let created = CalendarService.copy([source], to: date(2026, 10, 12, 12), context: context, calendar: calendar)
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(created[0].startTime, date(2026, 10, 12, 9, 30))
        XCTAssertEqual(created[0].endTime, date(2026, 10, 12, 12, 30))
        XCTAssertEqual(created[0].project?.id, project.id)
    }

    func testPendingShiftDisappearsOnceLogged() {
        let project = makeProject()
        let monday = date(2026, 10, 5, 12) // a Monday
        let shift = RecurringShift(projectID: project.id, weekdays: [2], startMinutes: 9 * 60, endMinutes: 13 * 60,
                                   taskDescription: "Office", startsOn: date(2026, 9, 1))
        context.insert(shift)

        XCTAssertEqual(CalendarService.pendingShifts([shift], on: monday, entries: [], projectIDs: [project.id], calendar: calendar).count, 1)
        XCTAssertTrue(CalendarService.pendingShifts([shift], on: date(2026, 10, 6, 12), entries: [], projectIDs: [project.id], calendar: calendar).isEmpty)

        let entry = CalendarService.confirm(shift, on: monday, project: project, context: context, calendar: calendar)
        XCTAssertEqual(entry.durationHours, 4, accuracy: 0.001)
        XCTAssertTrue(CalendarService.pendingShifts([shift], on: monday, entries: [entry], projectIDs: [project.id], calendar: calendar).isEmpty)
    }

    func testSkippedShiftIsNotPlanned() {
        let shift = RecurringShift(projectID: UUID(), weekdays: [2], startMinutes: 540, endMinutes: 600,
                                   taskDescription: "", startsOn: date(2026, 9, 1))
        let monday = date(2026, 10, 5, 12)
        XCTAssertTrue(shift.isPlanned(on: monday, calendar: calendar))
        shift.skip(monday)
        XCTAssertFalse(shift.isPlanned(on: monday, calendar: calendar))
    }

    func testOvernightShiftDuration() {
        let shift = RecurringShift(projectID: UUID(), weekdays: [6], startMinutes: 22 * 60, endMinutes: 2 * 60,
                                   breakMinutes: 30, taskDescription: "")
        XCTAssertEqual(shift.durationHours, 3.5, accuracy: 0.001)
    }

    func testInsights() {
        let project = makeProject()
        let entries = [
            addEntry(project, date(2026, 10, 5, 9), hours: 8),
            addEntry(project, date(2026, 10, 6, 9), hours: 8),
            addEntry(project, date(2026, 10, 7, 9), hours: 6),
            addEntry(project, date(2026, 10, 20, 9), hours: 2),
            addEntry(project, date(2026, 9, 15, 9), hours: 10)
        ]
        let insights = CalendarService.insights(entries: entries, month: date(2026, 10, 1), weeklyLimit: 20, calendar: calendar)
        XCTAssertEqual(insights.totalHours, 24, accuracy: 0.001)
        XCTAssertEqual(insights.daysWorked, 4)
        XCTAssertEqual(insights.averagePerWorkedDay, 6, accuracy: 0.001)
        XCTAssertEqual(insights.longestDayHours, 8, accuracy: 0.001)
        XCTAssertEqual(insights.previousMonthHours, 10, accuracy: 0.001)
        XCTAssertEqual(insights.weeksOverLimit.count, 1)
        XCTAssertEqual(insights.weeksOverLimit.first?.hours ?? 0, 22, accuracy: 0.001)
    }

    func testExportPeriodDays() {
        let period = ExportService.ExportPeriod.days(date(2026, 10, 11, 15), date(2026, 10, 5, 8), calendar: calendar)
        XCTAssertFalse(period.isWholeMonth)
        XCTAssertTrue(period.contains(date(2026, 10, 5, 0, 1)))
        XCTAssertTrue(period.contains(date(2026, 10, 11, 23, 59)))
        XCTAssertFalse(period.contains(date(2026, 10, 12, 0, 1)))
    }
}
