import SwiftUI
import SwiftData

/// The work calendar — for all projects (Home › Calendar) or for one project
/// (a project's Calendar tab).
/// - Each day shows its hours and a coloured dot per project worked; days are shaded by hours.
/// - Days with a regular shift still to log get a dashed outline.
/// - Tap a day for its entries, planned shifts and quick actions. Long-press a day for
///   the same actions: add an entry, copy the previous day, repeat last week, export.
/// - "Choose days" selects a range on the calendar to export as signed PDFs or CSV.
/// - Month insights below: total vs target, days worked, average, longest day,
///   change from last month and weeks over your weekly limit.
struct WorkCalendarView: View {
    /// nil = all projects.
    var project: Project? = nil

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Job.createdAt) private var jobs: [Job]
    @Query(sort: \WorkEntry.startTime) private var allEntries: [WorkEntry]
    @Query(sort: \RecurringShift.createdAt) private var shifts: [RecurringShift]
    @AppStorage(AppSettings.Keys.monthlyTargetHours) private var monthlyTarget = AppSettings.Defaults.monthlyTargetHours
    @AppStorage(AppSettings.Keys.weeklyLimitHours) private var weeklyLimit = AppSettings.Defaults.weeklyLimitHours

    @State private var month: Date = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selectedDay: Date = .now
    @State private var focusedProjectID: UUID?

    @State private var isChoosingRange = false
    @State private var rangeStart: Date?
    @State private var rangeEnd: Date?

    @State private var addEntryItem: DayItem?
    @State private var entryToEdit: WorkEntry?
    @State private var exportItem: PeriodItem?
    @State private var showingShifts = false
    @State private var undo: UndoBanner?

    private var calendar: Calendar { Calendar.current }

    // MARK: - Data

    private var allProjects: [Project] { jobs.flatMap(\.projects) }

    private var projectColors: [UUID: Color] { ProjectColors.map(for: allProjects) }

    /// Entries this calendar shows (one project, or all — narrowed by the legend focus).
    private var entries: [WorkEntry] {
        allEntries.filter { entry in
            guard let entryProject = entry.project else { return false }
            if let project { return entryProject.id == project.id }
            if let focusedProjectID { return entryProject.id == focusedProjectID }
            return true
        }
    }

    private var visibleProjectIDs: Set<UUID> {
        if let project { return [project.id] }
        if let focusedProjectID { return [focusedProjectID] }
        return Set(allProjects.map(\.id))
    }

    private var byDay: [Int: [WorkEntry]] { CalendarService.entriesByDay(entries, in: month) }

    private var cells: [Int?] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let firstDay = calendar.dateInterval(of: .month, for: month)?.start else { return [] }
        let leading = (calendar.component(.weekday, from: firstDay) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.map { Optional($0) }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private func dateFor(_ day: Int) -> Date {
        var components = calendar.dateComponents([.year, .month], from: month)
        components.day = day
        components.hour = 12
        return calendar.date(from: components) ?? month
    }

    private func pending(on day: Date) -> [RecurringShift] {
        CalendarService.pendingShifts(shifts, on: day, entries: allEntries, projectIDs: visibleProjectIDs)
    }

    private func findProject(id: UUID) -> Project? { allProjects.first { $0.id == id } }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                monthHeader
                exportStrip
                grid
                if project == nil { legend }
                if !isChoosingRange { daySection }
                insightsCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if let undo { undoBar(undo) }
                if isChoosingRange { rangeBar }
            }
            .animation(.easeInOut(duration: 0.2), value: undo?.id)
            .animation(.easeInOut(duration: 0.2), value: isChoosingRange)
        }
        .sheet(item: $addEntryItem) { item in
            EntryFormView(project: project, initialDate: item.date)
        }
        .sheet(item: $entryToEdit) { entry in
            EntryFormView(entryToEdit: entry)
        }
        .sheet(item: $exportItem) { item in
            ExportMonthSheet(jobs: jobs, initialProject: project, period: item.period)
        }
        .sheet(isPresented: $showingShifts) {
            NavigationStack {
                ShiftTemplatesView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingShifts = false }
                        }
                    }
            }
            .environment(\.tabBarInset, 0)
        }
    }

    // MARK: Header

    private var monthHeader: some View {
        let total = entries.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
            .reduce(0) { $0 + $1.durationHours }
        return HStack {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left").font(.app(.body, .semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous month")
            Spacer()
            VStack(spacing: 2) {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(Theme.display(.title3))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(DateDurationService.formattedDuration(hours: total)) · \(DateDurationService.formattedDecimalHours(total)) h")
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

    private var exportStrip: some View {
        HStack(spacing: 8) {
            Menu {
                Button("This day", systemImage: "sun.max") { exportItem = PeriodItem(period: .days(selectedDay, selectedDay)) }
                Button("This week", systemImage: "calendar") { exportWeek(of: selectedDay) }
                Button("Whole month", systemImage: "calendar.badge.clock") { exportItem = PeriodItem(period: .month(month)) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up").font(.app(.footnote, .semibold))
                    Text("Export").font(.app(.subheadline, .semibold))
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .overlay(Capsule().strokeBorder(Theme.textPrimary.opacity(0.22), lineWidth: 1))
                .contentShape(Capsule())
            }
            ChoiceChip(title: "Select days", systemImage: "hand.tap", isSelected: isChoosingRange) {
                withAnimation {
                    if isChoosingRange {
                        cancelRange()
                    } else {
                        isChoosingRange = true
                        rangeStart = nil
                        rangeEnd = nil
                    }
                }
            }
            Spacer(minLength: 0)
            Button { showingShifts = true } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.app(.body, .semibold))
                    .foregroundStyle(Theme.gold)
                    .frame(width: 44, height: 40)
            }
            .accessibilityLabel("Regular shifts")
        }
    }

    // MARK: Grid

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let dayMap = byDay
        let colors = projectColors
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
                        dayCell(day, entries: dayMap[day] ?? [], colors: colors)
                    } else {
                        Color.clear.frame(height: 58)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Int, entries dayEntries: [WorkEntry], colors: [UUID: Color]) -> some View {
        let date = dateFor(day)
        let hours = dayEntries.reduce(0) { $0 + $1.durationHours }
        let isToday = calendar.isDateInToday(date)
        let isSelected = !isChoosingRange && calendar.isDate(date, inSameDayAs: selectedDay)
        let inRange = isInRange(date)
        let isRangeEdge = isRangeEndpoint(date)
        let hasPending = !pending(on: date).isEmpty
        let projectIDs = Array(Set(dayEntries.compactMap { $0.project?.id })).sorted { $0.uuidString < $1.uuidString }
        let intensity = 0.12 + min(hours, 6) / 6 * 0.28
        let filled = isSelected || isRangeEdge

        let background: Color = filled ? Theme.goldFill
            : inRange ? Theme.goldFill.opacity(0.32)
            : hours > 0 ? Theme.goldFill.opacity(intensity)
            : Theme.dayEmpty

        return Button {
            tap(date)
        } label: {
            VStack(spacing: 3) {
                Text("\(day)")
                    .font(.app(.subheadline, .semibold))
                Text(hours > 0 ? compactHours(hours) : " ")
                    .font(.appSize(11, .semibold, relativeTo: .caption2))
                    .monospacedDigit()
                HStack(spacing: 2) {
                    ForEach(projectIDs.prefix(3), id: \.self) { id in
                        Circle()
                            .fill(colors[id] ?? Theme.textTertiary)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
                .opacity(project == nil ? 1 : 0)
            }
            .foregroundStyle(filled ? Theme.onGold : (hours > 0 ? Theme.textPrimary : Theme.textTertiary))
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(background))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        hasPending && !filled ? Theme.gold : (isToday && !filled ? Theme.gold : Color.clear),
                        style: StrokeStyle(lineWidth: 1.5, dash: hasPending && !filled ? [4, 3] : [])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu { dayActions(for: date) }
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(accessibilityValue(hours: hours, pending: hasPending))
        .accessibilityAddTraits(isSelected || isRangeEdge ? .isSelected : [])
    }

    private func accessibilityValue(hours: Double, pending: Bool) -> String {
        var parts: [String] = [hours > 0 ? DateDurationService.formattedDuration(hours: hours) : "No entries"]
        if pending { parts.append("regular shift to log") }
        return parts.joined(separator: ", ")
    }

    // MARK: Legend (all projects)

    @ViewBuilder
    private var legend: some View {
        let monthEntries = allEntries.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
        let active = allProjects.filter { project in monthEntries.contains { $0.project?.id == project.id } }
        if !active.isEmpty {
            let colors = projectColors
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(active) { item in
                        let hours = monthEntries.filter { $0.project?.id == item.id }.reduce(0) { $0 + $1.durationHours }
                        let isFocused = focusedProjectID == item.id
                        Button {
                            withAnimation { focusedProjectID = isFocused ? nil : item.id }
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(colors[item.id] ?? Theme.textTertiary).frame(width: 9, height: 9)
                                Text(item.name)
                                    .font(.app(.footnote, .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Text(DateDurationService.formattedDuration(hours: hours))
                                    .font(.app(.footnote))
                                    .foregroundStyle(Theme.textSecondary)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .background(Capsule().fill(isFocused ? Theme.goldFill.opacity(0.18) : Theme.surface))
                            .overlay(Capsule().strokeBorder(isFocused ? Theme.gold : Theme.cardBorder, lineWidth: isFocused ? 1.5 : 1))
                        }
                        .buttonStyle(.plain)
                        .opacity(focusedProjectID == nil || isFocused ? 1 : 0.55)
                        .accessibilityLabel("\(item.name), \(DateDurationService.formattedDuration(hours: hours))")
                        .accessibilityHint(isFocused ? "Shows all projects again" : "Shows only this project")
                    }
                }
            }
        }
    }

    // MARK: Selected day

    private var daySection: some View {
        let dayEntries = CalendarService.entries(entries, on: selectedDay)
        let planned = pending(on: selectedDay)
        let total = dayEntries.reduce(0) { $0 + $1.durationHours }
        let colors = projectColors
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                (Text(selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .foregroundStyle(Theme.textPrimary)
                 + Text(total > 0 ? "  · \(DateDurationService.formattedDuration(hours: total))" : "")
                    .foregroundStyle(Theme.gold))
                    .font(.app(.headline))
                Spacer()
                Menu {
                    dayActions(for: selectedDay)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.app(.title3))
                        .foregroundStyle(Theme.gold)
                        .frame(width: 44, height: 36)
                }
                .accessibilityLabel("Actions for this day")
            }

            HStack(spacing: 8) {
                quickButton("Add", icon: "plus") { addEntryItem = DayItem(date: selectedDay) }
                quickButton("Copy previous day", icon: "doc.on.doc") { copyPreviousDay(to: selectedDay) }
                    .disabled(sourceEntries(daysBefore: 1, target: selectedDay).isEmpty)
                quickButton("Repeat last week", icon: "arrow.uturn.backward") { repeatLastWeek(on: selectedDay) }
                    .disabled(sourceEntries(daysBefore: 7, target: selectedDay).isEmpty)
            }

            ForEach(planned) { shift in
                plannedRow(shift)
            }

            if dayEntries.isEmpty && planned.isEmpty {
                Text("No entries on this day.")
                    .font(.app(.subheadline))
                    .foregroundStyle(Theme.textSecondary)
                    .card(padding: 14, radius: 16)
            }

            ForEach(dayEntries) { entry in
                Button {
                    entryToEdit = entry
                } label: {
                    HStack(spacing: 0) {
                        if project == nil {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colors[entry.project?.id ?? UUID()] ?? Theme.textTertiary)
                                .frame(width: 4)
                                .padding(.vertical, 4)
                                .padding(.trailing, 10)
                        }
                        EntryRowView(entry: entry, showsProjectContext: project == nil)
                    }
                    .card(padding: 12, radius: 16)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func quickButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.app(.subheadline, .semibold))
                Text(title)
                    .font(.app(.caption2, .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(Theme.gold)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func plannedRow(_ shift: RecurringShift) -> some View {
        let shiftProject = findProject(id: shift.projectID)
        let canConfirm = calendar.startOfDay(for: selectedDay) <= calendar.startOfDay(for: .now)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("PLANNED · \(shift.timeRangeText)")
                    .font(.app(.caption2, .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.gold)
                Text(shift.taskDescription.isEmpty ? "Regular shift" : shift.taskDescription)
                    .font(.app(.subheadline, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                if let shiftProject {
                    Text("\(shiftProject.job?.name ?? "") · \(shiftProject.name) · \(DateDurationService.formattedDuration(hours: shift.durationHours))")
                        .font(.app(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(spacing: 6) {
                Button("Confirm") { confirm(shift, on: selectedDay) }
                    .font(.app(.footnote, .bold))
                    .foregroundStyle(Theme.onGold)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(Capsule().fill(Theme.goldFill.opacity(canConfirm ? 1 : 0.4)))
                    .disabled(!canConfirm)
                Button("Skip") {
                    shift.skip(selectedDay)
                }
                .font(.app(.footnote, .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(minHeight: 28)
            }
        }
        .padding(12)
        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.gold.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: Day actions (long-press menu and ⋯ menu)

    @ViewBuilder
    private func dayActions(for day: Date) -> some View {
        Button("Add entry", systemImage: "plus") { addEntryItem = DayItem(date: day) }
        let previous = sourceEntries(daysBefore: 1, target: day)
        Button("Copy previous day (\(previous.count))", systemImage: "doc.on.doc") { copyPreviousDay(to: day) }
            .disabled(previous.isEmpty)
        let lastWeek = sourceEntries(daysBefore: 7, target: day)
        Button("Repeat last week (\(lastWeek.count))", systemImage: "arrow.uturn.backward") { repeatLastWeek(on: day) }
            .disabled(lastWeek.isEmpty)
        let planned = pending(on: day)
        if !planned.isEmpty, calendar.startOfDay(for: day) <= calendar.startOfDay(for: .now) {
            Button("Confirm planned shifts (\(planned.count))", systemImage: "checkmark.circle") {
                confirmAll(planned, on: day)
            }
        }
        Divider()
        Button("Export this day", systemImage: "square.and.arrow.up") {
            exportItem = PeriodItem(period: .days(day, day))
        }
        Button("Export this week", systemImage: "calendar") { exportWeek(of: day) }
    }

    // MARK: Insights

    private var insightsCard: some View {
        let insights = CalendarService.insights(entries: project == nil ? allEntries : entries, month: month, weeklyLimit: project == nil ? weeklyLimit : 0)
        let showsTarget = project == nil && monthlyTarget > 0
        return VStack(alignment: .leading, spacing: 14) {
            Text("\(month.formatted(.dateTime.month(.wide))) at a glance")
                .font(.display(.headline))
                .foregroundStyle(Theme.textPrimary)

            if showsTarget {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(DateDurationService.formattedDuration(hours: insights.totalHours)) of \(DateDurationService.formattedDuration(hours: monthlyTarget))")
                            .font(.app(.subheadline, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                        Spacer()
                        Text("\(Int((min(insights.totalHours / monthlyTarget, 9.99) * 100).rounded()))%")
                            .font(.app(.subheadline, .bold))
                            .foregroundStyle(Theme.gold)
                            .monospacedDigit()
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.track)
                            Capsule().fill(Theme.goldFill)
                                .frame(width: proxy.size.width * min(1, insights.totalHours / monthlyTarget))
                        }
                    }
                    .frame(height: 8)
                    .accessibilityHidden(true)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                stat("Total", "\(DateDurationService.formattedDuration(hours: insights.totalHours))", sub: "\(DateDurationService.formattedDecimalHours(insights.totalHours)) h")
                stat("Days worked", "\(insights.daysWorked)", sub: insights.daysWorked == 1 ? "day" : "days")
                stat("Average", DateDurationService.formattedDuration(hours: insights.averagePerWorkedDay), sub: "per worked day")
                stat(
                    "Longest day",
                    DateDurationService.formattedDuration(hours: insights.longestDayHours),
                    sub: insights.longestDay.map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) } ?? "—"
                )
            }

            comparisonLine(insights)

            if !insights.weeksOverLimit.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(insights.weeksOverLimit) { week in
                        let weekEnd = calendar.date(byAdding: .day, value: 6, to: week.weekStart) ?? week.weekStart
                        Label {
                            Text("\(week.weekStart.formatted(.dateTime.day().month(.abbreviated)))–\(weekEnd.formatted(.dateTime.day().month(.abbreviated))): \(DateDurationService.formattedDuration(hours: week.hours)), over your \(DateDurationService.formattedDuration(hours: weeklyLimit)) weekly limit")
                                .font(.app(.footnote, .semibold))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundStyle(Theme.warning)
                    }
                }
            }
        }
        .card(padding: 16, radius: 20)
    }

    private func stat(_ title: String, _ value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.app(.caption, .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.app(.title3, .bold))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            Text(sub)
                .font(.app(.caption))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func comparisonLine(_ insights: CalendarService.MonthInsights) -> some View {
        let previousName = (calendar.date(byAdding: .month, value: -1, to: month) ?? month).formatted(.dateTime.month(.wide))
        if insights.previousMonthHours > 0 {
            let change = insights.changeFromPreviousMonth
            let percent = Int((abs(change) / insights.previousMonthHours * 100).rounded())
            Label {
                Text(abs(change) < 0.01
                     ? "Same as \(previousName)"
                     : "\(DateDurationService.formattedDuration(hours: abs(change))) \(change > 0 ? "more" : "less") than \(previousName) (\(change > 0 ? "+" : "−")\(percent)%)")
                    .font(.app(.footnote, .medium))
            } icon: {
                Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
            }
            .foregroundStyle(Theme.textSecondary)
        } else {
            Text("No hours logged in \(previousName) to compare with.")
                .font(.app(.footnote))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: Range selection

    private var rangeBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(rangeHint)
                .font(.app(.subheadline, .semibold))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            HStack(spacing: 10) {
                Button("Cancel") { withAnimation { cancelRange() } }
                    .buttonStyle(OutlineButtonStyle(height: 46))
                Button {
                    if let period = selectedPeriod {
                        exportItem = PeriodItem(period: period)
                        cancelRange()
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(GoldButtonStyle(height: 46))
                .disabled(selectedPeriod == nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.tabBar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var selectedPeriod: ExportService.ExportPeriod? {
        guard let rangeStart else { return nil }
        return .days(rangeStart, rangeEnd ?? rangeStart)
    }

    private var rangeHint: String {
        guard let period = selectedPeriod else { return "Tap the first day, then the last day." }
        let hours = entries.filter { period.contains($0.date) }.reduce(0) { $0 + $1.durationHours }
        let days = (calendar.dateComponents([.day], from: period.interval.start, to: period.interval.end).day ?? 1)
        let suffix = rangeEnd == nil ? " · tap the last day" : ""
        return "\(period.label) · \(days) \(days == 1 ? "day" : "days") · \(DateDurationService.formattedDuration(hours: hours))\(suffix)"
    }

    private func isInRange(_ date: Date) -> Bool {
        guard isChoosingRange, let period = selectedPeriod else { return false }
        return period.contains(date)
    }

    private func isRangeEndpoint(_ date: Date) -> Bool {
        guard isChoosingRange else { return false }
        return [rangeStart, rangeEnd].compactMap { $0 }.contains { calendar.isDate($0, inSameDayAs: date) }
    }

    private func cancelRange() {
        isChoosingRange = false
        rangeStart = nil
        rangeEnd = nil
    }

    // MARK: Undo banner

    private func undoBar(_ banner: UndoBanner) -> some View {
        HStack {
            Text(banner.message)
                .font(.app(.subheadline, .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button("Undo") { undoLast() }
                .font(.app(.subheadline, .bold))
                .foregroundStyle(Theme.gold)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 16)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func showUndo(_ message: String, created: [WorkEntry]) {
        guard !created.isEmpty else { return }
        let banner = UndoBanner(message: message, entryIDs: created.map(\.id))
        withAnimation { undo = banner }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if undo?.id == banner.id { withAnimation { undo = nil } }
        }
    }

    private func undoLast() {
        guard let banner = undo else { return }
        let toDelete = allEntries.filter { banner.entryIDs.contains($0.id) }
        for entry in toDelete {
            if let owner = entry.project, let index = owner.entries.firstIndex(where: { $0.id == entry.id }) {
                owner.entries.remove(at: index)
            }
            modelContext.delete(entry)
        }
        withAnimation { undo = nil }
    }

    // MARK: - Actions

    private func tap(_ date: Date) {
        if isChoosingRange {
            if rangeStart == nil || rangeEnd != nil {
                rangeStart = date
                rangeEnd = nil
            } else {
                rangeEnd = date
            }
        } else {
            withAnimation(.easeInOut(duration: 0.15)) { selectedDay = date }
        }
    }

    /// Entries (of the projects shown) on the day `daysBefore` days before `target`.
    private func sourceEntries(daysBefore: Int, target: Date) -> [WorkEntry] {
        guard let source = calendar.date(byAdding: .day, value: -daysBefore, to: target) else { return [] }
        return CalendarService.entries(entries, on: source)
    }

    private func copyPreviousDay(to day: Date) {
        let created = CalendarService.copy(sourceEntries(daysBefore: 1, target: day), to: day, context: modelContext)
        showUndo("Copied \(created.count) \(created.count == 1 ? "entry" : "entries") from the previous day", created: created)
        selectedDay = day
    }

    private func repeatLastWeek(on day: Date) {
        let created = CalendarService.copy(sourceEntries(daysBefore: 7, target: day), to: day, context: modelContext)
        showUndo("Repeated \(created.count) \(created.count == 1 ? "entry" : "entries") from last week", created: created)
        selectedDay = day
    }

    private func confirm(_ shift: RecurringShift, on day: Date) {
        guard let shiftProject = findProject(id: shift.projectID) else { return }
        let entry = CalendarService.confirm(shift, on: day, project: shiftProject, context: modelContext)
        showUndo("Logged \(shift.timeRangeText)", created: [entry])
    }

    private func confirmAll(_ planned: [RecurringShift], on day: Date) {
        var created: [WorkEntry] = []
        for shift in planned {
            guard let shiftProject = findProject(id: shift.projectID) else { continue }
            created.append(CalendarService.confirm(shift, on: day, project: shiftProject, context: modelContext))
        }
        showUndo("Logged \(created.count) planned \(created.count == 1 ? "shift" : "shifts")", created: created)
        selectedDay = day
    }

    private func exportWeek(of day: Date) {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: day) else { return }
        exportItem = PeriodItem(period: .days(week.start, week.end.addingTimeInterval(-1)))
    }

    private func shiftMonth(_ delta: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: delta, to: month) else { return }
        month = newMonth
        if !isChoosingRange {
            selectedDay = calendar.isDate(.now, equalTo: newMonth, toGranularity: .month)
                ? .now
                : (calendar.dateInterval(of: .month, for: newMonth)?.start ?? newMonth)
        }
    }

    private func compactHours(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : String(format: "%d:%02d", h, m)
    }
}

// MARK: - Helpers

private struct DayItem: Identifiable {
    let id = UUID()
    let date: Date
}

private struct PeriodItem: Identifiable {
    let id = UUID()
    let period: ExportService.ExportPeriod
}

private struct UndoBanner: Identifiable {
    let id = UUID()
    let message: String
    let entryIDs: [UUID]
}

/// The standalone calendar screen (Home › Calendar), covering all projects.
struct WorkCalendarScreen: View {
    var body: some View {
        WorkCalendarView()
            .themedScreen()
            .tabBarSpace()
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        WorkCalendarScreen()
    }
    .modelContainer(PreviewSupport.container)
}
