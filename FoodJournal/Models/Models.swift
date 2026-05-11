import Foundation
import SwiftData

@Model
final class FoodEntry: Identifiable {
    var id: UUID
    var name: String
    var brand: String?
    var servings: Double
    var servingUnit: String          // e.g. "g", "cup", "piece"

    // Macros (per serving as logged)
    var calories: Double
    var protein: Double              // g
    var carbs: Double                // g
    var fat: Double                  // g

    // Fats detail
    var saturatedFat: Double?        // g
    var polyunsaturatedFat: Double?  // g
    var monounsaturatedFat: Double?  // g
    var transFat: Double?            // g

    // Carbs detail
    var fiber: Double?               // g
    var sugar: Double?               // g

    // Other macronutrient-like
    var cholesterol: Double?         // mg
    var sodium: Double?              // mg
    var potassium: Double?           // mg

    // Vitamins & minerals (absolute amounts; convert to %DV at display time)
    var vitaminA: Double?            // µg RAE
    var vitaminC: Double?            // mg
    var vitaminD: Double?            // µg
    var calcium: Double?             // mg
    var iron: Double?                // mg
    var magnesium: Double?           // mg

    // Metadata
        var loggedAt: Date
        var mealType: String             // "breakfast" | "lunch" | "dinner" | "snack"
        var source: String               // "barcode" | "search" | "photo" | "manual"
        var barcode: String?
        var pendingDeleteAt: Date?       // soft-delete timestamp; commits after undo window expires

    init(
        name: String,
        brand: String? = nil,
        servings: Double = 1,
        servingUnit: String = "serving",
        calories: Double,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        saturatedFat: Double? = nil,
        polyunsaturatedFat: Double? = nil,
        monounsaturatedFat: Double? = nil,
        transFat: Double? = nil,
        fiber: Double? = nil,
        sugar: Double? = nil,
        cholesterol: Double? = nil,
        sodium: Double? = nil,
        potassium: Double? = nil,
        vitaminA: Double? = nil,
        vitaminC: Double? = nil,
        vitaminD: Double? = nil,
        calcium: Double? = nil,
        iron: Double? = nil,
        magnesium: Double? = nil,
        loggedAt: Date = .now,
        mealType: String = "snack",
        source: String = "manual",
        barcode: String? = nil,
        pendingDeleteAt: Date? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.brand = brand
        self.servings = servings
        self.servingUnit = servingUnit
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.saturatedFat = saturatedFat
        self.polyunsaturatedFat = polyunsaturatedFat
        self.monounsaturatedFat = monounsaturatedFat
        self.transFat = transFat
        self.fiber = fiber
        self.sugar = sugar
        self.cholesterol = cholesterol
        self.sodium = sodium
        self.potassium = potassium
        self.vitaminA = vitaminA
        self.vitaminC = vitaminC
        self.vitaminD = vitaminD
        self.calcium = calcium
        self.iron = iron
        self.magnesium = magnesium
        self.loggedAt = loggedAt
        self.mealType = mealType
        self.source = source
        self.barcode = barcode
        self.pendingDeleteAt = pendingDeleteAt
    }
}

@Model
final class UserGoals {
    // Macros
    var calorieGoal: Double
    var proteinGoal: Double
    var carbsGoal: Double
    var fatGoal: Double
    var waterGoalOz: Double = 100

    // New nutrient goals — nil means "no target, display total only"
    var fiberGoal: Double? = 40
    var sugarGoal: Double? = 50
    var saturatedFatGoal: Double? = 15
    var polyunsaturatedFatGoal: Double? = nil
    var monounsaturatedFatGoal: Double? = nil
    var transFatGoal: Double? = 0
    var cholesterolGoal: Double? = 200
    var sodiumGoal: Double? = 2300
    var potassiumGoal: Double? = 3500
    var vitaminAGoal: Double? = 900
    var vitaminCGoal: Double? = 90
    var vitaminDGoal: Double? = 20
    var calciumGoal: Double? = 1300
    var ironGoal: Double? = 18
    var magnesiumGoal: Double? = 420

