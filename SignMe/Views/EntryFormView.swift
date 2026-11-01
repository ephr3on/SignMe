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
    @State private var breakMinutes: Int
    @State private var taskDescription: String

    init(project: Project, entryToEdit: WorkEntry? = nil) {
        self.project = project
        self.entryToEdit = entryToEdit
        _date = State(initialValue: entryToEdit?.date ?? .now)
        _startTime = State(initialValue: entryToEdit?.startTime ?? .now)
        _endTime = State(initialValue: entryToEdit?.endTime ?? Date().addingTimeInterval(3600))
        _breakMinutes = State(initialValue: entryToEdit?.breakMinutes ?? 0)
        _taskDescription = State(initialValue: entryToEdit?.taskDescription ?? "")
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
    private var isDescriptionValid: Bool { !taskDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isValid: Bool { isTimeValid && isBreakValid && isDescriptionValid }

    private var durationPreview: Double {
        DateDurationService.durationHours(from: interval.start, to: interval.end, breakMinutes: breakMinutes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("When") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker(selection: $endTime, displayedComponents: .hourAndMinute) {
                        HStack(spacing: 6) {
                            Text("End")
                            if spansMidnight {
                                Text("+1 day")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                    Stepper(value: $breakMinutes, in: 0...480, step: 5) {
                        HStack {
                            Text("Break")
                            Spacer()
                            Text(breakMinutes == 0 ? "None" : DateDurationService.formattedDuration(hours: Double(breakMinutes) / 60))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    durationPreviewRow
                    if !isTimeValid {
                        Label("End time must be different from start time.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else if !isBreakValid {
                        Label("The break must be shorter than the time worked.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else if spansMidnight {
                        Label("This entry runs past midnight and ends the next day.", systemImage: "moon.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
        let isPositive = isTimeValid && isBreakValid
        return HStack {
            Image(systemName: "clock.fill")
                .foregroundStyle(isPositive ? Color.accentColor : Color.secondary)
            Text("Duration")
            Spacer()
            Text(DateDurationService.formattedDuration(hours: durationPreview))
                .font(.headline)
                .foregroundStyle(isPositive ? Color.accentColor : .secondary)
                .contentTransition(.numericText())
        }
        .animation(.easeInOut(duration: 0.2), value: durationPreview)
    }

    private func save() {
        guard isValid else { return }
        let resolved = interval
        let description = taskDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        if let entry = entryToEdit {
            entry.date = resolved.start
            entry.startTime = resolved.start
            entry.endTime = resolved.end
            entry.breakMinutes = breakMinutes
            entry.taskDescription = description
            entry.recalculateDuration()
            entry.updatedAt = .now
        } else {
            let entry = WorkEntry(
                date: resolved.start,
                startTime: resolved.start,
                endTime: resolved.end,
                breakMinutes: breakMinutes,
                taskDescription: description
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
