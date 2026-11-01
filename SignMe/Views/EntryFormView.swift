import SwiftUI
import SwiftData

/// Shared add/edit form for a WorkEntry. Passing `entryToEdit` switches the
/// form into edit mode; leaving it nil creates a brand-new entry on save.
struct EntryFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let project: Project
    var entryToEdit: WorkEntry?

    @State private var date: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var taskDescription: String

    init(project: Project, entryToEdit: WorkEntry? = nil) {
        self.project = project
        self.entryToEdit = entryToEdit
        _date = State(initialValue: entryToEdit?.date ?? .now)
        _startTime = State(initialValue: entryToEdit?.startTime ?? .now)
        _endTime = State(initialValue: entryToEdit?.endTime ?? Date().addingTimeInterval(3600))
        _taskDescription = State(initialValue: entryToEdit?.taskDescription ?? "")
    }

    private var combinedStart: Date { DateDurationService.combine(day: date, time: startTime) }
    private var combinedEnd: Date { DateDurationService.combine(day: date, time: endTime) }

    private var isTimeValid: Bool { DateDurationService.isValid(start: combinedStart, end: combinedEnd) }
    private var isDescriptionValid: Bool { !taskDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isValid: Bool { isTimeValid && isDescriptionValid }

    private var durationPreview: Double { DateDurationService.durationHours(from: combinedStart, to: combinedEnd) }

    var body: some View {
        NavigationStack {
            Form {
                Section("When") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                }

                Section {
                    durationPreviewRow
                    if !isTimeValid {
                        Label("End time must be after start time.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("Task Description") {
                    TextEditor(text: $taskDescription)
                        .frame(minHeight: 110)
                    if !isDescriptionValid {
                        Text("A short description is required.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(entryToEdit == nil ? "New Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }
            }
        }
    }

    private var durationPreviewRow: some View {
        HStack {
            Image(systemName: "clock.fill")
                .foregroundStyle(isTimeValid ? Color.accentColor : Color.secondary)
            Text("Duration")
            Spacer()
            Text(DateDurationService.formattedDuration(hours: max(0, durationPreview)))
                .font(.headline)
                .foregroundStyle(isTimeValid ? Color.accentColor : .secondary)
                .contentTransition(.numericText())
        }
        .animation(.easeInOut(duration: 0.2), value: durationPreview)
    }

    private func save() {
        guard isValid else { return }

        if let entry = entryToEdit {
            entry.date = date
            entry.startTime = combinedStart
            entry.endTime = combinedEnd
            entry.durationHours = DateDurationService.durationHours(from: combinedStart, to: combinedEnd)
            entry.taskDescription = taskDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.updatedAt = .now
        } else {
            let entry = WorkEntry(
                date: date,
                startTime: combinedStart,
                endTime: combinedEnd,
                taskDescription: taskDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                project: project
            )
            modelContext.insert(entry)
            project.entries.append(entry)
        }

        dismiss()
    }
}

#Preview {
    EntryFormView(project: PreviewSupport.sampleProject)
        .modelContainer(PreviewSupport.container)
}
