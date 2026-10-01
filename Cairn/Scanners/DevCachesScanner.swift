import Foundation

/// Package-manager & build-tool caches — the developer wedge. Ported and
/// extended from the prototype's `dev_caches.py` DEV_TARGETS table (SPEC §3.1).
/// These live in plain user dirs (0700) → no Full Disk Access needed.
struct DevCachesScanner: CairnScanner {
    let info = CategoryInfo(
        id: "dev-caches",
        title: "Developer Caches",
        subtitle: "Time-limited inventory of npm, yarn, pnpm, pip, cargo, go and more. Partial sizes are lower bounds.",
        systemImage: "shippingbox.fill",
        group: .developer,
        requiresFDA: false
    )

    /// These are observations, not deletion targets. A fixed home-relative
    /// path does not prove the tool's configured cache, and a scan cannot prove
    /// a CLI process has stopped writing. Re-enable one target only through a
    /// separately validated, tool-specific adapter.
    private struct Target {
        let label: String, rel: String, note: String
    }

    private static let targets: [Target] = [
            .init(label: "npm cache", rel: ".npm/_cacache", note: "Check npm's configured cache and active installs before using npm's own maintenance."),
            .init(label: "npm logs", rel: ".npm/_logs", note: "Install logs may have active writers or useful diagnostics. Review in npm."),
            .init(label: "Yarn (classic)", rel: "Library/Caches/Yarn", note: "Check Yarn's configured cache and active installs before using yarn cache clean."),
            .init(label: "Yarn Berry", rel: ".yarn/berry/cache", note: "Global cache may be shared with projects. Check configuration and active installs."),
            .init(label: "pnpm store", rel: "Library/pnpm/store", note: "May be hard-linked into projects. Check configured store and active installs before using pnpm store prune."),
            .init(label: "pnpm store (XDG)", rel: ".local/share/pnpm/store", note: "May be hard-linked into projects. Check configured store and active installs before using pnpm store prune."),
            .init(label: "Bun cache", rel: ".bun/install/cache", note: "Check Bun's configured cache and active installs before maintenance."),
            .init(label: "pip cache", rel: "Library/Caches/pip", note: "Check pip's configured cache and active installs before using pip cache commands."),
            .init(label: "uv cache", rel: ".cache/uv", note: "Shared package cache may be in use. Check uv configuration and active operations."),
            .init(label: "Poetry cache", rel: "Library/Caches/pypoetry", note: "Check Poetry's configured cache and active installs before maintenance."),
            .init(label: "Cargo registry", rel: ".cargo/registry/cache", note: "Downloaded crate archives may be shared across projects. Check active Cargo operations."),
            .init(label: "Cargo git db", rel: ".cargo/git/db", note: "Shared Git dependency cache. Check active Cargo operations and project recovery needs."),
            .init(label: "Go module cache", rel: "go/pkg/mod", note: "Check GOMODCACHE and active builds before using go clean -modcache."),
            .init(label: "Go build cache", rel: "Library/Caches/go-build", note: "Check GOCACHE and active builds before using go clean -cache."),
            .init(label: "Gradle caches", rel: ".gradle/caches", note: "Shared dependencies and build state. Check active daemons and configured Gradle home."),
            .init(label: "Gradle wrapper dists", rel: ".gradle/wrapper/dists", note: "Installed Gradle distributions may be pinned by projects. Review versions first."),
            .init(label: "Maven repository", rel: ".m2/repository", note: "Local repository may contain artifacts unavailable elsewhere. Inspect before maintenance."),
            .init(label: "Ivy cache", rel: ".ivy2/cache", note: "Shared dependencies may be in use or unavailable elsewhere. Inspect first."),
            .init(label: "CocoaPods cache", rel: "Library/Caches/CocoaPods", note: "Check configured cache and active installs before pod cache maintenance."),
            .init(label: "Carthage cache", rel: "Library/Caches/org.carthage.CarthageKit", note: "Check active builds and whether dependencies can be fetched again."),
            .init(label: "SwiftPM cache", rel: "Library/Caches/org.swift.swiftpm", note: "Shared package artifacts may be in use. Check active builds and configured cache."),
            .init(label: "ccache", rel: ".cache/ccache", note: "Check CCACHE_DIR and active compiler processes before ccache maintenance."),
            .init(label: "ccache (Library)", rel: "Library/Caches/ccache", note: "Check CCACHE_DIR and active compiler processes before ccache maintenance."),
            .init(label: "Composer cache", rel: ".composer/cache", note: "Check Composer's configured cache and active installs before maintenance."),
            .init(label: "Homebrew cache", rel: "Library/Caches/Homebrew", note: "Check Homebrew's configured cache and active operations before cleanup."),
            .init(label: "Deno cache", rel: "Library/Caches/deno", note: "Check Deno's configured cache and active runs before maintenance."),
            .init(label: "NuGet packages", rel: ".nuget/packages", note: "Shared packages may be in use. Check NuGet configuration and active restores."),
    ]

