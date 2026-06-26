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

    // MARK: - Text search (v2.2.1)

    /// A normalized OFF text-search result. Shape mirrors `USDAService.SearchHit`
    /// so the unified search UI can render USDA and OFF rows identically. Always
    /// has calories (search results without any calorie info are skipped during
    /// parse — they're effectively un-loggable).
    struct SearchHit: Identifiable, Hashable {
        /// OFF's product code (barcode for branded items). Used as identity for
        /// SwiftUI lists and as the dedupe key for the same product from both
        /// sources.
        let id: String
        let name: String
        let brand: String?

        // Per-100g values, units matched to the rest of the app:
        // macros in g; minerals (sodium / potassium / cholesterol / calcium /
        // iron / magnesium) in mg; vitamins A & D in µg; vitamin C in mg.
        // Mirrors `OpenFoodFactsService.Product` (the barcode result) exactly.
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
        let cholesterolPer100g: Double?
        let sodiumPer100g: Double?
        let potassiumPer100g: Double?
        let vitaminAPer100g: Double?
        let vitaminCPer100g: Double?
        let vitaminDPer100g: Double?
        let calciumPer100g: Double?
        let ironPer100g: Double?
        let magnesiumPer100g: Double?
    }

    /// Text-search via OFF's classic `cgi/search.pl` endpoint. Free, no API
    /// key. Returns up to ~25 usable products; malformed ones (no name, no
    /// nutriments block, no calorie info) are SKIPPED rather than included
    /// with fake zeros — fits the project-wide nil ≠ 0 invariant.
    ///
    /// The OFF data is crowd-sourced and FREQUENTLY partial. Missing optional
    /// nutrients (fiber, sugar, sat fat, vitamins, etc.) come back as `nil`
    /// and the UI shows "–" in the breakdown. We deliberately NEVER substitute
    /// 0 — that would silently corrupt the trends layer the same way a stray
    /// 0 protein would.
    static func search(_ query: String) async throws -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")
        components?.queryItems = [
            URLQueryItem(name: "search_terms", value: trimmed),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "25"),
        ]
        guard let url = components?.url else {
            throw ServiceError.network("Invalid OFF search URL")
        }

        var request = URLRequest(url: url)
        request.setValue("FoodJournal/1.0 (personal-use)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ServiceError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ServiceError.network("OFF returned HTTP \(http.statusCode)")
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let products = json["products"] as? [[String: Any]]
        else {
            // Empty / unrecognized response — return zero hits, don't throw.
            // The UI will show "No results" naturally.
            return []
        }

        var hits: [SearchHit] = []
        for product in products {
            if let hit = parseSearchHit(product) {
                hits.append(hit)
            }
            // Defensive: malformed products are skipped, never included with
            // fabricated values. A bad entry must not pollute the list.
            if hits.count >= 25 { break }
        }
        return hits
    }

    /// Parses one OFF product dict (from either the search response or the
    /// barcode response, schema is identical). Returns nil for products we
    /// can't safely log: no name, no nutriments block, OR no usable calorie
    /// info. The nutrient conversions mirror `lookup(barcode:)` exactly —
    /// if those ever change, update both call sites.
    private static func parseSearchHit(_ product: [String: Any]) -> SearchHit? {
        // Identity. Prefer "code" (OFF's primary key — usually the barcode);
        // fall back to a content-derived synthetic if missing.
        let code = (product["code"] as? String) ?? (product["_id"] as? String) ?? ""
        guard !code.isEmpty else { return nil }

        // Name — required. Skip products with no display name.
        let rawName = (product["product_name"] as? String)
            ?? (product["generic_name"] as? String)
            ?? ""
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let brand = (product["brands"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Nutriments block — required.
        guard let nutriments = product["nutriments"] as? [String: Any] else {
            return nil
        }

        // Calories. Prefer kcal_100g; fall back to energy_100g (kJ) / 4.184.
        // If BOTH are missing, the product is un-loggable — skip it. This is
        // the only divergence from `lookup(barcode:)`, which defaults missing
        // calories to 0 and trusts the user to fix in Confirm. For search
        // results, an entry with no calories is junk and should not appear.
        let kcal: Double? = numericValue(nutriments, "energy-kcal_100g")
            ?? numericValue(nutriments, "energy_100g").map { $0 / 4.184 }
        guard let kcal else { return nil }

        // Required macros. OFF often has these; when it doesn't, treat as 0
        // for the required model fields (FoodEntry.protein/carbs/fat are
        // non-optional Double). The user can correct in Confirm. This is NOT
        // a nil-vs-zero violation — these fields cannot hold nil at the model
        // level; the nil ≠ 0 rule applies to the OPTIONAL `Double?` nutrients
        // below.
        let protein = numericValue(nutriments, "proteins_100g") ?? 0
        let carbs   = numericValue(nutriments, "carbohydrates_100g") ?? 0
        let fat     = numericValue(nutriments, "fat_100g") ?? 0

        // Optional nutrients — nil stays nil. Unit conversions mirror the
        // barcode path: macros in g; minerals (cholesterol / sodium /
        // potassium / calcium / iron / magnesium) in mg; vitamins A & D in
        // µg; vitamin C in mg.
        let saturated = numericValue(nutriments, "saturated-fat_100g")
        let polyunsat = numericValue(nutriments, "polyunsaturated-fat_100g")
        let monounsat = numericValue(nutriments, "monounsaturated-fat_100g")
        let trans     = numericValue(nutriments, "trans-fat_100g")
        let fiber     = numericValue(nutriments, "fiber_100g")
        let sugar     = numericValue(nutriments, "sugars_100g")

        let cholesterol = numericValue(nutriments, "cholesterol_100g").map { $0 * 1000 }

        // Sodium fallback chain matches the barcode path.
        let sodium: Double? = {
            if let s = numericValue(nutriments, "sodium_100g") { return s * 1000 }
            if let salt = numericValue(nutriments, "salt_100g") { return salt * 0.4 * 1000 }
            return nil
        }()

        let potassium = numericValue(nutriments, "potassium_100g").map { $0 * 1000 }
        let calcium   = numericValue(nutriments, "calcium_100g").map   { $0 * 1000 }
        let iron      = numericValue(nutriments, "iron_100g").map      { $0 * 1000 }
        let magnesium = numericValue(nutriments, "magnesium_100g").map { $0 * 1000 }

        let vitaminA = numericValue(nutriments, "vitamin-a_100g").map { $0 * 1_000_000 }
        let vitaminC = numericValue(nutriments, "vitamin-c_100g").map { $0 * 1000 }
        let vitaminD = numericValue(nutriments, "vitamin-d_100g").map { $0 * 1_000_000 }

        return SearchHit(
            id: code,
            name: name,
            brand: (brand?.isEmpty ?? true) ? nil : brand,
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
}

extension OpenFoodFactsService.SearchHit {
    /// Convert an OFF search hit into the same `ConfirmFoodView.Prefill`
    /// shape USDA hits produce. Caller sees a uniform value type either
    /// way, which keeps SearchSheet's pick flow simple.
    func toPrefill() -> ConfirmFoodView.Prefill {
        ConfirmFoodView.Prefill(
            name: name,
            brand: brand,
            // OFF's `id` is typically a barcode — pass it through so the
            // resulting FoodEntry carries the barcode like a Scan-barcode
            // entry would. Searches that landed via OFF can still be deduped
            // against future barcode scans.
            barcode: id,
            servingSizeGrams: 100,
            caloriesPer100g: caloriesPer100g,
            proteinPer100g: proteinPer100g,
            carbsPer100g: carbsPer100g,
            fatPer100g: fatPer100g,
            saturatedFatPer100g: saturatedFatPer100g,
            polyunsaturatedFatPer100g: polyunsaturatedFatPer100g,
            monounsaturatedFatPer100g: monounsaturatedFatPer100g,
            transFatPer100g: transFatPer100g,
            fiberPer100g: fiberPer100g,
            sugarPer100g: sugarPer100g,
            cholesterolPer100g: cholesterolPer100g,
            sodiumPer100g: sodiumPer100g,
            potassiumPer100g: potassiumPer100g,
            vitaminAPer100g: vitaminAPer100g,
            vitaminCPer100g: vitaminCPer100g,
            vitaminDPer100g: vitaminDPer100g,
            calciumPer100g: calciumPer100g,
            ironPer100g: ironPer100g,
            magnesiumPer100g: magnesiumPer100g
        )
    }
}
