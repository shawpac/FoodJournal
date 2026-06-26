import SwiftUI

/// v2.1a follow-up — full-page Apple Fitness history. Pushed onto the
/// Workouts tab's nav stack via NavigationLink from the inline "See previous
/// workouts ›" row. Read-only: Apple Fitness data is live from HealthKit and
/// not editable.
///
/// Workouts are passed in already pre-filtered to EXCLUDE today (today's
/// rows render inline on the tab). This view does NOT issue its own HK
/// query — it reuses whatever the parent's `readWorkouts(from:to:)` call
/// returned. Matches the v1.9 invariant: HK data is read on demand, never
/// cached locally; the parent owns the fetch.
struct WorkoutHistoryView: View {

    /// Apple Fitness workouts EXCLUDING today's. Newest first.
    let workouts: [HealthService.WorkoutSummary]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if workouts.isEmpty {
                    emptyState
                } else {
                    ForEach(groupedByDay, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(dayLabel(group.day))
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
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Previous Workouts")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No previous workouts")
                .font(.headline)
            Text("Logged workouts from earlier days will appear here.")
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

    // MARK: - Grouping

    private struct DayGroup {
        let day: Date
        let items: [HealthService.WorkoutSummary]
    }

    private var groupedByDay: [DayGroup] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: workouts) { cal.startOfDay(for: $0.startDate) }
        return dict.keys.sorted(by: >).map { day in
            DayGroup(day: day, items: (dict[day] ?? []).sorted { $0.startDate > $1.startDate })
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        // "Today" is intentionally NOT a case here — this page excludes today.
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    // MARK: - Row + formatter
    // Visual twin of WorkoutView.workoutRow / formatDuration. Slight
    // duplication is acceptable here — the two views may diverge later (e.g.
    // adding a per-day summary header on this page) and keeping the helpers
    // local avoids cross-view coupling.

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

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
