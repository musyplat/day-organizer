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
/// Each block can produce up to two local notifications:
///   • a *buffer* heads-up at `start − bufferMinutes` (only if the task has
///     a non-zero buffer), and
///   • a *start* reminder at the actual start time.
///
/// Both are keyed by the block's `notificationID` (a UUID we own — see
/// ScheduledBlock for why we don't use `persistentModelID`) plus a stable
/// suffix, so each can be canceled or replaced independently.
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

    /// Schedule (or replace) the buffer + start notifications for this block.
    /// Always clears any pending requests for both ids first so a relocate or
    /// buffer-time edit can't leave a stale push behind. If a fire date has
    /// already passed (buffer time before "now", or start time before "now"),
    /// the corresponding push is silently skipped — this is normal for blocks
    /// scheduled close to the current minute.
    static func schedule(for block: ScheduledBlock) {
        let center = UNUserNotificationCenter.current()
        let ids = allIdentifiers(for: block)
        center.removePendingNotificationRequests(withIdentifiers: ids)

        let now = Date()

        // ── Start reminder
        if block.startTime > now {
            let request = makeStartRequest(for: block)
            center.add(request) { error in
                if let error {
                    print("[NotificationManager] schedule (start) failed for \(request.identifier): \(error)")
                }
            }
        }

        // ── Buffer heads-up
        let buffer = block.task.bufferMinutes
        if buffer > 0 {
            let bufferDate = block.startTime.addingTimeInterval(-Double(buffer) * 60)
            if bufferDate > now {
                let request = makeBufferRequest(for: block, bufferMinutes: buffer, fireDate: bufferDate)
                center.add(request) { error in
                    if let error {
                        print("[NotificationManager] schedule (buffer) failed for \(request.identifier): \(error)")
                    }
                }
            }
        }
    }

    /// Remove any pending notifications (both buffer + start) for this block.
    /// Safe to call even if nothing was scheduled.
    static func cancel(for block: ScheduledBlock) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: allIdentifiers(for: block))
    }

    /// Cancel several at once (e.g. before cascade-deleting a task).
    static func cancel<S: Sequence>(for blocks: S) where S.Element == ScheduledBlock {
        let ids = blocks.flatMap(allIdentifiers(for:))
        guard !ids.isEmpty else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Request Builders

    private static func makeStartRequest(for block: ScheduledBlock) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = block.task.title

        let timeLabel = CalendarEngine.timeLabel(for: block.startMinute)
        let subtext = block.task.subtext.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = subtext.isEmpty ? timeLabel : "\(timeLabel) — \(subtext)"
        content.sound = .default

        let trigger = makeCalendarTrigger(for: block.startTime)
        return UNNotificationRequest(
            identifier: startIdentifier(for: block),
            content: content,
            trigger: trigger
        )
    }

    private static func makeBufferRequest(
        for block: ScheduledBlock,
        bufferMinutes: Int,
        fireDate: Date
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        // Title makes it clear this is a heads-up, not the task itself starting.
        content.title = "Heads up: \(block.task.title)"

        let timeLabel = CalendarEngine.timeLabel(for: block.startMinute)
        content.body = "Starts in \(bufferMinutes) min — \(timeLabel)"
        content.sound = .default

        let trigger = makeCalendarTrigger(for: fireDate)
        return UNNotificationRequest(
            identifier: bufferIdentifier(for: block),
            content: content,
            trigger: trigger
        )
    }

    private static func makeCalendarTrigger(for fireDate: Date) -> UNCalendarNotificationTrigger {
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    }

    // MARK: - Identifiers

    /// Returns both ids for a block so cancel/replace operations cover the
    /// pair atomically.
    private static func allIdentifiers(for block: ScheduledBlock) -> [String] {
        [startIdentifier(for: block), bufferIdentifier(for: block)]
    }

    private static func startIdentifier(for block: ScheduledBlock) -> String {
        "block-\(stableID(for: block))-start"
    }

    private static func bufferIdentifier(for block: ScheduledBlock) -> String {
        "block-\(stableID(for: block))-buffer"
    }

    /// Lazy-assigns a UUID for blocks that predate the `notificationID`
    /// field so identifiers stay stable across launches.
    private static func stableID(for block: ScheduledBlock) -> String {
        if block.notificationID == nil {
            block.notificationID = UUID()
        }
        // Force-unwrap is safe: just assigned above if it was nil.
        return block.notificationID!.uuidString
    }
}
