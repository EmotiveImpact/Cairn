import Foundation
import AppKit
import Observation
import Darwin

/// Something Cairn knows how to move to a drive. App data is linked back so
/// the app keeps working while the drive is plugged in; your own files are
/// moved as they are and brought back with one click; rebuildable build files
/// are not copied at all, only pointed at the drive from now on.
struct RelocationTarget: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let url: URL
    let mode: Relocation.Mode
    /// The app to close first, in plain words, or empty when none.
    var closeFirst: String = ""
    var bundleIDs: [String] = []
    var processNames: [String] = []
    /// What the person loses while the drive is unplugged.
    var whileDisconnected: String = ""
    /// Private files need a drive locked with a password.
    var privateFiles = false
    /// A command that safely stops the owner before the move (simulators).
    var prepare: [String] = []
    /// Where it goes inside the drive's "Cairn Offload" folder.
    var driveFolder: String

    static let driveRoot = "Cairn Offload"
    static let ownFolder = "From this Mac"

    private static func home(_ relative: String) -> URL { FileScan.home.appendingPathComponent(relative) }

    static let all: [RelocationTarget] = appTargets + (DockerMove.installed ? [docker] : [])

    /// Docker quits itself and is pointed at the drive through its own setting,
    /// so there is no link and nothing for the person to close by hand.
    static let docker = RelocationTarget(id: "docker-desktop", title: "Docker's disk", url: DockerMove.currentDataFolder(), mode: .archive,
                                         whileDisconnected: "Docker will not start until the drive is back.", driveFolder: "docker-desktop")

    static let appTargets: [RelocationTarget] = [
        RelocationTarget(id: "ollama-models", title: "Ollama models", url: home(".ollama/models"), mode: .linkBack,
                         closeFirst: "Ollama", bundleIDs: ["com.electron.ollama"], processNames: ["ollama", "Ollama"],
                         whileDisconnected: "Ollama cannot load or pull models until the drive is back.", driveFolder: "ollama-models"),
        RelocationTarget(id: "lmstudio-models", title: "LM Studio models", url: home(".lmstudio/models"), mode: .linkBack,
                         closeFirst: "LM Studio", bundleIDs: ["ai.elementlabs.lmstudio"], processNames: ["LM Studio"],
                         whileDisconnected: "LM Studio shows no downloaded models until the drive is back.", driveFolder: "lmstudio-models"),
        RelocationTarget(id: "huggingface-hub", title: "Hugging Face models", url: home(".cache/huggingface/hub"), mode: .linkBack,
                         closeFirst: "any Python work using these models", processNames: [],
                         whileDisconnected: "Models are downloaded again if a program asks for them.", driveFolder: "huggingface-hub"),
        RelocationTarget(id: "xcode-archives", title: "Xcode archives", url: home("Library/Developer/Xcode/Archives"), mode: .linkBack,
                         closeFirst: "Xcode", bundleIDs: ["com.apple.dt.Xcode"],
                         whileDisconnected: "Xcode Organizer shows no archives until the drive is back.", driveFolder: "xcode-archives"),
        RelocationTarget(id: "ios-simulators", title: "iPhone simulators", url: home("Library/Developer/CoreSimulator/Devices"), mode: .linkBack,
                         closeFirst: "Xcode and Simulator", bundleIDs: ["com.apple.dt.Xcode", "com.apple.iphonesimulator"],
                         processNames: ["Simulator", "launchd_sim"],
                         whileDisconnected: "Xcode shows no simulators until the drive is back.",
                         prepare: ["/usr/bin/xcrun", "simctl", "shutdown", "all"], driveFolder: "ios-simulators"),
        RelocationTarget(id: "android-sdk", title: "Android SDK and NDK", url: home("Library/Android/sdk"), mode: .linkBack,
                         closeFirst: "Android Studio and any emulator", bundleIDs: ["com.google.android.studio"],
                         processNames: ["qemu-system-aarch64", "qemu-system-x86_64", "emulator", "adb"],
                         whileDisconnected: "Android builds stop until the drive is back.", driveFolder: "android-sdk"),
        RelocationTarget(id: "android-emulators", title: "Android emulators", url: home(".android/avd"), mode: .linkBack,
                         closeFirst: "Android Studio and any emulator", bundleIDs: ["com.google.android.studio"],
                         processNames: ["qemu-system-aarch64", "qemu-system-x86_64", "emulator"],
                         whileDisconnected: "Android emulators do not start until the drive is back.", driveFolder: "android-emulators"),
        RelocationTarget(id: "xcode-derived-data", title: "Xcode build files", url: home("Library/Developer/Xcode/DerivedData"), mode: .freshOnDrive,
                         closeFirst: "Xcode", bundleIDs: ["com.apple.dt.Xcode"],
                         whileDisconnected: "Xcode builds on this Mac until the drive is back.", driveFolder: "xcode-derived-data"),
    ]

    /// Your own file or folder, moved as it is under "From this Mac" with the
    /// same folder layout. Nil when it is not something Cairn should move.
    static func own(_ url: URL, home: URL = FileScan.home) -> RelocationTarget? {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        guard SafePaths.isUnder(path, homePath), path != homePath else { return nil }
        let relative = String(path.dropFirst(homePath.count + 1))
        let lowered = relative.lowercased()
        let refused = ["library/", ".", "applications/"]
        guard !refused.contains(where: { lowered.hasPrefix($0) || lowered + "/" == $0 }),
              !lowered.contains("/."), !lowered.hasSuffix(".app"),
              !lowered.hasSuffix(".photoslibrary"), !lowered.hasSuffix(".musiclibrary"),
              !lowered.contains(".photoslibrary/"), !lowered.contains(".musiclibrary/"),
              SafePaths.protectedSessionReason(url) == nil,
              Relocation.isRealDirectory(url) || Relocation.isRegularFile(url) else { return nil }
        return RelocationTarget(id: "own:" + relative, title: url.lastPathComponent, url: url, mode: .archive,
                                whileDisconnected: "Plug the drive in to open it.", privateFiles: true,
                                driveFolder: ownFolder + "/" + relative)
    }

    static func == (a: RelocationTarget, b: RelocationTarget) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
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
    // Added with verified moves; older history decodes these as missing.
    var mode: Relocation.Mode?
    var title: String?
    /// The destination inside its drive, so a drive mounted under a new name
    /// can be found again by its ID.
    var volumePath: String?
    var privateFiles: Bool?

    var resolvedMode: Relocation.Mode { mode ?? .linkBack }
}

