import SwiftUI
import SwiftData

/// Global search across every work entry's task description, job name,
/// project name, and formatted date.
struct SearchWorkEntryView: View {
    @Query private var allEntries: [WorkEntry]

    @State private var query = ""
    @State private var entryToEdit: WorkEntry?

    private var results: [WorkEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let needle = trimmed.lowercased()

        return allEntries.filter { entry in
            entry.taskDescription.lowercased().contains(needle) ||
            (entry.project?.name.lowercased().contains(needle) ?? false) ||
            (entry.project?.job?.name.lowercased().contains(needle) ?? false) ||
            DateDurationService.dateFormatter.string(from: entry.date).lowercased().contains(needle)
        }
        .sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "Search your work",
                    message: "Find entries by task, job, project, or date."
                )
            } else if results.isEmpty {
                EmptyStateView(
                    icon: "questionmark.folder",
                    title: "No matches",
                    message: "Try a different search term."
                )
            } else {
                List(results) { entry in
                    Button { entryToEdit = entry } label: {
                        EntryRowView(entry: entry, showsProjectContext: true)
                            .card(padding: 12, radius: 16)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                .listStyle(.plain)
            }
        }
        .themedScreen()
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Search entries, jobs, projects…")
        .sheet(item: $entryToEdit) { entry in
            if let project = entry.project {
                EntryFormView(project: project, entryToEdit: entry)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SearchWorkEntryView()
    }
    .modelContainer(PreviewSupport.container)
    .preferredColorScheme(.dark)
}
