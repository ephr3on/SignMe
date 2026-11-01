import SwiftUI
import SwiftData

/// The home screen: at-a-glance stats, quick actions, and recent activity.
struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Job.createdAt, order: .reverse) private var jobs: [Job]
    @Query(sort: \WorkEntry.date, order: .reverse) private var allEntries: [WorkEntry]

    @State private var showingSearch = false
    @State private var showingExportMonth = false

    // "Add Task" flow: pick a job (skipped if there's only one), then a
    // project (skipped if that job has only one), then the entry form.
    @State private var showingAddTaskJobPicker = false
    @State private var jobPickedForAddTask: Job?
    @State private var showingAddTaskProjectPicker = false
    @State private var jobForAddTaskProjectPicker: Job?
    @State private var projectPickedForAddTask: Project?
    @State private var addTaskEntryProject: Project?
    @State private var addTaskAlertMessage: String?

    private var totalHoursThisMonth: Double {
        let calendar = Calendar.current
        return allEntries
            .filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .month) && calendar.isDate($0.date, equalTo: .now, toGranularity: .year) }
            .reduce(0) { $0 + $1.durationHours }
    }

    private var totalHoursThisWeek: Double {
        let calendar = Calendar.current
        return allEntries
            .filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) && calendar.isDate($0.date, equalTo: .now, toGranularity: .yearForWeekOfYear) }
            .reduce(0) { $0 + $1.durationHours }
    }

    private var totalProjects: Int { jobs.reduce(0) { $0 + $1.projects.count } }
    private var recentEntries: [WorkEntry] { Array(allEntries.prefix(6)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                greeting
                statsGrid
                quickActions
                recentSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("SignMe")
        .sheet(isPresented: $showingSearch) {
            NavigationStack { SearchWorkEntryView() }
        }
        .sheet(isPresented: $showingExportMonth) {
            ExportMonthSheet(jobs: jobs)
        }
        .sheet(isPresented: $showingAddTaskJobPicker, onDismiss: {
            if let job = jobPickedForAddTask {
                jobPickedForAddTask = nil
                proceedAfterJobChosenForAddTask(job)
            }
        }) {
            DestinationPickerView(mode: .job, jobs: jobs, onSelectJob: { job in
                jobPickedForAddTask = job
            })
        }
        .sheet(isPresented: $showingAddTaskProjectPicker, onDismiss: {
            jobForAddTaskProjectPicker = nil
            if let project = projectPickedForAddTask {
                projectPickedForAddTask = nil
                addTaskEntryProject = project
            }
        }) {
            if let job = jobForAddTaskProjectPicker {
                DestinationPickerView(mode: .project, jobs: [job], onSelectProject: { project in
                    projectPickedForAddTask = project
                })
            }
        }
        .sheet(item: $addTaskEntryProject) { project in
            EntryFormView(project: project)
        }
        .alert("Add a Task", isPresented: Binding(
            get: { addTaskAlertMessage != nil },
            set: { if !$0 { addTaskAlertMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(addTaskAlertMessage ?? "")
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingText)
                .font(.largeTitle.bold())
            Text("Here's your work overview.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            StatCard(title: "This Month", value: DateDurationService.formattedDuration(hours: totalHoursThisMonth), icon: "calendar", tint: .blue)
            StatCard(title: "This Week", value: DateDurationService.formattedDuration(hours: totalHoursThisWeek), icon: "clock.fill", tint: .indigo)
            StatCard(title: "Jobs", value: "\(jobs.count)", icon: "briefcase.fill", tint: .teal)
            StatCard(title: "Projects", value: "\(totalProjects)", icon: "folder.fill", tint: .orange)
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions").font(.headline)
            HStack(spacing: 12) {
                quickActionButton("Add Task", "plus.circle.fill", .accentColor) { startAddTask() }
                quickActionButton("Search", "magnifyingglass.circle.fill", .purple) { showingSearch = true }
                quickActionButton("Export Month", "square.and.arrow.up.circle.fill", .green) { showingExportMonth = true }
            }
        }
    }

    private func quickActionButton(_ title: String, _ icon: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Entries").font(.headline)

            if recentEntries.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "No entries yet",
                    message: "Start tracking time to see recent activity here."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(recentEntries) { entry in
                        EntryRowView(entry: entry, showsProjectContext: true)
                            .padding(12)
                            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(.quaternary, lineWidth: 1)
                            )
                    }
                }
            }
        }
    }

    // MARK: - Add Task flow

    private func startAddTask() {
        guard !jobs.isEmpty else {
            addTaskAlertMessage = "Create a job first before adding a task."
            return
        }
        if jobs.count == 1, let onlyJob = jobs.first {
            proceedAfterJobChosenForAddTask(onlyJob)
        } else {
            showingAddTaskJobPicker = true
        }
    }

    private func proceedAfterJobChosenForAddTask(_ job: Job) {
        if job.projects.isEmpty {
            addTaskAlertMessage = "Add a project to \"\(job.name)\" before adding a task."
        } else if job.projects.count == 1, let onlyProject = job.projects.first {
            addTaskEntryProject = onlyProject
        } else {
            jobForAddTaskProjectPicker = job
            showingAddTaskProjectPicker = true
        }
    }
}