    init(
        calorieGoal: Double = 2000,
        proteinGoal: Double = 150,
        carbsGoal: Double = 225,
        fatGoal: Double = 55,
        waterGoalOz: Double = 100
    ) {
        self.calorieGoal = calorieGoal
        self.proteinGoal = proteinGoal
        self.carbsGoal = carbsGoal
        self.fatGoal = fatGoal
        self.waterGoalOz = waterGoalOz
    }
}

@Model
final class CachedFood {
    @Attribute(.unique) var barcode: String
    var name: String
    var brand: String?
    var caloriesPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var servingSizeGrams: Double?
    var lastFetched: Date

    init(
        barcode: String,
        name: String,
        brand: String? = nil,
        caloriesPer100g: Double,
        proteinPer100g: Double,
        carbsPer100g: Double,
        fatPer100g: Double,
        servingSizeGrams: Double? = nil
    ) {
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.caloriesPer100g = caloriesPer100g
        self.proteinPer100g = proteinPer100g
        self.carbsPer100g = carbsPer100g
        self.fatPer100g = fatPer100g
        self.servingSizeGrams = servingSizeGrams
        self.lastFetched = .now
    }
}

@Model
final class WaterEntry {
    var id: UUID
    var amountOz: Double
    var loggedAt: Date
    var pendingDeleteAt: Date?       // soft-delete timestamp; commits after undo window expires

    init(amountOz: Double, loggedAt: Date = .now, pendingDeleteAt: Date? = nil) {
        self.id = UUID()
        self.amountOz = amountOz
        self.loggedAt = loggedAt
        self.pendingDeleteAt = pendingDeleteAt
    }
}

@Model
final class WeightEntry {
    var id: UUID
    var weightLbs: Double
    var loggedAt: Date
    var pendingDeleteAt: Date?

    init(weightLbs: Double, loggedAt: Date = .now, pendingDeleteAt: Date? = nil) {
        self.id = UUID()
        self.weightLbs = weightLbs
        self.loggedAt = loggedAt
        self.pendingDeleteAt = pendingDeleteAt
    }
}
@Model
final class CachedPhotoEstimate {
    @Attribute(.unique) var imageHash: String
    var name: String
    var servings: Double
    var servingUnit: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    var saturatedFat: Double?
    var polyunsaturatedFat: Double?
    var monounsaturatedFat: Double?
    var transFat: Double?
    var fiber: Double?
    var sugar: Double?
    var cholesterol: Double?
    var sodium: Double?
    var potassium: Double?
    var vitaminA: Double?
    var vitaminC: Double?
    var vitaminD: Double?
    var calcium: Double?
    var iron: Double?
    var magnesium: Double?

    var confidence: String
    var notes: String?
    var cachedAt: Date

    init(
        imageHash: String,
        name: String,
        servings: Double,
        servingUnit: String,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        saturatedFat: Double? = nil,
        polyunsaturatedFat: Double? = nil,
        monounsaturatedFat: Double? = nil,
        transFat: Double? = nil,
        fiber: Double? = nil,
        sugar: Double? = nil,
        cholesterol: Double? = nil,
        sodium: Double? = nil,
        potassium: Double? = nil,
        vitaminA: Double? = nil,
        vitaminC: Double? = nil,
        vitaminD: Double? = nil,
        calcium: Double? = nil,
        iron: Double? = nil,
        magnesium: Double? = nil,
        confidence: String,
        notes: String? = nil
    ) {
        self.imageHash = imageHash
        self.name = name
        self.servings = servings
        self.servingUnit = servingUnit
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.saturatedFat = saturatedFat
        self.polyunsaturatedFat = polyunsaturatedFat
        self.monounsaturatedFat = monounsaturatedFat
        self.transFat = transFat
        self.fiber = fiber
        self.sugar = sugar
        self.cholesterol = cholesterol
        self.sodium = sodium
        self.potassium = potassium
        self.vitaminA = vitaminA
        self.vitaminC = vitaminC
        self.vitaminD = vitaminD
        self.calcium = calcium
        self.iron = iron
        self.magnesium = magnesium
        self.confidence = confidence
        self.notes = notes
        self.cachedAt = .now
    }

