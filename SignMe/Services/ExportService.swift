import Foundation
import UIKit

/// Builds CSV, JSON, and PDF exports and hands back a temp file URL ready for `ShareLink`.
enum ExportService {

    // MARK: - CSV

    static func csv(for entries: [WorkEntry]) -> String {
        var lines = ["Job,Project,Date,Start Time,End Time,Duration Hours,Duration Text,Task Description"]

        for entry in entries.sorted(by: { $0.date > $1.date }) {
            let job = entry.project?.job?.name ?? ""
            let project = entry.project?.name ?? ""
            let date = DateDurationService.dateFormatter.string(from: entry.date)
            let start = DateDurationService.timeFormatter.string(from: entry.startTime)
            let end = DateDurationService.timeFormatter.string(from: entry.endTime)
            let durationHours = String(format: "%.2f", entry.durationHours)
            let durationText = DateDurationService.formattedDuration(hours: entry.durationHours)

            let fields = [job, project, date, start, end, durationHours, durationText, entry.taskDescription]
                .map(csvEscape)
            lines.append(fields.joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    private static func csvEscape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: - File helpers

    static func allEntries(in jobs: [Job]) -> [WorkEntry] {
        jobs.flatMap { $0.projects.flatMap(\.entries) }
    }

    static func writeTempFile(data: Data, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Writes a fresh JSON backup of every job/project/entry and returns a shareable file URL.
    static func backupExportURL(jobs: [Job]) -> URL? {
        guard let data = try? BackupService.exportData(jobs: jobs) else { return nil }
        return writeTempFile(data: data, filename: "SignMe-Backup-\(timestamp()).json")
    }

    /// Writes a CSV of the given entries and returns a shareable file URL.
    static func csvExportURL(entries: [WorkEntry], filenamePrefix: String = "SignMe-Export") -> URL? {
        let data = Data(csv(for: entries).utf8)
        let safePrefix = filenamePrefix.replacingOccurrences(of: "/", with: "-")
        return writeTempFile(data: data, filename: "\(safePrefix)-\(timestamp()).csv")
    }

    /// Renders a formatted PDF of one project's entries for a single month —
    /// a title block, a table of entries, and the total tracked hours as the
    /// last line of the document. Filename format: "ProjectName_Month_Year.pdf".
    static func monthExportPDFURL(job: Job, project: Project, monthDate: Date, entries: [WorkEntry]) -> URL? {
        let sortedEntries = entries.sorted { $0.date < $1.date }
        let totalHours = entries.reduce(0) { $0 + $1.durationHours }
        let monthLabel = DateDurationService.monthYearFormatter.string(from: monthDate)

        let pageWidth: CGFloat = 612   // US Letter, 72pt/inch
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 40
        let contentWidth = pageWidth - margin * 2
        let bottomLimit = pageHeight - margin

        let titleFont = UIFont.boldSystemFont(ofSize: 20)
        let subtitleFont = UIFont.systemFont(ofSize: 12)
        let headerFont = UIFont.boldSystemFont(ofSize: 10)
        let bodyFont = UIFont.systemFont(ofSize: 10)
        let totalFont = UIFont.boldSystemFont(ofSize: 14)

        let columns: [(title: String, width: CGFloat)] = [
            ("Date", contentWidth * 0.16),
            ("Start", contentWidth * 0.11),
            ("End", contentWidth * 0.11),
            ("Duration", contentWidth * 0.14),
            ("Task Description", contentWidth * 0.48)
        ]

        func drawDivider(at y: CGFloat) {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: y))
            path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
            UIColor.black.withAlphaComponent(0.2).setStroke()
            path.lineWidth = 0.5
            path.stroke()
        }

        func drawTableHeader(startingAt y: CGFloat) -> CGFloat {
            var y = y
            var x = margin
            for column in columns {
                (column.title as NSString).draw(
                    in: CGRect(x: x, y: y, width: column.width - 6, height: 14),
                    withAttributes: [.font: headerFont]
                )
                x += column.width
            }
            y += 16
            drawDivider(at: y)
            return y + 8
        }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        let data = renderer.pdfData { context in
            context.beginPage()
            var y = margin

            let signerName = "Eslam Sherif"
            (signerName as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: titleFont])
            y += 26

            let subtitle = "\(project.name) · \(monthLabel)"
            (subtitle as NSString).draw(
                at: CGPoint(x: margin, y: y),
                withAttributes: [.font: subtitleFont, .foregroundColor: UIColor.darkGray]
            )
            y += 20
            drawDivider(at: y)
            y += 14

            y = drawTableHeader(startingAt: y)

            for entry in sortedEntries {
                let values = [
                    DateDurationService.dateFormatter.string(from: entry.date),
                    DateDurationService.timeFormatter.string(from: entry.startTime),
                    DateDurationService.timeFormatter.string(from: entry.endTime),
                    DateDurationService.formattedDuration(hours: entry.durationHours),
                    entry.taskDescription
                ]

                let taskBounds = (values[4] as NSString).boundingRect(
                    with: CGSize(width: columns[4].width - 6, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin],
                    attributes: [.font: bodyFont],
                    context: nil
                )
                let rowHeight = max(16, ceil(taskBounds.height) + 4)

                if y + rowHeight > bottomLimit - 40 {
                    context.beginPage()
                    y = margin
                    y = drawTableHeader(startingAt: y)
                }

                var x = margin
                for (index, column) in columns.enumerated() {
                    (values[index] as NSString).draw(
                        in: CGRect(x: x, y: y, width: column.width - 6, height: rowHeight),
                        withAttributes: [.font: bodyFont]
                    )
                    x += column.width
                }
                y += rowHeight + 6
            }

            if y + 40 > bottomLimit {
                context.beginPage()
                y = margin
            } else {
                y += 8
                drawDivider(at: y)
                y += 14
            }

            let totalText = "Total Hours: \(DateDurationService.formattedDuration(hours: totalHours))"
            (totalText as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: totalFont])
            y += 20

            if y + 60 > bottomLimit {
                context.beginPage()
                y = margin
            } else {
                y += 40
            }

            let signatureLineY = y + 30
            let signaturePath = UIBezierPath()
            signaturePath.move(to: CGPoint(x: margin, y: signatureLineY))
            signaturePath.addLine(to: CGPoint(x: margin + 220, y: signatureLineY))
            UIColor.black.setStroke()
            signaturePath.lineWidth = 0.75
            signaturePath.stroke()

            ("Signature" as NSString).draw(
                at: CGPoint(x: margin, y: signatureLineY + 4),
                withAttributes: [.font: subtitleFont, .foregroundColor: UIColor.darkGray]
            )
        }

        let monthName = DateDurationService.monthNameFormatter.string(from: monthDate)
        let year = Calendar.current.component(.year, from: monthDate)
        let safeProject = project.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        let filename = "\(safeProject)_\(monthName)_\(year).pdf"

        return writeTempFile(data: data, filename: filename)
    }

    private static func timestamp() -> Int {
        Int(Date().timeIntervalSince1970)
    }
}
