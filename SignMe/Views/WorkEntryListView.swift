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

/// Drives the "add entry on this day" sheet from the calendar.
private struct AddEntryDate: Identifiable {
    let id = UUID()
    let date: Date
}

/// Shows every WorkEntry inside a Project — as a list grouped by year then month
/// (newest first) or as a month calendar — with add/edit/delete, multi-select
/// batch actions, and export.
struct WorkEntryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Job.createdAt) private var allJobs: [Job]

    let project: Project

    private enum ViewMode: String, CaseIterable {
        case list = "List"
        case calendar = "Calendar"
    }

    @State private var viewMode: ViewMode = .list
    @State private var calendarMonth: Date = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var addEntryDate: AddEntryDate?
    @State private var showingExportMonth = false

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
    @State private var shareItem: ShareItem?
    @State private var didApplyInitialExpansion = false

    var body: some View {
        VStack(spacing: 0) {
            if !selectionMode {
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            if viewMode == .calendar && !selectionMode {
                WorkCalendarView(project: project)
            } else if project.entries.isEmpty {
                EmptyStateView(
                    icon: "clock.badge.questionmark",
                    title: "No entries yet",
                    message: "Log your first work entry for \(project.name).",
                    actionTitle: "Add Entry"
                ) { showingAddEntry = true }
                Spacer(minLength: 0)
            } else {
                entryList
            }
        }
        .themedScreen()
        .navigationTitle(selectionMode ? "\(selectedEntryIDs.count) Selected" : project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) {
            if selectionMode {
                selectionActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Outermost: keeps the list and the selection bar above the app's tab bar.
        .tabBarSpace()
        .animation(.easeInOut(duration: 0.2), value: selectionMode)
        .onAppear(perform: applyInitialExpansion)
        .onChange(of: project.entries.count) { oldCount, newCount in
            applyInitialExpansion()
            // Make sure a newly added/copied/moved-in entry isn't hidden in a collapsed month.
            if newCount > oldCount, let newest = project.entries.max(by: { $0.updatedAt < $1.updatedAt }) {
                reveal(newest)
            }
        }
        .shareSheet(item: $shareItem)
        .sheet(isPresented: $showingAddEntry) {
            EntryFormView(project: project)
        }
        .sheet(item: $entryToEdit) { entry in
            EntryFormView(project: project, entryToEdit: entry)
        }
        .sheet(item: $addEntryDate) { item in
            EntryFormView(project: project, initialDate: item.date)
        }
        .sheet(isPresented: $showingExportMonth) {
            ExportMonthSheet(jobs: allJobs, initialProject: project, initialMonth: calendarMonth)
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
            if hiddenSelectedCount > 0 {
                Text("\(hiddenSelectedCount) of them \(hiddenSelectedCount == 1 ? "is" : "are") in collapsed months. This can't be undone.")
            } else {
                Text("This can't be undone.")
            }
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
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isSelected ? Theme.gold : Color.clear, lineWidth: 1.5)
                )
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
                    .font(.app(.title3))
                    .foregroundStyle(Theme.gold)
                Text(String(group.year))
                    .font(Theme.display(.title3))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(DateDurationService.formattedDuration(hours: yearHours))
                    .font(.app(.subheadline, .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
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
                    .font(.app(.caption, .bold))
                    .foregroundStyle(Theme.gold)
                    .frame(width: 14)
                Text(DateDurationService.monthYearFormatter.string(from: group.month))
                    .font(.app(.subheadline, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(group.entries.count) \(group.entries.count == 1 ? "entry" : "entries")")
                    .font(.app(.caption2))
                    .foregroundStyle(Theme.textSecondary)
                Text(DateDurationService.formattedDuration(hours: group.entries.reduce(0) { $0 + $1.durationHours }))
                    .font(.app(.caption, .semibold))
                    .foregroundStyle(Theme.gold)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Theme.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    Button {
                        shareItem = ShareItem(ExportService.csvExportURL(entries: project.entries, filenamePrefix: project.name))
                    } label: {
                        Label("Export All (CSV)", systemImage: "square.and.arrow.up")
                    }
                    .disabled(project.entries.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingExportMonth = true } label: { Image(systemName: "signature") }
                    .accessibilityLabel("Export signed month")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddEntry = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add entry")
            }
        }
    }

    // MARK: - Selection action bar

    private var selectionActionBar: some View {
        VStack(spacing: 10) {
            HStack {
                actionBarButton("Delete", "trash", disabled: selectedEntryIDs.isEmpty, tint: Theme.danger) {
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
                actionBarButton("Export", "square.and.arrow.up", disabled: selectedEntryIDs.isEmpty) {
                    exportSelectedEntries()
                }
            }
            Divider()
            HStack {
                Button(allVisibleSelected ? "Deselect All" : "Select All") {
                    toggleSelectAll()
                }
                .disabled(visibleEntries.isEmpty)
                .font(.app(.subheadline, .semibold))
                Spacer()
                Button("Cancel") { exitSelectionMode() }
                    .font(.app(.subheadline, .semibold))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .foregroundStyle(Theme.gold)
        .background(Theme.tabBar.ignoresSafeArea(edges: .bottom))
    }

    private func actionBarButton(_ title: String, _ icon: String, disabled: Bool, tint: Color = Theme.gold, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                Text(title).font(.app(.caption2))
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .foregroundStyle(disabled ? Theme.textTertiary.opacity(0.5) : tint)
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

    // A year/month is expanded only while its id is in the expanded set. On first
    // appearance the most recent year and month are opened so entries are visible
    // right away; everything older starts collapsed.
    private func applyInitialExpansion() {
        guard !didApplyInitialExpansion, let latestYear = groupedByYear.first else { return }
        didApplyInitialExpansion = true
        expandedYearIDs.insert(latestYear.id)
        if let latestMonth = latestYear.months.first {
            expandedMonthIDs.insert(latestMonth.id)
        }
    }

    /// Expands the year and month that contain `entry`. Ids match `groupedByYear`.
    private func reveal(_ entry: WorkEntry) {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: entry.date)
        let month = calendar.component(.month, from: entry.date)
        expandedYearIDs.insert("\(year)")
        expandedMonthIDs.insert("\(year)-\(month)")
    }

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

    /// Entries currently on screen — i.e. inside an expanded year *and* month.
    private var visibleEntries: [WorkEntry] {
        groupedByYear
            .filter { isYearExpanded($0.id) }
            .flatMap(\.months)
            .filter { isMonthExpanded($0.id) }
            .flatMap(\.entries)
    }

    private var allVisibleSelected: Bool {
        let visible = visibleEntries
        return !visible.isEmpty && visible.allSatisfy { selectedEntryIDs.contains($0.id) }
    }

    /// Selected entries the user can't currently see (their month is collapsed).
    private var hiddenSelectedCount: Int {
        let visibleIDs = Set(visibleEntries.map(\.id))
        return selectedEntryIDs.subtracting(visibleIDs).count
    }

    /// Select All / Deselect All only affects entries that are visible, so a bulk
    /// action never silently includes entries hidden in collapsed months.
    private func toggleSelectAll() {
        let visibleIDs = Set(visibleEntries.map(\.id))
        if allVisibleSelected {
            selectedEntryIDs.subtract(visibleIDs)
        } else {
            selectedEntryIDs.formUnion(visibleIDs)
        }
    }

    private func exitSelectionMode() {
        selectionMode = false
        selectedEntryIDs.removeAll()
    }

    private var selectedEntries: [WorkEntry] {
        project.entries.filter { selectedEntryIDs.contains($0.id) }
    }

    private func exportSelectedEntries() {
        let entries = selectedEntries
        guard !entries.isEmpty else { return }
        shareItem = ShareItem(ExportService.csvExportURL(entries: entries, filenamePrefix: "\(project.name)-Selected"))
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
            entry.updatedAt = .now
            destination.entries.append(entry)  // SwiftData updates entry.project via the inverse
        }
        exitSelectionMode()
    }

    private func copySelectedEntries(to destination: Project) {
        guard destination.id != project.id else {
            moveBlockedMessage = "The destination project is the same as the source project."
            return
        }
        for entry in selectedEntries {
            let copy = entry.duplicate()
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
    @State private var shareItem: ShareItem?

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

    private func exportCSV() {
        let entries = filteredEntries
        guard !entries.isEmpty else { return }
        shareItem = ShareItem(ExportService.csvExportURL(entries: entries, filenamePrefix: "\(project.name)-Range"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Range") {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("To", selection: $endDate, displayedComponents: .date)
                }
                .themedRow()
                Section {
                    HStack {
                        Text("Matching Entries")
                        Spacer()
                        Text("\(filteredEntries.count)").foregroundStyle(Theme.textSecondary)
                    }
                }
                .themedRow()
                Section {
                    if !filteredEntries.isEmpty {
                        Button(action: exportCSV) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Label("No entries in this range", systemImage: "tray")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .themedRow()
            }
            .themedScreen()
            .navigationTitle("Export Range")
            .navigationBarTitleDisplayMode(.inline)
            .shareSheet(item: $shareItem)
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