    /// Convert this cached record back into the same Estimate struct that the
    /// vision service returns, so callers can treat both paths identically.
    func toEstimate() -> ClaudeVisionService.Estimate {
        ClaudeVisionService.Estimate(
            name: name,
            servings: servings,
            serving_unit: servingUnit,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            confidence: confidence,
            notes: notes,
            saturated_fat: saturatedFat,
            polyunsaturated_fat: polyunsaturatedFat,
            monounsaturated_fat: monounsaturatedFat,
            trans_fat: transFat,
            fiber: fiber,
            sugar: sugar,
            cholesterol: cholesterol,
            sodium: sodium,
            potassium: potassium,
            vitamin_a: vitaminA,
            vitamin_c: vitaminC,
            vitamin_d: vitaminD,
            calcium: calcium,
            iron: iron,
            magnesium: magnesium
        )
    }
}
// MARK: - LibraryFood
/// One record per unique food name+brand combo the user has ever logged.
/// Auto-populated on every save path (manual, barcode, photo, search).
/// Powers the "Search" feature on the Add tab — local-first food autocomplete.
///
/// Storage strategy is hybrid:
/// - If the original log was in grams (or had a known servingSizeGrams), we back-compute
///   per-100g values so future logs can flexibly scale by gram amount.
/// - For non-gram units (cup, tbsp, "burrito"), we store per-serving values with the
///   original unit. Future logs scale by serving count instead.
/// `isPer100g` distinguishes the two modes.
@Model
final class LibraryFood {
    /// Composite dedup key — lowercased "name|brand" for case-insensitive uniqueness.
    @Attribute(.unique) var dedupKey: String

    var name: String                  // display name, original casing
    var brand: String?                // display brand, original casing

    /// If true, all macro/nutrient values are per-100g. If false, values are per single serving in `servingUnit`.
    var isPer100g: Bool
    var servingUnit: String           // "g" when isPer100g==true; otherwise "cup", "burrito", etc.

    // Macros (per-100g OR per-serving, depending on isPer100g)
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    // Optional details — same per-100g/per-serving rule
    var saturatedFat: Double?
    var polyunsaturatedFat: Double?
    var monounsaturatedFat: Double?
    var transFat: Double?
    var fiber: Double?
    var sugar: Double?
    var cholesterol: Double?
    var sodium: Double?
    var potassium: Double?
    var vitaminA: Double?
    var vitaminC: Double?
    var vitaminD: Double?
    var calcium: Double?
    var iron: Double?
    var magnesium: Double?

    var lastUsedAt: Date              // bump on every re-log; lets us sort library by recency
    var useCount: Int                 // how many times this food has been logged

    init(
        dedupKey: String,
        name: String,
        brand: String? = nil,
        isPer100g: Bool,
        servingUnit: String,
        calories: Double,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        saturatedFat: Double? = nil,
        polyunsaturatedFat: Double? = nil,
        monounsaturatedFat: Double? = nil,
        transFat: Double? = nil,
        fiber: Double? = nil,
        sugar: Double? = nil,
        cholesterol: Double? = nil,
        sodium: Double? = nil,
        potassium: Double? = nil,
        vitaminA: Double? = nil,
        vitaminC: Double? = nil,
        vitaminD: Double? = nil,
        calcium: Double? = nil,
        iron: Double? = nil,
        magnesium: Double? = nil,
        lastUsedAt: Date = .now,
        useCount: Int = 1
    ) {
        self.dedupKey = dedupKey
        self.name = name
        self.brand = brand
        self.isPer100g = isPer100g
        self.servingUnit = servingUnit
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.saturatedFat = saturatedFat
        self.polyunsaturatedFat = polyunsaturatedFat
        self.monounsaturatedFat = monounsaturatedFat
        self.transFat = transFat
        self.fiber = fiber
        self.sugar = sugar
        self.cholesterol = cholesterol
        self.sodium = sodium
        self.potassium = potassium
        self.vitaminA = vitaminA
        self.vitaminC = vitaminC
        self.vitaminD = vitaminD
        self.calcium = calcium
        self.iron = iron
        self.magnesium = magnesium
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }

