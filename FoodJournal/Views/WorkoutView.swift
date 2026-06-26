import SwiftUI
import SwiftData

/// v2.0 — Workouts tab. Reads HKWorkout samples from Apple Health on demand
/// (no local caching, matching the v1.9 invariant). The body is composed as
/// a sequence of sections so v2.1+ can add more without re-architecting.
///
/// v2.1a — Added the **Daily** section (pushup / situp burst log + stretch
/// toggle) and the **Strength** section (entry points to manage routines,
/// log a session, and browse history). Both surfaces sit alongside the
/// existing Apple Fitness section.
///
/// State is self-contained: this view does NOT share RootView's selectedDate
/// binding, matching the precedent set by Trends and Settings.
struct WorkoutView: View {
    @Environment(\.modelContext) private var context

    /// Lookback window for the Apple Fitness list. Tunable — 30 days keeps
    /// the fetch fast while covering a meaningful history. Today's summary is
    /// derived from the same fetched array.
    private static let lookbackDays = 30

    @State private var workouts: [HealthService.WorkoutSummary] = []
    @State private var hasRequestedAuth = false
    @State private var isLoading = false

    // v2.1a — Daily section state
    @Query(sort: \ExerciseRepEntry.loggedAt, order: .reverse)
    private var allRepEntries: [ExerciseRepEntry]
    @Query private var allStretchDays: [StretchDay]

    @State private var pushupInput: String = ""
    @State private var situpInput: String = ""
    @State private var managingKind: String?  // "pushups" or "situps" — drives the DailyRepsSheet

    // v2.1a — Strength section state
    @Query private var allStrengthSessions: [StrengthSession]

