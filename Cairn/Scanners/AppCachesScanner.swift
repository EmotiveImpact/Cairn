import Foundation

/// General application caches under `~/Library/Caches`. Each direct child folder
/// is an app's reclaimable cache that the app recreates on next launch (SPEC §3.3).
/// Browser, IDE, container and dev-tool caches that also land here are deliberately
/// EXCLUDED — they are owned by the dedicated dev/browser/IDE scanners so we never
/// double-count or apply the wrong clean method. Reads `~/Library/Caches`, which
/// can contain TCC-gated app data, so this scanner requires Full Disk Access.
struct AppCachesScanner: CairnScanner {
    let info = CategoryInfo(
        id: "app-caches",
        title: "Application Caches",
        subtitle: "Per-app caches in ~/Library/Caches — apps recreate these",
        systemImage: "app.badge.fill",
        group: .general,
        requiresFDA: true
    )

    /// Folder-name prefixes owned by other scanners (browser / IDE / dev tools)
    /// or that are system-managed and unsafe to touch from here.
    private static let excludedPrefixes: [String] = [
        // Browsers (own scanner)
        "com.apple.Safari",
        "com.apple.WebKit",
        "Google/Chrome",
        "Mozilla",
        "Firefox",
        "BraveSoftware",
        "company.thebrowser.Browser",
        // IDEs / editors (own scanner)
        "com.microsoft.VSCode",
        "Code",
        "Cursor",
        "JetBrains",
        // Dev tools / package managers (DevCachesScanner & friends)
        "com.docker",
        "Homebrew",
        "CocoaPods",
        "org.swift.swiftpm",
        "org.carthage",
        "go-build",
        "pip",
        "deno",
        "ccache",
        "pypoetry",
        "uv",
        // System-managed caches — never surface from here
        "com.apple.Spotlight",
        "com.apple.HomeKit",
        "com.apple.iCloud",
        "CloudKit",
        "com.apple.bird",
    ]

    private func isExcluded(_ name: String) -> Bool {
        for prefix in Self.excludedPrefixes where name.hasPrefix(prefix) {
            return true
        }
        return false
    }

    /// A folder name that looks like a bundle id (reverse-DNS, contains a dot)
    /// names the owning app, which must quit before its cache can be cleaned.
    private func bundleIDs(for name: String) -> [String] {
        name.contains(".") ? [name] : []
    }

    func scan(_ ctx: ScanContext) async {
        let cachesRoot = FileScan.home.appendingPathComponent("Library/Caches")
        guard FileScan.exists(cachesRoot), let children = FileScan.children(of: cachesRoot) else { return }

        for child in children {
            if ctx.isCancelled() { return }

            // Only consider directories; skip stray files / symlinks.
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

            let name = child.lastPathComponent
            if isExcluded(name) { continue }

            ctx.progress(name)

            if let item = makeItem(
                at: child,
                severity: .safe,
                minSize: ctx.minSizeBytes,
                isRegenerable: true,
                requiresQuitBundleIDs: bundleIDs(for: name),
                cleanMethod: .trash,
                note: "Cache for \(name) — apps recreate this",
                selectedIfSafe: true
            ) {
                ctx.emit(item)
            }
        }
    }
}
