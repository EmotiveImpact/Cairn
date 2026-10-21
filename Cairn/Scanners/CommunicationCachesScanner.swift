import Foundation

/// Communication & desktop-app caches NOT covered by the generic `~/Library/Caches`
/// scanner — these apps stash their throwaway caches under `Application Support`
/// (and a couple of log/updater dirs) instead of the canonical caches root.
///
/// Only narrowly identified transient caches are selectable. Service Worker,
/// offline media, logs, updater and unknown app subfolders are advice only;
/// their names do not prove that all contents are disposable. All targets live in plain user dirs
/// (`~/Library/...`) → no Full Disk Access needed.
struct CommunicationCachesScanner: CairnScanner {
    let info = CategoryInfo(
        id: "comm-caches",
        title: "Communication & App Caches",
        subtitle: "Zoom, Teams, Spotify, Figma, Dropbox",
        systemImage: "bubble.left.and.bubble.right.fill",
        group: .general,
        requiresFDA: false
    )

    /// Cap files counted when sizing big cache trees (so one pathological cache
    /// can't dominate the scan; when hit the size becomes a lower bound).
    private static let maxCacheFiles = 50_000

    // MARK: - Owning-app bundle ids (must quit before a cache is cleaned)

    private static let zoomBundleIDs = ["us.zoom.xos"]
    private static let teamsBundleIDs = ["com.microsoft.teams2", "com.microsoft.teams"]
    private static let spotifyBundleIDs = ["com.spotify.client"]
    private static let figmaBundleIDs = ["com.figma.Desktop"]

    // MARK: - Scan

    func scan(_ ctx: ScanContext) async {
        let home = FileScan.home

        // A fixed cache target: (home-relative path, app display name, owning bundle ids).
        struct Target { let rel: String; let app: String; let quit: [String] }

        var targets: [Target] = [
            // Zoom — auto-updater download cache + logs (never the app's account/data).
            .init(rel: "Library/Application Support/zoom.us/AutoUpdater", app: "Zoom", quit: Self.zoomBundleIDs),
            .init(rel: "Library/Logs/zoom.us", app: "Zoom", quit: Self.zoomBundleIDs),

            // Microsoft Teams — Electron/Chromium cache subdirs only.
            .init(rel: "Library/Application Support/Microsoft/Teams/Cache", app: "Microsoft Teams", quit: Self.teamsBundleIDs),
            .init(rel: "Library/Application Support/Microsoft/Teams/Code Cache", app: "Microsoft Teams", quit: Self.teamsBundleIDs),
            .init(rel: "Library/Application Support/Microsoft/Teams/GPUCache", app: "Microsoft Teams", quit: Self.teamsBundleIDs),
            .init(rel: "Library/Application Support/Microsoft/Teams/Service Worker/CacheStorage", app: "Microsoft Teams", quit: Self.teamsBundleIDs),

            // Spotify — persistent media cache (recreated as you stream).
            .init(rel: "Library/Application Support/Spotify/PersistentCache", app: "Spotify", quit: Self.spotifyBundleIDs),

            // Figma — Electron/Chromium cache subdirs only.
            .init(rel: "Library/Application Support/Figma/Cache", app: "Figma", quit: Self.figmaBundleIDs),
            .init(rel: "Library/Application Support/Figma/Code Cache", app: "Figma", quit: Self.figmaBundleIDs),
            .init(rel: "Library/Application Support/Figma/GPUCache", app: "Figma", quit: Self.figmaBundleIDs),
        ]

        // Microsoft Teams group container — only a Cache subpath if it exists
        // (makeItem skips missing paths, so listing the candidate is safe).
        targets.append(.init(
            rel: "Library/Group Containers/UBF8T346G9.com.microsoft.teams/Library/Caches",
            app: "Microsoft Teams", quit: Self.teamsBundleIDs))

        for target in targets {
            if ctx.isCancelled() { return }
            let url = home.appendingPathComponent(target.rel)
            emitCache(at: url, app: target.app, quit: target.quit, ctx: ctx)
        }

        // Figma `Desktop/*Cache` — enumerate the Desktop dir and match any
        // immediate subdir whose name contains "Cache" (e.g. "DesktopProfile-…/Cache").
        if ctx.isCancelled() { return }
        let figmaDesktop = home.appendingPathComponent("Library/Application Support/Figma/Desktop")
        if FileScan.exists(figmaDesktop) {
            for child in directorySubdirs(of: figmaDesktop) {
                if ctx.isCancelled() { return }
                guard child.lastPathComponent.lowercased().contains("cache") else { continue }
                emitCache(at: child, app: "Figma", quit: Self.figmaBundleIDs, ctx: ctx,
                          manualOnly: true)
            }
        }
    }

    // MARK: - Helpers

    /// Missing / below-threshold paths are dropped by makeItem.
    private func emitCache(at url: URL, app: String, quit: [String], ctx: ScanContext,
                           manualOnly: Bool = false) {
        guard FileScan.exists(url) else { return }
        ctx.progress("\(app) cache")
        let uncertain = manualOnly || url.path.contains("CacheStorage")
            || url.path.contains("PersistentCache") || url.path.contains("Group Containers")
            || url.path.contains("/Logs/") || url.path.contains("AutoUpdater")
        if let item = makeItem(
            at: url,
            severity: uncertain ? .review : .safe,
            minSize: ctx.minSizeBytes,
            isRegenerable: true,
            requiresQuitBundleIDs: quit,
            cleanMethod: .trash,
            note: uncertain ? "\(app) offline and diagnostic storage — review before removing" :
                "\(app) transient cache — recreated on launch",
            selectedIfSafe: !uncertain,
            maxFiles: Self.maxCacheFiles
        ) {
            ctx.emit(item)
        }
    }

    /// Immediate subdirectories of `dir` (one level), skipping symlinks. Empty on
    /// error. Used for the Figma `Desktop/*Cache` wildcard case.
    private func directorySubdirs(of dir: URL) -> [URL] {
        guard let children = FileScan.children(of: dir) else { return [] }
        return children.filter { child in
            let rv = try? child.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            return rv?.isSymbolicLink != true && rv?.isDirectory == true
        }
    }
}
