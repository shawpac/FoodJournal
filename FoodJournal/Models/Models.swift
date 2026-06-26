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

    /// UUID of the HKCorrelation written to Apple Health for this entry.
    /// Nil when not synced (Health sync disabled at save time, or write failed).
    /// Used to delete the matching Health correlation when this entry is removed/edited.
    var healthSampleID: String?

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
        pendingDeleteAt: Date? = nil,
        healthSampleID: String? = nil
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
        self.healthSampleID = healthSampleID
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
    var healthSampleID: String?      // UUID of the matching HK dietaryWater sample, if synced

    init(amountOz: Double, loggedAt: Date = .now, pendingDeleteAt: Date? = nil, healthSampleID: String? = nil) {
        self.id = UUID()
        self.amountOz = amountOz
        self.loggedAt = loggedAt
        self.pendingDeleteAt = pendingDeleteAt
        self.healthSampleID = healthSampleID
    }
}

@Model
final class WeightEntry {
    var id: UUID
    var weightLbs: Double
    var loggedAt: Date
    var pendingDeleteAt: Date?
    var healthSampleID: String?      // UUID of the matching HK bodyMass sample, if synced
    /// True when this record was imported from Apple Health (not originated in-app).
    /// Used to gate delete-sync: imported entries should NOT delete the source Health
    /// sample on commit-delete, since the user didn't create it here.
    var importedFromHealth: Bool

    init(weightLbs: Double, loggedAt: Date = .now, pendingDeleteAt: Date? = nil, healthSampleID: String? = nil, importedFromHealth: Bool = false) {
        self.id = UUID()
        self.weightLbs = weightLbs
        self.loggedAt = loggedAt
        self.pendingDeleteAt = pendingDeleteAt
        self.healthSampleID = healthSampleID
        self.importedFromHealth = importedFromHealth
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

// MARK: - v2.1a — Strength + Daily tracker models
//
// First @Models in the project that use SwiftData @Relationship. Two patterns
// are at play:
//   • Flat models: ExerciseRepEntry, StretchDay. No relationships.
//   • Nested cascade: StrengthSession → LoggedExercise → LoggedSet, plus
//     StrengthRoutine → RoutineExercise. Each parent owns its children with
//     `deleteRule: .cascade`. The child carries the explicit back-pointer so
//     SwiftData can resolve the inverse for nested cascades. Pattern matches
//     Apple's @Relationship(inverse:) recommendation: declare the inverse on
//     the parent side so the cascade rule and inverse stay together.
//
// IMPORTANT: NO HealthKit fields on any of these models. Strength data has no
// HealthKit type (weight/reps/sets aren't tracked there), and the user wears
// an Apple Watch which already captures calories — writing duplicate workouts
// from in-app strength logging would double-count. Daily reps (pushups/situps)
// and stretch toggle also have no HealthKit type. All v2.1a data is in-app
// only.

// MARK: ExerciseRepEntry (daily bursts of pushups/situps)
/// Append-style burst log: each "I did 25 pushups" tap creates one row.
/// Today's displayed count is the SUM of today's non-soft-deleted entries
/// of that kind. Mirrors the WaterEntry model + soft-delete pattern.
@Model
final class ExerciseRepEntry {
    var id: UUID
    /// "pushups" | "situps". Free-form String so future kinds (squats, lunges)
    /// can be added without a schema change.
    var kind: String
    /// Always a real count — you don't log a burst without a number, so this
    /// is non-optional. Distinct from the routine-target Int? fields below.
    var count: Int
    var loggedAt: Date
    var pendingDeleteAt: Date?

    init(kind: String, count: Int, loggedAt: Date = .now, pendingDeleteAt: Date? = nil) {
        self.id = UUID()
        self.kind = kind
        self.count = count
        self.loggedAt = loggedAt
        self.pendingDeleteAt = pendingDeleteAt
    }
}

// MARK: StretchDay (binary "did I stretch today" flag)
/// One row per calendar day. `date` is normalized to startOfDay so the
/// uniqueness check on lookup is straightforward. Binary by design — no
/// "how long did I stretch?" tracking yet.
@Model
final class StretchDay {
    /// Start-of-day in the user's calendar. Use Calendar.current.startOfDay(for:)
    /// when constructing.
    @Attribute(.unique) var date: Date
    var stretched: Bool

    init(date: Date, stretched: Bool = false) {
        self.date = date
        self.stretched = stretched
    }
}

// MARK: StrengthRoutine (reusable template)
/// A named template (e.g. "Push day A"). Contains an ordered list of
/// RoutineExercises (display targets only — never copied into a session's
/// stored set values).
@Model
final class StrengthRoutine {
    var routineID: UUID
    var name: String
    var order: Int
    var createdAt: Date

    /// Cascade: deleting a routine deletes its target lines. Inverse declared
    /// here so RoutineExercise.routine resolves automatically.
    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.routine)
    var exercises: [RoutineExercise] = []

    init(routineID: UUID = UUID(), name: String, order: Int = 0, createdAt: Date = .now) {
        self.routineID = routineID
        self.name = name
        self.order = order
        self.createdAt = createdAt
    }
}

// MARK: RoutineExercise (one target line on a routine)
/// A target line on a routine — name + optional planned sets/reps/weight.
/// Numeric fields are Int?/Double? so "no target" stays distinguishable from
/// a literal 0. Display-only when a session is logged against the routine.
@Model
final class RoutineExercise {
    var name: String
    var targetSets: Int?
    var targetReps: Int?
    var targetWeightLbs: Double?
    var order: Int
    /// Back-pointer to the owning routine. SwiftData fills this in via the
    /// inverse declared on StrengthRoutine.exercises.
    var routine: StrengthRoutine?

