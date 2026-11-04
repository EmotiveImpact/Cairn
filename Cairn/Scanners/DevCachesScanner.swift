import Foundation

/// Package-manager & build-tool caches — the developer wedge. Ported and
/// extended from the prototype's `dev_caches.py` DEV_TARGETS table (SPEC §3.1).
/// These live in plain user dirs (0700) → no Full Disk Access needed.
struct DevCachesScanner: CairnScanner {
    let info = CategoryInfo(
        id: "dev-caches",
        title: "Developer Caches",
        subtitle: "npm, yarn, pnpm, pip, cargo, go, gradle, Homebrew and more",
        systemImage: "shippingbox.fill",
        group: .developer,
        requiresFDA: false
    )

    /// Where the caches live. The reliability check points this at a fixture.
    var home: URL = FileScan.home
    /// The time limit for the whole category. Caches are measured three at a
    /// time, so this covers about a minute of measuring.
    var timeLimit: TimeInterval = 20
    /// The most one cache may take. Big caches such as Gradle hold hundreds of
    /// thousands of files, so the file count is lifted and time is the bound.
    var perCacheLimit: TimeInterval = 8
    /// Caches measured at once.
    static let parallel = 3

    /// Rebuildable package and build caches. Plain caches are removed directly;
    /// stores that are hard-linked into projects or read-only use the tool's own
    /// clean command instead.
    struct Target {
        enum Kind { case plain, gradleCaches, pnpmStore }
        let label: String, rel: String, sev: Severity, method: CleanMethod, note: String
        var kind: Kind = .plain
    }

    private static func tool(_ t: String, _ a: [String], _ d: String) -> CleanMethod {
        .tool(ToolCommand(tool: t, arguments: a, display: d))
    }

    /// Apps that run Gradle builds. Cleaning the Gradle cache waits until they are closed.
    static let gradleApps = ["com.google.android.studio", "com.google.android.studio-EAP",
                             "com.jetbrains.intellij", "com.jetbrains.intellij.ce"]
    /// A Gradle cache nobody has written to for this long has no build or
    /// background Gradle process using it (Gradle stops idle ones after 3 hours).
    static let gradleQuietSeconds: TimeInterval = 86_400

    private static let pnpmPrune = DevCachesScanner.tool("pnpm", ["store", "prune"], "pnpm store prune")
    private static let pnpmNote = "pnpm removes only packages no project uses, so it can free less than this"
    private static let condaClean = DevCachesScanner.tool("conda", ["clean", "--all", "--yes"], "conda clean --all")
    private static let condaNote = "Package downloads. conda clean removes only what no environment uses, so it can free less than the size shown"

