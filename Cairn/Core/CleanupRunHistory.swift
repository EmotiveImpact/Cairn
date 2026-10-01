import Foundation
import Darwin

struct CleanupRun: Codable, Identifiable, Sendable {
    let id: UUID
    let started: Date
    var finished: Date?
    var summary: ScanStore.CleanSummary
    var kind: String? = nil
}

/// Durable, bounded receipts, separate from the per-file recovery authority.
/// Never silently discards history to make room for a new cleanup.
actor CleanupRunHistory {
    private let url: URL
    private var runs: [CleanupRun] = []
    private var loaded = false
    private var revision: Data?
    private var sequence: UInt64 = 0
    private var problem: String?
    private let byteLimit = 8 * 1_024 * 1_024
    init(url: URL) { self.url = url }
    private struct Envelope: Codable { let version: Int; let runs: [CleanupRun] }
    private func exists() throws -> Bool {
        var info = stat()
        if lstat(url.path, &info) == 0 { return true }
        if errno == ENOENT { return false }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    private func read() throws -> Data {
        // Open without following a link, then bound the actual read on that
        // descriptor. A preflight file-size check alone races replacement/growth.
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, info.st_size <= byteLimit else { throw CocoaError(.fileReadCorruptFile) }
        let data = try handle.read(upToCount: byteLimit + 1) ?? Data()
        guard data.count <= byteLimit else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }
    func load() -> (runs: [CleanupRun], error: String?, revision: UInt64) {
        if !loaded {
            loaded = true
            do {
                if try exists() {
                    let data = try read()
                    let envelope = try JSONDecoder().decode(Envelope.self, from: data)
                    guard envelope.version == 1, envelope.runs.count <= 512,
                          Set(envelope.runs.map(\.id)).count == envelope.runs.count else { throw CocoaError(.fileReadCorruptFile) }
                    runs = envelope.runs; revision = data
                }
            } catch { problem = "Cleanup receipts could not be read. Existing history was preserved; new cleanup is blocked." }
        }
        return (runs, problem, sequence)
    }
    func save(_ run: CleanupRun) -> String? {
        _ = load()
        guard problem == nil else { return problem }
        do {
            let fm = FileManager.default
            if try exists() {
                guard try read() == revision else { throw CocoaError(.fileWriteFileExists) }
            } else if revision != nil { throw CocoaError(.fileNoSuchFile) }
            var updated = runs
            if let index = updated.firstIndex(where: { $0.id == run.id }) { updated[index] = run }
            else { updated.insert(run, at: 0) }
            guard updated.count <= 512 else { throw CocoaError(.fileWriteOutOfSpace) }
            let data = try JSONEncoder().encode(Envelope(version: 1, runs: updated))
            guard data.count <= byteLimit else { throw CocoaError(.fileWriteOutOfSpace) }
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // The temporary file is private before its atomic replacement.
            let temporary = url.deletingLastPathComponent().appendingPathComponent(".receipt-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: temporary) }
            guard fm.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.synchronize(); try handle.close()
            guard rename(temporary.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            runs = updated; revision = data; sequence &+= 1
            return nil
        } catch {
            problem = "Cleanup receipt could not be saved. Further cleanup is blocked; existing receipts and recovery records were retained."
            return problem
        }
    }
}

/// Maps specialist outcomes into the same persistent receipt without changing
/// their stricter executors or treating affected sizes as released capacity.
extension ScanStore.CleanSummary {
    static func specialist(history: [ScanStore.RemovalLogEntry], failed: Int, errors: [String],
                           capacity: [CleanupCapacityChange], logged: Bool, interrupted: Bool) -> Self {
        var result = Self(failed: failed, errors: errors, capacityChanges: capacity, interrupted: interrupted)
        for entry in history {
            let trash = entry.trashPath.map { URL(fileURLWithPath: $0) }
            if let trash { result.restorable.append(.init(original: URL(fileURLWithPath: entry.originalPath), trash: trash)) }
            result.accounting.record(.init(movedToTrashURL: trash, bytesAffected: entry.bytes, usedTool: false), recoveryRecorded: logged)
        }
        return result
    }
}
