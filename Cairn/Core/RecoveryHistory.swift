import Foundation

/// One owner for recovery metadata. All decoding, conflict checks and atomic
/// writes occur away from the UI; callers receive versioned display snapshots.
actor RecoveryHistory {
    typealias Entry = ScanStore.RemovalLogEntry
    struct Snapshot: Sendable {
        let revision: UInt64
        let entries: [Entry]
        let error: String?
        var acknowledged: Set<UUID> = []
    }
    private let url: URL
    private let limit = 20 * 1024 * 1024
    private var entries: [Entry] = []
    private var diskRevision: Data?
    private var problem: String?
    private var loaded = false
    private var revision: UInt64 = 0
    init(url: URL) { self.url = url }
    private func snapshot(acknowledged: Set<UUID> = []) -> Snapshot {
        revision &+= 1
        return Snapshot(revision: revision, entries: entries, error: problem, acknowledged: acknowledged)
    }
    private func readFile() throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= limit else { throw CocoaError(.fileReadTooLarge) }
        let data = try Data(contentsOf: url)
        guard data.count <= limit else { throw CocoaError(.fileReadTooLarge) }
        return data
    }
    private func ensureLoaded() {
        guard !loaded else { return }; loaded = true
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try readFile()
            let records = try JSONDecoder().decode([Entry].self, from: data)
            guard Set(records.map(\.id)).count == records.count else { throw CocoaError(.fileReadCorruptFile) }
            entries = records; diskRevision = data
        } catch { problem = "Recovery history could not be read. It was preserved; cleanup is blocked until it can be recovered." }
    }
    @discardableResult private func save() -> Bool {
        guard problem == nil else { return false }
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path) {
                guard try readFile() == diskRevision else { throw CocoaError(.fileWriteFileExists) }
            } else if diskRevision != nil { throw CocoaError(.fileNoSuchFile) }
            let data = try JSONEncoder().encode(entries)
            guard data.count <= limit else { throw CocoaError(.fileWriteOutOfSpace) }
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            diskRevision = data
            return true
        } catch {
            problem = "Recovery history could not be saved. Further cleanup is blocked. Existing files and in-memory records are retained."
            return false
        }
    }
    func load() -> Snapshot { ensureLoaded(); return snapshot() }
    func prepare() -> Snapshot { ensureLoaded(); save(); return snapshot() }
    func append(_ incoming: [Entry]) -> Snapshot {
        ensureLoaded()
        guard problem == nil else { return snapshot() }
        let known = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        if incoming.contains(where: { entry in
            guard let existing = known[entry.id] else { return false }
            return existing.originalPath != entry.originalPath || existing.trashPath != entry.trashPath
        }) {
            problem = "Conflicting recovery identities were preserved. Further cleanup is blocked."
            return snapshot()
        }
        var ids = Set(entries.map(\.id))
        let additions = incoming.filter { ids.insert($0.id).inserted }
        entries.insert(contentsOf: additions, at: 0)
        if !additions.isEmpty { save() }
        return snapshot()
    }
    func markRestored(_ id: UUID) -> Snapshot {
        ensureLoaded()
        guard problem == nil, let index = entries.firstIndex(where: { $0.id == id }) else { return snapshot() }
        entries[index].restoredAt = Date()
        save(); return snapshot()
    }
    func reconcile(_ actions: [ActionJournal.Entry]) -> Snapshot {
        ensureLoaded()
        guard problem == nil else { return snapshot() }
        var acknowledged = Set<UUID>(), changed = false
        for action in actions where action.state == .succeeded {
            if action.actionKind == "restore", let related = action.relatedRecoveryID,
               let index = entries.firstIndex(where: { $0.id == related }), action.destinationPath == entries[index].originalPath {
                if entries[index].restoredAt == nil { entries[index].restoredAt = action.date; changed = true }
                acknowledged.insert(action.id); continue
            }
            if let existing = entries.first(where: { $0.id == action.id || ($0.originalPath == action.path && $0.trashPath == action.trashPath) }) {
                if existing.originalPath == action.path && existing.trashPath == action.trashPath { acknowledged.insert(action.id) }
                continue
            }
            guard action.actionKind == "trash", let bytes = action.affectedBytes, bytes >= 0,
                  let trash = action.trashPath, let identity = action.trashIdentity else { continue }
            var entry = Entry(id: action.id, name: URL(fileURLWithPath: action.path).lastPathComponent,
                              originalPath: action.path, trashPath: trash, bytes: bytes, date: action.date, category: action.category)
            entry.trashIdentity = identity; entry.actionKind = "trash"
            entries.insert(entry, at: 0); changed = true; acknowledged.insert(action.id)
        }
        if changed { save() }
        return snapshot(acknowledged: problem == nil ? acknowledged : [])
    }
}
