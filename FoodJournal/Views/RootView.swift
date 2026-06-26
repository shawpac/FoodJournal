import SwiftUI

struct RootView: View {
    /// Single source of truth for the calendar day the user is viewing /
    /// adding to. Owned here so both the Today tab and the Add tab stay in sync.
    /// Defaults to today on app launch.
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)

    /// Currently selected tab. Bound to TabView so notification deep-links
    /// can force a switch to Today (tag 0).
    @State private var selectedTab: Int = 0

    /// Meal key set when a notification deep-link wants Today to open a specific
    /// MealDetailSheet. TodayView consumes it and clears it back to nil.
    @State private var pendingMealKey: String?

    @Environment(NotificationCoordinator.self) private var notificationCoordinator

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(selectedDate: $selectedDate, pendingMealKey: $pendingMealKey)
                .tabItem { Label("Today", systemImage: "fork.knife") }
                .tag(0)

            AddFoodView(selectedDate: $selectedDate)
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
                .tag(1)

            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(2)

            WorkoutView()
                .tabItem { Label("Workouts", systemImage: "figure.run") }
                .tag(3)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(4)
        }
        .tint(.orange)
        .onChange(of: notificationCoordinator.pendingMealOpen) { _, newValue in
            guard let meal = newValue else { return }
            selectedTab = 0
            selectedDate = Calendar.current.startOfDay(for: .now)
            pendingMealKey = meal
            notificationCoordinator.pendingMealOpen = nil
        }
    }
}
