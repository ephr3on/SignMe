import XCTest
@testable import SignMe

final class DateDurationServiceTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    // MARK: - combine / resolveInterval

    func testCombineUsesDayFromFirstAndTimeFromSecondAndDropsSeconds() {
        let combined = DateDurationService.combine(
            day: date(2026, 11, 1, 23, 59),
            time: date(2020, 1, 1, 9, 15, 42),
            calendar: calendar
        )
        XCTAssertEqual(combined, date(2026, 11, 1, 9, 15, 0))
    }

    func testSameDayIntervalStaysOnSameDay() {
        let interval = DateDurationService.resolveInterval(
            day: date(2026, 11, 2),
            start: date(2000, 1, 1, 9, 0),
            end: date(2000, 1, 1, 17, 0),
            calendar: calendar
        )
        XCTAssertEqual(interval.start, date(2026, 11, 2, 9, 0))
        XCTAssertEqual(interval.end, date(2026, 11, 2, 17, 0))
        XCTAssertFalse(DateDurationService.spansMidnight(start: interval.start, end: interval.end, calendar: calendar))
    }

    func testOvernightShiftEndsNextDay() {
        let interval = DateDurationService.resolveInterval(
            day: date(2026, 11, 2),
            start: date(2000, 1, 1, 22, 0),
            end: date(2000, 1, 1, 2, 0),
            calendar: calendar
        )
        XCTAssertEqual(interval.start, date(2026, 11, 2, 22, 0))
        XCTAssertEqual(interval.end, date(2026, 11, 3, 2, 0))
        XCTAssertTrue(DateDurationService.isValid(start: interval.start, end: interval.end))
        XCTAssertTrue(DateDurationService.spansMidnight(start: interval.start, end: interval.end, calendar: calendar))
        XCTAssertEqual(DateDurationService.durationHours(from: interval.start, to: interval.end), 4, accuracy: 0.0001)
    }

    func testIdenticalStartAndEndIsInvalid() {
        let interval = DateDurationService.resolveInterval(
            day: date(2026, 11, 2),
            start: date(2000, 1, 1, 9, 0),
            end: date(2000, 1, 1, 9, 0),
            calendar: calendar
        )
        XCTAssertFalse(DateDurationService.isValid(start: interval.start, end: interval.end))
    }

    // MARK: - Duration

    func testBreakIsSubtracted() {
        let hours = DateDurationService.durationHours(from: date(2026, 11, 2, 9), to: date(2026, 11, 2, 17), breakMinutes: 30)
        XCTAssertEqual(hours, 7.5, accuracy: 0.0001)
    }

    func testDurationNeverNegative() {
        XCTAssertEqual(DateDurationService.durationHours(from: date(2026, 11, 2, 9), to: date(2026, 11, 2, 10), breakMinutes: 90), 0)
        XCTAssertEqual(DateDurationService.durationHours(from: date(2026, 11, 2, 10), to: date(2026, 11, 2, 9)), 0)
    }

    func testFormattedDuration() {
        XCTAssertEqual(DateDurationService.formattedDuration(hours: 1.5), "1h 30min")
        XCTAssertEqual(DateDurationService.formattedDuration(hours: 0.75), "45min")
        XCTAssertEqual(DateDurationService.formattedDuration(hours: 2), "2h")
        XCTAssertEqual(DateDurationService.formattedDuration(hours: 0), "0min")
        XCTAssertEqual(DateDurationService.formattedDuration(hours: .nan), "0min")
    }

    func testFormattedDecimalHoursIsLocaleAware() {
        XCTAssertEqual(DateDurationService.formattedDecimalHours(7.5, locale: Locale(identifier: "de_DE")), "7,50")
        XCTAssertEqual(DateDurationService.formattedDecimalHours(7.5, locale: Locale(identifier: "en_US")), "7.50")
        XCTAssertEqual(DateDurationService.formattedDecimalHours(1234.25, locale: Locale(identifier: "en_US")), "1234.25")
    }
}