    /// The usual biggest caches come first, so a slow Mac measures the ones
    /// that matter before the time limit. Any cache the limit skips still gets
    /// its own row saying it was not measured.
    static let targets: [Target] = [
        .init(label: "Homebrew cache", rel: "Library/Caches/Homebrew", sev: .safe, method: DevCachesScanner.tool("brew", ["cleanup", "--prune=all"], "brew cleanup --prune=all"), note: "Downloaded bottles and old versions"),
        .init(label: "Gradle caches", rel: ".gradle/caches", sev: .review, method: .trash, note: "Gradle dependency and build caches", kind: .gradleCaches),
        .init(label: "pnpm store", rel: "Library/pnpm/store", sev: .review, method: pnpmPrune, note: pnpmNote, kind: .pnpmStore),
        .init(label: "pnpm store (XDG)", rel: ".local/share/pnpm/store", sev: .review, method: pnpmPrune, note: pnpmNote, kind: .pnpmStore),
        .init(label: "npm cache", rel: ".npm/_cacache", sev: .safe, method: .trash, note: "npm package cache, downloaded again on the next install"),
        .init(label: "Go module cache", rel: "go/pkg/mod", sev: .safe, method: DevCachesScanner.tool("go", ["clean", "-modcache"], "go clean -modcache"), note: "Read-only module cache, cleared with go clean"),
        .init(label: "Cargo registry", rel: ".cargo/registry/cache", sev: .safe, method: .trash, note: "Rust crate archives, downloaded again on the next build"),
        .init(label: "Maven repository", rel: ".m2/repository", sev: .review, method: .trash, note: "Maven local repository, fetched again on the next build"),
        .init(label: "Yarn (classic)", rel: "Library/Caches/Yarn", sev: .safe, method: .trash, note: "Yarn v1 cache, downloaded again on install"),
        .init(label: "Yarn Berry", rel: ".yarn/berry/cache", sev: .safe, method: .trash, note: "Yarn Berry global cache"),
        .init(label: "Go build cache", rel: "Library/Caches/go-build", sev: .safe, method: .trash, note: "Go build cache"),
        .init(label: "Gradle wrapper dists", rel: ".gradle/wrapper/dists", sev: .review, method: .trash, note: "Downloaded Gradle versions, downloaded again when a project needs them"),
        .init(label: "CocoaPods cache", rel: "Library/Caches/CocoaPods", sev: .safe, method: .trash, note: "CocoaPods download cache"),
        .init(label: "pip cache", rel: "Library/Caches/pip", sev: .safe, method: .trash, note: "pip wheel cache"),
        .init(label: "uv cache", rel: ".cache/uv", sev: .safe, method: .trash, note: "uv package cache"),
        .init(label: "Conda packages (Miniconda)", rel: "miniconda3/pkgs", sev: .review, method: condaClean, note: condaNote),
        .init(label: "Conda packages (Anaconda)", rel: "anaconda3/pkgs", sev: .review, method: condaClean, note: condaNote),
        .init(label: "Conda packages (Miniforge)", rel: "miniforge3/pkgs", sev: .review, method: condaClean, note: condaNote),
        .init(label: "Conda packages", rel: ".conda/pkgs", sev: .review, method: condaClean, note: condaNote),
        .init(label: "Dart and Flutter packages", rel: ".pub-cache", sev: .review, method: .trash, note: "Downloaded again on the next pub get"),
        .init(label: "NuGet packages", rel: ".nuget/packages", sev: .review, method: .trash, note: ".NET packages, restored on the next build"),
        .init(label: "Bun cache", rel: ".bun/install/cache", sev: .safe, method: .trash, note: "Bun install cache"),
        .init(label: "Deno cache", rel: "Library/Caches/deno", sev: .review, method: .trash, note: "Deno module cache"),
        .init(label: "SwiftPM cache", rel: "Library/Caches/org.swift.swiftpm", sev: .safe, method: .trash, note: "SwiftPM downloads, restored by package resolve"),
        .init(label: "ccache", rel: ".cache/ccache", sev: .safe, method: .trash, note: "C/C++ compiler cache"),
        .init(label: "ccache (Library)", rel: "Library/Caches/ccache", sev: .safe, method: .trash, note: "C/C++ compiler cache"),
        .init(label: "Poetry cache", rel: "Library/Caches/pypoetry", sev: .safe, method: .trash, note: "Poetry cache"),
        .init(label: "Composer cache", rel: ".composer/cache", sev: .safe, method: .trash, note: "PHP Composer cache"),
        .init(label: "Cargo git db", rel: ".cargo/git/db", sev: .safe, method: .trash, note: "Cargo git dependency cache"),
        .init(label: "Carthage cache", rel: "Library/Caches/org.carthage.CarthageKit", sev: .safe, method: .trash, note: "Rebuilt on carthage bootstrap"),
        .init(label: "Ivy cache", rel: ".ivy2/cache", sev: .review, method: .trash, note: "Ivy dependency cache"),
        .init(label: "npm logs", rel: ".npm/_logs", sev: .safe, method: .trash, note: "npm install logs"),
    ]

