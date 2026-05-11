import Foundation
import UserNotifications
import Observation

/// Bridges UNUserNotificationCenter callbacks into SwiftUI state.
///
/// FoodJournalApp creates one instance, registers it as the notification
/// center's delegate, and injects it into the environment. RootView watches
/// `pendingMealOpen` and deep-links into the corresponding MealDetailSheet
/// on the Today tab when the user taps a reminder.
@MainActor
@Observable
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {

    /// Set by `didReceive response` when the user taps a meal reminder.
    /// RootView reads this, deep-links, and clears it back to nil.
    var pendingMealOpen: String?

    /// Show the banner even when the app is in the foreground. Default iOS
    /// behavior is to swallow the notification entirely when foregrounded.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// User tapped a notification. If it carries a `mealType`, surface that
    /// to RootView so it can open the right MealDetailSheet on Today.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let meal = response.notification.request.content.userInfo["mealType"] as? String
        Task { @MainActor in
            if let meal { self.pendingMealOpen = meal }
        }
        completionHandler()
    }
}
