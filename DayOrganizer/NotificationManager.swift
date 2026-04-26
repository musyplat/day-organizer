import Foundation
import UserNotifications
import SwiftData

/// Thin wrapper around `UNUserNotificationCenter` for scheduling reminders
/// when a `ScheduledBlock` starts.
///
/// Each block gets one local notification, keyed by the block's
/// `PersistentIdentifier` so we can cancel or replace it when the block is
/// moved, unscheduled, or its task is completed.
enum NotificationManager {

    // MARK: - Authorization

    /// Idempotent — if the user has already allowed or denied, this is a no-op
    /// (the system won't prompt a second time). Safe to call on every launch.
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
        center.add(request)
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

    /// `String(describing:)` on a `PersistentIdentifier` yields a stable
    /// opaque form for the lifetime of the record — good enough for matching
    /// pending requests across in-session changes and across launches.
    private static func identifier(for block: ScheduledBlock) -> String {
        "block-\(String(describing: block.persistentModelID))"
    }
}
