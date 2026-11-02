import Foundation
import SwiftData
import UserNotifications
import UIKit

/// Local notifications for planned tasks.
///
/// Instead of patching individual requests, every change re-syncs the whole set:
/// all pending "planned." requests are removed and the ones still ahead are added
/// again from the stored tasks. That keeps reminders right after edits, deletes,
/// completions, project renames and backup imports. iOS keeps at most 64 pending
/// local notifications per app, so the soonest ones win if there are more.
@MainActor
enum PlannedTaskNotifications {
    static let prefix = "planned."
    static let taskIDKey = "plannedTaskID"
    private static let limit = 60

    private static var center: UNUserNotificationCenter { .current() }

    // MARK: Permission

    enum Permission {
        case notDetermined, allowed, denied
    }

    static func permission() async -> Permission {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .allowed
        }
    }

    /// Asks once; returns whether notifications can be shown.
    @discardableResult
    static func requestPermission() async -> Bool {
        switch await permission() {
        case .allowed: return true
        case .denied: return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    static func openSystemSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: Sync

    private struct Pending {
        let identifier: String
        let date: Date
        let content: UNMutableNotificationContent
    }

    /// Rebuilds all planned-task notifications from what's stored.
    static func sync(context: ModelContext, now: Date = .now) async {
        let tasks = (try? context.fetch(FetchDescriptor<PlannedTask>())) ?? []
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let projectsByID = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var pending: [Pending] = []
        for task in tasks where task.status == .planned {
            guard let project = projectsByID[task.projectID] else { continue }
            pending += requests(for: task, project: project, now: now)
        }
        pending.sort { $0.date < $1.date }

        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: existing)

        // Remove delivered notifications of tasks that are done or deleted.
        let openIDs = Set(tasks.filter { $0.status == .planned }.map { $0.id.uuidString })
        let delivered = await center.deliveredNotifications()
            .filter { $0.request.identifier.hasPrefix(prefix) }
            .filter { !openIDs.contains(($0.request.content.userInfo[taskIDKey] as? String) ?? "") }
            .map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: delivered)

        guard !pending.isEmpty, await permission() == .allowed else { return }
        for item in pending.prefix(limit) {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: item.identifier, content: item.content, trigger: trigger)
            try? await center.add(request)
        }
    }

    private static func requests(for task: PlannedTask, project: Project, now: Date) -> [Pending] {
        let base = "\(prefix)\(task.id.uuidString)."
        let place = [project.job?.name, project.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        let time = task.start.formatted(date: .omitted, time: .shortened)
        let day = task.start.formatted(.dateTime.weekday(.wide).day().month(.wide))
        var result: [Pending] = []

        for reminder in task.upcomingReminders(now: now) {
            let content = baseContent(for: task)
            content.title = task.taskDescription
            content.subtitle = place
            content.body = reminder.offset == 0
                ? "Starting now (\(time))."
                : "Starts \(relative(reminder.offset)) — \(day), \(time)."
            result.append(Pending(identifier: base + "r\(reminder.offset)", date: reminder.date, content: content))
        }

        if let date = task.logReminderDate(now: now) {
            let content = baseContent(for: task)
            content.title = "Did you finish “\(task.taskDescription)”?"
            content.subtitle = place
            content.body = "Confirm it's done and set the end time to add it to your working hours."
            result.append(Pending(identifier: base + "log", date: date, content: content))
        }
        return result
    }

    private static func baseContent(for task: PlannedTask) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.threadIdentifier = task.id.uuidString
        content.userInfo = [taskIDKey: task.id.uuidString]
        return content
    }

    /// "in 1 day", "in 2 hours", "in 30 minutes"
    static func relative(_ offset: Int) -> String {
        if offset % 1440 == 0 {
            let days = offset / 1440
            return days == 1 ? "tomorrow" : "in \(days) days"
        }
        if offset % 60 == 0 {
            let hours = offset / 60
            return hours == 1 ? "in 1 hour" : "in \(hours) hours"
        }
        return "in \(offset) minutes"
    }
}

/// Opens a planned task when its notification is tapped.
@Observable
final class PlannedTaskRouter {
    static let shared = PlannedTaskRouter()
    var openTaskID: UUID?
}

/// Receives notification taps and shows notifications while the app is open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let raw = response.notification.request.content.userInfo[PlannedTaskNotifications.taskIDKey] as? String
        if let raw, let id = UUID(uuidString: raw) {
            DispatchQueue.main.async {
                PlannedTaskRouter.shared.openTaskID = id
            }
        }
        completionHandler()
    }
}
