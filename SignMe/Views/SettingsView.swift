import SwiftUI
import SwiftData

/// App settings: timesheet details, monthly target, signatures, backup, data summary,
/// app info, and a strongly-confirmed reset-all-data action.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var jobs: [Job]
    @Query private var allEntries: [WorkEntry]
    @Query(sort: \SavedSignature.createdAt) private var signatures: [SavedSignature]

    @AppStorage(AppSettings.Keys.signerName) private var signerName = AppSettings.Defaults.signerName
    @AppStorage(AppSettings.Keys.organization) private var organization = AppSettings.Defaults.organization
    @AppStorage(AppSettings.Keys.includeSupervisorSignature) private var includeSupervisorSignature = AppSettings.Defaults.includeSupervisorSignature
    @AppStorage(AppSettings.Keys.monthlyTargetHours) private var monthlyTarget = AppSettings.Defaults.monthlyTargetHours
    @AppStorage(AppSettings.Keys.defaultSignatureID) private var defaultSignatureID = AppSettings.Defaults.defaultSignatureID
    @AppStorage(AppSettings.Keys.theme) private var themeRawValue = AppSettings.Defaults.theme

    @State private var showingImporter = false
    @State private var showingResetConfirm = false
    @State private var shareItem: ShareItem?

    private var totalProjects: Int { jobs.reduce(0) { $0 + $1.projects.count } }
    private var totalHours: Double { allEntries.reduce(0) { $0 + $1.durationHours } }

    private var defaultSignatureName: String? {
        signatures.first { $0.id.uuidString == defaultSignatureID }?.name
    }

    var body: some View {
        List {
            Section {
                Picker("Theme", selection: $themeRawValue) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            } header: {
                Text("Appearance")
            } footer: {
                Text("Light is easier on the eyes in daylight; Dark suits evenings. System follows your iPhone's setting.")
            }
            .themedRow()

            Section {
                TextField("Your name", text: $signerName)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                TextField("Organization (optional)", text: $organization)
                    .textContentType(.organizationName)
                    .autocorrectionDisabled()
                Toggle("Supervisor signature line", isOn: $includeSupervisorSignature)
                NavigationLink {
                    SignaturesView()
                } label: {
                    HStack {
                        Label("Signatures", systemImage: "signature")
                        Spacer()
                        Text(signatureSummary)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            } header: {
                Text("PDF Timesheet")
            } footer: {
                Text("Shown on the monthly PDF export: your name and organization at the top, your signature and date at the end.")
            }
            .themedRow()

            Section {
                Stepper(value: targetBinding, in: 0...400, step: 1) {
                    HStack {
                        Text("Monthly target")
                        Spacer()
                        Text(monthlyTarget > 0 ? "\(Int(monthlyTarget)) h" : "Off")
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Goal")
            } footer: {
                Text("The dashboard shows your progress toward this many hours each month. Set to 0 to hide it.")
            }
            .themedRow()

            Section {
                Button {
                    shareItem = ShareItem(ExportService.backupExportURL(jobs: jobs, signatures: signatures))
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
                Text("Backups include your jobs, entries and signatures. Importing merges with your existing data — nothing is overwritten, and duplicates are skipped.")
            }
            .themedRow()

            Section("Data Summary") {
                summaryRow("Jobs", "\(jobs.count)", "briefcase.fill")
                summaryRow("Projects", "\(totalProjects)", "folder.fill")
                summaryRow("Entries", "\(allEntries.count)", "list.bullet.rectangle")
                summaryRow("Tracked Hours", DateDurationService.formattedDuration(hours: totalHours), "clock.fill")
            }
            .themedRow()

            Section("About") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Tracking Since", value: earliestJobDateText)
            }
            .themedRow()

            Section {
                Button(role: .destructive) { showingResetConfirm = true } label: {
                    Label("Reset All Data", systemImage: "trash.fill")
                        .foregroundStyle(Theme.danger)
                }
            } footer: {
                Text("Permanently deletes every job, project, entry and signature. This cannot be undone.")
            }
            .themedRow()
        }
        .themedScreen()
        .foregroundStyle(Theme.textPrimary)
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
            Text("This permanently deletes all jobs, projects, entries and signatures. This can't be undone.")
        }
    }

    private var signatureSummary: String {
        if signatures.isEmpty { return "None" }
        if let defaultSignatureName { return defaultSignatureName }
        return "\(signatures.count) saved"
    }

    /// Stepper binding in whole hours.
    private var targetBinding: Binding<Int> {
        Binding(
            get: { Int(monthlyTarget.rounded()) },
            set: { monthlyTarget = Double($0) }
        )
    }

    private func summaryRow(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(value).foregroundStyle(Theme.textSecondary)
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
        for signature in signatures {
            modelContext.delete(signature)
        }
        defaultSignatureID = ""
        try? modelContext.save()
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(PreviewSupport.container)
    .preferredColorScheme(.dark)
}