    init(name: String,
         targetSets: Int? = nil,
         targetReps: Int? = nil,
         targetWeightLbs: Double? = nil,
         order: Int = 0) {
        self.name = name
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeightLbs = targetWeightLbs
        self.order = order
    }
}

// MARK: StrengthSession (one workout performed)
/// One actual workout session. Owns its LoggedExercises which own their
/// LoggedSets — a two-level cascade. Soft-delete via pendingDeleteAt matches
/// FoodEntry / WaterEntry / WeightEntry; UI applies the 5-second undo pattern.
@Model
final class StrengthSession {
    var loggedAt: Date
    /// Snapshot of the routine's name at the time of logging. Stored as plain
    /// String, NOT a relationship — so renaming or deleting the routine
    /// doesn't retroactively change history.
    var routineName: String?
    /// Optional informational field. NEVER written to Apple Health — see the
    /// header comment for why strength sessions stay in-app.
    var durationMinutes: Double?
    var pendingDeleteAt: Date?

    /// Cascade: deleting a session cascades to its exercises, which cascade
    /// to their sets. Inverse declared here.
    @Relationship(deleteRule: .cascade, inverse: \LoggedExercise.session)
    var exercises: [LoggedExercise] = []

    init(loggedAt: Date = .now,
         routineName: String? = nil,
         durationMinutes: Double? = nil,
         pendingDeleteAt: Date? = nil) {
        self.loggedAt = loggedAt
        self.routineName = routineName
        self.durationMinutes = durationMinutes
        self.pendingDeleteAt = pendingDeleteAt
    }
}

// MARK: LoggedExercise (one exercise performed in a session)
/// One exercise inside a session. Holds NO numeric data of its own — all
/// numbers live on its LoggedSets. Owns those sets with cascade.
@Model
final class LoggedExercise {
    var name: String
    var order: Int
    /// Back-pointer to the owning session.
    var session: StrengthSession?

    @Relationship(deleteRule: .cascade, inverse: \LoggedSet.exercise)
    var sets: [LoggedSet] = []

    init(name: String, order: Int = 0) {
        self.name = name
        self.order = order
    }
}

// MARK: LoggedSet (per-set detail — the point of strength tracking)
/// One performed set. Weight and reps are Int?/Double? — a set logged with
/// no weight (e.g. body-weight pull-up) stays nil, never 0. setNumber is
/// auto-assigned in the log UI and used purely for display order.
@Model
final class LoggedSet {
    var weightLbs: Double?
    var reps: Int?
    var setNumber: Int
    /// Back-pointer to the owning exercise.
    var exercise: LoggedExercise?

    init(weightLbs: Double? = nil, reps: Int? = nil, setNumber: Int) {
        self.weightLbs = weightLbs
        self.reps = reps
        self.setNumber = setNumber
    }
}

