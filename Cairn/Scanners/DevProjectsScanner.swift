import Foundation

/// Whole-disk hunt for regenerable per-project build artifacts (SPEC §3.3).
/// Walks the user's home and, when enabled, each mounted external volume with
/// `ProjectFinder`: breadth-first, so every folder near the top is looked at
/// before any deep tree, and pruned on match, so a found node_modules, target
/// or build folder is never descended into. The same walk records every
/// project folder it passes, with or without build output, for the Projects
/// page.
///
/// These artifacts live in plain user-owned project dirs → no Full Disk Access.
struct DevProjectsScanner: CairnScanner {
    let info = CategoryInfo(
        id: "dev-projects",
        title: "Project Build Artifacts",
        subtitle: "node_modules, Rust and Gradle builds, venvs, Pods, SwiftPM .build…",
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

    /// Depth, folder and time limits for the walk.
    var limits = ProjectFinder.Limits()
    /// Cap on matched artifacts we size in one scan (sizing is the real cost).
    private let maxCandidates = 1_500
    /// Cap on project folders remembered for the Projects page.
    private let maxProjects = 5_000
    /// Floor size for non-node_modules artifacts (node_modules uses ctx.minSizeBytes).
    private let smallFloor: Int64 = 1 * 1024 * 1024  // 1 MB
    /// Time for one big single build folder (Rust target, SwiftPM .build, game
    /// engine output). A Rust target can pass 8 GB and 100,000 files, so these
    /// lift the file count and get longer than the usual 4 seconds.
    static let bigBuildSeconds: TimeInterval = 10

    // MARK: - Scan

    struct Candidate { let kind: ProjectFinder.Kind; let dir: URL; let parent: URL }

    func scan(_ ctx: ScanContext) async {
        var roots: [URL] = [FileScan.home]
        if ctx.includeExternalVolumes {
            roots.append(contentsOf: Volumes.mountedExternalVolumes())
        }
        roots = roots.filter(FileScan.exists)

        // 1) Fast traversal — collect matched artifacts WITHOUT sizing them,
        //    and every project folder on the way.
        let tCollect = Date()
        ctx.progress("Looking for your projects")
        let (candidates, projects, summary) = collect(roots: roots, isCancelled: { ctx.isCancelled() })
        if ctx.isCancelled() { return }
        FoundProjects.shared.record(.init(folders: projects, summary: summary, date: Date()))
        if let stopped = summary.stoppedEarly {
            ctx.progress("Stopped looking \(stopped); some folders were not looked in")
        }
        debugLog("looked in \(summary.foldersListed) folders, found \(projects.count) projects and \(candidates.count) candidates in \(ms(since: tCollect))ms\(summary.stoppedEarly.map { ", stopped early " + $0 } ?? "")")

        // 2) Size them IN PARALLEL across cores (sizing each tree is the cost —
        //    BUG-014). Each measure is file-capped. Emit as each completes.
        let tSize = Date()
        ctx.progress("Measuring \(candidates.count) project artifacts…")
        let limit = min(3, max(1, ProcessInfo.processInfo.activeProcessorCount / 2))

        // Sliding window, NOT fixed chunks. Artifact sizes are wildly uneven — a
        // 50k-file node_modules next to a 200-file one — and the old code awaited
        // a whole chunk before starting the next, so every core sat idle waiting
        // for that chunk's slowest tree. A new task starts the instant one
        // finishes, which keeps all cores busy for the whole pass.
        await withTaskGroup(of: ScanItem?.self) { group in
            var next = 0
            while next < min(limit, candidates.count) {
                let c = candidates[next]
                group.addTask { evaluate(c.kind, dir: c.dir, parent: c.parent, ctx: ctx) }
                next += 1
            }
            for await item in group {
                if let item { ctx.emit(item) }
                if ctx.isCancelled() { group.cancelAll(); break }
                if next < candidates.count {
                    let c = candidates[next]
                    next += 1
                    group.addTask { evaluate(c.kind, dir: c.dir, parent: c.parent, ctx: ctx) }
                }
            }
        }
        debugLog("sized \(candidates.count) candidates in \(ms(since: tSize))ms")
    }

    private func ms(since: Date) -> Int { Int(Date().timeIntervalSince(since) * 1000) }
    private func debugLog(_ s: String) {
        FileHandle.standardError.write("  [dev-projects] \(s)\n".data(using: .utf8)!)
    }

    /// One walk: matched build output to size, and the project folders passed.
    /// Folders inside a hidden folder (.agents, .vite) or a WordPress site
    /// (its plugins and themes) are not recorded as projects of their own,
    /// but build output in them is still found.
    func collect(roots: [URL], isCancelled: () -> Bool) -> ([Candidate], [URL], ProjectFinder.Summary) {
        var candidates: [Candidate] = []
        var projects: [URL] = []
        var wordPressSites: [String] = []
        let summary = ProjectFinder.walk(roots: roots, limits: limits,
                                         isCancelled: { isCancelled() || candidates.count >= maxCandidates }) { folder in
            let names = folder.names
            let path = folder.url.path
            let insideSite = wordPressSites.contains { path.hasPrefix($0 + "/") }
            if folder.depth > 0, !folder.isHidden, !insideSite, projects.count < maxProjects, ProjectFinder.isProjectFolder(names) {
                projects.append(folder.url)
            }
            // A WordPress site is one project. WordPress's own code never
            // holds build output, so only wp-content and the rest are walked.
            var skipped: Set<String> = []
            if ProjectFinder.isWordPressSite(names) {
                wordPressSites.append(path)
                skipped = ["wp-admin", "wp-includes"]
            }

            let subfolderNames = Set(folder.subfolders.map(\.lastPathComponent))
            var matched = Set<String>()
            // Game-engine and Flutter roots: their build folders have generic
            // names, so the project marker decides (~/Library is never a Unity
            // root, because the walk never enters it).
            for engine in ProjectFinder.engineOutput(names) {
                for sub in engine.folders where subfolderNames.contains(sub) && !matched.contains(sub) {
                    candidates.append(Candidate(kind: engine.kind, dir: folder.url.appendingPathComponent(sub), parent: folder.url))
                    matched.insert(sub)
                }
            }
            for sub in folder.subfolders {
                let name = sub.lastPathComponent
                guard !matched.contains(name), let found = ProjectFinder.match(name, at: sub, siblings: names) else { continue }
                candidates.append(Candidate(kind: found.kind, dir: found.url, parent: folder.url))
                matched.insert(name)   // prune: never descend into matched build output
            }
            skipped.formUnion(matched)
            return skipped.isEmpty ? .all : .skipping(skipped)
        }
        if candidates.count > maxCandidates { candidates = Array(candidates.prefix(maxCandidates)) }
        var result = summary
        if result.stoppedEarly == nil, candidates.count >= maxCandidates {
            result.stoppedEarly = "after finding \(maxCandidates.formatted()) build folders"
        }
        return (candidates, projects, result)
    }

    // MARK: - Per-target evaluation

    /// Days without work on a project before its rebuildable venv counts as
    /// ordinary build output.
    static let idleDays = 30

    /// True when the project's git metadata and manifests (never its build
    /// output) were last touched at least `idleDays` ago. Unknown activity is
    /// treated as active.
    private func isIdle(_ project: URL) -> Bool {
        var cache: [String: URL?] = [:]
        let root = ProjectIndex.repositoryRoot(from: project, stopAt: FileScan.home, cache: &cache) ?? project
        let marks = [ProjectIndex.lastActivity(of: root), ProjectIndex.lastActivity(of: project)].compactMap { $0 }
        guard let last = marks.max() else { return false }
        return Date().timeIntervalSince(last) >= Double(Self.idleDays) * 86_400
    }

    private func evaluate(_ kind: ProjectFinder.Kind, dir: URL, parent: URL, ctx: ScanContext) -> ScanItem? {
        let project = parent.lastPathComponent
        let name = dir.lastPathComponent
        func has(_ file: String) -> Bool { FileScan.exists(parent.appendingPathComponent(file)) }
        /// Build output the tool makes again on its own: safe, and counted in
        /// Home's one-click number.
        /// `big` is for one large build folder (Rust target, SwiftPM .build, game
        /// engine output): no file cap and a longer time limit, so it is fully counted.
        func rebuilt(_ note: String, big: Bool = false) -> ScanItem? {
            makeItem(at: dir, severity: .safe, minSize: smallFloor, isRegenerable: true, cleanMethod: .trash,
                     note: note, selectedIfSafe: true, maxFiles: big ? .max : 50_000,
                     largeTree: big, measureSeconds: big ? Self.bigBuildSeconds : FileScan.defaultMeasureSeconds)
        }
        /// Installed packages: they come back with an install step, but only
        /// the same versions when a lock file pins them, and some projects keep
        /// them in git on purpose, so they always wait for the person.
        func installed(_ note: String, locked: Bool) -> ScanItem? {
            makeItem(at: dir, severity: .review, minSize: smallFloor, isRegenerable: locked, cleanMethod: .trash,
                     note: note, selectedIfSafe: false, maxFiles: 50_000)
        }
        switch kind {
        case .nodeModules:
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

        case .cargoTarget:
            return rebuilt("Rust build output for \(project) — cargo clean", big: true)

        case .venv:
            let cfgInside = FileScan.exists(dir.appendingPathComponent("pyvenv.cfg"))
            let reqSibling = has("requirements.txt")
            let pyprojectSibling = has("pyproject.toml")
            guard cfgInside || reqSibling || pyprojectSibling else { return nil }
            let recreatable = reqSibling || pyprojectSibling
            // A recreatable venv in a project nobody has worked on for a month
            // is ordinary build output. In an active project it stays review,
            // because rebuilding it interrupts current work.
            let idle = recreatable && isIdle(parent)
            let note: String
            if !recreatable {
                note = "Python virtualenv for \(project) — no manifest found; may be the only copy"
            } else if idle {
                note = "Python virtualenv for \(project) — project untouched for \(Self.idleDays)+ days; recreatable from its requirements/pyproject"
            } else {
                note = "Python virtualenv for \(project) — recreatable from its requirements/pyproject"
            }
            return makeItem(
                at: dir,
                severity: idle ? .safe : .review,
                minSize: smallFloor,
                isRegenerable: recreatable,   // only truly regenerable if a manifest exists
                cleanMethod: .trash,
                note: note,
                selectedIfSafe: idle,
                maxFiles: 50_000
            )

        case .pods:
            return rebuilt("CocoaPods install for \(project) — pod install restores")

        case .swiftBuild:
            return rebuilt("SwiftPM build for \(project) — swift build restores", big: true)

        case .webBuild:
            return rebuilt("Web build output (\(name)) for \(project) — your bundler regenerates it")

        case .unity, .unreal, .flutter:
            let engine = kind == .unity ? "Unity" : (kind == .unreal ? "Unreal" : "Flutter")
            return rebuilt("\(engine) build output (\(name)) for \(project) — regenerates on next build", big: true)

        case .mavenTarget:
            return rebuilt("Maven build output for \(project), made again by mvn package")
        case .sbtTarget:
            return rebuilt("sbt build output for \(project), made again on the next build")
        case .gradleBuild:
            return rebuilt("Gradle build output for \(project), made again on the next build")
        case .gradleCache:
            return rebuilt("Gradle project cache for \(project), made again on the next build")
        case .xcodeBuild:
            return rebuilt("Xcode build output (\(name)) for \(project), made again on the next build")
        case .cmakeBuild:
            return rebuilt("CMake build folder (\(name)) for \(project), made again by cmake")
        case .dotnet:
            return rebuilt(".NET build output (\(name)) for \(project), made again by dotnet build")
        case .elixirBuild:
            return rebuilt("Elixir build output for \(project), made again by mix compile")
        case .stackWork:
            return rebuilt("Haskell Stack build output for \(project), made again by stack build")
        case .cabal:
            return rebuilt("Cabal build output for \(project), made again by cabal build")
        case .zig:
            return rebuilt("Zig build output (\(name)) for \(project), made again by zig build")
        case .godot:
            return rebuilt("Godot import cache for \(project), made again when Godot next opens it")
        case .pythonCache:
            return rebuilt("Python tool cache (\(name)) for \(project), made again on the next run")
        case .vercelOutput:
            return rebuilt("Vercel build output for \(project), made again by vercel build. The link to your Vercel project stays")
        case .webCache:
            return rebuilt("Web build cache (\(name)) for \(project), made again on the next build")
        case .carthage:
            return rebuilt("Carthage builds for \(project), made again by carthage build")

        case .elixirDeps:
            let locked = has("mix.lock")
            return installed(locked ? "Elixir packages for \(project), fetched again by mix deps.get"
                                    : "Elixir packages for \(project) with no mix.lock, so the same versions may not come back",
                             locked: locked)
        case .composerVendor:
            let locked = has("composer.lock")
            return installed(locked ? "PHP packages for \(project), installed again by composer install. Check they are not kept in git on purpose"
                                    : "PHP packages for \(project) with no composer.lock, so the same versions may not come back",
                             locked: locked)
        case .bundlerVendor:
            let locked = has("Gemfile.lock")
            return installed(locked ? "Ruby gems for \(project), installed again by bundle install"
                                    : "Ruby gems for \(project) with no Gemfile.lock, so the same versions may not come back",
                             locked: locked)
        case .terraform:
            return installed("Terraform providers and modules for \(project), downloaded again by terraform init",
                             locked: has(".terraform.lock.hcl"))
        }
    }
}
