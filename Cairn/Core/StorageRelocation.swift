import Foundation
import AppKit
import Observation
import Darwin

/// A folder Cairn knows how to move to an external drive and link back.
/// Each target is a self-contained data folder whose owning app follows a
/// symbolic link. Anything else (repositories, sessions, Docker's disk image,
/// cloud folders) stays out: a generic folder mover is not offered.
struct RelocationTarget: Identifiable, Sendable {
    let id: String
    let title: String
    let relativePath: String
    let bundleIDs: [String]
    let processNames: [String]
    /// What the user loses while the drive is disconnected.
    let whileDisconnected: String
    var url: URL { FileScan.home.appendingPathComponent(relativePath) }

    static let all: [RelocationTarget] = [
        RelocationTarget(id: "ollama-models", title: "Ollama models", relativePath: ".ollama/models",
                         bundleIDs: ["com.electron.ollama"], processNames: ["ollama", "Ollama"],
                         whileDisconnected: "Ollama cannot load or pull models until the drive is back."),
        RelocationTarget(id: "lmstudio-models", title: "LM Studio models", relativePath: ".lmstudio/models",
                         bundleIDs: ["ai.elementlabs.lmstudio"], processNames: ["LM Studio"],
                         whileDisconnected: "LM Studio shows no downloaded models until the drive is back."),
        RelocationTarget(id: "xcode-archives", title: "Xcode archives", relativePath: "Library/Developer/Xcode/Archives",
                         bundleIDs: ["com.apple.dt.Xcode"], processNames: [],
                         whileDisconnected: "Xcode Organizer shows no archives until the drive is back."),
    ]
}

struct RelocationRecord: Codable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable { case moving, offloaded, restoring, restored, interrupted, needsReview }
    var id = UUID()
    var date = Date()
    var targetID: String
    var source: String
    var destination: String
    var volumeID: String
    var volumeName: String
    var bytes: Int64 = 0
    var files: Int = 0
    var status: Status
    var detail: String
}

/// The filesystem steps. Nothing here touches the UI, so the diagnostics can
/// drive it against disposable folders.
enum Relocation {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static let movingSuffix = ".cairn-moving"
    static let restoringSuffix = ".cairn-restoring"
    static let partialSuffix = ".partial"

    struct Inventory: Sendable {
        var directories: [String] = []
        var files: [String] = []
        var bytes: Int64 = 0
    }

