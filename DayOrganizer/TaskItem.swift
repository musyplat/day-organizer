import Foundation
import SwiftData

@Model
class TaskItem {
    var title: String
    var timestamp: Date
    var isCompleted: Bool = false
    
    var latitude: Double?
    var longitude: Double?
    var locationName: String?

    init(title: String, timestamp: Date) {
        self.title = title
        self.timestamp = timestamp
    }
}