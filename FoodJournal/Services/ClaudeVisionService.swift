import Foundation
import UIKit

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

    static let model = "claude-opus-4-7"

    static func estimate(image: UIImage, apiKey: String) async throws -> Estimate {
        print("ClaudeVisionService: starting estimate, key length \(apiKey.count)")
        guard !apiKey.isEmpty else { throw ServiceError.missingAPIKey }

        // Aggressive compression: 768px max + 0.6 quality keeps payload ~50-100KB,
        // which is plenty of detail for food and dodges -1005 connection drops.
        let resized = image.resizedForUpload(maxDimension: 768)
        guard let jpeg = resized.jpegData(compressionQuality: 0.6) else {
            throw ServiceError.imageEncodingFailed
        }
        let base64 = jpeg.base64EncodedString()
        print("ClaudeVisionService: image \(jpeg.count) bytes, base64 \(base64.count) chars")

        let prompt = """
        Analyze this photo of food and estimate its nutrition.

        Return ONLY a JSON object — no markdown, no prose — with this exact shape:
        {
          "name": "short descriptive name",
          "servings": 1,
          "serving_unit": "plate" | "bowl" | "piece" | "cup" | "g",
          "calories": number,
          "protein": number,
          "carbs": number,
          "fat": number,
          "confidence": "high" | "medium" | "low",
          "notes": "optional caveat about your estimate"
        }

        Be realistic. If portion size is ambiguous, assume a typical adult portion and lower your confidence.
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": base64
                        ]
                    ],
                    ["type": "text", "text": prompt]
                ]
            ]]
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 90

        // Use a session with looser timeouts and HTTP/2 retry-friendly behavior.
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)

        // Up to 3 attempts on transient network errors. Each attempt re-uses the same request.
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
                // Don't retry our own logical errors, only network ones.
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
        case .networkConnectionLost,    // -1005
             .timedOut,                 // -1001
             .notConnectedToInternet,   // -1009
             .cannotConnectToHost,      // -1004
             .dnsLookupFailed:          // -1006
            return true
        default:
            return false
        }
    }
}

private extension UIImage {
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
    }
