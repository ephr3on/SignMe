import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The Jobs tab: search, add, rename, delete jobs, and backup export/import.
struct JobListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Job.createdAt, order: .reverse) private var allJobs: [Job]

    @State private var searchText = ""
    @State private var showingAddJob = false
    @State private var jobToRename: Job?
    @State private var jobPendingDelete: Job?
    @State private var showDeleteConfirm = false

    @State private var showingImporter = false
    @State private var importSummaryMessage: String?
    @State private var importErrorMessage: String?

    @State private var selectedJob: Job?

    private var filteredJobs: [Job] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return allJobs }
        return allJobs.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if allJobs.isEmpty {
                EmptyStateView(
                    icon: "briefcase",
                    title: "No jobs yet",
                    message: "Create your first job to start tracking work.",
                    actionTitle: "Add Job"
                ) { showingAddJob = true }
            } else {
                List {
                    ForEach(filteredJobs) { job in
                        Button {
                            selectedJob = job
                        } label: {
                            JobCardView(job: job)
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                jobPendingDelete = job
                                showDeleteConfirm = true
                            } label: { Label("Delete", systemImage: "trash") }

                            Button { jobToRename = job } label: { Label("Rename", systemImage: "pencil") }
                                .tint(.orange)
                        }
                        .contextMenu {
                            Button { jobToRename = job } label: { Label("Rename", systemImage: "pencil") }
                            Button(role: .destructive) {
                                jobPendingDelete = job
                                showDeleteConfirm = true
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Search jobs")
                .overlay {
                    if !searchText.isEmpty && filteredJobs.isEmpty {
                        EmptyStateView(icon: "magnifyingglass", title: "No matches", message: "Try a different search term.")
                    }
                }
            }
        }
        .navigationTitle("Jobs")
        .navigationDestination(item: $selectedJob) { job in
            ProjectListView(job: job)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingAddJob = true } label: { Label("Add Job", systemImage: "plus") }
                    if let backupURL = ExportService.backupExportURL(jobs: allJobs) {
                        ShareLink(item: backupURL) { Label("Export Backup", systemImage: "square.and.arrow.up") }
                    }
                    Button { showingImporter = true } label: { Label("Import Backup", systemImage: "square.and.arrow.down") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddJob = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAddJob) {
            NameEntrySheet(title: "New Job", fieldLabel: "Job Name") { name in
                let job = Job(name: name)
                modelContext.insert(job)
            }
        }
        .sheet(item: $jobToRename) { job in
            NameEntrySheet(title: "Rename Job", fieldLabel: "Job Name", initialValue: job.name) { newName in
                job.name = newName
            }
        }
        .confirmationDialog(
            "Delete this job?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible,
            presenting: jobPendingDelete
        ) { job in
            Button("Delete \"\(job.name)\"", role: .destructive) { modelContext.delete(job) }
        } message: { job in
            Text("This will permanently delete \"\(job.name)\" and all of its projects and entries.")
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json], onCompletion: handleImport)
        .alert("Import Complete", isPresented: Binding(
            get: { importSummaryMessage != nil },
            set: { if !$0 { importSummaryMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(importSummaryMessage ?? "")
        }
        .alert("Import Failed", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(importErrorMessage ?? "")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let summary = try BackupService.importData(data, into: modelContext, existingJobs: allJobs)
                if summary.isEmpty {
                    importSummaryMessage = "Nothing new to import — your data is already up to date."
                } else {
                    importSummaryMessage = "Added \(summary.newJobs) job(s), \(summary.newProjects) project(s), and \(summary.newEntries) entr\(summary.newEntries == 1 ? "y" : "ies"). Skipped \(summary.skippedDuplicates) duplicate(s)."
                }
            } catch {
                importErrorMessage = error.localizedDescription
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        JobListView()
    }
    .modelContainer(PreviewSupport.container)
}
