import Foundation

/// Maps wall-clock time to the most likely meal type. Used as a fallback
/// when no explicit meal context is provided (e.g. opening Manual Entry from
/// the Add tab rather than from a specific meal card).
///
/// Schedule:
///   6:00–9:59   → breakfast
///  10:00–11:59  → snack
///  12:00–13:59  → lunch
///  14:00–16:59  → snack
///  17:00–19:59  → dinner
///  20:00–22:59  → snack (late)
///  23:00–5:59   → snack (late)
enum MealTimeHelper {

    /// Best-guess meal type for the given Date.
    static func mealType(at date: Date = .now) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 6..<10:   return "breakfast"
        case 10..<12:  return "snack"
        case 12..<14:  return "lunch"
        case 14..<17:  return "snack"
        case 17..<20:  return "dinner"
        default:       return "snack"   // 20:00–05:59
        }
    }

    /// True between 8pm and 6am — when we want to nag the user about
    /// late-night snacking.
    static func isLateNight(at date: Date = .now) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 20 || hour < 6
    }

    /// Returns true ONLY when both: the meal being logged is "snack"
    /// AND it's currently late hours. This is the trigger for the
    /// confirmation alert at save time.
    static func shouldWarnAboutLateSnack(meal: String, at date: Date = .now) -> Bool {
        return meal == "snack" && isLateNight(at: date)
    }
}
