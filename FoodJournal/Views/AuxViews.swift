import SwiftUI
import SwiftData

// MARK: - ConfirmFoodView (barcode + search results land here)
struct ConfirmFoodView: View {
    struct Prefill {
        var name: String
        var brand: String?
        var barcode: String?
        var caloriesPer100g: Double
        var proteinPer100g: Double
        var carbsPer100g: Double
        var fatPer100g: Double
        var servingSizeGrams: Double?
    }

    @Environment(\.modelContext) private var context
    let prefill: Prefill
    let source: String
    let onSaved: () -> Void

    @State private var grams: Double
    @State private var mealType = "snack"

    init(prefill: Prefill, source: String, onSaved: @escaping () -> Void) {
        self.prefill = prefill
        self.source = source
        self.onSaved = onSaved
        _grams = State(initialValue: prefill.servingSizeGrams ?? 100)
    }

    private var multiplier: Double { grams / 100 }
    private var calories: Double { prefill.caloriesPer100g * multiplier }
    private var protein:  Double { prefill.proteinPer100g  * multiplier }
    private var carbs:    Double { prefill.carbsPer100g    * multiplier }
    private var fat:      Double { prefill.fatPer100g      * multiplier }

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: prefill.name)
                if let brand = prefill.brand { LabeledContent("Brand", value: brand) }
            }

            Section("Serving") {
                HStack {
                    Text("Grams")
                    Spacer()
                    TextField("g", value: $grams, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                Picker("Meal", selection: $mealType) {
                    Text("Breakfast").tag("breakfast")
                    Text("Lunch").tag("lunch")
                    Text("Dinner").tag("dinner")
                    Text("Snack").tag("snack")
                }
            }

            Section("Nutrition for \(Int(grams))g") {
                LabeledContent("Calories", value: "\(Int(calories)) kcal")
                LabeledContent("Protein",  value: String(format: "%.1f g", protein))
                LabeledContent("Carbs",    value: String(format: "%.1f g", carbs))
                LabeledContent("Fat",      value: String(format: "%.1f g", fat))
            }

            Section {
                Button {
                    save()
                } label: {
                    Text("Add to journal").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    private func save() {
        let entry = FoodEntry(
            name: prefill.name,
            brand: prefill.brand,
            servings: 1,
            servingUnit: "\(Int(grams))g",
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            mealType: mealType,
            source: source,
            barcode: prefill.barcode
        )
        context.insert(entry)
        onSaved()
    }
}

// MARK: - ManualEntrySheet
struct ManualEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var calories: Double = 0
    @State private var protein:  Double = 0
    @State private var carbs:    Double = 0
    @State private var fat:      Double = 0
    @State private var mealType = "snack"

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name", text: $name)
                }
                Section("Macros (per serving)") {
                    macroField("Calories", value: $calories, suffix: "kcal")
                    macroField("Protein",  value: $protein,  suffix: "g")
                    macroField("Carbs",    value: $carbs,    suffix: "g")
                    macroField("Fat",      value: $fat,      suffix: "g")
                }
                Section {
                    Picker("Meal", selection: $mealType) {
                        Text("Breakfast").tag("breakfast")
                        Text("Lunch").tag("lunch")
                        Text("Dinner").tag("dinner")
                        Text("Snack").tag("snack")
                    }
                }
            }
            .navigationTitle("Manual entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty)
                }
            }
        }
    }

    private func macroField(_ label: String, value: Binding<Double>, suffix: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(suffix).foregroundStyle(.secondary)
        }
    }

    private func save() {
        let entry = FoodEntry(
            name: name,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            mealType: mealType,
            source: "manual"
        )
        context.insert(entry)
        dismiss()
    }
}

