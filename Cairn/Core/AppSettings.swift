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
    var showMenuBarItem: Bool { didSet {
        guard oldValue != showMenuBarItem else { return }
        d.set(showMenuBarItem, forKey: "cairn.showMenuBarItem")
        CairnMenuBar.shared.setVisible(showMenuBarItem)
    } }

    var showSidebarFocus: Bool { didSet { d.set(showSidebarFocus, forKey: "cairn.showSidebarFocus") } }
    /// Read-only capacity monitoring. This does not arm any cleanup rule.
    var reserveEnabled: Bool { didSet { d.set(reserveEnabled, forKey: "cairn.reserveEnabled") } }
    var reservePaused: Bool { didSet { d.set(reservePaused, forKey: "cairn.reservePaused") } }
    var reservePauseUntil: Date? { didSet {
        if let reservePauseUntil { d.set(reservePauseUntil, forKey: "cairn.reservePauseUntil") }
        else { d.removeObject(forKey: "cairn.reservePauseUntil") }
    } }
    var locationMonitoringEnabled: Bool { didSet { d.set(locationMonitoringEnabled, forKey: "cairn.locationMonitoringEnabled.v1") } }
    var reserveQuietHours: Bool { didSet { d.set(reserveQuietHours, forKey: "cairn.reserveQuietHours") } }
    var reserveGB: Int { didSet { d.set(reserveGB, forKey: "cairn.reserveGB") } }
    var goalGB: Int { didSet { d.set(goalGB, forKey: "cairn.goalGB") } }

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
    /// Legacy preference retained for compatibility; no executor reads it.
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
        showSidebarFocus = b("cairn.showSidebarFocus", false)
        reserveEnabled = b("cairn.reserveEnabled", false)
        locationMonitoringEnabled = b("cairn.locationMonitoringEnabled.v1", false)
        reserveQuietHours = b("cairn.reserveQuietHours", false)
        reservePaused = b("cairn.reservePaused", false)
        reservePauseUntil = ud.object(forKey: "cairn.reservePauseUntil") as? Date
        reserveGB = max(5, min(500, ud.object(forKey: "cairn.reserveGB") == nil ? 30 : ud.integer(forKey: "cairn.reserveGB")))
        goalGB = max(5, min(1_000, ud.object(forKey: "cairn.goalGB") == nil ? 30 : ud.integer(forKey: "cairn.goalGB")))
        autoScanWeekly = b("cairn.autoScanWeekly", true)
        askBeforeDeleting = b("cairn.askBeforeDeleting", true)
        createRestoreSnapshot = b("cairn.createRestoreSnapshot", false)
        ignoreExternalDrives = b("cairn.ignoreExternalDrives", true)
        cleanOnQuitDevApp = b("cairn.cleanOnQuitDevApp", false)   // inert legacy setting
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
