import Foundation
import Observation
import CryptoKit
import Darwin

struct StorageDrive: Identifiable, Sendable {
    var url: URL
    var name: String
    var uuid: String
    var capacity: Int64
    var available: Int64
    var external: Bool
    var writable: Bool
    var encrypted: Bool
    var format: String
    var id: String { uuid.isEmpty ? url.path : uuid }
    var acceptsCopy: Bool { external && writable && encrypted && !uuid.isEmpty && format.lowercased().contains("apfs") }

    static func read(_ url: URL) -> StorageDrive? {
        guard let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeIsInternalKey, .volumeIsLocalKey, .volumeIsReadOnlyKey]),
              let info = Volumes.info(for: url) else { return nil }
        var encrypted = false
        var format = "Unknown"
        // Absolute executable bypasses login-shell discovery. Finite deadline.
        if let output = try? ToolRunner.runExecutable("/usr/sbin/diskutil", ["info", "-plist", url.path], timeout: 4), output.ok,
           let data = output.stdout.data(using: .utf8),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            encrypted = (plist["Encrypted"] as? Bool == true) || (plist["FileVault"] as? Bool == true)
            format = plist["FilesystemType"] as? String ?? "Unknown"
        }
        return StorageDrive(url: url, name: info.name, uuid: values.volumeUUIDString ?? "", capacity: info.totalCapacity, available: info.availableImportant, external: values.volumeIsInternal == false && values.volumeIsLocal == true, writable: values.volumeIsReadOnly == false, encrypted: encrypted, format: format)
    }
    func stillMounted(requiresWritable: Bool = true) -> Bool {
        guard let values = try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.volumeUUIDStringKey, .volumeIsReadOnlyKey]) else { return false }
        return !uuid.isEmpty && values.volumeUUIDString == uuid && (!requiresWritable || values.volumeIsReadOnly == false)
    }
}

struct TransferRecord: Codable, Identifiable, Sendable {
    var id = UUID()
    var date = Date()
    var source: String
    var destination: String
    var volumeID: String
    var status: String
    var detail: String
    var bytes: Int64 = 0
    var digest: String = ""
}

enum ArchiveCopy {
    private static func sameDirectory(_ descriptor: Int32, _ url: URL) -> Bool {
        var opened = stat(), current = stat()
        return fstat(descriptor, &opened) == 0 && lstat(url.path, &current) == 0
            && (current.st_mode & 0o170000) == 0o040000
            && opened.st_dev == current.st_dev && opened.st_ino == current.st_ino
    }
    enum Failure: LocalizedError {
        case rejected(String)
        var errorDescription: String? { if case .rejected(let message) = self { return message }; return nil }
    }
    static let extensions: Set<String> = ["zip", "tar", "gz", "7z", "dmg", "iso", "mp4", "mov", "m4v", "mp3", "wav", "pdf", "png", "jpg", "jpeg"]
    static func validateSource(_ url: URL) throws {
        guard extensions.contains(url.pathExtension.lowercased()),
              url.standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL,
              SafePaths.protectedSessionReason(url) == nil else { throw Failure.rejected("Choose an ordinary archive, exported document or media file. Links and protected locations are excluded.") }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isUbiquitousItemKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, values.isUbiquitousItem != true else { throw Failure.rejected("The source must be a local regular file, not a folder or cloud placeholder.") }
        let path = url.path.lowercased()
        guard !path.contains("/library/"), !path.contains("/library/cloudstorage/"), !path.contains("/.git/"), !path.contains("/.ssh/") else { throw Failure.rejected("Application, cloud and repository metadata are excluded. Export the file first.") }
    }

