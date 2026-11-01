import SwiftUI
import SwiftData

/// Settings hub: a short, grouped overview. Each area opens its own page so no
/// screen gets long or crowded.
struct SettingsView: View {
    @Query private var jobs: [Job]
    @Query private var allEntries: [WorkEntry]
    @Query(sort: \SavedSignature.createdAt) private var signatures: [SavedSignature]

    @AppStorage(AppSettings.Keys.signerName) private var signerName = AppSettings.Defaults.signerName
    @AppStorage(AppSettings.Keys.monthlyTargetHours) private var monthlyTarget = AppSettings.Defaults.monthlyTargetHours
    @AppStorage(AppSettings.Keys.defaultSignatureID) private var defaultSignatureID = AppSettings.Defaults.defaultSignatureID
    @AppStorage(AppSettings.Keys.theme) private var themeRawValue = AppSettings.Defaults.theme

    var body: some View {
        List {
            Section {
                NavigationLink {
                    TimesheetSettingsView()
                } label: {
                    SettingsRow(
                        icon: "person.text.rectangle",
                        tint: Theme.gold,
                        title: "Timesheet details",
                        value: signerName.isEmpty ? "Add your name" : signerName
                    )
                }
                NavigationLink {
                    SignaturesView()
                } label: {
                    SettingsRow(icon: "signature", tint: Color(hex: 0x3F6FB5), title: "Signatures", value: signatureSummary)
                }
                NavigationLink {
                    MonthlyTargetSettingsView()
                } label: {
                    SettingsRow(
                        icon: "target",
                        tint: Color(hex: 0x2E8B62),
                        title: "Monthly target",
                        value: monthlyTarget > 0 ? "\(Int(monthlyTarget)) h" : "Off"
                    )
                }
            } header: {
                SettingsHeader("Work")
            }
            .themedRow()

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsRow(icon: "circle.lefthalf.filled", tint: Color(hex: 0x6B5BA8), title: "Theme", value: nil)
                    Picker("Theme", selection: $themeRawValue) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.vertical, 4)
            } header: {
                SettingsHeader("Appearance")
            } footer: {
                Text("Light is easiest on the eyes in daylight; Dark suits evenings. System follows your iPhone.")
                    .font(.app(.footnote))
            }
            .themedRow()

            Section {
                NavigationLink {
                    DataSettingsView()
                } label: {
                    SettingsRow(
                        icon: "externaldrive",
                        tint: Color(hex: 0xB0662B),
                        title: "Backup & export",
                        value: "\(allEntries.count) \(allEntries.count == 1 ? "entry" : "entries")"
                    )
                }
            } header: {
                SettingsHeader("Data")
            }
            .themedRow()

            Section {
                HStack {
                    SettingsRow(icon: "info.circle", tint: Theme.textSecondary, title: "Version", value: nil)
                    Spacer()
                    Text(appVersion)
                        .font(.app(.subheadline))
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack {
                    SettingsRow(icon: "calendar.badge.clock", tint: Theme.textSecondary, title: "Tracking since", value: nil)
                    Spacer()
                    Text(earliestJobDateText)
                        .font(.app(.subheadline))
                        .foregroundStyle(Theme.textSecondary)
                }
            } header: {
                SettingsHeader("About")
            }
            .themedRow()
        }
        .listSectionSpacing(18)
        .themedScreen()
        .navigationTitle("Settings")
    }

    private var signatureSummary: String {
        if signatures.isEmpty { return "None yet" }
        if let name = signatures.first(where: { $0.id.uuidString == defaultSignatureID })?.name { return name }
        return "\(signatures.count) saved"
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
}

// MARK: - Building blocks

/// One settings row: a tinted icon tile, a title, and an optional value on the right.
struct SettingsRow: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(.app(.body, .medium))
                .foregroundStyle(Theme.textPrimary)
            if let value {
                Spacer(minLength: 8)
                Text(value)
                    .font(.app(.subheadline))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 36)
    }
}

/// Section header in the app's label style (not the system's shouty caps).
struct SettingsHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.app(.footnote, .bold))
            .foregroundStyle(Theme.textSecondary)
            .textCase(nil)
    }
}

// MARK: - Sub-pages

/// Name, organization and the supervisor line printed on the PDF timesheet.
struct TimesheetSettingsView: View {
    @AppStorage(AppSettings.Keys.signerName) private var signerName = AppSettings.Defaults.signerName
    @AppStorage(AppSettings.Keys.organization) private var organization = AppSettings.Defaults.organization
    @AppStorage(AppSettings.Keys.includeSupervisorSignature) private var includeSupervisorSignature = AppSettings.Defaults.includeSupervisorSignature

