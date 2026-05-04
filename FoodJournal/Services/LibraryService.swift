import Foundation
import SwiftData

/// Local-first search over LibraryFood records. Substring + case-insensitive match
/// across name and brand. Sorts by recency × frequency so familiar foods float up.
enum LibraryService {

    /// Search the local library. Returns top 25, sorted by useCount × recency.
    static func search(_ query: String, in context: ModelContext) -> [LibraryFood] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let needle = trimmed.lowercased()
        // SwiftData #Predicate string ops are limited — easier to fetch all and filter in-memory.
        // The library will rarely exceed a few hundred records for a personal app, so the cost is trivial.
        let descriptor = FetchDescriptor<LibraryFood>()
        guard let all = try? context.fetch(descriptor) else { return [] }

        let matches = all.filter { food in
            if food.name.lowercased().contains(needle) { return true }
            if let b = food.brand?.lowercased(), b.contains(needle) { return true }
            return false
        }

        // Score: recently-used and frequently-used both push up.
        // Recency contributes a logarithmic boost, useCount is linear.
        let now = Date.now
        return matches.sorted { a, b in
            let aScore = score(a, now: now)
            let bScore = score(b, now: now)
            return aScore > bScore
        }.prefix(25).map { $0 }
    }

    private static func score(_ food: LibraryFood, now: Date) -> Double {
        let ageDays = max(0, now.timeIntervalSince(food.lastUsedAt) / 86_400)
        let recency = 1.0 / (1.0 + ageDays)         // 1.0 today, 0.5 after 1 day, 0.1 after 9 days
        let frequency = Double(food.useCount)
        return frequency + recency * 5              // recency tip-the-scales for similar useCount
    }

    /// Convert a LibraryFood into the prefill struct ConfirmFoodView accepts.
    /// Handles both per-100g and per-serving storage modes.
    static func toPrefill(_ food: LibraryFood) -> ConfirmFoodView.Prefill {
        if food.isPer100g {
            // Already in the right shape — pass straight through.
            return ConfirmFoodView.Prefill(
                name: food.name,
                brand: food.brand,
                barcode: nil,
                servingSizeGrams: 100,
                caloriesPer100g: food.calories,
                proteinPer100g: food.protein,
                carbsPer100g: food.carbs,
                fatPer100g: food.fat,
                saturatedFatPer100g: food.saturatedFat,
                polyunsaturatedFatPer100g: food.polyunsaturatedFat,
                monounsaturatedFatPer100g: food.monounsaturatedFat,
                transFatPer100g: food.transFat,
                fiberPer100g: food.fiber,
                sugarPer100g: food.sugar,
                cholesterolPer100g: food.cholesterol,
                sodiumPer100g: food.sodium,
                potassiumPer100g: food.potassium,
                vitaminAPer100g: food.vitaminA,
                vitaminCPer100g: food.vitaminC,
                vitaminDPer100g: food.vitaminD,
                calciumPer100g: food.calcium,
                ironPer100g: food.iron,
                magnesiumPer100g: food.magnesium
            )
        } else {
            // Per-serving record (cup, tbsp, "burrito"). Map values into the per-100g slots
            // anyway — ConfirmFoodView treats them as multiplied by grams/100, which works
            // out as long as we tell the user "1 serving = 100g" on the confirm screen.
            // This is a pragmatic compromise. v1 keeps the user flow consistent, even though
            // for a "per-burrito" food the gram input is awkward.
            return ConfirmFoodView.Prefill(
                name: food.name,
                brand: food.brand,
                barcode: nil,
                servingSizeGrams: 100,
                caloriesPer100g: food.calories,
                proteinPer100g: food.protein,
                carbsPer100g: food.carbs,
                fatPer100g: food.fat,
                saturatedFatPer100g: food.saturatedFat,
                polyunsaturatedFatPer100g: food.polyunsaturatedFat,
                monounsaturatedFatPer100g: food.monounsaturatedFat,
                transFatPer100g: food.transFat,
                fiberPer100g: food.fiber,
                sugarPer100g: food.sugar,
                cholesterolPer100g: food.cholesterol,
                sodiumPer100g: food.sodium,
                potassiumPer100g: food.potassium,
                vitaminAPer100g: food.vitaminA,
                vitaminCPer100g: food.vitaminC,
                vitaminDPer100g: food.vitaminD,
                calciumPer100g: food.calcium,
                ironPer100g: food.iron,
                magnesiumPer100g: food.magnesium
            )
        }
    }
}
