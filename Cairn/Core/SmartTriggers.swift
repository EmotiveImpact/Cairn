import Foundation
import AppKit

/// Smart Triggers — clean a dev tool's regenerable caches the moment you quit it.
///
/// This is the one feature that makes a cleaner feel like infrastructure rather
/// than a chore: DerivedData never gets the chance to reach 50 GB, because it's
/// swept every time Xcode closes.
///
/// Safety posture, since nobody is watching when this fires:
///  - Opt-in. Off by default, and Pro-gated at the point of use.
///  - Only SAFE + regenerable items that go to the Trash. Never tool-mediated
///    cleans (which shell out) and never permanent removal — see
///    `ScanStore.autoClean`.
///  - Only the category belonging to the app that quit. Quitting Xcode never
///    touches your npm cache.
///  - Debounced per category, so quitting and reopening Xcode repeatedly can't
///    spawn a pile of concurrent scans.
///  - Silent when it finds nothing; notifies when it reclaims something, so the
///    user always learns that it acted.
@MainActor
final class SmartTriggers {
    static let shared = SmartTriggers()

    /// Bundle ID → (display name, scanner category to sweep).
    private static let watched: [String: (name: String, category: String)] = [
        "com.apple.dt.Xcode":                  ("Xcode", "xcode"),
        "com.microsoft.VSCode":                ("VS Code", "ide-caches"),
        "com.todesktop.230313mzl4w4u92":       ("Cursor", "ide-caches"),
        "com.exafunction.windsurf":            ("Windsurf", "ide-caches"),
        "com.google.android.studio":           ("Android Studio", "android"),
        "com.unity3d.unityhub":                ("Unity Hub", "dev-projects"),
    ]
    /// JetBrains ships a family of bundle IDs (IntelliJ, GoLand, PyCharm…).
    private static let jetBrainsPrefix = "com.jetbrains."

    /// Don't re-sweep the same category more often than this.
    private static let debounce: TimeInterval = 10 * 60

    private var token: NSObjectProtocol?
    private var lastRun: [String: Date] = [:]
    private weak var store: ScanStore?
    private var isProUnlocked: () -> Bool = { false }

    private init() {}

    /// Begins watching. Safe to call more than once.
    func start(store: ScanStore, isProUnlocked: @escaping () -> Bool) {
        self.store = store
        self.isProUnlocked = isProUnlocked
        guard token == nil else { return }
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            MainActor.assumeIsolated { SmartTriggers.shared.handleQuit(bundleID: bundleID) }
        }
    }

    func stop() {
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        token = nil
    }

    private func target(for bundleID: String) -> (name: String, category: String)? {
        if let hit = Self.watched[bundleID] { return hit }
        if bundleID.hasPrefix(Self.jetBrainsPrefix) { return ("JetBrains IDE", "ide-caches") }
        return nil
    }

    private func handleQuit(bundleID: String) {
        guard AppSettings.shared.cleanOnQuitDevApp, isProUnlocked() else { return }
        guard let target = target(for: bundleID), let store else { return }

        if let last = lastRun[target.category], Date().timeIntervalSince(last) < Self.debounce { return }
        lastRun[target.category] = Date()

        Task {
            let bytes = await store.autoClean(categoryID: target.category)
            guard bytes > 0 else { return }   // silent when there was nothing to do
            Notify.send(title: "Cleaned up after \(target.name)",
                        body: "Reclaimed \(Fmt.size(bytes)). Everything went to the Trash.")
        }
    }
}
