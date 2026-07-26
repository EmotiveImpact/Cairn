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
    /// True if measurement stopped at `maxFiles` — size is a lower bound ("≥").
    var truncated: Bool = false
}

/// Filesystem measurement. ONE enumerator pass accumulates on-disk allocated
/// size + latest mtime + file count together (fixes prototype BUG-001, the
/// double walk). Skips symlinks and iCloud dataless stubs so we never hydrate
/// "Optimize Mac Storage" files just to size them (prototype BUG-007).
enum FileScan {
    static let home = FileManager.default.homeDirectoryForCurrentUser

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
    /// (BUG-014); when hit, `truncated` is set and the size is a lower bound.
    static func measure(_ url: URL, maxFiles: Int = .max) -> DirStats {
        var stats = DirStats()
        let fm = FileManager.default

        // Symlink? Never follow; don't count (the target is sized via its own root).
        let rv = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey,
                                                    .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
                                                    .fileSizeKey, .contentModificationDateKey, .isUbiquitousItemKey])
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

        for case let item as URL in enumerator {
            // autoreleasepool per item: enumerating huge trees otherwise piles up
            // autoreleased URL/resourceValues objects until the runloop drains —
            // a classic multi-GB memory spike on large scans.
            var stop = false
            autoreleasepool {
                guard let v = try? item.resourceValues(forKeys: sizeKeys) else { return }
                if v.isSymbolicLink == true { return }
                if v.isUbiquitousItem == true { enumerator.skipDescendants(); return }
                if v.isDirectory == true { return } // count only leaf bytes
                stats.allocatedSize += allocated(from: v)
                stats.fileCount += 1
                if let mod = v.contentModificationDate, mod > stats.latestModified { stats.latestModified = mod }
                if stats.fileCount >= maxFiles { stats.truncated = true; stop = true }
            }
            if stop { break }
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
