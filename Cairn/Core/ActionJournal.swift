import Foundation

/// A small shared, durable intent record for every reviewed filesystem action.
/// A pending record after a crash is *uncertain*: it never authorizes replay.
/// The existing removal log remains the Put Back source; this journal exposes
/// the otherwise invisible gap between a filesystem move and its recovery log.
final class ActionJournal: @unchecked Sendable {
    enum State: String, Codable, Sendable { case pending, succeeded, failed }
    struct Entry: Codable, Identifiable, Sendable {
        let id: UUID
        let date: Date
        let path: String
        let category: String
        var state: State
        var trashPath: String?
        var detail: String?
    }

    static let shared = ActionJournal()
    private let lock = NSLock()
    private let url: URL
    private var entries: [Entry] = []
    private var loaded = false
    private var revision: Data?
    private var problem: String?
    private let maxBytes = 2 * 1_024 * 1_024
    private let maxEntries = 512

    init(url: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        self.url = url ?? base.appendingPathComponent("Cairn", isDirectory: true).appendingPathComponent("action-journal-v1.json")
    }

    var error: String? { lock.lock(); defer { lock.unlock() }; loadLocked(); return problem }
    var recent: [Entry] { lock.lock(); defer { lock.unlock() }; loadLocked(); return entries }
    var location: URL { url }

    func prepare() -> Bool {
        lock.lock(); defer { lock.unlock() }
        loadLocked()
        guard problem == nil else { return false }
        if entries.contains(where: { $0.state == .pending }) {
            problem = "An action may have been interrupted. Review the action journal and its original/Trash paths before more cleanup. No action will be replayed."
            return false
        }
        return true
    }

    func begin(path: String, category: String) -> UUID? {
        lock.lock(); defer { lock.unlock() }
        loadLocked()
        guard problem == nil, !entries.contains(where: { $0.state == .pending }) else { return nil }
        if entries.count >= maxEntries {
            entries.removeAll { $0.state != .pending && $0.date < Date().addingTimeInterval(-90 * 86_400) }
            if entries.count >= maxEntries { entries = Array(entries.suffix(maxEntries - 1)) }
        }
        let id = UUID()
        entries.append(Entry(id: id, date: Date(), path: path, category: category, state: .pending))
        guard saveLocked() else { return nil }
        return id
    }

    /// Persist the outcome before the caller advertises completion. If this
    /// write fails, the on-disk pending record remains the conservative truth.
    func finish(_ id: UUID, succeeded: Bool, trashPath: String?, detail: String? = nil) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard problem == nil, let index = entries.firstIndex(where: { $0.id == id && $0.state == .pending }) else { return false }
        entries[index].state = succeeded ? .succeeded : .failed
        entries[index].trashPath = trashPath
        entries[index].detail = detail.map { String($0.prefix(240)) }
        return saveLocked()
    }

    private func loadLocked() {
        guard !loaded else { return }
        loaded = true
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= maxBytes else { throw CocoaError(.fileReadTooLarge) }
            let data = try Data(contentsOf: url)
            guard data.count <= maxBytes else { throw CocoaError(.fileReadTooLarge) }
            let archive = try JSONDecoder().decode(Archive.self, from: data)
            guard archive.version == 1, archive.entries.count <= maxEntries,
                  Set(archive.entries.map(\.id)).count == archive.entries.count else { throw CocoaError(.fileReadCorruptFile) }
            entries = archive.entries
            revision = data
        } catch {
            problem = "Action journal could not be read. Its file was preserved and further cleanup is blocked."
        }
    }

    private struct Archive: Codable { let version: Int; let entries: [Entry] }

    private func saveLocked() -> Bool {
        guard problem == nil else { return false }
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path) {
                guard let revision, try Data(contentsOf: url) == revision else { throw CocoaError(.fileWriteFileExists) }
            } else if revision != nil { throw CocoaError(.fileNoSuchFile) }
            let data = try JSONEncoder().encode(Archive(version: 1, entries: entries))
            guard data.count <= maxBytes else { throw CocoaError(.fileWriteOutOfSpace) }
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            revision = data
            return true
        } catch {
            problem = "Action journal could not be saved. Further cleanup is blocked; the existing file and in-memory outcome were preserved."
            return false
        }
    }
}