/// Move state for every page that offers SSD. One move at a time, the rest
/// queued; journalled in its own file so it is never mixed with other history.
@MainActor @Observable final class RelocationStore {
    static let shared = RelocationStore()
    private static let maxJournalBytes = 4 << 20

    struct TargetState: Sendable {
        var bytes: Int64?
        var linkedTo: String?
        var driveConnected = false
        /// The record says it is on a drive, but an app made a fresh folder in
        /// its place. Both are kept until the person picks one.
        var conflict = false
    }
    private(set) var records: [RelocationRecord] = []
    private(set) var states: [String: TargetState] = [:]
    private(set) var busyTarget: String?
    private(set) var queued: [String] = []
    private(set) var copied: Int64 = 0
    private(set) var total: Int64 = 0
    private(set) var startedAt: Date?
    private(set) var message = ""
    private var loaded = false
    private var journalBroken = false
    private var cancellation: CancelBox?
    private var queue: [(RelocationTarget, StorageDrive)] = []
    private let journal: URL

    init(journal: URL = FileScan.home.appendingPathComponent("Library/Application Support/Cairn/relocations.json")) {
        self.journal = journal
    }

    /// The app targets plus every own file or folder that has a history.
    var targets: [RelocationTarget] {
        var seen = Set(RelocationTarget.all.map(\.id))
        var result = RelocationTarget.all
        // Own files and iPhone backups are found again from their history.
        for record in records where !seen.contains(record.targetID)
            && (record.targetID.hasPrefix("own:") || record.targetID.hasPrefix("iphone-backup:")) {
            seen.insert(record.targetID)
            let folder = (record.volumePath ?? "").replacingOccurrences(of: RelocationTarget.driveRoot + "/", with: "")
            result.append(RelocationTarget(id: record.targetID, title: record.title ?? URL(fileURLWithPath: record.source).lastPathComponent,
                                           url: URL(fileURLWithPath: record.source), mode: .archive,
                                           whileDisconnected: "Plug the drive in to open it.", privateFiles: record.privateFiles ?? true,
                                           driveFolder: folder))
        }
        return result
    }

