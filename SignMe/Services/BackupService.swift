import Foundation
import SwiftData

/// The stable, portable representation of app data used for JSON backup/import.
/// Intentionally decoupled from the SwiftData models so the file format never
/// breaks if the models evolve. Every field added after the first release is
/// optional, so older backup files keep importing.
struct BackupEntryDTO: Codable {
    var id: UUID?
    var date: Date
    var startTime: Date
    var endTime: Date
    var breakMinutes: Int?
    var durationHours: Double?
    var taskDescription: String
    var createdAt: Date?
    var updatedAt: Date?
}

struct BackupProjectDTO: Codable {
    var id: UUID?
    var name: String
    var createdAt: Date?
    var entries: [BackupEntryDTO]
}

struct BackupJobDTO: Codable {
    var id: UUID?
    var name: String
    var createdAt: Date?
    var projects: [BackupProjectDTO]
}

/// Top-level backup file. Version 1 introduced this wrapper; files written by
/// earlier builds are a bare `[BackupJobDTO]` array and are still accepted.
struct BackupFile: Codable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var exportedAt: Date
    var jobs: [BackupJobDTO]
}

enum BackupError: LocalizedError {
    case decodingFailed
    case encodingFailed
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .decodingFailed:
            return "This file doesn't look like a valid SignMe backup."
        case .encodingFailed:
            return "Could not prepare your data for backup."
        case .unsupportedVersion(let version):
            return "This backup was made by a newer version of SignMe (format \(version)). Update the app, then try again."
        }
    }
}

struct ImportSummary {
    var newJobs: Int
    var newProjects: Int
    var newEntries: Int
    var skippedDuplicates: Int

    var isEmpty: Bool {
        newJobs == 0 && newProjects == 0 && newEntries == 0 && skippedDuplicates == 0
    }

    var message: String {
        if newJobs == 0 && newProjects == 0 && newEntries == 0 {
            return "Nothing new to import — your data is already up to date."
        }
        return "Added \(newJobs) job(s), \(newProjects) project(s), and \(newEntries) entr\(newEntries == 1 ? "y" : "ies"). Skipped \(skippedDuplicates) duplicate(s)."
    }
}

enum BackupService {

    // MARK: - Export

