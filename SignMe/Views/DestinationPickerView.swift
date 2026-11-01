import SwiftUI

/// A reusable destination picker used for both "copy/move project to another job"
/// and "copy/move entries to another project" flows.
struct DestinationPickerView: View {
    enum Mode {
        case job
        case project
    }

    let mode: Mode
    let jobs: [Job]
    var excludingProject: Project? = nil
    var onSelectJob: ((Job) -> Void)? = nil
    var onSelectProject: ((Project) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    private var jobsWithSelectableProjects: [Job] {
        jobs.filter { job in
            job.projects.contains { $0.id != excludingProject?.id }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .job:
                    jobList
                case .project:
                    projectList
                }
            }
            .themedScreen()
            .navigationTitle(mode == .job ? "Select Job" : "Select Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var jobList: some View {
        Group {
            if jobs.isEmpty {
                EmptyStateView(icon: "briefcase", title: "No Jobs Available", message: "Create another job first.")
            } else {
                List(jobs) { job in
                    Button {
                        onSelectJob?(job)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "briefcase.fill")
                                .foregroundStyle(Theme.gold)
                            Text(job.name)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .themedRow()
                }
            }
        }
    }

    private var projectList: some View {
        Group {
            if jobsWithSelectableProjects.isEmpty {
                EmptyStateView(icon: "folder", title: "No Destination Available", message: "There's no other project to choose yet.")
            } else {
                List {
                    ForEach(jobsWithSelectableProjects) { job in
                        Section(job.name) {
                            ForEach(job.projects.filter { $0.id != excludingProject?.id }) { project in
                                Button {
                                    onSelectProject?(project)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Image(systemName: "folder.fill")
                                            .foregroundStyle(Theme.gold)
                                        Text(project.name)
                                            .foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                    }
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .themedRow()
                    }
                }
            }
        }
    }
}

#Preview {
    DestinationPickerView(mode: .project, jobs: [PreviewSupport.sampleJob])
        .modelContainer(PreviewSupport.container)
}
