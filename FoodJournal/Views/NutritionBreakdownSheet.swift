import SwiftUI
import SwiftData

struct NutritionBreakdownSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodEntry.loggedAt, order: .reverse) private var allEntries: [FoodEntry]
    @Query private var goalsList: [UserGoals]

    private var todayEntries: [FoodEntry] {
        allEntries.filter { Calendar.current.isDateInToday($0.loggedAt) }
    }

    private var goals: UserGoals? { goalsList.first }

    // Sums an optional Double field across today's entries, multiplied by servings.
    // nil values contribute nothing. If NO entry has the field set, returns nil so
    // the row can display "-" instead of "0".
    private func todayTotal(_ keyPath: KeyPath<FoodEntry, Double?>) -> Double? {
        var anyValue = false
        var sum: Double = 0
        for entry in todayEntries {
            if let val = entry[keyPath: keyPath] {
                anyValue = true
                sum += val * entry.servings
            }
        }
        return anyValue ? sum : nil
    }

    private func todayTotal(_ keyPath: KeyPath<FoodEntry, Double>) -> Double {
        todayEntries.reduce(0) { $0 + $1[keyPath: keyPath] * $1.servings }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Energy") {
                    NutrientRow(label: "Calories",
                                value: todayTotal(\.calories),
                                goal: goals?.calorieGoal,
                                unit: "cal",
                                color: .orange)
                }

                Section("Macronutrients") {
                    NutrientRow(label: "Protein",
                                value: todayTotal(\.protein),
                                goal: goals?.proteinGoal,
                                unit: "g",
                                color: .red)
                    NutrientRow(label: "Carbohydrates",
                                value: todayTotal(\.carbs),
                                goal: goals?.carbsGoal,
                                unit: "g",
                                color: .blue)
                    NutrientRow(label: "Fiber",
                                value: todayTotal(\.fiber),
                                goal: goals?.fiberGoal,
                                unit: "g",
                                color: .green)
                    NutrientRow(label: "Sugar",
                                value: todayTotal(\.sugar),
                                goal: goals?.sugarGoal,
                                unit: "g",
                                color: .pink)
                }

                Section("Fats") {
                    NutrientRow(label: "Total Fat",
                                value: todayTotal(\.fat),
                                goal: goals?.fatGoal,
                                unit: "g",
                                color: .yellow)
                    NutrientRow(label: "Saturated",
                                value: todayTotal(\.saturatedFat),
                                goal: goals?.saturatedFatGoal,
                                unit: "g",
                                color: .yellow)
                    NutrientRow(label: "Polyunsaturated",
                                value: todayTotal(\.polyunsaturatedFat),
                                goal: goals?.polyunsaturatedFatGoal,
                                unit: "g",
                                color: .yellow)
                    NutrientRow(label: "Monounsaturated",
                                value: todayTotal(\.monounsaturatedFat),
                                goal: goals?.monounsaturatedFatGoal,
                                unit: "g",
                                color: .yellow)
                    NutrientRow(label: "Trans",
                                value: todayTotal(\.transFat),
                                goal: goals?.transFatGoal,
                                unit: "g",
                                color: .red,
                                lowerIsBetter: true)
                }

                Section("Cholesterol & Electrolytes") {
                    NutrientRow(label: "Cholesterol",
                                value: todayTotal(\.cholesterol),
                                goal: goals?.cholesterolGoal,
                                unit: "mg",
                                color: .purple,
                                lowerIsBetter: true)
                    NutrientRow(label: "Sodium",
                                value: todayTotal(\.sodium),
                                goal: goals?.sodiumGoal,
                                unit: "mg",
                                color: .purple,
                                lowerIsBetter: true)
                    NutrientRow(label: "Potassium",
                                value: todayTotal(\.potassium),
                                goal: goals?.potassiumGoal,
                                unit: "mg",
                                color: .purple)
                }

                Section("Vitamins & Minerals") {
                    NutrientRow(label: "Vitamin A",
                                value: todayTotal(\.vitaminA),
                                goal: goals?.vitaminAGoal,
                                unit: "µg",
                                color: .mint)
                    NutrientRow(label: "Vitamin C",
                                value: todayTotal(\.vitaminC),
                                goal: goals?.vitaminCGoal,
                                unit: "mg",
                                color: .mint)
                    NutrientRow(label: "Vitamin D",
                                value: todayTotal(\.vitaminD),
                                goal: goals?.vitaminDGoal,
                                unit: "µg",
                                color: .mint)
                    NutrientRow(label: "Calcium",
                                value: todayTotal(\.calcium),
                                goal: goals?.calciumGoal,
                                unit: "mg",
                                color: .indigo)
                    NutrientRow(label: "Iron",
                                value: todayTotal(\.iron),
                                goal: goals?.ironGoal,
                                unit: "mg",
                                color: .indigo)
                    NutrientRow(label: "Magnesium",
                                value: todayTotal(\.magnesium),
                                goal: goals?.magnesiumGoal,
                                unit: "mg",
                                color: .indigo)
                }
            }
            .navigationTitle("Today's nutrition")
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
// Pass nil for `value` if no entry today has the field at all → renders as "-".
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
