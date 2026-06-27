import SwiftUI
import SwiftData
import UserNotifications

@main
struct FoodJournalApp: App {
    @State private var notificationCoordinator = NotificationCoordinator()

    var sharedModelContainer: ModelContainer = {
        // v2.1a: 7 strength/daily models registered explicitly.
        // v2.3a: +2 lab models (LabPanel cascade-owns LabResult). Container
        // now holds 16 model types total. Register both EXPLICITLY — don't
        // rely on relationship inference to pull children in.
        let schema = Schema([
                    FoodEntry.self,
                    UserGoals.self,
                    CachedFood.self,
                    WaterEntry.self,
                    CachedPhotoEstimate.self,
                    LibraryFood.self,
                    WeightEntry.self,
                    // v2.1a — daily tracker
                    ExerciseRepEntry.self,
                    StretchDay.self,
                    // v2.1a — strength: routines + sessions (nested cascade)
                    StrengthRoutine.self,
                    RoutineExercise.self,
                    StrengthSession.self,
                    LoggedExercise.self,
                    LoggedSet.self,
                    // v2.3a — labs: panel cascade-owns results
                    LabPanel.self,
                    LabResult.self
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
