import Foundation
import UserNotifications
import SwiftData

/// Foreground-presentation delegate. By default iOS suppresses banner and
/// sound when the app is in the foreground, which looked like "notifications
/// don't get sent" to the user. Returning presentation options here makes
/// reminders visible whether the app is open or not.
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

/// Thin wrapper around `UNUserNotificationCenter` for scheduling reminders
/// when a `ScheduledBlock` starts.
///
/// Each block gets one local notification, keyed by the block's
/// `notificationID` (a UUID we own — see ScheduledBlock for why we don't use
/// `persistentModelID`).
enum NotificationManager {

    // MARK: - Authorization

    /// Idempotent — if the user has already allowed or denied, this is a no-op
    /// (the system won't prompt a second time). Safe to call on every launch.
    /// Also installs the foreground-presentation delegate so banners show up
    /// when the app is open.
    static func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        // Set the delegate before scheduling anything so foreground delivery
        // works for the very first reminder of the session too.
        center.delegate = NotificationDelegate.shared
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - Schedule / Cancel

    /// Schedule (or replace) a notification that fires when `block.startTime`
    /// matches the wall clock. If the start time has already passed, nothing
    /// is scheduled — we still clear any pending request with this id so stale
    /// entries don't linger.
    static func schedule(for block: ScheduledBlock) {
        let id = identifier(for: block)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let fireDate = block.startTime
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = block.task.title

        // Body: "<start time> — <subtext>" when subtext exists, else just the
        // time. Keeping the time here means the push reads the same whether
        // it's delivered on-schedule or a minute late.
        let timeLabel = CalendarEngine.timeLabel(for: block.startMinute)
        let subtext = block.task.subtext.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = subtext.isEmpty ? timeLabel : "\(timeLabel) — \(subtext)"
        content.sound = .default

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request) { error in
            if let error {
                // Surfacing this — silent .add() failures previously made
                // "sometimes notifications don't get sent" hard to diagnose.
                print("[NotificationManager] schedule failed for \(id): \(error)")
            }
        }
    }

    /// Remove any pending notification for this block. Safe to call even if
    /// nothing was scheduled.
    static func cancel(for block: ScheduledBlock) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier(for: block)])
    }

    /// Cancel several at once (e.g. before cascade-deleting a task).
    static func cancel<S: Sequence>(for blocks: S) where S.Element == ScheduledBlock {
        let ids = blocks.map(identifier(for:))
        guard !ids.isEmpty else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Identifier

    /// Returns the block's stable notification id, lazy-assigning a UUID if
    /// the block predates the `notificationID` field (legacy rows from before
    /// this column was added migrate in as nil).
    private static func identifier(for block: ScheduledBlock) -> String {
        if block.notificationID == nil {
            block.notificationID = UUID()
        }
        // Force-unwrap is safe: just assigned above if it was nil.
        return "block-\(block.notificationID!.uuidString)"
    }
}