    /// Content export only. Source is never removed or altered. A fresh private
    /// folder contains any interrupted partial, so it cannot masquerade as done.
    static func copy(source: URL, directory: URL, cancel: CancelBox,
                     destinationValid: @Sendable () -> Bool,
                     progress: @Sendable (Int64) -> Void) throws -> (URL, Int64, String) {
        try validateSource(source)
        guard destinationValid(), !cancel.isCancelled, let before = DupHash.fingerprint(source, shouldCancel: { cancel.isCancelled }) else { throw Failure.rejected("The source changed, could not be read, or the destination is missing.") }
        guard directory == directory.resolvingSymlinksInPath().standardizedFileURL else { throw Failure.rejected("Destination paths cannot contain symbolic links.") }
        let parent = directory.deletingLastPathComponent()
        let parentFD = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parentFD >= 0 else { throw Failure.rejected("The destination is unavailable.") }
        defer { close(parentFD) }
        guard sameDirectory(parentFD, parent), destinationValid(),
              mkdirat(parentFD, directory.lastPathComponent, 0o700) == 0 else {
            throw Failure.rejected("Could not create a new private destination. Existing files were left intact.")
        }
        let directoryFD = openat(parentFD, directory.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directoryFD >= 0 else { throw Failure.rejected("Could not open the destination.") }
        defer { close(directoryFD) }
        let partial = directory.appendingPathComponent(source.lastPathComponent + ".partial")
        let finished = directory.appendingPathComponent(source.lastPathComponent)
        let inputFD = open(source.path, O_RDONLY | O_NOFOLLOW)
        guard inputFD >= 0 else { throw Failure.rejected("Could not open the source.") }
        let input = FileHandle(fileDescriptor: inputFD, closeOnDealloc: true)
        defer { try? input.close() }
        let outputFD = openat(directoryFD, partial.lastPathComponent, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard outputFD >= 0 else { throw Failure.rejected("Could not create a private destination file.") }
        let output = FileHandle(fileDescriptor: outputFD, closeOnDealloc: true)
        defer { try? output.close() }
        var bytes: Int64 = 0
        while true {
            guard !cancel.isCancelled, destinationValid(), sameDirectory(directoryFD, directory) else { throw Failure.rejected("Copy interrupted. The source is intact; an incomplete .partial file may remain on the destination.") }
            let count = try autoreleasepool { () -> Int in
                guard let data = try input.read(upToCount: 1 << 20), !data.isEmpty else { return 0 }
                try output.write(contentsOf: data)
                return data.count
            }
            if count == 0 { break }
            bytes += Int64(count)
            progress(bytes)
        }
        try output.synchronize()
        try output.close()
        guard !cancel.isCancelled, destinationValid(), sameDirectory(directoryFD, directory), DupHash.unchanged(source, since: before),
              let after = DupHash.fingerprint(partial, shouldCancel: { cancel.isCancelled }), after.digest == before.digest,
              after.identity.size == before.identity.size, bytes == before.identity.size else { throw Failure.rejected("Verification failed. The source is intact and the partial copy was not promoted.") }
        guard !cancel.isCancelled, destinationValid(), sameDirectory(directoryFD, directory), DupHash.unchanged(source, since: before),
              renameatx_np(directoryFD, partial.lastPathComponent, directoryFD, finished.lastPathComponent, UInt32(RENAME_EXCL)) == 0 else {
            throw Failure.rejected("The copy could not be completed safely. No existing destination was replaced; the source is intact.")
        }
        guard fsync(directoryFD) == 0, destinationValid(), sameDirectory(directoryFD, directory) else { throw Failure.rejected("The destination disconnected or could not finish syncing. Reconnect and check the recorded copy.") }
        return (finished, bytes, before.digest)
    }

    /// Re-check an existing finished copy. Never promotes a partial or removes
    /// a source, and never requires trusting the status text in the journal.
    static func verify(source: URL, destination: URL, bytes: Int64, digest: String,
                       cancel: CancelBox, destinationValid: @Sendable () -> Bool) throws -> (Int64, String) {
        guard destinationValid(), !cancel.isCancelled,
              destination.standardizedFileURL == destination.resolvingSymlinksInPath().standardizedFileURL,
              !destination.lastPathComponent.hasSuffix(".partial") else { throw Failure.rejected("Reconnect the original drive and select a finished copy.") }
        let expected: (Int64, String)
        var originalFingerprint: DupHash.Fingerprint?
        if !digest.isEmpty {
            expected = (bytes, digest)
        } else {
            try validateSource(source)
            guard let fingerprint = DupHash.fingerprint(source, shouldCancel: { cancel.isCancelled }) else { throw Failure.rejected("The original could not be verified.") }
            originalFingerprint = fingerprint
            expected = (fingerprint.identity.size, fingerprint.digest)
        }
        guard let copied = DupHash.fingerprint(destination, shouldCancel: { cancel.isCancelled }),
              copied.identity.size == expected.0, copied.digest == expected.1,
              !cancel.isCancelled, destinationValid() else { throw Failure.rejected("The copy is missing, changed, incomplete, or its drive disconnected. The source was left intact.") }
        if let originalFingerprint, !DupHash.unchanged(source, since: originalFingerprint) {
            throw Failure.rejected("The original changed during verification. Check the copy again after it has finished changing.")
        }
        return expected
    }
}

@MainActor @Observable final class StorageTransferStore {
    // Keep a damaged or unexpectedly large history from loading unbounded data
    // on the UI actor. Limits stop new exports rather than pruning old records.
    private static let maxJournalBytes = 4 * 1024 * 1024
    private static let maxJournalRecords = 2_048
    private(set) var drives: [StorageDrive] = []
    private(set) var records: [TransferRecord] = []
    private(set) var busy = false
    private(set) var checkingCopy = false
    private(set) var copied: Int64 = 0
    private(set) var message = ""
    private var cancellation: CancelBox?
    private var task: Task<Void, Never>?
    private var refreshing = false
    private var refreshAgain = false
    private let journal: URL
    private var journalError: String?
    private var hasLoaded = false
    private var journalRevision: Data?
    init(journal: URL = FileScan.home.appendingPathComponent("Library/Application Support/Cairn/transfers.json")) { self.journal = journal }

    private static func journalEntryExists(_ url: URL) throws -> Bool {
        var info = stat()
        if lstat(url.path, &info) == 0 { return true } // includes dangling links
        if errno == ENOENT { return false }
        throw ArchiveCopy.Failure.rejected("Transfer history could not be inspected; it was left untouched.")
    }

    private static func readJournal(_ url: URL) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ArchiveCopy.Failure.rejected("Transfer history could not be opened as an ordinary file; it was left untouched.") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & 0o170000) == 0o100000 else {
            throw ArchiveCopy.Failure.rejected("Transfer history is not an ordinary file; it was left untouched.")
        }
        let data = try handle.read(upToCount: maxJournalBytes + 1) ?? Data()
        guard data.count <= maxJournalBytes else {
            throw ArchiveCopy.Failure.rejected("Transfer history is too large to load safely; it was left untouched.")
        }
        return data
    }

