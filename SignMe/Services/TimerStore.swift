import Foundation
import Observation

/// The live "clock-in" timer. Its state is saved to UserDefaults on every change,
/// so a running timer survives the app being closed or the phone restarting.
@Observable
final class TimerStore {
    private enum Keys {
        static let startedAt = "timer.startedAt"
        static let projectID = "timer.projectID"
        static let breakStartedAt = "timer.breakStartedAt"
        static let accumulatedBreak = "timer.accumulatedBreak"
    }

    /// What a stopped timer hands to the entry form.
    struct Snapshot {
        var projectID: UUID
        var start: Date
        var end: Date
        var breakMinutes: Int
    }

    private(set) var startedAt: Date?
    private(set) var projectID: UUID?
    private(set) var breakStartedAt: Date?
    private(set) var accumulatedBreak: TimeInterval = 0

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let start = defaults.object(forKey: Keys.startedAt) as? Date {
            startedAt = start
            projectID = defaults.string(forKey: Keys.projectID).flatMap(UUID.init(uuidString:))
            breakStartedAt = defaults.object(forKey: Keys.breakStartedAt) as? Date
            accumulatedBreak = defaults.double(forKey: Keys.accumulatedBreak)
        }
    }

    var isRunning: Bool { startedAt != nil }
    var isOnBreak: Bool { breakStartedAt != nil }

    func breakDuration(at now: Date = .now) -> TimeInterval {
        accumulatedBreak + (breakStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    func workedDuration(at now: Date = .now) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, now.timeIntervalSince(startedAt) - breakDuration(at: now))
    }

    // MARK: - Actions

    func start(projectID: UUID, at date: Date = .now) {
        startedAt = date
        self.projectID = projectID
        breakStartedAt = nil
        accumulatedBreak = 0
        persist()
    }

    func toggleBreak(at date: Date = .now) {
        guard isRunning else { return }
        if let breakStart = breakStartedAt {
            accumulatedBreak += max(0, date.timeIntervalSince(breakStart))
            breakStartedAt = nil
        } else {
            breakStartedAt = date
        }
        persist()
    }

    func switchProject(to projectID: UUID) {
        guard isRunning else { return }
        self.projectID = projectID
        persist()
    }

    /// The interval to save if the timer were stopped at `now` (times cut to whole
    /// minutes). The timer keeps running until `reset()`, so cancelling the entry
    /// form loses nothing.
    func snapshot(at now: Date = .now, calendar: Calendar = .current) -> Snapshot? {
        guard let startedAt, let projectID else { return nil }
        let start = Self.wholeMinute(startedAt, calendar: calendar)
        let end = Self.wholeMinute(now, calendar: calendar)
        let spanMinutes = Int(end.timeIntervalSince(start) / 60)
        let breakMinutes = min(Int((breakDuration(at: now) / 60).rounded()), max(0, spanMinutes - 1))
        return Snapshot(projectID: projectID, start: start, end: end, breakMinutes: max(0, breakMinutes))
    }

    /// Stops and clears the timer.
    func reset() {
        startedAt = nil
        projectID = nil
        breakStartedAt = nil
        accumulatedBreak = 0
        persist()
    }

    // MARK: - Formatting

    /// "01:42:18"
    static func clockText(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    // MARK: - Private

    private static func wholeMinute(_ date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .minute, for: date)?.start ?? date
    }

    private func persist() {
        if let startedAt {
            defaults.set(startedAt, forKey: Keys.startedAt)
            defaults.set(projectID?.uuidString, forKey: Keys.projectID)
            defaults.set(breakStartedAt, forKey: Keys.breakStartedAt)
            defaults.set(accumulatedBreak, forKey: Keys.accumulatedBreak)
        } else {
            [Keys.startedAt, Keys.projectID, Keys.breakStartedAt, Keys.accumulatedBreak].forEach(defaults.removeObject(forKey:))
        }
    }
}
