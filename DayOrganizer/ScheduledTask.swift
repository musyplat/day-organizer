import Foundation
import SwiftData

@Model
class ScheduledTask {

    var date: Date
    var startTime: Date
    var endTime: Date

    var task: TaskItem

    init(task: TaskItem, date: Date, startTime: Date, endTime: Date) {
        self.task = task
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
    }

    var durationMinutes: Int {
        Int(endTime.timeIntervalSince(startTime) / 60)
    }
}