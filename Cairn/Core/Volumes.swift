import Foundation

/// Per-volume free space + the precondition checks behind the honest-reclaim
/// promise (SPEC §5.2). "Free" uses `volumeAvailableCapacityForImportantUsage`
/// (accounts for APFS purgeable), never raw statfs/df.
enum Volumes {
    struct Info {
        var url: URL
        var name: String
        var totalCapacity: Int64
        var availableImportant: Int64   // capacity for "important" usage (purgeable-aware)
    }

    static func info(for volumeURL: URL?) -> Info? {
        guard let v = volumeURL else { return nil }
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let rv = try? v.resourceValues(forKeys: keys) else { return nil }
        return Info(
            url: v,
            name: rv.volumeName ?? v.lastPathComponent,
            totalCapacity: Int64(rv.volumeTotalCapacity ?? 0),
            availableImportant: rv.volumeAvailableCapacityForImportantUsage ?? 0
        )
    }

    /// Free space on the volume backing the user's home folder.
    static func homeFree() -> Int64 {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return info(for: FileScan.volumeURL(of: home))?.availableImportant ?? 0
    }

    /// Mounted, browsable volumes under /Volumes the user might keep repos on.
    static func mountedExternalVolumes() -> [URL] {
        let keys: [URLResourceKey] = [.volumeIsBrowsableKey, .volumeIsLocalKey]
        let mounts = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []
        return mounts.filter { url in
            // Exclude the boot volume ("/") — that's covered by HOME roots.
            url.path.hasPrefix("/Volumes/")
        }
    }
}
