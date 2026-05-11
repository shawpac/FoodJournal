import Foundation
import UserNotifications

/// Pure scheduling logic for daily meal reminders. The Settings UI calls
/// these methods directly. Each meal has a stable identifier so reschedules
/// and cancels are surgical (no risk of orphaned duplicates).
///
/// Repeats daily via UNCalendarNotificationTrigger so we don't need to
/// reschedule on every app launch.
enum NotificationService {

    /// Identifier convention: "reminder.<meal>" — same format used to remove
    /// pending requests when the user toggles a reminder off or changes the time.
    static func identifier(for meal: String) -> String {
        "reminder.\(meal)"
    }

    /// Asks UNUserNotificationCenter for authorization. Returns granted/denied.
    /// Caller should only invoke this when the user is opting in (toggling a
    /// reminder ON for the first time), to avoid surprising the user with an
    /// iOS prompt on app launch.
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Schedules (or replaces) a daily-repeating reminder for the given meal.
    /// Adding a request with an existing identifier replaces the prior one
    /// per Apple's docs — no explicit cancel needed before reschedule.
    static func scheduleMealReminder(meal: String, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Time for \(meal)"
        content.body = "Log when you're done."
        content.sound = .default
        content.userInfo = ["mealType": meal]

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        let request = UNNotificationRequest(
            identifier: identifier(for: meal),
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelMealReminder(meal: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier(for: meal)])
    }
}
