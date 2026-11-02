import SwiftUI
import SwiftData
import UIKit

// MARK: - Editor

/// Plan a task (or edit a planned one): project, start, optional end,
/// description, and any number of reminders before the start.
struct PlannedTaskEditor: View {
    let task: PlannedTask?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Job.createdAt) private var jobs: [Job]

    @State private var projectID: UUID?
    @State private var start: Date
    @State private var hasEnd: Bool
    @State private var end: Date
    @State private var taskDescription: String
    @State private var reminders: [ReminderDraft]
    @State private var remindToLog: Bool
    @State private var permission: PlannedTaskNotifications.Permission?
    @State private var confirmDelete = false

    private static let maxReminders = 10

    /// - Parameters:
    ///   - task: the task to edit, or nil to plan a new one.
    ///   - project: pre-selected project for a new task.
    ///   - day: pre-selected day for a new task.
    init(task: PlannedTask? = nil, project: Project? = nil, day: Date? = nil) {
        self.task = task
        let calendar = Calendar.current
        let defaultStart: Date = {
            let nextHour = calendar.date(byAdding: .hour, value: 1, to: calendar.dateInterval(of: .hour, for: .now)?.start ?? .now) ?? .now
            guard let day, !calendar.isDateInToday(day) else { return nextHour }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? nextHour
        }()
        let start = task?.start ?? defaultStart
        _projectID = State(initialValue: task?.projectID ?? project?.id)
        _start = State(initialValue: start)
        _hasEnd = State(initialValue: task?.plannedEnd != nil)
        _end = State(initialValue: task?.effectivePlannedEnd ?? start.addingTimeInterval(3600))
        _taskDescription = State(initialValue: task?.taskDescription ?? "")
        _reminders = State(initialValue: (task?.reminderOffsets ?? [60]).map(ReminderDraft.init(offset:)))
        _remindToLog = State(initialValue: task?.remindToLog ?? true)
    }

    private var projects: [Project] { jobs.flatMap { $0.projects.sorted { $0.createdAt < $1.createdAt } } }

    private var trimmedDescription: String { taskDescription.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The end on the start's day; a time before the start means the next day.
    private var resolvedEnd: Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: end)
        let sameDay = calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: start) ?? end
        return sameDay > start ? sameDay : sameDay.addingTimeInterval(24 * 3600)
    }

    private var offsets: [Int] { PlannedTask.decode(PlannedTask.encode(reminders.map(\.minutes))) }

    private var canSave: Bool { projectID != nil && !trimmedDescription.isEmpty }

    private var wantsNotifications: Bool { !reminders.isEmpty || remindToLog }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Project", selection: $projectID) {
                        if projectID == nil { Text("Choose…").tag(UUID?.none) }
                        ForEach(projects) { project in
                            Text("\(project.job?.name ?? "") · \(project.name)").tag(Optional(project.id))
                        }
                    }
                    .themedRow()
                    TextField("What needs doing?", text: $taskDescription, axis: .vertical)
                        .lineLimit(1...4)
                        .themedRow()
                } header: { SectionLabel("Task") }

                Section {
                    DatePicker("Starts", selection: $start, displayedComponents: [.date, .hourAndMinute])
                        .themedRow()
                    Toggle("Set an end time", isOn: $hasEnd.animation())
                        .tint(Theme.goldFill)
                        .themedRow()
                    if hasEnd {
                        DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
                            .themedRow()
                        HStack {
                            Text("Planned")
                            Spacer()
                            Text(plannedSummary)
                                .foregroundStyle(Theme.gold)
                                .monospacedDigit()
                        }
                        .font(.app(.subheadline, .semibold))
                        .themedRow()
                    }
                } header: {
                    SectionLabel("When")
                } footer: {
                    if start < .now {
                        Text("This time has already passed, so you can log the task straight away.")
                            .font(.app(.footnote))
                    } else if !hasEnd {
                        Text("Optional. You can set the real end time when you log the task.")
                            .font(.app(.footnote))
                    }
                }

                remindersSection

                Section {
                    Toggle(isOn: $remindToLog) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ask me to log it")
                            Text(hasEnd ? "When it ends" : "2 hours after it starts")
                                .font(.app(.footnote))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .tint(Theme.goldFill)
                    .themedRow()
                } footer: {
                    Text("The task is only added to your working hours after you confirm it was done.")
                        .font(.app(.footnote))
                }

                if permission == .denied && wantsNotifications {
                    Section {
                        Label("Notifications are off for SignMe, so reminders won't appear.", systemImage: "bell.slash")
                            .font(.app(.subheadline, .semibold))
                            .foregroundStyle(Theme.warning)
                            .themedRow()
                        Button("Turn on in Settings") { PlannedTaskNotifications.openSystemSettings() }
                            .themedRow()
                    }
                }

                if task != nil {
                    Section {
                        Button("Delete task", role: .destructive) { confirmDelete = true }
                            .themedRow()
                    }
                }
            }
            .themedScreen()
            .navigationTitle(task == nil ? "Plan a task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .task { permission = await PlannedTaskNotifications.permission() }
            .confirmationDialog("Delete this planned task?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
            } message: {
                Text("Its reminders are cancelled. Hours you already logged are kept.")
            }
        }
    }

    private var plannedSummary: String {
        let hours = resolvedEnd.timeIntervalSince(start) / 3600
        let nextDay = !Calendar.current.isDate(resolvedEnd, inSameDayAs: start)
        return DateDurationService.formattedDuration(hours: hours) + (nextDay ? " · ends next day" : "")
    }

    // MARK: Reminders

    private var remindersSection: some View {
        Section {
            ForEach($reminders) { $reminder in
                ReminderRow(reminder: $reminder, start: start) {
                    withAnimation { reminders.removeAll { $0.id == reminder.id } }
                }
                .themedRow()
            }

            if reminders.count < Self.maxReminders {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ReminderDraft.presets, id: \.self) { minutes in
                            let exists = reminders.contains { $0.minutes == minutes }
                            ChoiceChip(title: PlannedTask.reminderText(minutes), systemImage: "plus", isSelected: false) {
                                withAnimation { reminders.append(ReminderDraft(offset: minutes)) }
                            }
                            .disabled(exists)
                            .opacity(exists ? 0.4 : 1)
                        }
                        ChoiceChip(title: "Custom", systemImage: "slider.horizontal.3", isSelected: false) {
                            withAnimation { reminders.append(ReminderDraft(value: 2, unit: .hours)) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .themedRow()
            }
        } header: {
            SectionLabel("Reminders")
        } footer: {
            Text(reminders.isEmpty
                 ? "No reminders. Add as many as you like, from minutes to weeks before the start."
                 : "\(offsets.count) \(offsets.count == 1 ? "reminder" : "reminders"). Duplicates are merged.")
                .font(.app(.footnote))
        }
    }

    // MARK: Actions

    private func save() {
        guard let projectID, canSave else { return }
        let plannedEnd = hasEnd ? resolvedEnd : nil
        if let task {
            task.projectID = projectID
            task.start = start
            task.plannedEnd = plannedEnd
            task.taskDescription = trimmedDescription
            task.reminderOffsets = offsets
            task.remindToLog = remindToLog
        } else {
            modelContext.insert(PlannedTask(
                projectID: projectID,
                start: start,
                plannedEnd: plannedEnd,
                taskDescription: trimmedDescription,
                reminderOffsets: offsets,
                remindToLog: remindToLog
            ))
        }
        try? modelContext.save()
        UserDefaults.standard.set(projectID.uuidString, forKey: AppSettings.Keys.lastProjectID)
        let context = modelContext
        let askPermission = wantsNotifications
        Task { @MainActor in
            if askPermission { await PlannedTaskNotifications.requestPermission() }
            await PlannedTaskNotifications.sync(context: context)
        }
        dismiss()
    }

    private func delete() {
        if let task { modelContext.delete(task) }
        try? modelContext.save()
        let context = modelContext
        Task { @MainActor in await PlannedTaskNotifications.sync(context: context) }
        dismiss()
    }
}

