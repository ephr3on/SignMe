import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// App settings: data summary, backup export/import, app info, and a
/// strongly-confirmed reset-all-data action.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var jobs: [Job]
    @Query private var allEntries: [WorkEntry]

    @State private var showingImporter = false
    @State private var showingResetConfirm = false
    @State private var importSummaryMessage: String?
    @State private var importErrorMessage: String?

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
                if let backupURL = ExportService.backupExportURL(jobs: jobs) {
                    ShareLink(item: backupURL) {
                        Label("Export Backup (JSON)", systemImage: "square.and.arrow.up")
                    }
                }
                if let csvURL = ExportService.csvExportURL(entries: ExportService.allEntries(in: jobs), filenamePrefix: "SignMe-AllEntries") {
                    ShareLink(item: csvURL) {
                        Label("Export All Entries (CSV)", systemImage: "tablecells")
                    }
                }
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
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json], onCompletion: handleImport)
        .confirmationDialog(
            "Reset all data?",
            isPresented: $showingResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) { resetAllData() }
        } message: {
            Text("This permanently deletes all jobs, projects, and entries. This can't be undone.")
        }
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

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let summary = try BackupService.importData(data, into: modelContext, existingJobs: jobs)
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

    private func resetAllData() {
        for job in jobs {
            modelContext.delete(job)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(PreviewSupport.container)
}
