import Foundation
import UIKit

/// Turns `ExportOptions` into finished files: A4 PDF timesheets (portrait or
/// landscape, English or German) or CSV spreadsheets, one per project or one combined.
enum TimesheetExporter {

    struct Document {
        var filename: String
        var data: Data
    }

    // MARK: - Labels

    struct Labels {
        let language: ExportOptions.SheetLanguage
        private var de: Bool { language == .german }

        var title: String { de ? "Stundenzettel" : "Timesheet" }
        var name: String { "Name" }
        var organization: String { de ? "Einrichtung" : "Organisation" }
        var jobProject: String { de ? "Tätigkeit" : "Job / project" }
        var period: String { de ? "Zeitraum" : "Period" }
        var total: String { de ? "Gesamt" : "Total" }
        var daysWorked: String { de ? "Arbeitstage" : "Days worked" }
        var week: String { de ? "KW" : "Week" }
        var generated: String { de ? "Erstellt am" : "Generated" }
        var noWork: String { "—" }
        var employeeSignature: String { de ? "Datum, Unterschrift (Beschäftigte/r)" : "Date, signature (employee)" }
        var supervisorSignature: String { de ? "Datum, Unterschrift (Vorgesetzte/r)" : "Date, signature (supervisor)" }
        func page(_ page: Int, of total: Int?) -> String {
            if let total { return de ? "Seite \(page) von \(total)" : "Page \(page) of \(total)" }
            return de ? "Seite \(page)" : "Page \(page)"
        }
        func employeeSignature(name: String) -> String {
            name.isEmpty ? employeeSignature : (de ? "Datum, Unterschrift — \(name)" : "Date, signature — \(name)")
        }

        func column(_ column: ExportOptions.Column) -> String {
            switch column {
            case .date: de ? "Datum" : "Date"
            case .weekday: de ? "Tag" : "Day"
            case .start: de ? "Beginn" : "Start"
            case .end: de ? "Ende" : "End"
            case .breakTime: de ? "Pause" : "Break"
            case .duration: de ? "Stunden" : "Hours"
            case .decimalHours: de ? "Dezimal" : "Decimal"
            case .description: de ? "Tätigkeit" : "Description"
            case .project: de ? "Projekt" : "Project"
            case .job: de ? "Stelle" : "Job"
            }
        }
    }

    // MARK: - Formatting

    struct Formatter {
        let language: ExportOptions.SheetLanguage
        let calendar: Calendar
        private let dateFormatter: DateFormatter
        private let isoFormatter: DateFormatter
        private let weekdayFormatter: DateFormatter
        private let timeFormatter: DateFormatter
        private let monthFormatter: DateFormatter
        private let shortFormatter: DateFormatter
        private let number: NumberFormatter

        init(language: ExportOptions.SheetLanguage, calendar: Calendar = .current) {
            self.language = language
            self.calendar = calendar
            let locale = language.locale
            func make(_ format: String) -> DateFormatter {
                let formatter = DateFormatter()
                formatter.locale = locale
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = format
                return formatter
            }
            dateFormatter = make(language == .german ? "dd.MM.yyyy" : "d MMM yyyy")
            isoFormatter = make("yyyy-MM-dd")
            isoFormatter.locale = Locale(identifier: "en_US_POSIX")
            weekdayFormatter = make("EEE")
            timeFormatter = make("HH:mm")
            monthFormatter = make("LLLL yyyy")
            shortFormatter = make(language == .german ? "d. MMM" : "d MMM")
            number = NumberFormatter()
            number.locale = locale
            number.minimumFractionDigits = 2
            number.maximumFractionDigits = 2
        }

