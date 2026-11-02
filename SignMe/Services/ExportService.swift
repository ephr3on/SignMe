import Foundation
import UIKit

/// Builds CSV, JSON, and PDF exports and writes them to a temp file ready for the share sheet.
/// Exports are generated on demand (when the user taps an export button), never during rendering.
enum ExportService {

    // MARK: - CSV

    /// Spreadsheet apps in comma-decimal locales (e.g. German Excel) expect ";" between fields.
    static func csvSeparator(for locale: Locale) -> String {
        (locale.decimalSeparator ?? ".") == "," ? ";" : ","
    }

    /// A spreadsheet-friendly CSV: ISO dates (yyyy-MM-dd), 24-hour times, locale-aware
    /// decimal hours and separator, CRLF line endings, and a UTF-8 BOM so Excel reads umlauts correctly.
    static func csv(for entries: [WorkEntry], locale: Locale = .current) -> String {
        let separator = csvSeparator(for: locale)
        let header = ["Job", "Project", "Date", "Start", "End Date", "End", "Break (min)", "Hours", "Duration", "Task Description"]
        var lines = [header.map { csvEscape($0, separator: separator) }.joined(separator: separator)]

        for entry in entries.sorted(by: { $0.startTime < $1.startTime }) {
            let fields = [
                entry.project?.job?.name ?? "",
                entry.project?.name ?? "",
                DateDurationService.isoDateFormatter.string(from: entry.date),
                DateDurationService.isoTimeFormatter.string(from: entry.startTime),
                DateDurationService.isoDateFormatter.string(from: entry.endTime),
                DateDurationService.isoTimeFormatter.string(from: entry.endTime),
                String(entry.breakMinutes),
                DateDurationService.formattedDecimalHours(entry.durationHours, locale: locale),
                DateDurationService.formattedDuration(hours: entry.durationHours),
                entry.taskDescription
            ]
            lines.append(fields.map { csvEscape($0, separator: separator) }.joined(separator: separator))
        }

        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    static func csvEscape(_ field: String, separator: String = ",") -> String {
        let needsQuoting = field.contains(separator)
            || field.contains("\"")
            || field.contains("\n")
            || field.contains("\r")
        guard needsQuoting else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: - File helpers

    static func allEntries(in jobs: [Job]) -> [WorkEntry] {
        jobs.flatMap { $0.projects.flatMap(\.entries) }
    }

    private static var exportDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
    }

    /// Writes `data` into the app's temp export folder and returns its URL.
    /// Only the most recent export is kept, so temp files never pile up.
    static func writeExportFile(data: Data, filename: String) -> URL? {
        writeExportFiles([(data: data, filename: filename)])?.first
    }

    /// Writes several files of one export together (the folder is cleared once,
    /// before the first file). Returns nil if any file can't be written.
    static func writeExportFiles(_ files: [(data: Data, filename: String)]) -> [URL]? {
        let fileManager = FileManager.default
        let directory = exportDirectory
        do {
            if fileManager.fileExists(atPath: directory.path) {
                try? fileManager.removeItem(at: directory)
            }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return try files.map { file in
                let url = directory.appendingPathComponent(sanitizedFilename(file.filename))
                try file.data.write(to: url, options: .atomic)
                return url
            }
        } catch {
            return nil
        }
    }

    /// Makes every filename in the list unique by adding " (2)", " (3)"… before the extension.
    static func uniqueFilenames(_ names: [String]) -> [String] {
        var seen: [String: Int] = [:]
        return names.map { name in
            let key = name.lowercased()
            let count = (seen[key] ?? 0) + 1
            seen[key] = count
            guard count > 1 else { return name }
            let ext = (name as NSString).pathExtension
            let stem = (name as NSString).deletingPathExtension
            return ext.isEmpty ? "\(stem) (\(count))" : "\(stem) (\(count)).\(ext)"
        }
    }

    static func sanitizedFilename(_ filename: String) -> String {
        let cleaned = filename
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "SignMe-Export" : cleaned
    }

    /// Writes a fresh JSON backup of every job/project/entry and returns a shareable file URL.
    static func backupExportURL(jobs: [Job], signatures: [SavedSignature] = []) -> URL? {
        guard let data = try? BackupService.exportData(jobs: jobs, signatures: signatures) else { return nil }
        return writeExportFile(data: data, filename: "SignMe-Backup-\(timestamp()).json")
    }

    /// Writes a CSV of the given entries and returns a shareable file URL.
    static func csvExportURL(entries: [WorkEntry], filenamePrefix: String = "SignMe-Export") -> URL? {
        let data = Data(csv(for: entries).utf8)
        return writeExportFile(data: data, filename: "\(filenamePrefix)-\(timestamp()).csv")
    }

    // MARK: - PDF timesheet

    /// What goes on the employee's signature line: the drawn signature (optional) and the date beside it.
    struct SignatureStamp {
        var image: UIImage?
        var dateText: String
    }

    /// Writes the monthly PDF timesheet and returns a shareable file URL.
    /// Filename format: "ProjectName_Month_Year.pdf".
    static func monthExportPDFURL(
        job: Job,
        project: Project,
        monthDate: Date,
        entries: [WorkEntry],
        settings: TimesheetSettings = .current,
        signature: SignatureStamp? = nil
    ) -> URL? {
        let data = monthExportPDFData(
            job: job,
            project: project,
            monthDate: monthDate,
            entries: entries,
            settings: settings,
            signature: signature
        )

        return writeExportFile(data: data, filename: monthPDFFilename(project: project, monthDate: monthDate))
    }

    /// "ProjectName_Month_Year.pdf"
    static func monthPDFFilename(project: Project, monthDate: Date) -> String {
        let monthName = DateDurationService.monthNameFormatter.string(from: monthDate)
        let year = Calendar.current.component(.year, from: monthDate)
        let safeProject = project.name.replacingOccurrences(of: " ", with: "_")
        return "\(safeProject)_\(monthName)_\(year).pdf"
    }

    /// Entries of `project` that fall in the month of `monthDate`.
    static func entries(of project: Project, inMonthOf monthDate: Date, calendar: Calendar = .current) -> [WorkEntry] {
        project.entries.filter { calendar.isDate($0.date, equalTo: monthDate, toGranularity: .month) }
    }

    /// Writes one signed PDF timesheet per project for the same month, all in one go.
    /// Projects without entries that month are skipped. Each PDF carries its own
    /// signature and date. Same-named projects get " (2)"-style filenames.
    /// Returns nil if nothing could be exported.
    static func monthExportPDFURLs(
        projects: [Project],
        monthDate: Date,
        settings: TimesheetSettings = .current,
        signature: SignatureStamp? = nil
    ) -> [URL]? {
        periodExportPDFURLs(projects: projects, period: .month(monthDate), settings: settings, signature: signature)
    }

    /// A span of time to export: a whole month, or any range of days.
    struct ExportPeriod: Equatable {
        /// Start of the first day ..< start of the day after the last day.
        let interval: DateInterval
        let isWholeMonth: Bool

        static func month(_ date: Date, calendar: Calendar = .current) -> ExportPeriod {
            let interval = calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 0)
            return ExportPeriod(interval: interval, isWholeMonth: true)
        }

        /// All days from `first` through `last` (inclusive, in either order).
        static func days(_ first: Date, _ last: Date, calendar: Calendar = .current) -> ExportPeriod {
            let a = calendar.startOfDay(for: min(first, last))
            let b = calendar.startOfDay(for: max(first, last))
            let end = calendar.date(byAdding: .day, value: 1, to: b) ?? b
            let interval = DateInterval(start: a, end: end)
            if let month = calendar.dateInterval(of: .month, for: a), month == interval {
                return ExportPeriod(interval: interval, isWholeMonth: true)
            }
            return ExportPeriod(interval: interval, isWholeMonth: false)
        }

        var firstDay: Date { interval.start }
        var lastDay: Date { interval.end.addingTimeInterval(-1) }

        func contains(_ date: Date) -> Bool {
            date >= interval.start && date < interval.end
        }

        /// "October 2026", "5 Oct 2026", or "5 Oct – 11 Oct 2026".
        var label: String {
            if isWholeMonth { return DateDurationService.monthYearFormatter.string(from: firstDay) }
            let calendar = Calendar.current
            if calendar.isDate(firstDay, inSameDayAs: lastDay) {
                return firstDay.formatted(.dateTime.day().month(.abbreviated).year())
            }
            let sameYear = calendar.isDate(firstDay, equalTo: lastDay, toGranularity: .year)
            let start = sameYear
                ? firstDay.formatted(.dateTime.day().month(.abbreviated))
                : firstDay.formatted(.dateTime.day().month(.abbreviated).year())
            return "\(start) – \(lastDay.formatted(.dateTime.day().month(.abbreviated).year()))"
        }

        /// "Project_October_2026.pdf" or "Project_2026-10-05_to_2026-10-11.pdf".
        func pdfFilename(for project: Project) -> String {
            if isWholeMonth { return ExportService.monthPDFFilename(project: project, monthDate: firstDay) }
            let safeProject = project.name.replacingOccurrences(of: " ", with: "_")
            let start = DateDurationService.isoDateFormatter.string(from: firstDay)
            let end = DateDurationService.isoDateFormatter.string(from: lastDay)
            return start == end ? "\(safeProject)_\(start).pdf" : "\(safeProject)_\(start)_to_\(end).pdf"
        }

        /// Prefix for CSV filenames, e.g. "SignMe_2026-10-05_to_2026-10-11".
        var csvPrefix: String {
            let start = DateDurationService.isoDateFormatter.string(from: firstDay)
            let end = DateDurationService.isoDateFormatter.string(from: lastDay)
            return start == end ? "SignMe_\(start)" : "SignMe_\(start)_to_\(end)"
        }
    }

