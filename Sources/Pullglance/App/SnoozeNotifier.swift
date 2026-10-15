import Foundation
import UserNotifications

/// macOS notifications for timed snoozes that ended. Asks for permission on the first notification, not at
/// launch. Needs an app bundle: the bare debug binary (snapshots) must not create one.
final class SnoozeNotifier: SnoozeNotifying {
    func snoozeEnded(count: Int) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Snooze ended", bundle: .app)
            content.body = count == 1
                ? String(localized: "A pull request is back in its section", bundle: .app)
                : String(format: String(localized: "%lld pull requests are back in their sections", bundle: .app), count)
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "snooze-ended-\(Date().timeIntervalSince1970)", content: content, trigger: nil))
        }
    }
}