    /// Reject a legacy Trash item for any cache root observed by this scanner.
    /// The displayed path is not proof that the corresponding CLI uses it.
    static func isObservedToolCache(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return targets.contains { target in
            let root = FileScan.home.appendingPathComponent(target.rel).standardizedFileURL.path
            return path == root || path.hasPrefix(root + "/")
        }
    }

    func scan(_ ctx: ScanContext) async {
        // Many package caches contain hundreds of thousands of tiny files. A
        // per-tree limit alone still allows the whole category to run for minutes.
        let budget: TimeInterval = 18
        let deadline = ProcessInfo.processInfo.systemUptime + budget
        let list = Self.targets
        for (index, t) in list.enumerated() {
            if ctx.isCancelled() { return }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining <= 0 {
                ctx.progress("Developer cache time limit reached; remaining locations were not measured")
                // An advice row for a REAL unmeasured cache path keeps the partial
                // category visible even if no earlier target met the size floor.
                for pending in list[index...] {
                    let path = FileScan.home.appendingPathComponent(pending.rel)
                    if SafePaths.protectedSessionReason(path) == nil && FileScan.exists(path) {
                        ctx.emit(ScanItem(
                            url: path, allocatedSize: 0, categoryID: info.id,
                            severity: .review, isRegenerable: false,
                            cleanMethod: .adviceOnly,
                            note: "Scan paused at the 18-second limit. This and later cache paths were not measured; run another scan to review them.",
                            selected: false
                        ))
                        break
                    }
                }
                return
            }
            let url = FileScan.home.appendingPathComponent(t.rel)
            ctx.progress(t.label)
            if let item = measureTarget(t, at: url, ctx: ctx,
                                        maxDuration: min(4, remaining)) {
                ctx.emit(item)
            }
        }
    }

    private func measureTarget(_ target: Target, at url: URL, ctx: ScanContext,
                               maxDuration: TimeInterval) -> ScanItem? {
        guard SafePaths.protectedSessionReason(url) == nil else { return nil }
        guard FileScan.exists(url) else { return nil }
        let stats = FileScan.measure(url, maxDuration: maxDuration)
        if ctx.isCancelled() || stats.cancelled { return nil }
        // A timed-out tree may have exceeded the floor even when its measured
        // prefix did not. Show the lower bound rather than silently hiding it.
        if stats.allocatedSize < ctx.minSizeBytes && !stats.truncated { return nil }

        let partial = stats.truncated || stats.permissionDenied
        let note = "\(target.label) — \(target.note)" +
            (partial ? " · Partial size (lower bound)" : "") + " Cairn will not remove this tool-owned cache."
        return ScanItem(
            url: url,
            allocatedSize: stats.allocatedSize,
            itemCount: stats.fileCount,
            latestModified: stats.latestModified,
            categoryID: info.id,
            severity: .review,
            isRegenerable: false,
            cleanMethod: .adviceOnly,
            note: note,
            permissionDenied: stats.permissionDenied,
            volumeURL: FileScan.volumeURL(of: url),
            selected: false
        )
    }
}
