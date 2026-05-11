import SwiftUI
import SwiftData
import UserNotifications

@main
struct FoodJournalApp: App {
    @State private var notificationCoordinator = NotificationCoordinator()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
                    FoodEntry.self,
                    UserGoals.self,
                    CachedFood.self,
                    WaterEntry.self,
                    CachedPhotoEstimate.self,
                    LibraryFood.self,
                    WeightEntry.self
                ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(notificationCoordinator)
                .task {
                    UNUserNotificationCenter.current().delegate = notificationCoordinator
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
