import Foundation

/// One repository (or project folder) and the build output a scan found in it.
/// Built from existing `dev-projects` scan items and the project folders the
/// same scan walked past; it never walks the disk for candidates itself and
/// never makes anything actionable that the scanner and executor did not
/// already allow. A project with no build output has no items.
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
        "package.json", "Package.swift", "Cargo.toml", "pyproject.toml", "setup.py", "Pipfile",
        "requirements.txt", "Podfile", "pubspec.yaml", "go.mod", "build.gradle", "build.gradle.kts",
        "settings.gradle", "settings.gradle.kts", "pom.xml", "build.sbt", "Gemfile", "composer.json",
        "CMakeLists.txt", "mix.exs", "project.godot", "deno.json", "stack.yaml", "build.zig",
    ]

    /// Folders that group several packages of one project (packages/web).
    private static let containerNames: Set<String> = ["packages", "apps", "modules", "libs", "crates", "services"]
    /// Platform or part folders that belong to the project around them
    /// (android/app, src-tauri, client and server).
    private static let partNames: Set<String> = ["android", "ios", "macos", "windows", "linux", "web", "src-tauri",
                                                 "electron", "app", "frontend", "backend", "client", "server", "api"]
    /// Files that say a folder holds a workspace of several packages.
    private static let workspaceFiles: Set<String> = ["settings.gradle", "settings.gradle.kts", "pnpm-workspace.yaml",
                                                      "lerna.json", "nx.json", "turbo.json", "rush.json", "go.work"]
    /// Manifests that nest inside a parent of the same kind (CMake subfolders,
    /// Gradle and Maven modules, Cargo workspace members).
    private static let nestingManifests: Set<String> = ["CMakeLists.txt", "build.gradle", "build.gradle.kts", "pom.xml", "Cargo.toml"]

    /// Groups scan items, and the project folders the scan passed, by the
    /// nearest enclosing repository, so a monorepo's packages appear as one
    /// project. Without a repository, a folder's project is the top of its run
    /// of project folders (an Android app inside its Expo project). A folder
    /// that holds build output but no project marker stands alone.
    static func build(from items: [ScanItem], roots: [URL] = [], stopAt home: URL = FileScan.home) -> [ProjectSummary] {
        var rootCache: [String: URL?] = [:]
        var topCache: [String: URL?] = [:]
        var groups: [String: (url: URL, repo: Bool, items: [ScanItem])] = [:]
        func project(for folder: URL) -> (URL, Bool)? {
            if let repo = repositoryRoot(from: folder, stopAt: home, cache: &rootCache) { return (repo, true) }
            // A WordPress plugin or theme belongs to its site.
            if let site = wordPressSite(around: folder) { return (site, false) }
            return projectTop(from: folder, stopAt: home, cache: &topCache).map { ($0, false) }
        }
        for item in items where item.categoryID == categoryID {
            var parent = item.url.deletingLastPathComponent().standardizedFileURL
            // vendor/bundle, Carthage/Build and .vercel/output belong to the folder above.
            if (parent.lastPathComponent == "vendor" && item.url.lastPathComponent == "bundle")
                || (parent.lastPathComponent == "Carthage" && item.url.lastPathComponent == "Build")
                || (parent.lastPathComponent == ".vercel" && item.url.lastPathComponent == "output") {
                parent = parent.deletingLastPathComponent()
            }
            let (root, repo) = project(for: parent) ?? (parent, false)
            groups[root.path, default: (root, repo, [])].items.append(item)
        }
        for folder in roots {
            let start = folder.standardizedFileURL
            guard start.path != home.standardizedFileURL.path else { continue }
            let (root, repo) = project(for: start) ?? (start, false)
            if groups[root.path] == nil { groups[root.path] = (root, repo, []) }
        }
        return groups.values.map { group in
            ProjectSummary(url: group.url,
                           items: group.items.sorted { $0.allocatedSize > $1.allocatedSize },
                           isRepository: group.repo,
                           lastActivity: lastActivity(of: group.url))
        }
    }

    /// Walks upwards looking for `.git`, as far as the home folder or the top
    /// of the drive. A `.git` file (worktree or submodule) counts as well as a
    /// directory. The home folder itself is never a project, even when it
    /// holds a `.git` for settings files, or every folder in it would join one
    /// repository.
    static func repositoryRoot(from start: URL, stopAt home: URL, cache: inout [String: URL?]) -> URL? {
        let homePath = home.standardizedFileURL.path
        var visited: [String] = []
        var current = start
        var result: URL?
        // Deeper than the project walk ever goes, so build output at its
        // deepest still finds a repository just below home.
        for _ in 0..<(ProjectFinder.Limits().maxDepth + 6) {
            if current.path == homePath || current.path == "/" { break }
            if let cached = cache[current.path] { result = cached; break }
            visited.append(current.path)
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(".git").path) {
                result = current
                break
            }
            current = current.deletingLastPathComponent()
        }
        for path in visited { cache[path] = result }
        return result
    }

    /// The top of a run of project folders, for folders outside any
    /// repository: android/app climbs to android (a Gradle workspace) and on
    /// to the Expo project around it; packages/web climbs to the workspace.
    /// A project folder that only sits inside another folder with a manifest
    /// stays on its own. Nil when the folder has no project marker.
    static func projectTop(from start: URL, stopAt home: URL, cache: inout [String: URL?]) -> URL? {
        if let cached = cache[start.path] { return cached }
        let homePath = home.standardizedFileURL.path
        var result: URL?
        if let startNames = entries(in: start), ProjectFinder.isProjectFolder(startNames) {
            var top = start
            var topNames = startNames
            for _ in 0..<4 {
                var up = top.deletingLastPathComponent()
                var grouped = false
                if containerNames.contains(up.lastPathComponent) {
                    up = up.deletingLastPathComponent()
                    grouped = true
                }
                guard up.path != homePath, up.pathComponents.count > 2,
                      let upNames = entries(in: up), ProjectFinder.isProjectFolder(upNames) else { break }
                let sameKind = !topNames.intersection(nestingManifests).isDisjoint(with: upNames)
                guard grouped || sameKind || partNames.contains(top.lastPathComponent) || isWorkspace(up, names: upNames) else { break }
                top = up
                topNames = upNames
            }
            result = top
        }
        cache[start.path] = result
        return result
    }

    /// The WordPress site whose wp-content holds this folder, if any.
    static func wordPressSite(around folder: URL) -> URL? {
        let parts = folder.pathComponents
        guard let index = parts.lastIndex(of: "wp-content"), index > 1 else { return nil }
        var site = folder
        for _ in index..<parts.count { site.deleteLastPathComponent() }
        guard let names = entries(in: site), ProjectFinder.isWordPressSite(names) else { return nil }
        return site
    }

    private static func entries(in folder: URL) -> Set<String>? {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)).map { Set($0) }
    }

    /// True when the folder declares several packages of its own.
    private static func isWorkspace(_ folder: URL, names: Set<String>) -> Bool {
        if !names.isDisjoint(with: workspaceFiles) { return true }
        func mentions(_ file: String, _ text: String) -> Bool {
            guard names.contains(file),
                  let handle = try? FileHandle(forReadingFrom: folder.appendingPathComponent(file)) else { return false }
            defer { try? handle.close() }
            let head = (try? handle.read(upToCount: 65_536)) ?? Data()
            return String(decoding: head, as: UTF8.self).contains(text)
        }
        return mentions("package.json", "\"workspaces\"") || mentions("Cargo.toml", "[workspace]")
    }

    static func lastActivity(of project: URL) -> Date? {
        var dates = markerDates(in: project)
        // A WordPress site's own work is in its plugins and themes, so their
        // manifests count too: one level down, never their build output, and
        // never followed further, so a plugin linked back to its site is
        // read once.
        let fm = FileManager.default
        if fm.fileExists(atPath: project.appendingPathComponent("wp-includes").path) {
            let content = project.appendingPathComponent("wp-content")
            for part in ["plugins", "themes"] {
                let folder = content.appendingPathComponent(part)
                for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] {
                    dates += markerDates(in: folder.appendingPathComponent(name))
                }
            }
        }
        return dates.max()
    }

    /// Modification dates of the project files directly in one folder.
    private static func markerDates(in project: URL) -> [Date] {
        let fm = FileManager.default
        var dates = activityMarkers.compactMap { marker in
            (try? fm.attributesOfItem(atPath: project.appendingPathComponent(marker).path))?[.modificationDate] as? Date
        }
        // Xcode, .NET and Unreal projects keep their manifest under its own name.
        for name in (try? fm.contentsOfDirectory(atPath: project.path)) ?? [] {
            let path: String
            if name.hasSuffix(".xcodeproj") { path = project.appendingPathComponent(name).appendingPathComponent("project.pbxproj").path }
            else if name.hasSuffix(".csproj") || name.hasSuffix(".fsproj") || name.hasSuffix(".sln") || name.hasSuffix(".uproject") {
                path = project.appendingPathComponent(name).path
            } else { continue }
            if let date = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date { dates.append(date) }
        }
        return dates
    }
}
