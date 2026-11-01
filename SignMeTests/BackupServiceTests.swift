import XCTest
import SwiftData
@testable import SignMe

@MainActor
final class BackupServiceTests: XCTestCase {
    private var containers: [ModelContainer] = []

    /// A fresh in-memory store. The container is retained for the test's lifetime.
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Job.self, Project.self, WorkEntry.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        containers.append(container)
        return container.mainContext
    }

    @discardableResult
    private func seed(_ context: ModelContext, jobName: String = "Acme", projectName: String = "Website", entryCount: Int = 3) -> Job {
        let job = Job(name: jobName, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(job)
        let project = Project(name: projectName)
        context.insert(project)
        job.projects.append(project)
        for index in 0..<entryCount {
            let start = Date(timeIntervalSince1970: 1_780_000_000 + Double(index) * 86_400)
            let entry = WorkEntry(
                date: start,
                startTime: start,
                endTime: start.addingTimeInterval(4 * 3600),
                breakMinutes: 15,
                taskDescription: "Task \(index)"
            )
            context.insert(entry)
            project.entries.append(entry)
        }
        return job
    }

    private func jobs(in context: ModelContext) throws -> [Job] {
        try context.fetch(FetchDescriptor<Job>())
    }

    // MARK: - Tests

    func testRoundTripRestoresEverything() throws {
        let source = try makeContext()
        seed(source)
        let data = try BackupService.exportData(jobs: try jobs(in: source))

        let destination = try makeContext()
        let summary = try BackupService.importData(data, into: destination, existingJobs: [])

        XCTAssertEqual(summary.newJobs, 1)
        XCTAssertEqual(summary.newProjects, 1)
        XCTAssertEqual(summary.newEntries, 3)

        let restored = try XCTUnwrap(try jobs(in: destination).first)
        XCTAssertEqual(restored.createdAt, Date(timeIntervalSince1970: 1_700_000_000))
        let entries = restored.projects.flatMap(\.entries)
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries.allSatisfy { $0.breakMinutes == 15 })
        XCTAssertEqual(entries.first?.durationHours ?? 0, 3.75, accuracy: 0.0001)
    }

    func testReimportingSameBackupSkipsEverything() throws {
        let context = try makeContext()
        seed(context)
        let data = try BackupService.exportData(jobs: try jobs(in: context))

        let summary = try BackupService.importData(data, into: context, existingJobs: try jobs(in: context))
        XCTAssertEqual(summary.newJobs, 0)
        XCTAssertEqual(summary.newEntries, 0)
        XCTAssertEqual(summary.skippedDuplicates, 3)
    }

    func testImportDoesNotCrashWhenStoreHasDuplicateNames() throws {
        let context = try makeContext()
        seed(context, jobName: "Acme", entryCount: 0)
        seed(context, jobName: "acme", entryCount: 0)       // same name, different case
        let job = try XCTUnwrap(try jobs(in: context).first)
        let twin = Project(name: "WEBSITE")                 // duplicate project name in one job
        context.insert(twin)
        job.projects.append(twin)

        let otherStore = try makeContext()
        seed(otherStore, jobName: "ACME", entryCount: 2)
        let data = try BackupService.exportData(jobs: try jobs(in: otherStore))

        let summary = try BackupService.importData(data, into: context, existingJobs: try jobs(in: context))
        XCTAssertEqual(summary.newJobs, 0, "Should merge into an existing 'Acme' job")
        XCTAssertEqual(summary.newEntries, 2)
    }

    func testLegacyBareArrayBackupStillImports() throws {
        let legacy = """
        [{"name":"Old Job","projects":[{"name":"P","entries":[{
          "date":"2026-01-05T08:00:00Z","startTime":"2026-01-05T08:00:00Z","endTime":"2026-01-05T10:00:00Z",
          "durationHours":2,"taskDescription":"Legacy"}]}]}]
        """
        let context = try makeContext()
        let summary = try BackupService.importData(Data(legacy.utf8), into: context, existingJobs: [])
        XCTAssertEqual(summary.newJobs, 1)
        XCTAssertEqual(summary.newEntries, 1)
        let entry = try XCTUnwrap(try jobs(in: context).first?.projects.first?.entries.first)
        XCTAssertEqual(entry.breakMinutes, 0)
        XCTAssertEqual(entry.durationHours, 2, accuracy: 0.0001)
    }

    func testNewerFormatVersionIsRejected() throws {
        let future = #"{"formatVersion": 99, "exportedAt": "2026-01-01T00:00:00Z", "jobs": []}"#
        let context = try makeContext()
        XCTAssertThrowsError(try BackupService.importData(Data(future.utf8), into: context, existingJobs: [])) { error in
            guard case .unsupportedVersion(99)? = error as? BackupError else {
                return XCTFail("Expected unsupportedVersion(99), got \(error)")
            }
        }
    }

    func testGarbageIsRejected() throws {
        let context = try makeContext()
        XCTAssertThrowsError(try BackupService.importData(Data("not json".utf8), into: context, existingJobs: []))
    }

    func testExportWritesVersionedWrapper() throws {
        let context = try makeContext()
        seed(context)
        let data = try BackupService.exportData(jobs: try jobs(in: context))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["formatVersion"] as? Int, BackupFile.currentFormatVersion)
        XCTAssertNotNil(object["jobs"] as? [Any])
    }
}
