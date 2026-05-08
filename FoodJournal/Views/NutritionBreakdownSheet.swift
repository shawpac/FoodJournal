import SwiftUI
import SwiftData

struct NutritionBreakdownSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodEntry.loggedAt, order: .reverse) private var allEntries: [FoodEntry]
    @Query private var goalsList: [UserGoals]

    /// The day this breakdown reflects. Defaults to today on construction so callers
    /// that don't pass a date keep working. v1.7.1 fix: TodayView's dailyTotalsCard
    /// now threads selectedDate so the breakdown matches what the rest of the Today
    /// tab is showing, and respects pendingDeleteAt so soft-deleted entries are
    /// excluded immediately.
    let selectedDate: Date

    init(selectedDate: Date = Calendar.current.startOfDay(for: .now)) {
        self.selectedDate = selectedDate
    }

    private var entriesForDay: [FoodEntry] {
        allEntries.filter {
            Calendar.current.isDate($0.loggedAt, inSameDayAs: selectedDate) &&
            $0.pendingDeleteAt == nil
        }
    }

    private var goals: UserGoals? { goalsList.first }

    private var sheetTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDate) { return "Today's nutrition" }
        if cal.isDateInYesterday(selectedDate) { return "Yesterday's nutrition" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "\(f.string(from: selectedDate)) — nutrition"
    }

    // Sums an optional Double field across the day's entries, multiplied by servings.
    // nil values contribute nothing. If NO entry has the field set, returns nil so
    // the row can display "-" instead of "0".
    private func dayTotal(_ keyPath: KeyPath<FoodEntry, Double?>) -> Double? {
        var anyValue = false
        var sum: Double = 0
        for entry in entriesForDay {
            if let val = entry[keyPath: keyPath] {
                anyValue = true
                sum += val * entry.servings
            }
        }
        return anyValue ? sum : nil
    }

    private func dayTotal(_ keyPath: KeyPath<FoodEntry, Double>) -> Double {
        entriesForDay.reduce(0) { $0 + $1[keyPath: keyPath] * $1.servings }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Energy") {
                    NutrientRow(label: "Calories",
                                value: dayTotal(\.calories),
                                goal: goals?.calorieGoal,
                                unit: "cal",
                                color: .orange)
                }

                Section("Macronutrients") {
                    NutrientRow(label: "Protein",
                                value: dayTotal(\.protein),
                                goal: goals?.proteinGoal,
                                unit: "g",
                                color: .red)
                    NutrientRow(label: "Carbohydrates",
                                value: dayTotal(\.carbs),
                                goal: goals?.carbsGoal,
                                unit: "g",
                                color: .blue)
                    NutrientRow(label: "Fiber",
                                value: dayTotal(\.fiber),
                                goal: goals?.fiberGoal,
                                unit: "g",
                                color: .green)
                    NutrientRow(label: "Sugar",
                                value: dayTotal(\.sugar),
                                goal: goals?.sugarGoal,
                                unit: "g",
                                color: .pink)
                }

                Section("Fats") {
                    NutrientRow(label: "Total Fat",
                                value: dayTotal(\.fat),
                                goal: goals?.fatGoal,
                                unit: "g",
                                color: .yellow)
                    NutrientRow(label: "Saturated",
                                value: dayTotal(\.saturatedFat),
                                goal: goals?.saturatedFatGoal,
                                unit: "g",
                                color: .yellow)
                    NutrientRow(label: "Polyunsaturated",
                                value: dayTotal(\.polyunsaturatedFat),
                                goal: goals?.polyunsaturatedFatGoal,
                                unit: "g",
                                color: .yellow)
                    NutrientRow(label: "Monounsaturated",
                                value: dayTotal(\.monounsaturatedFat),
                                goal: goals?.monounsaturatedFatGoal,
                                unit: "g",
                                color: .yellow)
                    NutrientRow(label: "Trans",
                                value: dayTotal(\.transFat),
                                goal: goals?.transFatGoal,
                                unit: "g",
                                color: .red,
                                lowerIsBetter: true)
                }

                Section("Cholesterol & Electrolytes") {
                    NutrientRow(label: "Cholesterol",
                                value: dayTotal(\.cholesterol),
                                goal: goals?.cholesterolGoal,
                                unit: "mg",
                                color: .purple,
                                lowerIsBetter: true)
                    NutrientRow(label: "Sodium",
                                value: dayTotal(\.sodium),
                                goal: goals?.sodiumGoal,
                                unit: "mg",
                                color: .purple,
                                lowerIsBetter: true)
                    NutrientRow(label: "Potassium",
                                value: dayTotal(\.potassium),
                                goal: goals?.potassiumGoal,
                                unit: "mg",
                                color: .purple)
                }

                Section("Vitamins & Minerals") {
                    NutrientRow(label: "Vitamin A",
                                value: dayTotal(\.vitaminA),
                                goal: goals?.vitaminAGoal,
                                unit: "µg",
                                color: .mint)
                    NutrientRow(label: "Vitamin C",
                                value: dayTotal(\.vitaminC),
                                goal: goals?.vitaminCGoal,
                                unit: "mg",
                                color: .mint)
                    NutrientRow(label: "Vitamin D",
                                value: dayTotal(\.vitaminD),
                                goal: goals?.vitaminDGoal,
                                unit: "µg",
                                color: .mint)
                    NutrientRow(label: "Calcium",
                                value: dayTotal(\.calcium),
                                goal: goals?.calciumGoal,
                                unit: "mg",
                                color: .indigo)
                    NutrientRow(label: "Iron",
                                value: dayTotal(\.iron),
                                goal: goals?.ironGoal,
                                unit: "mg",
                                color: .indigo)
                    NutrientRow(label: "Magnesium",
                                value: dayTotal(\.magnesium),
                                goal: goals?.magnesiumGoal,
                                unit: "mg",
                                color: .indigo)
                }
            }
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// One row in the breakdown.
// Pass nil for `value` if no entry has the field set → renders as "-".
// Pass nil for `goal` if there's no daily target → progress bar hidden.
// `lowerIsBetter` flips bar color (e.g. trans fat is good when low).
private struct NutrientRow: View {
    let label: String
    let value: Double?
    let goal: Double?
    let unit: String
    let color: Color
    var lowerIsBetter: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.body)
                Spacer()
                Text(rightText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let value, let goal, goal > 0 {
                ProgressView(value: progressFraction(value: value, goal: goal))
                    .tint(barColor(value: value, goal: goal))
            }
        }
        .padding(.vertical, 4)
    }

    private var rightText: String {
        guard let value else {
            if let goal { return "– / \(formatted(goal)) \(unit)" }
            return "–"
        }
        if let goal {
            return "\(formatted(value)) / \(formatted(goal)) \(unit)"
        }
        return "\(formatted(value)) \(unit)"
    }

    private func progressFraction(value: Double, goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return min(value / goal, 1)
    }

    private func barColor(value: Double, goal: Double) -> Color {
        if lowerIsBetter {
            return value > goal ? .red : color
        }
        return color
    }

    private func formatted(_ d: Double) -> String {
        FoodFormat.value(d)
    }
}
