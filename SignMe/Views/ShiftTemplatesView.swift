import SwiftUI
import SwiftData

/// Regular shifts ("Tue + Thu, 09:00–13:00 on Project X"). They appear on the
/// calendar as dashed planned blocks that one tap turns into real entries.
struct ShiftTemplatesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecurringShift.createdAt) private var shifts: [RecurringShift]
    @Query(sort: \Job.createdAt) private var jobs: [Job]

    @State private var editing: ShiftEditItem?

    private var allProjects: [Project] { jobs.flatMap(\.projects) }

    var body: some View {
        List {
            Section {
                Text("Add the shifts you work every week. They show on the calendar as planned blocks — tap Confirm to log one, or Skip for a day off.")
                    .font(.app(.footnote))
                    .foregroundStyle(Theme.textSecondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            }

            if !shifts.isEmpty {
                Section {
                    ForEach(shifts) { shift in
                        Button { editing = ShiftEditItem(shift: shift) } label: {
                            row(shift)
                        }
                        .themedRow()
                    }
                    .onDelete { offsets in
                        for index in offsets { modelContext.delete(shifts[index]) }
                    }
                } header: {
                    SectionLabel("Your shifts")
                }
            }

            Section {
                Button {
                    editing = ShiftEditItem(shift: nil)
                } label: {
                    Label("Add regular shift", systemImage: "plus.circle.fill")
                        .font(.app(.body, .semibold))
                        .foregroundStyle(Theme.gold)
                }
                .disabled(allProjects.isEmpty)
                .themedRow()
            } footer: {
                if allProjects.isEmpty {
                    Text("Create a project first.")
                        .font(.app(.footnote))
                }
            }
        }
        .themedScreen()
        .tabBarSpace()
        .navigationTitle("Regular shifts")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { item in
            ShiftEditorView(shift: item.shift, projects: allProjects)
                .environment(\.tabBarInset, 0)
        }
    }

    private func row(_ shift: RecurringShift) -> some View {
        let project = allProjects.first { $0.id == shift.projectID }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(shift.weekdaysText.isEmpty ? "No days" : shift.weekdaysText) · \(shift.timeRangeText)")
                    .font(.app(.body, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                Text(project.map { "\($0.job?.name ?? "") · \($0.name)" } ?? "Project deleted")
                    .font(.app(.footnote))
                    .foregroundStyle(project == nil ? Theme.danger : Theme.textSecondary)
                    .lineLimit(1)
                if !shift.taskDescription.isEmpty {
                    Text(shift.taskDescription)
                        .font(.app(.footnote))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if !shift.isActive {
                Text("Paused")
                    .font(.app(.caption, .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            Image(systemName: "chevron.right")
                .font(.app(.footnote, .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 4)
        .opacity(shift.isActive ? 1 : 0.6)
    }
}

private struct ShiftEditItem: Identifiable {
    let id = UUID()
    let shift: RecurringShift?
}

/// Create or edit one regular shift.
struct ShiftEditorView: View {
    let shift: RecurringShift?
    let projects: [Project]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var projectID: UUID?
    @State private var weekdays: Set<Int>
    @State private var start: Date
    @State private var end: Date
    @State private var breakMinutes: Int
    @State private var taskDescription: String
    @State private var isActive: Bool
    @State private var confirmDelete = false

    init(shift: RecurringShift?, projects: [Project]) {
        self.shift = shift
        self.projects = projects
        let midnight = Calendar.current.startOfDay(for: .now)
        func time(_ minutes: Int) -> Date { midnight.addingTimeInterval(TimeInterval(minutes * 60)) }
        let lastID = UUID(uuidString: UserDefaults.standard.string(forKey: AppSettings.Keys.lastProjectID) ?? "")
        _projectID = State(initialValue: shift?.projectID ?? projects.first { $0.id == lastID }?.id ?? projects.first?.id)
        _weekdays = State(initialValue: shift?.weekdays ?? [])
        _start = State(initialValue: time(shift?.startMinutes ?? 9 * 60))
        _end = State(initialValue: time(shift?.endMinutes ?? 13 * 60))
        _breakMinutes = State(initialValue: shift?.breakMinutes ?? 0)
        _taskDescription = State(initialValue: shift?.taskDescription ?? "")
        _isActive = State(initialValue: shift?.isActive ?? true)
    }

    private var orderedWeekdays: [Int] {
        let calendar = Calendar.current
        return (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    private func minutes(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private var spanMinutes: Int {
        let s = minutes(start), e = minutes(end)
        return e > s ? e - s : e + 24 * 60 - s
    }

    private var canSave: Bool {
        projectID != nil && !weekdays.isEmpty && spanMinutes > breakMinutes
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Project", selection: $projectID) {
                        ForEach(projects) { project in
                            Text("\(project.job?.name ?? "") · \(project.name)").tag(Optional(project.id))
                        }
                    }
                    .themedRow()
                } header: { SectionLabel("Project") }

                Section {
                    HStack(spacing: 6) {
                        ForEach(orderedWeekdays, id: \.self) { day in
                            let isOn = weekdays.contains(day)
                            Button {
                                if isOn { weekdays.remove(day) } else { weekdays.insert(day) }
                            } label: {
                                Text(Calendar.current.veryShortStandaloneWeekdaySymbols[day - 1])
                                    .font(.app(.subheadline, .bold))
                                    .foregroundStyle(isOn ? Theme.onGold : Theme.textPrimary)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(Circle().fill(isOn ? Theme.goldFill : Theme.surfaceRaised))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Calendar.current.standaloneWeekdaySymbols[day - 1])
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                    .themedRow()
                } header: { SectionLabel("Days") }

                Section {
                    DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                        .themedRow()
                    DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
                        .themedRow()
                    Stepper(value: $breakMinutes, in: 0...240, step: 15) {
                        HStack {
                            Text("Break")
                            Spacer()
                            Text("\(breakMinutes) min")
                                .foregroundStyle(Theme.textSecondary)
                                .monospacedDigit()
                        }
                    }
                    .themedRow()
                    HStack {
                        Text("Worked")
                        Spacer()
                        Text(DateDurationService.formattedDuration(hours: max(0, Double(spanMinutes - breakMinutes) / 60)))
                            .font(.app(.body, .semibold))
                            .foregroundStyle(Theme.gold)
                            .monospacedDigit()
                    }
                    .themedRow()
                } header: { SectionLabel("Time") }

                Section {
                    TextField("e.g. Office hours, tutoring", text: $taskDescription, axis: .vertical)
                        .lineLimit(1...3)
                        .themedRow()
                } header: { SectionLabel("Description") }

                Section {
                    Toggle("Show on calendar", isOn: $isActive)
                        .tint(Theme.goldFill)
                        .themedRow()
                }

                if shift != nil {
                    Section {
                        Button("Delete shift", role: .destructive) { confirmDelete = true }
                            .themedRow()
                    }
                }
            }
            .themedScreen()
            .navigationTitle(shift == nil ? "New regular shift" : "Edit shift")
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
            .confirmationDialog("Delete this regular shift?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let shift { modelContext.delete(shift) }
                    dismiss()
                }
            } message: {
                Text("Entries you already logged are kept.")
            }
        }
    }

    private func save() {
        guard let projectID else { return }
        let description = taskDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if let shift {
            shift.projectID = projectID
            shift.weekdays = weekdays
            shift.startMinutes = minutes(start)
            shift.endMinutes = minutes(end)
            shift.breakMinutes = breakMinutes
            shift.taskDescription = description
            shift.isActive = isActive
        } else {
            let new = RecurringShift(
                projectID: projectID,
                weekdays: weekdays,
                startMinutes: minutes(start),
                endMinutes: minutes(end),
                breakMinutes: breakMinutes,
                taskDescription: description,
                isActive: isActive
            )
            modelContext.insert(new)
        }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        ShiftTemplatesView()
    }
    .modelContainer(PreviewSupport.container)
}
