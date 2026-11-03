import SwiftUI
import SwiftData
import PDFKit

// MARK: - Export sheet

/// The export screen. Everything is adjustable — the date range (presets or any
/// days), which projects, PDF or CSV, English or German, the columns and their
/// order, rows per entry or per day, empty days, weekly subtotals, header fields,
/// totals, signatures and footer — and can be saved as a template.
/// The default template is applied when the sheet opens; a range or project the
/// sheet was opened for (calendar, project page) is kept on top of it.
struct ExportMonthSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let jobs: [Job]
    private let initialProject: Project?
    private let fixedPeriod: ExportService.ExportPeriod?
    private let initialMonth: Date

    @Query(sort: \ExportTemplate.createdAt) private var templates: [ExportTemplate]
    @Query(sort: \SavedSignature.createdAt) private var signatures: [SavedSignature]
    @AppStorage(AppSettings.Keys.defaultSignatureID) private var defaultSignatureID = AppSettings.Defaults.defaultSignatureID

    @State private var options: ExportOptions
    @State private var appliedTemplateID: UUID?
    /// The options as they were when the template was applied (incl. the range/project the sheet was opened for).
    @State private var baseline: ExportOptions?
    @State private var customSignatureDate = Date.now
    @State private var didApplyDefault = false

    @State private var shareItem: ShareItem?
    @State private var preview: PreviewItem?
    @State private var showingSaveAlert = false
    @State private var newTemplateName = ""
    @State private var showingTemplates = false
    @State private var showingSignatures = false
    @State private var nothingToExport = false

    init(jobs: [Job], initialProject: Project? = nil, initialMonth: Date = .now, period: ExportService.ExportPeriod? = nil) {
        self.jobs = jobs
        self.initialProject = initialProject
        self.fixedPeriod = period
        self.initialMonth = initialMonth
        _options = State(initialValue: Self.contextOptions(base: .standard, project: initialProject, period: period, month: initialMonth))
    }

    /// Applies what the sheet was opened for (a range, a month, a project) on top of `base`.
    private static func contextOptions(base: ExportOptions, project: Project?, period: ExportService.ExportPeriod?, month: Date) -> ExportOptions {
        var options = base
        let calendar = Calendar.current
        if let period {
            options.range = .custom
            options.customStart = period.firstDay
            options.customEnd = period.lastDay
        } else if !calendar.isDate(month, equalTo: .now, toGranularity: .month) {
            let interval = calendar.dateInterval(of: .month, for: month)
            options.range = .custom
            options.customStart = interval?.start
            options.customEnd = interval.map { $0.end.addingTimeInterval(-1) }
        }
        if let project {
            options.projectScope = .chosen
            options.projectIDs = [project.id]
            options.grouping = .perProject
        }
        return options
    }

    private var allProjects: [Project] { jobs.flatMap(\.projects) }
    private var period: ExportService.ExportPeriod { options.period() }
    private var exportedProjects: [Project] { TimesheetExporter.projects(for: options, from: allProjects, period: period) }
    private var appliedTemplate: ExportTemplate? { templates.first { $0.id == appliedTemplateID } }
    private var templateIsModified: Bool {
        guard appliedTemplate != nil, let baseline else { return false }
        return baseline.forTemplate != options.forTemplate
    }

    private var stampSignature: SavedSignature? {
        guard options.format == .pdf, options.employeeSignatureLine, options.stampSignature else { return nil }
        if let id = options.signatureID, let chosen = signatures.first(where: { $0.id == id }) { return chosen }
        return signatures.first { $0.id.uuidString == defaultSignatureID } ?? signatures.first
    }

    private var signingDate: Date {
        switch options.signatureDate {
        case .exportDay: .now
        case .lastDayOfRange: period.lastDay
        case .custom: customSignatureDate
        }
    }

    private var stamp: ExportService.SignatureStamp? {
        stampSignature.map {
            ExportService.SignatureStamp(image: $0.image, dateText: DateDurationService.signatureDateFormatter.string(from: signingDate))
        }
    }

    private var canExport: Bool { !exportedProjects.isEmpty && !options.columns.isEmpty }

    private var exportTitle: String {
        let count = options.grouping == .combined ? min(exportedProjects.count, 1) : exportedProjects.count
        let kind = options.format == .pdf ? (count == 1 ? "PDF" : "PDFs") : (count == 1 ? "CSV" : "CSVs")
        return count > 1 ? "Export \(count) \(kind)" : "Export \(kind)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if allProjects.isEmpty {
                    EmptyStateView(icon: "briefcase", title: "No projects yet", message: "Create a job and project first, then come back to export your hours.")
                } else {
                    Form {
                        templateSection
                        ExportOptionsSections(
                            options: $options,
                            jobs: jobs,
                            mode: .exporting,
                            customSignatureDate: $customSignatureDate,
                            onManageSignatures: { showingSignatures = true }
                        )
                    }
                    .safeAreaInset(edge: .bottom) { actionBar }
                }
            }
            .themedScreen()
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .shareSheet(item: $shareItem)
            .sheet(item: $preview) { item in
                ExportPreviewSheet(documents: item.documents)
            }
            .sheet(isPresented: $showingTemplates) {
                NavigationStack {
                    ExportTemplatesView(jobs: jobs, onUse: { template in apply(template) })
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { showingTemplates = false } }
                        }
                }
                .environment(\.tabBarInset, 0)
            }
            .sheet(isPresented: $showingSignatures) {
                NavigationStack {
                    SignaturesView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSignatures = false } }
                        }
                }
                .environment(\.tabBarInset, 0)
            }
            .alert("Save as template", isPresented: $showingSaveAlert) {
                TextField("Name, e.g. Studienkolleg monthly", text: $newTemplateName)
                Button("Save") { saveTemplate(makeDefault: false) }
                Button("Save as default") { saveTemplate(makeDefault: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(options.range == .custom
                     ? "Custom dates are saved as they are. Pick a preset like “Last month” to reuse the template every month."
                     : "Saves every setting below. The default template is used each time you open Export.")
            }
            .alert("Nothing to export", isPresented: $nothingToExport) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("None of the chosen projects has entries in this period.")
            }
            .onAppear(perform: applyDefaultTemplateOnce)
        }
    }

    // MARK: Template

    private var templateSection: some View {
        Section {
            Menu {
                Button {
                    appliedTemplateID = nil
                    options = Self.contextOptions(base: .standard, project: initialProject, period: fixedPeriod, month: initialMonth)
                } label: {
                    menuLabel("Standard settings", checked: appliedTemplateID == nil)
                }
                if !templates.isEmpty {
                    Section("Templates") {
                        ForEach(templates) { template in
                            Button { apply(template) } label: {
                                menuLabel(template.name + (template.isDefault ? " ★" : ""), checked: template.id == appliedTemplateID)
                            }
                        }
                    }
                }
                Section {
                    Button { newTemplateName = ""; showingSaveAlert = true } label: {
                        Label("Save as new template…", systemImage: "square.and.arrow.down")
                    }
                    if let appliedTemplate, templateIsModified {
                        Button { update(appliedTemplate) } label: {
                            Label("Update “\(appliedTemplate.name)”", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    Button { showingTemplates = true } label: {
                        Label("Manage templates…", systemImage: "slider.horizontal.3")
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.badge.gearshape")
                        .font(.app(.title3))
                        .foregroundStyle(Theme.gold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appliedTemplate?.name ?? "Standard settings")
                            .font(.app(.body, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(templateIsModified ? "Changed — save or update the template" : (appliedTemplate == nil ? "Tap to use or save a template" : "Template"))
                            .font(.app(.caption))
                            .foregroundStyle(templateIsModified ? Theme.gold : Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.app(.footnote, .semibold))
                        .foregroundStyle(Theme.gold)
                }
            }
            .themedRow()
        } header: {
            SectionLabel("Template")
        }
    }

    @ViewBuilder
    private func menuLabel(_ title: String, checked: Bool) -> some View {
        if checked { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    // MARK: Bottom bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                let docs = TimesheetExporter.documents(options: options, projects: allProjects, signature: stamp)
                if docs.isEmpty { nothingToExport = true } else { preview = PreviewItem(documents: docs) }
            } label: {
                Label("Preview", systemImage: "eye")
            }
            .buttonStyle(OutlineButtonStyle(height: 52))
            .frame(maxWidth: 140)
            .disabled(!canExport)

            Button(action: export) {
                Label(exportTitle, systemImage: "square.and.arrow.up")
            }
            .buttonStyle(GoldButtonStyle(height: 52))
            .disabled(!canExport)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Theme.background)
    }

    // MARK: Actions

    private func applyDefaultTemplateOnce() {
        guard !didApplyDefault else { return }
        didApplyDefault = true
        guard let template = templates.first(where: \.isDefault) else { return }
        appliedTemplateID = template.id
        options = Self.contextOptions(base: template.options, project: initialProject, period: fixedPeriod, month: initialMonth)
        baseline = options
    }

    private func apply(_ template: ExportTemplate) {
        appliedTemplateID = template.id
        options = template.options
        baseline = options
    }

    private func saveTemplate(makeDefault: Bool) {
        let name = newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = ExportTemplate(
            name: name.isEmpty ? "Template \(templates.count + 1)" : name,
            options: options,
            isDefault: makeDefault || templates.isEmpty
        )
        if template.isDefault { templates.forEach { $0.isDefault = false } }
        modelContext.insert(template)
        try? modelContext.save()
        appliedTemplateID = template.id
        baseline = options
    }

    private func update(_ template: ExportTemplate) {
        template.options = options
        try? modelContext.save()
        baseline = options
    }

    private func export() {
        guard let urls = TimesheetExporter.exportURLs(options: options, projects: allProjects, signature: stamp) else {
            nothingToExport = true
            return
        }
        shareItem = ShareItem(urls: urls)
    }
}

private struct PreviewItem: Identifiable {
    let id = UUID()
    let documents: [TimesheetExporter.Document]
}

// MARK: - Options form (shared by the sheet and the template editor)

struct ExportOptionsSections: View {
    enum Mode { case exporting, template }

    @Binding var options: ExportOptions
    let jobs: [Job]
    let mode: Mode
    @Binding var customSignatureDate: Date
    var onManageSignatures: (() -> Void)? = nil

    @Query(sort: \SavedSignature.createdAt) private var signatures: [SavedSignature]
    @AppStorage(AppSettings.Keys.signerName) private var signerName = AppSettings.Defaults.signerName
    @AppStorage(AppSettings.Keys.organization) private var organization = AppSettings.Defaults.organization
    @AppStorage(AppSettings.Keys.defaultSignatureID) private var defaultSignatureID = AppSettings.Defaults.defaultSignatureID

    private var allProjects: [Project] { jobs.flatMap(\.projects) }
    private var period: ExportService.ExportPeriod { options.period() }
    private var isPDF: Bool { options.format == .pdf }

    private func hours(_ project: Project) -> Double {
        project.entries.filter { period.contains($0.date) }.reduce(0) { $0 + $1.durationHours }
    }

    var body: some View {
        periodSection
        projectsSection
        formatSection
        tableSection
        if isPDF {
            headerSection
        }
        totalsSection
        if isPDF {
            signatureSection
            footerSection
        }
    }

    // MARK: Period

    private var periodSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(ExportOptions.RangePreset.allCases) { preset in
                    ChoiceChip(title: preset.title, isSelected: options.range == preset) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if preset == .custom, options.range != .custom {
                                let current = options.period()
                                options.customStart = current.firstDay
                                options.customEnd = current.lastDay
                            }
                            options.range = preset
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .themedRow()

            if options.range == .custom {
                DatePicker("From", selection: customStart, displayedComponents: .date)
                    .themedRow()
                DatePicker("To", selection: customEnd, in: customStart.wrappedValue..., displayedComponents: .date)
                    .themedRow()
                HStack {
                    Text("Whole month")
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 32) }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Previous month")
                    Text(customStart.wrappedValue.formatted(.dateTime.month(.abbreviated).year()))
                        .font(.app(.subheadline, .semibold))
                        .monospacedDigit()
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 32) }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Next month")
                }
                .foregroundStyle(Theme.gold)
                .themedRow()
            }
        } header: {
            SectionLabel("Period")
        } footer: {
            let entries = allProjects.flatMap(\.entries).filter { period.contains($0.date) }
            Text("\(TimesheetExporter.Formatter(language: options.language).periodLabel(period)) · \(entries.count) \(entries.count == 1 ? "entry" : "entries") · \(DateDurationService.formattedDuration(hours: entries.reduce(0) { $0 + $1.durationHours }))"
                 + (mode == .template && options.range != .custom ? " right now" : ""))
                .font(.app(.footnote))
                .monospacedDigit()
        }
    }

    private var customStart: Binding<Date> {
        Binding(
            get: { options.customStart ?? period.firstDay },
            set: { newValue in
                options.customStart = newValue
                if let end = options.customEnd, end < newValue { options.customEnd = newValue }
            }
        )
    }

    private var customEnd: Binding<Date> {
        Binding(get: { options.customEnd ?? period.lastDay }, set: { options.customEnd = $0 })
    }

    private func shiftMonth(_ delta: Int) {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .month, value: delta, to: customStart.wrappedValue) ?? customStart.wrappedValue
        guard let month = calendar.dateInterval(of: .month, for: base) else { return }
        options.customStart = month.start
        options.customEnd = month.end.addingTimeInterval(-1)
    }

    // MARK: Projects

    private var projectsSection: some View {
        Section {
            Picker("Projects", selection: $options.projectScope.animation()) {
                ForEach(ExportOptions.ProjectScope.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .themedRow()

            if options.projectScope == .chosen {
                ForEach(jobs.filter { !$0.projects.isEmpty }) { job in
                    ForEach(job.projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { project in
                        let isOn = options.projectIDs.contains(project.id)
                        let projectHours = hours(project)
                        Button {
                            if isOn { options.projectIDs.removeAll { $0 == project.id } } else { options.projectIDs.append(project.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                                    .font(.app(.title3))
                                    .foregroundStyle(isOn ? Theme.gold : Theme.textTertiary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(project.name).font(.app(.body, .medium)).foregroundStyle(Theme.textPrimary)
                                    Text(job.name).font(.app(.caption)).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Text(projectHours > 0 ? DateDurationService.formattedDuration(hours: projectHours) : "No hours")
                                    .font(.app(.subheadline, projectHours > 0 ? .semibold : .regular))
                                    .foregroundStyle(projectHours > 0 ? Theme.gold : Theme.textTertiary)
                                    .monospacedDigit()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .themedRow()
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
            }

            Picker("Files", selection: $options.grouping) {
                ForEach(ExportOptions.Grouping.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .themedRow()
        } header: {
            SectionLabel("Projects")
        } footer: {
            let count = TimesheetExporter.projects(for: options, from: allProjects, period: period).count
            Text(options.grouping == .combined
                 ? "\(count) \(count == 1 ? "project" : "projects") on one sheet\(options.columns.contains(.project) || count < 2 ? "." : " — tip: add the Project column so rows can be told apart.")"
                 : "\(count) separate \(count == 1 ? "file" : "files"), each with its own total and signature.")
                .font(.app(.footnote))
        }
    }

    // MARK: Format

    private var formatSection: some View {
        Section {
            Picker("Format", selection: $options.format.animation()) {
                ForEach(ExportOptions.Format.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .themedRow()
            Picker("Language", selection: $options.language) {
                ForEach(ExportOptions.SheetLanguage.allCases) { Text($0.title).tag($0) }
            }
            .themedRow()
            if isPDF {
                Picker("Page", selection: $options.orientation) {
                    ForEach(ExportOptions.Orientation.allCases) { Text($0.title).tag($0) }
                }
                .themedRow()
            }
        } header: {
            SectionLabel("Format")
        } footer: {
            Text(options.language == .german
                 ? "Labels, dates and numbers in German (e.g. “Stundenzettel”, 05.10.2026, 7,50)."
                 : "Labels, dates and numbers in English.")
                .font(.app(.footnote))
        }
    }

    // MARK: Table

    private var tableSection: some View {
        Section {
            NavigationLink {
                ExportColumnsEditor(columns: $options.columns)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Columns")
                    Text(options.columns.isEmpty ? "None — choose at least one" : options.columns.map(\.title).joined(separator: ", "))
                        .font(.app(.footnote))
                        .foregroundStyle(options.columns.isEmpty ? Theme.warning : Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            .themedRow()
            Toggle("One row per day", isOn: $options.groupByDay)
                .themedRow()
            Toggle("List days without work", isOn: $options.includeEmptyDays)
                .themedRow()
            Toggle("Weekly subtotals", isOn: $options.weeklySubtotals)
                .themedRow()
        } header: {
            SectionLabel("Table")
        } footer: {
            Text("“One row per day” combines a day's entries: first start, last end, breaks and hours added up.")
                .font(.app(.footnote))
        }
        .tint(Theme.goldFill)
    }

    // MARK: Header

    private var headerSection: some View {
        Section {
            TextField("Title (default: \(TimesheetExporter.Labels(language: options.language).title))", text: $options.title)
                .themedRow()
            Toggle(isOn: $options.showName) {
                labeled("Your name", signerName.isEmpty ? "Not set — add it in Settings › Timesheet details" : signerName)
            }
            .themedRow()
            Toggle(isOn: $options.showOrganization) {
                labeled("Organisation", organization.isEmpty ? "Not set" : organization)
            }
            .themedRow()
            Toggle("Job and project", isOn: $options.showJobAndProject)
                .themedRow()
            Toggle("Period", isOn: $options.showPeriod)
                .themedRow()
            TextField("Note under the header (optional)", text: $options.note, axis: .vertical)
                .lineLimit(1...4)
                .themedRow()
        } header: {
            SectionLabel("Header")
        }
        .tint(Theme.goldFill)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(value).font(.app(.footnote)).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
    }

    // MARK: Totals

    private var totalsSection: some View {
        Section {
            Toggle("Total hours", isOn: $options.showTotal)
                .themedRow()
            if isPDF {
                Toggle("Number of days worked", isOn: $options.showDaysWorked)
                    .themedRow()
                if options.grouping == .combined {
                    Toggle("Total per project", isOn: $options.showProjectTotals)
                        .themedRow()
                }
            }
        } header: {
            SectionLabel("Totals")
        }
        .tint(Theme.goldFill)
    }

    // MARK: Signatures

    private var signatureSection: some View {
        Section {
            Toggle("Employee signature line", isOn: $options.employeeSignatureLine.animation())
                .themedRow()
            if options.employeeSignatureLine {
                Toggle("Sign with my saved signature", isOn: $options.stampSignature.animation())
                    .themedRow()
                if options.stampSignature {
                    if signatures.isEmpty {
                        Button("Draw a signature first…") { onManageSignatures?() }
                            .themedRow()
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(signatures) { signature in
                                    signatureTile(signature)
                                }
                                if let onManageSignatures {
                                    Button(action: onManageSignatures) {
                                        Image(systemName: "plus")
                                            .font(.app(.title3, .semibold))
                                            .foregroundStyle(Theme.gold)
                                            .frame(width: 60, height: 74)
                                            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("New signature")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .themedRow()
                    }
                    Picker("Date next to it", selection: $options.signatureDate) {
                        ForEach(ExportOptions.SignatureDate.allCases.filter { mode == .exporting || $0 != .custom }) {
                            Text($0.title).tag($0)
                        }
                    }
                    .themedRow()
                    if options.signatureDate == .custom && mode == .exporting {
                        DatePicker("Signed on", selection: $customSignatureDate, displayedComponents: .date)
                            .themedRow()
                    }
                }
            }
            Toggle("Supervisor signature line", isOn: $options.supervisorSignatureLine)
                .themedRow()
        } header: {
            SectionLabel("Signatures")
        }
        .tint(Theme.goldFill)
    }

    private func signatureTile(_ signature: SavedSignature) -> some View {
        let selectedID = options.signatureID ?? signatures.first { $0.id.uuidString == defaultSignatureID }?.id ?? signatures.first?.id
        let isSelected = selectedID == signature.id
        return Button {
            options.signatureID = signature.id
        } label: {
            VStack(spacing: 4) {
                SignatureThumbnail(signature: signature)
                    .frame(width: 104, height: 50)
                Text(signature.name + (signature.id.uuidString == defaultSignatureID ? " ★" : ""))
                    .font(.app(.caption, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            .padding(6)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(isSelected ? Theme.gold : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(signature.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Footer

    private var footerSection: some View {
        Section {
            Toggle("“Generated on” date", isOn: $options.showGeneratedDate)
                .themedRow()
            Toggle("Page numbers", isOn: $options.showPageNumbers)
                .themedRow()
        } header: {
            SectionLabel("Footer")
        }
        .tint(Theme.goldFill)
    }
}

// MARK: - Columns editor

/// Switch columns on or off and drag them into order.
struct ExportColumnsEditor: View {
    @Binding var columns: [ExportOptions.Column]
    @State private var order: [ExportOptions.Column] = []

    var body: some View {
        List {
            Section {
                ForEach(order) { column in
                    Toggle(isOn: Binding(
                        get: { columns.contains(column) },
                        set: { isOn in
                            if isOn { columns = order.filter { columns.contains($0) || $0 == column } }
                            else { columns.removeAll { $0 == column } }
                        }
                    )) {
                        Text(column.title)
                            .foregroundStyle(columns.contains(column) ? Theme.textPrimary : Theme.textTertiary)
                    }
                    .tint(Theme.goldFill)
                    .themedRow()
                }
                .onMove { from, to in
                    order.move(fromOffsets: from, toOffset: to)
                    columns = order.filter { columns.contains($0) }
                }
            } footer: {
                Text("Drag ≡ to change the order. Columns that are off aren't exported.")
                    .font(.app(.footnote))
            }
            Section {
                Button("Reset to default") {
                    columns = ExportOptions.defaultColumns
                    order = ExportOptions.defaultColumns + ExportOptions.Column.allCases.filter { !ExportOptions.defaultColumns.contains($0) }
                }
                .foregroundStyle(Theme.gold)
                .themedRow()
            }
        }
        .environment(\.editMode, .constant(.active))
        .themedScreen()
        .navigationTitle("Columns")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if order.isEmpty {
                order = columns + ExportOptions.Column.allCases.filter { !columns.contains($0) }
            }
        }
    }
}

// MARK: - Preview

struct ExportPreviewSheet: View {
    let documents: [TimesheetExporter.Document]
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if documents.count > 1 {
                    Picker("File", selection: $index) {
                        ForEach(documents.indices, id: \.self) { Text(documents[$0].filename).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .padding(.vertical, 6)
                }
                let document = documents[min(index, documents.count - 1)]
                if document.filename.hasSuffix(".pdf") {
                    PDFKitView(data: document.data)
                        .id(index)
                } else {
                    ScrollView([.vertical, .horizontal]) {
                        Text(String(decoding: document.data, as: UTF8.self))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                            .textSelection(.enabled)
                            .padding()
                    }
                }
            }
            .themedScreen()
            .navigationTitle(documents.count > 1 ? "Preview · \(documents.count) files" : "Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

private struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}

// MARK: - Templates

/// Saved export templates: use, edit, make default, duplicate, delete.
struct ExportTemplatesView: View {
    let jobs: [Job]
    var onUse: ((ExportTemplate) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ExportTemplate.createdAt) private var templates: [ExportTemplate]
    @State private var editing: ExportTemplate?
    @State private var creating = false

    var body: some View {
        List {
            if templates.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No templates yet")
                            .font(.app(.headline))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Set up an export the way you like it, then choose “Save as new template…” in the Export sheet — or create one here.")
                            .font(.app(.subheadline))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 6)
                    .themedRow()
                }
            } else {
                Section {
                    ForEach(templates) { template in
                        Button {
                            if let onUse { onUse(template); dismiss() } else { editing = template }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: template.isDefault ? "star.fill" : "doc.text")
                                    .foregroundStyle(Theme.gold)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name)
                                        .font(.app(.body, .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(template.summary + (template.isDefault ? " · default" : ""))
                                        .font(.app(.footnote))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                if onUse != nil {
                                    Button { editing = template } label: {
                                        Image(systemName: "pencil.circle")
                                            .font(.app(.title3))
                                            .foregroundStyle(Theme.gold)
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Edit \(template.name)")
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .themedRow()
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(template) } label: { Label("Delete", systemImage: "trash") }
                            Button { duplicate(template) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                .tint(.gray)
                        }
                        .swipeActions(edge: .leading) {
                            Button { toggleDefault(template) } label: {
                                Label(template.isDefault ? "Not default" : "Default", systemImage: template.isDefault ? "star.slash" : "star")
                            }
                            .tint(Theme.goldFill)
                        }
                        .contextMenu {
                            Button { editing = template } label: { Label("Edit", systemImage: "pencil") }
                            Button { toggleDefault(template) } label: {
                                Label(template.isDefault ? "Stop using as default" : "Use as default", systemImage: "star")
                            }
                            Button { duplicate(template) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                            Button(role: .destructive) { delete(template) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                } header: {
                    SectionLabel("Templates")
                } footer: {
                    Text("★ The default template is applied every time you open Export. Swipe right to change it.")
                        .font(.app(.footnote))
                }
            }
            Section {
                Button { creating = true } label: {
                    Label("New template", systemImage: "plus.circle.fill")
                        .font(.app(.body, .semibold))
                        .foregroundStyle(Theme.gold)
                }
                .themedRow()
            }
        }
        .themedScreen()
        .tabBarSpace()
        .navigationTitle("Export templates")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { template in
            ExportTemplateEditor(template: template, jobs: jobs)
        }
        .sheet(isPresented: $creating) {
            ExportTemplateEditor(template: nil, jobs: jobs)
        }
    }

    private func toggleDefault(_ template: ExportTemplate) {
        let makeDefault = !template.isDefault
        templates.forEach { $0.isDefault = false }
        template.isDefault = makeDefault
        try? modelContext.save()
    }

    private func duplicate(_ template: ExportTemplate) {
        modelContext.insert(ExportTemplate(name: "\(template.name) copy", options: template.options))
        try? modelContext.save()
    }

    private func delete(_ template: ExportTemplate) {
        modelContext.delete(template)
        try? modelContext.save()
    }
}

/// Edit (or create) a template without exporting.
struct ExportTemplateEditor: View {
    let template: ExportTemplate?
    let jobs: [Job]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var templates: [ExportTemplate]
    @State private var name: String
    @State private var options: ExportOptions
    @State private var isDefault: Bool
    @State private var unusedDate = Date.now

    init(template: ExportTemplate?, jobs: [Job]) {
        self.template = template
        self.jobs = jobs
        _name = State(initialValue: template?.name ?? "")
        _options = State(initialValue: template?.options ?? .standard)
        _isDefault = State(initialValue: template?.isDefault ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Template name", text: $name)
                        .themedRow()
                    Toggle("Use by default", isOn: $isDefault)
                        .tint(Theme.goldFill)
                        .themedRow()
                } header: {
                    SectionLabel("Template")
                }
                ExportOptionsSections(options: $options, jobs: jobs, mode: .template, customSignatureDate: $unusedDate)
            }
            .themedScreen()
            .navigationTitle(template == nil ? "New template" : "Edit template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || options.columns.isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if isDefault { templates.forEach { $0.isDefault = false } }
        if let template {
            template.name = trimmed
            template.options = options
            template.isDefault = isDefault
        } else {
            modelContext.insert(ExportTemplate(name: trimmed, options: options, isDefault: isDefault))
        }
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Checkbox style

/// A square checkbox toggle.
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
}
