import Foundation

/// Git repository maintenance hunt. Walks the user's home with a bounded,
/// directory-only DFS (mirroring DevProjectsScanner's traversal) looking for
/// two things:
///
///   1. Large `.git` directories (>= 200 MB) — advice only. Git objects can be
///      recovery data, so Cairn never runs garbage collection for the user.
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

                // 1) Large .git → inspect manually, never automatic maintenance.
                if let gitDir = dotGitDir {
                    ctx.progress("Sizing .git in \(dir.lastPathComponent)")
                    let stats = FileScan.measure(gitDir, maxFiles: gitMaxFiles)
                    if stats.allocatedSize >= gitBloatFloor {
                        let project = dir.lastPathComponent
                        var note = "Large .git for \(project) (\(Fmt.size(stats.allocatedSize))) — inspect with Git before changing it; unreachable objects may be recovery data"
                        if stats.truncated { note += " · large (partial size)" }
                        let item = ScanItem(
                            url: gitDir,
                            allocatedSize: stats.allocatedSize,
                            itemCount: stats.fileCount,
                            latestModified: stats.latestModified,
                            categoryID: info.id,
                            severity: .review,
                            isRegenerable: false,
                            requiresQuitBundleIDs: [],
                            requiresRunning: false,
                            cleanMethod: .adviceOnly,
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
