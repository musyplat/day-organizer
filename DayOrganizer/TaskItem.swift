import Foundation
import SwiftData

@Model
class TaskItem: Identifiable {
    var title: String
    var subtext: String
    var estimatedMinutes: Int
    var repeatDays: [Bool]
    var isCompleted: Bool = false
    var createdAt: Date = Date()

    init(title: String = "", subtext: String = "", estimatedMinutes: Int = 30, repeatDays: [Bool] = Array(repeating: false, count: 7)) {
        self.title = title
        self.subtext = subtext
        self.estimatedMinutes = estimatedMinutes
        self.repeatDays = repeatDays
    }
}