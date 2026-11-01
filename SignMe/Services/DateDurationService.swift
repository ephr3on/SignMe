import Foundation

/// Centralizes every date, time, and duration calculation/formatting rule
/// used across the app so views never re-implement this logic.
enum DateDurationService {

    // MARK: - Duration math

    static func durationHours(from start: Date, to end: Date) -> Double {
        max(0, end.timeIntervalSince(start) / 3600)
    }

    static func isValid(start: Date, end: Date) -> Bool {
        end > start
    }

    /// Combines the calendar day of `day` with the time-of-day of `time`.
    /// Used so the Date/Start/End pickers in the entry form always agree on which day they describe.
    static func combine(day: Date, time: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second
        return calendar.date(from: components) ?? day
    }

    /// Formats hours as a short, human-readable duration string, e.g. "1h 30m", "45m", "2h".
    static func formattedDuration(hours: Double) -> String {
        guard hours.isFinite, hours > 0 else { return "0m" }
        let totalMinutes = Int((hours * 3600).rounded()) / 60
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        switch (h, m) {
        case (0, let m): return "\(m)m"
        case (let h, 0): return "\(h)h"
        default: return "\(h)h \(m)m"
        }
    }

    // MARK: - Formatters

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    static let monthNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"
        return formatter
    }()

    /// Full month names for a month-picker (index 0 = January).
    static let monthNames: [String] = DateFormatter().standaloneMonthSymbols

    static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
