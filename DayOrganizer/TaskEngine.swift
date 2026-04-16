import Foundation
import SwiftData

struct TaskEngine {

    // MARK: - Availability

    /// Returns tasks that should appear in the Unassigned pool for a given date:
    /// • Non-repeating tasks that haven't been completed yet
    /// • Repeating tasks scheduled for this weekday that haven't been completed today
    /// • Excludes tasks already scheduled as a ScheduledBlock on this day
    static func availableTasks(
        from tasks: [TaskItem],
        blocks: [ScheduledBlock],
        date: Date = Date()
    ) -> [TaskItem] {

        let weekday = weekdayIndex(for: date)
        let scheduledIDs = Set(
            blocks
                .filter { Calendar.current.isDate($0.dayDate, inSameDayAs: date) }
                .map { $0.task.persistentModelID }
        )

        return tasks.filter { task in
            if scheduledIDs.contains(task.persistentModelID) { return false }
            if wasCompleted(task, on: date) { return false }
            if task.isRepeating { return task.repeatDays[weekday] }
            return true
        }
    }

    // MARK: - Completion

    static func markCompleted(_ task: TaskItem) {
        task.lastCompletedDate = Date()
    }

    static func wasCompleted(_ task: TaskItem, on date: Date) -> Bool {
        guard let last = task.lastCompletedDate else { return false }
        return Calendar.current.isDate(last, inSameDayAs: date)
    }

    // MARK: - Block Manipulation (foundation for future features)

    /// Pushes all blocks to start consecutively from `fromMinute`, preserving order and durations
    static func pushBlocks(_ blocks: [ScheduledBlock], fromMinute: Int) {
        let sorted = blocks.sorted { $0.startMinute < $1.startMinute }
        var cursor = fromMinute
        for block in sorted {
            block.startMinute = cursor
            cursor += block.durationMinutes
        }
    }

    /// Packs all blocks with no gaps, starting from the earliest block's current start minute
    static func compactBlocks(_ blocks: [ScheduledBlock]) {
        let sorted = blocks.sorted { $0.startMinute < $1.startMinute }
        guard let first = sorted.first else { return }
        pushBlocks(sorted, fromMinute: first.startMinute)
    }

    // MARK: - Helpers

    static func weekdayIndex(for date: Date) -> Int {
        Calendar.current.component(.weekday, from: date) - 1
    }

    static func minutesFromMidnight(for date: Date = Date()) -> Int {
        let c = Calendar.current
        return c.component(.hour, from: date) * 60 + c.component(.minute, from: date)
    }
}
