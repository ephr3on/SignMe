import SwiftUI
import SwiftData

/// The Jobs tab: search, add, rename, delete jobs, and backup export/import.
struct JobListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Job.createdAt, order: .reverse) private var allJobs: [Job]
    @Query(sort: \SavedSignature.createdAt) private var signatures: [SavedSignature]

    @State private var searchText = ""
    @State private var showingAddJob = false
    @State private var jobToRename: Job?
    @State private var jobPendingDelete: Job?
    @State private var showDeleteConfirm = false

    @State private var showingImporter = false
    @State private var shareItem: ShareItem?

    @State private var selectedJob: Job?

    private var filteredJobs: [Job] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return allJobs }
        return allJobs.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var header: some View {
        TabHeader(
            title: "Jobs",
            subtitle: allJobs.isEmpty ? nil : "\(allJobs.count) \(allJobs.count == 1 ? "job" : "jobs")"
        ) {
            Menu {
                Button { showingAddJob = true } label: { Label("Add Job", systemImage: "plus") }
                Button {
                    shareItem = ShareItem(ExportService.backupExportURL(jobs: allJobs, signatures: signatures))
                } label: {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                }
                Button { showingImporter = true } label: { Label("Import Backup", systemImage: "square.and.arrow.down") }
            } label: {
                HeaderIcon(systemName: "ellipsis")
            }
            .accessibilityLabel("More")
            Button { showingAddJob = true } label: { HeaderIcon(systemName: "plus") }
                .buttonStyle(.plain)
                .accessibilityLabel("Add job")
        }
    }

    var body: some View {
        Group {
            if allJobs.isEmpty {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                    EmptyStateView(
                        icon: "briefcase",
                        title: "No jobs yet",
                        message: "Create your first job to start tracking work.",
                        actionTitle: "Add Job"
                    ) { showingAddJob = true }
                }
            } else {
                List {
                    Group {
                        header
                        InlineSearchField(text: $searchText, prompt: "Search jobs")
                            .padding(.bottom, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    if !searchText.isEmpty && filteredJobs.isEmpty {
                        Text("No jobs match “\(searchText)”.")
                            .font(.app(.subheadline))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

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
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .themedScreen()
        .tabBarSpace()
        .navigationTitle("Jobs")
        .navigationDestination(item: $selectedJob) { job in
            ProjectListView(job: job)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingAddJob) {
            NameEntrySheet(title: "New Job", fieldLabel: "Job Name", existingNames: allJobs.map(\.name)) { name in
                let job = Job(name: name)
                modelContext.insert(job)
            }
        }
        .sheet(item: $jobToRename) { job in
            NameEntrySheet(
                title: "Rename Job",
                fieldLabel: "Job Name",
                initialValue: job.name,
                existingNames: allJobs.filter { $0.id != job.id }.map(\.name)
            ) { newName in
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
        .backupImporter(isPresented: $showingImporter, existingJobs: allJobs)
        .shareSheet(item: $shareItem)
    }
}

#Preview {
    NavigationStack {
        JobListView()
    }
    .modelContainer(PreviewSupport.container)
}
