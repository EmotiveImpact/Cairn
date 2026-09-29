import Foundation

/// Result of a single-pass measurement of a directory tree.
struct DirStats {
    var allocatedSize: Int64 = 0
    var latestModified: Date = .distantPast
    var fileCount: Int = 0
    /// True if any entry could not be read (EPERM/EACCES) — the size is a lower
    /// bound and the UI must say "incomplete (permission denied)" rather than
    /// presenting an undercount as complete (prototype BUG-003).
    var permissionDenied: Bool = false
    /// True if measurement stopped at a file/entry/time limit or was cancelled;
    /// the size is a lower bound ("≥"), never an exact reclaim estimate.
    var truncated: Bool = false
    /// A cancelled measurement is incomplete and must not be treated as exact.
    var cancelled: Bool = false
    /// The monotonic per-tree time budget expired while measuring this item.
    var timedOut: Bool = false
}

/// Filesystem measurement. ONE enumerator pass accumulates on-disk allocated
/// size + latest mtime + file count together (fixes prototype BUG-001, the
/// double walk). Skips symlinks and iCloud dataless stubs so we never hydrate
/// "Optimize Mac Storage" files just to size them (prototype BUG-007).
enum FileScan {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    // A default `.max` from older scanners must not become an unbounded tree walk
    // on a Mac with a huge cache or an external volume. Both caps produce partial
    // sizes (DirStats.truncated), which makeItem labels for review.
    private static let hardFileLimit = 100_000
    private static let hardEntryLimit = 250_000
    private static let defaultMeasureSeconds: TimeInterval = 4

    private static let sizeKeys: Set<URLResourceKey> = [
        .totalFileAllocatedSizeKey,   // on-disk, incl. metadata/blocks
        .fileAllocatedSizeKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .isDirectoryKey,
        .isUbiquitousItemKey,
    ]

    /// Measure a single directory (or file) tree in one walk. `maxFiles` caps the
    /// number of files counted so one pathological tree can't dominate a scan
    /// (BUG-014). The hard entry cap also bounds trees with very many directories
    /// or tiny/non-regular files. The monotonic deadline bounds slow I/O across
    /// all callers; cancellation and every cap mark the result incomplete.
    static func measure(_ url: URL, maxFiles: Int = .max,
                        maxDuration: TimeInterval = defaultMeasureSeconds) -> DirStats {
        autoreleasepool { measureTree(url, maxFiles: maxFiles, maxDuration: maxDuration) }
    }

    private static func measureTree(_ url: URL, maxFiles: Int, maxDuration: TimeInterval) -> DirStats {
        var stats = DirStats()
        let fm = FileManager.default
        if Task.isCancelled { stats.cancelled = true; stats.truncated = true; return stats }
        let fileLimit = min(max(1, maxFiles), hardFileLimit)
        let deadline = ProcessInfo.processInfo.systemUptime + max(0.05, maxDuration)

        // Symlink? Never follow; don't count (the target is sized via its own root).
        let rv = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey,
                                                    .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
                                                    .fileSizeKey, .contentModificationDateKey, .isUbiquitousItemKey])
        if ProcessInfo.processInfo.systemUptime >= deadline {
            stats.timedOut = true; stats.truncated = true; return stats
        }
        if rv?.isSymbolicLink == true { return stats }

        if rv?.isDirectory != true {
            // Single file.
            if rv?.isUbiquitousItem == true { return stats } // iCloud stub — leave unhydrated
            if let mod = rv?.contentModificationDate { stats.latestModified = mod }
            stats.allocatedSize = allocated(from: rv)
            stats.fileCount = 1
            return stats
        }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: Array(sizeKeys),
            options: [],
            errorHandler: { _, error in
                let ns = error as NSError
                if ns.domain == NSCocoaErrorDomain || ns.domain == NSPOSIXErrorDomain {
                    // EPERM (1) / EACCES (13) → likely Full Disk Access gap.
                    if ns.code == 257 || ns.code == 13 || ns.code == 1 { stats.permissionDenied = true }
                }
                return true // keep going; record the gap
            }
        ) else { return stats }
        if ProcessInfo.processInfo.systemUptime >= deadline {
            stats.timedOut = true; stats.truncated = true; return stats
        }

        var examined = 0
        while true {
            var stop = false
            // nextObject itself creates autoreleased NSURL objects. Keeping it
            // outside this pool retains every visited URL for the entire scan.
            autoreleasepool {
                if Task.isCancelled { stats.cancelled = true; stats.truncated = true; stop = true; return }
                if ProcessInfo.processInfo.systemUptime >= deadline { stats.timedOut = true; stats.truncated = true; stop = true; return }
                guard let item = enumerator.nextObject() as? URL else { stop = true; return }
                examined += 1
                if examined > hardEntryLimit { stats.truncated = true; stop = true; return }
                guard let v = try? item.resourceValues(forKeys: sizeKeys) else { return }
                if v.isSymbolicLink == true { enumerator.skipDescendants(); return }
                if v.isUbiquitousItem == true { enumerator.skipDescendants(); return }
                if v.isDirectory == true { return }
                stats.allocatedSize += allocated(from: v)
                stats.fileCount += 1
                if let mod = v.contentModificationDate, mod > stats.latestModified { stats.latestModified = mod }
                if stats.fileCount >= fileLimit { stats.truncated = true; stop = true }
            }
            if stop { break }
        }
        if !stats.truncated && ProcessInfo.processInfo.systemUptime >= deadline {
            stats.timedOut = true
            stats.truncated = true
        }
        return stats
    }

    private static func allocated(from v: URLResourceValues?) -> Int64 {
        if let a = v?.totalFileAllocatedSize { return Int64(a) }
        if let a = v?.fileAllocatedSize { return Int64(a) }
        if let s = v?.fileSize { return Int64(s) }
        return 0
    }

    /// The volume URL a path lives on (for volume-aware Trash + free-space checks).
    static func volumeURL(of url: URL) -> URL? {
        (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Direct children of a directory (one level), nil on error.
    static func children(of url: URL) -> [URL]? {
        try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
    }
}
