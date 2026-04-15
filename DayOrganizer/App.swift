import SwiftUI
import SwiftData

@main
struct ProductivityApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [TaskItem.self, ScheduledTask.self])
    }
}