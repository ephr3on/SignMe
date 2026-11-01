import Foundation

/// Centralizes every date, time, and duration calculation/formatting rule
/// used across the app so views never re-implement this logic.
enum DateDurationService {

    // MARK: - Duration math

    /// Worked hours between `start` and `end`, minus an optional unpaid break.
    static func durationHours(from start: Date, to end: Date, breakMinutes: Int = 0) -> Double {
        let seconds = end.timeIntervalSince(start) - Double(max(0, breakMinutes)) * 60
        return max(0, seconds / 3600)
    }

    static func isValid(start: Date, end: Date) -> Bool {
        end > start
    }

    /// Combines the calendar day of `day` with the hour and minute of `time`
    /// (seconds are dropped so durations come out in whole minutes).
    /// Used so the Date/Start/End pickers in the entry form always agree on which day they describe.
    static func combine(day: Date, time: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = 0
        return calendar.date(from: components) ?? day
    }

    /// Turns the entry form's Date/Start/End pickers into a concrete interval.
    /// If the end time-of-day is earlier than the start, the shift is treated as
    /// running past midnight and the end moves to the next day (e.g. 22:00–02:00).
    /// Identical start and end times produce a zero-length (invalid) interval.
    static func resolveInterval(day: Date, start: Date, end: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let resolvedStart = combine(day: day, time: start, calendar: calendar)
        var resolvedEnd = combine(day: day, time: end, calendar: calendar)
        if resolvedEnd < resolvedStart {
            resolvedEnd = calendar.date(byAdding: .day, value: 1, to: resolvedEnd) ?? resolvedEnd
        }
        return (resolvedStart, resolvedEnd)
    }

    /// True when an entry's end falls on a later calendar day than its start.
    static func spansMidnight(start: Date, end: Date, calendar: Calendar = .current) -> Bool {
        end > start && !calendar.isDate(start, inSameDayAs: end)
    }

    /// Formats hours as a short, human-readable duration string, e.g. "1h 30m", "45m", "2h".
    static func formattedDuration(hours: Double) -> String {
        guard hours.isFinite, hours > 0 else { return "0m" }
        let totalMinutes = Int((hours * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        switch (h, m) {
        case (0, let m): return "\(m)m"
        case (let h, 0): return "\(h)h"
        default: return "\(h)h \(m)m"
        }
    }

    /// Formats hours as a locale-aware decimal number with two fraction digits,
    /// e.g. "7.50" (English) or "7,50" (German) — the format payroll and invoices expect.
    static func formattedDecimalHours(_ hours: Double, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: hours)) ?? String(format: "%.2f", hours)
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

    /// Numeric date written next to a signature, e.g. "30.10.2026" (German) or "10/30/2026" (US).
    static let signatureDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("ddMMyyyy")
        return formatter
    }()

    /// Machine-readable date for CSV files and filenames, e.g. "2026-11-01".
    static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Machine-readable 24-hour time for CSV files, e.g. "09:30".
    static let isoTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
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
