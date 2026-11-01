import SwiftUI
import SwiftData

private struct MonthGroup: Identifiable {
    let id: String
    let month: Date
    let entries: [WorkEntry]
}

private struct YearGroup: Identifiable {
    let id: String
    let year: Int
    let months: [MonthGroup]
}

/// Shows every WorkEntry inside a Project, grouped by year then month
/// (newest first), with add/edit/delete, multi-select batch actions, and export.
struct WorkEntryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allJobs: [Job]

    let project: Project

    @State private var selectionMode = false
    @State private var selectedEntryIDs: Set<UUID> = []

    @State private var expandedYearIDs: Set<String> = []
    @State private var expandedMonthIDs: Set<String> = []

    @State private var showingAddEntry = false
    @State private var entryToEdit: WorkEntry?

    @State private var entryPendingDelete: WorkEntry?
    @State private var showDeleteSingleConfirm = false
    @State private var showDeleteSelectedConfirm = false

    @State private var showingMovePicker = false
    @State private var showingCopyPicker = false
    @State private var showingExportRange = false
    @State private var moveBlockedMessage: String?

    var body: some View {
        Group {
            if project.entries.isEmpty {
                EmptyStateView(
                    icon: "clock.badge.questionmark",
                    title: "No entries yet",
                    message: "Log your first work entry for \(project.name).",
                    actionTitle: "Add Entry"
                ) { showingAddEntry = true }
            } else {
                entryList
            }
        }
        .navigationTitle(selectionMode ? "\(selectedEntryIDs.count) Selected" : project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) {
            if selectionMode {
                selectionActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectionMode)
        .sheet(isPresented: $showingAddEntry) {
            EntryFormView(project: project)
        }
        .sheet(item: $entryToEdit) { entry in
            EntryFormView(project: project, entryToEdit: entry)
        }
        .sheet(isPresented: $showingMovePicker) {
            DestinationPickerView(mode: .project, jobs: allJobs, excludingProject: project, onSelectProject: { destination in
                moveSelectedEntries(to: destination)
            })
        }
        .sheet(isPresented: $showingCopyPicker) {
            DestinationPickerView(mode: .project, jobs: allJobs, excludingProject: project, onSelectProject: { destination in
                copySelectedEntries(to: destination)
            })
        }
        .sheet(isPresented: $showingExportRange) {
            ExportRangeSheet(project: project)
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: $showDeleteSingleConfirm,
            titleVisibility: .visible,
            presenting: entryPendingDelete
        ) { entry in
            Button("Delete Entry", role: .destructive) { delete(entry) }
        } message: { _ in
            Text("This can't be undone.")
        }
        .confirmationDialog(
            "Delete \(selectedEntryIDs.count) entries?",
            isPresented: $showDeleteSelectedConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete \(selectedEntryIDs.count) Entries", role: .destructive) { deleteSelectedEntries() }
        } message: {
            Text("This can't be undone.")
        }
        .alert("Can't Move or Copy", isPresented: Binding(
            get: { moveBlockedMessage != nil },
            set: { if !$0 { moveBlockedMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(moveBlockedMessage ?? "")
        }
    }

    // MARK: - List

    private var entryList: some View {
        List {
            ForEach(groupedByYear) { yearGroup in
                Section {
                    if isYearExpanded(yearGroup.id) {
                        ForEach(yearGroup.months) { monthGroup in
                            monthHeader(monthGroup)
                            if isMonthExpanded(monthGroup.id) {
                                ForEach(monthGroup.entries) { entry in
                                    entryRow(entry)
                                }
                            }
                        }
                    }
                } header: {
                    yearHeader(yearGroup)
                }
                .listSectionSpacing(20)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }

    private func entryRow(_ entry: WorkEntry) -> some View {
        let isSelected = selectedEntryIDs.contains(entry.id)
        return Button {
            if selectionMode {
                toggleSelection(entry)
            } else {
                entryToEdit = entry
            }
        } label: {
            EntryRowView(entry: entry, isSelected: isSelected, selectionMode: selectionMode)
                .padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.06), lineWidth: isSelected ? 1.5 : 1)
                )
                .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .swipeActions(edge: .trailing) {
            if !selectionMode {
                Button(role: .destructive) {
                    entryPendingDelete = entry
                    showDeleteSingleConfirm = true
                } label: { Label("Delete", systemImage: "trash") }

                Button { entryToEdit = entry } label: { Label("Edit", systemImage: "pencil") }
                    .tint(.orange)
            }
        }
        .contextMenu {
            if !selectionMode {
                Button { entryToEdit = entry } label: { Label("Edit", systemImage: "pencil") }
                Button(role: .destructive) {
                    entryPendingDelete = entry
                    showDeleteSingleConfirm = true
                } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    private func yearHeader(_ group: YearGroup) -> some View {
        let yearHours = group.months.flatMap(\.entries).reduce(0) { $0 + $1.durationHours }
        return Button {
            withAnimation(.easeInOut(duration: 0.22)) { toggleYear(group.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isYearExpanded(group.id) ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                Text(String(group.year))
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                Spacer()
                Text(DateDurationService.formattedDuration(hours: yearHours))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
    }

    private func monthHeader(_ group: MonthGroup) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { toggleMonth(group.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isMonthExpanded(group.id) ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 14)
                Text(DateDurationService.monthYearFormatter.string(from: group.month))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(group.entries.count) \(group.entries.count == 1 ? "entry" : "entries")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(DateDurationService.formattedDuration(hours: group.entries.reduce(0) { $0 + $1.durationHours }))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if selectionMode {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { exitSelectionMode() }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { withAnimation { selectionMode = true } } label: {
                        Label("Select Entries", systemImage: "checkmark.circle")
                    }
                    Button { showingExportRange = true } label: {
                        Label("Export Date Range…", systemImage: "calendar.badge.clock")
                    }
                    if let allURL = ExportService.csvExportURL(entries: project.entries, filenamePrefix: project.name) {
                        ShareLink(item: allURL) {
                            Label("Export All (CSV)", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddEntry = true } label: { Image(systemName: "plus") }
            }
        }
    }

    // MARK: - Selection action bar

    private var selectionActionBar: some View {
        VStack(spacing: 10) {
            HStack {
                actionBarButton("Delete", "trash", disabled: selectedEntryIDs.isEmpty, tint: .red) {
                    showDeleteSelectedConfirm = true
                }
                Spacer()
                actionBarButton("Copy", "doc.on.doc", disabled: selectedEntryIDs.isEmpty) {
                    showingCopyPicker = true
                }
                Spacer()
                actionBarButton("Move", "folder", disabled: selectedEntryIDs.isEmpty) {
                    showingMovePicker = true
                }
                Spacer()
                exportButton
            }
            Divider()
            HStack {
                Button(selectedEntryIDs.count == project.entries.count ? "Deselect All" : "Select All") {
                    toggleSelectAll()
                }
                .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Cancel") { exitSelectionMode() }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var exportButton: some View {
        Group {
            if let url = selectedExportURL {
                ShareLink(item: url) {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export").font(.caption2)
                    }
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export").font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }
        }
    }

    private func actionBarButton(_ title: String, _ icon: String, disabled: Bool, tint: Color = .accentColor, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                Text(title).font(.caption2)
            }
        }
        .foregroundStyle(disabled ? Color.secondary.opacity(0.4) : tint)
        .disabled(disabled)
    }

    // MARK: - Grouping

    private var groupedByYear: [YearGroup] {
        let calendar = Calendar.current
        let sorted = project.entries.sorted { $0.date > $1.date }
        let byYear = Dictionary(grouping: sorted) { calendar.component(.year, from: $0.date) }

        return byYear.keys.sorted(by: >).map { year in
            let yearEntries = byYear[year] ?? []
            let byMonth = Dictionary(grouping: yearEntries) { calendar.component(.month, from: $0.date) }
            let months = byMonth.keys.sorted(by: >).map { month -> MonthGroup in
                let monthEntries = (byMonth[month] ?? []).sorted { $0.date > $1.date }
                let monthDate = calendar.date(from: DateComponents(year: year, month: month)) ?? .now
                return MonthGroup(id: "\(year)-\(month)", month: monthDate, entries: monthEntries)
            }
            return YearGroup(id: "\(year)", year: year, months: months)
        }
    }

    // Sections start collapsed: a year/month is only expanded once its id has
    // been explicitly opened by the user.
    private func isYearExpanded(_ id: String) -> Bool { expandedYearIDs.contains(id) }
    private func isMonthExpanded(_ id: String) -> Bool { expandedMonthIDs.contains(id) }

    private func toggleYear(_ id: String) {
        if expandedYearIDs.contains(id) { expandedYearIDs.remove(id) } else { expandedYearIDs.insert(id) }
    }

    private func toggleMonth(_ id: String) {
        if expandedMonthIDs.contains(id) { expandedMonthIDs.remove(id) } else { expandedMonthIDs.insert(id) }
    }

    // MARK: - Selection

    private func toggleSelection(_ entry: WorkEntry) {
        if selectedEntryIDs.contains(entry.id) {
            selectedEntryIDs.remove(entry.id)
        } else {
            selectedEntryIDs.insert(entry.id)
        }
    }

    private func toggleSelectAll() {
        if selectedEntryIDs.count == project.entries.count {
            selectedEntryIDs.removeAll()
        } else {
            selectedEntryIDs = Set(project.entries.map(\.id))
        }
    }

    private func exitSelectionMode() {
        selectionMode = false
        selectedEntryIDs.removeAll()
    }

    private var selectedEntries: [WorkEntry] {
        project.entries.filter { selectedEntryIDs.contains($0.id) }
    }

    private var selectedExportURL: URL? {
        guard !selectedEntries.isEmpty else { return nil }
        return ExportService.csvExportURL(entries: selectedEntries, filenamePrefix: "\(project.name)-Selected")
    }

    // MARK: - Mutations

    private func delete(_ entry: WorkEntry) {
        if let idx = project.entries.firstIndex(where: { $0.id == entry.id }) {
            project.entries.remove(at: idx)
        }
        modelContext.delete(entry)
    }

    private func deleteSelectedEntries() {
        for entry in selectedEntries {
            if let idx = project.entries.firstIndex(where: { $0.id == entry.id }) {
                project.entries.remove(at: idx)
            }
            modelContext.delete(entry)
        }
        exitSelectionMode()
    }

    private func moveSelectedEntries(to destination: Project) {
        guard destination.id != project.id else {
            moveBlockedMessage = "The destination project is the same as the source project."
            return
        }
        for entry in selectedEntries {
            if let idx = project.entries.firstIndex(where: { $0.id == entry.id }) {
                project.entries.remove(at: idx)
            }
            entry.project = destination
            entry.updatedAt = .now
            destination.entries.append(entry)
        }
        exitSelectionMode()
    }

    private func copySelectedEntries(to destination: Project) {
        guard destination.id != project.id else {
            moveBlockedMessage = "The destination project is the same as the source project."
            return
        }
        for entry in selectedEntries {
            let copy = WorkEntry(
                date: entry.date,
                startTime: entry.startTime,
                endTime: entry.endTime,
                taskDescription: entry.taskDescription,
                project: destination
            )
            modelContext.insert(copy)
            destination.entries.append(copy)
        }
        exitSelectionMode()
    }
}

/// Lets the user pick a date range and export the matching entries as CSV.
private struct ExportRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let project: Project

    @State private var startDate: Date
    @State private var endDate: Date

    init(project: Project) {
        self.project = project
        let dates = project.entries.map(\.date)
        _startDate = State(initialValue: dates.min() ?? .now)
        _endDate = State(initialValue: dates.max() ?? .now)
    }

    private var filteredEntries: [WorkEntry] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate
        return project.entries.filter { $0.date >= start && $0.date < end }
    }

    private var exportURL: URL? {
        ExportService.csvExportURL(entries: filteredEntries, filenamePrefix: "\(project.name)-Range")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Range") {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("To", selection: $endDate, displayedComponents: .date)
                }
                Section {
                    HStack {
                        Text("Matching Entries")
                        Spacer()
                        Text("\(filteredEntries.count)").foregroundStyle(.secondary)
                    }
                }
                Section {
                    if let exportURL, !filteredEntries.isEmpty {
                        ShareLink(item: exportURL) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Label("No entries in this range", systemImage: "tray")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Export Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

#Preview {
    NavigationStack {
        WorkEntryListView(project: PreviewSupport.sampleProject)
    }
    .modelContainer(PreviewSupport.container)
}
