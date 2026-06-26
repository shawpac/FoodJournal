import SwiftUI
import SwiftData
import Charts

/// v2.1b — Per-exercise strength progress. Reads the existing v2.1a models
/// (StrengthSession → LoggedExercise → LoggedSet) without any new schema.
///
/// Two trends per session, computed INDEPENDENTLY:
///   • **Top set weight**: max `weightLbs` among the exercise's sets in
///     that session (sets with nil weight are excluded). Answers "is the
///     weight going up."
///   • **Estimated 1RM** (Epley): max of `weight × (1 + reps/30)` across
///     sets with BOTH non-nil weight AND non-nil reps. Normalizes across
///     rep ranges so 135×8 and 145×3 are comparable.
///
/// The "top set" and "top e1RM" sets within one session may be different
/// sets — they are NOT derived from a single chosen set.
///
/// Honesty rules:
///   • e1RM is always labeled "est." — never presented as a logged number.
///   • Raw sets per session are listed under the charts so the actual lifted
///     numbers are never hidden behind the estimate.
///   • Sets with nil weight or nil reps appear in the raw list ("135 × –")
///     but are excluded from the math.
///   • 0 sessions → empty state. 1 session → single data point + caption
///     "Need 2+ sessions to show a trend." No drawn line.
///   • Gaps between sessions are real — never interpolated or filled with 0.
struct StrengthTrendsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \StrengthSession.loggedAt, order: .reverse)
    private var allSessions: [StrengthSession]

    /// User-picked exercise name. Lower-case-fold on match so "Bench Press"
    /// and "bench press" group together; display the most recent casing.
    @State private var selectedExerciseName: String?

    private var visibleSessions: [StrengthSession] {
        allSessions.filter { $0.pendingDeleteAt == nil }
    }

    /// Distinct exercise names across all visible sessions. Dedupe by
    /// lower-case-folded name; the display value is the most recent casing
    /// the user used.
    private var exerciseNames: [String] {
        var byKey: [String: (name: String, when: Date)] = [:]
        for session in visibleSessions {
            for ex in session.exercises {
                let key = ex.name.lowercased().trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { continue }
                if let prior = byKey[key] {
                    if session.loggedAt > prior.when {
                        byKey[key] = (ex.name, session.loggedAt)
                    }
                } else {
                    byKey[key] = (ex.name, session.loggedAt)
                }
            }
        }
        return byKey.values.map(\.name).sorted { $0.lowercased() < $1.lowercased() }
    }

    var body: some View {
        NavigationStack {
            Group {
                if exerciseNames.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("Strength trends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if selectedExerciseName == nil {
                    selectedExerciseName = exerciseNames.first
                }
            }
        }
    }

    // MARK: - Empty state (no logged sessions at all)

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No strength data yet")
                .font(.headline)
            Text("Log some strength sessions to see progress here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Content (≥ 1 exercise has data)

    private var content: some View {
        Form {
            Section {
                Picker("Exercise", selection: $selectedExerciseName) {
                    ForEach(exerciseNames, id: \.self) { name in
                        Text(name).tag(String?.some(name))
                    }
                }
                .pickerStyle(.menu)
            }

            if let selectedExerciseName,
               let stats = statsForSelected(selectedExerciseName) {
                summarySection(stats: stats)
                chartsSection(stats: stats)
                rawSetsSection(stats: stats)
            }
        }
    }

    // MARK: - Summary (last vs previous)

    @ViewBuilder
    private func summarySection(stats: [ExerciseSessionStat]) -> some View {
        Section {
            if stats.count == 1 {
                summaryRow(label: "Top set",
                           value: stats[0].topWeight.map(weightString) ?? "–",
                           delta: nil)
                summaryRow(label: "Est. 1RM",
                           value: stats[0].topE1RM.map(weightString) ?? "–",
                           delta: nil)
            } else if let last = stats.last, stats.count >= 2 {
                let prior = stats[stats.count - 2]
                summaryRow(label: "Top set",
                           value: last.topWeight.map(weightString) ?? "–",
                           delta: delta(last.topWeight, prior.topWeight))
                summaryRow(label: "Est. 1RM",
                           value: last.topE1RM.map(weightString) ?? "–",
                           delta: delta(last.topE1RM, prior.topE1RM))
            }
        } header: {
            Text("Latest session")
        } footer: {
            if stats.count == 1 {
                Text("Need 2+ sessions to show a trend.")
            } else if let last = stats.last {
                Text("Compared to the previous session on \(formatDate(prevSessionDate(stats: stats) ?? last.date)).")
            }
        }
    }

    private func summaryRow(label: String, value: String, delta: DeltaInfo?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
            if let delta {
                HStack(spacing: 2) {
                    Image(systemName: delta.symbol)
                        .font(.caption2.weight(.semibold))
                    Text(delta.text)
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(delta.color)
            } else {
                Text("–")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private struct DeltaInfo {
        let symbol: String
        let text: String
        let color: Color
    }

    private func delta(_ current: Double?, _ prior: Double?) -> DeltaInfo? {
        guard let current, let prior else { return nil }
        let diff = current - prior
        if diff == 0 {
            return DeltaInfo(symbol: "minus", text: "0", color: .secondary)
        } else if diff > 0 {
            return DeltaInfo(symbol: "arrow.up", text: "+\(weightString(diff))", color: .green)
        } else {
            return DeltaInfo(symbol: "arrow.down", text: weightString(diff), color: .orange)
        }
    }

    private func prevSessionDate(stats: [ExerciseSessionStat]) -> Date? {
        guard stats.count >= 2 else { return nil }
        return stats[stats.count - 2].date
    }

    // MARK: - Charts

    @ViewBuilder
    private func chartsSection(stats: [ExerciseSessionStat]) -> some View {
        let weightPoints = stats.compactMap { stat -> (Date, Double)? in
            guard let w = stat.topWeight else { return nil }
            return (stat.date, w)
        }
        let e1rmPoints = stats.compactMap { stat -> (Date, Double)? in
            guard let v = stat.topE1RM else { return nil }
            return (stat.date, v)
        }

        Section {
            chartView(title: "Top set weight",
                      points: weightPoints,
                      yLabel: "lbs",
                      lineColor: .orange,
                      drawLine: weightPoints.count >= 2)
            chartView(title: "Est. 1RM (Epley)",
                      points: e1rmPoints,
                      yLabel: "lbs",
                      lineColor: .blue,
                      drawLine: e1rmPoints.count >= 2)
        } header: {
            Text("Trends")
        } footer: {
            Text("Est. 1RM is calculated as weight × (1 + reps / 30). It's an estimate, not a lifted weight. Sets with no weight or reps are excluded from these numbers but still shown raw below.")
        }
    }

    @ViewBuilder
    private func chartView(
        title: String,
        points: [(Date, Double)],
        yLabel: String,
        lineColor: Color,
        drawLine: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if points.isEmpty {
                Text("No data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else if !drawLine {
                // One point only — show the value without a trend line that
                // would imply a slope from a single sample.
                HStack {
                    Text(points[0].0, format: Date.FormatStyle(date: .abbreviated))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(weightString(points[0].1)) \(yLabel)")
                        .font(.body.monospacedDigit())
                }
                .padding(.vertical, 8)
                Text("Need 2+ sessions to show a trend.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Chart {
                    ForEach(points, id: \.0) { pt in
                        LineMark(
                            x: .value("Date", pt.0),
                            y: .value(yLabel, pt.1)
                        )
                        .foregroundStyle(lineColor)
                        PointMark(
                            x: .value("Date", pt.0),
                            y: .value(yLabel, pt.1)
                        )
                        .foregroundStyle(lineColor)
                    }
                }
                .frame(height: 140)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Raw sets

    @ViewBuilder
    private func rawSetsSection(stats: [ExerciseSessionStat]) -> some View {
        Section {
            // Render newest first to match History's UX.
            ForEach(Array(stats.reversed().enumerated()), id: \.offset) { _, stat in
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatDate(stat.date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    let setLine = stat.sets
                        .sorted { $0.setNumber < $1.setNumber }
                        .map(rawSetString)
                        .joined(separator: ", ")
                    Text(setLine.isEmpty ? "No sets recorded." : setLine)
                        .font(.body.monospacedDigit())
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Raw sets")
        } footer: {
            Text("Actual logged sets per session. Sets with missing weight or reps display as \"— × N\" or \"N × —\" and don't contribute to the trend math.")
        }
    }

    /// "135 × 8" / "135 × –" / "– × 8" / "–"
    private func rawSetString(_ s: LoggedSet) -> String {
        let w = s.weightLbs.map(weightString) ?? "–"
        let r = s.reps.map { "\($0)" } ?? "–"
        if w == "–" && r == "–" { return "–" }
        return "\(w) × \(r)"
    }

    // MARK: - Stat extraction

    /// One row of trend data per session containing the selected exercise.
    /// Sorted chronologically (oldest first) so the chart's X axis advances
    /// left-to-right.
    private struct ExerciseSessionStat {
        let date: Date
        let topWeight: Double?
        let topE1RM: Double?
        let sets: [LoggedSet]
    }

    /// Returns sorted ascending by date, nil if the selected name has no
    /// matches.
    private func statsForSelected(_ name: String) -> [ExerciseSessionStat]? {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        var stats: [ExerciseSessionStat] = []
        for session in visibleSessions {
            // Pick the session's exercise(s) matching this name. Usually one
            // per session; if a user double-added the same exercise we union
            // their sets so the math still uses everything.
            let matching = session.exercises.filter {
                $0.name.lowercased().trimmingCharacters(in: .whitespaces) == key
            }
            guard !matching.isEmpty else { continue }
            let allSets = matching.flatMap { $0.sets }
            guard !allSets.isEmpty else { continue }

            // Top weight: max non-nil weightLbs.
            let topWeight = allSets.compactMap(\.weightLbs).max()
            // Top e1RM (Epley): max over sets with BOTH non-nil. Computed
            // independently — the "top weight" set and the "top e1RM" set
            // may be DIFFERENT sets, per spec.
            let topE1RM = allSets.compactMap { set -> Double? in
                guard let w = set.weightLbs, let r = set.reps else { return nil }
                return w * (1.0 + Double(r) / 30.0)
            }.max()

            // Include the session even if both stats are nil — the user may
            // have logged sets with neither weight nor reps; the raw list
            // surfaces them and the chart filters via compactMap.
            stats.append(ExerciseSessionStat(
                date: session.loggedAt,
                topWeight: topWeight,
                topE1RM: topE1RM,
                sets: allSets
            ))
        }
        guard !stats.isEmpty else { return nil }
        return stats.sorted { $0.date < $1.date }
    }

    // MARK: - Formatters

    /// "135" / "147.5" — trim trailing zero, keep one decimal for fractional
    /// loads (5-lb microplates, kilo-converted users).
    private func weightString(_ w: Double) -> String {
        if w.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(w))"
        }
        return String(format: "%.1f", w)
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: d)
    }
}
