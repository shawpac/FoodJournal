import Foundation
import UIKit
import CryptoKit

enum ClaudeVisionService {

    struct Estimate: Decodable {
        let name: String
        let servings: Double
        let serving_unit: String
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let confidence: String
        let notes: String?

        // All optional — Claude returns null when it can't reasonably estimate.
        let saturated_fat: Double?
        let polyunsaturated_fat: Double?
        let monounsaturated_fat: Double?
        let trans_fat: Double?
        let fiber: Double?
        let sugar: Double?
        let cholesterol: Double?
        let sodium: Double?
        let potassium: Double?
        let vitamin_a: Double?
        let vitamin_c: Double?
        let vitamin_d: Double?
        let calcium: Double?
        let iron: Double?
        let magnesium: Double?
    }

    enum ServiceError: LocalizedError {
        case missingAPIKey
        case imageEncodingFailed
        case badResponse(Int, String)
        case parseFailed(String)
        case networkError(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "API key is missing. Add it in Settings."
            case .imageEncodingFailed:
                return "Could not encode image as JPEG."
            case .badResponse(let code, let body):
                let preview = String(body.prefix(300))
                return "API returned HTTP \(code): \(preview)"
            case .parseFailed(let detail):
                return "Could not parse Claude's response: \(detail)"
            case .networkError(let detail):
                return "Network error: \(detail)"
            }
        }
    }

    static let model = "claude-sonnet-4-6"

    /// Produces the resized/compressed JPEG bytes and a SHA256 hash of the resized
    /// image's raw pixels. Use the hash as a cache key — same photo in = same hash out.
    static func prepareImage(_ image: UIImage) -> (jpeg: Data, hash: String)? {
        let resized = image.resizedForUpload(maxDimension: 768)
        guard let jpeg = resized.jpegData(compressionQuality: 0.6) else { return nil }
        guard let pixelData = resized.pixelData() else { return nil }
        let digest = SHA256.hash(data: pixelData)
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return (jpeg, hash)
    }

    /// Multi-image variant of prepareImage. Returns prepared JPEGs and a stable
    /// combined cache hash. For a single image, the combined hash equals
    /// prepareImage's hash so existing single-photo cache entries keep hitting.
    /// For N images, the hash is SHA256 over the sorted individual hashes —
    /// order-independent so re-taking the same set in any order maps to the
    /// same cache entry.
    static func prepareImages(_ images: [UIImage]) -> (jpegs: [Data], hash: String)? {
        guard !images.isEmpty else { return nil }
        var prepared: [(jpeg: Data, hash: String)] = []
        for img in images {
            guard let p = prepareImage(img) else { return nil }
            prepared.append(p)
        }
        let jpegs = prepared.map(\.jpeg)
        let combined: String
        if prepared.count == 1 {
            combined = prepared[0].hash
        } else {
            let joined = prepared.map(\.hash).sorted().joined()
            let digest = SHA256.hash(data: Data(joined.utf8))
            combined = digest.map { String(format: "%02x", $0) }.joined()
        }
        return (jpegs, combined)
    }

    /// The system prompt sent with every photo. Built as joined lines to avoid
    /// Swift's multi-line string indentation rules biting us.
    /// Single-photo wording — used when only one image is attached.
    private static let promptText: String = [
        "Analyze this photo of food and estimate its nutrition for ONE serving as shown.",
        "",
        "Return ONLY a JSON object — no markdown, no prose — with this exact shape:",
        "{",
        "  \"name\": \"short descriptive name\",",
        "  \"servings\": 1,",
        "  \"serving_unit\": \"plate\" | \"bowl\" | \"piece\" | \"cup\" | \"g\",",
        "  \"calories\": number,",
        "  \"protein\": number,",
        "  \"carbs\": number,",
        "  \"fat\": number,",
        "  \"saturated_fat\": number or null,",
        "  \"polyunsaturated_fat\": number or null,",
        "  \"monounsaturated_fat\": number or null,",
        "  \"trans_fat\": number or null,",
        "  \"fiber\": number or null,",
        "  \"sugar\": number or null,",
        "  \"cholesterol\": number or null,",
        "  \"sodium\": number or null,",
        "  \"potassium\": number or null,",
        "  \"vitamin_a\": number or null,",
        "  \"vitamin_c\": number or null,",
        "  \"vitamin_d\": number or null,",
        "  \"calcium\": number or null,",
        "  \"iron\": number or null,",
        "  \"magnesium\": number or null,",
        "  \"confidence\": \"high\" | \"medium\" | \"low\",",
        "  \"notes\": \"optional caveat about your estimate\"",
        "}",
        "",
        "Units (only fill if you can reasonably estimate, otherwise null):",
        "- Macros and fiber/sugar/fats: grams",
        "- Cholesterol, sodium, potassium, vitamin C, calcium, iron, magnesium: milligrams",
        "- Vitamin A, vitamin D: micrograms (µg)",
        "",
        "Use null for fields you genuinely cannot estimate from a photo. Do NOT guess",
        "vitamin/mineral content unless the food is well-known to be a significant",
        "source (e.g., orange = vitamin C, milk = calcium, leafy greens = iron).",
        "",
        "Be realistic about portion size. If ambiguous, assume a typical adult portion",
        "and lower your confidence accordingly."
    ].joined(separator: "\n")

    /// Multi-photo variant of the prompt. Used whenever 2+ images are attached.
    private static let multiPromptText: String = [
        "Analyze the food shown in these photos. The photos show the SAME meal",
        "from different angles — use ALL of them together to refine your single",
        "estimate of the meal's nutrition for ONE serving as shown.",
        "",
        "Return ONLY a JSON object — no markdown, no prose — with this exact shape:",
        "{",
        "  \"name\": \"short descriptive name\",",
        "  \"servings\": 1,",
        "  \"serving_unit\": \"plate\" | \"bowl\" | \"piece\" | \"cup\" | \"g\",",
        "  \"calories\": number,",
        "  \"protein\": number,",
        "  \"carbs\": number,",
        "  \"fat\": number,",
        "  \"saturated_fat\": number or null,",
        "  \"polyunsaturated_fat\": number or null,",
        "  \"monounsaturated_fat\": number or null,",
        "  \"trans_fat\": number or null,",
        "  \"fiber\": number or null,",
        "  \"sugar\": number or null,",
        "  \"cholesterol\": number or null,",
        "  \"sodium\": number or null,",
        "  \"potassium\": number or null,",
        "  \"vitamin_a\": number or null,",
        "  \"vitamin_c\": number or null,",
        "  \"vitamin_d\": number or null,",
        "  \"calcium\": number or null,",
        "  \"iron\": number or null,",
        "  \"magnesium\": number or null,",
        "  \"confidence\": \"high\" | \"medium\" | \"low\",",
        "  \"notes\": \"optional caveat about your estimate\"",
        "}",
        "",
        "Units (only fill if you can reasonably estimate, otherwise null):",
        "- Macros and fiber/sugar/fats: grams",
        "- Cholesterol, sodium, potassium, vitamin C, calcium, iron, magnesium: milligrams",
        "- Vitamin A, vitamin D: micrograms (µg)",
        "",
        "Use null for fields you genuinely cannot estimate. Do NOT guess vitamin/mineral",
        "content unless the food is well-known to be a significant source.",
        "",
        "Be realistic about portion size. Use the additional angles to disambiguate."
    ].joined(separator: "\n")

    /// Convenience wrapper around the multi-image estimate. Kept for back-compat
    /// with the existing single-photo call site.
    static func estimate(image: UIImage, apiKey: String) async throws -> Estimate {
        try await estimate(images: [image], apiKey: apiKey)
    }

    static func estimate(images: [UIImage], apiKey: String) async throws -> Estimate {
        print("ClaudeVisionService: starting estimate, key length \(apiKey.count), images \(images.count)")
        guard !apiKey.isEmpty else { throw ServiceError.missingAPIKey }
        guard !images.isEmpty else { throw ServiceError.imageEncodingFailed }

        guard let prepared = prepareImages(images) else {
            throw ServiceError.imageEncodingFailed
        }
        print("ClaudeVisionService: prepared \(prepared.jpegs.count) image(s), combined hash \(prepared.hash.prefix(8))…")

        var content: [[String: Any]] = prepared.jpegs.map { jpeg in
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": jpeg.base64EncodedString()
                ]
            ]
        }
        let text = prepared.jpegs.count > 1 ? multiPromptText : promptText
        content.append(["type": "text", "text": text])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [[
                "role": "user",
                "content": content
            ]]
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 90

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)

        var lastError: Error?
        for attempt in 1...3 {
            print("ClaudeVisionService: attempt \(attempt)")
            do {
                let (data, response) = try await session.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    throw ServiceError.networkError("response was not HTTP")
                }
                let bodyText = String(data: data, encoding: .utf8) ?? "<binary>"
                print("ClaudeVisionService: HTTP \(http.statusCode), body length \(data.count)")

                guard (200..<300).contains(http.statusCode) else {
                    throw ServiceError.badResponse(http.statusCode, bodyText)
                }

                guard
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let content = json["content"] as? [[String: Any]],
                    let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String
                else {
                    throw ServiceError.parseFailed("no text block in response. Body: \(String(bodyText.prefix(300)))")
                }

                let cleaned = text
                    .replacingOccurrences(of: "```json", with: "")
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard let jsonData = cleaned.data(using: .utf8) else {
                    throw ServiceError.parseFailed("could not encode model output")
                }

                do {
                    return try JSONDecoder().decode(Estimate.self, from: jsonData)
                } catch {
                    throw ServiceError.parseFailed("decode error: \(error.localizedDescription) — output was: \(cleaned)")
                }

            } catch let error as ServiceError {
                throw error
            } catch let urlError as URLError where shouldRetry(urlError) {
                lastError = urlError
                print("ClaudeVisionService: transient \(urlError.code.rawValue), will retry")
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                continue
            } catch {
                throw ServiceError.networkError(error.localizedDescription)
            }
        }

        throw ServiceError.networkError(
            "Network kept dropping after 3 tries. Last error: \(lastError?.localizedDescription ?? "unknown")"
        )
    }

    private static func shouldRetry(_ error: URLError) -> Bool {
        switch error.code {
        case .networkConnectionLost,
             .timedOut,
             .notConnectedToInternet,
             .cannotConnectToHost,
             .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}

fileprivate extension UIImage {
    func resizedForUpload(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Returns raw RGBA pixel bytes by drawing the image into a fixed-format
    /// CGContext. This normalizes away color profile / encoding differences,
    /// so the same visual image always produces the same bytes.
    func pixelData() -> Data? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &bytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let cgImage = self.cgImage
        else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Data(bytes)
    }
}