        func date(_ date: Date) -> String { dateFormatter.string(from: date) }
        func iso(_ date: Date) -> String { isoFormatter.string(from: date) }
        func weekday(_ date: Date) -> String { weekdayFormatter.string(from: date) }
        func time(_ date: Date) -> String { timeFormatter.string(from: date) }
        func decimal(_ hours: Double) -> String { number.string(from: NSNumber(value: hours)) ?? String(format: "%.2f", hours) }
        /// "4h 55min" on sheets; "4:55" in spreadsheets so it stays calculable.
        func duration(_ hours: Double, forCSV: Bool = false) -> String {
            let minutes = max(0, Int((hours * 60).rounded()))
            if forCSV { return String(format: "%d:%02d", minutes / 60, minutes % 60) }
            let h = minutes / 60, m = minutes % 60
            if h == 0 { return "\(m)min" }
            return m == 0 ? "\(h)h" : "\(h)h \(m)min"
        }
        func breakText(_ minutes: Int) -> String {
            minutes == 0 ? "—" : (language == .german ? "\(minutes) Min." : "\(minutes) min")
        }

        func periodLabel(_ period: ExportService.ExportPeriod) -> String {
            if period.isWholeMonth { return monthFormatter.string(from: period.firstDay) }
            if calendar.isDate(period.firstDay, inSameDayAs: period.lastDay) { return date(period.firstDay) }
            return "\(date(period.firstDay)) – \(date(period.lastDay))"
        }

        /// "Oktober_2026" or "2026-10-05_to_2026-10-11"
        func periodSlug(_ period: ExportService.ExportPeriod) -> String {
            if period.isWholeMonth { return monthFormatter.string(from: period.firstDay).replacingOccurrences(of: " ", with: "_") }
            let start = iso(period.firstDay), end = iso(period.lastDay)
            return start == end ? start : "\(start)_to_\(end)"
        }

        var csvSeparator: String { language == .german ? ";" : "," }
    }

    // MARK: - Rows

    struct Row: Equatable {
        enum Kind: Equatable { case work, emptyDay, weekSubtotal }
        var kind: Kind
        var date: Date
        var values: [ExportOptions.Column: String]
        var hours: Double
        /// Only for subtotals: "Week 41".
        var label: String = ""
    }

    /// The table rows for `entries` within `period`: one per entry (or per day),
    /// optionally with empty days and weekly subtotals.
    static func rows(
        entries: [WorkEntry],
        period: ExportService.ExportPeriod,
        options: ExportOptions,
        format: Formatter,
        labels: Labels,
        forCSV: Bool = false
    ) -> [Row] {
        let calendar = format.calendar
        let sorted = entries.filter { period.contains($0.date) }.sorted { $0.startTime < $1.startTime }

        func dateValue(_ date: Date) -> String { forCSV ? format.iso(date) : format.date(date) }

        var rows: [Row]
        if options.groupByDay {
            let byDay = Dictionary(grouping: sorted) { calendar.startOfDay(for: $0.date) }
            rows = byDay.keys.sorted().map { day in
                let items = byDay[day] ?? []
                let start = items.map(\.startTime).min() ?? day
                let end = items.map(\.endTime).max() ?? day
                let hours = items.reduce(0) { $0 + $1.durationHours }
                let breaks = items.reduce(0) { $0 + $1.breakMinutes }
                func unique(_ values: [String]) -> String {
                    var seen = Set<String>()
                    return values.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: forCSV ? " | " : "; ")
                }
                var values: [ExportOptions.Column: String] = [
                    .date: dateValue(day),
                    .weekday: format.weekday(day),
                    .start: format.time(start),
                    .end: format.time(end) + (calendar.isDate(start, inSameDayAs: end) ? "" : " (+1)"),
                    .breakTime: forCSV ? String(breaks) : format.breakText(breaks),
                    .duration: format.duration(hours, forCSV: forCSV),
                    .decimalHours: format.decimal(hours)
                ]
                values[.description] = unique(items.map(\.taskDescription))
                values[.project] = unique(items.compactMap { $0.project?.name })
                values[.job] = unique(items.compactMap { $0.project?.job?.name })
                return Row(kind: .work, date: day, values: values, hours: hours)
            }
        } else {
            rows = sorted.map { entry in
                var end = format.time(entry.endTime)
                if DateDurationService.spansMidnight(start: entry.startTime, end: entry.endTime) { end += " (+1)" }
                let values: [ExportOptions.Column: String] = [
                    .date: dateValue(entry.date),
                    .weekday: format.weekday(entry.date),
                    .start: format.time(entry.startTime),
                    .end: end,
                    .breakTime: forCSV ? String(entry.breakMinutes) : format.breakText(entry.breakMinutes),
                    .duration: format.duration(entry.durationHours, forCSV: forCSV),
                    .decimalHours: format.decimal(entry.durationHours),
                    .description: entry.taskDescription,
                    .project: entry.project?.name ?? "",
                    .job: entry.project?.job?.name ?? ""
                ]
                return Row(kind: .work, date: entry.date, values: values, hours: entry.durationHours)
            }
        }

