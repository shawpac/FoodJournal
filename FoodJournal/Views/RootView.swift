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
        // v2.2 reorganization: 5 tabs total, no "More" overflow.
        // Order: Food (was Today) · Workouts · Health Data · Trends · Settings.
        // The Add tab was removed — food is logged via Today's meal cards
        // (MealDetailSheet) which is how the user actually adds meals.
        // AddFoodView.swift is left in the project but unreferenced; safe to
        // delete in a later cleanup if it stays unused.
        TabView(selection: $selectedTab) {
            TodayView(selectedDate: $selectedDate, pendingMealKey: $pendingMealKey)
                .tabItem { Label("Food", systemImage: "fork.knife") }
                .tag(0)

            WorkoutView()
                .tabItem { Label("Workouts", systemImage: "figure.run") }
                .tag(1)

            HealthMetricsView()
                .tabItem { Label("Health Data", systemImage: "heart.text.square") }
                .tag(2)

            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
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