    /// Build the canonical dedup key from a name and optional brand.
    static func makeDedupKey(name: String, brand: String?) -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = (brand ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(n)|\(b)"
    }
}
/// Shared number formatting for nutrient/serving display.
/// - Whole numbers show as integers: `3` not `3.0`.
/// - Fractional values show one decimal: `2.5`, `0.5`.
/// - Tiny values (< 0.1) show as `<0.1` to avoid silly precision.
enum FoodFormat {
    static func value(_ d: Double) -> String {
        if d == 0 { return "0" }
        if abs(d) < 0.1 { return "<0.1" }
        if d.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(d))
        }
        return String(format: "%.1f", d)
    }

    /// Formats `"value unit"` together — handles the "no value yet" case as `–`.
    static func valueUnit(_ d: Double?, _ unit: String) -> String {
        guard let d else { return "–" }
        return "\(value(d)) \(unit)"
    }
}
// MARK: - LibraryFood upsert helper
/// Upserts a LibraryFood record from a FoodEntry that's about to be saved.
/// Call this immediately AFTER context.insert(entry) on every save path.
enum LibraryFoodUpsert {
    static func upsert(from entry: FoodEntry, in context: ModelContext) {
        let key = LibraryFood.makeDedupKey(name: entry.name, brand: entry.brand)

        let descriptor = FetchDescriptor<LibraryFood>(
            predicate: #Predicate<LibraryFood> { $0.dedupKey == key }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.useCount += 1
            existing.lastUsedAt = .now
            return
        }

        // Derive the right representation. Two shapes need to be detected:
        //   Shape A — manual-style:  servingUnit="g", servings=<grams>
        //   Shape B — barcode-style: servingUnit="<N>g", servings=1
        // Both mean "this entry represents N grams of food."
        let totalGrams: Double? = {
                    // Pure "g" with a meaningful gram count (>=10g) — manual-style: servings IS gram count
                    if entry.servingUnit == "g" && entry.servings >= 10 {
                        return entry.servings
                    }
                    // "<N>g" — barcode-style: explicit gram count per serving, multiplied by servings
                    let unit = entry.servingUnit
                    if unit.hasSuffix("g"), let n = Double(unit.dropLast()), n > 0 {
                        return n * entry.servings
                    }
                    // Anything else (cup, tbsp, "burrito", or "g" with tiny servings count) → per-serving
                    return nil
                }()

        let isPer100g = (totalGrams != nil)
        let scale: Double
        let resolvedUnit: String

        if let g = totalGrams, g > 0 {
            scale = 100.0 / g
            resolvedUnit = "g"
        } else {
            // Non-gram unit (cup, tbsp, "burrito"). Store per-serving values.
            // Per-serving on FoodEntry already factors out by `servings`, so divide.
            scale = entry.servings > 0 ? 1.0 / entry.servings : 1.0
            resolvedUnit = entry.servingUnit
        }

        let lib = LibraryFood(
            dedupKey: key,
            name: entry.name,
            brand: entry.brand,
            isPer100g: isPer100g,
            servingUnit: resolvedUnit,
            calories: entry.calories * scale,
            protein: entry.protein * scale,
            carbs: entry.carbs * scale,
            fat: entry.fat * scale,
            saturatedFat: entry.saturatedFat.map { $0 * scale },
            polyunsaturatedFat: entry.polyunsaturatedFat.map { $0 * scale },
            monounsaturatedFat: entry.monounsaturatedFat.map { $0 * scale },
            transFat: entry.transFat.map { $0 * scale },
            fiber: entry.fiber.map { $0 * scale },
            sugar: entry.sugar.map { $0 * scale },
            cholesterol: entry.cholesterol.map { $0 * scale },
            sodium: entry.sodium.map { $0 * scale },
            potassium: entry.potassium.map { $0 * scale },
            vitaminA: entry.vitaminA.map { $0 * scale },
            vitaminC: entry.vitaminC.map { $0 * scale },
            vitaminD: entry.vitaminD.map { $0 * scale },
            calcium: entry.calcium.map { $0 * scale },
            iron: entry.iron.map { $0 * scale },
            magnesium: entry.magnesium.map { $0 * scale }
        )
        context.insert(lib)
    }
}
