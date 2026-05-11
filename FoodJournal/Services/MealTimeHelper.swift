import Foundation

/// Maps wall-clock time to the most likely meal type. Used as a fallback
/// when no explicit meal context is provided (e.g. opening Manual Entry from
/// the Add tab rather than from a specific meal card).
///
/// Also gates the late-night snack confirmation alert. The window and on/off
/// switch are user-configurable via Settings (stored in UserDefaults so no
/// schema change is required).
///
/// v1.8: meal windows themselves are also user-configurable via Settings.
/// Six UserDefaults keys hold breakfast/lunch/dinner start+end hours.
/// Each window may wrap midnight (start > end). Order of precedence when
/// windows overlap: breakfast, then lunch, then dinner. Anything not in a
/// configured window falls through to "snack".
enum MealTimeHelper {

    // MARK: - UserDefaults keys

    enum Keys {
        static let warningEnabled   = "lateNightWarningEnabled"
        static let warningStartHour = "lateNightWarningStartHour"
        static let warningEndHour   = "lateNightWarningEndHour"

        static let breakfastStart   = "mealBreakfastStart"
        static let breakfastEnd     = "mealBreakfastEnd"
        static let lunchStart       = "mealLunchStart"
        static let lunchEnd         = "mealLunchEnd"
        static let dinnerStart      = "mealDinnerStart"
        static let dinnerEnd        = "mealDinnerEnd"
    }

    // Late-night warning defaults: 8pm–6am, enabled.
    static let defaultEnabled   = true
    static let defaultStartHour = 20
    static let defaultEndHour   = 6

    // Meal-window defaults match the v1.7 hardcoded schedule.
    static let defaultBreakfastStart = 6
    static let defaultBreakfastEnd   = 10
    static let defaultLunchStart     = 12
    static let defaultLunchEnd       = 14
    static let defaultDinnerStart    = 17
    static let defaultDinnerEnd      = 20

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
        readHour(Keys.warningStartHour, fallback: defaultStartHour)
    }

    static var warningEndHour: Int {
        readHour(Keys.warningEndHour, fallback: defaultEndHour)
    }

    static var breakfastStart: Int { readHour(Keys.breakfastStart, fallback: defaultBreakfastStart) }
    static var breakfastEnd:   Int { readHour(Keys.breakfastEnd,   fallback: defaultBreakfastEnd) }
    static var lunchStart:     Int { readHour(Keys.lunchStart,     fallback: defaultLunchStart) }
    static var lunchEnd:       Int { readHour(Keys.lunchEnd,       fallback: defaultLunchEnd) }
    static var dinnerStart:    Int { readHour(Keys.dinnerStart,    fallback: defaultDinnerStart) }
    static var dinnerEnd:      Int { readHour(Keys.dinnerEnd,      fallback: defaultDinnerEnd) }

    private static func readHour(_ key: String, fallback: Int) -> Int {
        if UserDefaults.standard.object(forKey: key) == nil {
            return fallback
        }
        return UserDefaults.standard.integer(forKey: key)
    }

    // MARK: - Public API (call sites unchanged)

    /// Best-guess meal type for the given Date. Reads the user-configured
    /// breakfast/lunch/dinner windows from UserDefaults; falls back to snack.
    /// Precedence on overlap: breakfast > lunch > dinner > snack.
    static func mealType(at date: Date = .now) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        if hourInWindow(hour, start: breakfastStart, end: breakfastEnd) { return "breakfast" }
        if hourInWindow(hour, start: lunchStart,     end: lunchEnd)     { return "lunch" }
        if hourInWindow(hour, start: dinnerStart,    end: dinnerEnd)    { return "dinner" }
        return "snack"
    }

    /// True when the current hour is inside the user-configured late-night window.
    static func isLateNight(at date: Date = .now) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hourInWindow(hour, start: warningStartHour, end: warningEndHour)
    }

    /// Returns true ONLY when: warning is enabled, meal is "snack",
    /// AND the current time is in the late-night window.
    static func shouldWarnAboutLateSnack(meal: String, at date: Date = .now) -> Bool {
        guard warningEnabled else { return false }
        return meal == "snack" && isLateNight(at: date)
    }

    // MARK: - Helpers

    /// Returns true when `hour` falls inside a [start, end) window.
    /// - start == end → zero-width window, never matches.
    /// - start < end → ordinary same-day window.
    /// - start > end → wraps midnight (e.g. 20→6 means hour ≥ 20 OR hour < 6).
    private static func hourInWindow(_ hour: Int, start: Int, end: Int) -> Bool {
        if start == end { return false }
        if start < end {
            return hour >= start && hour < end
        }
        return hour >= start || hour < end
    }
}
