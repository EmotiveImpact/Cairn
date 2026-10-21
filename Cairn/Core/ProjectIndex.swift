import Foundation

/// One repository (or project folder) and the build output a scan found in it.
/// Built from existing `dev-projects` scan items; it never walks the disk for
/// candidates itself and never makes anything actionable that the scanner and
/// executor did not already allow.
struct ProjectSummary: Identifiable {
    let url: URL
    let items: [ScanItem]
    let isRepository: Bool
    /// Most recent of the repository's git metadata and manifest timestamps.
    /// Build output is excluded, because a background tool can touch it.
    let lastActivity: Date?

    var id: String { url.path }
    var name: String { url.lastPathComponent }

    /// Items the executor can act on and the scanner judged rebuildable.
    var rebuildable: [ScanItem] {
        items.filter { $0.isActionable && $0.isRegenerable && $0.severity != .risky }
    }
    var rebuildableBytes: Int64 { rebuildable.reduce(0) { $0 + $1.allocatedSize } }
    var measuredBytes: Int64 { items.reduce(0) { $0 + $1.allocatedSize } }

    func idleDays(now: Date = Date()) -> Int? {
        lastActivity.map { max(0, Int(now.timeIntervalSince($0) / 86_400)) }
    }
}

enum ProjectIndex {
    static let categoryID = "dev-projects"

    /// Files whose timestamps show recent work on a project. Reading a handful
    /// of `stat` results is cheap and never hydrates cloud placeholders.
    private static let activityMarkers = [
        ".git/index", ".git/HEAD", ".git/FETCH_HEAD", ".git/logs/HEAD",
        "package.json", "Package.swift", "Cargo.toml", "pyproject.toml",
        "requirements.txt", "Podfile", "pubspec.yaml", "go.mod", "build.gradle",
    ]

    /// Groups scan items by the nearest enclosing repository, so a monorepo's
    /// packages appear as one project. Without a repository the artifact's
    /// parent folder is the project.
    static func build(from items: [ScanItem], stopAt home: URL = FileScan.home) -> [ProjectSummary] {
        var rootCache: [String: URL?] = [:]
        var groups: [String: (url: URL, repo: Bool, items: [ScanItem])] = [:]
        for item in items where item.categoryID == categoryID {
            let parent = item.url.deletingLastPathComponent().standardizedFileURL
            let repo = repositoryRoot(from: parent, stopAt: home, cache: &rootCache)
            let root = repo ?? parent
            groups[root.path, default: (root, repo != nil, [])].items.append(item)
        }
        return groups.values.map { group in
            ProjectSummary(url: group.url,
                           items: group.items.sorted { $0.allocatedSize > $1.allocatedSize },
                           isRepository: group.repo,
                           lastActivity: lastActivity(of: group.url))
        }
    }

    /// Walks upwards a bounded number of levels looking for `.git`. A `.git`
    /// file (worktree or submodule) counts as well as a directory.
    static func repositoryRoot(from start: URL, stopAt home: URL, cache: inout [String: URL?]) -> URL? {
        var visited: [String] = []
        var current = start
        var result: URL?
        for _ in 0..<8 {
            if let cached = cache[current.path] { result = cached; break }
            visited.append(current.path)
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(".git").path) {
                result = current
                break
            }
            if current.path == home.standardizedFileURL.path || current.path == "/" { break }
            current = current.deletingLastPathComponent()
        }
        for path in visited { cache[path] = result }
        return result
    }

    static func lastActivity(of project: URL) -> Date? {
        activityMarkers.compactMap { marker in
            (try? FileManager.default.attributesOfItem(atPath: project.appendingPathComponent(marker).path))?[.modificationDate] as? Date
        }.max()
    }
}
