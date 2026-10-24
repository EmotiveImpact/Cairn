import Foundation

/// Stale installer disk images / packages sitting in ~/Downloads. Once an app is
/// installed the original `.dmg`/`.pkg`/`.iso` is dead weight. When the file's
/// name matches an app that is already installed it is SAFE and pre-selected;
/// otherwise it may be the only copy of something, so it stays REVIEW. Either
/// way it is the user's own download, so it always goes to the Trash rather
/// than being deleted outright (see `ScanItem.isRebuildable`).
///
/// "Install macOS …" apps in /Applications are sized as advice: Cairn never
/// removes app bundles from a cleanup list, so they are pointed at Apps.
///
/// Fixes prototype BUG-010: the prototype also swept archive formats
/// (`.zip`/`.xz`/`.bz2`/`.tar.gz`) which are frequently the only copy of user
/// data. Those are NEVER matched here — only genuine installer media is.
struct InstallersScanner: CairnScanner {
    let info = CategoryInfo(
        id: "installers",
        title: "Installers in Downloads",
        subtitle: "Old .dmg / .pkg / .iso files in ~/Downloads",
        systemImage: "opticaldisc.fill",
        group: .general,
        requiresFDA: false
    )

    /// Installer media only — deliberately excludes archive formats, which often
    /// hold the sole local copy of user data.
    private static let installerExtensions: Set<String> = ["dmg", "pkg", "iso"]

    /// Files newer than this are likely still in use (just downloaded).
    private static let minAgeDays: Double = 30
    /// An installer whose app is already installed has done its job; a week
    /// leaves time to reinstall after a failed first run.
    private static let installedAppMinAgeDays: Double = 7

    /// Small floor so we don't surface trivial stub files.
    private static let floorBytes: Int64 = 1 * 1024 * 1024  // 1 MB

    func scan(_ ctx: ScanContext) async {
        let downloads = FileScan.home.appendingPathComponent("Downloads")
        guard FileScan.exists(downloads) else { emitMacOSInstallers(ctx); return }

        ctx.progress("Scanning Downloads for installers")
        let installed = Self.installedApps()
        guard let children = FileScan.children(of: downloads) else { emitMacOSInstallers(ctx); return }

        for child in children {
            if ctx.isCancelled() { return }

            // Match installer media by extension only (case-insensitive). Never
            // archives — those are treated as user data (BUG-010).
            let ext = child.pathExtension.lowercased()
            guard Self.installerExtensions.contains(ext) else { continue }

            // Skip symlinks / directories / iCloud stubs; measure leaf bytes.
            let rv = try? child.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            if rv?.isSymbolicLink == true { continue }
            if rv?.isDirectory == true { continue }

            ctx.progress(child.lastPathComponent)

            let age = Fmt.age(Date().timeIntervalSince(latestModified(of: child)) / 86_400)
            let app = Self.installedApp(matching: child.deletingPathExtension().lastPathComponent, in: installed)
            if let item = makeItem(
                at: child,
                severity: app == nil ? .review : .safe,
                minSize: Self.floorBytes,
                // The app is installed and its maker offers the download again.
                isRegenerable: app != nil,
                cleanMethod: .trash,
                note: app.map { "Installer for \($0), which is already installed (\(ext), \(age))" }
                    ?? "Installer in Downloads (\(ext), \(age))",
                selectedIfSafe: true
            ) {
                // Only surface files that are genuinely stale: 30 days, or a
                // week when the app it installs is already in Applications.
                guard item.ageDays >= (app == nil ? Self.minAgeDays : Self.installedAppMinAgeDays) else { continue }
                ctx.emit(item)
            }
        }

        emitMacOSInstallers(ctx)
    }

    // MARK: - Matching installers to installed apps

    /// Installed app names, normalised, mapped to their display names.
    private static func installedApps() -> [String: String] {
        var apps: [String: String] = [:]
        let roots = [URL(fileURLWithPath: "/Applications"), FileScan.home.appendingPathComponent("Applications")]
        for root in roots {
            for app in FileScan.children(of: root) ?? [] where app.pathExtension == "app" {
                let name = app.deletingPathExtension().lastPathComponent
                let key = normalise(name)
                if key.count >= 3 { apps[key] = name }
            }
        }
        return apps
    }

    /// Words installer names add after the app's own name.
    private static let installerWords = [
        "installer", "install", "setup", "desktop", "universal", "applesilicon", "silicon",
        "arm", "aarch", "intel", "x", "amd", "mac", "macos", "osx", "darwin", "apple", "release",
        "stable", "latest", "full", "signed", "dmg", "pkg", "v",
    ].sorted { $0.count > $1.count }

    /// Names are reduced to letters ("Docker-4.34.2-arm64" → "dockerarm"). An
    /// installer matches an app when its letters are the app's letters followed
    /// only by installer words, so "Notion Calendar.dmg" never matches Notion.
    /// Three-letter minimum keeps short names from matching everything.
    static func installedApp(matching fileName: String, in apps: [String: String]) -> String? {
        let key = normalise(fileName)
        guard key.count >= 3 else { return nil }
        return apps.filter { key.hasPrefix($0.key) && onlyInstallerWords(String(key.dropFirst($0.key.count))) }
            .max { $0.key.count < $1.key.count }?.value
    }

    private static func onlyInstallerWords(_ rest: String) -> Bool {
        var rest = Substring(rest)
        while !rest.isEmpty {
            guard let word = installerWords.first(where: { rest.hasPrefix($0) }) else { return false }
            rest = rest.dropFirst(word.count)
        }
        return true
    }

    private static func normalise(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter { CharacterSet.lowercaseLetters.contains($0) && $0.isASCII })
    }

    // MARK: - macOS installer apps

    private func emitMacOSInstallers(_ ctx: ScanContext) {
        for app in FileScan.children(of: URL(fileURLWithPath: "/Applications")) ?? [] {
            if ctx.isCancelled() { return }
            let name = app.deletingPathExtension().lastPathComponent
            guard app.pathExtension == "app", name.hasPrefix("Install macOS") else { continue }
            let stats = FileScan.measure(app)
            guard stats.allocatedSize >= Self.floorBytes else { continue }
            ctx.emit(ScanItem(
                url: app,
                allocatedSize: stats.allocatedSize,
                itemCount: stats.fileCount,
                latestModified: stats.latestModified,
                categoryID: info.id,
                severity: .review,
                isRegenerable: false,
                requiresQuitBundleIDs: [],
                requiresRunning: false,
                cleanMethod: .adviceOnly,
                note: "\(name) — the macOS installer stays after an upgrade. Remove it in Apps; the App Store downloads it again if needed",
                permissionDenied: stats.permissionDenied,
                volumeURL: FileScan.volumeURL(of: app),
                selected: false
            ))
        }
    }

    /// Modification date of a single file (for the human-readable age in the note),
    /// falling back to the distant past if unreadable.
    private func latestModified(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }
}
