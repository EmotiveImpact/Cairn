import Foundation

/// The `~/Library` folders and files that belonged to apps the user removed in
/// Cairn. The uninstaller never trashes support data itself; it records it here
/// so the next scan lists it straight away for review, instead of waiting for
/// the six-month staleness rule that guards unknown leftovers.
enum RemovedAppLeftovers {
    struct Entry: Codable, Equatable {
        var path: String
        var app: String
        var removed: Date
    }

    private static let key = "cairn.removedAppLeftovers.v1"
    /// Bounded so a long history never grows the defaults file without limit.
    private static let limit = 500

    static func record(_ paths: [URL], app: String, defaults: UserDefaults = .standard) {
        guard !paths.isEmpty else { return }
        var entries = load(defaults: defaults)
        let known = Set(entries.map(\.path))
        let now = Date()
        for url in paths where !known.contains(url.path) {
            entries.append(Entry(path: url.path, app: app, removed: now))
        }
        save(Array(entries.suffix(limit)), defaults: defaults)
    }

    /// Entries whose path still exists. Gone paths are dropped from the record.
    static func pending(defaults: UserDefaults = .standard) -> [Entry] {
        let entries = load(defaults: defaults)
        let present = entries.filter { FileManager.default.fileExists(atPath: $0.path) }
        if present.count != entries.count { save(present, defaults: defaults) }
        return present
    }

    private static func load(defaults: UserDefaults) -> [Entry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private static func save(_ entries: [Entry], defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(entries), forKey: key)
    }
}
