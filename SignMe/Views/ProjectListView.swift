import SwiftUI
import SwiftData

/// Shows every Project inside a Job, with rename/duplicate/copy/move/delete
/// available via swipe actions and context menus.
struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allJobs: [Job]

    let job: Job

    private enum DestinationAction {
        case copy
        case move
    }

    @State private var showingAddProject = false
    @State private var projectToRename: Project?
    @State private var projectPendingDelete: Project?
    @State private var showDeleteConfirm = false
    @State private var projectForDestination: Project?
    @State private var destinationAction: DestinationAction = .copy
    @State private var selectedProject: Project?

    private var sortedProjects: [Project] {
        job.projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if job.projects.isEmpty {
                EmptyStateView(
                    icon: "folder",
                    title: "No projects yet",
                    message: "Add a project to \(job.name) to start logging time.",
                    actionTitle: "Add Project"
                ) { showingAddProject = true }
            } else {
                List {
                    ForEach(sortedProjects) { project in
                        Button {
                            selectedProject = project
                        } label: {
                            ProjectCardView(project: project)
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                projectPendingDelete = project
                                showDeleteConfirm = true
                            } label: { Label("Delete", systemImage: "trash") }

                            Button { projectToRename = project } label: { Label("Rename", systemImage: "pencil") }
                                .tint(.orange)
                        }
                        .contextMenu {
                            Button { projectToRename = project } label: { Label("Rename", systemImage: "pencil") }
                            Button { duplicateProject(project) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                            Button {
                                projectForDestination = project
                                destinationAction = .copy
                            } label: { Label("Copy to Job…", systemImage: "arrowshape.turn.up.right") }
                            Button {
                                projectForDestination = project
                                destinationAction = .move
                            } label: { Label("Move to Job…", systemImage: "folder.badge.gearshape") }
                            Divider()
                            Button(role: .destructive) {
                                projectPendingDelete = project
                                showDeleteConfirm = true
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(job.name)
        .navigationDestination(item: $selectedProject) { project in
            WorkEntryListView(project: project)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddProject = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAddProject) {
            NameEntrySheet(
                title: "New Project",
                fieldLabel: "Project Name",
                existingNames: job.projects.map(\.name)
            ) { name in
                let project = Project(name: name)
                modelContext.insert(project)
                job.projects.append(project)
            }
        }
        .sheet(item: $projectToRename) { project in
            NameEntrySheet(
                title: "Rename Project",
                fieldLabel: "Project Name",
                initialValue: project.name,
                existingNames: job.projects.filter { $0.id != project.id }.map(\.name)
            ) { newName in
                project.name = newName
            }
        }
        .sheet(item: $projectForDestination) { project in
            DestinationPickerView(mode: .job, jobs: destinationJobs, onSelectJob: { destinationJob in
                switch destinationAction {
                case .copy: copyProject(project, into: destinationJob)
                case .move: moveProject(project, to: destinationJob)
                }
            })
        }
        .confirmationDialog(
            "Delete this project?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible,
            presenting: projectPendingDelete
        ) { project in
            Button("Delete \"\(project.name)\"", role: .destructive) { delete(project) }
        } message: { project in
            Text("This will permanently delete \"\(project.name)\" and all of its entries.")
        }
    }

    private var destinationJobs: [Job] {
        destinationAction == .move ? allJobs.filter { $0.id != job.id } : allJobs
    }

    // MARK: - Mutations

    private func duplicateProject(_ project: Project) {
        guard let currentJob = project.job else { return }
        copyProject(project, into: currentJob)
    }

    private func copyProject(_ project: Project, into destinationJob: Job) {
        let newName = destinationJob.uniqueProjectName(base: project.name)
        let newProject = Project(name: newName)
        modelContext.insert(newProject)
        destinationJob.projects.append(newProject)

        for entry in project.entries {
            let copy = entry.duplicate()
            modelContext.insert(copy)
            newProject.entries.append(copy)
        }
    }

    /// Relationships are always changed from the parent's side
    /// (`job.projects`); SwiftData keeps `project.job` in sync.
    private func moveProject(_ project: Project, to destinationJob: Job) {
        guard destinationJob.id != project.job?.id else { return }
        if let currentJob = project.job, let idx = currentJob.projects.firstIndex(where: { $0.id == project.id }) {
            currentJob.projects.remove(at: idx)
        }
        project.name = destinationJob.uniqueProjectName(base: project.name)
        destinationJob.projects.append(project)
    }

    private func delete(_ project: Project) {
        if let idx = job.projects.firstIndex(where: { $0.id == project.id }) {
            job.projects.remove(at: idx)
        }
        modelContext.delete(project)
    }
}

#Preview {
    NavigationStack {
        ProjectListView(job: PreviewSupport.sampleJob)
    }
    .modelContainer(PreviewSupport.container)
}
