import Foundation
import Observation
import ServiceManagement

/// Persisted preferences. Backs the Settings page. Toggles default to honest
/// values; the ones that are also enforced by the engine (Protect System Files,
/// Skip Open Files) stay on. Exclusions feed the SafePaths chokepoint.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    // Exclusions (Ignored Locations)
    var excludedPaths: [String] { didSet { d.set(excludedPaths, forKey: "cairn.excludedPaths"); SafePaths.userExcluded = excludedPaths } }

    // General
    var openAtLogin: Bool {
        didSet {
            d.set(openAtLogin, forKey: "cairn.openAtLogin")
            // Real login item via SMAppService (macOS 13+). Failure (e.g. running
            // from a DMG) just leaves the toggle as a preference.
            do {
                if openAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch { /* not fatal — surface nothing, macOS shows its own UI in Settings */ }
        }
    }
    var showMenuBarItem: Bool { didSet { d.set(showMenuBarItem, forKey: "cairn.showMenuBarItem") } }

    // Smart Scan
    var autoScanWeekly: Bool { didSet { d.set(autoScanWeekly, forKey: "cairn.autoScanWeekly") } }
    var askBeforeDeleting: Bool { didSet { d.set(askBeforeDeleting, forKey: "cairn.askBeforeDeleting") } }
    var createRestoreSnapshot: Bool { didSet { d.set(createRestoreSnapshot, forKey: "cairn.createRestoreSnapshot") } }
    var ignoreExternalDrives: Bool { didSet { d.set(ignoreExternalDrives, forKey: "cairn.ignoreExternalDrives") } }

    // Safety
    var protectSystemFiles: Bool { didSet { d.set(protectSystemFiles, forKey: "cairn.protectSystemFiles") } }
    var skipOpenFiles: Bool { didSet { d.set(skipOpenFiles, forKey: "cairn.skipOpenFiles") } }
    var secureDeletion: Bool { didSet { d.set(secureDeletion, forKey: "cairn.secureDeletion") } }

    // Notifications
    var scanNotifications: Bool {
        didSet {
            d.set(scanNotifications, forKey: "cairn.scanNotifications")
            if scanNotifications { Notify.requestAuth() }   // ask up front, not mid-scan
        }
    }
    var smartRecommendations: Bool { didSet { d.set(smartRecommendations, forKey: "cairn.smartRecommendations") } }

    // Developer Tools
    /// Smart Triggers — clean a tool's regenerable caches when you quit it.
    /// Pro-gated at the point of use, and only ever touches SAFE + regenerable
    /// items that go to the Trash.
    var cleanOnQuitDevApp: Bool { didSet { d.set(cleanOnQuitDevApp, forKey: "cairn.cleanOnQuitDevApp") } }
    var includeDeveloperCaches: Bool { didSet { d.set(includeDeveloperCaches, forKey: "cairn.includeDeveloperCaches") } }
    var includeSimulators: Bool { didSet { d.set(includeSimulators, forKey: "cairn.includeSimulators") } }

    // Restore Bin
    var restoreBinKeepDays: Int { didSet { d.set(restoreBinKeepDays, forKey: "cairn.restoreBinKeepDays") } }

    private init() {
        let ud = UserDefaults.standard
        func b(_ key: String, _ def: Bool) -> Bool { ud.object(forKey: key) == nil ? def : ud.bool(forKey: key) }
        excludedPaths = ud.stringArray(forKey: "cairn.excludedPaths") ?? []
        openAtLogin = b("cairn.openAtLogin", false)
        showMenuBarItem = b("cairn.showMenuBarItem", true)
        autoScanWeekly = b("cairn.autoScanWeekly", true)
        askBeforeDeleting = b("cairn.askBeforeDeleting", true)
        createRestoreSnapshot = b("cairn.createRestoreSnapshot", true)
        ignoreExternalDrives = b("cairn.ignoreExternalDrives", true)
        cleanOnQuitDevApp = b("cairn.cleanOnQuitDevApp", false)   // opt-in: it deletes without asking
        protectSystemFiles = b("cairn.protectSystemFiles", true)
        skipOpenFiles = b("cairn.skipOpenFiles", true)
        secureDeletion = b("cairn.secureDeletion", false)
        scanNotifications = b("cairn.scanNotifications", true)
        smartRecommendations = b("cairn.smartRecommendations", true)
        includeDeveloperCaches = b("cairn.includeDeveloperCaches", true)
        includeSimulators = b("cairn.includeSimulators", true)
        restoreBinKeepDays = ud.object(forKey: "cairn.restoreBinKeepDays") == nil ? 30 : ud.integer(forKey: "cairn.restoreBinKeepDays")
        SafePaths.userExcluded = excludedPaths
    }

    func add(_ url: URL) {
        let p = url.standardizedFileURL.path
        if !excludedPaths.contains(p) { excludedPaths.append(p) }
    }
    func remove(_ path: String) { excludedPaths.removeAll { $0 == path } }
    func isExcluded(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        return excludedPaths.contains { p == $0 || p.hasPrefix($0 + "/") }
    }
}