    var body: some View {
        Form {
            Section {
                LabeledField(title: "Your name") {
                    TextField("e.g. Eslam Sherif", text: $signerName)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                }
                LabeledField(title: "Organization") {
                    TextField("Optional", text: $organization)
                        .textContentType(.organizationName)
                        .autocorrectionDisabled()
                }
            } header: {
                SettingsHeader("Printed at the top of every PDF")
            }
            .themedRow()

            Section {
                Toggle("Supervisor signature line", isOn: $includeSupervisorSignature)
                    .font(.app(.body))
            } header: {
                SettingsHeader("Signature block")
            } footer: {
                Text("Adds an empty line for your supervisor next to yours.")
                    .font(.app(.footnote))
            }
            .themedRow()
        }
        .themedScreen()
        .navigationTitle("Timesheet details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A small label above a text field, so forms read top-to-bottom.
struct LabeledField<Field: View>: View {
    let title: String
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.app(.caption, .semibold))
                .foregroundStyle(Theme.textSecondary)
            field
                .font(.app(.body))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 4)
    }
}

/// Monthly hours goal shown on the dashboard.
struct MonthlyTargetSettingsView: View {
    @AppStorage(AppSettings.Keys.monthlyTargetHours) private var monthlyTarget = AppSettings.Defaults.monthlyTargetHours

    private var isOn: Binding<Bool> {
        Binding(
            get: { monthlyTarget > 0 },
            set: { monthlyTarget = $0 ? 80 : 0 }
        )
    }

    private var hours: Binding<Int> {
        Binding(
            get: { max(1, Int(monthlyTarget.rounded())) },
            set: { monthlyTarget = Double($0) }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show a monthly target", isOn: isOn)
                    .font(.app(.body))
                if monthlyTarget > 0 {
                    Stepper(value: hours, in: 1...400) {
                        HStack {
                            Text("Hours per month")
                            Spacer()
                            Text("\(hours.wrappedValue) h")
                                .font(.app(.body, .bold))
                                .foregroundStyle(Theme.gold)
                                .monospacedDigit()
                        }
                    }
                }
            } footer: {
                Text("The dashboard shows how close you are to this goal and how much is left per workday.")
                    .font(.app(.footnote))
            }
            .themedRow()
        }
        .themedScreen()
        .navigationTitle("Monthly target")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Backups, CSV export, import, a summary of stored data, and reset.
struct DataSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var jobs: [Job]
    @Query private var allEntries: [WorkEntry]
    @Query(sort: \SavedSignature.createdAt) private var signatures: [SavedSignature]
    @AppStorage(AppSettings.Keys.defaultSignatureID) private var defaultSignatureID = AppSettings.Defaults.defaultSignatureID

    @State private var showingImporter = false
    @State private var showingResetConfirm = false
    @State private var shareItem: ShareItem?

    private var totalProjects: Int { jobs.reduce(0) { $0 + $1.projects.count } }
    private var totalHours: Double { allEntries.reduce(0) { $0 + $1.durationHours } }

    var body: some View {
        List {
            Section {
                Button {
                    shareItem = ShareItem(ExportService.backupExportURL(jobs: jobs, signatures: signatures))
                } label: {
                    SettingsRow(icon: "square.and.arrow.up", tint: Color(hex: 0x3F6FB5), title: "Export backup", value: "JSON")
                }
                Button {
                    showingImporter = true
                } label: {
                    SettingsRow(icon: "square.and.arrow.down", tint: Color(hex: 0x2E8B62), title: "Import backup", value: nil)
                }
            } header: {
                SettingsHeader("Backup")
            } footer: {
                Text("Backups include jobs, entries and signatures. Importing merges with what's here — nothing is overwritten and duplicates are skipped.")
                    .font(.app(.footnote))
            }
            .themedRow()

            Section {
                Button {
                    shareItem = ShareItem(
                        ExportService.csvExportURL(entries: ExportService.allEntries(in: jobs), filenamePrefix: "SignMe-AllEntries")
                    )
                } label: {
                    SettingsRow(icon: "tablecells", tint: Color(hex: 0xB0662B), title: "Export all entries", value: "CSV")
                }
                .disabled(allEntries.isEmpty)
            } header: {
                SettingsHeader("Spreadsheet")
            }
            .themedRow()

            Section {
                summaryRow("Jobs", "\(jobs.count)")
                summaryRow("Projects", "\(totalProjects)")
                summaryRow("Entries", "\(allEntries.count)")
                summaryRow("Tracked", DateDurationService.formattedDuration(hours: totalHours))
                summaryRow("Signatures", "\(signatures.count)")
            } header: {
                SettingsHeader("Stored on this iPhone")
            }
            .themedRow()

            Section {
                Button(role: .destructive) {
                    showingResetConfirm = true
                } label: {
                    Label("Reset all data", systemImage: "trash")
                        .font(.app(.body, .semibold))
                        .foregroundStyle(Theme.danger)
                }
            } footer: {
                Text("Permanently deletes every job, project, entry and signature. Export a backup first.")
                    .font(.app(.footnote))
            }
            .themedRow()
        }
        .listSectionSpacing(18)
        .themedScreen()
        .navigationTitle("Backup & export")
        .navigationBarTitleDisplayMode(.inline)
        .backupImporter(isPresented: $showingImporter, existingJobs: jobs)
        .shareSheet(item: $shareItem)
        .confirmationDialog("Reset all data?", isPresented: $showingResetConfirm, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) { resetAllData() }
        } message: {
            Text("This permanently deletes all jobs, projects, entries and signatures. This can't be undone.")
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value)
                .font(.app(.body, .semibold))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
        }
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
}
