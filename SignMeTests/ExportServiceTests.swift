import XCTest
import PDFKit
@testable import SignMe

final class ExportServiceTests: XCTestCase {

    // MARK: - CSV

    func testCSVEscaping() {
        XCTAssertEqual(ExportService.csvEscape("plain"), "plain")
        XCTAssertEqual(ExportService.csvEscape("a,b"), "\"a,b\"")
        XCTAssertEqual(ExportService.csvEscape("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(ExportService.csvEscape("line1\nline2"), "\"line1\nline2\"")
        XCTAssertEqual(ExportService.csvEscape("line1\r\nline2"), "\"line1\r\nline2\"")
        XCTAssertEqual(ExportService.csvEscape("a;b", separator: ";"), "\"a;b\"")
        XCTAssertEqual(ExportService.csvEscape("a,b", separator: ";"), "a,b")
    }

    func testCSVSeparatorFollowsDecimalSeparator() {
        XCTAssertEqual(ExportService.csvSeparator(for: Locale(identifier: "de_DE")), ";")
        XCTAssertEqual(ExportService.csvSeparator(for: Locale(identifier: "en_US")), ",")
    }

    func testCSVUsesISODatesBOMAndLocaleDecimals() {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9, minute: 0))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 17, minute: 0))!
        let entry = WorkEntry(date: start, startTime: start, endTime: end, breakMinutes: 30, taskDescription: "Prüfung; vorbereiten")

        let csv = ExportService.csv(for: [entry], locale: Locale(identifier: "de_DE"))
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}Job;Project;Date;Start;End Date;End;Break (min);Hours;Duration;Task Description\r\n"))

        let row = csv.components(separatedBy: "\r\n")[1]
        XCTAssertEqual(row, ";;2026-11-02;09:00;2026-11-02;17:00;30;7,50;7h 30m;\"Prüfung; vorbereiten\"")
    }

    func testSanitizedFilename() {
        XCTAssertEqual(ExportService.sanitizedFilename("a/b:c\\d.csv"), "a-b-c-d.csv")
        XCTAssertEqual(ExportService.sanitizedFilename("   "), "SignMe-Export")
    }

    // MARK: - PDF

    func testMonthPDFPaginatesAndRenders() throws {
        let job = Job(name: "Studienkolleg")
        let project = Project(name: "Tutoring")
        let calendar = Calendar.current
        let monthDate = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!

        let entries: [WorkEntry] = (0..<80).map { index in
            let day = calendar.date(byAdding: .day, value: index % 28, to: monthDate)!
            let start = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: day)!
            let end = calendar.date(byAdding: .hour, value: 4, to: start)!  // overnight shift
            return WorkEntry(date: start, startTime: start, endTime: end, breakMinutes: 15, taskDescription: "Entry \(index)")
        }

        let settings = TimesheetSettings(signerName: "Test Person", organization: "Org", includeSupervisorSignature: true)
        let data = ExportService.monthExportPDFData(job: job, project: project, monthDate: monthDate, entries: entries, settings: settings)

        XCTAssertTrue(data.starts(with: Array("%PDF".utf8)))
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThanOrEqual(document.pageCount, 2)

        let firstPage = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(firstPage.bounds(for: .mediaBox).width, 595.2, accuracy: 0.5, "Timesheet should be A4")

        let text = document.string ?? ""
        XCTAssertTrue(text.contains("Test Person"))
        XCTAssertTrue(text.contains("Studienkolleg"))
        XCTAssertTrue(text.contains("Page 1 of \(document.pageCount)"))
        XCTAssertTrue(text.contains("supervisor"))
    }
}
