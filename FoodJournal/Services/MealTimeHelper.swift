import Foundation

/// Maps wall-clock time to the most likely meal type. Used as a fallback
/// when no explicit meal context is provided (e.g. opening Manual Entry from
/// the Add tab rather than from a specific meal card).
///
/// Also gates the late-night snack confirmation alert. The window and on/off
/// switch are user-configurable via Settings (stored in UserDefaults so no
/// schema change is required).
enum MealTimeHelper {

    // MARK: - UserDefaults keys

    enum Keys {
        static let warningEnabled   = "lateNightWarningEnabled"
        static let warningStartHour = "lateNightWarningStartHour"
        static let warningEndHour   = "lateNightWarningEndHour"
    }

    // Defaults are 8pm–6am, enabled. Used when keys haven't been set yet.
    static let defaultEnabled   = true
    static let defaultStartHour = 20
    static let defaultEndHour   = 6

    // MARK: - Computed config (reads UserDefaults, falls back to defaults)

    /// Reads enabled flag. UserDefaults.bool returns false for missing keys,
    /// so we explicitly check for key presence and use the true default.
    static var warningEnabled: Bool {
        if UserDefaults.standard.object(forKey: Keys.warningEnabled) == nil {
            return defaultEnabled
        }
        return UserDefaults.standard.bool(forKey: Keys.warningEnabled)
    }

    static var warningStartHour: Int {
        if UserDefaults.standard.object(forKey: Keys.warningStartHour) == nil {
            return defaultStartHour
        }
        return UserDefaults.standard.integer(forKey: Keys.warningStartHour)
    }

    static var warningEndHour: Int {
        if UserDefaults.standard.object(forKey: Keys.warningEndHour) == nil {
            return defaultEndHour
        }
        return UserDefaults.standard.integer(forKey: Keys.warningEndHour)
    }

    // MARK: - Public API (call sites unchanged)

    /// Best-guess meal type for the given Date. Time-of-day → meal mapping is fixed.
    static func mealType(at date: Date = .now) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 6..<10:   return "breakfast"
        case 10..<12:  return "snack"
        case 12..<14:  return "lunch"
        case 14..<17:  return "snack"
        case 17..<20:  return "dinner"
        default:       return "snack"
        }
    }

    /// True when the current hour is inside the user-configured late-night window.
    /// Handles wraparound: a 20:00 → 06:00 window means hour ≥ 20 OR hour < 6.
    /// A non-wrapping window like 22:00 → 23:00 means 22 ≤ hour < 23.
    static func isLateNight(at date: Date = .now) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        let start = warningStartHour
        let end = warningEndHour
        if start == end {
            // Degenerate: zero-width window. Treat as never late.
            return false
        }
        if start < end {
            return hour >= start && hour < end
        } else {
            // Wraparound case (the default 20→6 falls here).
            return hour >= start || hour < end
        }
    }

    /// Returns true ONLY when: warning is enabled, meal is "snack",
    /// AND the current time is in the late-night window.
    static func shouldWarnAboutLateSnack(meal: String, at date: Date = .now) -> Bool {
        guard warningEnabled else { return false }
        return meal == "snack" && isLateNight(at: date)
    }
}
