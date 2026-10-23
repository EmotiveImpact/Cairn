import Foundation
import AppKit

/// Running-app / daemon guard (SPEC §5.3). Cleaning a cache owned by a live
/// process (Xcode mid-index, Docker daemon, an editor, a dev server) can corrupt
/// state — so app-owned items are blocked until the owner quits.
enum RunningApps {
    // `runningApplications` is a full process enumeration. It's read from SwiftUI
    // row bodies (the "QUIT APP" badge), so with a few hundred visible rows it was
    // running hundreds of process sweeps per redraw — a major source of UI lag.
    // Cached for a short TTL; correctness is preserved because the clean path
    // always re-checks live state immediately before acting.
    private static var cachedIDs: Set<String> = []
    private static var cachedAt: TimeInterval = 0
    private static let ttl: TimeInterval = 2.0

    /// Bundle ids of currently-running apps (cached ~2s for view reads).
    static func runningBundleIDs() -> Set<String> {
        let now = Date.timeIntervalSinceReferenceDate
        if now - cachedAt < ttl, !cachedIDs.isEmpty { return cachedIDs }
        cachedIDs = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        cachedAt = now
        return cachedIDs
    }

    /// Uncached, authoritative read — use before quitting/cleaning.
    static func runningBundleIDsNow() -> Set<String> {
        cachedIDs = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        cachedAt = Date.timeIntervalSinceReferenceDate
        return cachedIDs
    }

    /// Which of the given bundle ids are currently running (cached; for display).
    static func running(amongst ids: [String]) -> [String] {
        guard !ids.isEmpty else { return [] }
        let live = runningBundleIDs()
        return ids.filter { live.contains($0) }
    }

    /// Which of the given bundle ids are running RIGHT NOW (for the clean path).
    static func runningNow(amongst ids: [String]) -> [String] {
        guard !ids.isEmpty else { return [] }
        let live = runningBundleIDsNow()
        return ids.filter { live.contains($0) }
    }

    /// Localized display names for running bundle ids (for the quit-first prompt).
    static func displayNames(for ids: [String]) -> [String] {
        let apps = NSWorkspace.shared.runningApplications
        return ids.compactMap { id in
            apps.first { $0.bundleIdentifier == id }?.localizedName ?? shortName(id)
        }
    }

    private static func shortName(_ bundleID: String) -> String {
        bundleID.components(separatedBy: ".").last ?? bundleID
    }

    /// Is the Docker daemon reachable? Prune requires it UP; otherwise advice-only.
    /// Docker Desktop, OrbStack or Colima has a live engine the `docker` CLI
    /// can reach. OrbStack and Colima only create their sockets while running.
    static func isDockerRunning() -> Bool {
        let ids = runningBundleIDs()
        if ids.contains("com.docker.docker") || ids.contains("dev.kdrag0n.MacVirt") { return true }
        return [".docker/run/docker.sock", ".orbstack/run/docker.sock", ".colima/default/docker.sock"].contains {
            FileManager.default.fileExists(atPath: FileScan.home.appendingPathComponent($0).path)
        }
    }

    /// Request quit for a set of apps (used by the quit-first prompt).
    @MainActor
    static func requestQuit(_ ids: [String]) {
        for app in NSWorkspace.shared.runningApplications where ids.contains(app.bundleIdentifier ?? "") {
            app.terminate()
        }
    }
}
