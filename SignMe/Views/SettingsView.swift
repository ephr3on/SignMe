import SwiftUI
import SwiftData

/// App settings: data summary, timesheet details, backup export/import, app
/// info, and a strongly-confirmed reset-all-data action.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var jobs: [Job]
    @Query private var allEntries: [WorkEntry]

    @AppStorage(AppSettings.Keys.signerName) private var signerName = AppSettings.Defaults.signerName
    @AppStorage(AppSettings.Keys.organization) private var organization = AppSettings.Defaults.organization
    @AppStorage(AppSettings.Keys.includeSupervisorSignature) private var includeSupervisorSignature = AppSettings.Defaults.includeSupervisorSignature

    @State private var showingImporter = false
    @State private var showingResetConfirm = false
    @State private var shareItem: ShareItem?

    private var totalProjects: Int { jobs.reduce(0) { $0 + $1.projects.count } }
    private var totalHours: Double { allEntries.reduce(0) { $0 + $1.durationHours } }

    var body: some View {
        List {
            Section("Data Summary") {
                summaryRow("Jobs", "\(jobs.count)", "briefcase.fill")
                summaryRow("Projects", "\(totalProjects)", "folder.fill")
                summaryRow("Entries", "\(allEntries.count)", "list.bullet.rectangle")
                summaryRow("Tracked Hours", DateDurationService.formattedDuration(hours: totalHours), "clock.fill")
            }

            Section {
                TextField("Your name", text: $signerName)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                TextField("Organization (optional)", text: $organization)
                    .textContentType(.organizationName)
                    .autocorrectionDisabled()
                Toggle("Supervisor signature line", isOn: $includeSupervisorSignature)
            } header: {
                Text("PDF Timesheet")
            } footer: {
                Text("Shown on the monthly PDF export: your name and organization at the top, and signature lines at the end.")
            }

            Section {
                Button {
                    shareItem = ShareItem(ExportService.backupExportURL(jobs: jobs))
                } label: {
                    Label("Export Backup (JSON)", systemImage: "square.and.arrow.up")
                }
                Button {
                    shareItem = ShareItem(
                        ExportService.csvExportURL(entries: ExportService.allEntries(in: jobs), filenamePrefix: "SignMe-AllEntries")
                    )
                } label: {
                    Label("Export All Entries (CSV)", systemImage: "tablecells")
                }
                .disabled(allEntries.isEmpty)
                Button { showingImporter = true } label: {
                    Label("Import Backup", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Importing merges with your existing jobs and projects — nothing is overwritten, and duplicate entries are skipped.")
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Tracking Since", value: earliestJobDateText)
            }

            Section {
                Button(role: .destructive) { showingResetConfirm = true } label: {
                    Label("Reset All Data", systemImage: "trash.fill")
                }
            } footer: {
                Text("Permanently deletes every job, project, and entry. This cannot be undone.")
            }
        }
        .navigationTitle("Settings")
        .backupImporter(isPresented: $showingImporter, existingJobs: jobs)
        .shareSheet(item: $shareItem)
        .confirmationDialog(
            "Reset all data?",
            isPresented: $showingResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) { resetAllData() }
        } message: {
            Text("This permanently deletes all jobs, projects, and entries. This can't be undone.")
        }
    }

    private func summaryRow(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var earliestJobDateText: String {
        guard let earliest = jobs.map(\.createdAt).min() else { return "—" }
        return DateDurationService.dateFormatter.string(from: earliest)
    }

    private func resetAllData() {
        for job in jobs {
            modelContext.delete(job)
        }
        try? modelContext.save()
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(PreviewSupport.container)
}
