import SwiftUI
import SwiftData

/// Export one project's month as a signed A4 PDF timesheet.
/// - Asks which saved signature to use, unless a default is set (then it is used
///   automatically, with a "Change" option). "Use as default" skips the question next time.
/// - The date next to the signature is today unless another date is chosen.
struct ExportMonthSheet: View {
    @Environment(\.dismiss) private var dismiss
    let jobs: [Job]

    @Query(sort: \SavedSignature.createdAt) private var signatures: [SavedSignature]
    @AppStorage(AppSettings.Keys.signerName) private var signerName = AppSettings.Defaults.signerName
    @AppStorage(AppSettings.Keys.defaultSignatureID) private var defaultSignatureID = AppSettings.Defaults.defaultSignatureID
    @AppStorage(AppSettings.Keys.includeSupervisorSignature) private var includeSupervisorSignature = AppSettings.Defaults.includeSupervisorSignature

    @State private var selectedProject: Project?
    @State private var month: Date
    @State private var selectedSignatureID: UUID?
    @State private var didPickSignature = false
    @State private var useAsDefault = false
    @State private var changingSignature = false
    @State private var useCustomDate = false
    @State private var customDate = Date.now
    @State private var shareItem: ShareItem?
    @State private var showingSignatures = false

    init(jobs: [Job], initialProject: Project? = nil, initialMonth: Date = .now) {
        self.jobs = jobs
        let calendar = Calendar.current
        _month = State(initialValue: calendar.dateInterval(of: .month, for: initialMonth)?.start ?? initialMonth)
        let allProjects = jobs.flatMap(\.projects)
        _selectedProject = State(initialValue: initialProject ?? (allProjects.count == 1 ? allProjects.first : nil))
    }

    // MARK: - Derived