/// One reminder being edited: a number and a unit.
struct ReminderDraft: Identifiable, Equatable {
    enum Unit: String, CaseIterable, Identifiable {
        case minutes, hours, days, weeks
        var id: String { rawValue }
        var minutes: Int {
            switch self {
            case .minutes: 1
            case .hours: 60
            case .days: 1440
            case .weeks: 10080
            }
        }
        var maxValue: Int {
            switch self {
            case .minutes: 55
            case .hours: 23
            case .days: 30
            case .weeks: 8
            }
        }
        var step: Int { self == .minutes ? 5 : 1 }
        var title: String { rawValue.capitalized }
    }

    let id = UUID()
    var value: Int
    var unit: Unit

    var minutes: Int { value * unit.minutes }

    static let presets = [0, 15, 60, 1440]

    init(value: Int, unit: Unit) {
        self.value = value
        self.unit = unit
    }

    /// Picks the largest unit that divides the offset evenly.
    init(offset: Int) {
        if offset > 0, offset % 10080 == 0 { self.init(value: offset / 10080, unit: .weeks) }
        else if offset > 0, offset % 1440 == 0 { self.init(value: offset / 1440, unit: .days) }
        else if offset > 0, offset % 60 == 0 { self.init(value: offset / 60, unit: .hours) }
        else { self.init(value: offset, unit: .minutes) }
    }
}

