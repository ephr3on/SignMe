import SwiftUI
import SwiftData

/// Export a month as signed A4 PDF timesheets — for one project, or for several
/// projects at once (one separate, signed PDF per project, shared together).
/// - Asks which saved signature to use, unless a default is set (then it is used
///   automatically, with a "Change" option). "Use as default" skips the question next time.
/// - The date next to the signature is today unless another date is chosen.
/// - In "Several projects" mode, every project with hours in the chosen month is ticked.
struct ExportMonthSheet: View {
    enum Mode: String, CaseIterable {
        case single = "One project"
        case multiple = "Several projects"
    }

    @Environment(\.dismiss) private var dismiss
    let jobs: [Job]

    @Query(sort: \SavedSignature.createdAt) private var signatures: [SavedSignature]
    @AppStorage(AppSettings.Keys.signerName) private var signerName = AppSettings.Defaults.signerName
    @AppStorage(AppSettings.Keys.defaultSignatureID) private var defaultSignatureID = AppSettings.Defaults.defaultSignatureID
    @AppStorage(AppSettings.Keys.includeSupervisorSignature) private var includeSupervisorSignature = AppSettings.Defaults.includeSupervisorSignature
    @AppStorage("export.lastMode") private var lastModeRaw = Mode.single.rawValue

