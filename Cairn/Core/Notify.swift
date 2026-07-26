import Foundation
import UserNotifications

/// Local user notifications — used for "scan complete" when the user has the
/// Scan Notifications setting on. Quiet failure everywhere: notifications are
/// nice-to-have, never load-bearing.
enum Notify {
    static func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// General-purpose local notice. Used by Smart Triggers, which acts without
    /// the user present — so it must always say what it did.
    static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// "Scan complete — X reclaimable found."
    static func scanComplete(totalBytes: Int64, items: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Scan complete"
        content.body = "\(Fmt.size(totalBytes)) reclaimable across \(items) items."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
