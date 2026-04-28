import Foundation
import SwiftData

@Model
class TaskItem {
    var title: String
    var subtext: String
    var estimatedMinutes: Int
    /// [Sun, Mon, Tue, Wed, Thu, Fri, Sat] — true = repeats on that day
    var repeatDays: [Bool]
    var lastCompletedDate: Date?

    /// Optional pre-task buffer in minutes (0 = no buffer).
    /// Visible everywhere the task is shown; on the calendar it renders as a
    /// gray extension above the block, and the notification center fires an
    /// additional reminder at `start − bufferMinutes`.
    /// Default of 0 lets SwiftData lightweight-migration cover existing rows.
    var bufferMinutes: Int = 0

    /// Cascade-deletes all ScheduledBlocks when this task is deleted
    @Relationship(deleteRule: .cascade, inverse: \ScheduledBlock.task)
    var scheduledBlocks: [ScheduledBlock] = []

    init(
        title: String,
        subtext: String = "",
        estimatedMinutes: Int = 30,
        bufferMinutes: Int = 0,
        repeatDays: [Bool] = Array(repeating: false, count: 7),
        lastCompletedDate: Date? = nil
    ) {
        self.title = title
        self.subtext = subtext
        self.estimatedMinutes = estimatedMinutes
        self.bufferMinutes = bufferMinutes
        self.repeatDays = repeatDays
        self.lastCompletedDate = lastCompletedDate
    }

    var isRepeating: Bool { repeatDays.contains(true) }
}
