import Foundation

/// Package-manager & build-tool caches — the developer wedge. Ported and
/// extended from the prototype's `dev_caches.py` DEV_TARGETS table (SPEC §3.1).
/// These live in plain user dirs (0700) → no Full Disk Access needed.
struct DevCachesScanner: CairnScanner {
    let info = CategoryInfo(
        id: "dev-caches",
        title: "Developer Caches",
        subtitle: "npm, yarn, pnpm, pip, cargo, go, gradle, Homebrew…",
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
        for t in targets {
            if ctx.isCancelled() { return }
            let url = FileScan.home.appendingPathComponent(t.rel)
            ctx.progress(t.label)
            if let item = makeItem(
                at: url,
                severity: t.sev,
                minSize: ctx.minSizeBytes,
                isRegenerable: true,
                cleanMethod: t.method,
                note: "\(t.label) — \(t.note)",
                selectedIfSafe: true
            ) {
                ctx.emit(item)
            }
        }
    }
}