    private static func fileType(_ path: String) -> mode_t? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return info.st_mode & S_IFMT
    }
    static func isRealDirectory(_ url: URL) -> Bool { fileType(url.path) == S_IFDIR }
    static func isLink(_ url: URL) -> Bool { fileType(url.path) == S_IFLNK }
    static func exists(_ url: URL) -> Bool { fileType(url.path) != nil }
    static func linkDestination(_ url: URL) -> String? {
        guard isLink(url) else { return nil }
        return try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
    }

    /// Every entry must be an ordinary local file or folder. A link, socket or
    /// cloud placeholder means the folder is not a plain data store, so stop.
    static func inventory(_ root: URL, cancel: CancelBox) throws -> Inventory {
        guard isRealDirectory(root) else { throw Failure(message: "\(root.path) is not an ordinary folder.") }
        var result = Inventory()
        var stack: [String] = [""]
        while let relative = stack.popLast() {
            if cancel.isCancelled { throw Failure(message: "Cancelled. Nothing was moved.") }
            let folder = relative.isEmpty ? root : root.appendingPathComponent(relative)
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
            for name in names {
                let child = relative.isEmpty ? name : relative + "/" + name
                let url = root.appendingPathComponent(child)
                var info = stat()
                guard lstat(url.path, &info) == 0 else { throw Failure(message: "Could not read \(url.path).") }
                switch info.st_mode & S_IFMT {
                case S_IFDIR: result.directories.append(child); stack.append(child)
                case S_IFREG:
                    if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true {
                        throw Failure(message: "\(url.path) is a cloud file. Nothing was moved.")
                    }
                    result.files.append(child); result.bytes += Int64(info.st_size)
                default: throw Failure(message: "\(url.path) is a link or special file. Cairn only moves plain data folders.")
                }
            }
        }
        return result
    }

    /// Copies into a fresh `.partial` folder, verifies every file by SHA-256,
    /// then promotes it without replacing anything already there.
    static func copyTree(from source: URL, to destination: URL, cancel: CancelBox,
                         destinationValid: () -> Bool, progress: (Int64) -> Void = { _ in }) throws -> Inventory {
        let plan = try inventory(source, cancel: cancel)
        guard !exists(destination) else { throw Failure(message: "\(destination.path) already exists. Nothing was replaced.") }
        let partial = URL(fileURLWithPath: destination.path + partialSuffix)
        guard !exists(partial) else { throw Failure(message: "An unfinished copy is at \(partial.path). Remove it or choose another drive.") }
        guard destinationValid() else { throw Failure(message: "The drive is no longer available.") }
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        for folder in plan.directories {
            try FileManager.default.createDirectory(at: partial.appendingPathComponent(folder), withIntermediateDirectories: false)
        }
        var copied: Int64 = 0
        for file in plan.files {
            guard !cancel.isCancelled, destinationValid() else {
                throw Failure(message: "Copy interrupted. The original is untouched; an unfinished copy is at \(partial.path).")
            }
            let from = source.appendingPathComponent(file)
            let to = partial.appendingPathComponent(file)
            guard let before = DupHash.fingerprint(from, shouldCancel: { cancel.isCancelled }) else {
                throw Failure(message: "Could not read \(from.path). The original is untouched.")
            }
            try copyFile(from, to)
            guard DupHash.unchanged(from, since: before),
                  let after = DupHash.fingerprint(to, shouldCancel: { cancel.isCancelled }),
                  after.digest == before.digest, after.identity.size == before.identity.size else {
                throw Failure(message: "\(file) changed or did not verify. Close the app that owns it and try again. The original is untouched.")
            }
            copied += before.identity.size
            progress(copied)
        }
        guard destinationValid(), renamex_np(partial.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            throw Failure(message: "The verified copy could not be finished. The original is untouched.")
        }
        return plan
    }

    private static func copyFile(_ from: URL, _ to: URL) throws {
        let input = open(from.path, O_RDONLY | O_NOFOLLOW)
        guard input >= 0 else { throw Failure(message: "Could not open \(from.path).") }
        let reader = FileHandle(fileDescriptor: input, closeOnDealloc: true)
        let output = open(to.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard output >= 0 else { throw Failure(message: "Could not create \(to.path).") }
        let writer = FileHandle(fileDescriptor: output, closeOnDealloc: true)
        defer { try? reader.close(); try? writer.close() }
        while true {
            let more = try autoreleasepool { () -> Bool in
                guard let data = try reader.read(upToCount: DupHash.chunk), !data.isEmpty else { return false }
                try writer.write(contentsOf: data)
                return true
            }
            if !more { break }
        }
        try writer.synchronize()
    }

    /// Copy, verify, swap the folder for a link, check the link, then remove
    /// the original. Every failure before the last step leaves the original in
    /// place under its own name.
    static func offload(source: URL, destination: URL, cancel: CancelBox,
                        destinationValid: () -> Bool, progress: (Int64) -> Void = { _ in }) throws -> Inventory {
        guard isRealDirectory(source) else { throw Failure(message: "\(source.path) is not an ordinary folder. It may already be offloaded.") }
        let moving = URL(fileURLWithPath: source.path + movingSuffix)
        guard !exists(moving) else { throw Failure(message: "A previous move did not finish at \(moving.path). Review it first.") }
        let copied = try copyTree(from: source, to: destination, cancel: cancel, destinationValid: destinationValid, progress: progress)
        let current = try inventory(source, cancel: cancel)
        guard current.files == copied.files, current.bytes == copied.bytes else {
            throw Failure(message: "The folder changed while it was being copied. The original is untouched; the copy stays at \(destination.path).")
        }
        guard renamex_np(source.path, moving.path, UInt32(RENAME_EXCL)) == 0 else {
            throw Failure(message: "Could not set the original aside. It is untouched.")
        }
        func putBack(_ reason: String) -> Failure {
            if isLink(source) { unlink(source.path) }
            let restored = renamex_np(moving.path, source.path, UInt32(RENAME_EXCL)) == 0
            return Failure(message: reason + (restored ? " The original was put back." : " The original is at \(moving.path)."))
        }
        guard symlink(destination.path, source.path) == 0 else { throw putBack("Could not create the link.") }
        guard linkDestination(source) == destination.path, destinationValid(),
              let linked = try? inventory(destination, cancel: cancel),
              linked.files == copied.files, linked.bytes == copied.bytes else {
            throw putBack("The link did not check out.")
        }
        try FileManager.default.removeItem(at: moving)
        return copied
    }

    /// Copies the data back beside the link, verifies it, then swaps the link
    /// for the folder. The drive copy is kept so nothing is lost if this fails.
    static func restore(source: URL, destination: URL, cancel: CancelBox,
                        destinationValid: () -> Bool, progress: (Int64) -> Void = { _ in }) throws -> Inventory {
        guard linkDestination(source) == destination.path else {
            throw Failure(message: "\(source.path) is no longer Cairn's link to \(destination.path). Nothing was changed.")
        }
        let incoming = URL(fileURLWithPath: source.path + restoringSuffix)
        guard !exists(incoming) else { throw Failure(message: "A previous restore did not finish at \(incoming.path). Review it first.") }
        let copied = try copyTree(from: destination, to: incoming, cancel: cancel, destinationValid: destinationValid, progress: progress)
        guard linkDestination(source) == destination.path, unlink(source.path) == 0 else {
            throw Failure(message: "The link changed during the restore. The restored copy is at \(incoming.path).")
        }
        guard renamex_np(incoming.path, source.path, UInt32(RENAME_EXCL)) == 0 else {
            _ = symlink(destination.path, source.path)
            throw Failure(message: "Could not move the restored folder into place. The link was recreated; the restored copy is at \(incoming.path).")
        }
        return copied
    }

    /// After a crash: if the original was set aside but no link exists, put it
    /// back. If both exist, leave them for the user to review.
    static func reconcile(source: URL) -> RelocationRecord.Status? {
        let moving = URL(fileURLWithPath: source.path + movingSuffix)
        guard exists(moving) else { return nil }
        if !exists(source), renamex_np(moving.path, source.path, UInt32(RENAME_EXCL)) == 0 { return .interrupted }
        return .needsReview
    }

    static func ownerRunning(_ target: RelocationTarget) -> Bool {
        if target.bundleIDs.contains(where: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }) { return true }
        return target.processNames.contains { name in
            (try? ToolRunner.runExecutable("/usr/bin/pgrep", ["-x", name], timeout: 3))?.ok == true
        }
    }
}