private struct ReminderRow: View {
    @Binding var reminder: ReminderDraft
    let start: Date
    let onDelete: () -> Void

    private var fireDate: Date { start.addingTimeInterval(-Double(reminder.minutes) * 60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bell.fill")
                    .foregroundStyle(Theme.gold)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(PlannedTask.reminderText(reminder.minutes))
                        .font(.app(.body, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(fireDate <= .now
                         ? "Already passed — won't be sent"
                         : fireDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                        .font(.app(.footnote))
                        .foregroundStyle(fireDate <= .now ? Theme.warning : Theme.textSecondary)
                        .monospacedDigit()
                }
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.app(.title3))
                        .foregroundStyle(Theme.danger)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove reminder")
            }
            HStack(spacing: 10) {
                Stepper(value: $reminder.value, in: 0...reminder.unit.maxValue, step: reminder.unit.step) {
                    Text("\(reminder.value)")
                        .font(.app(.body, .bold))
                        .monospacedDigit()
                }
                Picker("Unit", selection: $reminder.unit) {
                    ForEach(ReminderDraft.Unit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
        }
        .padding(.vertical, 2)
        .onChange(of: reminder.unit) { _, unit in
            reminder.value = min(max(reminder.value, unit == .minutes ? 0 : 1), unit.maxValue)
        }
    }
}

// MARK: - Task sheet (details + confirm done)

/// Shows a planned task. From its day on, the real start, end and break can be
/// entered; it's added to the working hours only after "This task is done" is ticked.
struct PlannedTaskSheet: View {
    let task: PlannedTask

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Job.createdAt) private var jobs: [Job]

    @State private var actualStart: Date
    @State private var actualEnd: Date
    @State private var breakMinutes = 0
    @State private var logDescription: String
    @State private var confirmedDone = false
    @State private var showingEditor = false
    @State private var confirmDelete = false

    init(task: PlannedTask) {
        self.task = task
        let now = Date.now
        let roundedNow = Calendar.current.date(
            byAdding: .minute,
            value: -(Calendar.current.component(.minute, from: now) % 5),
            to: Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now
        ) ?? now
        _actualStart = State(initialValue: task.start)
        let plannedEnd = task.effectivePlannedEnd
        let end: Date
        if let plannedEnd, plannedEnd <= now { end = plannedEnd }
        else if roundedNow > task.start { end = roundedNow }
        else { end = task.start.addingTimeInterval(3600) }
        _actualEnd = State(initialValue: end)
        _logDescription = State(initialValue: task.taskDescription)
    }

    private var project: Project? { jobs.flatMap(\.projects).first { $0.id == task.projectID } }

    private var validation: String? {
        PlannedTask.validationMessage(start: actualStart, end: actualEnd, breakMinutes: breakMinutes)
    }

    private var workedHours: Double {
        max(0, actualEnd.timeIntervalSince(actualStart) / 3600 - Double(breakMinutes) / 60)
    }

    private var loggedEntry: WorkEntry? {
        guard let id = task.completedEntryID else { return nil }
        return project?.entries.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            Form {
                summarySection
                if task.status == .done {
                    doneSection
                } else if project == nil {
                    Section {
                        Text("This task's project was deleted, so it can't be logged.")
                            .font(.app(.subheadline))
                            .foregroundStyle(Theme.textSecondary)
                            .themedRow()
                    }
                } else if task.canConfirm() {
                    logSection
                } else {
                    Section {
                        Label("You can log this task from \(task.start.formatted(.dateTime.weekday(.wide).day().month(.wide))).", systemImage: "calendar.badge.clock")
                            .font(.app(.subheadline))
                            .foregroundStyle(Theme.textSecondary)
                            .themedRow()
                    }
                }
                if task.status == .planned {
                    remindersSection
                }
                Section {
                    Button(task.status == .done ? "Remove from planned tasks" : "Delete task", role: .destructive) {
                        confirmDelete = true
                    }
                    .themedRow()
                } footer: {
                    if task.status == .done {
                        Text("The logged hours stay in your working hours.")
                            .font(.app(.footnote))
                    }
                }
            }
            .themedScreen()
            .navigationTitle(task.status == .done ? "Done" : "Planned task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if task.status == .planned {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") { showingEditor = true }
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                PlannedTaskEditor(task: task)
            }
            .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
            }
        }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                StageBadge(stage: task.stage())
                Text(task.taskDescription)
                    .font(.app(.title3, .bold))
                    .foregroundStyle(Theme.textPrimary)
                Label(task.whenText, systemImage: "clock")
                    .font(.app(.subheadline, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                if let project {
                    Label("\(project.job?.name ?? "") · \(project.name)", systemImage: "folder")
                        .font(.app(.subheadline))
                        .foregroundStyle(Theme.textSecondary)
                }
                if let hours = task.plannedHours {
                    Text("Planned: \(DateDurationService.formattedDuration(hours: hours))")
                        .font(.app(.footnote))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.vertical, 4)
            .themedRow()
        }
    }

