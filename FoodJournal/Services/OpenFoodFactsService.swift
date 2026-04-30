import Foundation

// Open Food Facts is free, no API key needed.
// Docs: https://openfoodfacts.github.io/openfoodfacts-server/api/
enum OpenFoodFactsService {

    struct Product {
        let barcode: String
        let name: String
        let brand: String?
        let caloriesPer100g: Double
        let proteinPer100g: Double
        let carbsPer100g: Double
        let fatPer100g: Double
        let servingSizeGrams: Double?
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

        // Open Food Facts uses both "energy-kcal_100g" and sometimes only kJ.
        let kcal = (nutriments["energy-kcal_100g"] as? Double)
            ?? ((nutriments["energy_100g"] as? Double).map { $0 / 4.184 })
            ?? 0
        let protein = (nutriments["proteins_100g"] as? Double) ?? 0
        let carbs = (nutriments["carbohydrates_100g"] as? Double) ?? 0
        let fat = (nutriments["fat_100g"] as? Double) ?? 0

        let servingGrams: Double? = {
            if let s = product["serving_quantity"] as? Double { return s }
            if let s = product["serving_quantity"] as? String { return Double(s) }
            return nil
        }()

        return Product(
            barcode: barcode,
            name: name,
            brand: brand,
            caloriesPer100g: kcal,
            proteinPer100g: protein,
            carbsPer100g: carbs,
            fatPer100g: fat,
            servingSizeGrams: servingGrams
        )
    }
}
