import Foundation
import SwiftData

@Model
final class FoodEntry: Identifiable {
    var id: UUID
    var name: String
    var brand: String?
    var servings: Double
    var servingUnit: String          // e.g. "g", "cup", "piece"
    var calories: Double             // per serving as logged
    var protein: Double              // grams
    var carbs: Double                // grams
    var fat: Double                  // grams
    var loggedAt: Date
    var mealType: String             // "breakfast" | "lunch" | "dinner" | "snack"
    var source: String               // "barcode" | "search" | "photo" | "manual"
    var barcode: String?

    init(
        name: String,
        brand: String? = nil,
        servings: Double = 1,
        servingUnit: String = "serving",
        calories: Double,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        loggedAt: Date = .now,
        mealType: String = "snack",
        source: String = "manual",
        barcode: String? = nil
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
        self.loggedAt = loggedAt
        self.mealType = mealType
        self.source = source
        self.barcode = barcode
    }
}

@Model
final class UserGoals {
    var calorieGoal: Double
    var proteinGoal: Double
    var carbsGoal: Double
    var fatGoal: Double
    var waterGoalOz: Double = 100

    init(
        calorieGoal: Double = 2000,
        proteinGoal: Double = 150,
        carbsGoal: Double = 200,
        fatGoal: Double = 65,
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

    init(amountOz: Double, loggedAt: Date = .now) {
        self.id = UUID()
        self.amountOz = amountOz
        self.loggedAt = loggedAt
    }
}
