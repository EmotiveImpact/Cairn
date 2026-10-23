import Foundation

/// Git repository maintenance hunt. Walks the user's home with a bounded,
/// directory-only DFS (mirroring DevProjectsScanner's traversal) looking for
/// two things:
///
///   1. Large `.git` directories (>= 200 MB) — a `.tool` item running
///      `git gc --prune=now`, which compacts history without losing commits.
///      The item's size is the estimated saving (loose objects and temporary
///      packs), not the whole `.git`, and it is skipped below 50 MB.
///      The `.git` dir is pruned from the walk once matched.
///   2. Abandoned project roots (a dir directly containing `.git`,
///      `package.json`, `Cargo.toml`, or a `*.xcodeproj`/`*.xcworkspace`) whose
///      contents haven't been touched in 180+ days — surfaced as an
///      `.adviceOnly` card suggesting archival. Never descended into further.
///
/// Everything here lives in plain user-owned project dirs → no Full Disk Access.
struct GitMaintenanceScanner: CairnScanner {
    let info = CategoryInfo(
        id: "git-bloat",
        title: "Git Maintenance",
        subtitle: "Bloated .git histories & abandoned project roots",
        systemImage: "arrow.triangle.branch",
        group: .developer,
        requiresFDA: false
    )

    // MARK: - Tuning

    /// Maximum directory depth (relative to a root) we descend before bailing.
    private let maxDepth = 6
    /// Hard cap on directories listed per root, so the scan always finishes fast.
    private let maxDirsPerRoot = 30_000
    /// A `.git` directory must be at least this large to warrant a gc suggestion.
    private let gitBloatFloor: Int64 = 200 * 1024 * 1024  // 200 MB
    /// Files cap when sizing a `.git` tree.
    private let gitMaxFiles = 60_000
    /// A gc suggestion must be expected to free at least this much.
    private let gcSavingFloor: Int64 = 50 * 1024 * 1024  // 50 MB
    /// A project root is "abandoned" if untouched for this many days.
    private let abandonedAfterDays: Double = 180
    /// Cap on abandoned-advice items emitted in one scan.
    private let maxAbandonedAdvice = 40

    /// Hidden / system dirs we never descend into (would waste the walk or hit
    /// protected state). Mirrors the DevProjectsScanner prune set.
    private static let skipNames: Set<String> = [
        ".git", ".hg", ".svn",
        "Library",                 // caches/state (also iCloud Drive lives here)
        "Applications", "Music", "Movies", "Pictures", "Public",  // heavy, never project roots
        "Photos Library.photoslibrary",
        ".Trash", ".Trashes",
        ".cache", ".npm", ".cargo", ".rustup", ".gradle", ".m2", ".pyenv",
        ".nvm", ".asdf", ".bun", ".deno", ".docker", ".ollama", ".conda",
        // Editor extension stores: every extension has a package.json, which
        // would otherwise read as dozens of abandoned projects.
        ".vscode", ".vscode-insiders", ".cursor", ".windsurf", ".antigravity", ".kiro", ".trae",
        ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100", ".TemporaryItems",
        "node_modules", "node_modules-internal",
    ]

    // MARK: - Scan

    func scan(_ ctx: ScanContext) async {
        let roots: [URL] = [FileScan.home]
        var abandonedEmitted = 0

        for root in roots {
            if ctx.isCancelled() { return }
            guard FileScan.exists(root) else { continue }
            ctx.progress("Scanning \(root.lastPathComponent)")
            walk(root: root, ctx: ctx, abandonedEmitted: &abandonedEmitted)
        }
    }

    /// Directory-only DFS with prune-on-match, depth bound, and a hard dir cap.
    /// Children are listed with `isDirectory` PRE-CACHED so non-dir entries are
    /// skipped with cheap cached reads (no per-file syscall). Never follows
    /// symlinks.
    private func walk(root: URL, ctx: ScanContext, abandonedEmitted: inout Int) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        var stack: [(url: URL, depth: Int)] = [(root, 0)]
        var listed = 0

