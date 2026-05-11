import SwiftUI
import SwiftData
import UIKit

/// Lightweight haptic feedback helper. Avoids us having to construct a generator at each call site.
enum Haptic {
    /// Light tap — for incremental actions like logging water.
    static func light() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.impactOccurred()
    }

    /// Medium tap — for destructive actions like deletion.
    static func medium() {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.impactOccurred()
    }

    /// Success notification — distinctive triple-tap pattern, perfect for "logged!"
    static func success() {
        let g = UINotificationFeedbackGenerator()
        g.notificationOccurred(.success)
    }
}

extension View {
    func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}

/// Selects all text in a TextField when it gains focus.
/// Apply with .selectAllOnFocus() on any TextField.
struct SelectAllOnFocus: ViewModifier {
    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { notification in
            guard let textField = notification.object as? UITextField else { return }
            DispatchQueue.main.async {
                textField.selectAll(nil)
            }
        }
    }
}

extension View {
    func selectAllOnFocus() -> some View {
        self.modifier(SelectAllOnFocus())
    }
}

// MARK: - ConfirmFoodView (barcode + search results land here)
struct ConfirmFoodView: View {
    struct Prefill {
        var name: String
        var brand: String?
        var barcode: String?
        var servingSizeGrams: Double?

        var caloriesPer100g: Double
        var proteinPer100g: Double
        var carbsPer100g: Double
        var fatPer100g: Double

        var saturatedFatPer100g: Double?
        var polyunsaturatedFatPer100g: Double?
        var monounsaturatedFatPer100g: Double?
        var transFatPer100g: Double?
        var fiberPer100g: Double?
        var sugarPer100g: Double?
        var cholesterolPer100g: Double?
        var sodiumPer100g: Double?
        var potassiumPer100g: Double?
        var vitaminAPer100g: Double?
        var vitaminCPer100g: Double?
        var vitaminDPer100g: Double?
        var calciumPer100g: Double?
        var ironPer100g: Double?
        var magnesiumPer100g: Double?
    }

    @Environment(\.modelContext) private var context
    let prefill: Prefill
        let source: String
        let defaultMeal: String?
        let defaultDate: Date?
        let onSaved: () -> Void

        @State private var grams: Double
        @State private var mealType: String
        @State private var showingLateSnackAlert = false

        init(prefill: Prefill, source: String, defaultMeal: String? = nil, defaultDate: Date? = nil, onSaved: @escaping () -> Void) {
            self.prefill = prefill
            self.source = source
            self.defaultMeal = defaultMeal
            self.defaultDate = defaultDate
            self.onSaved = onSaved
            _grams = State(initialValue: prefill.servingSizeGrams ?? 100)
            _mealType = State(initialValue: defaultMeal ?? MealTimeHelper.mealType())
        }

    private var multiplier: Double { grams / 100 }