    func scan(_ ctx: ScanContext) async {
        // Many package caches contain hundreds of thousands of tiny files. A
        // per-cache limit alone still allows the whole category to run for minutes.
        let deadline = ProcessInfo.processInfo.systemUptime + timeLimit
        // Only caches that exist take a measuring slot.
        let present: [(target: Target, url: URL)] = Self.targets.compactMap { target in
            let url = home.appendingPathComponent(target.rel)
            guard SafePaths.protectedSessionReason(url) == nil, FileScan.exists(url) else { return nil }
            return (target: target, url: url)
        }

        // A sliding window: a new cache starts the moment one finishes, and
        // nothing starts once the time limit has passed.
        let started = await withTaskGroup(of: ScanItem?.self, returning: Int.self) { group in
            var next = 0
            var active = 0
            while true {
                if ctx.isCancelled() { group.cancelAll(); return next }
                while active < Self.parallel && next < present.count {
                    let remaining = deadline - ProcessInfo.processInfo.systemUptime
                    if remaining <= 0.05 { break }
                    let (target, url) = present[next]
                    next += 1
                    active += 1
                    ctx.progress(target.label)
                    let limit = min(perCacheLimit, remaining)
                    group.addTask { measureTarget(target, at: url, ctx: ctx, maxDuration: limit) }
                }
                if active == 0 { return next }
                guard let result = await group.next() else { return next }
                active -= 1
                if let item = result { ctx.emit(item) }
            }
        }
        if ctx.isCancelled() || started >= present.count { return }

        // Every cache the limit skipped gets its own row, so none silently
        // drops off the list.
        let skipped = present[started...]
        ctx.progress("Developer cache time limit reached; \(skipped.count) not measured")
        for (target, url) in skipped {
            ctx.emit(ScanItem(
                url: url, allocatedSize: 0, categoryID: info.id,
                severity: .review, isRegenerable: false,
                cleanMethod: .adviceOnly,
                note: "\(target.label) — Not measured. The scan reached its \(Int(timeLimit))-second limit for developer caches first. Scan again to measure it.",
                selected: false
            ))
        }
    }

    private func measureTarget(_ target: Target, at url: URL, ctx: ScanContext,
                               maxDuration: TimeInterval) -> ScanItem? {
        let stats = FileScan.measure(url, maxDuration: maxDuration, largeTree: true,
                                     separateSharedLinks: target.kind == .pnpmStore)
        if ctx.isCancelled() || stats.cancelled { return nil }
        // A timed-out tree may have exceeded the floor even when its measured
        // prefix did not. Show the lower bound rather than silently hiding it.
        if stats.allocatedSize < ctx.minSizeBytes && !stats.truncated { return nil }

        let partial = stats.truncated || stats.permissionDenied
        var severity = target.sev
        var note = target.note
        var quitFirst: [String] = []
        switch target.kind {
        case .plain:
            break
        case .gradleCaches:
            quitFirst = Self.gradleApps
            let quiet = Self.gradleIsQuiet(latestModified: stats.latestModified)
            // One click only when the whole cache was read, so the last-used
            // time is known, and Gradle has not touched it for a day.
            if quiet && !partial {
                severity = .safe
                note += ". Gradle has not used it for a day and downloads what it needs on the next build"
            } else if !quiet {
                note += ". Gradle used it in the last day, so it is left for you to check"
            }
        case .pnpmStore:
            if stats.sharedLinkBytes > 0 {
                note += ". Another \(Fmt.size(stats.sharedLinkBytes)) is shared with your projects, stays, and is not counted"
            }
        }
        note = "\(target.label) — \(note)" + (partial ? " · Partial size (lower bound)" : "")
        return ScanItem(
            url: url,
            allocatedSize: stats.allocatedSize,
            itemCount: stats.fileCount,
            latestModified: stats.latestModified,
            categoryID: info.id,
            severity: severity,
            isRegenerable: true,
            requiresQuitBundleIDs: quitFirst,
            cleanMethod: target.method,
            note: note,
            permissionDenied: stats.permissionDenied,
            volumeURL: FileScan.volumeURL(of: url),
            selected: severity == .safe && !stats.permissionDenied
        )
    }

    /// True when the newest file in the Gradle cache is at least a day old.
    static func gradleIsQuiet(latestModified: Date, now: Date = Date()) -> Bool {
        latestModified > .distantPast && now.timeIntervalSince(latestModified) >= gradleQuietSeconds
    }
}
