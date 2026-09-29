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

    /// (label, home-relative path, severity, method, note)
    private struct Target {
        let label: String, rel: String, sev: Severity, method: CleanMethod, note: String
    }

    private var targets: [Target] {
        func tool(_ t: String, _ a: [String], _ d: String, destroys: Bool = false) -> CleanMethod {
            .tool(ToolCommand(tool: t, arguments: a, display: d, destroysData: destroys))
        }
        return [
            .init(label: "npm cache", rel: ".npm/_cacache", sev: .safe, method: .trash, note: "npm package cache — reinstalls on next install"),
            .init(label: "npm logs", rel: ".npm/_logs", sev: .safe, method: .trash, note: "npm install logs"),
            .init(label: "Yarn (classic)", rel: "Library/Caches/Yarn", sev: .safe, method: .trash, note: "Yarn v1 cache — `yarn cache clean`"),
            .init(label: "Yarn Berry", rel: ".yarn/berry/cache", sev: .safe, method: .trash, note: "Yarn Berry global cache"),
            .init(label: "pnpm store", rel: "Library/pnpm/store", sev: .review, method: tool("pnpm", ["store", "prune"], "pnpm store prune"), note: "Hard-linked into projects — prune, never delete"),
            .init(label: "pnpm store (XDG)", rel: ".local/share/pnpm/store", sev: .review, method: tool("pnpm", ["store", "prune"], "pnpm store prune"), note: "Hard-linked into projects — prune, never delete"),
            .init(label: "Bun cache", rel: ".bun/install/cache", sev: .safe, method: .trash, note: "Bun install cache"),
            .init(label: "pip cache", rel: "Library/Caches/pip", sev: .safe, method: .trash, note: "pip wheel cache — `pip cache purge`"),
            .init(label: "uv cache", rel: ".cache/uv", sev: .safe, method: .trash, note: "uv cache"),
            .init(label: "Poetry cache", rel: "Library/Caches/pypoetry", sev: .safe, method: .trash, note: "Poetry cache"),
            .init(label: "Cargo registry", rel: ".cargo/registry/cache", sev: .safe, method: .trash, note: "Rust registry tarballs — re-downloaded on build"),
            .init(label: "Cargo git db", rel: ".cargo/git/db", sev: .safe, method: .trash, note: "Cargo git dependency cache"),
            .init(label: "Go module cache", rel: "go/pkg/mod", sev: .safe, method: tool("go", ["clean", "-modcache"], "go clean -modcache"), note: "Read-only (0444) — use go clean, not rm"),
            .init(label: "Go build cache", rel: "Library/Caches/go-build", sev: .safe, method: .trash, note: "Go build cache — `go clean -cache`"),
            .init(label: "Gradle caches", rel: ".gradle/caches", sev: .review, method: .trash, note: "Gradle dependency + build caches"),
            .init(label: "Gradle wrapper dists", rel: ".gradle/wrapper/dists", sev: .review, method: .trash, note: "Downloaded Gradle distributions — pile up forever"),
            .init(label: "Maven repository", rel: ".m2/repository", sev: .review, method: .trash, note: "Maven local repo — re-resolves on next build"),
            .init(label: "Ivy cache", rel: ".ivy2/cache", sev: .review, method: .trash, note: "Ivy cache"),
            .init(label: "CocoaPods cache", rel: "Library/Caches/CocoaPods", sev: .safe, method: .trash, note: "CocoaPods cache — `pod cache clean --all`"),
            .init(label: "Carthage cache", rel: "Library/Caches/org.carthage.CarthageKit", sev: .safe, method: .trash, note: "Rebuilds on `carthage bootstrap`"),
            .init(label: "SwiftPM cache", rel: "Library/Caches/org.swift.swiftpm", sev: .safe, method: .trash, note: "SwiftPM artifacts — `swift package resolve` restores"),
            .init(label: "ccache", rel: ".cache/ccache", sev: .safe, method: .trash, note: "C/C++ compiler cache — `ccache -C`"),
            .init(label: "ccache (Library)", rel: "Library/Caches/ccache", sev: .safe, method: .trash, note: "C/C++ compiler cache"),
            .init(label: "Composer cache", rel: ".composer/cache", sev: .safe, method: .trash, note: "PHP Composer cache"),
            .init(label: "Homebrew cache", rel: "Library/Caches/Homebrew", sev: .safe, method: .trash, note: "Downloaded bottles — `brew cleanup --prune=all`"),
            .init(label: "Deno cache", rel: "Library/Caches/deno", sev: .review, method: .trash, note: "Deno module cache"),
            .init(label: "NuGet packages", rel: ".nuget/packages", sev: .review, method: .trash, note: ".NET packages — `dotnet nuget locals all --clear`"),
        ]
    }

    func scan(_ ctx: ScanContext) async {
        // Many package caches contain hundreds of thousands of tiny files. A
        // per-tree limit alone still allows the whole category to run for minutes.
        let budget: TimeInterval = 18
        let deadline = ProcessInfo.processInfo.systemUptime + budget
        let list = targets
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
        if stats.allocatedSize < ctx.minSizeBytes && !target.method.isPaid && !stats.truncated { return nil }

        let partial = stats.truncated || stats.permissionDenied
        let method: CleanMethod = partial && stats.allocatedSize == 0 ? .adviceOnly : target.method
        let note = "\(target.label) — \(target.note)" +
            (partial ? " · Partial size (lower bound); review before cleaning" : "")
        return ScanItem(
            url: url,
            allocatedSize: stats.allocatedSize,
            itemCount: stats.fileCount,
            latestModified: stats.latestModified,
            categoryID: info.id,
            severity: partial ? .review : target.sev,
            isRegenerable: true,
            cleanMethod: method,
            note: note,
            permissionDenied: stats.permissionDenied,
            volumeURL: FileScan.volumeURL(of: url),
            selected: !partial && target.sev == .safe && method.isActionable
        )
    }
}
