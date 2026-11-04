import Foundation

/// Finds coding projects and the build output inside them, for the project
/// scanner, the git scanner and the Projects page.
///
/// The walk is breadth-first: every folder near the top of the home folder is
/// looked at before any deep tree, so one large tool folder can no longer use
/// up the whole budget before ordinary project folders are reached. Hidden
/// folders directly inside a root (tool, editor and agent state such as
/// ~/.codex, ~/.vscode or ~/.volta), app and library bundles, links and other
/// mounted drives are never walked.
enum ProjectFinder {
    struct Limits: Sendable {
        /// Folders deeper than this below a root are not listed.
        var maxDepth = 10
        /// Cap on folders listed across all roots in one walk.
        var maxFolders = 150_000
        /// Time allowed for the walk itself. Sizing happens afterwards.
        var timeBudget: TimeInterval = 60
    }

    /// One listed folder, as the visitor sees it.
    struct Folder {
        let url: URL
        let depth: Int
        /// Every entry name in the folder, files included, because most
        /// project markers are files.
        let names: Set<String>
        /// Real subfolders the walk may enter: no links, bundles or mount points.
        let subfolders: [URL]
        /// True when this folder or one of its parents below the root is hidden.
        let isHidden: Bool
    }

    /// Which subfolders of a listed folder the walk enters next.
    enum Descend { case all, skipping(Set<String>), skipAll }

    struct Summary: Sendable, Equatable {
        var foldersListed = 0
        var seconds: Double = 0
        /// Plain words when the walk stopped before it finished, otherwise nil.
        var stoppedEarly: String?
    }

    // MARK: - What the walk never enters

    /// Folders directly inside a root that never hold the person's projects.
    static let rootSkips: Set<String> = [
        "Library", "Applications", "Music", "Movies", "Pictures", "Public",
        "System", "private", "usr", "sbin", "cores",
        "micromamba", "miniconda3", "anaconda3", "miniforge3", "mambaforge",
        "Calibre Library", "Parallels", "Virtual Machines.localized", "VirtualBox VMs",
    ]

    /// Never descended into at any depth: version-control internals, package
    /// stores and caches that hold other people's code, never a project.
    static let skipAnywhere: Set<String> = [
        ".git", ".hg", ".svn", ".jj", "node_modules", "node_modules-internal", "__pycache__",
        ".Trash", ".Trashes", ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100", ".TemporaryItems",
        ".cache", ".npm", ".cargo", ".rustup", ".gradle", ".m2", ".pyenv", ".nvm", ".asdf", ".bun",
        ".deno", ".docker", ".ollama", ".conda", ".pnpm-store", ".yarn", ".vite",
        "bower_components", "jspm_packages", "site-packages", "dist-packages",
        "Photos Library.photoslibrary",
    ]

    /// Folder extensions macOS treats as one document or bundle. Lower case.
    static let bundleExtensions: Set<String> = [
        "app", "framework", "xcframework", "bundle", "plugin", "appex", "kext",
        "photoslibrary", "photolibrary", "aplibrary", "musiclibrary", "tvlibrary", "imovielibrary",
        "fcpbundle", "logicx", "band", "pvm", "vmwarevm", "utm", "sparsebundle", "xcarchive",
        "xcassets", "xcodeproj", "xcworkspace", "playground", "docset", "dsym", "noindex", "lproj",
    ]

    static func isBundle(_ name: String) -> Bool {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        return bundleExtensions.contains(name[name.index(after: dot)...].lowercased())
    }

    // MARK: - Walk