    private var doneSection: some View {
        Section {
            if let entry = loggedEntry {
                EntryRowView(entry: entry)
                    .themedRow()
            }
            if let completedAt = task.completedAt {
                Text("Confirmed \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.app(.footnote))
                    .foregroundStyle(Theme.textSecondary)
                    .themedRow()
            }
        } header: {
            SectionLabel("Added to working hours")
        }
    }

    private var logSection: some View {
        Section {
            DatePicker("Started", selection: $actualStart, displayedComponents: [.date, .hourAndMinute])
                .themedRow()
            DatePicker("Ended", selection: $actualEnd, in: ...Date.now.addingTimeInterval(60), displayedComponents: [.date, .hourAndMinute])
                .themedRow()
            Stepper(value: $breakMinutes, in: 0...240, step: 5) {
                HStack {
                    Text("Break")
                    Spacer()
                    Text("\(breakMinutes) min")
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
            }
            .themedRow()
            TextField("Description", text: $logDescription, axis: .vertical)
                .lineLimit(1...4)
                .themedRow()
            HStack {
                Text("Worked")
                Spacer()
                Text(DateDurationService.formattedDuration(hours: workedHours))
                    .font(.app(.body, .bold))
                    .foregroundStyle(Theme.gold)
                    .monospacedDigit()
            }
            .themedRow()

            if let validation {
                Label(validation, systemImage: "exclamationmark.triangle.fill")
                    .font(.app(.footnote, .semibold))
                    .foregroundStyle(Theme.warning)
                    .themedRow()
            }

            Toggle(isOn: $confirmedDone) {
                Text("I confirm this task is done")
                    .font(.app(.body, .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .toggleStyle(GoldCheckboxToggleStyle())
            .themedRow()

            Button {
                logTask()
            } label: {
                Label("Add to working hours", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(GoldButtonStyle(height: 50))
            .disabled(!confirmedDone || validation != nil || logDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        } header: {
            SectionLabel("Log it")
        } footer: {
            Text(confirmedDone ? "" : "Tick the box to confirm the task was done before it's added to your hours.")
                .font(.app(.footnote))
        }
    }

    private var remindersSection: some View {
        Section {
            if task.reminderOffsets.isEmpty && !task.remindToLog {
                Text("No reminders")
                    .foregroundStyle(Theme.textSecondary)
                    .themedRow()
            }
            ForEach(task.reminderOffsets, id: \.self) { offset in
                let date = task.start.addingTimeInterval(-Double(offset) * 60)
                reminderLine(PlannedTask.reminderText(offset), date: date)
            }
            if task.remindToLog {
                reminderLine("Ask me to log it", date: task.effectivePlannedEnd ?? task.start.addingTimeInterval(2 * 3600))
            }
        } header: {
            SectionLabel("Reminders")
        }
    }

    private func reminderLine(_ title: String, date: Date) -> some View {
        HStack {
            Image(systemName: date > .now ? "bell" : "bell.badge")
                .foregroundStyle(Theme.gold)
                .accessibilityHidden(true)
            Text(title)
            Spacer()
            Text(date > .now ? date.formatted(.dateTime.weekday(.abbreviated).day().hour().minute()) : "Sent")
                .font(.app(.footnote))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
        }
        .themedRow()
    }

    private func logTask() {
        guard confirmedDone, validation == nil, let project else { return }
        task.complete(
            start: actualStart,
            end: actualEnd,
            breakMinutes: breakMinutes,
            description: logDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            project: project,
            context: modelContext
        )
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let context = modelContext
        Task { @MainActor in await PlannedTaskNotifications.sync(context: context) }
        dismiss()
    }

    private func delete() {
        modelContext.delete(task)
        try? modelContext.save()
        let context = modelContext
        Task { @MainActor in await PlannedTaskNotifications.sync(context: context) }
        dismiss()
    }
}

/// Opens a task by id (used when a notification is tapped).
struct PlannedTaskLinkSheet: View {
    let taskID: UUID
    @Query private var tasks: [PlannedTask]
    @Environment(\.dismiss) private var dismiss

    init(taskID: UUID) {
        self.taskID = taskID
        _tasks = Query(filter: #Predicate<PlannedTask> { $0.id == taskID })
    }

    var body: some View {
        if let task = tasks.first {
            PlannedTaskSheet(task: task)
        } else {
            NavigationStack {
                EmptyStateView(icon: "checklist", title: "Task not found", message: "It may have been deleted.")
                    .themedScreen()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    }
            }
        }
    }
}

// MARK: - Badge & row

struct StageBadge: View {
    let stage: PlannedTask.Stage

    private var style: (text: String, icon: String, color: Color) {
        switch stage {
        case .upcoming: return ("Upcoming", "clock", Theme.textSecondary)
        case .awaitingConfirmation: return ("Confirm when done", "exclamationmark.circle.fill", Theme.gold)
        case .done: return ("Done", "checkmark.circle.fill", Theme.success)
        }
    }

    var body: some View {
        Label(style.text, systemImage: style.icon)
            .font(.app(.caption, .bold))
            .foregroundStyle(style.color)
    }
}

struct PlannedTaskRow: View {
    let task: PlannedTask
    let project: Project?
    var showsProject = true

    var body: some View {
        let stage = task.stage()
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(stage))
                .font(.app(.title3))
                .foregroundStyle(stage == .done ? Theme.success : Theme.gold)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.taskDescription)
                    .font(.app(.body, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(task.whenText)
                    .font(.app(.footnote, .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                if showsProject {
                    Text(project.map { "\($0.job?.name ?? "") · \($0.name)" } ?? "Project deleted")
                        .font(.app(.footnote))
                        .foregroundStyle(project == nil ? Theme.danger : Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if stage == .awaitingConfirmation {
                Text("Confirm")
                    .font(.app(.caption, .bold))
                    .foregroundStyle(Theme.onGold)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 28)
                    .background(Capsule().fill(Theme.goldFill))
            } else if stage == .upcoming, !task.reminderOffsets.isEmpty {
                Label("\(task.reminderOffsets.count)", systemImage: "bell.fill")
                    .font(.app(.caption, .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityLabel("\(task.reminderOffsets.count) reminders")
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func icon(_ stage: PlannedTask.Stage) -> String {
        switch stage {
        case .upcoming: "clock"
        case .awaitingConfirmation: "exclamationmark.circle"
        case .done: "checkmark.circle.fill"
        }
    }
}

// MARK: - List

/// All planned tasks (or one project's): waiting for confirmation, upcoming, done.
struct PlannedTasksView: View {
    var project: Project? = nil

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlannedTask.start) private var allTasks: [PlannedTask]
    @Query(sort: \Job.createdAt) private var jobs: [Job]

    @State private var selectedTask: PlannedTask?
    @State private var showingEditor = false

    private var projectsByID: [UUID: Project] {
        Dictionary(jobs.flatMap(\.projects).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var tasks: [PlannedTask] {
        guard let project else { return allTasks }
        return allTasks.filter { $0.projectID == project.id }
    }

    var body: some View {
        let now = Date.now
        let awaiting = tasks.filter { $0.stage(now: now) == .awaitingConfirmation }
        let upcoming = tasks.filter { $0.stage(now: now) == .upcoming }
        let done = tasks.filter { $0.status == .done }
            .sorted { ($0.completedAt ?? $0.start) > ($1.completedAt ?? $1.start) }
            .prefix(30)
        let projects = projectsByID

        List {
            if tasks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checklist")
                        .font(.app(.largeTitle))
                        .foregroundStyle(Theme.textTertiary)
                    Text("Nothing planned")
                        .font(.app(.headline))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Plan a task with reminders. Once it's done, confirm it to add the hours.")
                        .font(.app(.subheadline))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Plan a task") { showingEditor = true }
                        .buttonStyle(GoldButtonStyle(height: 46))
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .listRowBackground(Color.clear)
            }
            section("Confirm when done", awaiting, projects)
            section("Upcoming", upcoming, projects)
            section("Done", Array(done), projects)
        }
        .themedScreen()
        .navigationTitle(project.map { "Planned · \($0.name)" } ?? "Planned tasks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingEditor = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Plan a task")
            }
        }
        .sheet(item: $selectedTask) { task in
            PlannedTaskSheet(task: task)
        }
        .sheet(isPresented: $showingEditor) {
            PlannedTaskEditor(project: project)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [PlannedTask], _ projects: [UUID: Project]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { task in
                    Button { selectedTask = task } label: {
                        PlannedTaskRow(task: task, project: projects[task.projectID], showsProject: project == nil)
                    }
                    .buttonStyle(.plain)
                    .themedRow()
                    .swipeActions {
                        Button(role: .destructive) { delete(task) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            } header: {
                SectionLabel(title)
            }
        }
    }

    private func delete(_ task: PlannedTask) {
        modelContext.delete(task)
        try? modelContext.save()
        let context = modelContext
        Task { @MainActor in await PlannedTaskNotifications.sync(context: context) }
    }
}

/// Pushed screen wrapper (keeps content above the tab bar).
struct PlannedTasksScreen: View {
    var project: Project? = nil

    var body: some View {
        PlannedTasksView(project: project)
            .tabBarSpace()
    }
}

#Preview {
    NavigationStack {
        PlannedTasksScreen()
    }
    .modelContainer(PreviewSupport.container)
}