    private func scaled(_ per100g: Double) -> Double { per100g * multiplier }
    private func scaled(_ per100g: Double?) -> Double? {
        guard let v = per100g else { return nil }
        return v * multiplier
    }

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
                row("Calories", scaled(prefill.caloriesPer100g),    unit: "", asInt: true)
                row("Protein",  scaled(prefill.proteinPer100g),     unit: "g")
                row("Carbs",    scaled(prefill.carbsPer100g),       unit: "g")
                row("Fat",      scaled(prefill.fatPer100g),         unit: "g")
                optionalRow("Saturated",       scaled(prefill.saturatedFatPer100g),       unit: "g")
                optionalRow("Polyunsaturated", scaled(prefill.polyunsaturatedFatPer100g), unit: "g")
                optionalRow("Monounsaturated", scaled(prefill.monounsaturatedFatPer100g), unit: "g")
                optionalRow("Trans",           scaled(prefill.transFatPer100g),           unit: "g")
                optionalRow("Fiber",           scaled(prefill.fiberPer100g),              unit: "g")
                optionalRow("Sugar",           scaled(prefill.sugarPer100g),              unit: "g")
                optionalRow("Cholesterol",     scaled(prefill.cholesterolPer100g),        unit: "mg")
                optionalRow("Sodium",          scaled(prefill.sodiumPer100g),             unit: "mg")
                optionalRow("Potassium",       scaled(prefill.potassiumPer100g),          unit: "mg")
                optionalRow("Vitamin A",       scaled(prefill.vitaminAPer100g),           unit: "µg")
                optionalRow("Vitamin C",       scaled(prefill.vitaminCPer100g),           unit: "mg")
                optionalRow("Vitamin D",       scaled(prefill.vitaminDPer100g),           unit: "µg")
                optionalRow("Calcium",         scaled(prefill.calciumPer100g),            unit: "mg")
                optionalRow("Iron",            scaled(prefill.ironPer100g),               unit: "mg")
                optionalRow("Magnesium",       scaled(prefill.magnesiumPer100g),          unit: "mg")
            }

            Section {
                Button {
                    attemptSave()
                } label: {
                    Text("Add to journal").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .selectAllOnFocus()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { attemptSave() }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
        .alert("Late-night snack?", isPresented: $showingLateSnackAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Log it anyway") { save() }
        } message: {
            Text("It's getting late. Eating this close to bed can affect sleep quality and digestion. Consider whether you really need it.")
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: Double, unit: String, asInt: Bool = false) -> some View {
        let valueText = asInt ? "\(Int(value))" : FoodFormat.value(value)
        LabeledContent(label, value: unit.isEmpty ? valueText : "\(valueText) \(unit)")
    }

    @ViewBuilder
    private func optionalRow(_ label: String, _ value: Double?, unit: String) -> some View {
        if let v = value {
            LabeledContent(label, value: "\(FoodFormat.value(v)) \(unit)")
        }
    }

    private func attemptSave() {
        if MealTimeHelper.shouldWarnAboutLateSnack(meal: mealType) {
            showingLateSnackAlert = true
        } else {
            save()
        }
    }

    private func save() {
        dismissKeyboard()
        let entry = FoodEntry(
            name: prefill.name,
            brand: prefill.brand,
            servings: 1,
            servingUnit: "\(Int(grams))g",
            calories: scaled(prefill.caloriesPer100g),
            protein: scaled(prefill.proteinPer100g),
            carbs: scaled(prefill.carbsPer100g),
            fat: scaled(prefill.fatPer100g),
            saturatedFat: scaled(prefill.saturatedFatPer100g),
            polyunsaturatedFat: scaled(prefill.polyunsaturatedFatPer100g),
            monounsaturatedFat: scaled(prefill.monounsaturatedFatPer100g),
            transFat: scaled(prefill.transFatPer100g),
            fiber: scaled(prefill.fiberPer100g),
            sugar: scaled(prefill.sugarPer100g),
            cholesterol: scaled(prefill.cholesterolPer100g),
            sodium: scaled(prefill.sodiumPer100g),
            potassium: scaled(prefill.potassiumPer100g),
            vitaminA: scaled(prefill.vitaminAPer100g),
            vitaminC: scaled(prefill.vitaminCPer100g),
            vitaminD: scaled(prefill.vitaminDPer100g),
            calcium: scaled(prefill.calciumPer100g),
            iron: scaled(prefill.ironPer100g),
            magnesium: scaled(prefill.magnesiumPer100g),
                    mealType: mealType,
                    source: source,
                    barcode: prefill.barcode
                )
                if let defaultDate {
                    entry.loggedAt = defaultDate
                }
                context.insert(entry)
                LibraryFoodUpsert.upsert(from: entry, in: context)
                onSaved()
            }}

// MARK: - ManualEntrySheet
struct ManualEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let defaultMeal: String?
        let defaultDate: Date?

        /// Per-serving = values are for one serving (legacy mode, always how it worked).
    /// Total amount = values are the totals for the amount typed above. On save we
    /// divide by `servings` to derive per-serving values, keeping the storage layer
    /// unchanged. Default is per-serving so existing muscle memory is preserved.
    enum EntryMode: String, CaseIterable, Identifiable {
        case perServing = "Per serving"
        case totalAmount = "Total amount"
        var id: String { rawValue }
    }

    @State private var entryMode: EntryMode = .perServing

    @State private var name = ""
    @State private var brand = ""
    @State private var servings: Double = 1
    @State private var servingUnit = "g"
    @State private var isCustomUnit = false
    @State private var customUnitText = ""
    @State private var mealType: String
    @State private var showingLateSnackAlert = false

    @State private var calories: Double = 0
    @State private var protein:  Double = 0
    @State private var carbs:    Double = 0
    @State private var fat:      Double = 0

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

    init(defaultMeal: String? = nil, defaultDate: Date? = nil) {
            self.defaultMeal = defaultMeal
            self.defaultDate = defaultDate
            _mealType = State(initialValue: defaultMeal ?? MealTimeHelper.mealType())
        }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name", text: $name)
                    TextField("Brand (optional)", text: $brand)
                }

                Section {
                    Picker("Mode", selection: $entryMode) {
                        ForEach(EntryMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                    HStack {
                        Text(entryMode == .perServing ? "Servings" : "Amount")
                        Spacer()
                        TextField("1", value: $servings, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    Picker("Unit", selection: $servingUnit) {
                        Text("grams (g)").tag("g")
                        Text("milliliters (ml)").tag("ml")
                        Text("ounces (oz)").tag("oz")
                        Text("serving").tag("serving")
                        Text("cup").tag("cup")
                        Text("tbsp").tag("tbsp")
                        Text("tsp").tag("tsp")
                        Text("Custom…").tag("__custom__")
                    }
                    .onChange(of: servingUnit) { _, newValue in
                        isCustomUnit = (newValue == "__custom__")
                        if !isCustomUnit { customUnitText = "" }
                    }

                    if isCustomUnit {
                        HStack {
                            Text("Custom unit")
                            Spacer()
                            TextField("e.g. burrito", text: $customUnitText)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 160)
                        }
                    }

                    Picker("Meal", selection: $mealType) {
                        Text("Breakfast").tag("breakfast")
                        Text("Lunch").tag("lunch")
                        Text("Dinner").tag("dinner")
                        Text("Snack").tag("snack")
                    }
                } header: {
                    Text("Serving")
                } footer: {
                    Text(entryMode == .perServing
                         ? "Macros below are per single serving."
                         : "Macros below are the totals for the amount above.")
                        .font(.caption)
                }

                Section(entryMode == .perServing ? "Macros (per serving)" : "Macros (totals)") {
                    macroField("Calories", value: $calories, suffix: "")
                    macroField("Protein",  value: $protein,  suffix: "g")
                    macroField("Carbs",    value: $carbs,    suffix: "g")
                    macroField("Fat",      value: $fat,      suffix: "g")
                }

                Section {
                    optionalField("Fiber",  text: $fiberStr, suffix: "g")
                    optionalField("Sugar",  text: $sugarStr, suffix: "g")
                } header: {
                    Text("Carbs detail")
                } footer: {
                    Text("Leave blank if you don't know.")
                }

                Section("Fats detail") {
                    optionalField("Saturated",       text: $saturatedFatStr,       suffix: "g")
                    optionalField("Polyunsaturated", text: $polyunsaturatedFatStr, suffix: "g")
                    optionalField("Monounsaturated", text: $monounsaturatedFatStr, suffix: "g")
                    optionalField("Trans",           text: $transFatStr,           suffix: "g")
                }

                Section("Cholesterol & electrolytes") {
                    optionalField("Cholesterol", text: $cholesterolStr, suffix: "mg")
                    optionalField("Sodium",      text: $sodiumStr,      suffix: "mg")
                    optionalField("Potassium",   text: $potassiumStr,   suffix: "mg")
                }

                Section("Vitamins & minerals") {
                    optionalField("Vitamin A", text: $vitaminAStr, suffix: "µg")
                    optionalField("Vitamin C", text: $vitaminCStr, suffix: "mg")
                    optionalField("Vitamin D", text: $vitaminDStr, suffix: "µg")
                    optionalField("Calcium",   text: $calciumStr,  suffix: "mg")
                    optionalField("Iron",      text: $ironStr,     suffix: "mg")
                    optionalField("Magnesium", text: $magnesiumStr, suffix: "mg")
                }
            }
            .navigationTitle("Manual entry")
            .navigationBarTitleDisplayMode(.inline)
            .selectAllOnFocus()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { attemptSave() }
                        .disabled(name.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
            }
            .alert("Late-night snack?", isPresented: $showingLateSnackAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Log it anyway") { save() }
            } message: {
                Text("It's getting late. Eating this close to bed can affect sleep quality and digestion. Consider whether you really need it.")
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

    private func optionalField(_ label: String, text: Binding<String>, suffix: String) -> some View {
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

    private func attemptSave() {
        if MealTimeHelper.shouldWarnAboutLateSnack(meal: mealType) {
            showingLateSnackAlert = true
        } else {
            save()
        }
    }

    private func save() {
        dismissKeyboard()
        Haptic.success()
        let resolvedUnit: String = {
            if isCustomUnit {
                let trimmed = customUnitText.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? "serving" : trimmed
            }
            return servingUnit
        }()

        // In totals mode, the typed values are the totals across `servings`.
        // We convert to per-serving by dividing each value by servings.
        // Per-serving mode keeps values as-typed (divisor = 1).
        // Guard against divide-by-zero (servings=0 in totals falls back to as-typed).
        let divisor: Double = (entryMode == .totalAmount && servings > 0) ? servings : 1.0

        let entry = FoodEntry(
            name: name,
            brand: brand.isEmpty ? nil : brand,
            servings: servings,
            servingUnit: resolvedUnit,
            calories: calories / divisor,
            protein: protein / divisor,
            carbs: carbs / divisor,
            fat: fat / divisor,
            saturatedFat: parseOptional(saturatedFatStr).map { $0 / divisor },
            polyunsaturatedFat: parseOptional(polyunsaturatedFatStr).map { $0 / divisor },
            monounsaturatedFat: parseOptional(monounsaturatedFatStr).map { $0 / divisor },
            transFat: parseOptional(transFatStr).map { $0 / divisor },
            fiber: parseOptional(fiberStr).map { $0 / divisor },
            sugar: parseOptional(sugarStr).map { $0 / divisor },
            cholesterol: parseOptional(cholesterolStr).map { $0 / divisor },
            sodium: parseOptional(sodiumStr).map { $0 / divisor },
            potassium: parseOptional(potassiumStr).map { $0 / divisor },
            vitaminA: parseOptional(vitaminAStr).map { $0 / divisor },
            vitaminC: parseOptional(vitaminCStr).map { $0 / divisor },
            vitaminD: parseOptional(vitaminDStr).map { $0 / divisor },
            calcium: parseOptional(calciumStr).map { $0 / divisor },
            iron: parseOptional(ironStr).map { $0 / divisor },
            magnesium: parseOptional(magnesiumStr).map { $0 / divisor },
            mealType: mealType,
                        source: "manual"
                    )
                    if let defaultDate {
                        entry.loggedAt = defaultDate
                    }
                    context.insert(entry)
                    LibraryFoodUpsert.upsert(from: entry, in: context)
                    dismiss()
                }

    private func parseOptional(_ s: String) -> Double? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        return Double(trimmed)
    }
}
// MARK: - SettingsView
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var goalsList: [UserGoals]

    @State private var calorieGoal: Double = 2000
    @State private var proteinGoal: Double = 150
    @State private var carbsGoal:   Double = 225
    @State private var fatGoal:     Double = 55
    @State private var waterGoalOz: Double = 100

    @State private var showingNutrientGoals = false
    @State private var showingCSVExport = false
    @State private var showingAnthropicSheet = false
    @State private var showingUSDASheet = false

    // Tracked locally so the row's "Set / Not set" status updates after a sheet edit.
    @State private var anthropicKeySet = false
    @State private var usdaKeySet = false
    @State private var showingResetLibraryAlert = false
    @State private var libraryCount = 0

    // Late-night warning config — backed by UserDefaults via @AppStorage.
    // Defaults match MealTimeHelper.defaultEnabled / defaultStartHour / defaultEndHour.
    // These auto-save on change; no Save button needed for this section.
    @AppStorage("lateNightWarningEnabled")   private var warningEnabled: Bool = true
    @AppStorage("lateNightWarningStartHour") private var warningStartHour: Int = 20
    @AppStorage("lateNightWarningEndHour")   private var warningEndHour: Int = 6

    // Meal-window config — boundary hours for each named meal. Anything outside
    // these windows falls through to "snack". Defaults match the v1.7 hardcoded
    // schedule. Each window can wrap midnight (start > end).
    @AppStorage("mealBreakfastStart") private var breakfastStart: Int = 6
    @AppStorage("mealBreakfastEnd")   private var breakfastEnd:   Int = 10
    @AppStorage("mealLunchStart")     private var lunchStart:     Int = 12
    @AppStorage("mealLunchEnd")       private var lunchEnd:       Int = 14
    @AppStorage("mealDinnerStart")    private var dinnerStart:    Int = 17
    @AppStorage("mealDinnerEnd")      private var dinnerEnd:      Int = 20

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily goals") {
                    goalField("Calories", value: $calorieGoal, suffix: "")
                    goalField("Protein",  value: $proteinGoal, suffix: "g")
                    goalField("Carbs",    value: $carbsGoal,   suffix: "g")
                    goalField("Fat",      value: $fatGoal,     suffix: "g")
                    goalField("Water",    value: $waterGoalOz, suffix: "oz")
                }

                Section {
                    Button {
                        showingNutrientGoals = true
                    } label: {
                        HStack {
                            Text("More nutrient goals")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("Fiber, sugar, vitamins…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section {
                    Toggle("Warn me about late snacks", isOn: $warningEnabled)

                    if warningEnabled {
                        Picker("Start", selection: $warningStartHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(formatHour(hour)).tag(hour)
                            }
                        }
                        Picker("End", selection: $warningEndHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(formatHour(hour)).tag(hour)
                            }
                        }
                    }
                } header: {
                    Text("Late-night snack alert")
                } footer: {
                    if warningEnabled {
                        Text("Snacks logged between \(formatHour(warningStartHour)) and \(formatHour(warningEndHour)) prompt a confirmation. Other meals are unaffected.")
                    } else {
                        Text("Late-night snack saves will not prompt a confirmation.")
                    }
                }

                Section {
                    mealWindowRow(label: "Breakfast", start: $breakfastStart, end: $breakfastEnd)
                    mealWindowRow(label: "Lunch",     start: $lunchStart,     end: $lunchEnd)
                    mealWindowRow(label: "Dinner",    start: $dinnerStart,    end: $dinnerEnd)
                    Button {
                        resetMealSchedule()
                    } label: {
                        Text("Reset to defaults")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Meal time schedule")
                } footer: {
                    Text("Hours outside these windows default to Snack. Each window can wrap midnight (e.g. Dinner 22:00–02:00). New entries logged without an explicit meal context use this schedule.")
                }

                Section("Data") {
                    Button {
                        showingCSVExport = true
                    } label: {
                        HStack {
                            Text("Export data")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("CSV")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Button {
                        libraryCount = countLibrary()
                        showingResetLibraryAlert = true
                    } label: {
                        HStack {
                            Text("Reset food library")
                                .foregroundStyle(.red)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section("API keys") {
                    Button {
                        showingAnthropicSheet = true
                    } label: {
                        keyRow(label: "Anthropic API key", isSet: anthropicKeySet)
                    }
                    Button {
                        showingUSDASheet = true
                    } label: {
                        keyRow(label: "USDA API key", isSet: usdaKeySet)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .alert("Reset food library?", isPresented: $showingResetLibraryAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    resetLibrary()
                }
            } message: {
                Text("This will erase all \(libraryCount) library record\(libraryCount == 1 ? "" : "s"). Your existing journal entries are not affected. The library will refill itself as you log foods.")
            }
            .onAppear { reload() }
            .sheet(isPresented: $showingNutrientGoals) {
                NutrientGoalsSheet()
            }
            .sheet(isPresented: $showingCSVExport) {
                CSVExportSheet()
            }
            .sheet(isPresented: $showingAnthropicSheet, onDismiss: reload) {
                AnthropicKeySheet()
            }
            .sheet(isPresented: $showingUSDASheet, onDismiss: reload) {
                USDAKeySheet()
            }
        }
    }

    private func keyRow(label: String, isSet: Bool) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            Text(isSet ? "Set" : "Not set")
                .font(.subheadline)
                .foregroundStyle(isSet ? .green : .secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
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

    /// Format a 0–23 hour as "12 AM" / "8 AM" / "12 PM" / "8 PM".
    private func formatHour(_ hour: Int) -> String {
        switch hour {
        case 0:       return "12 AM"
        case 1...11:  return "\(hour) AM"
        case 12:      return "12 PM"
        case 13...23: return "\(hour - 12) PM"
        default:      return "\(hour):00"
        }
    }

    @ViewBuilder
    private func mealWindowRow(label: String, start: Binding<Int>, end: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Picker("", selection: start) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(formatHour(hour)).tag(hour)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            Text("–").foregroundStyle(.secondary)
            Picker("", selection: end) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(formatHour(hour)).tag(hour)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private func resetMealSchedule() {
        Haptic.light()
        breakfastStart = MealTimeHelper.defaultBreakfastStart
        breakfastEnd   = MealTimeHelper.defaultBreakfastEnd
        lunchStart     = MealTimeHelper.defaultLunchStart
        lunchEnd       = MealTimeHelper.defaultLunchEnd
        dinnerStart    = MealTimeHelper.defaultDinnerStart
        dinnerEnd      = MealTimeHelper.defaultDinnerEnd
    }

    private func reload() {
        anthropicKeySet = !KeychainStore.loadAPIKey().isEmpty
        usdaKeySet = !KeychainStore.load(.usda).isEmpty
        if let g = goalsList.first {
            calorieGoal = g.calorieGoal
            proteinGoal = g.proteinGoal
            carbsGoal   = g.carbsGoal
            fatGoal     = g.fatGoal
            waterGoalOz = g.waterGoalOz
        }
    }

    private func countLibrary() -> Int {
        let descriptor = FetchDescriptor<LibraryFood>()
        return (try? context.fetch(descriptor).count) ?? 0
    }

    private func resetLibrary() {
        Haptic.medium()
        let descriptor = FetchDescriptor<LibraryFood>()
        guard let foods = try? context.fetch(descriptor) else { return }
        for f in foods { context.delete(f) }
    }

    private func save() {
        dismissKeyboard()
        Haptic.light()
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

// MARK: - AnthropicKeySheet
struct AnthropicKeySheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $key)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !key.isEmpty {
                        Text("Length: \(key.count) chars · starts with \(String(key.prefix(7)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Key")
                } footer: {
                    Text("Stored in Keychain. Required for photo-based logging. Get one at \(Text("console.anthropic.com").underline().foregroundColor(.accentColor)).")
                }
                .onTapGesture {
                    if let url = URL(string: "https://console.anthropic.com") {
                        UIApplication.shared.open(url)
                    }
                }

                if !key.isEmpty {
                    Section {
                        Button("Clear key", role: .destructive) {
                            clear()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.callout)
                            .foregroundStyle(statusMessage.hasPrefix("✓") ? .green : .red)
                    }
                }
            }
            .navigationTitle("Anthropic API key")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                key = KeychainStore.loadAPIKey()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        dismissKeyboard()
        Haptic.light()
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = KeychainStore.saveAPIKey(trimmed)
        let readBack = KeychainStore.loadAPIKey()

        if status == errSecSuccess && readBack == trimmed && !trimmed.isEmpty {
            statusMessage = "✓ Saved \(trimmed.count) chars"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                dismiss()
            }
        } else if trimmed.isEmpty {
            statusMessage = "✗ Key field is empty"
        } else {
            statusMessage = "✗ Save failed (status \(status))"
        }
    }

    private func clear() {
        Haptic.medium()
        _ = KeychainStore.saveAPIKey("")
        key = ""
        statusMessage = "✓ Key cleared"
    }
}

// MARK: - USDAKeySheet
struct USDAKeySheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Your USDA API key", text: $key)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !key.isEmpty {
                        Text("Length: \(key.count) chars")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Key")
                } footer: {
                    Text("Stored in Keychain. Powers food search. Free key, takes 30 seconds — sign up at \(Text("api.data.gov/signup").underline().foregroundColor(.accentColor)). No review, key arrives by email.")
                }
                .onTapGesture {
                    if let url = URL(string: "https://api.data.gov/signup/") {
                        UIApplication.shared.open(url)
                    }
                }

                if !key.isEmpty {
                    Section {
                        Button("Clear key", role: .destructive) {
                            clear()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.callout)
                            .foregroundStyle(statusMessage.hasPrefix("✓") ? .green : .red)
                    }
                }
            }
            .navigationTitle("USDA API key")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                key = KeychainStore.load(.usda)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        dismissKeyboard()
        Haptic.light()
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = KeychainStore.save(trimmed, for: .usda)
        let readBack = KeychainStore.load(.usda)

        if status == errSecSuccess && readBack == trimmed && !trimmed.isEmpty {
            statusMessage = "✓ Saved \(trimmed.count) chars"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                dismiss()
            }
        } else if trimmed.isEmpty {
            statusMessage = "✗ Key field is empty"
        } else {
            statusMessage = "✗ Save failed (status \(status))"
        }
    }

    private func clear() {
        Haptic.medium()
        _ = KeychainStore.save("", for: .usda)
        key = ""
        statusMessage = "✓ Key cleared"
    }
}