        while let (dir, depth) = stack.popLast() {
            if ctx.isCancelled() { return }
            listed += 1
            if listed > maxDirsPerRoot {
                ctx.progress("Stopped after \(maxDirsPerRoot) folders")
                return
            }

            autoreleasepool {
                guard let children = try? fm.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: keys,   // pre-caches isDirectory → cheap reads below
                    options: []
                ) else { return }

                // Pre-scan children once: collect directory names + the dir subset we
                // may descend into. This lets us detect a project root cheaply.
                var childNames: Set<String> = []
                var subdirs: [URL] = []
                var dotGitDir: URL?
                for child in children {
                    let rv = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    let name = child.lastPathComponent
                    childNames.insert(name)
                    guard rv?.isDirectory == true, rv?.isSymbolicLink != true else { continue }
                    if name == ".git" {
                        dotGitDir = child
                        continue   // never descend into .git
                    }
                    subdirs.append(child)
                }

                // 1) Large .git → git gc, sized by what gc can actually free.
                if let gitDir = dotGitDir {
                    ctx.progress("Sizing .git in \(dir.lastPathComponent)")
                    let stats = FileScan.measure(gitDir, maxFiles: gitMaxFiles)
                    let saving = stats.allocatedSize >= gitBloatFloor ? gcSavingEstimate(gitDir) : 0
                    if saving >= gcSavingFloor {
                        let project = dir.lastPathComponent
                        let kept = max(0, stats.allocatedSize - saving)
                        var note = "Tidying git history for \(project) saves about \(Fmt.size(saving)); no commits are lost. The other \(Fmt.size(kept)) is real history and stays"
                        if stats.truncated { note += " · large (partial size)" }
                        // allocatedSize is the estimated saving, not the .git size:
                        // Home, receipts and the de-duplicator all sum this field.
                        let item = ScanItem(
                            url: gitDir,
                            allocatedSize: saving,
                            itemCount: stats.fileCount,
                            latestModified: stats.latestModified,
                            categoryID: info.id,
                            severity: .review,
                            isRegenerable: false,
                            requiresQuitBundleIDs: [],
                            requiresRunning: false,
                            cleanMethod: .tool(ToolCommand(
                                tool: "git",
                                arguments: ["-C", dir.path, "gc", "--prune=now"],
                                display: "git gc --prune=now"
                            )),
                            note: note,
                            permissionDenied: stats.permissionDenied,
                            volumeURL: FileScan.volumeURL(of: gitDir),
                            selected: false
                        )
                        ctx.emit(item)
                    }
                }

                // 2) Project-root detection.
                let isProjectRoot = isProjectRoot(childNames: childNames)
                if isProjectRoot {
                    if abandonedEmitted < maxAbandonedAdvice,
                       let modified = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                        let ageDays = max(0, Date().timeIntervalSince(modified) / 86_400)
                        if ageDays >= abandonedAfterDays {
                            let name = dir.lastPathComponent
                            let item = ScanItem(
                                url: dir,
                                allocatedSize: 0,
                                itemCount: 0,
                                latestModified: modified,
                                categoryID: info.id,
                                severity: .review,
                                isRegenerable: false,
                                requiresQuitBundleIDs: [],
                                requiresRunning: false,
                                cleanMethod: .adviceOnly,
                                note: "Abandoned project '\(name)' — last touched \(Fmt.age(ageDays)); consider archiving",
                                permissionDenied: false,
                                volumeURL: FileScan.volumeURL(of: dir),
                                selected: false
                            )
                            ctx.emit(item)
                            abandonedEmitted += 1
                        }
                    }
                    // A detected project root is not descended into further: its build
                    // artifacts / nested repos are covered by other scanners.
                    return
                }

                // 3) Otherwise descend into subdirectories (depth-bounded, pruning
                //    hidden/system trees).
                if depth + 1 < maxDepth {
                    for sub in subdirs {
                        let name = sub.lastPathComponent
                        if Self.skipNames.contains(name) { continue }
                        stack.append((sub, depth + 1))
                    }
                }
            }
        }
    }

    /// What `git gc --prune=now` can be expected to free. Packed history is
    /// already compact, so only loose objects and abandoned temporary packs
    /// count. Loose objects are zlib'd one by one; packing them with deltas
    /// typically saves well over half, so half is a conservative estimate.
    /// Temporary pack files left by an interrupted fetch or repack go entirely.
    private func gcSavingEstimate(_ gitDir: URL) -> Int64 {
        let objects = gitDir.appendingPathComponent("objects")
        guard let children = FileScan.children(of: objects) else { return 0 }
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        var loose: Int64 = 0
        for child in children {
            let name = child.lastPathComponent
            guard name.count == 2, name.unicodeScalars.allSatisfy({ hex.contains($0) }) else { continue }
            loose += FileScan.measure(child, maxFiles: gitMaxFiles).allocatedSize
        }
        var garbage: Int64 = 0
        for file in FileScan.children(of: objects.appendingPathComponent("pack")) ?? [] {
            let name = file.lastPathComponent
            guard name.hasPrefix("tmp_") || name.hasPrefix(".tmp-") else { continue }
            garbage += FileScan.measure(file).allocatedSize
        }
        return loose / 2 + garbage
    }

    /// A directory is a project root if it directly contains `.git`,
    /// `package.json`, `Cargo.toml`, or any `*.xcodeproj` / `*.xcworkspace`.
    private func isProjectRoot(childNames: Set<String>) -> Bool {
        if childNames.contains(".git") { return true }
        if childNames.contains("package.json") { return true }
        if childNames.contains("Cargo.toml") { return true }
        for name in childNames {
            if name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") { return true }
        }
        return false
    }
}
