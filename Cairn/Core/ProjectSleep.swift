import Foundation

/// A project put to sleep: its rebuildable output was cleared through the
/// normal review and clean, and this note says what was cleared and how to
/// bring it back. Cairn never runs the wake-up command itself, because an
/// install step runs the project's own scripts.
struct SleepingProject: Codable, Identifiable, Equatable, Sendable {
    var path: String
    var name: String
    var asleepSince: Date
    var bytes: Int64
    /// Absolute paths of the folders that were cleared.
    var cleared: [String]
    var wakeCommand: String?
    var id: String { path }
}

enum ProjectSleep {
    static var defaultURL: URL {
        FileScan.home.appendingPathComponent("Library/Application Support/Cairn/sleeping-projects.json")
    }

    /// A note waits this long for its clean before an unfinished one is dropped.
    static let pendingGrace: TimeInterval = 30 * 60

    static func load(from url: URL = defaultURL) -> [SleepingProject] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SleepingProject].self, from: data)) ?? []
    }

    static func save(_ notes: [SleepingProject], to url: URL = defaultURL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(notes) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// A note for the project, written before its review. It only counts as
    /// asleep once the cleared folders are really gone.
    static func note(for project: ProjectSummary, now: Date = Date()) -> SleepingProject {
        let items = project.rebuildable
        return SleepingProject(path: project.url.path, name: project.name, asleepSince: now,
                               bytes: items.reduce(0) { $0 + $1.allocatedSize },
                               cleared: items.map(\.resolvedURL.path),
                               wakeCommand: wakeCommand(for: project.url, cleared: items.map(\.resolvedURL)))
    }

    /// True once every cleared folder has gone and the project itself is still there.
    static func isAsleep(_ note: SleepingProject, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: note.path) && !note.cleared.contains { fileManager.fileExists(atPath: $0) }
    }

    /// Keeps notes for projects that are asleep or still in review. A project
    /// whose folders came back (woken, or its review was cancelled) or that
    /// was moved away no longer needs one.
    static func reconcile(_ notes: [SleepingProject], now: Date = Date(), fileManager: FileManager = .default) -> [SleepingProject] {
        var seen = Set<String>()
        return notes.sorted { $0.asleepSince > $1.asleepSince }.filter { note in
            guard seen.insert(note.path).inserted, fileManager.fileExists(atPath: note.path) else { return false }
            return isAsleep(note, fileManager: fileManager) || now.timeIntervalSince(note.asleepSince) < pendingGrace
        }
    }

    /// Adds or replaces the notes, one per project.
    static func merge(_ new: [SleepingProject], into notes: [SleepingProject]) -> [SleepingProject] {
        let paths = Set(new.map(\.path))
        return new + notes.filter { !paths.contains($0.path) }
    }

    /// The command that rebuilds what was cleared, from the project's own
    /// manifests. Each step runs in the folder that held what it rebuilds, so
    /// an Android app inside an Expo project gets its own Gradle step. Nil
    /// when Cairn cannot tell.
    static func wakeCommand(for project: URL, cleared: [URL], fileManager: FileManager = .default) -> String? {
        let root = project.standardizedFileURL
        var byFolder: [String: Set<String>] = [:]
        var order: [String] = []
        for url in cleared.map(\.standardizedFileURL) {
            var folder = url.deletingLastPathComponent()
            var name = url.lastPathComponent
            // vendor/bundle and Carthage/Build are rebuilt from the folder above.
            if folder.lastPathComponent == "vendor" && name == "bundle" { folder.deleteLastPathComponent(); name = "vendor/bundle" }
            if folder.lastPathComponent == "Carthage" && name == "Build" { folder.deleteLastPathComponent(); name = "Carthage/Build" }
            if folder.lastPathComponent == ".vercel" && name == "output" { folder.deleteLastPathComponent(); name = ".vercel/output" }
            // A package's node_modules is installed from the workspace root
            // that holds the lock file, once for the whole workspace, and a
            // Gradle module is built from the folder that holds gradlew.
            if name == "node_modules", let found = nearest(lockfiles, from: folder, upTo: root, fileManager) { folder = found }
            if name == "build" || name == ".gradle", !fileManager.fileExists(atPath: folder.appendingPathComponent("pubspec.yaml").path),
               let found = nearest(["gradlew"], from: folder, upTo: root, fileManager) { folder = found }
            if byFolder[folder.path] == nil { order.append(folder.path) }
            byFolder[folder.path, default: []].insert(name)
        }
        var steps: [String] = []
        // The project folder first, then its parts in a stable order.
        for path in order.sorted(by: { ($0 == root.path ? "" : $0) < ($1 == root.path ? "" : $1) }) {
            let folder = URL(fileURLWithPath: path)
            let commands = wakeSteps(in: folder, cleared: byFolder[path] ?? [], fileManager)
            guard !commands.isEmpty else { continue }
            let joined = commands.joined(separator: " && ")
            if path == root.path {
                steps.append(joined)
            } else if path.hasPrefix(root.path + "/") {
                steps.append("(cd \(CLIInstallPolicy.quoteForShell(String(path.dropFirst(root.path.count + 1)))) && \(joined))")
            }
        }
        guard !steps.isEmpty else { return nil }
        return "cd \(CLIInstallPolicy.quoteForShell(project.path)) && " + steps.joined(separator: " && ")
    }

    private static let lockfiles = ["pnpm-lock.yaml", "yarn.lock", "bun.lockb", "bun.lock", "package-lock.json", "npm-shrinkwrap.json"]

    /// The nearest folder from `start` up to the project root that holds one
    /// of `files`.
    private static func nearest(_ files: [String], from start: URL, upTo root: URL, _ fm: FileManager) -> URL? {
        var current = start
        for _ in 0..<6 {
            if files.contains(where: { fm.fileExists(atPath: current.appendingPathComponent($0).path) }) { return current }
            if current.path == root.path || !current.path.hasPrefix(root.path + "/") { return nil }
            current.deleteLastPathComponent()
        }
        return nil
    }

    /// The install or build steps for what was cleared from one folder.
    private static func wakeSteps(in folder: URL, cleared names: Set<String>, _ fm: FileManager) -> [String] {
        func has(_ name: String) -> Bool { fm.fileExists(atPath: folder.appendingPathComponent(name).path) }
        func hasFile(endingWith ending: String) -> Bool {
            ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).contains { $0.hasSuffix(ending) }
        }
        func hasScript(_ script: String) -> Bool {
            guard let data = fm.contents(atPath: folder.appendingPathComponent("package.json").path),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let scripts = json["scripts"] as? [String: Any] else { return false }
            return scripts[script] != nil
        }
        var steps: [String] = []
        let runner: String? = has("pnpm-lock.yaml") ? "pnpm" : has("yarn.lock") ? "yarn"
            : (has("bun.lockb") || has("bun.lock")) ? "bun" : (has("package.json") || has("package-lock.json")) ? "npm" : nil
        if let runner, names.contains("node_modules") || has("package.json") && names.contains(".next") {
            steps.append("\(runner) install")
        }
        // Web build output comes back from the project's own build script,
        // or from vercel build, which runs that script and writes its output.
        if names.contains(".vercel/output") {
            steps.append("vercel build")
        } else if let runner, !names.isDisjoint(with: [".next", ".nuxt", ".output", ".svelte-kit", "dist", "build"]),
                  hasScript("build") {
            steps.append("\(runner) run build")
        }
        if names.contains("Pods"), has("Podfile") { steps.append("pod install") }
        if !names.isDisjoint(with: [".venv", "venv"]) {
            if has("uv.lock") { steps.append("uv sync") }
            else if has("poetry.lock") { steps.append("poetry install") }
            else if has("requirements.txt") {
                let venv = names.contains(".venv") ? ".venv" : "venv"
                steps.append("python3 -m venv \(venv) && \(venv)/bin/pip install -r requirements.txt")
            }
        }
        if names.contains("target") {
            if has("Cargo.toml") { steps.append("cargo build") }
            else if has("pom.xml") { steps.append(has("mvnw") ? "./mvnw package" : "mvn package") }
            else if has("build.sbt") { steps.append("sbt compile") }
        }
        if names.contains(".build"), has("Package.swift") { steps.append("swift build") }
        if names.contains(".dart_tool"), has("pubspec.yaml") { steps.append("flutter pub get") }
        if names.contains("vendor") {
            if has("go.mod") { steps.append("go mod vendor") }
            else if has("composer.json") { steps.append("composer install") }
        }
        if names.contains("vendor/bundle"), has("Gemfile") { steps.append("bundle install") }
        if !names.isDisjoint(with: [".gradle", "build"]), has("gradlew") { steps.append("./gradlew build") }
        if !names.isDisjoint(with: ["bin", "obj"]), hasFile(endingWith: ".csproj") || hasFile(endingWith: ".fsproj") {
            steps.append("dotnet build")
        }
        if names.contains("deps"), has("mix.exs") { steps.append("mix deps.get") }
        if names.contains("_build"), has("mix.exs") { steps.append("mix compile") }
        if names.contains(".stack-work"), has("stack.yaml") { steps.append("stack build") }
        if names.contains("dist-newstyle") { steps.append("cabal build") }
        if !names.isDisjoint(with: ["zig-cache", ".zig-cache", "zig-out"]), has("build.zig") { steps.append("zig build") }
        if names.contains(".terraform") { steps.append("terraform init") }
        if names.contains("Carthage/Build"), has("Cartfile") { steps.append("carthage build") }
        return steps
    }
}