    /// App data linked to a drive that is not here, newest first. Only
    /// linked items are counted: an archive is not missed by any app.
    nonisolated static func away(_ records: [RelocationRecord]) -> [(title: String, drive: String)] {
        var seen = Set<String>()
        var result: [(title: String, drive: String)] = []
        for record in records where seen.insert(record.targetID).inserted {
            guard record.status == .offloaded, record.resolvedMode != .archive,
                  !Relocation.exists(URL(fileURLWithPath: record.destination)) else { continue }
            let title = record.title ?? RelocationTarget.appTargets.first { $0.id == record.targetID }?.title
                ?? URL(fileURLWithPath: record.source).lastPathComponent
            result.append((title, record.volumeName))
        }
        return result
    }

    func latest(_ target: RelocationTarget) -> RelocationRecord? {
        records.first { $0.targetID == target.id }
    }

    /// Seconds left, from the pace so far. Nil until there is a pace.
    var secondsLeft: TimeInterval? {
        guard let startedAt, copied > 0, total > copied else { return nil }
        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed > 3 else { return nil }
        return elapsed / Double(copied) * Double(total - copied)
    }

    func load() {
        guard !loaded else { return }
        loaded = true
        if Relocation.exists(journal) {
            guard !Relocation.isLink(journal),
                  let data = try? Data(contentsOf: journal), data.count <= Self.maxJournalBytes,
                  let decoded = try? JSONDecoder().decode([RelocationRecord].self, from: data) else {
                journalBroken = true
                message = "Cairn's move history could not be read, so moves are paused rather than risk overwriting it."
                return
            }
            records = decoded
        }
        var changed = false
        for index in records.indices where records[index].status == .moving || records[index].status == .restoring {
            let record = records[index]
            let outcome = Relocation.reconcile(source: URL(fileURLWithPath: record.source),
                                               destination: URL(fileURLWithPath: record.destination), mode: record.resolvedMode)
            switch outcome {
            case .offloaded?:
                records[index].status = .offloaded
                records[index].detail = record.status == .moving
                    ? "The move finished after Cairn restarted. The drive copy was checked again first."
                    : "The bring-back stopped early. It is still on \(record.volumeName)."
            case .interrupted?:
                records[index].status = .interrupted
                records[index].detail = "The last move stopped early. Everything is back where it was."
            case nil where record.status == .restoring:
                records[index].status = Relocation.exists(URL(fileURLWithPath: record.source)) && !Relocation.isLink(URL(fileURLWithPath: record.source)) ? .restored : .offloaded
                records[index].detail = records[index].status == .restored ? "Back on this Mac." : "Still on \(record.volumeName)."
            case nil:
                records[index].status = .interrupted
                records[index].detail = "The last move stopped before anything changed."
            default:
                records[index].status = .needsReview
                records[index].detail = "The last move stopped part way. Cairn kept both \(record.source) and the drive copy for you to check."
            }
            changed = true
        }
        if changed { persist() }
    }