    /// Lists folders breadth-first from each root and asks `visit` which
    /// subfolders to enter. Stops at the folder cap or the time budget and
    /// says so in the summary.
    static func walk(roots: [URL], limits: Limits = Limits(), isCancelled: () -> Bool,
                     visit: (Folder) -> Descend) -> Summary {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isVolumeKey]
        let keySet = Set(keys)
        let started = Date()
        var summary = Summary()
        var queue: [(url: URL, depth: Int, hidden: Bool)] = roots.map { ($0.standardizedFileURL, 0, false) }
        var head = 0
        var attempts = 0
        while head < queue.count {
            if isCancelled() { break }
            if summary.foldersListed >= limits.maxFolders {
                summary.stoppedEarly = "after looking in \(limits.maxFolders.formatted()) folders"
                break
            }
            attempts += 1
            if attempts % 256 == 0, Date().timeIntervalSince(started) > limits.timeBudget {
                summary.stoppedEarly = "after \(Int(limits.timeBudget)) seconds"
                break
            }
            let entry = queue[head]
            head += 1
            if head >= 50_000 { queue.removeFirst(head); head = 0 }
            autoreleasepool {
                guard let children = try? fm.contentsOfDirectory(at: entry.url, includingPropertiesForKeys: keys,
                                                                 options: []) else { return }
                summary.foldersListed += 1
                var names = Set<String>()
                var subfolders: [URL] = []
                for child in children {
                    let name = child.lastPathComponent
                    names.insert(name)
                    guard let values = try? child.resourceValues(forKeys: keySet),
                          values.isDirectory == true, values.isSymbolicLink != true, values.isVolume != true else { continue }
                    if entry.depth == 0, name.hasPrefix(".") || rootSkips.contains(name) { continue }
                    if isBundle(name) { continue }
                    subfolders.append(child)
                }
                let decision = visit(Folder(url: entry.url, depth: entry.depth, names: names,
                                            subfolders: subfolders, isHidden: entry.hidden))
                guard entry.depth < limits.maxDepth else { return }
                let skipped: Set<String>
                switch decision {
                case .skipAll: return
                case .all: skipped = []
                case .skipping(let set): skipped = set
                }
                for sub in subfolders {
                    let name = sub.lastPathComponent
                    if skipped.contains(name) || skipAnywhere.contains(name) { continue }
                    queue.append((sub, entry.depth + 1, entry.hidden || name.hasPrefix(".")))
                }
            }
        }
        summary.seconds = Date().timeIntervalSince(started)
        return summary
    }

    // MARK: - What counts as a project

    /// Files whose presence makes a folder a project, beside a `.git`.
    static let manifestNames: Set<String> = [
        "package.json", "Cargo.toml", "pyproject.toml", "requirements.txt", "setup.py", "Pipfile",
        "Package.swift", "go.mod", "pubspec.yaml", "build.gradle", "build.gradle.kts",
        "settings.gradle", "settings.gradle.kts", "pom.xml", "build.sbt", "Gemfile", "composer.json",
        "CMakeLists.txt", "deno.json", "deno.jsonc", "mix.exs", "project.godot", "Podfile",
        "stack.yaml", "cabal.project", "build.zig", "Cartfile", "Project.swift",
    ]
    /// Extensions of project files and folders such as App.xcodeproj. Lower case.
    static let manifestExtensions: Set<String> = ["xcodeproj", "xcworkspace", "csproj", "fsproj", "vbproj", "sln", "uproject", "cabal"]

    static func hasManifestExtension(_ names: Set<String>) -> Bool {
        names.contains { name in
            guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
            return manifestExtensions.contains(name[name.index(after: dot)...].lowercased())
        }
    }

    static func isWordPressSite(_ names: Set<String>) -> Bool {
        names.contains("wp-content") && names.contains("wp-includes")
    }

    /// True for a git repository, a folder with a project manifest, a Unity
    /// project or a WordPress site.
    static func isProjectFolder(_ names: Set<String>) -> Bool {
        if names.contains(".git") || !names.isDisjoint(with: manifestNames) { return true }
        if names.contains("Assets") && names.contains("ProjectSettings") { return true }
        return isWordPressSite(names) || hasManifestExtension(names)
    }

    // MARK: - Build output

    /// A kind of rebuildable build output, matched by folder name and the
    /// manifest beside it, so a folder that only shares the name is entered
    /// like any other folder instead.
    enum Kind: String, Sendable {
        case nodeModules, venv, cargoTarget, mavenTarget, sbtTarget, pods, swiftBuild, webBuild, webCache, vercelOutput
        case unity, unreal, flutter
        case gradleBuild, gradleCache, xcodeBuild, cmakeBuild, dotnet
        case elixirBuild, elixirDeps, stackWork, cabal, zig, godot, pythonCache
        case composerVendor, bundlerVendor, terraform, carthage
    }

    static let pythonManifests: Set<String> = ["pyproject.toml", "setup.py", "setup.cfg", "tox.ini", "noxfile.py",
                                               "requirements.txt", "Pipfile"]

    /// Whole-project captures for game engines and Flutter: their build
    /// folders have generic names, so the project marker decides.
    static func engineOutput(_ names: Set<String>) -> [(kind: Kind, folders: [String])] {
        var found: [(kind: Kind, folders: [String])] = []
        if names.contains("Assets") && names.contains("ProjectSettings") { found.append((.unity, ["Library", "Temp", "Logs", "obj"])) }
        if names.contains(where: { $0.hasSuffix(".uproject") }) { found.append((.unreal, ["Saved", "Intermediate", "DerivedDataCache"])) }
        if names.contains("pubspec.yaml") { found.append((.flutter, ["build", ".dart_tool"])) }
        return found
    }

    /// The build output a subfolder holds, judged by its name and the files
    /// beside it. The URL is the folder to clear, which for vendor/bundle and
    /// Carthage/Build is one level down.
    static func match(_ name: String, at url: URL, siblings: Set<String>) -> (kind: Kind, url: URL)? {
        func has(_ file: String) -> Bool { siblings.contains(file) }
        func hasEnding(_ ending: String) -> Bool { siblings.contains { $0.hasSuffix(ending) } }
        func inside(_ entry: String) -> Bool { FileManager.default.fileExists(atPath: url.appendingPathComponent(entry).path) }
        let gradle = has("build.gradle") || has("build.gradle.kts")
        let xcode = hasEnding(".xcodeproj") || hasEnding(".xcworkspace")
        switch name {
        case "node_modules":
            return (.nodeModules, url)
        case ".venv", "venv":
            return (.venv, url)
        case "target":
            if has("Cargo.toml") { return (.cargoTarget, url) }
            if has("pom.xml") { return (.mavenTarget, url) }
            if has("build.sbt") { return (.sbtTarget, url) }
        case "Pods":
            if has("Podfile") { return (.pods, url) }
        case ".build":
            if has("Package.swift") { return (.swiftBuild, url) }
        case ".next", ".nuxt", ".output", ".turbo", ".svelte-kit", ".expo", "dist":
            if has("package.json") { return (.webBuild, url) }
        case ".parcel-cache", ".angular", "storybook-static", ".docusaurus", ".nx":
            if has("package.json") { return (.webCache, url) }
        case "build":
            // A folder called build can hold source (icons, scripts), so it
            // only counts when its contents look like the tool's own output.
            if gradle, ["tmp", "intermediates", "generated", "classes", "libs", "outputs", "kotlin", "reports"].contains(where: inside) {
                return (.gradleBuild, url)
            }
            if xcode, ["XCBuildData", "Intermediates.noindex", "Products", "Release", "Debug",
                       "Release-iphoneos", "Debug-iphoneos", "Release-iphonesimulator", "Debug-iphonesimulator"].contains(where: inside) {
                return (.xcodeBuild, url)
            }
            if has("CMakeLists.txt"), inside("CMakeCache.txt") { return (.cmakeBuild, url) }
            // Create React App and similar bundlers write an asset manifest.
            if has("package.json"), inside("asset-manifest.json") { return (.webBuild, url) }
        case ".gradle":
            if gradle || has("settings.gradle") || has("settings.gradle.kts") || has("gradlew") { return (.gradleCache, url) }
        case "DerivedData":
            if xcode { return (.xcodeBuild, url) }
        case "bin", "obj":
            if hasEnding(".csproj") || hasEnding(".fsproj") || hasEnding(".vbproj") { return (.dotnet, url) }
        case "_build":
            if has("mix.exs") { return (.elixirBuild, url) }
        case "deps":
            if has("mix.exs") { return (.elixirDeps, url) }
        case ".stack-work":
            if has("stack.yaml") { return (.stackWork, url) }
        case "dist-newstyle":
            if has("cabal.project") || hasEnding(".cabal") { return (.cabal, url) }
        case "zig-cache", ".zig-cache", "zig-out":
            if has("build.zig") { return (.zig, url) }
        case ".godot", ".import":
            if has("project.godot") { return (.godot, url) }
        case ".pytest_cache", ".mypy_cache", ".ruff_cache", ".tox", ".nox":
            if !siblings.isDisjoint(with: pythonManifests) { return (.pythonCache, url) }
        case "vendor":
            if has("composer.json") { return (.composerVendor, url) }
            if has("Gemfile"), inside("bundle") { return (.bundlerVendor, url.appendingPathComponent("bundle")) }
        case ".vercel":
            // Only the build output; project.json beside it links the site.
            if has("package.json") || has("vercel.json"), inside("output") { return (.vercelOutput, url.appendingPathComponent("output")) }
        case ".terraform":
            if hasEnding(".tf") { return (.terraform, url) }
        case "Carthage":
            if has("Cartfile"), inside("Build") { return (.carthage, url.appendingPathComponent("Build")) }
        default:
            if name.hasPrefix("cmake-build-"), has("CMakeLists.txt"), inside("CMakeCache.txt") { return (.cmakeBuild, url) }
        }
        return nil
    }
}

/// The project folders the latest project walk found, for the Projects page,
/// the CLI and agents. Only folder paths are kept, in memory.
final class FoundProjects: @unchecked Sendable {
    struct Search: Sendable {
        var folders: [URL]
        var summary: ProjectFinder.Summary
        var date: Date
    }

    static let shared = FoundProjects()
    private let lock = NSLock()
    private var search: Search?

    func record(_ new: Search) {
        lock.lock(); search = new; lock.unlock()
    }

    var latest: Search? {
        lock.lock(); defer { lock.unlock() }
        return search
    }
}