/// Offload state for the Storage page. One operation at a time, journalled in
/// its own file so transfer history is never rewritten by this feature.
@MainActor @Observable final class RelocationStore {
    static let shared = RelocationStore()
    private static let maxJournalBytes = 1 << 20

    struct TargetState: Sendable {
        var bytes: Int64?
        var linkedTo: String?
        var driveConnected = false
    }
    private(set) var records: [RelocationRecord] = []
    private(set) var states: [String: TargetState] = [:]
    private(set) var busyTarget: String?
    private(set) var copied: Int64 = 0
    private(set) var message = ""
    private var loaded = false
    private var journalBroken = false
    private var cancellation: CancelBox?
    private let journal: URL

    init(journal: URL = FileScan.home.appendingPathComponent("Library/Application Support/Cairn/relocations.json")) {
        self.journal = journal
    }

    func latest(_ target: RelocationTarget) -> RelocationRecord? {
        records.first { $0.targetID == target.id }
    }

    func load() {
        guard !loaded else { return }
        loaded = true
        if Relocation.exists(journal) {
            guard !Relocation.isLink(journal),
                  let data = try? Data(contentsOf: journal), data.count <= Self.maxJournalBytes,
                  let decoded = try? JSONDecoder().decode([RelocationRecord].self, from: data) else {
                journalBroken = true
                message = "Offload history could not be read; it will not be overwritten. Moves are disabled until it is fixed."
                return
            }
            records = decoded
        }
        var changed = false
        for index in records.indices where records[index].status == .moving || records[index].status == .restoring {
            let source = URL(fileURLWithPath: records[index].source)
            let outcome = Relocation.reconcile(source: source)
            records[index].status = outcome ?? .needsReview
            records[index].detail = outcome == .interrupted
                ? "The previous move stopped early. The original folder was put back."
                : "The previous operation stopped early. Check \(records[index].source) and the drive copy before trying again."
            changed = true
        }
        if changed { persist() }
    }

    func refresh() async {
        load()
        let targets = RelocationTarget.all
        let snapshot = await Task.detached(priority: .utility) { () -> [String: TargetState] in
            var result: [String: TargetState] = [:]
            for target in targets {
                var state = TargetState()
                if let destination = Relocation.linkDestination(target.url) {
                    state.linkedTo = destination
                    state.driveConnected = Relocation.isRealDirectory(URL(fileURLWithPath: destination))
                } else if Relocation.isRealDirectory(target.url) {
                    let stats = FileScan.measure(target.url)
                    state.bytes = stats.allocatedSize
                }
                result[target.id] = state
            }
            return result
        }.value
        states = snapshot
    }

    func cancel() { cancellation?.cancel() }

