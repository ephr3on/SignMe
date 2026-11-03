import SwiftUI
import SwiftData

/// Search & browse every work entry.
/// - A search field that stays at the top of the page (it never jumps or hides).
/// - Every word typed must match the task, project, job, or the date
///   (e.g. "tutoring oktober", "office 12.10.", "monday").
/// - Period and job filters; results grouped by month with entry counts and totals.
/// - With an empty search the page lists everything, newest first.
struct SearchWorkEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkEntry.startTime, order: .reverse) private var allEntries: [WorkEntry]
    @Query(sort: \Job.createdAt) private var jobs: [Job]

    @State private var query = ""
    @State private var period: Period = .all
    @State private var jobFilterID: UUID?
    @State private var entryToEdit: WorkEntry?
    @State private var entryPendingDelete: WorkEntry?
    @FocusState private var searchFocused: Bool

    enum Period: String, CaseIterable, Identifiable {
        case all = "All time"
        case thisWeek = "This week"
        case thisMonth = "This month"
        case lastMonth = "Last month"
        case thisYear = "This year"

        var id: String { rawValue }

        func contains(_ date: Date, calendar: Calendar = .current, now: Date = .now) -> Bool {
            switch self {
            case .all:
                return true
            case .thisWeek:
                return calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear)
            case .thisMonth:
                return calendar.isDate(date, equalTo: now, toGranularity: .month)
            case .lastMonth:
                guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) else { return false }
                return calendar.isDate(date, equalTo: lastMonth, toGranularity: .month)
            case .thisYear:
                return calendar.isDate(date, equalTo: now, toGranularity: .year)
            }
        }
    }

    private struct MonthSection: Identifiable {
        let id: String
        let title: String
        let entries: [WorkEntry]
        var hours: Double { entries.reduce(0) { $0 + $1.durationHours } }
    }

    // MARK: - Filtering

    private var tokens: [String] {
        query
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    private var results: [WorkEntry] {
        let words = tokens
        return allEntries.filter { entry in
            guard period.contains(entry.date) else { return false }
            if let jobFilterID, entry.project?.job?.id != jobFilterID { return false }
            guard !words.isEmpty else { return true }
            let haystack = Self.searchText(for: entry)
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    private var sections: [MonthSection] {
        let calendar = Calendar.current
        var order: [String] = []
        var grouped: [String: [WorkEntry]] = [:]
        var titles: [String: String] = [:]
        for entry in results {
            let components = calendar.dateComponents([.year, .month], from: entry.date)
            let key = "\(components.year ?? 0)-\(components.month ?? 0)"
            if grouped[key] == nil {
                order.append(key)
                titles[key] = DateDurationService.monthYearFormatter.string(from: entry.date)
            }
            grouped[key, default: []].append(entry)
        }
        return order.map { MonthSection(id: $0, title: titles[$0] ?? $0, entries: grouped[$0] ?? []) }
    }

    /// Everything an entry can be found by, folded to lower case without accents.
    private static func searchText(for entry: WorkEntry) -> String {
        let parts = [
            entry.taskDescription,
            entry.project?.name ?? "",
            entry.project?.job?.name ?? "",
            DateDurationService.dateFormatter.string(from: entry.date),
            DateDurationService.signatureDateFormatter.string(from: entry.date),
            DateDurationService.isoDateFormatter.string(from: entry.date),
            DateDurationService.monthYearFormatter.string(from: entry.date),
            entry.date.formatted(.dateTime.weekday(.wide))
        ]
        return parts.joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private var hasActiveFilters: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || period != .all || jobFilterID != nil
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12, pinnedViews: []) {
                TabHeader(title: "Search", subtitle: "Every entry across all jobs")
                searchField
                filterBar
                summary
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .themedScreen()
        .tabBarSpace()
        .navigationTitle("Search")
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $entryToEdit) { entry in
            EntryFormView(entryToEdit: entry)
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(
                get: { entryPendingDelete != nil },
                set: { if !$0 { entryPendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: entryPendingDelete
        ) { entry in
            Button("Delete Entry", role: .destructive) { delete(entry) }
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            TextField("Task, project, job or date", text: $query)
                .font(.app(.body))
                .foregroundStyle(Theme.textPrimary)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minHeight: 50)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(searchFocused ? Theme.gold.opacity(0.6) : Theme.cardBorder, lineWidth: searchFocused ? 1.5 : 1)
        )
    }

    // MARK: Filters

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Period", selection: $period) {
                        ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    filterPill(title: period.rawValue, icon: "calendar", isActive: period != .all)
                }

                if jobs.count > 1 {
                    Menu {
                        Picker("Job", selection: $jobFilterID) {
                            Text("All jobs").tag(UUID?.none)
                            ForEach(jobs) { job in
                                Text(job.name).tag(Optional(job.id))
                            }
                        }
                    } label: {
                        filterPill(
                            title: jobs.first { $0.id == jobFilterID }?.name ?? "All jobs",
                            icon: "briefcase",
                            isActive: jobFilterID != nil
                        )
                    }
                }

                if hasActiveFilters {
                    Button {
                        withAnimation {
                            query = ""
                            period = .all
                            jobFilterID = nil
                        }
                    } label: {
                        Text("Reset")
                            .font(.app(.subheadline, .semibold))
                            .foregroundStyle(Theme.gold)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 38)
                    }
                }
            }
        }
    }

    private func filterPill(title: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.app(.footnote, .semibold))
            Text(title)
                .font(.app(.subheadline, .semibold))
            Image(systemName: "chevron.down")
                .font(.app(.caption2, .bold))
        }
        .foregroundStyle(isActive ? Theme.onGold : Theme.textPrimary)
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .background(Capsule().fill(isActive ? Theme.goldFill : Theme.surface))
        .overlay(Capsule().strokeBorder(isActive ? Color.clear : Theme.cardBorder, lineWidth: 1))
    }

    // MARK: Summary & results

    @ViewBuilder
    private var summary: some View {
        let entries = results
        if !allEntries.isEmpty && !entries.isEmpty {
            let hours = entries.reduce(0) { $0 + $1.durationHours }
            Text("\(entries.count) \(entries.count == 1 ? "entry" : "entries") · \(DateDurationService.formattedDuration(hours: hours))")
                .font(.app(.footnote, .medium))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var content: some View {
        if allEntries.isEmpty {
            EmptyStateView(
                icon: "clock.arrow.circlepath",
                title: "Nothing to search yet",
                message: "Entries you log will show up here, ready to search."
            )
            .padding(.top, 24)
        } else if sections.isEmpty {
            VStack(spacing: 12) {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No matches",
                    message: "Try fewer or different words, or reset the filters."
                )
                Button("Reset search") {
                    query = ""
                    period = .all
                    jobFilterID = nil
                }
                .font(.app(.subheadline, .semibold))
                .foregroundStyle(Theme.gold)
            }
            .padding(.top, 24)
        } else {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(section.title)
                            .font(.display(.headline))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(section.entries.count) · \(DateDurationService.formattedDuration(hours: section.hours))")
                            .font(.app(.footnote, .semibold))
                            .foregroundStyle(Theme.gold)
                            .monospacedDigit()
                    }
                    .padding(.top, 10)

                    ForEach(section.entries) { entry in
                        Button {
                            entryToEdit = entry
                        } label: {
                            EntryRowView(entry: entry, showsProjectContext: true)
                                .card(padding: 12, radius: 16)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { entryToEdit = entry }
                            Button("Delete", systemImage: "trash", role: .destructive) { entryPendingDelete = entry }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func delete(_ entry: WorkEntry) {
        if let project = entry.project, let index = project.entries.firstIndex(where: { $0.id == entry.id }) {
            project.entries.remove(at: index)
        }
        modelContext.delete(entry)
    }
}

#Preview {
    NavigationStack {
        SearchWorkEntryView()
    }
    .modelContainer(PreviewSupport.container)
}
