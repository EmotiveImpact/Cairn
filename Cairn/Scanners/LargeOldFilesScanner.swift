import Foundation

/// Large and/or stale files sitting in the user's own folders (~/Downloads,
/// ~/Desktop, ~/Movies). These are NOT regenerable caches — they are the user's
/// own data, frequently the only local copy — so every hit is REVIEW and never
/// pre-selected. The scanner only surfaces what is worth a human glance:
///   • "large"  → >= 200 MB (worth reviewing regardless of age)
///   • "old"    → >= 50 MB AND not touched in over 180 days (stale heavyweight)
///
/// We walk a bounded depth (~4 levels) and treat bundle directories
/// (`*.app`, `*.photoslibrary`) as opaque leaves we never descend into — their
/// internals are app/library state, not loose user files. Symlinks are never
/// followed. `FileScan.measure` handles single-file sizing (and skips iCloud
/// dataless stubs so we never hydrate "Optimize Mac Storage" files).
struct LargeOldFilesScanner: CairnScanner {
    let info = CategoryInfo(
        id: "large-old",
        title: "Large & Old Files",
        subtitle: "Big or long-untouched files in Downloads, Desktop, Movies",
        systemImage: "doc.fill",
        group: .general,
        requiresFDA: false
    )

    // Thresholds.
    private static let largeBytes: Int64 = 200 * 1024 * 1024   // >= 200 MB → "large"
    private static let oldFloorBytes: Int64 = 50 * 1024 * 1024 // >= 50 MB  → eligible for "old"
    private static let oldAgeDays: Double = 180                // older than 180d → "old"

    /// Maximum directory depth to descend (root files are depth 0).
    private static let maxDepth = 4

    /// Bundle directories we treat as opaque leaves — never descend into them.
    private static let opaqueBundleExtensions: Set<String> = ["app", "photoslibrary"]

    func scan(_ ctx: ScanContext) async {
        let roots = ["Downloads", "Desktop", "Movies"].map {
            FileScan.home.appendingPathComponent($0)
        }

        for root in roots {
            if ctx.isCancelled() { return }
            guard FileScan.exists(root) else { continue }
            ctx.progress("Scanning \(root.lastPathComponent)")
            walk(root, depth: 0, ctx: ctx)
        }
    }

    // MARK: - Bounded recursive walk

    /// One level of the walk. Emits qualifying files, recurses into plain
    /// subdirectories up to `maxDepth`, and never descends into bundles or
    /// follows symlinks.
    private func walk(_ dir: URL, depth: Int, ctx: ScanContext) {
        guard let children = FileScan.children(of: dir) else { return }

        for child in children {
            if ctx.isCancelled() { return }

            let rv = try? child.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            if rv?.isSymbolicLink == true { continue }          // never follow symlinks

            if rv?.isDirectory == true {
                // Bundles (`*.app`, `*.photoslibrary`) are opaque — skip entirely.
                if Self.opaqueBundleExtensions.contains(child.pathExtension.lowercased()) { continue }
                // Recurse into plain directories, bounded by maxDepth.
                if depth < Self.maxDepth {
                    walk(child, depth: depth + 1, ctx: ctx)
                }
                continue
            }

            // A regular file — evaluate it.
            evaluate(child, ctx: ctx)
        }
    }

    /// Measure a single file and emit a REVIEW item if it qualifies as large or
    /// old. Built directly via the ScanItem initializer (not `makeItem`) so the
    /// two-threshold qualification — and the per-file note — is explicit and we
    /// bypass makeItem's single-threshold min-size skip.
    private func evaluate(_ url: URL, ctx: ScanContext) {
        let stats = FileScan.measure(url)
        // measure() returns zeroed stats for symlinks / iCloud stubs.
        guard stats.fileCount > 0, stats.allocatedSize > 0 else { return }

        let isLarge = stats.allocatedSize >= Self.largeBytes
        let ageDays = max(0, Date().timeIntervalSince(stats.latestModified) / 86_400)
        let isOld = stats.allocatedSize >= Self.oldFloorBytes && ageDays >= Self.oldAgeDays

        guard isLarge || isOld else { return }

        ctx.progress(url.lastPathComponent)

        let note: String
        if isLarge && isOld {
            note = "Large + old file (\(Fmt.age(ageDays)))"
        } else if isLarge {
            note = "Large file"
        } else {
            note = "Old file (\(Fmt.age(ageDays)))"
        }

        let item = ScanItem(
            url: url,
            allocatedSize: stats.allocatedSize,
            itemCount: stats.fileCount,
            latestModified: stats.latestModified,
            categoryID: info.id,
            severity: .review,                  // user's own data → never SAFE
            isRegenerable: false,               // not a regenerable cache
            cleanMethod: .trash,
            note: note,
            permissionDenied: stats.permissionDenied,
            volumeURL: FileScan.volumeURL(of: url),
            selected: false                     // never pre-selected
        )
        ctx.emit(item)
    }
}