    func refresh() async {
        guard !refreshing else { refreshAgain = true; return }
        refreshing = true
        let snapshot = await Task.detached(priority: .utility) {
            let urls = [FileScan.volumeURL(of: FileScan.home)].compactMap { $0 } + Volumes.mountedExternalVolumes()
            return urls.compactMap(StorageDrive.read)
        }.value
        drives = snapshot; refreshing = false
        if refreshAgain { refreshAgain = false; await refresh() }
    }
    func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        do {
            guard try Self.journalEntryExists(journal) else { return }
            let data = try Self.readJournal(journal)
            let decoded = try JSONDecoder().decode([TransferRecord].self, from: data)
            guard decoded.count <= Self.maxJournalRecords else { throw ArchiveCopy.Failure.rejected("Transfer history has too many records; it was left untouched.") }
            guard Set(decoded.map(\.id)).count == decoded.count else { throw ArchiveCopy.Failure.rejected("Duplicate transfer identities") }
            records = decoded
            journalRevision = data
            for i in records.indices where records[i].status == "Copying" {
                records[i].status = "Interrupted"; records[i].detail = "Previous copy did not complete. Source was retained. Inspect the destination before starting a new copy."
            }
        } catch {
            let reason = (error as? ArchiveCopy.Failure)?.localizedDescription
            journalError = "Transfer history could not be read; it will not be overwritten."
                + (reason.map { " \($0)" } ?? "")
            message = journalError!
        }
    }
    private func persist() throws {
        if let journalError { throw ArchiveCopy.Failure.rejected(journalError) }
        if try Self.journalEntryExists(journal) {
            guard try Self.readJournal(journal) == journalRevision else {
                journalError = "Transfer history changed outside this window. It will not be overwritten."
                throw ArchiveCopy.Failure.rejected(journalError!)
            }
        } else if journalRevision != nil { throw ArchiveCopy.Failure.rejected("Transfer history disappeared. It will not be recreated automatically.") }
        guard records.count <= Self.maxJournalRecords else { throw ArchiveCopy.Failure.rejected("Transfer history is full; no existing records were removed.") }
        try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(records)
        guard data.count <= Self.maxJournalBytes else { throw ArchiveCopy.Failure.rejected("Transfer history is full; no existing records were removed.") }
        try data.write(to: journal, options: .atomic)
        journalRevision = data
    }
    func cancel() { cancellation?.cancel(); task?.cancel() }
    func start(source: URL, drive: StorageDrive) {
        load()
        guard !busy, drive.acceptsCopy else { return }
        let cancel = CancelBox(); cancellation = cancel
        let folder = drive.url.appendingPathComponent("Cairn Export \(UUID().uuidString)")
        var record = TransferRecord(source: source.path, destination: folder.appendingPathComponent(source.lastPathComponent).path, volumeID: drive.uuid, status: "Copying", detail: "Source retained")
        do { try ArchiveCopy.validateSource(source); records.insert(record, at: 0); try persist() }
        catch { message = error.localizedDescription; records.removeAll { $0.id == record.id }; return }
        busy = true; checkingCopy = false; copied = 0; message = "Copying and verifying…"
        task = Task {
            guard await ScanGate.shared.acquire(.copy) else {
                record.status = "Interrupted"; record.detail = "Cancelled before copying. Original retained."
                finish(record); return
            }
            defer { ScanGate.shared.release() }
            let outcome = await Task.detached(priority: .utility) { () -> Result<(URL, Int64, String), Error> in
                do {
                    guard let fresh = StorageDrive.read(drive.url), fresh.uuid == drive.uuid, fresh.acceptsCopy,
                          let attrs = try? source.resourceValues(forKeys: [.fileSizeKey]),
                          fresh.available > Int64(attrs.fileSize ?? 0) + 256_000_000 else { throw ArchiveCopy.Failure.rejected("Destination identity, encryption or free space could not be verified.") }
                    let throttle = ProgressThrottle()
                    return .success(try ArchiveCopy.copy(source: source, directory: folder, cancel: cancel, destinationValid: { drive.stillMounted() }, progress: { bytes in
                        if throttle.shouldPublish() { Task { @MainActor [weak self] in self?.copied = bytes } }
                    }))
                } catch { return .failure(error) }
            }.value
            switch outcome {
            case .success(let (url, bytes, digest)):
                record.destination = url.path; record.bytes = bytes; record.digest = digest
                record.status = "Verified"; record.detail = "Content verified with SHA-256. Original retained. This is a file export, not a managed backup."
            case .failure(let error): record.status = "Interrupted"; record.detail = error.localizedDescription
            }
            finish(record)
            await refresh()
        }
    }

    private func finish(_ record: TransferRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) { records[index] = record }
        message = record.detail
        do { try persist() } catch { message += " History could not be saved: \(error.localizedDescription)" }
        busy = false; checkingCopy = false; task = nil; cancellation = nil
    }

    func recheck(_ record: TransferRecord) {
        guard !busy, journalError == nil, let drive = drives.first(where: { $0.uuid == record.volumeID }), !drive.uuid.isEmpty else {
            message = journalError ?? "Reconnect the original drive before checking this copy."; return
        }
        var destination = URL(fileURLWithPath: record.destination)
        // Older journals stored the containing directory while copying.
        if destination.lastPathComponent.hasPrefix("Cairn Export ") { destination.appendPathComponent(URL(fileURLWithPath: record.source).lastPathComponent) }
        guard SafePaths.isUnder(destination.path, drive.url.path), destination.path != drive.url.path else { message = "The recorded destination does not belong to this drive."; return }
        let cancel = CancelBox(); cancellation = cancel; busy = true; checkingCopy = true; message = "Checking the copy…"
        let target = destination
        task = Task {
            guard await ScanGate.shared.acquire(.verify) else { busy = false; checkingCopy = false; cancellation = nil; task = nil; message = "Copy check cancelled."; return }
            defer { ScanGate.shared.release() }
            let outcome = await Task.detached(priority: .utility) { () -> Result<(Int64, String), Error> in
                Result { try ArchiveCopy.verify(source: URL(fileURLWithPath: record.source), destination: target, bytes: record.bytes, digest: record.digest,
                    cancel: cancel, destinationValid: { drive.stillMounted(requiresWritable: false) }) }
            }.value
            if let index = records.firstIndex(where: { $0.id == record.id }) {
                switch outcome {
                case .success(let (bytes, digest)):
                    records[index].status = "Verified"; records[index].destination = target.path
                    records[index].bytes = bytes; records[index].digest = digest
                    records[index].detail = "Existing copy verified with SHA-256. Original left intact."
                case .failure(let error): records[index].status = "Needs review"; records[index].detail = error.localizedDescription
                }
                message = records[index].detail
                do { try persist() } catch { message += " History could not be saved: \(error.localizedDescription)" }
            }
            busy = false; checkingCopy = false; task = nil; cancellation = nil
        }
    }
}