        if options.includeEmptyDays {
            let worked = Set(rows.map { calendar.startOfDay(for: $0.date) })
            var day = calendar.startOfDay(for: period.firstDay)
            var guardCount = 0
            while day < period.interval.end && guardCount < 400 {
                if !worked.contains(day) {
                    rows.append(Row(kind: .emptyDay, date: day, values: [
                        .date: dateValue(day),
                        .weekday: format.weekday(day),
                        .description: forCSV ? "" : labels.noWork
                    ], hours: 0))
                }
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? period.interval.end
                guardCount += 1
            }
            // Keep entries of one day in their original order.
            rows = rows.enumerated()
                .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
                .map(\.element)
        }

        if options.weeklySubtotals {
            var result: [Row] = []
            var currentWeek: DateComponents?
            var weekHours = 0.0
            var weekStart: Date?
            func flush() {
                guard let currentWeek, let weekStart else { return }
                let label = "\(labels.week) \(currentWeek.weekOfYear ?? 0)"
                result.append(Row(kind: .weekSubtotal, date: weekStart, values: [
                    .duration: format.duration(weekHours, forCSV: forCSV),
                    .decimalHours: format.decimal(weekHours)
                ], hours: weekHours, label: label))
            }
            for row in rows {
                let week = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: row.date)
                if week != currentWeek {
                    flush()
                    currentWeek = week
                    weekHours = 0
                    weekStart = row.date
                }
                weekHours += row.hours
                result.append(row)
            }
            flush()
            rows = result
        }
        return rows
    }

    // MARK: - Planning the files

    /// Projects that the options export within `period`.
    static func projects(for options: ExportOptions, from all: [Project], period: ExportService.ExportPeriod) -> [Project] {
        let candidates = options.projectScope == .chosen
            ? all.filter { options.projectIDs.contains($0.id) }
            : all
        return candidates.filter { project in
            let hasHours = project.entries.contains { period.contains($0.date) }
            // A chosen project can still produce an (empty) sheet when empty days are listed.
            return hasHours || (options.projectScope == .chosen && options.includeEmptyDays)
        }
    }

    static func documents(
        options: ExportOptions,
        projects all: [Project],
        settings: TimesheetSettings = .current,
        signature: ExportService.SignatureStamp?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Document] {
        let period = options.period(now: now, calendar: calendar)
        let chosen = projects(for: options, from: all, period: period)
        guard !chosen.isEmpty else { return [] }
        let format = Formatter(language: options.language, calendar: calendar)
        let slug = format.periodSlug(period)
        let ext = options.format == .pdf ? "pdf" : "csv"

        var docs: [Document] = []
        if options.grouping == .combined {
            let entries = chosen.flatMap { $0.entries.filter { period.contains($0.date) } }
            let base = options.title.trimmingCharacters(in: .whitespaces).isEmpty ? Labels(language: options.language).title : options.title
            let filename = "\(base.replacingOccurrences(of: " ", with: "_"))_\(slug).\(ext)"
            let data = options.format == .pdf
                ? pdf(options: options, entries: entries, projects: chosen, period: period, settings: settings, signature: signature, generatedAt: now, calendar: calendar)
                : Data(csv(options: options, entries: entries, projects: chosen, period: period, calendar: calendar).utf8)
            docs.append(Document(filename: filename, data: data))
        } else {
            for project in chosen {
                let entries = project.entries.filter { period.contains($0.date) }
                let filename = "\(project.name.replacingOccurrences(of: " ", with: "_"))_\(slug).\(ext)"
                let data = options.format == .pdf
                    ? pdf(options: options, entries: entries, projects: [project], period: period, settings: settings, signature: signature, generatedAt: now, calendar: calendar)
                    : Data(csv(options: options, entries: entries, projects: [project], period: period, calendar: calendar).utf8)
                docs.append(Document(filename: filename, data: data))
            }
        }
        let names = ExportService.uniqueFilenames(docs.map(\.filename))
        return zip(docs, names).map { Document(filename: $1, data: $0.data) }
    }

    /// Writes the documents for sharing.
    static func exportURLs(
        options: ExportOptions,
        projects: [Project],
        signature: ExportService.SignatureStamp?,
        now: Date = .now
    ) -> [URL]? {
        let docs = documents(options: options, projects: projects, signature: signature, now: now)
        guard !docs.isEmpty else { return nil }
        return ExportService.writeExportFiles(docs.map { (data: $0.data, filename: $0.filename) })
    }

    // MARK: - CSV

    static func csv(
        options: ExportOptions,
        entries: [WorkEntry],
        projects: [Project],
        period: ExportService.ExportPeriod,
        calendar: Calendar = .current
    ) -> String {
        let format = Formatter(language: options.language, calendar: calendar)
        let labels = Labels(language: options.language)
        let separator = format.csvSeparator
        let columns = options.columns.isEmpty ? ExportOptions.defaultColumns : options.columns
        func line(_ fields: [String]) -> String {
            fields.map { ExportService.csvEscape($0, separator: separator) }.joined(separator: separator)
        }
        var lines = [line(columns.map { column in
            column == .breakTime ? "\(labels.column(column)) (min)" : labels.column(column)
        })]
        let tableRows = rows(entries: entries, period: period, options: options, format: format, labels: labels, forCSV: true)
        for row in tableRows {
            if row.kind == .weekSubtotal {
                lines.append(line(columns.enumerated().map { index, column in
                    if index == 0 { return row.label }
                    return row.values[column] ?? ""
                }))
            } else {
                lines.append(line(columns.map { row.values[$0] ?? "" }))
            }
        }
        if options.showTotal {
            let total = tableRows.filter { $0.kind == .work }.reduce(0) { $0 + $1.hours }
            lines.append(line(columns.enumerated().map { index, column in
                if index == 0 { return labels.total }
                switch column {
                case .duration: return format.duration(total, forCSV: true)
                case .decimalHours: return format.decimal(total)
                default: return ""
                }
            }))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: - PDF

    static func pdf(
        options: ExportOptions,
        entries: [WorkEntry],
        projects: [Project],
        period: ExportService.ExportPeriod,
        settings: TimesheetSettings = .current,
        signature: ExportService.SignatureStamp?,
        generatedAt: Date = .now,
        calendar: Calendar = .current
    ) -> Data {
        let format = Formatter(language: options.language, calendar: calendar)
        let labels = Labels(language: options.language)
        let tableRows = rows(entries: entries, period: period, options: options, format: format, labels: labels)
        let workRows = tableRows.filter { $0.kind == .work }
        let totalHours = workRows.reduce(0) { $0 + $1.hours }
        let daysWorked = Set(workRows.map { calendar.startOfDay(for: $0.date) }).count

        let landscape = options.orientation == .landscape
        let pageWidth: CGFloat = landscape ? 841.8 : 595.2
        let pageHeight: CGFloat = landscape ? 595.2 : 841.8
        let margin: CGFloat = 40
        let footerHeight: CGFloat = 20
        let contentWidth = pageWidth - margin * 2
        let contentBottom = pageHeight - margin - footerHeight
        let rowPadding: CGFloat = 4
        let tableHeaderHeight: CGFloat = 22

        let ink = UIColor(red: 0.07, green: 0.10, blue: 0.18, alpha: 1)
        let muted = UIColor.darkGray
        let titleFont = UIFont.boldSystemFont(ofSize: 20)
        let labelFont = UIFont.systemFont(ofSize: 10)
        let valueFont = UIFont.boldSystemFont(ofSize: 10.5)
        let headerFont = UIFont.boldSystemFont(ofSize: 9.5)
        let bodyFont = UIFont.systemFont(ofSize: 9.5)
        let boldBodyFont = UIFont.boldSystemFont(ofSize: 9.5)
        let smallFont = UIFont.systemFont(ofSize: 8.5)
        let totalFont = UIFont.boldSystemFont(ofSize: 13)

        // Column widths: fixed columns by weight, the description takes the rest.
        let columns = options.columns.isEmpty ? ExportOptions.defaultColumns : options.columns
        let fixedWeight = columns.filter { $0 != .description }.reduce(0) { $0 + $1.weight }
        var widths: [ExportOptions.Column: CGFloat] = [:]
        if columns.contains(.description) {
            let descriptionShare = max(0.22, 1 - fixedWeight)
            let scale = (1 - descriptionShare) / max(fixedWeight, 0.0001)
            for column in columns where column != .description { widths[column] = contentWidth * CGFloat(column.weight * scale) }
            widths[.description] = contentWidth * CGFloat(descriptionShare)
        } else {
            for column in columns { widths[column] = contentWidth * CGFloat(column.weight / max(fixedWeight, 0.0001)) }
        }

        func attributes(_ font: UIFont, _ color: UIColor = ink, alignment: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
            let style = NSMutableParagraphStyle()
            style.alignment = alignment
            style.lineBreakMode = .byWordWrapping
            return [.font: font, .foregroundColor: color, .paragraphStyle: style]
        }

        func textHeight(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
            ceil((text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            ).height)
        }

        let maxRowHeight = contentBottom - margin - 60
        let rowHeights: [CGFloat] = tableRows.map { row in
            var height: CGFloat = 13
            for column in columns where column.wraps {
                height = max(height, textHeight(row.values[column] ?? "", width: (widths[column] ?? 0) - 6, font: bodyFont))
            }
            return min(height + rowPadding * 2, maxRowHeight)
        }

        // Header text
        let title = options.title.trimmingCharacters(in: .whitespaces).isEmpty ? labels.title : options.title
        var info: [(String, String)] = []
        if options.showName, !settings.signerName.isEmpty { info.append((labels.name, settings.signerName)) }
        if options.showOrganization, !settings.organization.isEmpty { info.append((labels.organization, settings.organization)) }
        if options.showJobAndProject, !projects.isEmpty {
            let text = projects.count == 1
                ? [projects[0].job?.name, projects[0].name].compactMap { $0 }.joined(separator: " · ")
                : projects.map { "\($0.name) (\($0.job?.name ?? ""))" }.joined(separator: ", ")
            info.append((labels.jobProject, text))
        }
        if options.showPeriod { info.append((labels.period, format.periodLabel(period))) }
        let continuationText = [title, settings.signerName, format.periodLabel(period)].filter { !$0.isEmpty }.joined(separator: " · ")

        func divider(_ y: CGFloat, alpha: CGFloat = 0.25, width: CGFloat = 0.5) {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: y))
            path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
            ink.withAlphaComponent(alpha).setStroke()
            path.lineWidth = width
            path.stroke()
        }

        func drawFirstHeader() -> CGFloat {
            var y = margin
            (title as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: attributes(titleFont))
            y += 30
            let labelWidth: CGFloat = 92
            for (label, value) in info {
                (label as NSString).draw(in: CGRect(x: margin, y: y, width: labelWidth, height: 14), withAttributes: attributes(labelFont, muted))
                let height = max(14, textHeight(value, width: contentWidth - labelWidth, font: valueFont))
                (value as NSString).draw(in: CGRect(x: margin + labelWidth, y: y, width: contentWidth - labelWidth, height: height), withAttributes: attributes(valueFont))
                y += height + 3
            }
            let note = options.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                y += 4
                let height = textHeight(note, width: contentWidth, font: labelFont)
                (note as NSString).draw(in: CGRect(x: margin, y: y, width: contentWidth, height: height), withAttributes: attributes(labelFont, muted))
                y += height
            }
            y += 8
            divider(y, alpha: 0.6, width: 1)
            return y + 10
        }

        func drawContinuationHeader() -> CGFloat {
            (continuationText as NSString).draw(in: CGRect(x: margin, y: margin, width: contentWidth, height: 14), withAttributes: attributes(smallFont, muted))
            return margin + 22
        }

        func drawTableHeader(_ y: CGFloat) -> CGFloat {
            var x = margin
            for column in columns {
                let width = widths[column] ?? 0
                (labels.column(column) as NSString).draw(
                    in: CGRect(x: x + 3, y: y, width: width - 6, height: 14),
                    withAttributes: attributes(headerFont, ink, alignment: column.isNumeric ? .right : .left)
                )
                x += width
            }
            divider(y + 16, alpha: 0.6)
            return y + tableHeaderHeight
        }

        func drawFooter(page: Int, total: Int?) {
            let y = pageHeight - margin
            if options.showGeneratedDate {
                ("\(labels.generated) \(format.date(generatedAt))" as NSString).draw(
                    in: CGRect(x: margin, y: y, width: contentWidth / 2, height: 12), withAttributes: attributes(smallFont, .gray))
            }
            if options.showPageNumbers {
                (labels.page(page, of: total) as NSString).draw(
                    in: CGRect(x: margin + contentWidth / 2, y: y, width: contentWidth / 2, height: 12),
                    withAttributes: attributes(smallFont, .gray, alignment: .right))
            }
        }

        func drawRow(_ row: Row, height: CGFloat, y: CGFloat, shaded: Bool) {
            if row.kind == .weekSubtotal {
                UIColor(red: 0.83, green: 0.69, blue: 0.22, alpha: 0.12).setFill()
                UIBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: height)).fill()
            } else if shaded {
                UIColor(white: 0, alpha: 0.03).setFill()
                UIBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: height)).fill()
            }
            var x = margin
            for (index, column) in columns.enumerated() {
                let width = widths[column] ?? 0
                var text = row.values[column] ?? ""
                var font = bodyFont
                var color = ink
                switch row.kind {
                case .weekSubtotal:
                    font = boldBodyFont
                    if index == 0 {
                        text = row.label
                        if !columns.contains(.duration) && !columns.contains(.decimalHours) {
                            text += ": \(format.duration(row.hours))"
                        }
                    }
                case .emptyDay:
                    color = .gray
                case .work:
                    break
                }
                (text as NSString).draw(
                    in: CGRect(x: x + 3, y: y + rowPadding, width: width - 6, height: height - rowPadding),
                    withAttributes: attributes(font, color, alignment: column.isNumeric ? .right : .left)
                )
                x += width
            }
        }

        func drawSignatureLine(x: CGFloat, y: CGFloat, width: CGFloat, label: String) {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + width, y: y))
            ink.setStroke()
            path.lineWidth = 0.75
            path.stroke()
            (label as NSString).draw(in: CGRect(x: x, y: y + 4, width: width, height: 14), withAttributes: attributes(smallFont, muted))
        }

        func drawStamp(_ stamp: ExportService.SignatureStamp, lineX: CGFloat, lineY: CGFloat, width: CGFloat) {
            let dateAttributes = attributes(bodyFont)
            let dateSize = (stamp.dateText as NSString).size(withAttributes: dateAttributes)
            let dateX = lineX + width - dateSize.width
            (stamp.dateText as NSString).draw(at: CGPoint(x: dateX, y: lineY - dateSize.height - 3), withAttributes: dateAttributes)
            guard let image = stamp.image, image.size.width > 0, image.size.height > 0 else { return }
            let maxWidth = max(40, dateX - lineX - 10)
            let scale = min(maxWidth / image.size.width, 46 / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: lineX, y: lineY - size.height + 4, width: size.width, height: size.height))
        }

        // Summary lines: hours and minutes, plus decimal hours only when that column is shown.
        func hoursText(_ hours: Double) -> String {
            let text = format.duration(hours)
            return columns.contains(.decimalHours) ? "\(text) (\(format.decimal(hours)) h)" : text
        }
        var summary: [(String, UIFont)] = []
        if options.showTotal {
            summary.append(("\(labels.total): \(hoursText(totalHours))", totalFont))
        }
        if options.showDaysWorked {
            summary.append(("\(labels.daysWorked): \(daysWorked)", valueFont))
        }
        if options.showProjectTotals, projects.count > 1 {
            for project in projects {
                let hours = entries.filter { $0.project?.id == project.id && period.contains($0.date) }.reduce(0) { $0 + $1.durationHours }
                summary.append(("\(project.name): \(hoursText(hours))", labelFont))
            }
        }

        func render(totalPages: Int?) -> (data: Data, pages: Int) {
            var pages = 0
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
            let data = renderer.pdfData { context in
                func newPage(first: Bool) -> CGFloat {
                    context.beginPage()
                    pages += 1
                    drawFooter(page: pages, total: totalPages)
                    return first ? drawFirstHeader() : drawContinuationHeader()
                }
                var y = newPage(first: true)
                y = drawTableHeader(y)
                var shaded = false
                for (row, height) in zip(tableRows, rowHeights) {
                    if y + height > contentBottom {
                        y = newPage(first: false)
                        y = drawTableHeader(y)
                    }
                    drawRow(row, height: height, y: y, shaded: shaded && row.kind != .weekSubtotal)
                    if row.kind != .weekSubtotal { shaded.toggle() }
                    y += height
                }

                if !summary.isEmpty {
                    let blockHeight = CGFloat(summary.count) * 18 + 16
                    if y + blockHeight > contentBottom { y = newPage(first: false) }
                    divider(y + 2, alpha: 0.6)
                    y += 12
                    for (text, font) in summary {
                        (text as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: attributes(font))
                        y += font.lineHeight + 4
                    }
                }

                if options.employeeSignatureLine || options.supervisorSignatureLine {
                    if y + 84 > contentBottom { y = newPage(first: false) }
                    let lineY = y + 58
                    let both = options.employeeSignatureLine && options.supervisorSignatureLine
                    let width = both ? (contentWidth - 30) / 2 : min(contentWidth, 260)
                    var x = margin
                    if options.employeeSignatureLine {
                        if let signature { drawStamp(signature, lineX: x, lineY: lineY, width: width) }
                        drawSignatureLine(x: x, y: lineY, width: width, label: labels.employeeSignature(name: settings.signerName))
                        x += width + 30
                    }
                    if options.supervisorSignatureLine {
                        drawSignatureLine(x: x, y: lineY, width: width, label: labels.supervisorSignature)
                    }
                }
            }
            return (data, pages)
        }

        let first = render(totalPages: nil)
        return options.showPageNumbers ? render(totalPages: first.pages).data : first.data
    }
}
