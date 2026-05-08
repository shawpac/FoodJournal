import SwiftUI

struct RootView: View {
    /// Single source of truth for the calendar day the user is viewing /
    /// adding to. Owned here so both the Today tab and the Add tab stay in sync.
    /// Defaults to today on app launch.
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)

    var body: some View {
        TabView {
            TodayView(selectedDate: $selectedDate)
                .tabItem { Label("Today", systemImage: "fork.knife") }

            AddFoodView(selectedDate: $selectedDate)
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }

            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.orange)
    }
}
