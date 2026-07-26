import Foundation

/// Whole-disk hunt for regenerable per-project build artifacts (SPEC §3.3).
/// Walks the user's home — and, when enabled, each mounted external volume —
/// with a manual `FileManager` enumerator that PRUNES on match: the moment a
/// target directory (node_modules / target / .venv / venv / Pods / .build) is
/// found and emitted, `skipDescendants()` stops recursion so we never descend
/// into nested node_modules or re-walk a matched tree. The walk is depth-bounded
/// and skips hidden/system trees that can never hold a project artifact.
///
/// These artifacts live in plain user-owned project dirs → no Full Disk Access.
struct DevProjectsScanner: CairnScanner {
    let info = CategoryInfo(
        id: "dev-projects",
        title: "Project Build Artifacts",
        subtitle: "node_modules, Rust target, venvs, Pods, SwiftPM .build…",
        systemImage: "folder.fill.badge.gearshape",
        group: .developer,
        requiresFDA: false
    )

    /// Items can be trashed from HOME and from any external volume we walked.
    var allowedRoots: [URL] {
        var roots = [FileScan.home]
        roots.append(contentsOf: Volumes.mountedExternalVolumes())
        return roots
    }

    // MARK: - Tuning

    /// Maximum directory depth (relative to a root) we descend before bailing.
    private let maxDepth = 7
    /// Hard cap on directories listed per root, so the default scan always
    /// finishes fast even on a huge home tree (BUG-014). The dedicated
    /// Dev-Project Explorer (v2) can lift this for a deeper hunt.
    private let maxDirsPerRoot = 40_000
    /// Cap on matched artifacts we size in one scan (sizing is the real cost).
    private let maxCandidates = 800
    /// Floor size for non-node_modules artifacts (node_modules uses ctx.minSizeBytes).
    private let smallFloor: Int64 = 1 * 1024 * 1024  // 1 MB

    /// Directory names that, once matched, are pruned (never descended into).
    private static let targetNames: Set<String> = [
        "node_modules", "target", ".venv", "venv", "Pods", ".build",
        // JS/web build outputs (gated by a package.json sibling in evaluate)
        ".next", ".nuxt", ".output", ".turbo", ".svelte-kit", ".expo", "dist",
    ]

    /// Hidden / system dirs we never descend into (would waste the walk or hit
    /// protected state). `.venv`/`venv` are NOT here — they are matchable targets.
    private static let skipNames: Set<String> = [
        ".git", ".hg", ".svn",
        "Library",                 // caches/state, covered by other scanners (also iCloud Drive lives here)
        "Applications", "Music", "Movies", "Pictures", "Public",  // never hold build artifacts; heavy
        "Photos Library.photoslibrary",
        ".Trash", ".Trashes",
        ".cache", ".npm", ".cargo", ".rustup", ".gradle", ".m2", ".pyenv",
        ".nvm", ".asdf", ".bun", ".deno", ".docker", ".ollama", ".conda",
        ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100", ".TemporaryItems",
        "node_modules-internal",
    ]

    // MARK: - Scan

    private struct Candidate { let target: String; let dir: URL; let parent: URL }

    func scan(_ ctx: ScanContext) async {
        var roots: [URL] = [FileScan.home]
        if ctx.includeExternalVolumes {
            roots.append(contentsOf: Volumes.mountedExternalVolumes())
        }

        // 1) Fast traversal — collect matched artifacts WITHOUT sizing them.
        let tCollect = Date()
        var candidates: [Candidate] = []
        for root in roots {
            if ctx.isCancelled() { return }
            guard FileScan.exists(root) else { continue }
            ctx.progress("Hunting in \(root.lastPathComponent)")
            collect(root: root, ctx: ctx, into: &candidates)
            if candidates.count >= maxCandidates { break }
        }
        if candidates.count > maxCandidates { candidates = Array(candidates.prefix(maxCandidates)) }
        debugLog("collected \(candidates.count) candidates in \(ms(since: tCollect))ms")

        // 2) Size them IN PARALLEL across cores (sizing each tree is the cost —
        //    BUG-014). Each measure is file-capped. Emit as each completes.
        let tSize = Date()
        ctx.progress("Measuring \(candidates.count) project artifacts…")
        let limit = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)