// MARK: - SettingsView
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var goalsList: [UserGoals]

    @State private var apiKey = ""
    @State private var calorieGoal: Double = 2000
    @State private var proteinGoal: Double = 150
    @State private var carbsGoal:   Double = 200
    @State private var fatGoal:     Double = 65
    @State private var waterGoalOz: Double = 100
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily goals") {
                    goalField("Calories", value: $calorieGoal, suffix: "kcal")
                    goalField("Protein",  value: $proteinGoal, suffix: "g")
                    goalField("Carbs",    value: $carbsGoal,   suffix: "g")
                    goalField("Fat",      value: $fatGoal,     suffix: "g")
                    goalField("Water",    value: $waterGoalOz, suffix: "oz")
                }

                Section {
                    SecureField("sk-ant-…", text: $apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !apiKey.isEmpty {
                        Text("Key length: \(apiKey.count) chars, starts with: \(String(apiKey.prefix(7)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Anthropic API key")
                } footer: {
                    Text("Stored in Keychain. Required for photo-based logging. Get one at console.anthropic.com.")
                }

                Section {
                    Button("Save") { save() }
                        .frame(maxWidth: .infinity)
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.callout)
                            .foregroundStyle(statusMessage.hasPrefix("✓") ? .green : .red)
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                apiKey = KeychainStore.loadAPIKey()
                if let g = goalsList.first {
                    calorieGoal = g.calorieGoal
                    proteinGoal = g.proteinGoal
                    carbsGoal   = g.carbsGoal
                    fatGoal     = g.fatGoal
                    waterGoalOz = g.waterGoalOz
                }
            }
        }
    }

    private func goalField(_ label: String, value: Binding<Double>, suffix: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(suffix).foregroundStyle(.secondary)
        }
    }

    private func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = KeychainStore.saveAPIKey(trimmed)

        // Verify by reading it back immediately
        let readBack = KeychainStore.loadAPIKey()

        if status == errSecSuccess && readBack == trimmed && !trimmed.isEmpty {
            statusMessage = "✓ Saved \(trimmed.count) chars"
        } else if trimmed.isEmpty {
            statusMessage = "✗ Key field is empty"
        } else {
            statusMessage = "✗ Save failed (status \(status), read-back length \(readBack.count))"
        }

        if let g = goalsList.first {
            g.calorieGoal = calorieGoal
            g.proteinGoal = proteinGoal
            g.carbsGoal   = carbsGoal
            g.fatGoal     = fatGoal
            g.waterGoalOz = waterGoalOz
        } else {
            context.insert(UserGoals(
                calorieGoal: calorieGoal,
                proteinGoal: proteinGoal,
                carbsGoal:   carbsGoal,
                fatGoal:     fatGoal,
                waterGoalOz: waterGoalOz
            ))
        }
    }
}
// MARK: - RelogSheet (used by Recents quick-log)
struct RelogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let template: FoodEntry
    @State private var servings: Double
    @State private var mealType: String

    init(template: FoodEntry) {
        self.template = template
        _servings = State(initialValue: template.servings)
        _mealType = State(initialValue: template.mealType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Name", value: template.name)
                    if let brand = template.brand {
                        LabeledContent("Brand", value: brand)
                    }
                }

                Section("Servings") {
                    HStack {
                        Text("Servings (\(template.servingUnit))")
                        Spacer()
                        TextField("", value: $servings, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    Picker("Meal", selection: $mealType) {
                        Text("Breakfast").tag("breakfast")
                        Text("Lunch").tag("lunch")
                        Text("Dinner").tag("dinner")
                        Text("Snack").tag("snack")
                    }
                }

                Section("Nutrition for \(formatted(servings)) \(template.servingUnit)") {
                    LabeledContent("Calories", value: "\(Int(template.calories * servings)) kcal")
                    LabeledContent("Protein",  value: String(format: "%.1f g", template.protein * servings))
                    LabeledContent("Carbs",    value: String(format: "%.1f g", template.carbs * servings))
                    LabeledContent("Fat",      value: String(format: "%.1f g", template.fat * servings))
                }
            }
            .navigationTitle("Re-log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { save() }
                        .disabled(servings <= 0)
                }
            }
        }
    }

    private func formatted(_ d: Double) -> String {
        d.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(d))
            : String(format: "%.1f", d)
    }

    private func save() {
        let entry = FoodEntry(
            name: template.name,
            brand: template.brand,
            servings: servings,
            servingUnit: template.servingUnit,
            calories: template.calories,
            protein: template.protein,
            carbs: template.carbs,
            fat: template.fat,
            mealType: mealType,
            source: template.source,
            barcode: template.barcode
        )
        context.insert(entry)
        dismiss()
    }
}
