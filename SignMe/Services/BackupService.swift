import Foundation
import SwiftData

/// The stable, portable representation of app data used for JSON backup/import.
/// Intentionally decoupled from the SwiftData models so the file format never
/// breaks if the models evolve.
struct BackupEntryDTO: Codable {
    var date: Date
    var startTime: Date
    var endTime: Date
    var durationHours: Double
    var taskDescription: String
}

struct BackupProjectDTO: Codable {
    var name: String
    var entries: [BackupEntryDTO]
}

struct BackupJobDTO: Codable {
    var name: String
    var projects: [BackupProjectDTO]
}

enum BackupError: LocalizedError {
    case decodingFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .decodingFailed:
            return "This file doesn't look like a valid SignMe backup."
        case .encodingFailed:
            return "Could not prepare your data for backup."
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
}

enum BackupService {

    // MARK: - Export

    static func exportData(jobs: [Job]) throws -> Data {
        let dtos = jobs.map { job in
            BackupJobDTO(
                name: job.name,
                projects: job.projects.map { project in
                    BackupProjectDTO(
                        name: project.name,
                        entries: project.entries.map { entry in
                            BackupEntryDTO(
                                date: entry.date,
                                startTime: entry.startTime,
                                endTime: entry.endTime,
                                durationHours: entry.durationHours,
                                taskDescription: entry.taskDescription
                            )
                        }
                    )
                }
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(dtos)
        } catch {
            throw BackupError.encodingFailed
        }
    }

    // MARK: - Import & merge

    /// Merges the backup file into existing data:
    /// - Jobs are matched (case-insensitively) by name, or created if new.
    /// - Projects are matched by name within their job, or created if new.
    /// - Entries are skipped if an equivalent entry already exists in the destination project.
    @discardableResult
    static func importData(_ data: Data, into context: ModelContext, existingJobs: [Job]) throws -> ImportSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let dtos: [BackupJobDTO]
        do {
            dtos = try decoder.decode([BackupJobDTO].self, from: data)
        } catch {
            throw BackupError.decodingFailed
        }

        var jobsByName = Dictionary(uniqueKeysWithValues: existingJobs.map { ($0.name.lowercased(), $0) })
        var newJobs = 0, newProjects = 0, newEntries = 0, skipped = 0

        for jobDTO in dtos {
            let job: Job
            if let existing = jobsByName[jobDTO.name.lowercased()] {
                job = existing
            } else {
                job = Job(name: jobDTO.name)
                context.insert(job)
                jobsByName[jobDTO.name.lowercased()] = job
                newJobs += 1
            }

            var projectsByName = Dictionary(uniqueKeysWithValues: job.projects.map { ($0.name.lowercased(), $0) })

            for projectDTO in jobDTO.projects {
                let project: Project
                if let existing = projectsByName[projectDTO.name.lowercased()] {
                    project = existing
                } else {
                    project = Project(name: projectDTO.name, job: job)
                    context.insert(project)
                    job.projects.append(project)
                    projectsByName[projectDTO.name.lowercased()] = project
                    newProjects += 1
                }

                for entryDTO in projectDTO.entries {
                    if isDuplicate(entryDTO, in: project) {
                        skipped += 1
                        continue
                    }
                    let entry = WorkEntry(
                        date: entryDTO.date,
                        startTime: entryDTO.startTime,
                        endTime: entryDTO.endTime,
                        taskDescription: entryDTO.taskDescription,
                        project: project
                    )
                    context.insert(entry)
                    project.entries.append(entry)
                    newEntries += 1
                }
            }
        }

        try context.save()
        return ImportSummary(newJobs: newJobs, newProjects: newProjects, newEntries: newEntries, skippedDuplicates: skipped)
    }

    private static func isDuplicate(_ dto: BackupEntryDTO, in project: Project) -> Bool {
        let calendar = Calendar.current
        return project.entries.contains { entry in
            calendar.isDate(entry.date, inSameDayAs: dto.date) &&
            abs(entry.startTime.timeIntervalSince(dto.startTime)) < 60 &&
            abs(entry.endTime.timeIntervalSince(dto.endTime)) < 60 &&
            abs(entry.durationHours - dto.durationHours) < 0.01 &&
            entry.taskDescription == dto.taskDescription
        }
    }
}
