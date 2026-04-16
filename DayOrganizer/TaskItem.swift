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

    /// Cascade-deletes all ScheduledBlocks when this task is deleted
    @Relationship(deleteRule: .cascade, inverse: \ScheduledBlock.task)
    var scheduledBlocks: [ScheduledBlock] = []

    init(
        title: String,
        subtext: String = "",
        estimatedMinutes: Int = 30,
        repeatDays: [Bool] = Array(repeating: false, count: 7),
        lastCompletedDate: Date? = nil
    ) {
        self.title = title
        self.subtext = subtext
        self.estimatedMinutes = estimatedMinutes
        self.repeatDays = repeatDays
        self.lastCompletedDate = lastCompletedDate
    }

    var isRepeating: Bool { repeatDays.contains(true) }
}
