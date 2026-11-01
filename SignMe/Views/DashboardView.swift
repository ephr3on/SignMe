import SwiftUI
import SwiftData
import Charts

/// The home screen: live clock-in timer, monthly target, this week's hours and recent entries.
struct DashboardView: View {
    @Environment(TimerStore.self) private var timer
    @Query(sort: \Job.createdAt) private var jobs: [Job]
    @Query(sort: \WorkEntry.date, order: .reverse) private var allEntries: [WorkEntry]

    @AppStorage(AppSettings.Keys.monthlyTargetHours) private var monthlyTarget = AppSettings.Defaults.monthlyTargetHours
    @AppStorage(AppSettings.Keys.lastProjectID) private var lastProjectID = AppSettings.Defaults.lastProjectID
    @AppStorage(AppSettings.Keys.signerName) private var signerName = AppSettings.Defaults.signerName

    @State private var idleProjectID: UUID?
    @State private var timerEntry: TimerEntryItem?
    @State private var entryToEdit: WorkEntry?
    @State private var showingExportMonth = false
    @State private var showingTargetEditor = false
    @State private var showingDiscardConfirm = false
    @State private var showingTooShortAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                timerCard
                targetCard
                weekCard
                recentSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .themedScreen()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $timerEntry) { item in
            EntryFormView(
                project: project(with: item.snapshot.projectID),
                prefill: EntryPrefill(start: item.snapshot.start, end: item.snapshot.end, breakMinutes: item.snapshot.breakMinutes),
                onSaved: { timer.reset() }
            )
        }
        .sheet(item: $entryToEdit) { entry in
            EntryFormView(entryToEdit: entry)
        }
        .sheet(isPresented: $showingExportMonth) {
            ExportMonthSheet(jobs: jobs)
        }
        .sheet(isPresented: $showingTargetEditor) {
            MonthlyTargetEditor(target: $monthlyTarget)
        }
        .confirmationDialog("Discard the running timer?", isPresented: $showingDiscardConfirm, titleVisibility: .visible) {
            Button("Discard Timer", role: .destructive) { timer.reset() }
        } message: {
            Text("The tracked time won't be saved.")
        }
        .alert("Less than a minute tracked", isPresented: $showingTooShortAlert) {
            Button("Keep Running", role: .cancel) {}
            Button("Discard", role: .destructive) { timer.reset() }
        } message: {
            Text("There's nothing to save yet.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SIGNME")
                    .font(.system(.footnote, design: .serif, weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(Theme.gold)
                Text(greeting)
                    .font(Theme.display(.title))
                    .foregroundStyle(Theme.textPrimary)
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                showingExportMonth = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.gold)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.surface))
                    .overlay(Circle().strokeBorder(Theme.gold.opacity(0.35), lineWidth: 1))
            }
            .accessibilityLabel("Export month")
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        let base: String
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: base = "Good morning"
        case 12..<18: base = "Good afternoon"
        default: base = "Good evening"
        }
        let firstName = signerName.split(separator: " ").first.map(String.init) ?? ""
        return firstName.isEmpty ? base : "\(base), \(firstName)"
    }

    // MARK: - Timer

    @ViewBuilder
    private var timerCard: some View {
        if timer.isRunning {
            runningTimerCard
        } else {
            idleTimerCard
        }
    }

    private var runningTimerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(timer.isOnBreak ? Theme.warning : Theme.success)
                    .frame(width: 8, height: 8)
                Text(timerStatusText)
                    .font(Theme.sectionLabel)
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Menu {
                    projectMenuItems { project in timer.switchProject(to: project.id) }
                    Divider()
                    Button("Discard Timer", systemImage: "trash", role: .destructive) {
                        showingDiscardConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Timer options")
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    Text(TimerStore.clockText(timer.workedDuration(at: context.date)))
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(timer.isOnBreak ? Theme.textSecondary : Theme.textPrimary)
                        .accessibilityLabel("Worked \(DateDurationService.formattedDuration(hours: timer.workedDuration(at: context.date) / 3600))")
                    let breakTime = timer.breakDuration(at: context.date)
                    if breakTime >= 60 {
                        Text("Break \(DateDurationService.formattedDuration(hours: breakTime / 3600))")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            Text(runningProjectLine)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            HStack(spacing: 10) {
                Button(action: stopTimer) {
                    Label("Stop & save", systemImage: "stop.fill")
                }
                .buttonStyle(GoldButtonStyle(height: 50))

                Button {
                    withAnimation { timer.toggleBreak() }
                } label: {
                    Text(timer.isOnBreak ? "Resume" : "Break")
                }
                .buttonStyle(OutlineButtonStyle(height: 50))
                .frame(width: 118)
            }
        }
        .card(padding: 18, radius: 22, highlighted: true)
    }

    private var timerStatusText: String {
        if timer.isOnBreak { return "ON BREAK" }
        guard let start = timer.startedAt else { return "TRACKING" }
        return "TRACKING · SINCE \(DateDurationService.timeFormatter.string(from: start))"
    }

    private var runningProjectLine: String {
        guard let project = project(with: timer.projectID) else { return "Project not found — choose one in ⋯" }
        return "\(project.job?.name ?? "") · \(project.name)"
    }

    private var idleTimerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.gold)
                Text("Ready to clock in?")
                    .font(Theme.display(.title3))
                    .foregroundStyle(Theme.textPrimary)
            }

            if allProjects.isEmpty {
                Text("Create a job and a project in the Jobs tab to start tracking time.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Menu {
                    projectMenuItems { project in idleProjectID = project.id }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(idleProject?.name ?? "Choose a project")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(idleProject?.job?.name ?? "")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.gold)
                    }
                    .padding(12)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityLabel("Timer project: \(idleProject?.name ?? "none")")

                Button {
                    guard let project = idleProject else { return }
                    lastProjectID = project.id.uuidString
                    withAnimation { timer.start(projectID: project.id) }
                } label: {
                    Label("Start timer", systemImage: "play.fill")
                }
                .buttonStyle(GoldButtonStyle(height: 50))
                .disabled(idleProject == nil)
            }
        }
        .card(padding: 18, radius: 22, highlighted: true)
    }

    private var idleProject: Project? {
        if let idleProjectID, let match = project(with: idleProjectID) { return match }
        return allProjects.first { $0.id.uuidString == lastProjectID } ?? allProjects.first
    }

    @ViewBuilder
    private func projectMenuItems(_ select: @escaping (Project) -> Void) -> some View {
        ForEach(jobs) { job in
            if !job.projects.isEmpty {
                Section(job.name) {
                    ForEach(job.projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { project in
                        Button(project.name) { select(project) }
                    }
                }
            }
        }
    }

    private func stopTimer() {
        guard let snapshot = timer.snapshot() else { return }
        if snapshot.end.timeIntervalSince(snapshot.start) < 60 {
            showingTooShortAlert = true
        } else {
            timerEntry = TimerEntryItem(snapshot: snapshot)
        }
    }

    // MARK: - Target

    private var monthHours: Double {
        let calendar = Calendar.current
        return allEntries
            .filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .month) }
            .reduce(0) { $0 + $1.durationHours }
    }

    private var targetCard: some View {
        Button {
            showingTargetEditor = true
        } label: {
            HStack(spacing: 16) {
                if monthlyTarget > 0 {
                    let progress = monthHours / monthlyTarget
                    ProgressRing(progress: progress, label: "\(Int((min(progress, 1) * 100).rounded()))%")
                        .frame(width: 84, height: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel("\(Date.now.formatted(.dateTime.month(.wide))) target")
                        (Text(DateDurationService.formattedDuration(hours: monthHours))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                         + Text("  of \(DateDurationService.formattedDuration(hours: monthlyTarget))")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary))
                            .monospacedDigit()
                        Text(targetRemainingText)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    Image(systemName: "target")
                        .font(.title2)
                        .foregroundStyle(Theme.gold)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Theme.surfaceRaised))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Set a monthly target")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("See your progress toward your contract hours.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .card(padding: 16, radius: 22)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit monthly target")
    }

    private var targetRemainingText: String {
        let remaining = monthlyTarget - monthHours
        guard remaining > 0.005 else { return "Target reached this month" }
        let workdays = remainingWorkdays()
        let remainingText = DateDurationService.formattedDuration(hours: remaining)
        guard workdays > 0 else { return "\(remainingText) to go" }
        let perDay = DateDurationService.formattedDuration(hours: remaining / Double(workdays))
        return "\(remainingText) to go · about \(perDay) per workday"
    }

    /// Monday–Friday days from today to the end of this month, today included.
    private func remainingWorkdays() -> Int {
        let calendar = Calendar.current
        guard let monthEnd = calendar.dateInterval(of: .month, for: .now)?.end else { return 0 }
        var day = calendar.startOfDay(for: .now)
        var count = 0
        while day < monthEnd {
            if !calendar.isDateInWeekend(day) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return count
    }

    // MARK: - Week chart

    private struct DayHours: Identifiable {
        let id: Date
        let label: String
        let hours: Double
        let isToday: Bool
    }

    private var weekDays: [DayHours] {
        let calendar = Calendar.current
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let hours = allEntries
                .filter { calendar.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.durationHours }
            let weekday = calendar.component(.weekday, from: day)
            return DayHours(
                id: day,
                label: calendar.shortStandaloneWeekdaySymbols[weekday - 1],
                hours: hours,
                isToday: calendar.isDateInToday(day)
            )
        }
    }

    private var weekCard: some View {
        let days = weekDays
        let total = days.reduce(0) { $0 + $1.hours }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("This week")
                Text(DateDurationService.formattedDuration(hours: total))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
            }
            Chart(days) { day in
                BarMark(
                    x: .value("Day", day.label),
                    y: .value("Hours", day.hours)
                )
                .foregroundStyle(day.isToday ? Theme.gold : Theme.bar)
                .cornerRadius(6)
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(height: 120)
        }
        .card(padding: 16, radius: 22)
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent")
                .font(Theme.display(.title3))
                .foregroundStyle(Theme.textPrimary)

            if allEntries.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "No entries yet",
                    message: "Start the timer or tap + to log your first hours."
                )
                .card(padding: 4, radius: 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(allEntries.prefix(4)) { entry in
                        Button {
                            entryToEdit = entry
                        } label: {
                            EntryRowView(entry: entry, showsProjectContext: true)
                                .card(padding: 12, radius: 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var allProjects: [Project] {
        jobs.flatMap { job in
            job.projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func project(with id: UUID?) -> Project? {
        guard let id else { return nil }
        return allProjects.first { $0.id == id }
    }
}

/// Wraps a timer snapshot so it can drive `.sheet(item:)`.
private struct TimerEntryItem: Identifiable {
    let id = UUID()
    let snapshot: TimerStore.Snapshot
}

/// Small sheet to set or clear the monthly hours target.
struct MonthlyTargetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var target: Double
    @State private var hours: Int

    init(target: Binding<Double>) {
        _target = target
        _hours = State(initialValue: target.wrappedValue > 0 ? Int(target.wrappedValue.rounded()) : 80)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("How many hours do you want to work each month?")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Stepper(value: $hours, in: 1...400) {
                    Text("\(hours) h per month")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                }
                .card(padding: 14, radius: 16)
                Button("Save target") {
                    target = Double(hours)
                    dismiss()
                }
                .buttonStyle(GoldButtonStyle())
                if target > 0 {
                    Button("Remove target", role: .destructive) {
                        target = 0
                        dismiss()
                    }
                    .foregroundStyle(Theme.danger)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .themedScreen()
            .navigationTitle("Monthly target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.height(340)])
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
    .modelContainer(PreviewSupport.container)
    .environment(TimerStore(defaults: UserDefaults(suiteName: "preview")!))
    .preferredColorScheme(.dark)
}
