import Foundation
import UserNotifications

/// macOS notifications: timed snoozes that ended, and watched pull requests that moved. Asks for permission
/// on the first notification, not at launch. Needs an app bundle: the bare debug binary (snapshots) must not
/// create one. It is the center's delegate too, so a click on a moved pull request opens it, and a banner
/// shows while the app is frontmost (a menu bar app usually is not, but the Desk can be).
final class SnoozeNotifier: NSObject, SnoozeNotifying, UNUserNotificationCenterDelegate, @unchecked Sendable {
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func snoozeEnded(count: Int) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Snooze ended", bundle: .app)
        content.body = String.localizedStringWithFormat(String(localized: "%lld pull requests are back in their sections", bundle: .app), count)
        deliver(content, identifier: "snooze-ended-\(Date().timeIntervalSince1970)")
    }

    func pullRequestMoved(_ mark: WatchMark, _ movement: WatchMovement) {
        let content = UNMutableNotificationContent()
        content.title = movement.title
        content.body = "#\(mark.number) \(mark.title)"
        content.subtitle = mark.repo
        content.userInfo = ["url": mark.url.absoluteString, "id": mark.id]
        deliver(content, identifier: "watch-\(mark.id)")
    }

    private func deliver(_ content: UNMutableNotificationContent, identifier: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            content.sound = .default
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let id = info["id"] as? String, let raw = info["url"] as? String, let url = URL(string: raw) {
            Task { @MainActor in PullRequestOpener.open(watched: id, url: url) }
        }
        completionHandler()
    }
}
