import SwiftUI
import SwiftData

@main
struct ProductivityApp: App {

    init() {
        // Asks once; no-op on subsequent launches once the user has chosen.
        NotificationManager.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [TaskItem.self, ScheduledBlock.self])
    }
}