        // Sliding window, NOT fixed chunks. Artifact sizes are wildly uneven — a
        // 50k-file node_modules next to a 200-file one — and the old code awaited
        // a whole chunk before starting the next, so every core sat idle waiting
        // for that chunk's slowest tree. A new task starts the instant one
        // finishes, which keeps all cores busy for the whole pass.
        await withTaskGroup(of: ScanItem?.self) { group in
            var next = 0
            while next < min(limit, candidates.count) {
                let c = candidates[next]
                group.addTask { evaluate(target: c.target, dir: c.dir, parent: c.parent, ctx: ctx) }
                next += 1
            }
            for await item in group {
                if let item { ctx.emit(item) }
                if ctx.isCancelled() { group.cancelAll(); break }
                if next < candidates.count {
                    let c = candidates[next]
                    next += 1
                    group.addTask { evaluate(target: c.target, dir: c.dir, parent: c.parent, ctx: ctx) }
                }
            }
        }
        debugLog("sized \(candidates.count) candidates in \(ms(since: tSize))ms")
    }

    private func ms(since: Date) -> Int { Int(Date().timeIntervalSince(since) * 1000) }
    private func debugLog(_ s: String) {
        FileHandle.standardError.write("  [dev-projects] \(s)\n".data(using: .utf8)!)
    }

    /// Directory-only DFS with prune-on-match, depth bound, and a hard dir cap.
    /// We list each directory's children with `isDirectory` PRE-CACHED, so file
    /// entries are skipped with a cheap cached read (no per-file syscall) — the
    /// fix for BUG-014, where the old recursive enumerator stat'd every file in
    /// the home tree. Sizing is deferred to the parallel pass in `scan`.
    private func collect(root: URL, ctx: ScanContext, into candidates: inout [Candidate]) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        var stack: [(url: URL, depth: Int)] = [(root, 0)]
        var listed = 0

        while let (dir, depth) = stack.popLast() {
            if ctx.isCancelled() { return }
            if candidates.count >= maxCandidates { return }
            listed += 1
            if listed > maxDirsPerRoot {
                ctx.progress("Stopped after \(maxDirsPerRoot) folders — deeper hunt coming to the Explorer")
                return
            }

            guard let children = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: keys,   // pre-caches isDirectory → cheap reads below
                options: []
            ) else { continue }

            // Game-engine / Flutter project roots: capture their (regenerable)
            // build dirs and don't descend into them. Gated by marker siblings so
            // a generic "Library"/"build"/"Saved" folder isn't misread (and ~/Library
            // is never a Unity root, so it stays pruned below).
            let childNames = Set(children.map { $0.lastPathComponent })
            var capturedHere = Set<String>()
            func capture(_ marker: Bool, _ tag: String, _ subdirs: [String]) {
                guard marker else { return }
                for sub in subdirs where childNames.contains(sub) {
                    candidates.append(Candidate(target: tag, dir: dir.appendingPathComponent(sub), parent: dir))
                    capturedHere.insert(sub)
                }
            }
            capture(childNames.contains("Assets") && childNames.contains("ProjectSettings"),
                    "fw-unity", ["Library", "Temp", "Logs", "obj"])
            capture(childNames.contains(where: { $0.hasSuffix(".uproject") }),
                    "fw-unreal", ["Saved", "Intermediate", "DerivedDataCache"])
            capture(childNames.contains("pubspec.yaml"),
                    "fw-flutter", ["build", ".dart_tool"])

            for child in children {
                let rv = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard rv?.isDirectory == true, rv?.isSymbolicLink != true else { continue }

                let name = child.lastPathComponent
                if capturedHere.contains(name) { continue }   // already captured as a framework artifact

                if Self.targetNames.contains(name) {
                    candidates.append(Candidate(target: name, dir: child, parent: dir))
                    continue   // prune — never descend into a matched target
                }
                if Self.skipNames.contains(name) { continue }
                if depth + 1 < maxDepth { stack.append((child, depth + 1)) }
            }
        }
    }

    // MARK: - Per-target evaluation

    private func evaluate(target: String, dir: URL, parent: URL, ctx: ScanContext) -> ScanItem? {
        let project = parent.lastPathComponent
        switch target {
        case "node_modules":
            let r = Regenerability.evaluateNodeModules(projectDir: parent)
            return makeItem(
                at: dir,
                severity: r.severity,
                minSize: ctx.minSizeBytes,
                isRegenerable: r.isRegenerable,
                cleanMethod: .trash,
                note: "node_modules for \(project) — \(r.note)",
                selectedIfSafe: true,
                maxFiles: 50_000
            )

        case "target":
            guard FileScan.exists(parent.appendingPathComponent("Cargo.toml")) else { return nil }
            return makeItem(
                at: dir,
                severity: .safe,
                minSize: smallFloor,
                isRegenerable: true,
                cleanMethod: .trash,
                note: "Rust build output for \(project) — cargo clean",
                selectedIfSafe: true,
                maxFiles: 50_000
            )

        case ".venv", "venv":
            let cfgInside = FileScan.exists(dir.appendingPathComponent("pyvenv.cfg"))
            let reqSibling = FileScan.exists(parent.appendingPathComponent("requirements.txt"))
            let pyprojectSibling = FileScan.exists(parent.appendingPathComponent("pyproject.toml"))
            guard cfgInside || reqSibling || pyprojectSibling else { return nil }
            let recreatable = reqSibling || pyprojectSibling
            return makeItem(
                at: dir,
                severity: .review,
                minSize: smallFloor,
                isRegenerable: recreatable,   // only truly regenerable if a manifest exists
                cleanMethod: .trash,
                note: recreatable
                    ? "Python virtualenv for \(project) — recreatable from its requirements/pyproject"
                    : "Python virtualenv for \(project) — no manifest found; may be the only copy",
                selectedIfSafe: false,
                maxFiles: 50_000
            )

        case "Pods":
            guard FileScan.exists(parent.appendingPathComponent("Podfile")) else { return nil }
            return makeItem(
                at: dir,
                severity: .safe,
                minSize: smallFloor,
                isRegenerable: true,
                cleanMethod: .trash,
                note: "CocoaPods install for \(project) — pod install restores",
                selectedIfSafe: true,
                maxFiles: 50_000
            )

        case ".build":
            guard FileScan.exists(parent.appendingPathComponent("Package.swift")) else { return nil }
            return makeItem(
                at: dir,
                severity: .safe,
                minSize: smallFloor,
                isRegenerable: true,
                cleanMethod: .trash,
                note: "SwiftPM build for \(project) — swift build restores",
                selectedIfSafe: true,
                maxFiles: 50_000
            )

        case ".next", ".nuxt", ".output", ".turbo", ".svelte-kit", ".expo", "dist":
            // JS/web bundler output — only when this really is a JS project.
            guard FileScan.exists(parent.appendingPathComponent("package.json")) else { return nil }
            return makeItem(
                at: dir,
                severity: .safe,
                minSize: smallFloor,
                isRegenerable: true,
                cleanMethod: .trash,
                note: "Web build output (\(target)) for \(project) — your bundler regenerates it",
                selectedIfSafe: true,
                maxFiles: 50_000
            )

        case "fw-unity", "fw-unreal", "fw-flutter":
            let engine = target == "fw-unity" ? "Unity" : (target == "fw-unreal" ? "Unreal" : "Flutter")
            return makeItem(
                at: dir,
                severity: .safe,
                minSize: smallFloor,
                isRegenerable: true,
                cleanMethod: .trash,
                note: "\(engine) build output (\(dir.lastPathComponent)) for \(project) — regenerates on next build",
                selectedIfSafe: true,
                maxFiles: 50_000
            )

        default:
            return nil
        }
    }
}
