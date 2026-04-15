import Foundation
import SwiftData

@Model
class TaskItem {
    var title: String
    var subtext: String
    var estimatedMinutes: Int
    var repeatDays: [Bool]
    var lastCompletedDate: Date?

    init(title: String, subtext: String, estimatedMinutes: Int, repeatDays: [Bool], lastCompletedDate: Date? = nil) {
        self.title = title
        self.subtext = subtext
        self.estimatedMinutes = estimatedMinutes
        self.repeatDays = repeatDays
        self.lastCompletedDate = lastCompletedDate
    }
}