    func refresh() async {
        load()
        let targets = targets
        let records = records
        let snapshot = await Task.detached(priority: .utility) { () -> ([String: TargetState], [UUID: String]) in
            var result: [String: TargetState] = [:]
            var repointed: [UUID: String] = [:]
            let mounted = Volumes.mountedExternalVolumes().compactMap { url -> (String, URL)? in
                guard let id = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString else { return nil }
                return (id, url)
            }
            for target in targets {
                var state = TargetState()
                let record = records.first { $0.targetID == target.id }
                // A drive that came back under a new name: find it by its ID.
                if let record, record.status == .offloaded, !Relocation.exists(URL(fileURLWithPath: record.destination)),
                   let inside = record.volumePath,
                   let volume = mounted.first(where: { $0.0 == record.volumeID })?.1 {
                    let moved = volume.appendingPathComponent(inside)
                    if Relocation.exists(moved), Self.repoint(target, from: record.destination, to: moved.path, mode: record.resolvedMode) {
                        repointed[record.id] = moved.path
                    }
                }
                let destination = repointed[record?.id ?? UUID()] ?? record?.destination
                if let link = Relocation.linkDestination(target.url) {
                    state.linkedTo = link
                    state.driveConnected = Relocation.exists(URL(fileURLWithPath: link))
                } else if record?.status == .offloaded, record?.resolvedMode == .archive, let destination {
                    state.linkedTo = destination
                    state.driveConnected = Relocation.exists(URL(fileURLWithPath: destination))
                } else if Relocation.isRealDirectory(target.url) || Relocation.isRegularFile(target.url) {
                    state.bytes = FileScan.measure(target.url).allocatedSize
                    state.conflict = record?.status == .offloaded && record?.resolvedMode != .archive
                }
                // Tidy unfinished copies Cairn left on a drive that is here now.
                if let record, record.status == .interrupted, let destination {
                    let copy = URL(fileURLWithPath: destination)
                    Relocation.discardPartial(for: copy)
                    let original = URL(fileURLWithPath: record.source)
                    if (Relocation.isRealDirectory(original) || Relocation.isRegularFile(original)),
                       destination.contains("/\(RelocationTarget.driveRoot)/"), Relocation.exists(copy), !Relocation.isLink(copy) {
                        try? FileManager.default.removeItem(at: copy)
                    }
                }
                result[target.id] = state
            }
            return (result, repointed)
        }.value
        states = snapshot.0
        if !snapshot.1.isEmpty {
            for (id, path) in snapshot.1 {
                if let index = self.records.firstIndex(where: { $0.id == id }) { self.records[index].destination = path }
            }
            persist()
        }
    }

    /// Swaps a link to point at the drive's new mount path in one step, so the
    /// app never sees a missing link. Only Cairn's own link is touched.
    nonisolated private static func repoint(_ target: RelocationTarget, from old: String, to new: String, mode: Relocation.Mode) -> Bool {
        guard mode != .archive else { return true }
        guard Relocation.linkDestination(target.url) == old else { return false }
        let temporary = target.url.path + ".cairn-link"
        unlink(temporary)
        guard symlink(new, temporary) == 0 else { return false }
        guard rename(temporary, target.url.path) == 0 else { unlink(temporary); return false }
        return true
    }

    func cancel() {
        queue.removeAll(); queued.removeAll()
        cancellation?.cancel()
    }

