import XCTest
@testable import SignMe

final class TimerStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "SignMeTests.TimerStore"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private let t0 = Date(timeIntervalSince1970: 1_780_000_020)  // exactly on a minute boundary

    func testWorkedTimeExcludesBreaks() {
        let timer = TimerStore(defaults: defaults)
        timer.start(projectID: UUID(), at: t0)
        timer.toggleBreak(at: t0.addingTimeInterval(3600))        // break after 1h
        timer.toggleBreak(at: t0.addingTimeInterval(3600 + 900))  // 15 min break
        let now = t0.addingTimeInterval(2 * 3600)

        XCTAssertEqual(timer.breakDuration(at: now), 900, accuracy: 0.001)
        XCTAssertEqual(timer.workedDuration(at: now), 2 * 3600 - 900, accuracy: 0.001)
    }

    func testSnapshotUsesWholeMinutesAndBreak() throws {
        let timer = TimerStore(defaults: defaults)
        let project = UUID()
        timer.start(projectID: project, at: t0.addingTimeInterval(20))   // 20 s past the minute
        timer.toggleBreak(at: t0.addingTimeInterval(600))
        timer.toggleBreak(at: t0.addingTimeInterval(600 + 30 * 60))     // 30 min break

        let snapshot = try XCTUnwrap(timer.snapshot(at: t0.addingTimeInterval(3 * 3600 + 45)))
        XCTAssertEqual(snapshot.projectID, project)
        XCTAssertEqual(snapshot.start, t0)
        XCTAssertEqual(snapshot.end, t0.addingTimeInterval(3 * 3600))
        XCTAssertEqual(snapshot.breakMinutes, 30)
        XCTAssertTrue(timer.isRunning, "Taking a snapshot must not stop the timer")
    }

    func testStatePersistsAcrossInstancesAndResetClears() {
        let project = UUID()
        let first = TimerStore(defaults: defaults)
        first.start(projectID: project, at: t0)
        first.toggleBreak(at: t0.addingTimeInterval(60))

        let restored = TimerStore(defaults: defaults)
        XCTAssertTrue(restored.isRunning)
        XCTAssertTrue(restored.isOnBreak)
        XCTAssertEqual(restored.projectID, project)
        XCTAssertEqual(restored.startedAt, t0)

        restored.reset()
        XCTAssertFalse(TimerStore(defaults: defaults).isRunning)
    }

    func testClockText() {
        XCTAssertEqual(TimerStore.clockText(0), "00:00:00")
        XCTAssertEqual(TimerStore.clockText(6138), "01:42:18")
    }
}
