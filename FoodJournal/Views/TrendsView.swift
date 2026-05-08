import SwiftUI
import SwiftData

struct TrendsView: View {
    @Query(sort: \FoodEntry.loggedAt, order: .reverse) private var allEntries: [FoodEntry]
    @Query(sort: \WaterEntry.loggedAt, order: .reverse) private var allWater: [WaterEntry]
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
            $0.loggedAt >= dateRange.start &&
            $0.loggedAt <= dateRange.end
        }
    }

    private var hasAnyData: Bool {
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

                if !hasAnyData {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 36))
                                .foregroundStyle(.tertiary)
                            Text("No data in this range")
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
}