    private var allProjects: [Project] {
        jobs.flatMap { job in
            job.projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var matchingEntries: [WorkEntry] {
        guard let project = selectedProject else { return [] }
        let calendar = Calendar.current
        return project.entries.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    private var totalHours: Double {
        matchingEntries.reduce(0) { $0 + $1.durationHours }
    }

    private var defaultSignature: SavedSignature? {
        signatures.first { $0.id.uuidString == defaultSignatureID }
    }

    /// The signature that will be stamped (nil = leave the line empty).
    private var activeSignature: SavedSignature? {
        if !changingSignature, let defaultSignature { return defaultSignature }
        guard let selectedSignatureID else { return nil }
        return signatures.first { $0.id == selectedSignatureID }
    }

    private var signingDate: Date { useCustomDate ? customDate : .now }
    private var dateText: String { DateDurationService.signatureDateFormatter.string(from: signingDate) }

    private var canExport: Bool { selectedProject?.job != nil && !matchingEntries.isEmpty }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if allProjects.isEmpty {
                    EmptyStateView(
                        icon: "briefcase",
                        title: "No projects yet",
                        message: "Create a job and project first, then come back to export a month of work."
                    )
                } else {
                    content
                }
            }
            .themedScreen()
            .navigationTitle("Export month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .shareSheet(item: $shareItem)
            .sheet(isPresented: $showingSignatures) {
                NavigationStack {
                    SignaturesView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingSignatures = false }
                            }
                        }
                }
            }
            .onAppear(perform: preselectSignature)
            .onChange(of: signatures.count) { _, _ in preselectSignature() }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                summarySection
                signatureSection
                dateSection
                preview
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: export) {
                Label(activeSignature == nil ? "Export PDF" : "Export signed PDF", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(GoldButtonStyle(height: 54))
            .disabled(!canExport)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Theme.background)
        }
    }

    // MARK: Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Menu {
                ForEach(jobs) { job in
                    if !job.projects.isEmpty {
                        Section(job.name) {
                            ForEach(job.projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { project in
                                Button(project.name) { selectedProject = project }
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedProject?.name ?? "Choose a project")
                            .font(.app(.body, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(selectedProject?.job?.name ?? "Which project's hours?")
                            .font(.app(.caption))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.app(.footnote, .semibold))
                        .foregroundStyle(Theme.gold)
                }
                .card(padding: 14, radius: 16, highlighted: selectedProject == nil)
            }

            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Previous month")
                Spacer()
                VStack(spacing: 2) {
                    Text(month.formatted(.dateTime.month(.wide).year()))
                        .font(Theme.display(.headline))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(matchingEntries.count) \(matchingEntries.count == 1 ? "entry" : "entries") · \(DateDurationService.formattedDuration(hours: totalHours))")
                        .font(.app(.footnote))
                        .foregroundStyle(matchingEntries.isEmpty ? Theme.textTertiary : Theme.textSecondary)
                        .monospacedDigit()
                }
                Spacer()
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Next month")
            }
            .foregroundStyle(Theme.gold)
            .card(padding: 6, radius: 16)
        }
    }

    // MARK: Signature

    private var signatureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Sign with")
                Button("+ New signature") { showingSignatures = true }
                    .font(.app(.footnote, .bold))
                    .foregroundStyle(Theme.gold)
            }

            if let defaultSignature, !changingSignature {
                HStack(spacing: 12) {
                    SignatureThumbnail(signature: defaultSignature)
                        .frame(width: 96, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(defaultSignature.name)
                            .font(.app(.body, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Your default — used automatically")
                            .font(.app(.caption))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button("Change") {
                        selectedSignatureID = defaultSignature.id
                        changingSignature = true
                    }
                    .font(.app(.subheadline, .semibold))
                    .foregroundStyle(Theme.gold)
                }
                .card(padding: 12, radius: 16)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(signatures) { signature in
                        signatureTile(signature: signature, isSelected: selectedSignatureID == signature.id) {
                            selectedSignatureID = signature.id
                            didPickSignature = true
                        }
                    }
                    signatureTile(signature: nil, isSelected: selectedSignatureID == nil) {
                        selectedSignatureID = nil
                        didPickSignature = true
                    }
                }

                Toggle(isOn: $useAsDefault) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use as default")
                            .font(.app(.body, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Next time, export without asking")
                            .font(.app(.caption))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .toggleStyle(GoldCheckboxToggleStyle())
                .disabled(selectedSignatureID == nil)
            }
        }
    }

    private func signatureTile(signature: SavedSignature?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                SignatureThumbnail(signature: signature)
                    .frame(height: 58)
                Text(signature?.name ?? "No signature")
                    .font(.app(.caption, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            .padding(8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Theme.gold : Color.clear, lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.app(.title3))
                        .foregroundStyle(Theme.onGold, Theme.goldFill)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(signature?.name ?? "No signature")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Date

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Date next to signature")
            Picker("Signature date", selection: $useCustomDate) {
                Text("Today · \(DateDurationService.signatureDateFormatter.string(from: .now))").tag(false)
                Text("Other date").tag(true)
            }
            .pickerStyle(.segmented)

            if useCustomDate {
                DatePicker("Signed on", selection: $customDate, displayedComponents: .date)
                    .foregroundStyle(Theme.textPrimary)
                    .card(padding: 12, radius: 14)
            }
        }
    }

    // MARK: Preview

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Preview")
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Total: \(DateDurationService.formattedDuration(hours: totalHours)) (\(DateDurationService.formattedDecimalHours(totalHours)) h)")
                        .font(.app(.caption, .bold))
                    Spacer()
                }
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xD9D3C4)).frame(height: 1) }

                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .bottom) {
                            if let image = activeSignature?.image {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 90, maxHeight: 36, alignment: .bottomLeading)
                            }
                            Spacer(minLength: 4)
                            if activeSignature != nil {
                                Text(dateText)
                                    .font(.app(.caption2, .semibold))
                            }
                        }
                        .frame(height: 36)
                        Rectangle().fill(Color(hex: 0x1B2333)).frame(height: 1)
                        Text(signerName.isEmpty ? "Date, signature (employee)" : "Date, signature — \(signerName)")
                            .font(.appSize(10, relativeTo: .caption2))
                            .foregroundStyle(Color(hex: 0x5B6474))
                            .lineLimit(1)
                    }
                    if includeSupervisorSignature {
                        VStack(alignment: .leading, spacing: 3) {
                            Spacer().frame(height: 36)
                            Rectangle().fill(Color(hex: 0x1B2333)).frame(height: 1)
                            Text("Date, signature (supervisor)")
                                .font(.appSize(10, relativeTo: .caption2))
                                .foregroundStyle(Color(hex: 0x5B6474))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .foregroundStyle(Color(hex: 0x1B2333))
            .padding(14)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(activeSignature == nil
                ? "Preview: signature line left empty"
                : "Preview: signed with \(activeSignature?.name ?? ""), dated \(dateText)")
        }
    }

    // MARK: - Actions

    private func preselectSignature() {
        guard !didPickSignature, selectedSignatureID == nil else { return }
        selectedSignatureID = defaultSignature?.id ?? signatures.first?.id
    }

    private func shiftMonth(_ delta: Int) {
        month = Calendar.current.date(byAdding: .month, value: delta, to: month) ?? month
    }

    private func export() {
        guard let project = selectedProject, let job = project.job, !matchingEntries.isEmpty else { return }
        let signature = activeSignature
        if changingSignature || defaultSignature == nil, useAsDefault, let signature {
            defaultSignatureID = signature.id.uuidString
        }
        let stamp = signature.map { ExportService.SignatureStamp(image: $0.image, dateText: dateText) }
        shareItem = ShareItem(
            ExportService.monthExportPDFURL(
                job: job,
                project: project,
                monthDate: month,
                entries: matchingEntries,
                signature: stamp
            )
        )
    }
}

/// A square checkbox toggle ("Use as default").
struct GoldCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.app(.title2))
                    .foregroundStyle(configuration.isOn ? Theme.gold : Theme.textSecondary)
                configuration.label
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

#Preview {
    ExportMonthSheet(jobs: [PreviewSupport.sampleJob])
        .modelContainer(PreviewSupport.container)
        .preferredColorScheme(.dark)
}
