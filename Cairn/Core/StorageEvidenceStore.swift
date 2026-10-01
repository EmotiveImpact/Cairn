import Foundation
import CSQLite

struct StorageEvidenceSnapshot: Sendable {
    var sequence: UInt64 = 0
    var capacity: [CapacityReading] = []
    var candidates: [CandidateReading] = []
    var locations: [LocationReading] = []
}

/// Serialized disk work stays off the UI actor. Import and each append/prune
/// commit together. Failed imports leave both the old file and transaction intact.
actor StorageEvidenceStore {
    struct StoreError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    struct LegacyArchive: Codable {
        var version: Int
        var capacity: [CapacityReading]
        var candidates: [CandidateReading]
    }
    static var directory: URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support"))
            .appendingPathComponent("Cairn", isDirectory: true)
    }
    let url: URL
    let legacyURL: URL
    private var db: OpaquePointer?
    private var ready = false
    private var sequence: UInt64 = 0
    private let now: @Sendable () -> Date
    private let failure: @Sendable (String) throws -> Void
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL = directory.appendingPathComponent("storage-evidence-v2.sqlite"),
         legacyURL: URL = directory.appendingPathComponent("storage-control-v1.json"),
         now: @escaping @Sendable () -> Date = { Date() },
         failure: @escaping @Sendable (String) throws -> Void = { _ in }) {
        self.url = url; self.legacyURL = legacyURL; self.now = now; self.failure = failure
    }
    deinit { if let db { sqlite3_close(db) } }

    private func checked(_ result: Int32) throws {
        guard result == SQLITE_OK || result == SQLITE_DONE || result == SQLITE_ROW else {
            throw StoreError(message: "Storage history database error (\(result)). The existing records are preserved.")
        }
    }
    private func execute(_ sql: String) throws { try checked(sqlite3_exec(db, sql, nil, nil, nil)) }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        try checked(sqlite3_prepare_v2(db, sql, -1, &stmt, nil))
        guard let stmt else { throw StoreError(message: "Storage history statement unavailable.") }
        return stmt
    }
    private func value(_ sql: String) throws -> Int {
        let stmt = try statement(sql); defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw StoreError(message: "Storage history metadata is unavailable.") }
        return Int(sqlite3_column_int(stmt, 0))
    }
    private func transaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try operation(); try failure("before-commit"); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }
    private func prepare() throws {
        guard !ready else { return }
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        // Reject a redirected or unexpectedly large store before SQLite opens it.
        if fm.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true, (values.fileSize ?? 0) <= 20 * 1024 * 1024 else {
                throw StoreError(message: "Storage history needs review; its file was preserved.")
            }
        }
        if db == nil {
            try checked(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil))
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        sqlite3_busy_timeout(db, 1_000)
        try execute("PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; PRAGMA cache_size=-512; PRAGMA max_page_count=4096; PRAGMA trusted_schema=OFF")
        let version = try value("PRAGMA user_version")
        guard version == 0 || version == 2 else { throw StoreError(message: "Storage history comes from a newer version. Writes are paused.") }
        try transaction {
            try execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value INTEGER NOT NULL)")
            for table in ["capacity", "candidates", "locations"] {
                try execute("CREATE TABLE IF NOT EXISTS \(table) (id TEXT PRIMARY KEY, time REAL NOT NULL, root TEXT NOT NULL, payload BLOB NOT NULL)")
                try execute("CREATE INDEX IF NOT EXISTS \(table)_time ON \(table)(time)")
            }
            try execute("PRAGMA user_version=2")
            let imported = try value("SELECT COUNT(*) FROM meta WHERE key='imported-v1'")
            if imported == 0 {
                if fm.fileExists(atPath: legacyURL.path) {
                    let info = try legacyURL.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
                    guard info.isSymbolicLink != true, (info.fileSize ?? Int.max) <= 2 * 1024 * 1024 else {
                        throw StoreError(message: "Earlier storage history is too large or redirected. Import is paused.")
                    }
                    let data = try Data(contentsOf: legacyURL, options: .mappedIfSafe)
                    guard data.count <= 2 * 1024 * 1024 else { throw StoreError(message: "Earlier storage history grew during import.") }
                    let old = try JSONDecoder().decode(LegacyArchive.self, from: data)
                    guard old.version == 1, old.capacity.count <= 2_300, old.candidates.count <= 32 else {
                        throw StoreError(message: "Earlier storage history format is unsupported.")
                    }
                    for reading in old.capacity { try put(reading) }
                    for reading in old.candidates { try put(reading) }
                    try failure("after-import")
                }
                try execute("INSERT INTO meta VALUES ('imported-v1',1)")
            }
            try prune()
        }
        ready = true
    }
    private func insert<T: Encodable>(_ object: T, id: UUID, date: Date, root: String, table: String) throws {
        let data = try JSONEncoder().encode(object)
        guard data.count <= 128 * 1024, date.timeIntervalSince1970.isFinite else {
            throw StoreError(message: "Storage observation exceeds its size budget.")
        }
        let stmt = try statement("INSERT OR IGNORE INTO \(table) VALUES (?,?,?,?)")
        defer { sqlite3_finalize(stmt) }
        try checked(sqlite3_bind_text(stmt, 1, id.uuidString, -1, transient))
        try checked(sqlite3_bind_double(stmt, 2, date.timeIntervalSince1970))
        try checked(sqlite3_bind_text(stmt, 3, root, -1, transient))
        try data.withUnsafeBytes { raw in try checked(sqlite3_bind_blob(stmt, 4, raw.baseAddress, Int32(raw.count), transient)) }
        try checked(sqlite3_step(stmt))
    }
    private func put(_ reading: CapacityReading) throws {
        guard reading.available >= 0, reading.total > 0, !reading.volumeID.isEmpty else { throw StoreError(message: "Invalid capacity observation.") }
        try insert(reading, id: reading.id, date: reading.date, root: reading.volumeID, table: "capacity")
    }
    private func put(_ reading: CandidateReading) throws {
        guard !reading.volumeID.isEmpty, reading.categories.count <= 64,
              Set(reading.categories.map(\.id)).count == reading.categories.count,
              reading.categories.allSatisfy({ $0.bytes >= 0 }) else { throw StoreError(message: "Invalid candidate observation.") }
        try insert(reading, id: reading.id, date: reading.date, root: reading.volumeID, table: "candidates")
    }
    private func put(_ reading: LocationReading) throws {
        guard reading.valid else { throw StoreError(message: "Invalid location observation.") }
        try insert(reading, id: reading.id, date: reading.ended, root: reading.root.id, table: "locations")
    }
    private func prune() throws {
        let oldest = now().addingTimeInterval(-90 * 86_400).timeIntervalSince1970
        let fine = now().addingTimeInterval(-7 * 86_400).timeIntervalSince1970
        for table in ["capacity", "candidates", "locations"] {
            try execute("DELETE FROM \(table) WHERE time < \(oldest)")
        }
        try execute("DELETE FROM capacity WHERE time < \(fine) AND id NOT IN (SELECT id FROM capacity WHERE time < \(fine) GROUP BY root, CAST(time/86400 AS INTEGER) HAVING time=MAX(time))")
        for (table, cap) in [("capacity", 2_300), ("candidates", 32), ("locations", 1_024)] {
            try execute("DELETE FROM \(table) WHERE id NOT IN (SELECT id FROM \(table) ORDER BY time DESC LIMIT \(cap))")
        }
    }
    private func read<T: Decodable>(_ type: T.Type, table: String, limit: Int) throws -> [T] {
        let stmt = try statement("SELECT payload FROM \(table) ORDER BY time DESC LIMIT \(limit)")
        defer { sqlite3_finalize(stmt) }
        var output: [T] = []
        while true {
            let code = sqlite3_step(stmt)
            if code == SQLITE_DONE { break }
            try checked(code)
            let count = Int(sqlite3_column_bytes(stmt, 0))
            guard count > 0, count <= 128 * 1024, let pointer = sqlite3_column_blob(stmt, 0) else {
                throw StoreError(message: "Storage history contains an invalid record.")
            }
            output.append(try JSONDecoder().decode(type, from: Data(bytes: pointer, count: count)))
        }
        return output.reversed()
    }
    func load() throws -> StorageEvidenceSnapshot {
        try prepare()
        sequence += 1
        let snapshot = StorageEvidenceSnapshot(
            sequence: sequence,
            capacity: try read(CapacityReading.self, table: "capacity", limit: 2_300),
            candidates: try read(CandidateReading.self, table: "candidates", limit: 32),
            locations: try read(LocationReading.self, table: "locations", limit: 1_024))
        guard snapshot.locations.allSatisfy(\.valid),
              snapshot.capacity.allSatisfy({ $0.available >= 0 && $0.total > 0 && !$0.volumeID.isEmpty }),
              snapshot.candidates.allSatisfy({ Set($0.categories.map(\.id)).count == $0.categories.count && $0.categories.allSatisfy { $0.bytes >= 0 } }) else {
            throw StoreError(message: "Storage history contains incompatible evidence. Records were preserved.")
        }
        return snapshot
    }
    func append(capacity: CapacityReading? = nil, candidates: CandidateReading? = nil,
                locations: [LocationReading] = []) throws -> StorageEvidenceSnapshot {
        try prepare()
        try transaction {
            try failure("before-append")
            if let capacity { try put(capacity) }
            if let candidates { try put(candidates) }
            guard locations.count <= 32 else { throw StoreError(message: "Too many locations in one observation.") }
            for location in locations { try put(location) }
            try prune()
        }
        return try load()
    }
}
