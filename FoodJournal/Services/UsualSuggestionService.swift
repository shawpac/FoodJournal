import Foundation
import SwiftData

/// Identifies "your usual" food for a given meal slot by frequency over a
/// rolling 14-day window. Used by TodayView to surface a "Your usual breakfast?"
/// banner during the matching meal-time window.
///
/// v1 scope:
/// - Single-food suggestions only (no combo detection).
/// - Group by lowercased name+brand (same dedup as LibraryFood).
/// - Threshold: ≥ 3 occurrences in the past 14 days for that meal slot.
/// - Snacks are intentionally excluded — too unpredictable to suggest.
enum UsualSuggestionService {

    /// How many days back to look when scoring foods.
    static let lookbackDays = 14
    /// Minimum occurrences in the window for a food to qualify as "usual."
    static let minOccurrences = 3
    /// Hours of grace past a meal window's end during which we still surface
    /// that meal's suggestion (handles "late breakfast" cases).
    static let graceHoursAfterMealEnd = 1

    struct Suggestion {
        let meal: String       // "breakfast" | "lunch" | "dinner"
        let template: FoodEntry
        let occurrences: Int
    }

    /// Returns the meal slot whose active window currently includes `now`
    /// (extended by `graceHoursAfterMealEnd`), or nil if no qualifying window
    /// is active. Precedence on overlap: breakfast → lunch → dinner.
    static func activeMeal(at now: Date = .now) -> String? {
        let hour = Calendar.current.component(.hour, from: now)
        if inExtended(hour, start: MealTimeHelper.breakfastStart, end: MealTimeHelper.breakfastEnd) {
            return "breakfast"
        }
        if inExtended(hour, start: MealTimeHelper.lunchStart, end: MealTimeHelper.lunchEnd) {
            return "lunch"
        }
        if inExtended(hour, start: MealTimeHelper.dinnerStart, end: MealTimeHelper.dinnerEnd) {
            return "dinner"
        }
        return nil
    }

    /// True when `hour` falls inside [start, end + grace), with wrap-around
    /// support. Modular-arithmetic form keeps the wrap case simple: shift the
    /// hour into the window's local frame and compare to the extended span.
    private static func inExtended(_ hour: Int, start: Int, end: Int) -> Bool {
        if start == end { return false }
        let span = ((end - start) + 24) % 24
        let extendedSpan = span + graceHoursAfterMealEnd
        let offset = ((hour - start) + 24) % 24
        return offset < extendedSpan
    }

    /// Looks up the most-frequently-logged food in the given meal slot over
    /// the lookback window. Returns nil if no food clears `minOccurrences`.
    /// Template is the most-recent matching entry — its values reflect the
    /// freshest copy of that food's nutritional data the user has logged.
    static func suggest(for meal: String, in context: ModelContext, now: Date = .now) -> Suggestion? {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -lookbackDays, to: now) else { return nil }

        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate<FoodEntry> { entry in
                entry.mealType == meal &&
                entry.loggedAt >= cutoff &&
                entry.pendingDeleteAt == nil
            }
        )
        guard let entries = try? context.fetch(descriptor), !entries.isEmpty else { return nil }

        var groups: [String: [FoodEntry]] = [:]
        for entry in entries {
            let key = LibraryFood.makeDedupKey(name: entry.name, brand: entry.brand)
            groups[key, default: []].append(entry)
        }

        guard let winner = groups.max(by: { $0.value.count < $1.value.count }),
              winner.value.count >= minOccurrences,
              let template = winner.value.max(by: { $0.loggedAt < $1.loggedAt })
        else { return nil }

        return Suggestion(meal: meal, template: template, occurrences: winner.value.count)
    }
}
