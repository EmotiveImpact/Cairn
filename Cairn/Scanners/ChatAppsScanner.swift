import Foundation
import AppKit

/// WhatsApp and Telegram keep a local copy of every photo and video you have
/// been sent, and on a Mac nothing trims it. Their folders also hold the chats
/// themselves and the sign-in, so Cairn never clears inside them: it measures
/// each app and points to the app's own storage screen, where you choose which
/// chats to trim. Slack, Discord, Teams and Zoom caches are found by the
/// dedicated cache scanners; the Chat apps page shows them alongside.
struct ChatAppsScanner: CairnScanner {
    let info = CategoryInfo(
        id: "chat-apps",
        title: "Chat apps",
        subtitle: "WhatsApp and Telegram photos and videos",
        systemImage: "bubble.left.and.text.bubble.right",
        group: .general,
        requiresFDA: false
    )

    /// Keys in ScanItem.detail, read by the Chat apps page.
    enum Key {
        static let app = "app"            // display name
        static let bundleIDs = "bundleIDs" // comma separated, to open the app
        static let howTo = "howTo"        // where the app's own storage screen is
    }

    struct ChatApp {
        let name: String
        let bundleIDs: [String]
        /// Containers belong to the app; macOS asks before another app reads
        /// them unless Cairn has Full Disk Access.
        let containers: [String]
        let plain: [String]
        let howTo: String
        let line: String
    }

    static let apps: [ChatApp] = [
        ChatApp(name: "WhatsApp", bundleIDs: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"],
                containers: ["Library/Group Containers/group.net.whatsapp.WhatsApp.shared",
                             "Library/Containers/net.whatsapp.WhatsApp"],
                plain: ["Library/Application Support/WhatsApp"],
                howTo: "In WhatsApp, Settings › Storage and data › Manage storage shows your biggest chats and lets you clear their photos and videos.",
                line: "Every photo and video you've been sent"),
        ChatApp(name: "Telegram", bundleIDs: ["ru.keepcoder.Telegram", "com.tdesktop.Telegram"],
                containers: ["Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram",
                             "Library/Containers/ru.keepcoder.Telegram"],
                plain: ["Library/Application Support/Telegram Desktop"],
                howTo: "In Telegram, Settings › Data and Storage › Storage Usage clears the media cache and sets a size limit, so it stops growing.",
                line: "Media cache, kept with no limit unless you set one"),
    ]

    func scan(_ ctx: ScanContext) async {
        let home = FileScan.home
        for app in Self.apps {
            if ctx.isCancelled() { return }
            var parts = app.plain.map { home.appendingPathComponent($0) }
            var unmeasured = false
            let installed = Self.installedApp(app) != nil
            for rel in app.containers {
                let url = home.appendingPathComponent(rel)
                // Without Full Disk Access, reading another app's container
                // makes macOS ask the person mid-scan. Skip it and say so,
                // but only for an app that is actually on this Mac.
                if ctx.fdaGranted { parts.append(url) } else if installed { unmeasured = true }
            }
            let found = parts.filter(FileScan.exists)
            guard !found.isEmpty || unmeasured else { continue }
            ctx.progress(app.name)
            var total: Int64 = 0
            var files = 0
            var latest = Date.distantPast
            var denied = false
            var largest: (url: URL, bytes: Int64)?
            for part in found {
                if ctx.isCancelled() { return }
                let stats = FileScan.measure(part, maxFiles: 80_000, maxDuration: 3)
                total += stats.allocatedSize
                files += stats.fileCount
                latest = max(latest, stats.latestModified)
                denied = denied || stats.permissionDenied
                if stats.allocatedSize > (largest?.bytes ?? -1) { largest = (url: part, bytes: stats.allocatedSize) }
            }
            let shown = largest?.url ?? home.appendingPathComponent(app.containers[0])
            // Nothing measured and nothing worth a line: stay quiet.
            if total < ctx.minSizeBytes && !unmeasured { continue }
            var item = ScanItem(
                url: shown, allocatedSize: total, itemCount: files, latestModified: latest,
                categoryID: info.id, severity: .review, isRegenerable: false, cleanMethod: .adviceOnly,
                note: "\(app.name) keeps a copy of everything you've been sent. Cairn won't clear inside its folder, because that can sign you out or lose chats. " + app.howTo,
                permissionDenied: denied || unmeasured, volumeURL: FileScan.volumeURL(of: shown), selected: false)
            item.detail = [Key.app: app.name, Key.bundleIDs: app.bundleIDs.joined(separator: ","), Key.howTo: app.howTo]
            ctx.emit(item)
        }
    }

    /// The app itself, when it is installed. Looked up by bundle ID, which
    /// reads nothing inside the app's own folders.
    static func installedApp(_ app: ChatApp) -> URL? {
        app.bundleIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    /// Which chat app a finding from any scanner belongs to, by its path.
    static func chatApp(for item: ScanItem) -> String? {
        if let name = item.detail[Key.app] { return name }
        let path = item.resolvedURL.path.lowercased()
        let known: [(String, [String])] = [
            ("Slack", ["/slack/", "com.tinyspeck.slackmacgap"]),
            ("Discord", ["/discord/", "com.hnc.discord"]),
            ("Microsoft Teams", ["microsoft/teams", "com.microsoft.teams"]),
            ("Zoom", ["zoom.us"]),
            ("WhatsApp", ["whatsapp"]),
            ("Telegram", ["telegram"]),
            ("Signal", ["/signal/"]),
            ("Messenger", ["com.facebook.archon"]),
        ]
        for (name, markers) in known where markers.contains(where: { path.contains($0) || (path + "/").hasSuffix($0) }) {
            return name
        }
        return nil
    }
}
