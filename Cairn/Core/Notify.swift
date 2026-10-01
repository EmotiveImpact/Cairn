import Foundation
import UserNotifications

/// Local user notifications — used for "scan complete" when the user has the
/// Scan Notifications setting on. Quiet failure everywhere: notifications are
/// nice-to-have, never load-bearing.
enum Notify {
    /// UserNotifications raises an Objective-C exception when a SwiftPM
    /// executable is launched without its containing .app bundle. Check the
    /// process identity before asking for the notification center; Swift error
    /// handling cannot catch that exception.
    static var isAvailable: Bool {
        let bundle = Bundle.main
        return bundle.bundleURL.pathExtension.lowercased() == "app"
            && bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL"
            && !(bundle.bundleIdentifier ?? "").isEmpty
    }

    static var center: UNUserNotificationCenter? {
        guard isAvailable else { return nil }
        return UNUserNotificationCenter.current()
    }

    static func requestAuth() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// General-purpose local status notice. Notifications never authorize actions.
    static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center?.add(request)
    }

    /// Candidate estimates are not guaranteed released capacity.
    static func scanComplete(totalBytes: Int64, items: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Scan complete"
        content.body = "\(Fmt.size(totalBytes)) in candidate file-size estimates across \(items) items. Review before removal."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center?.add(request)
    }
}
