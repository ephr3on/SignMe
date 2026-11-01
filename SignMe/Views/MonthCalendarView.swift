import SwiftUI

/// A project's month as a calendar: each day shows its hours, shaded in gold by
/// how much was worked. Tapping a day lists its entries below, with an Add button.
struct MonthCalendarView: View {
    let project: Project
    @Binding var month: Date
    @Binding var selectedDay: Date
    var onAdd: (Date) -> Void
    var onEdit: (WorkEntry) -> Void

    private var calendar: Calendar { Calendar.current }

    private var monthEntries: [WorkEntry] {
        project.entries.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    private var hoursByDay: [Int: Double] {
        var result: [Int: Double] = [:]
        for entry in monthEntries {
            result[calendar.component(.day, from: entry.date), default: 0] += entry.durationHours
        }
        return result
    }

    private var monthTotal: Double { monthEntries.reduce(0) { $0 + $1.durationHours } }

    /// Grid cells: nil for the blank days before the 1st, then the day numbers.
    private var cells: [Int?] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let firstDay = calendar.dateInterval(of: .month, for: month)?.start else { return [] }
        let weekdayOfFirst = calendar.component(.weekday, from: firstDay)
        let leading = (weekdayOfFirst - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.map { Optional($0) }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private var selectedDayEntries: [WorkEntry] {
        project.entries
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDay) }
            .sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                monthHeader
                grid
                daySection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: Header

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left").font(.app(.body, .semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous month")
            Spacer()
            VStack(spacing: 2) {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(Theme.display(.title3))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(DateDurationService.formattedDuration(hours: monthTotal)) · \(DateDurationService.formattedDecimalHours(monthTotal)) h · \(hoursByDay.count) \(hoursByDay.count == 1 ? "day" : "days")")
                    .font(.app(.footnote))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
            Spacer()
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right").font(.app(.body, .semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Next month")
        }
        .foregroundStyle(Theme.gold)
    }

    // MARK: Grid

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let hours = hoursByDay
        return VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol.uppercased())
                        .font(.app(.caption2, .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day, hours: hours[day] ?? 0)
                    } else {
                        Color.clear.frame(height: 50)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Int, hours: Double) -> some View {
        let date = dateFor(day)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(date)
        let intensity = 0.12 + min(hours, 6) / 6 * 0.28

        return Button {
            selectedDay = date
        } label: {
            VStack(spacing: 4) {
                Text("\(day)")
                    .font(.app(.subheadline, .semibold))
                Text(hours > 0 ? compactHours(hours) : " ")
                    .font(.appSize(11, .semibold, relativeTo: .caption2))
                    .monospacedDigit()
            }
            .foregroundStyle(isSelected ? Theme.onGold : (hours > 0 ? Theme.textPrimary : Theme.textTertiary))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Theme.goldFill : (hours > 0 ? Theme.goldFill.opacity(intensity) : Theme.dayEmpty))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isToday && !isSelected ? Theme.gold : Color.clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(hours > 0 ? DateDurationService.formattedDuration(hours: hours) : "No entries")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Selected day

    private var daySection: some View {
        let entries = selectedDayEntries
        let dayTotal = entries.reduce(0) { $0 + $1.durationHours }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                (Text(selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .foregroundStyle(Theme.textPrimary)
                 + Text(dayTotal > 0 ? "  · \(DateDurationService.formattedDuration(hours: dayTotal))" : "")
                    .foregroundStyle(Theme.gold))
                    .font(.app(.headline))
                Spacer()
                Button {
                    onAdd(selectedDay)
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.app(.subheadline, .bold))
                        .frame(minHeight: 44)
                }
                .foregroundStyle(Theme.gold)
            }

            if entries.isEmpty {
                Text("No entries on this day.")
                    .font(.app(.subheadline))
                    .foregroundStyle(Theme.textSecondary)
                    .card(padding: 14, radius: 16)
            } else {
                ForEach(entries) { entry in
                    Button {
                        onEdit(entry)
                    } label: {
                        EntryRowView(entry: entry)
                            .card(padding: 12, radius: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Helpers

    private func dateFor(_ day: Int) -> Date {
        var components = calendar.dateComponents([.year, .month], from: month)
        components.day = day
        components.hour = 12
        return calendar.date(from: components) ?? month
    }

    private func compactHours(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : String(format: "%d:%02d", h, m)
    }

    private func shiftMonth(_ delta: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: delta, to: month) else { return }
        month = newMonth
        // Keep a sensible selection: today if it's in that month, otherwise the 1st.
        if calendar.isDate(.now, equalTo: newMonth, toGranularity: .month) {
            selectedDay = .now
        } else {
            selectedDay = calendar.dateInterval(of: .month, for: newMonth)?.start ?? newMonth
        }
    }
}
