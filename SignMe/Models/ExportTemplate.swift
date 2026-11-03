import Foundation
import SwiftData

// MARK: - Options

/// Everything that decides what an export looks like. Saved inside templates as JSON,
/// so new options can be added later: missing keys simply fall back to their defaults.
struct ExportOptions: Codable, Equatable {

    enum RangePreset: String, Codable, CaseIterable, Identifiable {
        case thisWeek, lastWeek, thisMonth, lastMonth, last30Days, thisYear, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .thisWeek: "This week"
            case .lastWeek: "Last week"
            case .thisMonth: "This month"
            case .lastMonth: "Last month"
            case .last30Days: "Last 30 days"
            case .thisYear: "This year"
            case .custom: "Custom"
            }
        }
    }

    enum Format: String, Codable, CaseIterable, Identifiable {
        case pdf, csv
        var id: String { rawValue }
        var title: String { self == .pdf ? "PDF" : "Spreadsheet (CSV)" }
    }

    enum ProjectScope: String, Codable, CaseIterable, Identifiable {
        /// Every project that has hours in the range.
        case withHours
        /// Only the projects in `projectIDs`.
        case chosen
        var id: String { rawValue }
        var title: String { self == .withHours ? "All with hours" : "Choose" }
    }

    enum Grouping: String, Codable, CaseIterable, Identifiable {
        case perProject, combined
        var id: String { rawValue }
        var title: String { self == .perProject ? "One file per project" : "One combined file" }
    }

    enum SheetLanguage: String, Codable, CaseIterable, Identifiable {
        case english, german
        var id: String { rawValue }
        var title: String { self == .english ? "English" : "Deutsch" }
        var locale: Locale { Locale(identifier: self == .english ? "en_GB" : "de_DE") }
    }

    enum Orientation: String, Codable, CaseIterable, Identifiable {
        case portrait, landscape
        var id: String { rawValue }
        var title: String { self == .portrait ? "Portrait" : "Landscape" }
    }

    enum SignatureDate: String, Codable, CaseIterable, Identifiable {
        /// The day the export is made.
        case exportDay
        /// The last day of the exported range.
        case lastDayOfRange
        /// A date picked in the export sheet (not stored in templates).
        case custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .exportDay: "Export day"
            case .lastDayOfRange: "Last day of period"
            case .custom: "Other date"
            }
        }
    }

    enum Column: String, Codable, CaseIterable, Identifiable {
        case date, weekday, start, end, breakTime, duration, decimalHours, description, project, job
        var id: String { rawValue }
        var title: String {
            switch self {
            case .date: "Date"
            case .weekday: "Weekday"
            case .start: "Start"
            case .end: "End"
            case .breakTime: "Break"
            case .duration: "Hours (h min)"
            case .decimalHours: "Decimal hours"
            case .description: "Description"
            case .project: "Project"
            case .job: "Job"
            }
        }
        /// Relative width on the PDF; the description takes whatever is left.
        var weight: Double {
            switch self {
            case .date: 0.13
            case .weekday: 0.08
            case .start: 0.08
            case .end: 0.10
            case .breakTime: 0.08
            case .duration: 0.11
            case .decimalHours: 0.08
            case .description: 0.30
            case .project: 0.15
            case .job: 0.15
            }
        }
        /// Columns whose text can wrap onto several lines.
        var wraps: Bool { self == .description || self == .project || self == .job }
        var isNumeric: Bool { self == .duration || self == .decimalHours || self == .breakTime }
    }

    // Range
    var range: RangePreset = .thisMonth
    var customStart: Date?
    var customEnd: Date?

    // What's included
    var projectScope: ProjectScope = .withHours
    var projectIDs: [UUID] = []
    var grouping: Grouping = .perProject

    // Format
    var format: Format = .pdf
    var language: SheetLanguage = .english
    var orientation: Orientation = .portrait

    // Header
    var title: String = ""
    var showName = true
    var showOrganization = true
    var showJobAndProject = true
    var showPeriod = true
    var note: String = ""

    // Table
    var columns: [Column] = ExportOptions.defaultColumns
    var groupByDay = false
    var includeEmptyDays = false
    var weeklySubtotals = false

    // Summary
    var showTotal = true
    var showDaysWorked = false
    var showProjectTotals = true

    // Signatures
    var employeeSignatureLine = true
    var supervisorSignatureLine = true
    var stampSignature = true
    /// nil = the default signature (or the first one).
    var signatureID: UUID?
    var signatureDate: SignatureDate = .exportDay

    // Footer
    var showGeneratedDate = true
    var showPageNumbers = true

    static let defaultColumns: [Column] = [.date, .start, .end, .breakTime, .duration, .description]

    init() {}

    /// Defaults that follow the app's settings (e.g. supervisor line on or off).
    static var standard: ExportOptions {
        var options = ExportOptions()
        let defaults = UserDefaults.standard
        options.supervisorSignatureLine = defaults.object(forKey: AppSettings.Keys.includeSupervisorSignature) as? Bool
            ?? AppSettings.Defaults.includeSupervisorSignature
        return options
    }

    // MARK: Codable (tolerant of missing keys)

    private enum CodingKeys: String, CodingKey {
        case range, customStart, customEnd, projectScope, projectIDs, grouping, format, language, orientation
        case title, showName, showOrganization, showJobAndProject, showPeriod, note
        case columns, groupByDay, includeEmptyDays, weeklySubtotals
        case showTotal, showDaysWorked, showProjectTotals
        case employeeSignatureLine, supervisorSignatureLine, stampSignature, signatureID, signatureDate
        case showGeneratedDate, showPageNumbers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ExportOptions()
        range = (try? c.decodeIfPresent(RangePreset.self, forKey: .range)) ?? d.range
        customStart = try? c.decodeIfPresent(Date.self, forKey: .customStart)
        customEnd = try? c.decodeIfPresent(Date.self, forKey: .customEnd)
        projectScope = (try? c.decodeIfPresent(ProjectScope.self, forKey: .projectScope)) ?? d.projectScope
        projectIDs = (try? c.decodeIfPresent([UUID].self, forKey: .projectIDs)) ?? d.projectIDs
        grouping = (try? c.decodeIfPresent(Grouping.self, forKey: .grouping)) ?? d.grouping
        format = (try? c.decodeIfPresent(Format.self, forKey: .format)) ?? d.format
        language = (try? c.decodeIfPresent(SheetLanguage.self, forKey: .language)) ?? d.language
        orientation = (try? c.decodeIfPresent(Orientation.self, forKey: .orientation)) ?? d.orientation
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? d.title
        showName = (try? c.decodeIfPresent(Bool.self, forKey: .showName)) ?? d.showName
        showOrganization = (try? c.decodeIfPresent(Bool.self, forKey: .showOrganization)) ?? d.showOrganization
        showJobAndProject = (try? c.decodeIfPresent(Bool.self, forKey: .showJobAndProject)) ?? d.showJobAndProject
        showPeriod = (try? c.decodeIfPresent(Bool.self, forKey: .showPeriod)) ?? d.showPeriod
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? d.note
        // Unknown column names (from a newer version) are skipped.
        if let raw = try? c.decodeIfPresent([String].self, forKey: .columns) {
            var seen = Set<Column>()
            columns = raw.compactMap(Column.init(rawValue:)).filter { seen.insert($0).inserted }
        } else {
            columns = d.columns
        }
        groupByDay = (try? c.decodeIfPresent(Bool.self, forKey: .groupByDay)) ?? d.groupByDay
        includeEmptyDays = (try? c.decodeIfPresent(Bool.self, forKey: .includeEmptyDays)) ?? d.includeEmptyDays
        weeklySubtotals = (try? c.decodeIfPresent(Bool.self, forKey: .weeklySubtotals)) ?? d.weeklySubtotals
        showTotal = (try? c.decodeIfPresent(Bool.self, forKey: .showTotal)) ?? d.showTotal
        showDaysWorked = (try? c.decodeIfPresent(Bool.self, forKey: .showDaysWorked)) ?? d.showDaysWorked
        showProjectTotals = (try? c.decodeIfPresent(Bool.self, forKey: .showProjectTotals)) ?? d.showProjectTotals
        employeeSignatureLine = (try? c.decodeIfPresent(Bool.self, forKey: .employeeSignatureLine)) ?? d.employeeSignatureLine
        supervisorSignatureLine = (try? c.decodeIfPresent(Bool.self, forKey: .supervisorSignatureLine)) ?? d.supervisorSignatureLine
        stampSignature = (try? c.decodeIfPresent(Bool.self, forKey: .stampSignature)) ?? d.stampSignature
        signatureID = try? c.decodeIfPresent(UUID.self, forKey: .signatureID)
        signatureDate = (try? c.decodeIfPresent(SignatureDate.self, forKey: .signatureDate)) ?? d.signatureDate
        showGeneratedDate = (try? c.decodeIfPresent(Bool.self, forKey: .showGeneratedDate)) ?? d.showGeneratedDate
        showPageNumbers = (try? c.decodeIfPresent(Bool.self, forKey: .showPageNumbers)) ?? d.showPageNumbers
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(range, forKey: .range)
        try c.encodeIfPresent(customStart, forKey: .customStart)
        try c.encodeIfPresent(customEnd, forKey: .customEnd)
        try c.encode(projectScope, forKey: .projectScope)
        try c.encode(projectIDs, forKey: .projectIDs)
        try c.encode(grouping, forKey: .grouping)
        try c.encode(format, forKey: .format)
        try c.encode(language, forKey: .language)
        try c.encode(orientation, forKey: .orientation)
        try c.encode(title, forKey: .title)
        try c.encode(showName, forKey: .showName)
        try c.encode(showOrganization, forKey: .showOrganization)
        try c.encode(showJobAndProject, forKey: .showJobAndProject)
        try c.encode(showPeriod, forKey: .showPeriod)
        try c.encode(note, forKey: .note)
        try c.encode(columns.map(\.rawValue), forKey: .columns)
        try c.encode(groupByDay, forKey: .groupByDay)
        try c.encode(includeEmptyDays, forKey: .includeEmptyDays)
        try c.encode(weeklySubtotals, forKey: .weeklySubtotals)
        try c.encode(showTotal, forKey: .showTotal)
        try c.encode(showDaysWorked, forKey: .showDaysWorked)
        try c.encode(showProjectTotals, forKey: .showProjectTotals)
        try c.encode(employeeSignatureLine, forKey: .employeeSignatureLine)
        try c.encode(supervisorSignatureLine, forKey: .supervisorSignatureLine)
        try c.encode(stampSignature, forKey: .stampSignature)
        try c.encodeIfPresent(signatureID, forKey: .signatureID)
        try c.encode(signatureDate, forKey: .signatureDate)
        try c.encode(showGeneratedDate, forKey: .showGeneratedDate)
        try c.encode(showPageNumbers, forKey: .showPageNumbers)
    }

    // MARK: Range

    /// The concrete days the options cover, relative to `now` for the presets.
    func period(now: Date = .now, calendar: Calendar = .current) -> ExportService.ExportPeriod {
        switch range {
        case .thisWeek, .lastWeek:
            let base = range == .thisWeek ? now : (calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now)
            let week = calendar.dateInterval(of: .weekOfYear, for: base) ?? DateInterval(start: base, duration: 86400)
            return .days(week.start, week.end.addingTimeInterval(-1), calendar: calendar)
        case .thisMonth:
            return .month(now, calendar: calendar)
        case .lastMonth:
            return .month(calendar.date(byAdding: .month, value: -1, to: now) ?? now, calendar: calendar)
        case .last30Days:
            return .days(calendar.date(byAdding: .day, value: -29, to: now) ?? now, now, calendar: calendar)
        case .thisYear:
            let year = calendar.dateInterval(of: .year, for: now) ?? DateInterval(start: now, duration: 86400)
            return .days(year.start, year.end.addingTimeInterval(-1), calendar: calendar)
        case .custom:
            let start = customStart ?? calendar.dateInterval(of: .month, for: now)?.start ?? now
            let end = customEnd ?? now
            return .days(start, end, calendar: calendar)
        }
    }

    /// A copy for saving in a template: a one-off "Other date" for the signature becomes the export day.
    var forTemplate: ExportOptions {
        var copy = self
        if copy.signatureDate == .custom { copy.signatureDate = .exportDay }
        return copy
    }
}

// MARK: - Template

/// A saved set of export options ("Studienkolleg monthly", "Weekly CSV for HR").
/// The default template is applied whenever the export sheet opens.
@Model
final class ExportTemplate {
    var id: UUID
    var name: String
    var optionsData: Data
    var isDefault: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, options: ExportOptions, isDefault: Bool = false, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.optionsData = (try? JSONEncoder().encode(options.forTemplate)) ?? Data()
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var options: ExportOptions {
        get { (try? JSONDecoder().decode(ExportOptions.self, from: optionsData)) ?? .standard }
        set {
            optionsData = (try? JSONEncoder().encode(newValue.forTemplate)) ?? optionsData
            updatedAt = .now
        }
    }

    /// One line describing the template, e.g. "Last month · PDF · per project · Deutsch".
    var summary: String {
        let o = options
        var parts = [o.range == .custom ? "Fixed dates" : o.range.title, o.format == .pdf ? "PDF" : "CSV"]
        parts.append(o.grouping == .combined ? "combined" : "per project")
        if o.language == .german { parts.append("Deutsch") }
        return parts.joined(separator: " · ")
    }
}