/// Presented from the Dashboard's "Export Month" quick action — exports one
/// project's entries for a single month as JSON, ending with the total hours.
struct ExportMonthSheet: View {
    @Environment(\.dismiss) private var dismiss
    let jobs: [Job]

    @State private var selectedJob: Job?
    @State private var selectedProject: Project?
    @State private var selectedMonthIndex: Int
    @State private var selectedYear: Int

    init(jobs: [Job]) {
        self.jobs = jobs
        let calendar = Calendar.current
        _selectedMonthIndex = State(initialValue: calendar.component(.month, from: .now))
        _selectedYear = State(initialValue: calendar.component(.year, from: .now))
        let initialJob = jobs.count == 1 ? jobs.first : nil
        _selectedJob = State(initialValue: initialJob)
        _selectedProject = State(initialValue: (initialJob?.projects.count == 1) ? initialJob?.projects.first : nil)
    }

    private var availableYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: .now)
        let entryYears = jobs.flatMap { $0.projects.flatMap(\.entries) }
            .map { Calendar.current.component(.year, from: $0.date) }
        var years = Set(entryYears)
        years.insert(currentYear)
        return years.sorted(by: >)
    }

    private var monthDate: Date {
        Calendar.current.date(from: DateComponents(year: selectedYear, month: selectedMonthIndex)) ?? .now
    }

    private var matchingEntries: [WorkEntry] {
        guard let project = selectedProject else { return [] }
        let calendar = Calendar.current
        return project.entries.filter {
            calendar.component(.year, from: $0.date) == selectedYear &&
            calendar.component(.month, from: $0.date) == selectedMonthIndex
        }
    }

    private var totalHours: Double {
        matchingEntries.reduce(0) { $0 + $1.durationHours }
    }

    private var exportURL: URL? {
        guard let job = selectedJob, let project = selectedProject, !matchingEntries.isEmpty else { return nil }
        return ExportService.monthExportPDFURL(job: job, project: project, monthDate: monthDate, entries: matchingEntries)
    }

    var body: some View {
        NavigationStack {
            Group {
                if jobs.isEmpty {
                    EmptyStateView(
                        icon: "briefcase",
                        title: "No Jobs Yet",
                        message: "Create a job and project first, then come back to export a month of work."
                    )
                } else {
                    form
                }
            }
            .navigationTitle("Export Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private var form: some View {
        Form {
            if jobs.count > 1 {
                Section("Job") {
                    Picker("Job", selection: $selectedJob) {
                        Text("Choose a job").tag(Job?.none)
                        ForEach(jobs) { job in
                            Text(job.name).tag(Optional(job))
                        }
                    }
                    .onChange(of: selectedJob) { _, _ in selectedProject = nil }
                }
            }

            if let job = selectedJob {
                Section("Project") {
                    if job.projects.isEmpty {
                        Text("This job has no projects yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Project", selection: $selectedProject) {
                            Text("Choose a project").tag(Project?.none)
                            ForEach(job.projects) { project in
                                Text(project.name).tag(Optional(project))
                            }
                        }
                    }
                }
            }

            Section("Month") {
                Picker("Month", selection: $selectedMonthIndex) {
                    ForEach(1...12, id: \.self) { index in
                        Text(DateDurationService.monthNames[index - 1]).tag(index)
                    }
                }
                Picker("Year", selection: $selectedYear) {
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
            }

            Section {
                HStack {
                    Text("Matching Entries")
                    Spacer()
                    Text("\(matchingEntries.count)").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Total Hours")
                    Spacer()
                    Text(DateDurationService.formattedDuration(hours: totalHours))
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
            }

            Section {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Export Month (PDF)", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Label(
                        selectedProject == nil ? "Choose a project to export" : "No entries in this month",
                        systemImage: "tray"
                    )
                    .foregroundStyle(.secondary)
                }
            } footer: {
                Text("The exported PDF lists every entry for the selected project and month, with the total tracked hours at the end.")
            }
        }
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
    .modelContainer(PreviewSupport.container)
}