    /// Moves one item, or queues it behind the one already moving.
    func move(_ target: RelocationTarget, to drive: StorageDrive) {
        load()
        guard !journalBroken else { return }
        guard drive.acceptsMove(privateFiles: target.privateFiles) else { message = drive.moveStatus(privateFiles: target.privateFiles); return }
        if busyTarget != nil {
            guard busyTarget != target.id, !queued.contains(target.id) else { return }
            queue.append((target, drive)); queued.append(target.id)
            return
        }
        guard !Self.ownerRunning(target) else {
            message = "Close \(target.closeFirst.isEmpty ? "the app using it" : target.closeFirst) first, then try again."
            runNext(); return
        }
        let inside = RelocationTarget.driveRoot + "/" + target.driveFolder
        let destination = drive.url.appendingPathComponent(inside)
        var record = RelocationRecord(targetID: target.id, source: target.url.path, destination: destination.path,
                                      volumeID: drive.uuid, volumeName: drive.name, status: .moving,
                                      detail: target.mode == .freshOnDrive ? "Pointing future build files at \(drive.name)."
                                          : "Copying and checking. The original stays put until the copy matches.",
                                      mode: target.mode, title: target.title, volumePath: inside, privateFiles: target.privateFiles)
        run(target, record: &record) { cancel, publish, setTotal in
            guard let fresh = StorageDrive.read(drive.url), fresh.uuid == drive.uuid,
                  fresh.acceptsMove(privateFiles: target.privateFiles), fresh.hasUniqueMountedIdentity() else {
                throw Relocation.Failure(message: "Cairn could not confirm this is the same drive. Nothing was moved.")
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if target.mode == .freshOnDrive {
                try Relocation.redirect(source: target.url, destination: destination, destinationValid: { drive.stillMounted() })
                return Relocation.Inventory()
            }
            let size = try Relocation.inventory(target.url, cancel: cancel).bytes
            setTotal(size)
            guard fresh.available > size + 2_000_000_000 else {
                throw Relocation.Failure(message: "\(fresh.name) needs \(Fmt.size(size + 2_000_000_000)) free for this. Nothing was moved.")
            }
            if target.id == RelocationTarget.docker.id {
                return try DockerMove.move(from: target.url, to: destination, cancel: cancel,
                                           destinationValid: { drive.stillMounted() }, progress: publish)
            }
            return try Relocation.offload(source: target.url, destination: destination, mode: target.mode, cancel: cancel,
                                          destinationValid: { drive.stillMounted() }, progress: publish)
        } finish: { record, inventory in
            record.status = .offloaded
            record.bytes = inventory.bytes; record.files = inventory.files.count
            switch target.mode {
            case .linkBack: record.detail = "Moved \(Fmt.size(inventory.bytes)) to \(drive.name) and linked it back. \(target.whileDisconnected)"
            case .archive: record.detail = "Moved \(Fmt.size(inventory.bytes)) to \(drive.name). Bring it back any time."
            case .freshOnDrive: record.detail = "Old build files removed. New ones go to \(drive.name)."
            }
        }
    }

    func bringBack(_ target: RelocationTarget) {
        load()
        guard busyTarget == nil, !journalBroken, let previous = latest(target), previous.status == .offloaded else { return }
        guard !Self.ownerRunning(target) else {
            message = "Close \(target.closeFirst.isEmpty ? "the app using it" : target.closeFirst) first, then try again."; return
        }
        let destination = URL(fileURLWithPath: previous.destination)
        guard Relocation.exists(destination) else { message = "Plug in \(previous.volumeName) to bring \(target.title) back."; return }
        var record = previous
        record.id = UUID(); record.date = Date(); record.status = .restoring
        record.detail = "Copying back and checking. The drive copy stays until this Mac's copy matches."
        let mode = previous.resolvedMode
        run(target, record: &record) { cancel, publish, setTotal in
            if mode == .freshOnDrive {
                try Relocation.unredirect(source: target.url, destination: destination, destinationValid: { Relocation.exists(destination) })
                return Relocation.Inventory()
            }
            setTotal(previous.bytes)
            guard Volumes.homeFree() > previous.bytes + 2_000_000_000 else {
                throw Relocation.Failure(message: "This Mac needs \(Fmt.size(previous.bytes + 2_000_000_000)) free to bring it back. Nothing was changed.")
            }
            if target.id == RelocationTarget.docker.id {
                return try DockerMove.bringBack(to: target.url, from: destination, cancel: cancel,
                                                destinationValid: { Relocation.exists(destination) }, progress: publish)
            }
            return try Relocation.restore(source: target.url, destination: destination, mode: mode, cancel: cancel,
                                          destinationValid: { Relocation.exists(destination) }, progress: publish)
        } finish: { record, inventory in
            record.status = .restored
            record.bytes = inventory.bytes; record.files = inventory.files.count
            record.detail = mode == .freshOnDrive ? "Xcode builds on this Mac again." : "Back on this Mac, and removed from \(previous.volumeName)."
        }
    }

    private func runNext() {
        guard busyTarget == nil, !queue.isEmpty else { return }
        let (target, drive) = queue.removeFirst()
        queued.removeAll { $0 == target.id }
        move(target, to: drive)
    }

    private func run(_ target: RelocationTarget, record: inout RelocationRecord,
                     work: @escaping @Sendable (CancelBox, @escaping @Sendable (Int64) -> Void, @escaping @Sendable (Int64) -> Void) throws -> Relocation.Inventory,
                     finish: @escaping (inout RelocationRecord, Relocation.Inventory) -> Void) {
        records.insert(record, at: 0)
        guard persist() else { records.removeFirst(); return }
        let cancel = CancelBox()
        cancellation = cancel
        busyTarget = target.id
        copied = 0; total = 0; startedAt = Date()
        message = record.detail
        let initial = record
        Task {
            var current = initial
            defer { busyTarget = nil; cancellation = nil; startedAt = nil; runNext() }
            guard await ScanGate.shared.acquire(.copy) else {
                current.status = .interrupted; current.detail = "Stopped before starting. Nothing was changed."
                save(current); return
            }
            defer { ScanGate.shared.release() }
            if !target.prepare.isEmpty {
                let command = target.prepare
                _ = await Task.detached(priority: .utility) {
                    try? ToolRunner.runExecutable(command[0], Array(command.dropFirst()), timeout: 60)
                }.value
            }
            if Self.ownerRunning(target) {
                current.status = .interrupted
                current.detail = "\(target.closeFirst.isEmpty ? "The app using it" : target.closeFirst) is still open. Nothing was changed."
                save(current); return
            }
            // Keep the Mac awake: a sleeping Mac would stall the copy.
            let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                                 reason: "Cairn is moving files to a drive")
            defer { ProcessInfo.processInfo.endActivity(activity) }
            let throttle = ProgressThrottle()
            let outcome = await Task.detached(priority: .utility) { () -> Result<Relocation.Inventory, Error> in
                let counter = ByteCounter()
                return Result {
                    try work(cancel, { bytes in
                        counter.set(bytes)
                        if throttle.shouldPublish() { Task { @MainActor in RelocationStore.shared.copied = counter.value } }
                    }, { size in
                        Task { @MainActor in RelocationStore.shared.total = size }
                    })
                }
            }.value
            switch outcome {
            case .success(let inventory): finish(&current, inventory)
            case .failure(let error):
                let mode = current.resolvedMode
                let settled = Relocation.reconcile(source: target.url, destination: URL(fileURLWithPath: current.destination), mode: mode)
                if current.status == .restoring {
                    current.status = settled == .needsReview ? .needsReview : .offloaded
                    current.detail = error.localizedDescription + " It is still on \(current.volumeName)."
                } else {
                    current.status = settled == .needsReview ? .needsReview : (settled == .offloaded ? .offloaded : .interrupted)
                    current.detail = error.localizedDescription
                }
            }
            save(current)
            await refresh()
        }
    }

    private func save(_ record: RelocationRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) { records[index] = record }
        message = record.detail
        if !persist() { message += " Cairn could not save its move history." }
    }

    @discardableResult private func persist() -> Bool {
        guard !journalBroken else { return false }
        do {
            try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Array(records.prefix(1_000)))
            try data.write(to: journal, options: .atomic)
            return true
        } catch {
            message = "Cairn could not save its move history: \(error.localizedDescription)"
            return false
        }
    }

    nonisolated static func ownerRunning(_ target: RelocationTarget) -> Bool {
        if target.bundleIDs.contains(where: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }) { return true }
        return target.processNames.contains { name in
            (try? ToolRunner.runExecutable("/usr/bin/pgrep", ["-x", name], timeout: 3))?.ok == true
        }
    }
}

/// Bytes copied so far, shared between the copy and the progress line.
private final class ByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Int64 = 0
    var value: Int64 { lock.lock(); defer { lock.unlock() }; return bytes }
    func set(_ value: Int64) { lock.lock(); bytes = value; lock.unlock() }
}
