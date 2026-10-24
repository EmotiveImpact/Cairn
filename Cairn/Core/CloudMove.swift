import Foundation
import Observation

/// One file or folder of your own copied into a cloud folder. The original
/// stays until the cloud app reports every file uploaded and the original is
/// unchanged since the copy; then it goes to the Bin and the Mac's copy of
/// the cloud version is released, so it lives online only.
struct CloudMoveJob: Codable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable { case uploading, done, stopped }
    var id = UUID()
    var date = Date()
    var source: String
    var destination: String
    var provider: String
    var bytes: Int64
    /// Sizes, dates and file IDs of the original when it was copied.
    var fingerprint: String
    var status: Status
    var detail: String
}

enum CloudMove {
    static let folderName = "Moved by Cairn"

    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }

    /// Only your own files and folders; never app data, apps, libraries or
    /// anything already in a cloud folder. Docker and simulators live in
    /// Library, so they can never be picked.
    static func allowed(_ url: URL, home: URL = FileScan.home) -> Bool {
        RelocationTarget.own(url, home: home) != nil
    }

    /// "~/Films/2019" → "<cloud>/Moved by Cairn/Films/2019".
    static func destination(for source: URL, in cloud: URL, home: URL = FileScan.home) -> URL? {
        let path = source.standardizedFileURL.path, homePath = home.standardizedFileURL.path
        guard SafePaths.isUnder(path, homePath), path != homePath else { return nil }
        return cloud.appendingPathComponent(folderName).appendingPathComponent(String(path.dropFirst(homePath.count + 1)))
    }

    static func fingerprint(_ inventory: Relocation.Inventory) -> String {
        inventory.stamps.keys.sorted().map { key in
            let stamp = inventory.stamps[key]!
            return "\(key)|\(stamp.inode)|\(stamp.size)|\(stamp.modified)"
        }.joined(separator: "\n") + "\n" + inventory.directories.sorted().joined(separator: "\n")
    }

    /// Copies and checks, then hands the copy to the cloud app. The original
    /// is not touched here.
    static func copy(_ source: URL, into cloud: (id: String, name: String, url: URL), home: URL = FileScan.home,
                     cancel: CancelBox = CancelBox(), progress: (Int64) -> Void = { _ in }) throws -> CloudMoveJob {
        guard allowed(source, home: home) else { throw Failure(message: "Only your own files and folders can go to the cloud. App data stays on this Mac or an SSD.") }
        guard Relocation.isRealDirectory(cloud.url), let destination = destination(for: source, in: cloud.url, home: home) else {
            throw Failure(message: "\(cloud.name) is not set up on this Mac.")
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plan = try Relocation.copyTree(from: source, to: destination, cancel: cancel, destinationValid: { Relocation.isRealDirectory(cloud.url) }, progress: progress)
        return CloudMoveJob(source: source.path, destination: destination.path, provider: cloud.name, bytes: plan.bytes,
                            fingerprint: fingerprint(plan), status: .uploading,
                            detail: "Copied and checked. Waiting for \(cloud.name) to upload it.")
    }

    /// True when every file is uploaded, false while any is waiting, nil when
    /// the cloud app does not report it (not a cloud folder).
    static func uploaded(_ url: URL) -> Bool? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isUbiquitousItemKey, .ubiquitousItemIsUploadedKey]
        func check(_ file: URL) -> Bool? {
            guard let values = try? file.resourceValues(forKeys: keys), values.isUbiquitousItem == true else { return nil }
            return values.ubiquitousItemIsUploaded == true
        }
        if Relocation.isRegularFile(url) { return check(url) }
        guard Relocation.isRealDirectory(url), let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return nil }
        for case let file as URL in walker {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            guard let done = check(file) else { return nil }
            if !done { return false }
        }
        return true
    }

    /// One step for a waiting job: once uploaded, and only if the original is
    /// exactly as it was copied, the original goes to the Bin and the Mac's
    /// copy of the cloud version is released.
    static func advance(_ job: CloudMoveJob, now: Date = Date(), isUploaded: (URL) -> Bool? = CloudMove.uploaded,
                        release: ([URL]) -> Void = { _ = CloudSpace.keepOnlineOnly($0) }) -> CloudMoveJob {
        guard job.status == .uploading else { return job }
        var job = job
        let source = URL(fileURLWithPath: job.source), destination = URL(fileURLWithPath: job.destination)
        guard Relocation.exists(destination) else {
            job.status = .stopped; job.detail = "The cloud copy is gone, so the original was kept."; return job
        }
        guard Relocation.exists(source) else {
            job.status = .stopped; job.detail = "The original was moved or removed by someone else. The cloud copy is kept."; return job
        }
        guard isUploaded(destination) == true else {
            // A new file can take a while to be picked up; give up after two weeks.
            if now.timeIntervalSince(job.date) > 14 * 86_400 {
                job.status = .stopped; job.detail = "\(job.provider) has not uploaded this after two weeks, so the original was kept."
            }
            return job
        }
        guard let current = try? Relocation.inventory(source, cancel: CancelBox()), fingerprint(current) == job.fingerprint else {
            job.status = .stopped; job.detail = "The original changed after it was copied, so both are kept."; return job
        }
        do {
            try FileManager.default.trashItem(at: source, resultingItemURL: nil)
        } catch {
            job.status = .stopped; job.detail = "Uploaded, but the original could not go to the Bin: \(error.localizedDescription)"; return job
        }
        release(files(in: destination))
        job.status = .done
        job.detail = "In \(job.provider), online only. The original is in the Bin."
        return job
    }

    static func files(in url: URL) -> [URL] {
        if Relocation.isRegularFile(url) { return [url] }
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
    }
}

/// Cloud moves survive quitting Cairn: the list is saved and each waiting
/// move is checked again whenever Cairn looks.
@MainActor @Observable final class CloudMoveStore {
    static let shared = CloudMoveStore()
    private(set) var jobs: [CloudMoveJob] = []
    private(set) var busy = false
    private(set) var message = ""
    private var loaded = false
    private let journal: URL

    init(journal: URL = FileScan.home.appendingPathComponent("Library/Application Support/Cairn/cloud-moves.json")) {
        self.journal = journal
    }

    var waiting: [CloudMoveJob] { jobs.filter { $0.status == .uploading } }

    func load() {
        guard !loaded else { return }
        loaded = true
        guard Relocation.isRegularFile(journal), let data = try? Data(contentsOf: journal), data.count <= 4 << 20,
              let decoded = try? JSONDecoder().decode([CloudMoveJob].self, from: data) else { return }
        jobs = decoded
    }

    func move(_ sources: [URL], to cloud: (id: String, name: String, url: URL)) async {
        load()
        guard !busy else { message = "Cairn is already copying to the cloud."; return }
        busy = true
        defer { busy = false }
        for source in sources {
            let result = await Task.detached(priority: .utility) { () -> Result<CloudMoveJob, Error> in
                Result { try CloudMove.copy(source, into: cloud) }
            }.value
            switch result {
            case .success(let job): jobs.insert(job, at: 0); message = job.detail
            case .failure(let error): message = error.localizedDescription
            }
            save()
        }
        await check()
    }

    /// Looks at every waiting move once.
    func check() async {
        load()
        let waiting = waiting
        guard !waiting.isEmpty else { return }
        let updated = await Task.detached(priority: .utility) { waiting.map { CloudMove.advance($0) } }.value
        for job in updated { if let index = jobs.firstIndex(where: { $0.id == job.id }) { jobs[index] = job } }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Array(jobs.prefix(1_000))) else { return }
        try? FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: journal, options: .atomic)
    }
}
