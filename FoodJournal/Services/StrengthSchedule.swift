import Foundation

/// v2.1b — Storage for the weekly strength schedule. A weekday → routineID
/// map (UUID), persisted as a single JSON-encoded String under one
/// UserDefaults key so it round-trips through `@AppStorage` cleanly. The
/// pattern mirrors how `MealTimeHelper` uses UserDefaults — schema-clean,
/// no new @Model.
///
/// Weekday numbering follows `Calendar.component(.weekday, from:)`:
/// 1 = Sunday … 7 = Saturday. We store ints as String keys in the JSON
/// because JSON object keys must be strings.
///
/// **Robustness**: a stored routineID may no longer resolve (the user
/// deleted that routine). Callers always resolve via `routine(forWeekday:in:)`
/// which returns nil for unresolved IDs — treat unresolved as Rest. Do NOT
/// reach for the raw UUID without resolving; rendering a dangling ID is the
/// fastest way to ship a confusing UI bug.
enum StrengthSchedule {

    /// `@AppStorage` key. SwiftUI views can `@AppStorage(storageKey)` a
    /// `String` directly and call `decode(_:)` for read or `encode(_:)` to
    /// produce the new JSON value.
    static let storageKey = "strengthWeeklySchedule"

    // MARK: - JSON codec

    /// Returns the map keyed by Calendar.weekday (1…7). Empty when no
    /// schedule has been saved yet OR when the stored value is malformed.
    static func decode(_ json: String) -> [Int: UUID] {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        var out: [Int: UUID] = [:]
        for (k, v) in dict {
            guard let weekday = Int(k), (1...7).contains(weekday),
                  let uuid = UUID(uuidString: v) else { continue }
            out[weekday] = uuid
        }
        return out
    }

    /// Encodes a weekday → routineID map back into the JSON string the
    /// `@AppStorage` property stores. Empty input encodes as `{}`.
    static func encode(_ map: [Int: UUID]) -> String {
        let stringKeyed = Dictionary(uniqueKeysWithValues: map.map {
            (String($0.key), $0.value.uuidString)
        })
        guard let data = try? JSONEncoder().encode(stringKeyed),
              let s = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return s
    }

    // MARK: - Convenience helpers (operate on the in-memory map)

    /// Returns a new map with the given weekday updated. Passing `nil`
    /// clears that day (= Rest).
    static func setting(_ map: [Int: UUID], routineID: UUID?, forWeekday weekday: Int) -> [Int: UUID] {
        var copy = map
        if let id = routineID {
            copy[weekday] = id
        } else {
            copy.removeValue(forKey: weekday)
        }
        return copy
    }

    /// Weekday number 1…7 in the user's current calendar for the given date.
    /// Pass `.now` to read today's weekday.
    static func weekday(for date: Date) -> Int {
        Calendar.current.component(.weekday, from: date)
    }
}
