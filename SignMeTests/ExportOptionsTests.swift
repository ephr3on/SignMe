import XCTest
import SwiftData
@testable import SignMe

@MainActor
final class ExportOptionsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    override func setUp() async throws {
        let schema = Schema([Job.self, Project.self, WorkEntry.self, SavedSignature.self, RecurringShift.self, PlannedTask.self, ExportTemplate.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = container.mainContext
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func project(_ name: String = "Events", entries: [(Date, Double)]) -> Project {
        let job = Job(name: "Kolleg")
        let project = Project(name: name)
        context.insert(job); context.insert(project)
        job.projects.append(project)
        for (start, hours) in entries {
            let entry = WorkEntry(date: start, startTime: start, endTime: start.addingTimeInterval(hours * 3600), taskDescription: "Work")
            context.insert(entry)
            project.entries.append(entry)
        }
        return project
    }

    func testRangePresets() {
        let now = date(2026, 11, 4) // Wednesday
        var o = ExportOptions()
        o.range = .thisMonth
        XCTAssertTrue(o.period(now: now, calendar: calendar).isWholeMonth)
        o.range = .lastMonth
        XCTAssertEqual(calendar.component(.month, from: o.period(now: now, calendar: calendar).firstDay), 10)
        o.range = .thisWeek
        let week = o.period(now: now, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: week.firstDay), 2)   // Monday 2 Nov
        XCTAssertEqual(calendar.component(.day, from: week.lastDay), 8)
        o.range = .lastWeek
        XCTAssertEqual(calendar.component(.day, from: o.period(now: now, calendar: calendar).firstDay), 26)
        o.range = .last30Days
        let last30 = o.period(now: now, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.day], from: last30.interval.start, to: last30.interval.end).day, 30)
        o.range = .custom
        o.customStart = date(2026, 10, 5)
        o.customEnd = date(2026, 10, 11)
        XCTAssertFalse(o.period(now: now, calendar: calendar).isWholeMonth)
    }

    func testDecodingFillsMissingKeysAndSkipsUnknownColumns() throws {
        let json = #"{"range":"lastMonth","columns":["date","teleport","decimalHours","date"],"language":"german"}"#
        let o = try JSONDecoder().decode(ExportOptions.self, from: Data(json.utf8))
        XCTAssertEqual(o.range, .lastMonth)
        XCTAssertEqual(o.language, .german)
        XCTAssertEqual(o.columns, [.date, .decimalHours])
        XCTAssertTrue(o.showTotal)
        XCTAssertEqual(o.format, .pdf)
    }

    func testTemplateRoundTripDropsOneOffSignatureDate() {
        var o = ExportOptions()
        o.signatureDate = .custom
        o.columns = [.date, .description]
        let template = ExportTemplate(name: "Monthly", options: o)
        XCTAssertEqual(template.options.signatureDate, .exportDay)
        XCTAssertEqual(template.options.columns, [.date, .description])
    }

    func testGermanCSVWithDailyRowsEmptyDaysAndSubtotals() {
        let p = project(entries: [(date(2026, 10, 5, 9), 2), (date(2026, 10, 5, 14), 1.5), (date(2026, 10, 7, 9), 3)])
        var o = ExportOptions()
        o.range = .custom
        o.customStart = date(2026, 10, 5)
        o.customEnd = date(2026, 10, 7)
        o.language = .german
        o.columns = [.date, .decimalHours]
        o.groupByDay = true
        o.includeEmptyDays = true
        o.weeklySubtotals = true
        let csv = TimesheetExporter.csv(options: o, entries: p.entries, projects: [p], period: o.period(calendar: calendar), calendar: calendar)
        let lines = csv.dropFirst().split(separator: "\r\n").map(String.init)
        XCTAssertEqual(lines.first, "Datum;Stunden")
        XCTAssertEqual(lines[1], "2026-10-05;3,50")   // two entries combined
        XCTAssertEqual(lines[2], "2026-10-06;")       // empty day
        XCTAssertEqual(lines[3], "2026-10-07;3,00")
        XCTAssertTrue(lines[4].hasPrefix("KW 41;6,50"))
        XCTAssertEqual(lines[5], "Gesamt;6,50")
    }

    func testProjectScopeAndGrouping() {
        let a = project("A", entries: [(date(2026, 10, 5, 9), 2)])
        let b = project("B", entries: [(date(2026, 10, 6, 9), 1)])
        let c = project("C", entries: [])
        var o = ExportOptions()
        o.range = .custom
        o.customStart = date(2026, 10, 1)
        o.customEnd = date(2026, 10, 31)
        let period = o.period(calendar: calendar)
        XCTAssertEqual(Set(TimesheetExporter.projects(for: o, from: [a, b, c], period: period).map(\.name)), ["A", "B"])
        o.projectScope = .chosen
        o.projectIDs = [b.id, c.id]
        XCTAssertEqual(TimesheetExporter.projects(for: o, from: [a, b, c], period: period).map(\.name), ["B"])
        o.includeEmptyDays = true
        XCTAssertEqual(TimesheetExporter.projects(for: o, from: [a, b, c], period: period).count, 2)

        o.projectScope = .withHours
        o.format = .csv
        o.grouping = .combined
        XCTAssertEqual(TimesheetExporter.documents(options: o, projects: [a, b, c], signature: nil, calendar: calendar).count, 1)
        o.grouping = .perProject
        XCTAssertEqual(TimesheetExporter.documents(options: o, projects: [a, b, c], signature: nil, calendar: calendar).count, 2)
    }

    func testPDFRendersInBothOrientations() {
        let p = project(entries: [(date(2026, 10, 5, 9), 2)])
        var o = ExportOptions()
        o.range = .custom
        o.customStart = date(2026, 10, 1)
        o.customEnd = date(2026, 10, 31)
        for orientation in ExportOptions.Orientation.allCases {
            o.orientation = orientation
            let data = TimesheetExporter.pdf(options: o, entries: p.entries, projects: [p], period: o.period(calendar: calendar), signature: nil, calendar: calendar)
            XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        }
    }
}