// MARK: - RelogSheet (used by Recents quick-log)
struct RelogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let template: FoodEntry
        let defaultMeal: String?
        @State private var servings: Double
        @State private var mealType: String
        @State private var showingLateSnackAlert = false

    init(template: FoodEntry, defaultMeal: String? = nil) {
            self.template = template
            self.defaultMeal = defaultMeal
            _servings = State(initialValue: template.servings)
            _mealType = State(initialValue: defaultMeal ?? MealTimeHelper.mealType())
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

                Section("Nutrition for \(FoodFormat.value(servings)) \(template.servingUnit)") {
                    LabeledContent("Calories", value: "\(Int(template.calories * servings))")
                    LabeledContent("Protein",  value: "\(FoodFormat.value(template.protein * servings)) g")
                    LabeledContent("Carbs",    value: "\(FoodFormat.value(template.carbs * servings)) g")
                    LabeledContent("Fat",      value: "\(FoodFormat.value(template.fat * servings)) g")
                }
            }
            .navigationTitle("Re-log")
            .navigationBarTitleDisplayMode(.inline)
            .selectAllOnFocus()
            .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { dismiss() }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Log") { attemptSave() }
                                    .disabled(servings <= 0)
                            }
                        }
                        .alert("Late-night snack?", isPresented: $showingLateSnackAlert) {
                            Button("Cancel", role: .cancel) { }
                            Button("Log it anyway") { save() }
                        } message: {
                            Text("It's getting late. Eating this close to bed can affect sleep quality and digestion. Consider whether you really need it.")
                        }
                    }
                }
    private func attemptSave() {
            if MealTimeHelper.shouldWarnAboutLateSnack(meal: mealType) {
                showingLateSnackAlert = true
            } else {
                save()
            }
        }
    private func save() {
        dismissKeyboard()
        Haptic.success()
        let entry = FoodEntry(
            name: template.name,
            brand: template.brand,
            servings: servings,
            servingUnit: template.servingUnit,
            calories: template.calories,
            protein: template.protein,
            carbs: template.carbs,
            fat: template.fat,
            saturatedFat: template.saturatedFat,
            polyunsaturatedFat: template.polyunsaturatedFat,
            monounsaturatedFat: template.monounsaturatedFat,
            transFat: template.transFat,
            fiber: template.fiber,
            sugar: template.sugar,
            cholesterol: template.cholesterol,
            sodium: template.sodium,
            potassium: template.potassium,
            vitaminA: template.vitaminA,
            vitaminC: template.vitaminC,
            vitaminD: template.vitaminD,
            calcium: template.calcium,
            iron: template.iron,
            magnesium: template.magnesium,
            mealType: mealType,
            source: template.source,
            barcode: template.barcode
        )
        context.insert(entry)
        LibraryFoodUpsert.upsert(from: entry, in: context)
        dismiss()
    }
}

