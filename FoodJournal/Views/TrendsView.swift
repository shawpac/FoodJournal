import SwiftUI
import SwiftData

struct TrendsView: View {
    @Query(sort: \FoodEntry.loggedAt, order: .reverse) private var allEntries: [FoodEntry]
    @Query(sort: \WaterEntry.loggedAt, order: .reverse) private var allWater: [WaterEntry]
    @Query(sort: \WeightEntry.loggedAt, order: .reverse) private var allWeights: [WeightEntry]
    @Query private var goalsList: [UserGoals]

    enum RangePreset: String, CaseIterable, Identifiable {
        case sevenDays = "7 days"
        case thirtyDays = "30 days"
        case custom = "Custom"
        var id: String { rawValue }
    }

    @State private var preset: RangePreset = .sevenDays
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    @State private var customEnd: Date = .now

    // MARK: - Range computation

    private var dateRange: (start: Date, end: Date) {
        let cal = Calendar.current
        let now = Date.now
        let endOfToday = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        switch preset {
        case .sevenDays:
            let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)) ?? now
            return (start, endOfToday)
        case .thirtyDays:
            let start = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: now)) ?? now
            return (start, endOfToday)
        case .custom:
            let endOfCustom = cal.date(bySettingHour: 23, minute: 59, second: 59, of: customEnd) ?? customEnd
            return (cal.startOfDay(for: customStart), endOfCustom)
        }
    }

    private var totalDays: Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: dateRange.start)
        let end = cal.startOfDay(for: dateRange.end)
        return (cal.dateComponents([.day], from: start, to: end).day ?? 0) + 1
    }

    private var entriesInRange: [FoodEntry] {
        allEntries.filter {
            $0.pendingDeleteAt == nil &&
            $0.loggedAt >= dateRange.start &&
            $0.loggedAt <= dateRange.end
        }
    }

    private var waterInRange: [WaterEntry] {
        allWater.filter {
            $0.pendingDeleteAt == nil &&
            $0.loggedAt >= dateRange.start &&
            $0.loggedAt <= dateRange.end
        }
    }

    private var weightsInRange: [WeightEntry] {
        allWeights.filter {
            $0.pendingDeleteAt == nil &&
            $0.loggedAt >= dateRange.start &&
            $0.loggedAt <= dateRange.end
        }
    }

    private var activeWeights: [WeightEntry] {
        allWeights.filter { $0.pendingDeleteAt == nil }
    }

    private var latestWeight: WeightEntry? {
        // allWeights is already sorted by loggedAt descending
        activeWeights.first
    }

    private var weightStat: Stat {
        let cal = Calendar.current
        // One value per calendar day; if multiple entries on a day, use the most recent.
        var byDay: [Date: (date: Date, value: Double)] = [:]
        for w in weightsInRange {
            let day = cal.startOfDay(for: w.loggedAt)
            if let existing = byDay[day] {
                if w.loggedAt > existing.date {
                    byDay[day] = (w.loggedAt, w.weightLbs)
                }
            } else {
                byDay[day] = (w.loggedAt, w.weightLbs)
            }
        }
        let n = byDay.count
        guard n > 0 else { return Stat(average: nil, daysWithData: 0, totalDays: totalDays) }
        let sum = byDay.values.reduce(0) { $0 + $1.value }
        return Stat(average: sum / Double(n), daysWithData: n, totalDays: totalDays)
    }

    /// Difference between the most recent weight in range and the earliest weight in range.
    /// Returns nil if fewer than 2 entries in range.
    private var weightDelta: Double? {
        let sorted = weightsInRange.sorted { $0.loggedAt < $1.loggedAt }
        guard sorted.count >= 2, let first = sorted.first, let last = sorted.last else { return nil }
        return last.weightLbs - first.weightLbs
    }

    private var hasAnyData: Bool {
        !entriesInRange.isEmpty || !waterInRange.isEmpty || !weightsInRange.isEmpty
    }

    private var hasFoodOrWaterData: Bool {
        !entriesInRange.isEmpty || !waterInRange.isEmpty
    }

    private var goals: UserGoals? { goalsList.first }

    // MARK: - Stat helpers
    // Each stat is (daily average, days with data, total days in range).
    // "Days with data" = count of distinct calendar days where at least one
    // entry has a non-nil value for the nutrient. Preserves nil ≠ 0.

    private struct Stat {
        let average: Double?
        let daysWithData: Int
        let totalDays: Int
        var hasPartialCoverage: Bool { daysWithData < totalDays }
    }

    private func averageRequired(_ keyPath: KeyPath<FoodEntry, Double>) -> Stat {
        let cal = Calendar.current
        var byDay: [Date: Double] = [:]
        for entry in entriesInRange {
            let day = cal.startOfDay(for: entry.loggedAt)
            byDay[day, default: 0] += entry[keyPath: keyPath] * entry.servings
        }
        let n = byDay.count
        guard n > 0 else { return Stat(average: nil, daysWithData: 0, totalDays: totalDays) }
        let sum = byDay.values.reduce(0, +)
        return Stat(average: sum / Double(n), daysWithData: n, totalDays: totalDays)
    }

    private func averageOptional(_ keyPath: KeyPath<FoodEntry, Double?>) -> Stat {
        let cal = Calendar.current
        var byDay: [Date: Double] = [:]
        for entry in entriesInRange {
            guard let v = entry[keyPath: keyPath] else { continue }
            let day = cal.startOfDay(for: entry.loggedAt)
            byDay[day, default: 0] += v * entry.servings
        }
        let n = byDay.count
        guard n > 0 else { return Stat(average: nil, daysWithData: 0, totalDays: totalDays) }
        let sum = byDay.values.reduce(0, +)
        return Stat(average: sum / Double(n), daysWithData: n, totalDays: totalDays)
    }

    private func averageWater() -> Stat {
        let cal = Calendar.current
        var byDay: [Date: Double] = [:]
        for entry in waterInRange {
            let day = cal.startOfDay(for: entry.loggedAt)
            byDay[day, default: 0] += entry.amountOz
        }
        let n = byDay.count
        guard n > 0 else { return Stat(average: nil, daysWithData: 0, totalDays: totalDays) }
        let sum = byDay.values.reduce(0, +)
        return Stat(average: sum / Double(n), daysWithData: n, totalDays: totalDays)
    }

    // MARK: - View

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Range", selection: $preset) {
                        ForEach(RangePreset.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)

                    if preset == .custom {
                        DatePicker("Start", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                        DatePicker("End", selection: $customEnd, in: customStart...Date.now, displayedComponents: .date)
                    }

                    HStack {
                        Text("Range covers")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(totalDays) day\(totalDays == 1 ? "" : "s")")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                // Weight section is always visible — it's its own entry point for
                // logging, independent of food/water data.
                Section("Weight") {
                    weightSummaryRows
                    NavigationLink {
                        WeightEntriesSheet()
                    } label: {
                        HStack {
                            Text("Manage entries")
                            Spacer()
                            Text("\(activeWeights.count) total")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !hasFoodOrWaterData {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 36))
                                .foregroundStyle(.tertiary)
                            Text("No food or water in this range")
                                .font(.headline)
                            Text("Try expanding the range, or log some food first.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section("Macros (daily average)") {
                        nutrientRow(label: "Calories", stat: averageRequired(\.calories), goal: goals?.calorieGoal, unit: "", asInt: true)
                        nutrientRow(label: "Protein", stat: averageRequired(\.protein), goal: goals?.proteinGoal, unit: "g")
                        nutrientRow(label: "Carbs", stat: averageRequired(\.carbs), goal: goals?.carbsGoal, unit: "g")
                        nutrientRow(label: "Fat", stat: averageRequired(\.fat), goal: goals?.fatGoal, unit: "g")
                    }

                    Section {
                        distributionRow("Breakfast", meal: "breakfast")
                        distributionRow("Lunch",     meal: "lunch")
                        distributionRow("Dinner",    meal: "dinner")
                        distributionRow("Snacks",    meal: "snack")
                    } header: {
                        Text("Distribution by meal")
                    } footer: {
                        Text("Share of each macro across the range, by meal. Helps spot patterns like \"most of my carbs are at dinner.\"")
                    }

                    Section("Water (daily average)") {
                        nutrientRow(label: "Water", stat: averageWater(), goal: goals?.waterGoalOz, unit: "oz", asInt: true)
                    }

                    Section("Carbs detail") {
                        nutrientRow(label: "Fiber", stat: averageOptional(\.fiber), goal: nil, unit: "g")
                        nutrientRow(label: "Sugar", stat: averageOptional(\.sugar), goal: nil, unit: "g")
                    }

                    Section("Fats detail") {
                        nutrientRow(label: "Saturated", stat: averageOptional(\.saturatedFat), goal: nil, unit: "g")
                        nutrientRow(label: "Polyunsaturated", stat: averageOptional(\.polyunsaturatedFat), goal: nil, unit: "g")
                        nutrientRow(label: "Monounsaturated", stat: averageOptional(\.monounsaturatedFat), goal: nil, unit: "g")
                        nutrientRow(label: "Trans", stat: averageOptional(\.transFat), goal: nil, unit: "g")
                    }

                    Section("Cholesterol & electrolytes") {
                        nutrientRow(label: "Cholesterol", stat: averageOptional(\.cholesterol), goal: nil, unit: "mg")
                        nutrientRow(label: "Sodium", stat: averageOptional(\.sodium), goal: nil, unit: "mg")
                        nutrientRow(label: "Potassium", stat: averageOptional(\.potassium), goal: nil, unit: "mg")
                    }

                    Section("Vitamins & minerals") {
                        nutrientRow(label: "Vitamin A", stat: averageOptional(\.vitaminA), goal: nil, unit: "µg")
                        nutrientRow(label: "Vitamin C", stat: averageOptional(\.vitaminC), goal: nil, unit: "mg")
                        nutrientRow(label: "Vitamin D", stat: averageOptional(\.vitaminD), goal: nil, unit: "µg")
                        nutrientRow(label: "Calcium", stat: averageOptional(\.calcium), goal: nil, unit: "mg")
                        nutrientRow(label: "Iron", stat: averageOptional(\.iron), goal: nil, unit: "mg")
                        nutrientRow(label: "Magnesium", stat: averageOptional(\.magnesium), goal: nil, unit: "mg")
                    }
                }
            }
            .navigationTitle("Trends")
        }
    }

    @ViewBuilder
    private func nutrientRow(label: String, stat: Stat, goal: Double?, unit: String, asInt: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                Spacer()
                if let avg = stat.average {
                    Text(formatValue(avg, asInt: asInt))
                        .font(.body.monospacedDigit())
                    if !unit.isEmpty {
                        Text(unit).foregroundStyle(.secondary)
                    }
                    if let goal {
                        Text("/ \(formatValue(goal, asInt: asInt))\(unit.isEmpty ? "" : " \(unit)")")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("–")
                        .foregroundStyle(.tertiary)
                }
            }

            if let avg = stat.average, let goal, goal > 0 {
                ProgressView(value: min(avg / goal, 1.0))
                    .tint(.orange)
            }

            if stat.hasPartialCoverage {
                Text("based on \(stat.daysWithData) of \(stat.totalDays) day\(stat.totalDays == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func formatValue(_ v: Double, asInt: Bool) -> String {
        if asInt {
            return "\(Int(v.rounded()))"
        }
        return FoodFormat.value(v)
    }

    // MARK: - Distribution by meal

    private struct MealDistribution {
        let cal: Double  // 0…100
        let p:   Double
        let c:   Double
        let f:   Double
    }

    private func mealDistribution(_ meal: String) -> MealDistribution {
        let mealEntries = entriesInRange.filter { $0.mealType == meal }
        let mealCal = mealEntries.reduce(0) { $0 + $1.calories * $1.servings }
        let mealP   = mealEntries.reduce(0) { $0 + $1.protein  * $1.servings }
        let mealC   = mealEntries.reduce(0) { $0 + $1.carbs    * $1.servings }
        let mealF   = mealEntries.reduce(0) { $0 + $1.fat      * $1.servings }

        let totalCal = entriesInRange.reduce(0) { $0 + $1.calories * $1.servings }
        let totalP   = entriesInRange.reduce(0) { $0 + $1.protein  * $1.servings }
        let totalC   = entriesInRange.reduce(0) { $0 + $1.carbs    * $1.servings }
        let totalF   = entriesInRange.reduce(0) { $0 + $1.fat      * $1.servings }

        func pct(_ part: Double, _ total: Double) -> Double {
            guard total > 0 else { return 0 }
            return (part / total) * 100
        }
        return MealDistribution(
            cal: pct(mealCal, totalCal),
            p:   pct(mealP,   totalP),
            c:   pct(mealC,   totalC),
            f:   pct(mealF,   totalF)
        )
    }

    @ViewBuilder
    private func distributionRow(_ label: String, meal: String) -> some View {
        let d = mealDistribution(meal)
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.semibold))
            HStack(spacing: 14) {
                pctChip("Cal", d.cal)
                pctChip("P",   d.p)
                pctChip("C",   d.c)
                pctChip("F",   d.f)
            }
        }
    }

    private func pctChip(_ label: String, _ pct: Double) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text("\(Int(pct.rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Weight summary rows

    @ViewBuilder
    private var weightSummaryRows: some View {
        HStack {
            Text("Latest")
            Spacer()
            if let w = latestWeight {
                Text(formatWeight(w.weightLbs))
                    .font(.body.monospacedDigit())
                Text("lbs").foregroundStyle(.secondary)
                Text(w.loggedAt, style: .date)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            } else {
                Text("–").foregroundStyle(.tertiary)
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Avg in range")
                Spacer()
                if let avg = weightStat.average {
                    Text(formatWeight(avg))
                        .font(.body.monospacedDigit())
                    Text("lbs").foregroundStyle(.secondary)
                } else {
                    Text("–").foregroundStyle(.tertiary)
                }
            }
            if weightStat.hasPartialCoverage, weightStat.daysWithData > 0 {
                Text("based on \(weightStat.daysWithData) of \(weightStat.totalDays) day\(weightStat.totalDays == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }

        if let delta = weightDelta {
            HStack {
                Text("Change in range")
                Spacer()
                Text(formatDelta(delta))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(deltaColor(delta))
                Text("lbs").foregroundStyle(.secondary)
            }
        }
    }

    private func formatWeight(_ v: Double) -> String {
        String(format: "%.1f", v)
    }

    private func formatDelta(_ v: Double) -> String {
        if v == 0 { return "±0.0" }
        let sign = v > 0 ? "+" : "−"
        return "\(sign)\(String(format: "%.1f", Swift.abs(v)))"
    }

    private func deltaColor(_ v: Double) -> Color {
        if v == 0 { return .gray }
        return v < 0 ? .green : .orange
    }
}

// MARK: - WeightEntriesSheet

struct WeightEntriesSheet: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WeightEntry.loggedAt, order: .reverse) private var allWeights: [WeightEntry]

    @State private var weightInput: String = ""
    @State private var dateInput: Date = .now

    @State private var undoMessage: String?
    @State private var pendingDeleteIDs: [PersistentIdentifier] = []
    @State private var undoTask: Task<Void, Never>?

    private var visibleWeights: [WeightEntry] {
        allWeights.filter { $0.pendingDeleteAt == nil }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Form {
                Section("Log weight") {
                    HStack {
                        TextField("Weight", text: $weightInput)
                            .keyboardType(.decimalPad)
                            .modifier(SelectAllOnFocus())
                        Text("lbs")
                            .foregroundStyle(.secondary)
                    }
                    DatePicker("When", selection: $dateInput, in: ...Date.now, displayedComponents: .date)
                    Button {
                        logWeight()
                    } label: {
                        Text("Save")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(parsedWeight == nil)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section("Entries") {
                    if visibleWeights.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "scalemass")
                                .foregroundStyle(.secondary)
                            Text("No weight entries yet.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(visibleWeights) { entry in
                            HStack {
                                Image(systemName: "scalemass.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(formatWeight(entry.weightLbs)) lbs")
                                        .font(.body.monospacedDigit())
                                    Text(entry.loggedAt, style: .date)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    softDelete(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }

            if let undoMessage {
                HStack(spacing: 12) {
                    Text(undoMessage)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Undo") { undoDelete() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.yellow)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: undoMessage)
        .navigationTitle("Weight")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { commitPendingDeletes() }
    }

    private var parsedWeight: Double? {
        let trimmed = weightInput.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value > 0 else { return nil }
        return value
    }

    private func logWeight() {
        guard let value = parsedWeight else { return }
        Haptic.light()
        dismissKeyboard()
        let entry = WeightEntry(weightLbs: value, loggedAt: dateInput)
        context.insert(entry)
        HealthSync.onWeightSaved(entry)
        weightInput = ""
        dateInput = .now
    }

    private func softDelete(_ entry: WeightEntry) {
        Haptic.medium()
        entry.pendingDeleteAt = .now
        pendingDeleteIDs.append(entry.persistentModelID)
        undoMessage = "Deleted \(formatWeight(entry.weightLbs)) lbs"

        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled { return }
            await MainActor.run { commitPendingDeletes() }
        }
    }

    private func undoDelete() {
        Haptic.light()
        undoTask?.cancel()
        for id in pendingDeleteIDs {
            if let entry = allWeights.first(where: { $0.persistentModelID == id }) {
                entry.pendingDeleteAt = nil
            }
        }
        pendingDeleteIDs.removeAll()
        undoMessage = nil
    }

    private func commitPendingDeletes() {
        undoTask?.cancel()
        for id in pendingDeleteIDs {
            if let entry = allWeights.first(where: { $0.persistentModelID == id }) {
                HealthSync.onWeightDeleting(entry)
                context.delete(entry)
            }
        }
        pendingDeleteIDs.removeAll()
        undoMessage = nil
    }

    private func formatWeight(_ v: Double) -> String {
        String(format: "%.1f", v)
    }
}
