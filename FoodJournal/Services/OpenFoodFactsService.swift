import Foundation

// Open Food Facts is free, no API key needed.
// Docs: https://openfoodfacts.github.io/openfoodfacts-server/api/
//
// Their nutriment fields are stored as both "nutrient_100g" and "nutrient_serving"
// (and unit-suffixed variants like "salt_100g"). We pull the per-100g values and
// let the UI scale to grams entered.
enum OpenFoodFactsService {

    struct Product {
        let barcode: String
        let name: String
        let brand: String?
        let servingSizeGrams: Double?

        // Per 100g values. Optional ones may be missing from Open Food Facts.
        let caloriesPer100g: Double
        let proteinPer100g: Double
        let carbsPer100g: Double
        let fatPer100g: Double

        let saturatedFatPer100g: Double?
        let polyunsaturatedFatPer100g: Double?
        let monounsaturatedFatPer100g: Double?
        let transFatPer100g: Double?
        let fiberPer100g: Double?
        let sugarPer100g: Double?
        let cholesterolPer100g: Double?     // mg
        let sodiumPer100g: Double?          // mg
        let potassiumPer100g: Double?       // mg
        let vitaminAPer100g: Double?        // µg
        let vitaminCPer100g: Double?        // mg
        let vitaminDPer100g: Double?        // µg
        let calciumPer100g: Double?         // mg
        let ironPer100g: Double?            // mg
        let magnesiumPer100g: Double?       // mg
    }

    enum ServiceError: Error {
        case notFound
        case incompleteData
        case network(String)
    }

    static func lookup(barcode: String) async throws -> Product {
        let urlString = "https://world.openfoodfacts.org/api/v2/product/\(barcode).json"
        guard let url = URL(string: urlString) else {
            throw ServiceError.network("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue("FoodJournal/1.0 (personal-use)", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let status = json["status"] as? Int,
            status == 1,
            let product = json["product"] as? [String: Any]
        else {
            throw ServiceError.notFound
        }

        let name = (product["product_name"] as? String)
            ?? (product["generic_name"] as? String)
            ?? "Unknown product"
        let brand = product["brands"] as? String

        guard let nutriments = product["nutriments"] as? [String: Any] else {
            throw ServiceError.incompleteData
        }

        // Required: calories. OFF stores both kcal and kJ — prefer kcal, derive from kJ if needed.
        let kcal = numericValue(nutriments, "energy-kcal_100g")
            ?? numericValue(nutriments, "energy_100g").map { $0 / 4.184 }
            ?? 0
        let protein = numericValue(nutriments, "proteins_100g") ?? 0
        let carbs   = numericValue(nutriments, "carbohydrates_100g") ?? 0
        let fat     = numericValue(nutriments, "fat_100g") ?? 0

        let servingGrams: Double? = numericValue(product, "serving_quantity")

        // OFF stores some values in grams that we want in mg (sodium, salt, calcium, etc.).
        // Their "_100g" fields are typically grams, vitamins are sometimes in IU or %DV.
        // We convert to our canonical units: g for macros, mg for most minerals, µg for A & D.
        let saturated     = numericValue(nutriments, "saturated-fat_100g")
        let polyunsat     = numericValue(nutriments, "polyunsaturated-fat_100g")
        let monounsat     = numericValue(nutriments, "monounsaturated-fat_100g")
        let trans         = numericValue(nutriments, "trans-fat_100g")
        let fiber         = numericValue(nutriments, "fiber_100g")
        let sugar         = numericValue(nutriments, "sugars_100g")

        // Cholesterol on OFF: stored in g per 100g. Convert to mg.
        let cholesterol   = numericValue(nutriments, "cholesterol_100g").map { $0 * 1000 }

        // Sodium: prefer "sodium_100g" (g), fall back to deriving from "salt_100g" (g) using 1g salt = 0.4g sodium.
        let sodium: Double? = {
            if let s = numericValue(nutriments, "sodium_100g") { return s * 1000 }
            if let salt = numericValue(nutriments, "salt_100g") { return salt * 0.4 * 1000 }
            return nil
        }()

        // Potassium and other minerals: g on OFF, we want mg
        let potassium     = numericValue(nutriments, "potassium_100g").map { $0 * 1000 }
        let calcium       = numericValue(nutriments, "calcium_100g").map   { $0 * 1000 }
        let iron          = numericValue(nutriments, "iron_100g").map      { $0 * 1000 }
        let magnesium     = numericValue(nutriments, "magnesium_100g").map { $0 * 1000 }

        // Vitamin A: OFF in g, we want µg
        let vitaminA      = numericValue(nutriments, "vitamin-a_100g").map { $0 * 1_000_000 }
        // Vitamin C: OFF in g, we want mg
        let vitaminC      = numericValue(nutriments, "vitamin-c_100g").map { $0 * 1000 }
        // Vitamin D: OFF in g, we want µg
        let vitaminD      = numericValue(nutriments, "vitamin-d_100g").map { $0 * 1_000_000 }

        return Product(
            barcode: barcode,
            name: name,
            brand: brand,
            servingSizeGrams: servingGrams,
            caloriesPer100g: kcal,
            proteinPer100g: protein,
            carbsPer100g: carbs,
            fatPer100g: fat,
            saturatedFatPer100g: saturated,
            polyunsaturatedFatPer100g: polyunsat,
            monounsaturatedFatPer100g: monounsat,
            transFatPer100g: trans,
            fiberPer100g: fiber,
            sugarPer100g: sugar,
            cholesterolPer100g: cholesterol,
            sodiumPer100g: sodium,
            potassiumPer100g: potassium,
            vitaminAPer100g: vitaminA,
            vitaminCPer100g: vitaminC,
            vitaminDPer100g: vitaminD,
            calciumPer100g: calcium,
            ironPer100g: iron,
            magnesiumPer100g: magnesium
        )
    }

    /// OFF returns numbers as either Double or String; this normalizes both.
    private static func numericValue(_ dict: [String: Any], _ key: String) -> Double? {
        if let d = dict[key] as? Double { return d }
        if let i = dict[key] as? Int { return Double(i) }
        if let s = dict[key] as? String { return Double(s) }
        return nil
    }
}
