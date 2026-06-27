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
    /// combined cache hash. For a single image with no context, the combined
    /// hash equals prepareImage's hash so existing single-photo cache entries
    /// keep hitting. For N images, the hash is SHA256 over the sorted
    /// individual hashes — order-independent so re-taking the same set in any
    /// order maps to the same cache entry.
    ///
    /// v2.2.2 — `userContext` is optional typed text the user attached to the
    /// photo set (weight, brand, prep notes). When non-empty, it's folded
    /// into the cache hash so the same photo with different context misses
    /// cache and re-queries Claude. When empty, the hash is unchanged from
    /// v1.8.5 — existing cache entries keep hitting.
    static func prepareImages(_ images: [UIImage], userContext: String = "") -> (jpegs: [Data], hash: String)? {
        guard !images.isEmpty else { return nil }
        var prepared: [(jpeg: Data, hash: String)] = []
        for img in images {
            guard let p = prepareImage(img) else { return nil }
            prepared.append(p)
        }
        let jpegs = prepared.map(\.jpeg)
        let imageHash: String
        if prepared.count == 1 {
            imageHash = prepared[0].hash
        } else {
            let joined = prepared.map(\.hash).sorted().joined()
            let digest = SHA256.hash(data: Data(joined.utf8))
            imageHash = digest.map { String(format: "%02x", $0) }.joined()
        }

        // v2.2.2 — fold normalized user context into the cache hash. Empty
        // context falls through to the v1.8.5 hash unchanged.
        let trimmedContext = userContext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContext.isEmpty else {
            return (jpegs, imageHash)
        }
        let composite = imageHash + "|ctx|" + trimmedContext.lowercased()
        let contextDigest = SHA256.hash(data: Data(composite.utf8))
        let finalHash = contextDigest.map { String(format: "%02x", $0) }.joined()
        return (jpegs, finalHash)
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

    /// v2.2.2 — Prepends the user-provided context block to the base prompt
    /// when non-empty. The block instructs Claude to treat the user's text
    /// (weights, names, brands, prep details) as more authoritative than what
    /// it would infer from pixels alone. Empty context returns the base
    /// prompt unchanged.
    private static func fullPrompt(base: String, userContext: String) -> String {
        let trimmed = userContext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        let contextBlock = [
            "Additional context from the user:",
            trimmed,
            "",
            "Treat this user-provided information as authoritative — prefer any weights, names, brands, or preparation details the user has given over what you would infer from the photo alone. Use the photo to fill in the rest.",
            "",
            "",
        ].joined(separator: "\n")
        return contextBlock + base
    }

    /// Convenience wrapper around the multi-image estimate. Kept for back-compat
    /// with the existing single-photo call site.
    static func estimate(image: UIImage, apiKey: String) async throws -> Estimate {
        try await estimate(images: [image], userContext: "", apiKey: apiKey)
    }

    /// v2.2.2 — `userContext` is optional typed text the user attached to the
    /// photo set (weight, brand, prep notes). When non-empty, it's prepended
    /// to the prompt with instructions to prefer the user's information over
    /// what Claude would infer from the photo alone. Empty context preserves
    /// the original prompt verbatim.
    static func estimate(images: [UIImage], userContext: String = "", apiKey: String) async throws -> Estimate {
        print("ClaudeVisionService: starting estimate, key length \(apiKey.count), images \(images.count), context chars \(userContext.count)")
        guard !apiKey.isEmpty else { throw ServiceError.missingAPIKey }
        guard !images.isEmpty else { throw ServiceError.imageEncodingFailed }

        guard let prepared = prepareImages(images, userContext: userContext) else {
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
        let base = prepared.jpegs.count > 1 ? multiPromptText : promptText
        let text = fullPrompt(base: base, userContext: userContext)
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

    // MARK: - v2.3a — Lab report transcription
    //
    // SAFETY: this is a TRANSCRIPTION path, not an interpretation path. The
    // prompt forbids medical commentary, unit conversion, and inventing
    // reference ranges. Extracted output is NEVER saved directly — the UI
    // surfaces an editable review screen and only the user's confirmed
    // version persists.

    struct ExtractedLabReport: Decodable {
        let collected_date: String?  // "YYYY-MM-DD" or null
        let source: String?           // lab name printed on the report, if visible
        let results: [ExtractedLabResult]
    }

    struct ExtractedLabResult: Decodable {
        let test_name: String
        let value: Double?
        let value_text: String?
        let unit: String?
        let ref_range_low: Double?
        let ref_range_high: Double?
        let ref_range_text: String?
    }

    private static let labExtractionPrompt: String = [
        "Transcribe the lab test results from this image of a lab report (or page of one).",
        "",
        "Return ONLY a JSON object — no markdown, no prose — with this exact shape:",
        "{",
        "  \"collected_date\": \"YYYY-MM-DD\" or null,",
        "  \"source\": \"lab name printed on the report (e.g. LabCorp, Quest)\" or null,",
        "  \"results\": [",
        "    {",
        "      \"test_name\": \"exact name as printed (e.g. Hemoglobin A1c)\",",
        "      \"value\": numeric result or null,",
        "      \"value_text\": \"qualitative result (e.g. Negative, Detected, <0.1, >100)\" or null,",
        "      \"unit\": \"exact unit as printed (mg/dL, %, mmol/L, ng/mL, etc.)\" or null,",
        "      \"ref_range_low\": numeric lower bound or null,",
        "      \"ref_range_high\": numeric upper bound or null,",
        "      \"ref_range_text\": \"verbatim non-simple range (e.g. <5.7, Negative)\" or null",
        "    }",
        "  ]",
        "}",
        "",
        "CRITICAL TRANSCRIPTION RULES — read carefully:",
        "- Transcribe EXACTLY what is printed. Do NOT infer, normalize, or interpret values.",
        "- Do NOT convert units. If the page says \"mg/dL\", return \"mg/dL\" — never convert to mmol/L or anything else.",
        "- Do NOT add reference ranges that are not printed on the page. If a test has no range printed,",
        "  return null for ALL of ref_range_low, ref_range_high, and ref_range_text. Do NOT consult",
        "  medical knowledge for ranges — only what is visible on the page.",
        "- For numeric ranges printed as \"low – high\" or \"low - high\" or \"low to high\",",
        "  fill ref_range_low and ref_range_high. For ranges like \"<5.7\", \">10\", \"Negative\",",
        "  or any non-low–high format, put the verbatim text in ref_range_text and leave",
        "  ref_range_low and ref_range_high null.",
        "- For qualitative results (\"Negative\", \"Detected\", \"Positive\", \"None\"), put the text in value_text",
        "  and leave value null. NEVER coerce a qualitative result to 0 or 1.",
        "- For numeric values printed as \">100\" or \"<0.1\", put the verbatim text in value_text and",
        "  leave value null. A bounded value cannot be transcribed as a plain number.",
        "- If you cannot read a field clearly, return null for that field. Do NOT guess.",
        "- Skip any test row where you cannot read the test name. Do NOT invent placeholder names.",
        "",
        "This is transcription only. Make NO medical interpretation. Do NOT comment on whether",
        "values are high or low, normal or abnormal, or what they might mean — the app will compare",
        "values to the printed reference ranges itself and present a neutral indicator. Anything",
        "beyond literal transcription is out of scope."
    ].joined(separator: "\n")

    /// Send a photo of a lab report to Claude for STRUCTURED TRANSCRIPTION
    /// (not interpretation). Output populates an editable review screen —
    /// nothing extracted here is ever persisted directly.
    /// Reuses `prepareImage` and the v1.4 API plumbing patterns from
    /// `estimate(images:userContext:apiKey:)`.
    static func extractLabReport(image: UIImage, apiKey: String) async throws -> ExtractedLabReport {
        print("ClaudeVisionService: starting lab extraction (image), key length \(apiKey.count)")
        guard !apiKey.isEmpty else { throw ServiceError.missingAPIKey }
        guard let prepared = prepareImage(image) else { throw ServiceError.imageEncodingFailed }
        let content: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": prepared.jpeg.base64EncodedString()
                ]
            ],
            ["type": "text", "text": labExtractionPrompt]
        ]
        return try await performLabExtraction(content: content, apiKey: apiKey)
    }

    /// v2.3a — PDF variant. Sends the raw PDF bytes to Claude via the
    /// `document` content type (supported on Sonnet 3.5+ / Sonnet 4.x). The
    /// model reads multi-page lab reports natively without us rasterizing
    /// each page first. Same transcription-only contract as the image path:
    /// output populates an editable review screen, never persists directly.
    /// Apple Health → Browse → Lab Results → Share → PDF lands here.
    static func extractLabReport(pdfData: Data, apiKey: String) async throws -> ExtractedLabReport {
        print("ClaudeVisionService: starting lab extraction (PDF), key length \(apiKey.count), bytes \(pdfData.count)")
        guard !apiKey.isEmpty else { throw ServiceError.missingAPIKey }
        guard !pdfData.isEmpty else { throw ServiceError.imageEncodingFailed }
        let content: [[String: Any]] = [
            [
                "type": "document",
                "source": [
                    "type": "base64",
                    "media_type": "application/pdf",
                    "data": pdfData.base64EncodedString()
                ]
            ],
            ["type": "text", "text": labExtractionPrompt]
        ]
        return try await performLabExtraction(content: content, apiKey: apiKey)
    }

    /// Shared request/response/retry plumbing for both image and PDF lab
    /// extraction. max_tokens 8192 to cover multi-page panels with 30+ tests
    /// (Anthropic only bills for output tokens used, not the max).
    private static func performLabExtraction(content: [[String: Any]], apiKey: String) async throws -> ExtractedLabReport {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8192,
            "messages": [["role": "user", "content": content]]
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // PDFs can be 32MB / 100 pages — give the request room.
        request.timeoutInterval = 180

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 240
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)

        var lastError: Error?
        for attempt in 1...3 {
            print("ClaudeVisionService: lab extract attempt \(attempt)")
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
                    let respContent = json["content"] as? [[String: Any]],
                    let text = respContent.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String
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
                    return try JSONDecoder().decode(ExtractedLabReport.self, from: jsonData)
                } catch {
                    throw ServiceError.parseFailed("decode error: \(error.localizedDescription) — output was: \(String(cleaned.prefix(500)))")
                }

            } catch let error as ServiceError {
                throw error
            } catch let urlError as URLError where shouldRetry(urlError) {
                lastError = urlError
                print("ClaudeVisionService: lab extract transient \(urlError.code.rawValue), will retry")
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