// MARK: - EditEntrySheet (tap a logged entry to edit all fields)
struct EditEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let entry: FoodEntry

    @State private var name: String
    @State private var brand: String
    @State private var servings: Double
    @State private var servingUnit: String
    @State private var isCustomUnit: Bool
    @State private var customUnitText: String
    @State private var mealType: String
        @State private var loggedAt: Date

        @State private var calories: Double
    @State private var protein: Double
    @State private var carbs: Double
    @State private var fat: Double

    @State private var fiberStr: String
    @State private var sugarStr: String
    @State private var saturatedFatStr: String
    @State private var polyunsaturatedFatStr: String
    @State private var monounsaturatedFatStr: String
    @State private var transFatStr: String
    @State private var cholesterolStr: String
    @State private var sodiumStr: String
    @State private var potassiumStr: String
    @State private var vitaminAStr: String
    @State private var vitaminCStr: String
    @State private var vitaminDStr: String
    @State private var calciumStr: String
    @State private var ironStr: String
    @State private var magnesiumStr: String

    private static let standardUnits: Set<String> = [
        "g", "ml", "oz", "serving", "cup", "tbsp", "tsp"
    ]

    init(entry: FoodEntry) {
        self.entry = entry
        _name = State(initialValue: entry.name)
        _brand = State(initialValue: entry.brand ?? "")
        _servings = State(initialValue: entry.servings)
        _mealType = State(initialValue: entry.mealType)
                _loggedAt = State(initialValue: entry.loggedAt)

                let isStd = Self.standardUnits.contains(entry.servingUnit)
        _servingUnit = State(initialValue: isStd ? entry.servingUnit : "__custom__")
        _isCustomUnit = State(initialValue: !isStd)
        _customUnitText = State(initialValue: isStd ? "" : entry.servingUnit)

        _calories = State(initialValue: entry.calories)
        _protein = State(initialValue: entry.protein)
        _carbs = State(initialValue: entry.carbs)
        _fat = State(initialValue: entry.fat)

        _fiberStr = State(initialValue: Self.optStr(entry.fiber))
        _sugarStr = State(initialValue: Self.optStr(entry.sugar))
        _saturatedFatStr = State(initialValue: Self.optStr(entry.saturatedFat))
        _polyunsaturatedFatStr = State(initialValue: Self.optStr(entry.polyunsaturatedFat))
        _monounsaturatedFatStr = State(initialValue: Self.optStr(entry.monounsaturatedFat))
        _transFatStr = State(initialValue: Self.optStr(entry.transFat))
        _cholesterolStr = State(initialValue: Self.optStr(entry.cholesterol))
        _sodiumStr = State(initialValue: Self.optStr(entry.sodium))
        _potassiumStr = State(initialValue: Self.optStr(entry.potassium))
        _vitaminAStr = State(initialValue: Self.optStr(entry.vitaminA))
        _vitaminCStr = State(initialValue: Self.optStr(entry.vitaminC))
        _vitaminDStr = State(initialValue: Self.optStr(entry.vitaminD))
        _calciumStr = State(initialValue: Self.optStr(entry.calcium))
        _ironStr = State(initialValue: Self.optStr(entry.iron))
        _magnesiumStr = State(initialValue: Self.optStr(entry.magnesium))
    }

    private static func optStr(_ d: Double?) -> String {
        guard let d else { return "" }
        if d.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(d))
        }
        return String(format: "%.2f", d)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name", text: $name)
                    TextField("Brand (optional)", text: $brand)
                }

                Section("Serving") {
                    HStack {
                        Text("Servings")
                        Spacer()
                        TextField("1", value: $servings, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    Picker("Unit", selection: $servingUnit) {
                        Text("grams (g)").tag("g")
                        Text("milliliters (ml)").tag("ml")
                        Text("ounces (oz)").tag("oz")
                        Text("serving").tag("serving")
                        Text("cup").tag("cup")
                        Text("tbsp").tag("tbsp")
                        Text("tsp").tag("tsp")
                        Text("Custom…").tag("__custom__")
                    }
                    .onChange(of: servingUnit) { _, newValue in
                        isCustomUnit = (newValue == "__custom__")
                        if !isCustomUnit { customUnitText = "" }
                    }

                    if isCustomUnit {
                        HStack {
                            Text("Custom unit")
                            Spacer()
                            TextField("e.g. burrito", text: $customUnitText)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 160)
                        }
                    }

                    Picker("Meal", selection: $mealType) {
                                            Text("Breakfast").tag("breakfast")
                                            Text("Lunch").tag("lunch")
                                            Text("Dinner").tag("dinner")
                                            Text("Snack").tag("snack")
                                        }
                                    }

                                    Section("When") {
                                        DatePicker(
                                            "Date logged",
                                            selection: $loggedAt,
                                            in: ...Date.now,
                                            displayedComponents: .date
                                        )
                                    }

                                    Section("Macros (per serving)") {
                    macroField("Calories", value: $calories, suffix: "")
                    macroField("Protein",  value: $protein,  suffix: "g")
                    macroField("Carbs",    value: $carbs,    suffix: "g")
                    macroField("Fat",      value: $fat,      suffix: "g")
                }

                Section("Carbs detail") {
                    optionalField("Fiber", text: $fiberStr, suffix: "g")
                    optionalField("Sugar", text: $sugarStr, suffix: "g")
                }

                Section("Fats detail") {
                    optionalField("Saturated",       text: $saturatedFatStr,       suffix: "g")
                    optionalField("Polyunsaturated", text: $polyunsaturatedFatStr, suffix: "g")
                    optionalField("Monounsaturated", text: $monounsaturatedFatStr, suffix: "g")
                    optionalField("Trans",           text: $transFatStr,           suffix: "g")
                }

                Section("Cholesterol & electrolytes") {
                    optionalField("Cholesterol", text: $cholesterolStr, suffix: "mg")
                    optionalField("Sodium",      text: $sodiumStr,      suffix: "mg")
                    optionalField("Potassium",   text: $potassiumStr,   suffix: "mg")
                }

                Section("Vitamins & minerals") {
                    optionalField("Vitamin A", text: $vitaminAStr,  suffix: "µg")
                    optionalField("Vitamin C", text: $vitaminCStr,  suffix: "mg")
                    optionalField("Vitamin D", text: $vitaminDStr,  suffix: "µg")
                    optionalField("Calcium",   text: $calciumStr,   suffix: "mg")
                    optionalField("Iron",      text: $ironStr,      suffix: "mg")
                    optionalField("Magnesium", text: $magnesiumStr, suffix: "mg")
                }
            }
            .navigationTitle("Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .selectAllOnFocus()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
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
            if !suffix.isEmpty {
                Text(suffix).foregroundStyle(.secondary)
            }
        }
    }

    private func optionalField(_ label: String, text: Binding<String>, suffix: String) -> some View {
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

    private func save() {
        dismissKeyboard()
        Haptic.success()

        let resolvedUnit: String = {
            if isCustomUnit {
                let trimmed = customUnitText.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? "serving" : trimmed
            }
            return servingUnit
        }()

        entry.name = name
        entry.brand = brand.isEmpty ? nil : brand
        entry.servings = servings
        entry.servingUnit = resolvedUnit
                entry.mealType = mealType
                entry.loggedAt = loggedAt
                entry.calories = calories
        entry.protein = protein
        entry.carbs = carbs
        entry.fat = fat
        entry.fiber = parseOptional(fiberStr)
        entry.sugar = parseOptional(sugarStr)
        entry.saturatedFat = parseOptional(saturatedFatStr)
        entry.polyunsaturatedFat = parseOptional(polyunsaturatedFatStr)
        entry.monounsaturatedFat = parseOptional(monounsaturatedFatStr)
        entry.transFat = parseOptional(transFatStr)
        entry.cholesterol = parseOptional(cholesterolStr)
        entry.sodium = parseOptional(sodiumStr)
        entry.potassium = parseOptional(potassiumStr)
        entry.vitaminA = parseOptional(vitaminAStr)
        entry.vitaminC = parseOptional(vitaminCStr)
        entry.vitaminD = parseOptional(vitaminDStr)
        entry.calcium = parseOptional(calciumStr)
        entry.iron = parseOptional(ironStr)
        entry.magnesium = parseOptional(magnesiumStr)

        LibraryFoodUpsert.upsert(from: entry, in: context)
        dismiss()
    }

    private func parseOptional(_ s: String) -> Double? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        return Double(trimmed)
    }
}
