import Foundation

/// Talks to USDA FoodData Central. Free public API, requires a personal API key
/// (https://api.data.gov/signup/). All foods returned are mapped to per-100g values
/// to slot directly into ConfirmFoodView.Prefill.
///
/// Default search hits Foundation + SR Legacy + Survey datasets — the high-quality
/// generic foods. Branded foods are excluded by default to keep results clean
/// (the user already has barcode scanning for branded items).
enum USDAService {

    enum USDAError: LocalizedError {
        case missingKey
        case invalidURL
        case network(String)
        case http(Int, String)    // status code + response body (api.data.gov returns a JSON message with details)
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .missingKey:        return "USDA API key not set. Add one in Settings → USDA API key."
            case .invalidURL:        return "Couldn't construct the search URL."
            case .network(let m):    return "Network error: \(m)"
            case .http(let code, let body):
                let preview = String(body.prefix(300))
                return "USDA HTTP \(code). \(preview)"
            case .decode(let m):     return "Couldn't read USDA response: \(m)"
            }
        }
    }

    /// Public-facing search result — what the search UI displays in its list.
    /// Already mapped to per-100g; slots directly into ConfirmFoodView.Prefill.
    struct SearchHit: Identifiable, Hashable {
        let id: Int                  // fdcId
        let name: String
        let brand: String?
        let dataType: String         // "Foundation" / "SR Legacy" / "Survey (FNDDS)" / "Branded"

        // Per-100g
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

    // MARK: - Public API

    /// Search USDA. Returns up to 25 results. Throws USDAError on failure.
    /// `includeBranded` defaults to false; set true to include manufacturer-submitted foods.
    static func search(_ query: String, includeBranded: Bool = false) async throws -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Trim defensively — pasting from email sometimes carries trailing
        // whitespace or a newline that URLQueryItem then percent-encodes
        // into the api_key value, turning a valid key into a malformed one
        // (and api.data.gov returns 400, not a clear "bad key" message).
        let key = KeychainStore.load(.usda).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw USDAError.missingKey }

        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")
                let dataTypes = includeBranded
                    ? "Foundation,SR Legacy,Survey (FNDDS),Branded"
                    : "Foundation,SR Legacy,Survey (FNDDS)"
                let items: [URLQueryItem] = [
                    URLQueryItem(name: "api_key", value: key),
                    URLQueryItem(name: "query", value: trimmed),
                    URLQueryItem(name: "pageSize", value: "25"),
                    URLQueryItem(name: "dataType", value: dataTypes)
                ]
                components?.queryItems = items

        // URLComponents doesn't percent-encode parentheses by default, but USDA's
                // nginx fronting layer rejects URLs with raw `(` or `)`. Force-encode them.
                if let encoded = components?.percentEncodedQuery {
                    components?.percentEncodedQuery = encoded
                        .replacingOccurrences(of: "(", with: "%28")
                        .replacingOccurrences(of: ")", with: "%29")
                }

                guard let url = components?.url else { throw USDAError.invalidURL }


                var req = URLRequest(url: url)
                req.timeoutInterval = 15

                let (data, response): (Data, URLResponse)
                do {
                    (data, response) = try await URLSession.shared.data(for: req)
                } catch {
                    throw USDAError.network(error.localizedDescription)
                }

                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    // api.data.gov returns a JSON message in the response
                    // body explaining what was wrong (invalid key, bad
                    // parameter, etc.). Surface it via the error so the
                    // user can see the actual cause in the search sheet.
                    let bodyText = String(data: data, encoding: .utf8) ?? "<no body>"
                    throw USDAError.http(http.statusCode, bodyText)
                }

        let decoded: SearchResponse
        do {
            decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw USDAError.decode(error.localizedDescription)
        }

        return decoded.foods.map { mapToHit($0) }
    }

    // MARK: - Wire types (USDA's response shape)

    private struct SearchResponse: Decodable {
        let foods: [Food]
    }

    private struct Food: Decodable {
        let fdcId: Int
        let description: String
        let dataType: String?
        let brandOwner: String?
        let brandName: String?
        let foodNutrients: [Nutrient]?
        let servingSize: Double?
        let servingSizeUnit: String?
    }

    private struct Nutrient: Decodable {
        // Different USDA endpoints use slightly different field names; we cover both.
        let nutrientId: Int?
        let nutrientName: String?
        let unitName: String?
        let value: Double?

        // Some responses nest under "nutrient": { "id": ..., "name": ..., "unitName": ... }
        let nutrient: NestedNutrient?
        let amount: Double?

        struct NestedNutrient: Decodable {
            let id: Int?
            let name: String?
            let unitName: String?
        }

        var resolvedId: Int? { nutrientId ?? nutrient?.id }
        var resolvedValue: Double? { value ?? amount }
        var resolvedUnit: String? { unitName ?? nutrient?.unitName }
    }

    // MARK: - Mapping

    /// Nutrient ID reference (USDA standard, see https://fdc.nal.usda.gov/docs/Nutrient_IDs.pdf).
    private enum NID {
        static let calories            = 1008
        static let protein             = 1003
        static let totalFat            = 1004
        static let carbs               = 1005
        static let fiber               = 1079
        static let sugar               = 2000   // total sugars
        static let saturatedFat        = 1258
        static let polyunsaturatedFat  = 1293
        static let monounsaturatedFat  = 1292
        static let transFat            = 1257
        static let cholesterol         = 1253
        static let sodium              = 1093
        static let potassium           = 1092
        static let vitaminA            = 1106   // µg RAE
        static let vitaminC            = 1162
        static let vitaminD            = 1114   // µg
        static let calcium             = 1087
        static let iron                = 1089
        static let magnesium           = 1090
    }

    private static func mapToHit(_ food: Food) -> SearchHit {
        let nutrients = food.foodNutrients ?? []

        // Build a lookup by nutrient ID, with all values normalized to per-100g.
        // Foundation/SR/Survey foods report per-100g already. Branded foods sometimes
        // report per-serving — but USDA's foods/search endpoint returns Branded values
        // already normalized to per-100g for the labelNutrients alternative.
        // For this v1, we trust whatever value USDA returns and just key by nutrient ID.
        // If it ever looks wrong for a branded item, we'll add scaling here.
        var byId: [Int: Double] = [:]
        for n in nutrients {
            if let id = n.resolvedId, let v = n.resolvedValue {
                byId[id] = v
            }
        }

        func g(_ id: Int) -> Double { byId[id] ?? 0 }
        func opt(_ id: Int) -> Double? { byId[id] }

        let brand: String? = {
            if let b = food.brandName, !b.isEmpty { return b }
            if let b = food.brandOwner, !b.isEmpty { return b }
            return nil
        }()

        return SearchHit(
            id: food.fdcId,
            name: food.description,
            brand: brand,
            dataType: food.dataType ?? "",
            caloriesPer100g: g(NID.calories),
            proteinPer100g:  g(NID.protein),
            carbsPer100g:    g(NID.carbs),
            fatPer100g:      g(NID.totalFat),
            saturatedFatPer100g:       opt(NID.saturatedFat),
            polyunsaturatedFatPer100g: opt(NID.polyunsaturatedFat),
            monounsaturatedFatPer100g: opt(NID.monounsaturatedFat),
            transFatPer100g:           opt(NID.transFat),
            fiberPer100g:    opt(NID.fiber),
            sugarPer100g:    opt(NID.sugar),
            cholesterolPer100g: opt(NID.cholesterol),
            sodiumPer100g:      opt(NID.sodium),
            potassiumPer100g:   opt(NID.potassium),
            vitaminAPer100g:    opt(NID.vitaminA),
            vitaminCPer100g:    opt(NID.vitaminC),
            vitaminDPer100g:    opt(NID.vitaminD),
            calciumPer100g:     opt(NID.calcium),
            ironPer100g:        opt(NID.iron),
            magnesiumPer100g:   opt(NID.magnesium)
        )
    }
}

extension USDAService.SearchHit {
    /// Convert a USDA search hit into the prefill struct ConfirmFoodView already accepts.
    /// Defaults to a 100g serving size since that's the USDA reference.
    func toPrefill() -> ConfirmFoodView.Prefill {
        ConfirmFoodView.Prefill(
            name: name,
            brand: brand,
            barcode: nil,
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