    static func exportData(jobs: [Job], exportedAt: Date = .now) throws -> Data {
        let dtos = jobs.map { job in
            BackupJobDTO(
                id: job.id,
                name: job.name,
                createdAt: job.createdAt,
                projects: job.projects.map { project in
                    BackupProjectDTO(
                        id: project.id,
                        name: project.name,
                        createdAt: project.createdAt,
                        entries: project.entries.sorted { $0.startTime < $1.startTime }.map { entry in
                            BackupEntryDTO(
                                id: entry.id,
                                date: entry.date,
                                startTime: entry.startTime,
                                endTime: entry.endTime,
                                breakMinutes: entry.breakMinutes,
                                durationHours: entry.durationHours,
                                taskDescription: entry.taskDescription,
                                createdAt: entry.createdAt,
                                updatedAt: entry.updatedAt
                            )
                        }
                    )
                }
            )
        }

        let file = BackupFile(formatVersion: BackupFile.currentFormatVersion, exportedAt: exportedAt, jobs: dtos)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(file)
        } catch {
            throw BackupError.encodingFailed
        }
    }

    // MARK: - Decode

    /// Reads either the current wrapped format or the legacy bare-array format.
    static func decodeJobs(from data: Data) throws -> [BackupJobDTO] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let file = try? decoder.decode(BackupFile.self, from: data) {
            guard file.formatVersion <= BackupFile.currentFormatVersion else {
                throw BackupError.unsupportedVersion(file.formatVersion)
            }
            return file.jobs
        }
        if let legacy = try? decoder.decode([BackupJobDTO].self, from: data) {
            return legacy
        }
        throw BackupError.decodingFailed
    }

    // MARK: - Import & merge

    /// Merges the backup file into existing data:
    /// - Jobs are matched (case-insensitively) by name, or created if new.
    /// - Projects are matched by name within their job, or created if new.
    /// - Entries are skipped if the same entry (by id) already exists anywhere,
    ///   or if an equivalent entry already exists in the destination project.
    /// - Original ids and creation dates are restored when they don't clash.
    /// Existing data is never overwritten. Duplicate names already in the store
    /// are tolerated (the first match wins) instead of crashing.
    @discardableResult
    static func importData(_ data: Data, into context: ModelContext, existingJobs: [Job]) throws -> ImportSummary {
        let jobDTOs = try decodeJobs(from: data)

        var jobsByName = Dictionary(
            existingJobs.map { ($0.name.normalizedNameKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var knownJobIDs = Set(existingJobs.map(\.id))
        var knownProjectIDs = Set(existingJobs.flatMap { $0.projects.map(\.id) })
        var knownEntryIDs = Set(existingJobs.flatMap { $0.projects.flatMap { $0.entries.map(\.id) } })

        var newJobs = 0, newProjects = 0, newEntries = 0, skipped = 0

        for jobDTO in jobDTOs {
            let jobName = displayName(jobDTO.name, fallback: "Untitled Job")
            let job: Job
            if let existing = jobsByName[jobName.normalizedNameKey] {
                job = existing
            } else {
                let id = unusedID(jobDTO.id, known: knownJobIDs)
                job = Job(id: id, name: jobName, createdAt: jobDTO.createdAt ?? .now)
                context.insert(job)
                jobsByName[jobName.normalizedNameKey] = job
                knownJobIDs.insert(id)
                newJobs += 1
            }

            var projectsByName = Dictionary(
                job.projects.map { ($0.name.normalizedNameKey, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            for projectDTO in jobDTO.projects {
                let projectName = displayName(projectDTO.name, fallback: "Untitled Project")
                let project: Project
                if let existing = projectsByName[projectName.normalizedNameKey] {
                    project = existing
                } else {
                    let id = unusedID(projectDTO.id, known: knownProjectIDs)
                    project = Project(id: id, name: projectName, createdAt: projectDTO.createdAt ?? .now)
                    context.insert(project)
                    job.projects.append(project)
                    projectsByName[projectName.normalizedNameKey] = project
                    knownProjectIDs.insert(id)
                    newProjects += 1
                }

                for entryDTO in projectDTO.entries {
                    if let id = entryDTO.id, knownEntryIDs.contains(id) {
                        skipped += 1
                        continue
                    }
                    if isDuplicate(entryDTO, in: project) {
                        skipped += 1
                        continue
                    }
                    let entry = WorkEntry(
                        id: entryDTO.id ?? UUID(),
                        date: entryDTO.date,
                        startTime: entryDTO.startTime,
                        endTime: entryDTO.endTime,
                        breakMinutes: max(0, entryDTO.breakMinutes ?? 0),
                        taskDescription: entryDTO.taskDescription,
                        createdAt: entryDTO.createdAt ?? .now,
                        updatedAt: entryDTO.updatedAt ?? .now
                    )
                    context.insert(entry)
                    project.entries.append(entry)
                    knownEntryIDs.insert(entry.id)
                    newEntries += 1
                }
            }
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return ImportSummary(newJobs: newJobs, newProjects: newProjects, newEntries: newEntries, skippedDuplicates: skipped)
    }

    // MARK: - Helpers

    private static func displayName(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func unusedID(_ candidate: UUID?, known: Set<UUID>) -> UUID {
        if let candidate, !known.contains(candidate) { return candidate }
        return UUID()
    }

    private static func isDuplicate(_ dto: BackupEntryDTO, in project: Project) -> Bool {
        let calendar = Calendar.current
        let dtoDuration = DateDurationService.durationHours(
            from: dto.startTime,
            to: dto.endTime,
            breakMinutes: dto.breakMinutes ?? 0
        )
        return project.entries.contains { entry in
            calendar.isDate(entry.date, inSameDayAs: dto.date) &&
            abs(entry.startTime.timeIntervalSince(dto.startTime)) < 60 &&
            abs(entry.endTime.timeIntervalSince(dto.endTime)) < 60 &&
            abs(entry.durationHours - dtoDuration) < 0.01 &&
            entry.taskDescription == dto.taskDescription
        }
    }
}