    func offload(_ target: RelocationTarget, to drive: StorageDrive) {
        load()
        guard busyTarget == nil, !journalBroken else { return }
        guard drive.acceptsCopy else { message = drive.exportStatus; return }
        guard !Relocation.ownerRunning(target) else { message = "Quit \(target.title.components(separatedBy: " ").first ?? "the app") first, then try again."; return }
        let destination = drive.url.appendingPathComponent("Cairn Offload", isDirectory: true).appendingPathComponent(target.id)
        var record = RelocationRecord(targetID: target.id, source: target.url.path, destination: destination.path,
                                      volumeID: drive.uuid, volumeName: drive.name, status: .moving,
                                      detail: "Copying and verifying. The original stays in place until the copy checks out.")
        run(target, record: &record, gate: .copy) { cancel, publish in
            guard let fresh = StorageDrive.read(drive.url), fresh.uuid == drive.uuid, fresh.acceptsCopy, fresh.hasUniqueMountedIdentity() else {
                throw Relocation.Failure(message: "The drive's identity or encryption could not be confirmed. Nothing was moved.")
            }
            let size = try Relocation.inventory(target.url, cancel: cancel).bytes
            guard fresh.available > size + 1_000_000_000 else {
                throw Relocation.Failure(message: "\(fresh.name) needs \(Fmt.size(size + 1_000_000_000)) free. Nothing was moved.")
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            return try Relocation.offload(source: target.url, destination: destination, cancel: cancel,
                                          destinationValid: { drive.stillMounted() }, progress: publish)
        } finish: { record, inventory in
            record.status = .offloaded
            record.bytes = inventory.bytes; record.files = inventory.files.count
            record.detail = "Moved \(Fmt.size(inventory.bytes)) to \(drive.name) and linked it back. \(target.whileDisconnected)"
        }
    }

    func restore(_ target: RelocationTarget) {
        load()
        guard busyTarget == nil, !journalBroken, let previous = latest(target), previous.status == .offloaded else { return }
        guard !Relocation.ownerRunning(target) else { message = "Quit \(target.title.components(separatedBy: " ").first ?? "the app") first, then try again."; return }
        let destination = URL(fileURLWithPath: previous.destination)
        guard Relocation.isRealDirectory(destination) else { message = "Connect \(previous.volumeName) to bring \(target.title) back."; return }
        var record = previous
        record.id = UUID(); record.date = Date(); record.status = .restoring
        record.detail = "Copying back and verifying. The drive copy is kept."
        run(target, record: &record, gate: .copy) { cancel, publish in
            guard Volumes.homeFree() > previous.bytes + 2_000_000_000 else {
                throw Relocation.Failure(message: "This Mac needs \(Fmt.size(previous.bytes + 2_000_000_000)) free to bring it back. Nothing was changed.")
            }
            return try Relocation.restore(source: target.url, destination: destination, cancel: cancel,
                                          destinationValid: { Relocation.isRealDirectory(destination) }, progress: publish)
        } finish: { record, inventory in
            record.status = .restored
            record.bytes = inventory.bytes; record.files = inventory.files.count
            record.detail = "Back on this Mac. The copy on \(previous.volumeName) was kept at \(previous.destination); delete it there when you no longer need it."
        }
    }

    private func run(_ target: RelocationTarget, record: inout RelocationRecord, gate: ScanGate.Operation,
                     work: @escaping @Sendable (CancelBox, @escaping @Sendable (Int64) -> Void) throws -> Relocation.Inventory,
                     finish: @escaping (inout RelocationRecord, Relocation.Inventory) -> Void) {
        records.insert(record, at: 0)
        guard persist() else { records.removeFirst(); return }
        let cancel = CancelBox()
        cancellation = cancel
        busyTarget = target.id
        copied = 0
        message = record.detail
        var current = record
        Task {
            defer { busyTarget = nil; cancellation = nil }
            guard await ScanGate.shared.acquire(gate) else {
                current.status = .interrupted; current.detail = "Cancelled before starting. Nothing was changed."
                save(current); return
            }
            defer { ScanGate.shared.release() }
            let throttle = ProgressThrottle()
            let outcome = await Task.detached(priority: .utility) { () -> Result<Relocation.Inventory, Error> in
                Result {
                    try work(cancel) { bytes in
                        if throttle.shouldPublish() { Task { @MainActor in RelocationStore.shared.copied = bytes } }
                    }
                }
            }.value
            switch outcome {
            case .success(let inventory): finish(&current, inventory)
            case .failure(let error):
                current.status = Relocation.reconcile(source: target.url) == .needsReview ? .needsReview : .interrupted
                current.detail = error.localizedDescription
            }
            save(current)
            await refresh()
        }
    }

    private func save(_ record: RelocationRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) { records[index] = record }
        message = record.detail
        if !persist() { message += " Offload history could not be saved." }
    }

    @discardableResult private func persist() -> Bool {
        guard !journalBroken else { return false }
        do {
            try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Array(records.prefix(500)))
            try data.write(to: journal, options: .atomic)
            return true
        } catch {
            message = "Offload history could not be saved: \(error.localizedDescription)"
            return false
        }
    }
}
