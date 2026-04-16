import Foundation
import SwiftData

/// A time slot on the calendar for a specific task on a specific day.
@Model
class ScheduledBlock {

    /// Midnight of the calendar day this block belongs to
    var dayDate: Date

    /// Minutes from midnight (0 = 12:00 AM, 1439 = 11:59 PM)
    var startMinute: Int

    /// Can differ from task.estimatedMinutes after splitting or manual resize
    var durationMinutes: Int

    /// The task this block represents
    var task: TaskItem

    /// True after the user ticks this block as done on the calendar
    var isCompleted: Bool

    init(task: TaskItem, dayDate: Date, startMinute: Int, durationMinutes: Int? = nil) {
        self.task = task
        self.dayDate = dayDate
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes ?? task.estimatedMinutes
        self.isCompleted = false
    }

    var endMinute: Int { startMinute + durationMinutes }

    var startTime: Date {
        Calendar.current.date(byAdding: .minute, value: startMinute, to: dayDate) ?? dayDate
    }

    var endTime: Date {
        Calendar.current.date(byAdding: .minute, value: endMinute, to: dayDate) ?? dayDate
    }
}
