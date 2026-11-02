import Foundation
import SwiftData
import SwiftUI

/// The logic behind the work calendar: grouping entries by day, copying days,
/// planned regular shifts, and month insights. Kept free of UI so it can be tested.
enum CalendarService {

    // MARK: - Grouping

    /// Entries within `month`, keyed by day of month.
    static func entriesByDay(_ entries: [WorkEntry], in month: Date, calendar: Calendar = .current) -> [Int: [WorkEntry]] {
        var result: [Int: [WorkEntry]] = [:]
        for entry in entries where calendar.isDate(entry.date, equalTo: month, toGranularity: .month) {
            result[calendar.component(.day, from: entry.date), default: []].append(entry)
        }
        return result
    }

    static func entries(_ entries: [WorkEntry], on day: Date, calendar: Calendar = .current) -> [WorkEntry] {
        entries.filter { calendar.isDate($0.date, inSameDayAs: day) }.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Copying days

    /// Copies `source` entries onto `targetDay`, keeping each entry's time of day,
    /// duration, break, description and project. Returns the new entries.
    @discardableResult
    static func copy(_ source: [WorkEntry], to targetDay: Date, context: ModelContext, calendar: Calendar = .current) -> [WorkEntry] {
        var created: [WorkEntry] = []
        for entry in source {
            guard let project = entry.project else { continue }
            let start = DateDurationService.combine(day: targetDay, time: entry.startTime, calendar: calendar)
            let end = start.addingTimeInterval(entry.endTime.timeIntervalSince(entry.startTime))
            let copy = WorkEntry(
                date: start,
                startTime: start,
                endTime: end,
                breakMinutes: entry.breakMinutes,
                taskDescription: entry.taskDescription
            )
            context.insert(copy)
            project.entries.append(copy)
            created.append(copy)
        }
        return created
    }

    // MARK: - Planned shifts

    /// Shifts planned on `day` that haven't been logged yet. A shift counts as logged
    /// when its project already has an entry that day starting within 5 minutes of it.
    static func pendingShifts(
        _ shifts: [RecurringShift],
        on day: Date,
        entries: [WorkEntry],
        projectIDs: Set<UUID>,
        calendar: Calendar = .current
    ) -> [RecurringShift] {
        let dayEntries = entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
        return shifts
            .filter { projectIDs.contains($0.projectID) && $0.isPlanned(on: day, calendar: calendar) }
            .filter { shift in
                let start = shift.interval(on: day, calendar: calendar).start
                return !dayEntries.contains { entry in
                    entry.project?.id == shift.projectID && abs(entry.startTime.timeIntervalSince(start)) < 5 * 60
                }
            }
            .sorted { $0.startMinutes < $1.startMinutes }
    }

    /// Turns a planned shift into a real entry on `day`.
    @discardableResult
    static func confirm(_ shift: RecurringShift, on day: Date, project: Project, context: ModelContext, calendar: Calendar = .current) -> WorkEntry {
        let interval = shift.interval(on: day, calendar: calendar)
        let entry = WorkEntry(
            date: interval.start,
            startTime: interval.start,
            endTime: interval.end,
            breakMinutes: shift.breakMinutes,
            taskDescription: shift.taskDescription
        )
        context.insert(entry)
        project.entries.append(entry)
        return entry
    }

    // MARK: - Insights

    struct WeekTotal: Identifiable, Equatable {
        var id: Date { weekStart }
        let weekStart: Date
        let hours: Double
    }

    struct MonthInsights: Equatable {
        var totalHours: Double
        var daysWorked: Int
        var averagePerWorkedDay: Double
        var longestDay: Date?
        var longestDayHours: Double
        var previousMonthHours: Double
        /// Weeks touching this month whose total (all days of the week) is over the limit.
        var weeksOverLimit: [WeekTotal]

        var changeFromPreviousMonth: Double { totalHours - previousMonthHours }
    }

    static func insights(
        entries: [WorkEntry],
        month: Date,
        weeklyLimit: Double,
        calendar: Calendar = .current
    ) -> MonthInsights {
        let byDay = entriesByDay(entries, in: month, calendar: calendar)
        let dayTotals = byDay.mapValues { $0.reduce(0) { $0 + $1.durationHours } }
        let total = dayTotals.values.reduce(0, +)
        let worked = dayTotals.filter { $0.value > 0 }
        let longest = worked.max { $0.value < $1.value }

        var longestDate: Date?
        if let longest {
            var components = calendar.dateComponents([.year, .month], from: month)
            components.day = longest.key
            longestDate = calendar.date(from: components)
        }

        let previousMonth = calendar.date(byAdding: .month, value: -1, to: month) ?? month
        let previousTotal = entries
            .filter { calendar.isDate($0.date, equalTo: previousMonth, toGranularity: .month) }
            .reduce(0) { $0 + $1.durationHours }

        var overLimit: [WeekTotal] = []
        if weeklyLimit > 0, let monthInterval = calendar.dateInterval(of: .month, for: month) {
            var weekStart = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start)?.start ?? monthInterval.start
            while weekStart < monthInterval.end {
                let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                let hours = entries
                    .filter { $0.date >= weekStart && $0.date < weekEnd }
                    .reduce(0) { $0 + $1.durationHours }
                if hours > weeklyLimit + 0.001 {
                    overLimit.append(WeekTotal(weekStart: weekStart, hours: hours))
                }
                weekStart = weekEnd
            }
        }

        return MonthInsights(
            totalHours: total,
            daysWorked: worked.count,
            averagePerWorkedDay: worked.isEmpty ? 0 : total / Double(worked.count),
            longestDay: longestDate,
            longestDayHours: longest?.value ?? 0,
            previousMonthHours: previousTotal,
            weeksOverLimit: overLimit
        )
    }
}

// MARK: - Project colors

/// Distinct colors for telling projects apart on the calendar (dots and legend).
/// Assigned in project creation order, so a project keeps its color.
enum ProjectColors {
    static let palette: [Color] = [
        Color(hex: 0x3B6FD8), Color(hex: 0xC2643A), Color(hex: 0x2E8B62), Color(hex: 0x8E5BC9),
        Color(hex: 0xC24F6E), Color(hex: 0x1F8A9B), Color(hex: 0xB08A1E), Color(hex: 0x6B7280)
    ]

    static func map(for projects: [Project]) -> [UUID: Color] {
        let ordered = projects.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        var result: [UUID: Color] = [:]
        for (index, project) in ordered.enumerated() {
            result[project.id] = palette[index % palette.count]
        }
        return result
    }
}
