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
    /// manifests. Nil when Cairn cannot tell.
    static func wakeCommand(for project: URL, cleared: [URL], fileManager: FileManager = .default) -> String? {
        func has(_ name: String) -> Bool { fileManager.fileExists(atPath: project.appendingPathComponent(name).path) }
        let names = Set(cleared.map(\.lastPathComponent))
        var steps: [String] = []
        if names.contains("node_modules") || has("package.json") && names.contains(".next") {
            if has("pnpm-lock.yaml") { steps.append("pnpm install") }
            else if has("yarn.lock") { steps.append("yarn install") }
            else if has("bun.lockb") || has("bun.lock") { steps.append("bun install") }
            else if has("package.json") { steps.append("npm install") }
        }
        if names.contains("Pods"), has("Podfile") { steps.append("pod install") }
        if !names.isDisjoint(with: [".venv", "venv"]) {
            if has("uv.lock") { steps.append("uv sync") }
            else if has("poetry.lock") { steps.append("poetry install") }
            else if has("requirements.txt") {
                let folder = names.contains(".venv") ? ".venv" : "venv"
                steps.append("python3 -m venv \(folder) && \(folder)/bin/pip install -r requirements.txt")
            }
        }
        if names.contains("target"), has("Cargo.toml") { steps.append("cargo build") }
        if names.contains(".build"), has("Package.swift") { steps.append("swift build") }
        if names.contains(".dart_tool"), has("pubspec.yaml") { steps.append("flutter pub get") }
        if names.contains("vendor"), has("go.mod") { steps.append("go mod vendor") }
        if !names.isDisjoint(with: [".gradle", "build"]), has("gradlew") { steps.append("./gradlew build") }
        guard !steps.isEmpty else { return nil }
        return "cd \(CLIInstallPolicy.quoteForShell(project.path)) && " + steps.joined(separator: " && ")
    }
}
