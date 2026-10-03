import Foundation
@preconcurrency import UserNotifications

/// macOS notifications. Only works inside an .app bundle (not a bare `swift run` binary).
enum Notifier {
    private static var available: Bool { Bundle.main.bundlePath.hasSuffix(".app") }

    static func notify(title: String, body: String) {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
