import Foundation

/// Stale installer disk images / packages sitting in ~/Downloads. Once an app is
/// installed the original `.dmg`/`.pkg`/`.iso` is dead weight — but it is the
/// user's own download, not a regenerable cache, so it is always REVIEW and
/// never pre-selected.
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

    /// Small floor so we don't surface trivial stub files.
    private static let floorBytes: Int64 = 1 * 1024 * 1024  // 1 MB

    func scan(_ ctx: ScanContext) async {
        let downloads = FileScan.home.appendingPathComponent("Downloads")
        guard FileScan.exists(downloads) else { return }

        ctx.progress("Scanning Downloads for installers")
        guard let children = FileScan.children(of: downloads) else { return }

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

            if let item = makeItem(
                at: child,
                severity: .review,
                minSize: Self.floorBytes,
                isRegenerable: false,
                cleanMethod: .trash,
                note: "Installer in Downloads (\(ext), \(Fmt.age(Date().timeIntervalSince(latestModified(of: child)) / 86_400)))",
                selectedIfSafe: false
            ) {
                // Only surface files that are genuinely stale (older than 30d).
                guard item.ageDays >= Self.minAgeDays else { continue }
                ctx.emit(item)
            }
        }
    }

    /// Modification date of a single file (for the human-readable age in the note),
    /// falling back to the distant past if unreadable.
    private func latestModified(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }
}