    @State private var mode: Mode
    @State private var selectedProject: Project?
    @State private var selectedProjectIDs: Set<UUID> = []
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
        // Opened from a specific project → single; otherwise reuse the last mode.
        let remembered = Mode(rawValue: UserDefaults.standard.string(forKey: "export.lastMode") ?? "") ?? .single
        _mode = State(initialValue: initialProject != nil || allProjects.count < 2 ? .single : remembered)
    }

    // MARK: - Derived

    private var allProjects: [Project] {
        jobs.flatMap { job in
            job.projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var matchingEntries: [WorkEntry] {
        guard let project = selectedProject else { return [] }
        return ExportService.entries(of: project, inMonthOf: month)
    }

    private func monthHours(_ project: Project) -> Double {
        ExportService.entries(of: project, inMonthOf: month).reduce(0) { $0 + $1.durationHours }
    }

    /// Ticked projects that actually have hours this month, in list order.
    private var selectedProjects: [Project] {
        allProjects.filter { selectedProjectIDs.contains($0.id) && monthHours($0) > 0 }
    }

    /// Single mode: the project's total. Several: the first ticked project's total (for the preview).
    private var totalHours: Double {
        switch mode {
        case .single: return matchingEntries.reduce(0) { $0 + $1.durationHours }
        case .multiple: return selectedProjects.first.map(monthHours) ?? 0
        }
    }

    private var selectedTotalHours: Double {
        selectedProjects.reduce(0) { $0 + monthHours($1) }
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

    private var canExport: Bool {
        switch mode {
        case .single: return selectedProject?.job != nil && !matchingEntries.isEmpty
        case .multiple: return !selectedProjects.isEmpty
        }
    }

    private var exportButtonTitle: String {
        let signed = activeSignature != nil
        switch mode {
        case .single:
            return signed ? "Export signed PDF" : "Export PDF"
        case .multiple:
            let count = selectedProjects.count
            if count <= 1 { return signed ? "Export signed PDF" : "Export PDF" }
            return signed ? "Export \(count) signed PDFs" : "Export \(count) PDFs"
        }
    }

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
                .environment(\.tabBarInset, 0)   // no tab bar inside this sheet
            }
            .onAppear {
                preselectSignature()
                preselectProjectsWithHours()
            }
            .onChange(of: signatures.count) { _, _ in preselectSignature() }
            .onChange(of: month) { _, _ in preselectProjectsWithHours() }
            .onChange(of: mode) { _, newMode in lastModeRaw = newMode.rawValue }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if allProjects.count > 1 {
                    Picker("Export", selection: $mode.animation(.easeInOut(duration: 0.2))) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
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
                Label(exportButtonTitle, systemImage: "square.and.arrow.up")
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
            monthSelector
            if mode == .single {
                projectMenu
            } else {
                projectChecklist
            }
        }
    }

    private var projectMenu: some View {
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
    }

    private var monthSelector: some View {
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
                Text(monthSubtitle)
                    .font(.app(.footnote))
                    .foregroundStyle(canExport ? Theme.textSecondary : Theme.textTertiary)
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

    private var monthSubtitle: String {
        switch mode {
        case .single:
            return "\(matchingEntries.count) \(matchingEntries.count == 1 ? "entry" : "entries") · \(DateDurationService.formattedDuration(hours: totalHours))"
        case .multiple:
            let count = selectedProjects.count
            return "\(count) \(count == 1 ? "project" : "projects") · \(DateDurationService.formattedDuration(hours: selectedTotalHours))"
        }
    }

    // MARK: Several projects

    private var projectChecklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Projects")
                Button(allWithHoursSelected ? "Clear" : "Select all with hours") {
                    if allWithHoursSelected {
                        selectedProjectIDs.removeAll()
                    } else {
                        preselectProjectsWithHours()
                    }
                }
                .font(.app(.footnote, .bold))
                .foregroundStyle(Theme.gold)
                .disabled(projectsWithHours.isEmpty)
            }

            VStack(spacing: 0) {
                ForEach(jobs.filter { !$0.projects.isEmpty }) { job in
                    Text(job.name)
                        .font(.app(.caption, .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    ForEach(job.projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { project in
                        projectCheckRow(project)
                    }
                }
            }
            .padding(.bottom, 6)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))

            if !selectedProjects.isEmpty {
                Text("Creates \(selectedProjects.count) separate \(selectedProjects.count == 1 ? "PDF" : "PDFs"), each with its own total and signature. They're shared together, e.g. attached to one email or saved to Files at once.")
                    .font(.app(.footnote))
                    .foregroundStyle(Theme.textSecondary)
            } else if projectsWithHours.isEmpty {
                Text("No project has hours in this month.")
                    .font(.app(.footnote))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func projectCheckRow(_ project: Project) -> some View {
        let hours = monthHours(project)
        let hasHours = hours > 0
        let isOn = selectedProjectIDs.contains(project.id) && hasHours
        return Button {
            if selectedProjectIDs.contains(project.id) {
                selectedProjectIDs.remove(project.id)
            } else {
                selectedProjectIDs.insert(project.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.app(.title3))
                    .foregroundStyle(isOn ? Theme.gold : Theme.textTertiary)
                Text(project.name)
                    .font(.app(.body, .medium))
                    .foregroundStyle(hasHours ? Theme.textPrimary : Theme.textTertiary)
                    .lineLimit(1)
                Spacer()
                Text(hasHours ? DateDurationService.formattedDuration(hours: hours) : "No hours")
                    .font(.app(.subheadline, hasHours ? .semibold : .regular))
                    .foregroundStyle(hasHours ? Theme.gold : Theme.textTertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasHours)
        .accessibilityLabel("\(project.name), \(hasHours ? DateDurationService.formattedDuration(hours: hours) : "no hours")")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var projectsWithHours: [Project] {
        allProjects.filter { monthHours($0) > 0 }
    }

    private var allWithHoursSelected: Bool {
        let ids = Set(projectsWithHours.map(\.id))
        return !ids.isEmpty && ids.isSubset(of: selectedProjectIDs)
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
            SectionLabel(mode == .multiple && selectedProjects.count > 1
                         ? "Preview · end of “\(selectedProjects.first?.name ?? "")”"
                         : "Preview")
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

    private func preselectProjectsWithHours() {
        selectedProjectIDs = Set(projectsWithHours.map(\.id))
    }

    private func shiftMonth(_ delta: Int) {
        month = Calendar.current.date(byAdding: .month, value: delta, to: month) ?? month
    }

    private func export() {
        guard canExport else { return }
        let signature = activeSignature
        if changingSignature || defaultSignature == nil, useAsDefault, let signature {
            defaultSignatureID = signature.id.uuidString
        }
        let stamp = signature.map { ExportService.SignatureStamp(image: $0.image, dateText: dateText) }

        if mode == .multiple {
            shareItem = ShareItem(urls: ExportService.monthExportPDFURLs(
                projects: selectedProjects,
                monthDate: month,
                signature: stamp
            ))
            return
        }

        guard let project = selectedProject, let job = project.job else { return }
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