    /// Entries of `project` within `period`.
    static func entries(of project: Project, in period: ExportPeriod) -> [WorkEntry] {
        project.entries.filter { period.contains($0.date) }
    }

    /// One signed PDF timesheet per project for any period, shared together.
    static func periodExportPDFURLs(
        projects: [Project],
        period: ExportPeriod,
        settings: TimesheetSettings = .current,
        signature: SignatureStamp? = nil
    ) -> [URL]? {
        let rendered: [(data: Data, filename: String)] = projects.compactMap { project -> (data: Data, filename: String)? in
            guard let job = project.job else { return nil }
            let periodEntries = ExportService.entries(of: project, in: period)
            guard !periodEntries.isEmpty else { return nil }
            let data = monthExportPDFData(
                job: job,
                project: project,
                monthDate: period.firstDay,
                entries: periodEntries,
                settings: settings,
                signature: signature,
                periodLabel: period.label
            )
            return (data: data, filename: period.pdfFilename(for: project))
        }
        guard !rendered.isEmpty else { return nil }
        let names = uniqueFilenames(rendered.map(\.filename))
        return writeExportFiles(zip(rendered, names).map { (data: $0.0.data, filename: $0.1) })
    }

    /// Renders an A4 PDF of one project's entries for a single month: a header with
    /// the signer's name, organization, job, project and month; a table of entries;
    /// the total in both "h m" and decimal hours; signature lines for the employee and
    /// (optionally) the supervisor; and "Page x of y" on every page.
    static func monthExportPDFData(
        job: Job,
        project: Project,
        monthDate: Date,
        entries: [WorkEntry],
        settings: TimesheetSettings = .current,
        signature: SignatureStamp? = nil,
        periodLabel: String? = nil,
        generatedAt: Date = .now
    ) -> Data {
        let sortedEntries = entries.sorted { $0.startTime < $1.startTime }
        let totalHours = entries.reduce(0) { $0 + $1.durationHours }
        let monthLabel = periodLabel ?? DateDurationService.monthYearFormatter.string(from: monthDate)
        let titleText = settings.signerName.isEmpty ? "Timesheet" : settings.signerName
        let subtitleText = "\(job.name) · \(project.name) · \(monthLabel)"

        // A4 at 72 pt/inch.
        let pageWidth: CGFloat = 595.2
        let pageHeight: CGFloat = 841.8
        let margin: CGFloat = 40
        let footerHeight: CGFloat = 20
        let contentWidth = pageWidth - margin * 2
        let contentBottom = pageHeight - margin - footerHeight
        let rowSpacing: CGFloat = 6
        let tableHeaderHeight: CGFloat = 24
        let continuationHeaderHeight: CGFloat = 24

        let titleFont = UIFont.boldSystemFont(ofSize: 20)
        let subtitleFont = UIFont.systemFont(ofSize: 12)
        let headerFont = UIFont.boldSystemFont(ofSize: 10)
        let bodyFont = UIFont.systemFont(ofSize: 10)
        let smallFont = UIFont.systemFont(ofSize: 9)
        let totalFont = UIFont.boldSystemFont(ofSize: 14)

        let columns: [(title: String, width: CGFloat)] = [
            ("Date", contentWidth * 0.16),
            ("Start", contentWidth * 0.10),
            ("End", contentWidth * 0.12),
            ("Break", contentWidth * 0.09),
            ("Hours", contentWidth * 0.09),
            ("Task Description", contentWidth * 0.44)
        ]
        let taskColumn = columns.count - 1

        // Pre-compute row contents and heights. A single row is never taller than
        // a full continuation page, so pagination always makes progress.
        let maxRowHeight = contentBottom - (margin + continuationHeaderHeight + tableHeaderHeight)
        let rows: [(values: [String], height: CGFloat)] = sortedEntries.map { entry -> (values: [String], height: CGFloat) in
            var endText = DateDurationService.timeFormatter.string(from: entry.endTime)
            if DateDurationService.spansMidnight(start: entry.startTime, end: entry.endTime) {
                endText += " (+1)"
            }
            let values = [
                DateDurationService.dateFormatter.string(from: entry.date),
                DateDurationService.timeFormatter.string(from: entry.startTime),
                endText,
                entry.breakMinutes > 0 ? DateDurationService.formattedDuration(hours: Double(entry.breakMinutes) / 60) : "—",
                DateDurationService.formattedDecimalHours(entry.durationHours),
                entry.taskDescription
            ]
            let taskBounds = (entry.taskDescription as NSString).boundingRect(
                with: CGSize(width: columns[taskColumn].width - 6, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: bodyFont],
                context: nil
            )
            let height = min(max(16, ceil(taskBounds.height) + 4), maxRowHeight)
            return (values, height)
        }

        func drawDivider(at y: CGFloat, alpha: CGFloat = 0.2) {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: y))
            path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
            UIColor.black.withAlphaComponent(alpha).setStroke()
            path.lineWidth = 0.5
            path.stroke()
        }

        func drawTableHeader(at y: CGFloat) -> CGFloat {
            var x = margin
            for column in columns {
                (column.title as NSString).draw(
                    in: CGRect(x: x, y: y, width: column.width - 6, height: 14),
                    withAttributes: [.font: headerFont]
                )
                x += column.width
            }
            drawDivider(at: y + 16)
            return y + tableHeaderHeight
        }

        func drawFirstPageHeader() -> CGFloat {
            var y = margin
            (titleText as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: titleFont])
            y += 26
            if !settings.organization.isEmpty {
                (settings.organization as NSString).draw(
                    at: CGPoint(x: margin, y: y),
                    withAttributes: [.font: subtitleFont, .foregroundColor: UIColor.darkGray]
                )
                y += 18
            }
            (subtitleText as NSString).draw(
                at: CGPoint(x: margin, y: y),
                withAttributes: [.font: subtitleFont, .foregroundColor: UIColor.darkGray]
            )
            y += 20
            drawDivider(at: y)
            return y + 14
        }

        func drawContinuationHeader() -> CGFloat {
            ("\(titleText) · \(subtitleText)" as NSString).draw(
                in: CGRect(x: margin, y: margin, width: contentWidth, height: 14),
                withAttributes: [.font: smallFont, .foregroundColor: UIColor.darkGray]
            )
            return margin + continuationHeaderHeight
        }

        func drawFooter(page: Int, totalPages: Int?) {
            let y = pageHeight - margin
            let attributes: [NSAttributedString.Key: Any] = [.font: smallFont, .foregroundColor: UIColor.gray]
            ("Generated \(DateDurationService.dateFormatter.string(from: generatedAt))" as NSString).draw(
                in: CGRect(x: margin, y: y, width: contentWidth / 2, height: 12),
                withAttributes: attributes
            )
            let pageText = totalPages.map { "Page \(page) of \($0)" } ?? "Page \(page)"
            let rightAligned = NSMutableParagraphStyle()
            rightAligned.alignment = .right
            var rightAttributes = attributes
            rightAttributes[.paragraphStyle] = rightAligned
            (pageText as NSString).draw(
                in: CGRect(x: margin + contentWidth / 2, y: y, width: contentWidth / 2, height: 12),
                withAttributes: rightAttributes
            )
        }

        func drawSignatureLine(x: CGFloat, y: CGFloat, width: CGFloat, label: String) {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + width, y: y))
            UIColor.black.setStroke()
            path.lineWidth = 0.75
            path.stroke()
            (label as NSString).draw(
                in: CGRect(x: x, y: y + 4, width: width, height: 14),
                withAttributes: [.font: smallFont, .foregroundColor: UIColor.darkGray]
            )
        }

        /// The signature image (left, sitting on the line) and its date (right), above the employee line.
        func drawStamp(_ stamp: SignatureStamp, lineX: CGFloat, lineY: CGFloat, width: CGFloat) {
            let dateAttributes: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: UIColor.black]
            let dateSize = (stamp.dateText as NSString).size(withAttributes: dateAttributes)
            let dateX = lineX + width - dateSize.width
            (stamp.dateText as NSString).draw(at: CGPoint(x: dateX, y: lineY - dateSize.height - 3), withAttributes: dateAttributes)

            guard let image = stamp.image, image.size.width > 0, image.size.height > 0 else { return }
            let maxWidth = max(40, dateX - lineX - 10)
            let maxHeight: CGFloat = 46
            let scale = min(maxWidth / image.size.width, maxHeight / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: lineX, y: lineY - size.height + 4, width: size.width, height: size.height))
        }

        /// Draws the whole document. Rendered twice: once to count pages, then
        /// again with the known total for the "Page x of y" footers.
        func render(totalPages: Int?) -> (data: Data, pageCount: Int) {
            var pageCount = 0
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
            let data = renderer.pdfData { context in
                func startPage(isFirst: Bool) -> CGFloat {
                    context.beginPage()
                    pageCount += 1
                    drawFooter(page: pageCount, totalPages: totalPages)
                    return isFirst ? drawFirstPageHeader() : drawContinuationHeader()
                }

                var y = startPage(isFirst: true)
                y = drawTableHeader(at: y)

                for row in rows {
                    if y + row.height > contentBottom {
                        y = startPage(isFirst: false)
                        y = drawTableHeader(at: y)
                    }
                    var x = margin
                    for (index, column) in columns.enumerated() {
                        (row.values[index] as NSString).draw(
                            in: CGRect(x: x, y: y, width: column.width - 6, height: row.height),
                            withAttributes: [.font: bodyFont]
                        )
                        x += column.width
                    }
                    y += row.height + rowSpacing
                }

                // Total
                let totalBlockHeight: CGFloat = 44
                if y + totalBlockHeight > contentBottom {
                    y = startPage(isFirst: false)
                }
                y += 4
                drawDivider(at: y)
                y += 12
                let totalText = "Total: \(DateDurationService.formattedDuration(hours: totalHours)) (\(DateDurationService.formattedDecimalHours(totalHours)) h)"
                (totalText as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: totalFont])
                y += 24

                // Signatures
                let signatureBlockHeight: CGFloat = 80
                if y + signatureBlockHeight > contentBottom {
                    y = startPage(isFirst: false)
                }
                let signatureY = y + 56
                let signatureWidth = (contentWidth - 30) / 2
                let employeeLabel = settings.signerName.isEmpty
                    ? "Date, signature (employee)"
                    : "Date, signature — \(settings.signerName)"
                if let signature {
                    drawStamp(signature, lineX: margin, lineY: signatureY, width: signatureWidth)
                }
                drawSignatureLine(x: margin, y: signatureY, width: signatureWidth, label: employeeLabel)
                if settings.includeSupervisorSignature {
                    drawSignatureLine(
                        x: margin + signatureWidth + 30,
                        y: signatureY,
                        width: signatureWidth,
                        label: "Date, signature (supervisor)"
                    )
                }
            }
            return (data, pageCount)
        }

        let layoutPass = render(totalPages: nil)
        return render(totalPages: layoutPass.pageCount).data
    }

    // MARK: - Helpers

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return formatter
    }()

    private static func timestamp(_ date: Date = .now) -> String {
        timestampFormatter.string(from: date)
    }
}
