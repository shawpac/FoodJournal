import SwiftUI

/// v2.0 — Workouts tab. Reads HKWorkout samples from Apple Health on demand
/// (no local caching, matching the v1.9 invariant). The body is composed as
/// a sequence of optional sections so v2.1 can add a daily bodyweight tracker
/// and strength-training routines without re-architecting.
///
/// State is self-contained: this view does NOT share RootView's selectedDate
/// binding, matching the precedent set by Trends and Settings.
struct WorkoutView: View {

    /// Lookback window for the Apple Fitness list. Tunable — 30 days keeps
    /// the fetch fast while covering a meaningful history. Today's summary is
    /// derived from the same fetched array.
    private static let lookbackDays = 30

    @State private var workouts: [HealthService.WorkoutSummary] = []
    @State private var hasRequestedAuth = false
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    todaySummaryCard
                    appleFitnessSection
                    // v2.1 section slots — leave the structure here so future
                    // additions plug in without touching the loader / state:
                    // dailyBodyweightSection
                    // strengthRoutinesSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Workouts")
            .task {
                if !hasRequestedAuth {
                    hasRequestedAuth = true
                    _ = await HealthService.requestWorkoutReadAuthorization()
                }
                await reloadWorkouts()
            }
            .refreshable {
                await reloadWorkouts()
            }
        }
    }

    // MARK: - Loading

    private func reloadWorkouts() async {
        isLoading = true
        let cal = Calendar.current
        let now = Date.now
        let start = cal.date(byAdding: .day, value: -Self.lookbackDays, to: cal.startOfDay(for: now)) ?? now
        workouts = await HealthService.readWorkouts(from: start, to: now)
        isLoading = false
    }

    // MARK: - Today summary

    private var todayWorkouts: [HealthService.WorkoutSummary] {
        let cal = Calendar.current
        return workouts.filter { cal.isDateInToday($0.startDate) }
    }

    /// Sum of activeCalories across today's workouts. Nil when EVERY workout
    /// today has no active-cal data — preserves nil ≠ 0 honesty. A mix of
    /// nil + numeric workouts uses the numeric values (which is at least an
    /// under-count, not a fake zero).
    private var todayActiveCal: Double? {
        let values = todayWorkouts.compactMap(\.activeCalories)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    /// Sum of durations today. Nil when no workouts today.
    private var todayDuration: TimeInterval? {
        guard !todayWorkouts.isEmpty else { return nil }
        return todayWorkouts.reduce(0) { $0 + $1.duration }
    }

    private var todaySummaryCard: some View {
        HStack(spacing: 12) {
            WorkoutStat(
                label: "Workouts",
                value: todayWorkouts.isEmpty ? "—" : "\(todayWorkouts.count)",
                sub: "today"
            )
            WorkoutStat(
                label: "Active cal",
                value: todayActiveCal.map { "\(Int($0.rounded()))" } ?? "—",
                sub: "kcal"
            )
            WorkoutStat(
                label: "Duration",
                value: todayDuration.map(formatDuration) ?? "—",
                sub: "today"
            )
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Apple Fitness section

    private var appleFitnessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Apple Fitness")
            if workouts.isEmpty {
                emptyStateCard
            } else {
                VStack(spacing: 16) {
                    ForEach(groupedWorkouts, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(dayHeader(group.day))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                            VStack(spacing: 8) {
                                ForEach(group.items) { w in
                                    workoutRow(w)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyStateCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No workouts found")
                .font(.headline)
            Text("Workouts sync from Apple Health. Log a session in the Fitness app or with your Apple Watch and it'll appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private func workoutRow(_ w: HealthService.WorkoutSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: w.symbolName)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(w.displayName).font(.body)
                Text(w.startDate, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDuration(w.duration))
                    .font(.callout.monospacedDigit())
                Text(w.activeCalories.map { "\(Int($0.rounded())) kcal" } ?? "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let miles = w.distanceMiles {
                    Text(String(format: "%.2f mi", miles))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Grouping

    private struct DayGroup {
        let day: Date
        let items: [HealthService.WorkoutSummary]
    }

    private var groupedWorkouts: [DayGroup] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: workouts) { cal.startOfDay(for: $0.startDate) }
        return dict.keys.sorted(by: >).map { day in
            DayGroup(day: day, items: (dict[day] ?? []).sorted { $0.startDate > $1.startDate })
        }
    }

    private func dayHeader(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    // MARK: - Formatters

    /// "1h 5m" / "23m" / "0m" — US-style duration. Seconds are rounded to
    /// the nearest minute, which is plenty of precision for workout cards.
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.leading, 4)
    }

    // MARK: - Tile

    /// Visual twin of TodayView.StatTile but inlined here to avoid coupling.
    /// Workout tiles never carry a progress bar — match the bare-tile styling
    /// used by the v1.9 energy strip's non-Net tiles.
    private struct WorkoutStat: View {
        let label: String
        let value: String
        let sub: String

        var body: some View {
            VStack(spacing: 4) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
