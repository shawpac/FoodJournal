import SwiftUI
import SwiftData

struct NutrientGoalsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var goalsList: [UserGoals]

    // Optional goals — nil means "no daily target, just show running total."
    @State private var fiberStr = ""
    @State private var sugarStr = ""
    @State private var saturatedFatStr = ""
    @State private var polyunsaturatedFatStr = ""
    @State private var monounsaturatedFatStr = ""
    @State private var transFatStr = ""
    @State private var cholesterolStr = ""
    @State private var sodiumStr = ""
    @State private var potassiumStr = ""
    @State private var vitaminAStr = ""
    @State private var vitaminCStr = ""
    @State private var vitaminDStr = ""
    @State private var calciumStr = ""
    @State private var ironStr = ""
    @State private var magnesiumStr = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Leave any field blank for **no daily target** — that nutrient will show running totals only, with no progress bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Carbs detail") {
                    goalField("Fiber", text: $fiberStr, suffix: "g")
                    goalField("Sugar", text: $sugarStr, suffix: "g")
                }

                Section("Fats detail") {
                    goalField("Saturated",       text: $saturatedFatStr,       suffix: "g")
                    goalField("Polyunsaturated", text: $polyunsaturatedFatStr, suffix: "g")
                    goalField("Monounsaturated", text: $monounsaturatedFatStr, suffix: "g")
                    goalField("Trans",           text: $transFatStr,           suffix: "g")
                }

                Section("Cholesterol & electrolytes") {
                    goalField("Cholesterol", text: $cholesterolStr, suffix: "mg")
                    goalField("Sodium",      text: $sodiumStr,      suffix: "mg")
                    goalField("Potassium",   text: $potassiumStr,   suffix: "mg")
                }

                Section("Vitamins & minerals") {
                    goalField("Vitamin A", text: $vitaminAStr, suffix: "µg")
                    goalField("Vitamin C", text: $vitaminCStr, suffix: "mg")
                    goalField("Vitamin D", text: $vitaminDStr, suffix: "µg")
                    goalField("Calcium",   text: $calciumStr,  suffix: "mg")
                    goalField("Iron",      text: $ironStr,     suffix: "mg")
                    goalField("Magnesium", text: $magnesiumStr, suffix: "mg")
                }
            }
            .navigationTitle("Nutrient goals")
            .navigationBarTitleDisplayMode(.inline)
            .selectAllOnFocus()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
            }
            .onAppear { loadFromGoals() }
        }
    }

    private func goalField(_ label: String, text: Binding<String>, suffix: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("–", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(suffix).foregroundStyle(.secondary)
        }
    }

    private func loadFromGoals() {
        guard let g = goalsList.first else { return }
        fiberStr               = optStr(g.fiberGoal)
        sugarStr               = optStr(g.sugarGoal)
        saturatedFatStr        = optStr(g.saturatedFatGoal)
        polyunsaturatedFatStr  = optStr(g.polyunsaturatedFatGoal)
        monounsaturatedFatStr  = optStr(g.monounsaturatedFatGoal)
        transFatStr            = optStr(g.transFatGoal)
        cholesterolStr         = optStr(g.cholesterolGoal)
        sodiumStr              = optStr(g.sodiumGoal)
        potassiumStr           = optStr(g.potassiumGoal)
        vitaminAStr            = optStr(g.vitaminAGoal)
        vitaminCStr            = optStr(g.vitaminCGoal)
        vitaminDStr            = optStr(g.vitaminDGoal)
        calciumStr             = optStr(g.calciumGoal)
        ironStr                = optStr(g.ironGoal)
        magnesiumStr           = optStr(g.magnesiumGoal)
    }

    private func save() {
        dismissKeyboard()
        Haptic.light()

        // If for some reason there's no UserGoals record yet, create one.
        let g: UserGoals = {
            if let existing = goalsList.first { return existing }
            let new = UserGoals()
            context.insert(new)
            return new
        }()

        g.fiberGoal              = parseOptional(fiberStr)
        g.sugarGoal              = parseOptional(sugarStr)
        g.saturatedFatGoal       = parseOptional(saturatedFatStr)
        g.polyunsaturatedFatGoal = parseOptional(polyunsaturatedFatStr)
        g.monounsaturatedFatGoal = parseOptional(monounsaturatedFatStr)
        g.transFatGoal           = parseOptional(transFatStr)
        g.cholesterolGoal        = parseOptional(cholesterolStr)
        g.sodiumGoal             = parseOptional(sodiumStr)
        g.potassiumGoal          = parseOptional(potassiumStr)
        g.vitaminAGoal           = parseOptional(vitaminAStr)
        g.vitaminCGoal           = parseOptional(vitaminCStr)
        g.vitaminDGoal           = parseOptional(vitaminDStr)
        g.calciumGoal            = parseOptional(calciumStr)
        g.ironGoal               = parseOptional(ironStr)
        g.magnesiumGoal          = parseOptional(magnesiumStr)

        dismiss()
    }

    /// Format an optional Double for display in a String-backed field.
    /// Empty string for nil; integer if whole; one decimal otherwise.
    private func optStr(_ d: Double?) -> String {
        guard let d else { return "" }
        if d.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(d))
        }
        return String(format: "%.1f", d)
    }

    private func parseOptional(_ s: String) -> Double? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        return Double(trimmed)
    }
}
