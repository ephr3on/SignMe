import SwiftUI
import SwiftData

/// Times handed to the entry form from the live timer.
struct EntryPrefill {
    var start: Date
    var end: Date
    var breakMinutes: Int
}

/// Quick add/edit form for a WorkEntry.
/// - New entries start on the last-used project, ending now and lasting an hour.
/// - Day, break and recent task descriptions are one-tap choices.
/// - Passing `entryToEdit` switches to edit mode (the project can be changed, which moves the entry).
struct EntryFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Job.createdAt) private var jobs: [Job]
    @Query(EntryFormView.recentEntriesDescriptor) private var recentEntries: [WorkEntry]
    @AppStorage(AppSettings.Keys.lastProjectID) private var lastProjectID = AppSettings.Defaults.lastProjectID

    var entryToEdit: WorkEntry?
    var onSaved: (() -> Void)?

    @State private var selectedProject: Project?
    @State private var date: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var breakMinutes: Int
    @State private var taskDescription: String
    @State private var showingDatePicker = false
    @State private var showingCustomBreak = false
    @FocusState private var descriptionFocused: Bool

    private static let breakPresets = [0, 15, 30, 45, 60]

    static var recentEntriesDescriptor: FetchDescriptor<WorkEntry> {
        var descriptor = FetchDescriptor<WorkEntry>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 300
        return descriptor
    }

    init(
        project: Project? = nil,
        entryToEdit: WorkEntry? = nil,
        initialDate: Date? = nil,
        prefill: EntryPrefill? = nil,
        onSaved: (() -> Void)? = nil
    ) {
        self.entryToEdit = entryToEdit
        self.onSaved = onSaved
        _selectedProject = State(initialValue: entryToEdit?.project ?? project)

        let calendar = Calendar.current
        let defaultEnd = calendar.dateInterval(of: .minute, for: .now)?.start ?? .now
        let roundedEnd = calendar.date(
            byAdding: .minute,
            value: -(calendar.component(.minute, from: defaultEnd) % 5),
            to: defaultEnd
        ) ?? defaultEnd

        let start = entryToEdit?.startTime ?? prefill?.start ?? roundedEnd.addingTimeInterval(-3600)
        let end = entryToEdit?.endTime ?? prefill?.end ?? roundedEnd
        let day = entryToEdit?.date ?? prefill?.start ?? initialDate ?? .now

        _date = State(initialValue: day)
        _startTime = State(initialValue: start)
        _endTime = State(initialValue: end)
        _breakMinutes = State(initialValue: entryToEdit?.breakMinutes ?? prefill?.breakMinutes ?? 0)
        _taskDescription = State(initialValue: entryToEdit?.taskDescription ?? "")
        let isTodayOrYesterday = calendar.isDateInToday(day) || calendar.isDateInYesterday(day)
        _showingDatePicker = State(initialValue: !isTodayOrYesterday)
        _showingCustomBreak = State(initialValue: !Self.breakPresets.contains(entryToEdit?.breakMinutes ?? prefill?.breakMinutes ?? 0))
    }

    // MARK: - Derived values

    private var allProjects: [Project] {
        jobs.flatMap { job in
            job.projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var interval: (start: Date, end: Date) {
        DateDurationService.resolveInterval(day: date, start: startTime, end: endTime)
    }

    private var spansMidnight: Bool {
        DateDurationService.spansMidnight(start: interval.start, end: interval.end)
    }

    private var spanMinutes: Int {
        Int((interval.end.timeIntervalSince(interval.start) / 60).rounded())
    }

    private var isTimeValid: Bool { DateDurationService.isValid(start: interval.start, end: interval.end) }
    private var isBreakValid: Bool { breakMinutes >= 0 && breakMinutes < spanMinutes }
    private var trimmedDescription: String { taskDescription.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { selectedProject != nil && isTimeValid && isBreakValid && !trimmedDescription.isEmpty }

    private var workedHours: Double {
        DateDurationService.durationHours(from: interval.start, to: interval.end, breakMinutes: breakMinutes)
    }

    /// Distinct recent descriptions — this project's first — filtered by what's typed.
    private var suggestions: [String] {
        let projectID = selectedProject?.id
        let ordered = recentEntries.filter { $0.project?.id == projectID } + recentEntries.filter { $0.project?.id != projectID }
        var seen = Set<String>()
        var result: [String] = []
        let needle = trimmedDescription.lowercased()
        for entry in ordered {
            let text = entry.taskDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = text.lowercased()
            guard !text.isEmpty, !seen.contains(key), key != needle else { continue }
            if !needle.isEmpty && !key.contains(needle) { continue }
            seen.insert(key)
            result.append(text)
            if result.count == 6 { break }
        }
        return result
    }

    private var dayChoice: DayChoice {
        let calendar = Calendar.current
        if showingDatePicker { return .other }
        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }
        return .other
    }

    private enum DayChoice { case today, yesterday, other }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if allProjects.isEmpty {
                    EmptyStateView(
                        icon: "folder.badge.plus",
                        title: "No projects yet",
                        message: "Create a job and a project in the Jobs tab, then log your time here."
                    )
                } else {
                    form
                }
            }
            .themedScreen()
            .navigationTitle(entryToEdit == nil ? "New entry" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.bold)
                        .disabled(!isValid)
                }
            }
            .onAppear(perform: selectDefaultProject)
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                projectPicker
                daySection
                timeSection
                descriptionSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(action: save) {
                Text(entryToEdit == nil ? "Save entry" : "Save changes")
            }
            .buttonStyle(GoldButtonStyle(height: 54))
            .disabled(!isValid)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(Theme.background)
        }
    }

    // MARK: Project

    private var projectPicker: some View {
        Menu {
            ForEach(jobs) { job in
                if !job.projects.isEmpty {
                    Section(job.name) {
                        ForEach(job.projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { project in
                            Button {
                                selectedProject = project
                            } label: {
                                if project.id == selectedProject?.id {
                                    Label(project.name, systemImage: "checkmark")
                                } else {
                                    Text(project.name)
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.background)
                    .frame(width: 38, height: 38)
                    .background(Theme.gold, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedProject?.name ?? "Choose a project")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(projectSubtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("Change")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.gold)
            }
            .card(padding: 12, radius: 16, highlighted: true)
        }
        .accessibilityLabel("Project: \(selectedProject?.name ?? "none"). Change project")
    }

    private var projectSubtitle: String {
        guard let project = selectedProject else { return "Tap to pick where this time goes" }
        let jobName = project.job?.name ?? ""
        let isLastUsed = project.id.uuidString == lastProjectID && entryToEdit == nil
        return isLastUsed ? "\(jobName) · last used" : jobName
    }

    // MARK: Day

    private var daySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Day")
            HStack(spacing: 8) {
                ChoiceChip(title: "Today", isSelected: dayChoice == .today) {
                    showingDatePicker = false
                    date = .now
                }
                ChoiceChip(title: "Yesterday", isSelected: dayChoice == .yesterday) {
                    showingDatePicker = false
                    date = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
                }
                ChoiceChip(title: "Other", systemImage: "calendar", isSelected: dayChoice == .other) {
                    showingDatePicker = true
                }
            }
            if showingDatePicker {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .foregroundStyle(Theme.textPrimary)
                    .card(padding: 12, radius: 14)
            }
        }
    }

    // MARK: Time

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Time")
            HStack(spacing: 10) {
                timeCard(title: "Start", selection: $startTime)
                timeCard(title: spansMidnight ? "End · next day" : "End", selection: $endTime)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("Break")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(Self.breakPresets, id: \.self) { minutes in
                        ChoiceChip(
                            title: minutes == 0 ? "None" : DateDurationService.formattedDuration(hours: Double(minutes) / 60),
                            isSelected: !showingCustomBreak && breakMinutes == minutes
                        ) {
                            showingCustomBreak = false
                            breakMinutes = minutes
                        }
                    }
                    ChoiceChip(title: "Other", isSelected: showingCustomBreak) {
                        showingCustomBreak = true
                    }
                }
            }

            if showingCustomBreak {
                Stepper(value: $breakMinutes, in: 0...600, step: 5) {
                    HStack {
                        Text("Break")
                        Spacer()
                        Text(breakMinutes == 0 ? "None" : DateDurationService.formattedDuration(hours: Double(breakMinutes) / 60))
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                    .foregroundStyle(Theme.textPrimary)
                }
                .card(padding: 12, radius: 14)
            }

            HStack {
                Text("Worked")
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(DateDurationService.formattedDuration(hours: workedHours))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isTimeValid && isBreakValid ? Theme.gold : Theme.textTertiary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: workedHours)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Theme.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if !isTimeValid {
                validationLabel("End time must be different from start time.")
            } else if !isBreakValid {
                validationLabel("The break must be shorter than the time worked.")
            }
        }
    }

    private func timeCard(title: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .card(padding: 12, radius: 16)
    }

    private func validationLabel(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(Theme.danger)
    }

    // MARK: Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("What did you do?")
            TextField("Describe the task", text: $taskDescription, axis: .vertical)
                .lineLimit(2...6)
                .focused($descriptionFocused)
                .foregroundStyle(Theme.textPrimary)
                .card(padding: 14, radius: 14)

            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                taskDescription = suggestion
                            } label: {
                                Text(suggestion)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 36)
                                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Uses this description")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func selectDefaultProject() {
        guard selectedProject == nil else { return }
        selectedProject = allProjects.first { $0.id.uuidString == lastProjectID } ?? allProjects.first
    }

    private func save() {
        guard isValid, let project = selectedProject else { return }
        let resolved = interval

        if let entry = entryToEdit {
            if let oldProject = entry.project, oldProject.id != project.id,
               let index = oldProject.entries.firstIndex(where: { $0.id == entry.id }) {
                oldProject.entries.remove(at: index)
                project.entries.append(entry)
            }
            entry.date = resolved.start
            entry.startTime = resolved.start
            entry.endTime = resolved.end
            entry.breakMinutes = breakMinutes
            entry.taskDescription = trimmedDescription
            entry.recalculateDuration()
            entry.updatedAt = .now
        } else {
            let entry = WorkEntry(
                date: resolved.start,
                startTime: resolved.start,
                endTime: resolved.end,
                breakMinutes: breakMinutes,
                taskDescription: trimmedDescription
            )
            modelContext.insert(entry)
            project.entries.append(entry)
        }

        lastProjectID = project.id.uuidString
        onSaved?()
        dismiss()
    }
}

#Preview {
    EntryFormView()
        .modelContainer(PreviewSupport.container)
        .preferredColorScheme(.dark)
}
