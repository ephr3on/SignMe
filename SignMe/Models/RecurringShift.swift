import Foundation
import SwiftData

/// A regular shift, e.g. "Office hours, Tuesdays and Thursdays 09:00–13:00".
/// It shows on the calendar as a planned block on matching days; one tap confirms
/// it as a real WorkEntry, or it can be skipped for a single day.
@Model
final class RecurringShift {
    var id: UUID
    /// The project the shift belongs to (looked up by id; templates of deleted projects are ignored).
    var projectID: UUID
    /// Calendar weekdays (1 = Sunday … 7 = Saturday), stored as "3,5".
    var weekdaysRaw: String
    var startMinutes: Int
    var endMinutes: Int
    var breakMinutes: Int
    var taskDescription: String
    var isActive: Bool
    /// First day the shift applies.
    var startsOn: Date
    /// Days skipped once ("yyyy-MM-dd", comma-separated).
    var skippedDaysRaw: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        projectID: UUID,
        weekdays: Set<Int>,
        startMinutes: Int,
        endMinutes: Int,
        breakMinutes: Int = 0,
        taskDescription: String,
        isActive: Bool = true,
        startsOn: Date = Calendar.current.startOfDay(for: .now),
        createdAt: Date = .now
    ) {
        self.id = id
        self.projectID = projectID
        self.weekdaysRaw = weekdays.sorted().map(String.init).joined(separator: ",")
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.breakMinutes = breakMinutes
        self.taskDescription = taskDescription
        self.isActive = isActive
        self.startsOn = startsOn
        self.skippedDaysRaw = ""
        self.createdAt = createdAt
    }

    var weekdays: Set<Int> {
        get { Set(weekdaysRaw.split(separator: ",").compactMap { Int($0) }) }
        set { weekdaysRaw = newValue.sorted().map(String.init).joined(separator: ",") }
    }

    private var skippedDays: Set<String> {
        get { Set(skippedDaysRaw.split(separator: ",").map(String.init)) }
        set { skippedDaysRaw = newValue.sorted().joined(separator: ",") }
    }

    func isSkipped(on day: Date) -> Bool {
        skippedDays.contains(DateDurationService.isoDateFormatter.string(from: day))
    }

    func skip(_ day: Date) {
        skippedDays.insert(DateDurationService.isoDateFormatter.string(from: day))
    }

    /// Whether this shift is planned for `day` (active, on a matching weekday, from its start date, not skipped).
    func isPlanned(on day: Date, calendar: Calendar = .current) -> Bool {
        guard isActive, calendar.startOfDay(for: day) >= calendar.startOfDay(for: startsOn) else { return false }
        guard weekdays.contains(calendar.component(.weekday, from: day)) else { return false }
        return !isSkipped(on: day)
    }

    /// The concrete interval on `day`; a shift ending before it starts runs past midnight.
    func interval(on day: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let midnight = calendar.startOfDay(for: day)
        let start = calendar.date(byAdding: .minute, value: startMinutes, to: midnight) ?? midnight
        var end = calendar.date(byAdding: .minute, value: endMinutes, to: midnight) ?? midnight
        if end <= start { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
        return (start, end)
    }

    var durationHours: Double {
        let span = endMinutes > startMinutes ? endMinutes - startMinutes : endMinutes + 24 * 60 - startMinutes
        return max(0, Double(span - breakMinutes) / 60)
    }

    /// "09:00–13:00"
    var timeRangeText: String {
        func text(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
        return "\(text(startMinutes))–\(text(endMinutes))"
    }

    /// "Tue, Thu"
    var weekdaysText: String {
        let calendar = Calendar.current
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let ordered = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        return ordered.filter { weekdays.contains($0) }.map { symbols[$0 - 1] }.joined(separator: ", ")
    }
}