    @State private var showingRoutines = false
    @State private var showingLogSession = false
    @State private var showingHistory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    todaySummaryCard
                    appleFitnessSection
                    dailySection            // v2.1a
                    strengthSection         // v2.1a
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
            .sheet(item: Binding(
                get: { managingKind.map { KindID(kind: $0) } },
                set: { managingKind = $0?.kind }
            )) { id in
                DailyRepsSheet(kind: id.kind)
            }
            .sheet(isPresented: $showingRoutines) {
                RoutinesSheet()
            }
            .sheet(isPresented: $showingLogSession) {
                LogSessionSheet()
            }
            .sheet(isPresented: $showingHistory) {
                SessionHistorySheet()
            }
        }
    }

    // sheet(item:) needs an Identifiable wrapper around a String.
    private struct KindID: Identifiable {
        let kind: String
        var id: String { kind }
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
    //
    // v2.1a follow-up — keep the Workouts tab short by showing ONLY today's
    // Apple Fitness workouts inline. A "See previous workouts ›" row pushes
    // the full 30-day history (excluding today) to WorkoutHistoryView.

    /// All Apple Fitness workouts from the lookback window EXCLUDING today.
    private var previousWorkouts: [HealthService.WorkoutSummary] {
        let cal = Calendar.current
        return workouts.filter { !cal.isDateInToday($0.startDate) }
    }

    private var appleFitnessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Apple Fitness")
            if workouts.isEmpty {
                // Nothing at all in the lookback — keep the original CTA.
                emptyStateCard
            } else {
                VStack(spacing: 8) {
                    if todayWorkouts.isEmpty {
                        nothingTodayCard
                    } else {
                        ForEach(todayWorkouts) { w in
                            workoutRow(w)
                        }
                    }
                    if !previousWorkouts.isEmpty {
                        NavigationLink {
                            WorkoutHistoryView(workouts: previousWorkouts)
                        } label: {
                            HStack {
                                Text("See previous workouts")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(previousWorkouts.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(14)
                            .background(Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Inline placeholder for when today is empty but earlier days have data.
    /// Distinct from the full emptyStateCard so the user sees today's gap at
    /// a glance without losing the previous-workouts entry point underneath.
    private var nothingTodayCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.title3)
                .foregroundStyle(.orange.opacity(0.6))
                .frame(width: 32)
            Text("No workouts logged today.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14))
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

    // MARK: - Daily section (v2.1a)
    //
    // Pushups + situps are append-style: each "Log" tap inserts a new
    // ExerciseRepEntry with the typed count. The big number shown above
    // each input is the SUM of today's non-soft-deleted entries of that
    // kind — "–" when zero entries today (nil ≠ 0 honesty).
    //
    // Stretch is binary: one StretchDay row per day. Tapping toggles. If
    // there's no row for today, the toggle creates one.

    private var todayRepEntries: [ExerciseRepEntry] {
        let cal = Calendar.current
        return allRepEntries.filter {
            cal.isDateInToday($0.loggedAt) && $0.pendingDeleteAt == nil
        }
    }

    private func todayCount(kind: String) -> Int {
        todayRepEntries.filter { $0.kind == kind }.reduce(0) { $0 + $1.count }
    }

    /// Sum string. Returns "–" when there are zero non-soft-deleted entries
    /// today (not "0") — the user requirement: an untracked count shows "–"
    /// not "0".
    private func todayDisplay(kind: String) -> String {
        let entries = todayRepEntries.filter { $0.kind == kind }
        guard !entries.isEmpty else { return "–" }
        return "\(entries.reduce(0) { $0 + $1.count })"
    }

    private var stretchedToday: Bool {
        let today = Calendar.current.startOfDay(for: .now)
        return allStretchDays.contains { Calendar.current.isDate($0.date, inSameDayAs: today) && $0.stretched }
    }

    private var dailySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Daily")
            VStack(spacing: 12) {
                repsCard(kind: "pushups", label: "Pushups", input: $pushupInput)
                repsCard(kind: "situps", label: "Situps", input: $situpInput)
                stretchCard
            }
        }
    }

    private func repsCard(kind: String, label: String, input: Binding<String>) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(label)
                    .font(.headline)
                Spacer()
                Button {
                    managingKind = kind
                } label: {
                    HStack(spacing: 4) {
                        Text(todayDisplay(kind: kind))
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(.orange)
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                TextField("Count", text: input)
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 10))

                Button {
                    logReps(kind: kind, input: input)
                } label: {
                    Text("Log")
                        .font(.callout.weight(.semibold))
                        .frame(width: 64)
                        .padding(.vertical, 10)
                        .background(.orange, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(parseRepCount(input.wrappedValue) == nil)
                .opacity(parseRepCount(input.wrappedValue) == nil ? 0.4 : 1)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private var stretchCard: some View {
        Button {
            toggleStretchToday()
        } label: {
            HStack {
                Text("Stretched today")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: stretchedToday ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(stretchedToday ? .green : .secondary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func parseRepCount(_ s: String) -> Int? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard let v = Int(trimmed), v > 0 else { return nil }
        return v
    }

    private func logReps(kind: String, input: Binding<String>) {
        guard let count = parseRepCount(input.wrappedValue) else { return }
        Haptic.light()
        let entry = ExerciseRepEntry(kind: kind, count: count, loggedAt: .now)
        context.insert(entry)
        input.wrappedValue = ""
        dismissKeyboard()
    }

    private func toggleStretchToday() {
        Haptic.light()
        let today = Calendar.current.startOfDay(for: .now)
        if let existing = allStretchDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
            existing.stretched.toggle()
        } else {
            // First tap today — create the row in the "stretched" state.
            context.insert(StretchDay(date: today, stretched: true))
        }
    }

    // MARK: - Strength section (v2.1a)

    private var activeSessions: [StrengthSession] {
        allStrengthSessions.filter { $0.pendingDeleteAt == nil }
    }

    private var strengthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Strength")
            VStack(spacing: 0) {
                strengthRow(
                    label: "Routines",
                    symbol: "list.bullet.rectangle.portrait",
                    color: .orange
                ) {
                    showingRoutines = true
                }
                Divider().padding(.leading, 48)
                strengthRow(
                    label: "Log a session",
                    symbol: "plus.square.fill",
                    color: .pink
                ) {
                    showingLogSession = true
                }
                Divider().padding(.leading, 48)
                strengthRow(
                    label: "History",
                    symbol: "clock.arrow.circlepath",
                    color: .blue,
                    trailing: "\(activeSessions.count) session\(activeSessions.count == 1 ? "" : "s")"
                ) {
                    showingHistory = true
                }
            }
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func strengthRow(
        label: String,
        symbol: String,
        color: Color,
        trailing: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 32)
                Text(label)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
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
