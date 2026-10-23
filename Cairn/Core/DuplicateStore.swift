import Foundation
import Observation
import CryptoKit
import AppKit
import Darwin

/// Rate-limits background progress callbacks so they can't flood the main actor.
/// Called from the scanning thread; cheap and lock-guarded.
final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last: TimeInterval = 0
    private let interval: TimeInterval

    init(interval: TimeInterval = 0.12) { self.interval = interval }

    func shouldPublish() -> Bool {
        let now = Date.timeIntervalSinceReferenceDate
        lock.lock(); defer { lock.unlock() }
        guard now - last >= interval else { return false }
        last = now
        return true
    }
}

// MARK: - Models

/// One physical copy of a file inside a duplicate group.
struct DupFile: Identifiable {
    let id = UUID()
    var url: URL
    var resolvedURL: URL
    var size: Int64
    var modified: Date
    var volumeURL: URL?
    var isKeeper: Bool = false
    var selected: Bool = false

    var name: String { url.lastPathComponent }
}

/// A set of >= 2 byte-identical files. Exactly one copy is the `keeper`.
struct DupGroup: Identifiable {
    let id = UUID()
    var name: String          // representative file name
    var hash: String          // content fingerprint shared by all copies
    var files: [DupFile]

    var count: Int { files.count }
    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
    /// Logical file size of a copy, not independently allocated disk blocks.
    var copySize: Int64 { files.first?.size ?? 0 }
    /// Combined logical file sizes of non-keepers. Trash and shared blocks mean
    /// this must never be presented as an immediate free-space estimate.
    var reclaimableSize: Int64 { Int64(max(0, count - 1)) * copySize }
    var keeper: DupFile? { files.first { $0.isKeeper } }
    /// Representative file for the thumbnail (the keeper, else the first copy).
    var representativeURL: URL? { (keeper ?? files.first)?.url }
}

// MARK: - Hashing helper

/// Full streamed SHA-256. Even large files must be read in their entirety: matching
/// edges do not prove that the middle of two files is identical.
enum DupHash {
    static let chunk = 1 << 20            // 1 MB

    struct Identity: Equatable, Sendable {
        let device: UInt64
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64
    }

    struct Fingerprint: Sendable {
        let digest: String
        let identity: Identity
    }

    private static func identity(_ info: stat) -> Identity {
        Identity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino),
                 size: Int64(info.st_size),
                 modifiedSeconds: Int64(info.st_mtimespec.tv_sec),
                 modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
                 changedSeconds: Int64(info.st_ctimespec.tv_sec),
                 changedNanoseconds: Int64(info.st_ctimespec.tv_nsec))
    }

    /// lstat refuses a newly substituted symlink instead of following it.
    private static func pathIdentity(_ url: URL) -> Identity? {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (info.st_mode & 0o170000) == 0o100000 else { return nil }
        return identity(info)
    }

    static func unchanged(_ url: URL, since fingerprint: Fingerprint) -> Bool {
        pathIdentity(url) == fingerprint.identity
    }

    /// Returns nil if the file changes while read, cannot be read, or work is cancelled.
    static func fingerprint(_ url: URL, shouldCancel: () -> Bool = { false }) -> Fingerprint? {
        guard let before = pathIdentity(url) else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var opened = stat()
        guard fstat(handle.fileDescriptor, &opened) == 0,
              identity(opened) == before else { return nil }
        var hasher = SHA256()
        var readBytes: Int64 = 0
        do {
            while true {
                if Task.isCancelled || shouldCancel() { return nil }
                // FileHandle bridges autoreleased NSData. A Swift loop scope
                // alone does not release those buffers on a long-lived worker.
                let count = try autoreleasepool { () -> Int in
                    guard let data = try handle.read(upToCount: chunk), !data.isEmpty else { return 0 }
                    hasher.update(data: data)
                    return data.count
                }
                if count == 0 { break }
                readBytes += Int64(count)
            }
        } catch {
            return nil
        }
        var ended = stat()
        guard !Task.isCancelled, readBytes == before.size,
              fstat(handle.fileDescriptor, &ended) == 0,
              identity(ended) == before,
              pathIdentity(url) == before else { return nil }
        return Fingerprint(digest: hasher.finalize().map { String(format: "%02x", $0) }.joined(),
                           identity: before)
    }
}

/// Immutable removal plan passed off the main actor. A fresh full hash of the
/// chosen keeper and each selected copy is required before each Trash move.
private struct DupRemovalFile: Sendable {
    let id: UUID
    let url: URL
    let resolvedURL: URL
    let estimatedBytes: Int64
}

private struct DupRemovalPlan: Sendable {
    let name: String
    let scannedDigest: String
    let keeper: DupRemovalFile?
    let selected: [DupRemovalFile]
}

private struct DupRemovalBatch: Sendable {
    var trashed = 0
    var failed = 0
    var bytes: Int64 = 0
    var errors: [String] = []
    var removedIDs: Set<UUID> = []
    var history: [ScanStore.RemovalLogEntry] = []
}

private enum DupRemovalEngine {
    private static let permittedRoots = ["Downloads", "Documents", "Desktop", "Pictures", "Movies"]
        .map { FileScan.home.appendingPathComponent($0).resolvingSymlinksInPath().standardizedFileURL.path }

    /// Duplicate removal needs Documents/Pictures, so it cannot use SafePaths'
    /// general cleaner rule (which deliberately forbids Documents). Apply the
    /// shared session guard and every applicable system/user exclusion here.
    private static func permitted(_ file: DupRemovalFile, excludedPaths: [String]) -> Bool {
        let original = file.url.standardizedFileURL
        let resolved = file.url.resolvingSymlinksInPath().standardizedFileURL
        let path = resolved.path
        guard resolved == file.resolvedURL.standardizedFileURL,
              SafePaths.protectedSessionReason(original) == nil,
              SafePaths.protectedSessionReason(resolved) == nil,
              permittedRoots.contains(where: { root in
                  SafePaths.isUnder(original.path, root) && original.path != root
                      && SafePaths.isUnder(path, root) && path != root
              }),
              !SafePaths.denyAbsolutePrefixes.contains(where: { SafePaths.isUnder(path, $0) }),
              !SafePaths.denyComponents.contains(where: { denied in
                  resolved.pathComponents.contains { $0.lowercased().hasSuffix(denied.lowercased()) }
              }),
              !excludedPaths.contains(where: { excluded in
                  SafePaths.isUnder(original.path, excluded) || SafePaths.isUnder(path, excluded)
              }) else { return false }
        return true
    }

    static func run(_ plans: [DupRemovalPlan], excludedPaths: [String]) -> DupRemovalBatch {
        var result = DupRemovalBatch()
        let fm = FileManager.default

        for plan in plans {
            if Task.isCancelled { break }
            guard let keeper = plan.keeper, permitted(keeper, excludedPaths: excludedPaths),
                  let keeperHash = DupHash.fingerprint(keeper.url),
                  keeperHash.digest == plan.scannedDigest else {
                result.failed += plan.selected.count
                result.errors.append("\(plan.name): keeper changed or is protected — rescan before removal")
                continue
            }

            for file in plan.selected {
                if Task.isCancelled { break }
                guard FileScan.exists(file.url) else {
                    // The copy vanished independently; remove the stale row, but
                    // never report its bytes as reclaimed by Cairn.
                    result.removedIDs.insert(file.id)
                    continue
                }
                guard permitted(file, excludedPaths: excludedPaths), file.url != keeper.url,
                      let copyHash = DupHash.fingerprint(file.url),
                      copyHash.digest == plan.scannedDigest,
                      DupHash.unchanged(keeper.url, since: keeperHash),
                      DupHash.unchanged(file.url, since: copyHash),
                      permitted(keeper, excludedPaths: excludedPaths),
                      permitted(file, excludedPaths: excludedPaths) else {
                    result.failed += 1
                    result.errors.append("\(file.url.lastPathComponent): changed, protected, or no verified keeper — rescan")
                    continue
                }
                guard let actionID = ActionJournal.shared.begin(path: file.url.path, category: "duplicates", affectedBytes: file.estimatedBytes) else {
                    result.failed += 1
                    result.errors.append(ActionJournal.shared.error ?? "Action intent could not be recorded; duplicate removal stopped")
                    return result
                }
                do {
                    var trashedURL: NSURL?
                    try fm.trashItem(at: file.url, resultingItemURL: &trashedURL)
                    result.history.append(ScanStore.RemovalLogEntry(id: actionID, name: file.url.lastPathComponent, originalPath: file.url.path, trashPath: (trashedURL as URL?)?.path, bytes: file.estimatedBytes, date: Date(), category: "duplicates"))
                    result.trashed += 1
                    result.bytes += file.estimatedBytes
                    result.removedIDs.insert(file.id)
                    guard ActionJournal.shared.finish(actionID, succeeded: true, trashPath: (trashedURL as URL?)?.path) else {
                        result.failed += 1
                        result.errors.append(ActionJournal.shared.error ?? "Action outcome could not be recorded; duplicate removal stopped")
                        return result
                    }
                } catch {
                    result.failed += 1
                    result.errors.append("\(file.url.lastPathComponent): \((error as NSError).localizedDescription)")
                    guard ActionJournal.shared.finish(actionID, succeeded: false, trashPath: nil, detail: error.localizedDescription) else {
                        result.errors.append(ActionJournal.shared.error ?? "Action outcome could not be recorded; duplicate removal stopped")
                        return result
                    }
                }
            }
        }
        if Task.isCancelled { result.errors.append("Duplicate removal stopped; remaining copies were left in place") }
        return result
    }
}

// MARK: - Store

/// Self-contained, on-demand duplicate finder. Mirrors `ScanStore`'s lifecycle but
/// is NOT registered with the shared `ScannerRegistry` — it runs only when the
/// Duplicates screen appears, so it never pollutes Smart Scan totals. Two-pass:
/// group candidates by exact byte size, then SHA-256-verify multi-file clusters
/// off the main actor. Cancellable, bounded, and conservative.
@MainActor
@Observable
final class DuplicateStore {
    var beginReceipt: (() async -> CleanupRun?)?
    var finishReceipt: ((CleanupRun, ScanStore.CleanSummary) async -> Bool)?
    var onRemovals: (([ScanStore.RemovalLogEntry]) async -> Bool)?
    var prepareRemoval: () async -> Bool = { false }

    enum Phase: Equatable { case idle, scanning, finished, cancelled }
    enum SortOrder: String, CaseIterable, Identifiable {
        case size = "Size", count = "Count", name = "Name", newest = "Newest"
        var id: String { rawValue }
    }

    // Observable state
    private(set) var phase: Phase = .idle
    private(set) var groups: [DupGroup] = []
    private(set) var hashedCount: Int = 0
    private(set) var candidateCount: Int = 0
    private(set) var progressText: String = ""
    private(set) var wasLimited = false
    private(set) var isRemoving = false
    var sortOrder: SortOrder = .size
    var searchQuery: String = ""

    // Tuning / bounds
    private let minSize: Int64 = 1 << 20          // 1 MB floor
    private let candidateCap = 20_000             // never hash more than this many files
    private let skipDirNames: Set<String> = ["node_modules", "Library", ".git", ".Trash"]

    nonisolated(unsafe) private var scanTask: Task<Void, Never>?
    private var scanGeneration = UUID()

    deinit { scanTask?.cancel() }

    var isScanning: Bool { phase == .scanning }
    var hasScanned: Bool { phase == .finished || phase == .cancelled }

    // MARK: Derived stats
    /// Historical property name; this is extra-copy file size, not capacity gain.
    var reclaimableBytes: Int64 { groups.reduce(0) { $0 + $1.reclaimableSize } }
    var selectedCopyCount: Int { groups.reduce(0) { $0 + $1.files.lazy.filter { $0.selected }.count } }
    var selectedBytes: Int64 {
        groups.reduce(0) { acc, g in acc + g.files.lazy.filter { $0.selected }.reduce(0) { $0 + $1.size } }
    }

    /// Filtered + sorted groups for display.
    var visibleGroups: [DupGroup] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        var list = groups
        if !q.isEmpty {
            list = list.filter { g in
                g.name.localizedCaseInsensitiveContains(q)
                || g.files.contains { $0.url.path.localizedCaseInsensitiveContains(q) }
            }
        }
        switch sortOrder {
        case .size:   list.sort { $0.reclaimableSize > $1.reclaimableSize }
        case .count:  list.sort { $0.count > $1.count }
        case .name:   list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .newest: list.sort { ($0.keeper?.modified ?? .distantPast) > ($1.keeper?.modified ?? .distantPast) }
        }
        // Render a page at a time. Each group card is a heavy view (thumbnail,
        // pills, buttons); handing SwiftUI thousands at once stalled layout even
        // inside a LazyVStack. Sorted biggest-first, so page 1 is the useful page.
        return Array(list.prefix(visibleLimit))
    }

    /// How many groups are currently rendered, and how many exist in total.
    private(set) var visibleLimit = 120
    var matchingGroupCount: Int {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return groups.count }
        return groups.filter { g in
            g.name.localizedCaseInsensitiveContains(q)
            || g.files.contains { $0.url.path.localizedCaseInsensitiveContains(q) }
        }.count
    }
    var hasMoreGroups: Bool { matchingGroupCount > visibleLimit }
    func showMoreGroups() { visibleLimit += 120 }

    // MARK: Roots (bounded set of user dirs)
    private var roots: [URL] {
        let h = FileScan.home
        return ["Downloads", "Documents", "Desktop", "Pictures", "Movies"]
            .map { h.appendingPathComponent($0) }
            .filter { FileScan.exists($0) }
    }

    // MARK: Lifecycle

    /// Lazy entry point — safe to call repeatedly; only the first run does work.
    func startIfNeeded() {
        guard phase == .idle else { return }
        start()
    }

    func rescan() {
        guard !isRemoving else { return }
        cancel()
        groups = []
        hashedCount = 0
        candidateCount = 0
        phase = .idle
        start()
    }

    func cancel() {
        scanGeneration = UUID()
        scanTask?.cancel()
        scanTask = nil
        if phase == .scanning { phase = .cancelled }
    }

    func cancelAndWait() async {
        let worker = scanTask
        cancel()
        await worker?.value
    }

    private func start() {
        phase = .scanning
        wasLimited = false
        progressText = "Waiting for other disk work to finish…"
        let generation = UUID()
        scanGeneration = generation
        let roots = self.roots
        let minSize = self.minSize
        let cap = self.candidateCap
        let skip = self.skipDirNames

        // Progress arrives thousands of times per scan. Hopping to the main actor
        // for each one queued a flood of Tasks that each wrote three @Observable
        // properties — every write invalidated the view graph, and every re-render
        // re-sorted the whole group list. That storm is what pegged the main
        // thread at 100% and made this page look like a crash. Publish ~8×/sec.
        let throttle = ProgressThrottle()

        // Detached + .utility: this Task was previously created from the @MainActor
        // context, so the walk/hash work inherited main-actor isolation and
        // user-initiated priority — it starved the UI and froze navigation for the
        // whole scan. Detaching guarantees it runs off-main, below the UI.
        scanTask = Task.detached(priority: .utility) { [weak self] in
            guard await ScanGate.shared.acquire(.duplicates) else { return }
            defer { ScanGate.shared.release() }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard self?.scanGeneration == generation else { return }
                self?.progressText = "Scanning folders…"
            }
            let result = await Self.findDuplicates(
                roots: roots, minSize: minSize, cap: cap, skipDirNames: skip,
                onProgress: { hashed, candidates in
                    guard throttle.shouldPublish() else { return }
                    Task { @MainActor [weak self] in
                        guard self?.scanGeneration == generation else { return }
                        self?.hashedCount = hashed
                        self?.candidateCount = candidates
                        self?.progressText = "Hashing \(hashed) of \(candidates) candidate files…"
                    }
                }
            )
            await MainActor.run { [weak self] in
                guard let self, self.scanGeneration == generation else { return }
                if Task.isCancelled { self.phase = .cancelled; return }
                self.groups = result.groups
                self.wasLimited = result.limited
                self.phase = .finished
                self.progressText = result.limited ? "Comparison reached its safety limit. Results cover only the files checked." : ""
            }
        }
    }

    // MARK: Selection

    func toggle(_ copyID: UUID) {
        guard !isRemoving else { return }
        for gi in groups.indices {
            if let fi = groups[gi].files.firstIndex(where: { $0.id == copyID }) {
                if groups[gi].files[fi].isKeeper { return }   // can't stage the keeper
                groups[gi].files[fi].selected.toggle()
                return
            }
        }
    }

    /// Make `copyID` the keeper of its group; clear that copy's selection.
    func setKeeper(_ copyID: UUID, in groupID: UUID) {
        guard !isRemoving else { return }
        guard let gi = groups.firstIndex(where: { $0.id == groupID }) else { return }
        for fi in groups[gi].files.indices {
            let isNew = groups[gi].files[fi].id == copyID
            groups[gi].files[fi].isKeeper = isNew
            if isNew { groups[gi].files[fi].selected = false }
        }
    }

    /// Select every non-keeper copy across all groups.
    func autoSelectRecommended() {
        guard !isRemoving else { return }
        for gi in groups.indices {
            for fi in groups[gi].files.indices {
                groups[gi].files[fi].selected = !groups[gi].files[fi].isKeeper
            }
        }
    }

    func clearSelection() {
        guard !isRemoving else { return }
        for gi in groups.indices {
            for fi in groups[gi].files.indices { groups[gi].files[fi].selected = false }
        }
    }

    // MARK: Removal (recoverable — Trash only)

    struct RemovalResult { var trashed = 0; var failed = 0; var bytes: Int64 = 0; var errors: [String] = []; var capacityChanges: [CleanupCapacityChange] = []; var recordedRecoveries = 0 }

    /// Rehash the keeper and selected files off-main before each recoverable Trash
    /// move. A scan result is never enough evidence to remove a possibly changed file.
    @discardableResult
    func removeSelected() async -> RemovalResult {
        guard await prepareRemoval() else { return RemovalResult(trashed: 0, failed: 1, bytes: 0, errors: ["Recovery history is unavailable. Nothing was removed."]) }
        guard await Task.detached(priority: .utility, operation: { ActionJournal.shared.prepare() }).value else {
            return RemovalResult(trashed: 0, failed: 1, bytes: 0, errors: [ActionJournal.shared.error ?? "Action journal unavailable. Nothing was removed."])
        }
        guard !isRemoving else {
            return RemovalResult(trashed: 0, failed: 1, bytes: 0,
                                 errors: ["Duplicate removal is already running"])
        }
        let plans: [DupRemovalPlan] = groups.compactMap { group in
            let selected = group.files.filter { $0.selected && !$0.isKeeper }
            guard !selected.isEmpty else { return nil }
            func planned(_ file: DupFile) -> DupRemovalFile {
                DupRemovalFile(id: file.id, url: file.url, resolvedURL: file.resolvedURL,
                               estimatedBytes: file.size)
            }
            let keeper = group.files.first { $0.isKeeper && !$0.selected }.map(planned)
            return DupRemovalPlan(name: group.name, scannedDigest: group.hash,
                                  keeper: keeper, selected: selected.map(planned))
        }
        guard !plans.isEmpty else { return RemovalResult() }
        isRemoving = true
        defer { isRemoving = false }
        guard await ScanGate.shared.acquire(.removeDuplicates) else { return RemovalResult() }
        defer { ScanGate.shared.release() }
        guard let run = await beginReceipt?() else { return RemovalResult(failed: plans.reduce(0) { $0 + $1.selected.count }, errors: ["Cleanup receipt could not be prepared. No duplicate was removed."]) }
        let capacityWindow = await CleanupCapacityWindow.begin(urls: plans.flatMap { $0.selected.map(\.url) })
        let excludedPaths = SafePaths.userExcluded
        let worker = Task.detached(priority: .utility) {
            DupRemovalEngine.run(plans, excludedPaths: excludedPaths)
        }
        let batch = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        for gi in groups.indices {
            groups[gi].files.removeAll { batch.removedIDs.contains($0.id) }
        }
        // Drop groups that no longer have at least 2 copies.
        groups.removeAll { $0.count < 2 }
        let logged = await onRemovals?(batch.history) ?? batch.history.isEmpty
        var result = RemovalResult(trashed: batch.trashed, failed: batch.failed + (logged ? 0 : 1),
                             bytes: batch.bytes, errors: batch.errors + (logged ? [] : ["Recovery history could not be saved. Action journal retains the paths; further cleanup is blocked."]),
                             capacityChanges: await capacityWindow.finish(), recordedRecoveries: logged ? batch.history.filter { $0.trashPath != nil }.count : 0)
        let receipt = ScanStore.CleanSummary.specialist(history: batch.history, failed: result.failed, errors: result.errors,
            capacity: result.capacityChanges, logged: logged, interrupted: Task.isCancelled || !logged)
        if await finishReceipt?(run, receipt) != true { result.failed += 1; result.errors.append("The complete receipt could not be saved. Recovery records remain available.") }
        return result
    }

    // MARK: Keeper policy

    /// "Keep best": prefer the most canonical location, then the oldest (original)
    /// file. Canonical preference: ~/Documents, ~/Pictures, ~/Movies over Downloads/Desktop.
    nonisolated static func recommendedKeeperID(_ files: [DupFile]) -> UUID? {
        guard !files.isEmpty else { return nil }
        func rank(_ f: DupFile) -> Int {
            let p = f.url.path
            if p.contains("/Documents/") { return 0 }
            if p.contains("/Pictures/") { return 1 }
            if p.contains("/Movies/") { return 2 }
            if p.contains("/Desktop/") { return 3 }
            return 4   // Downloads / elsewhere
        }
        return files.min { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return a.modified < b.modified   // oldest wins (the original)
        }?.id
    }

    // MARK: Engine (off the main actor)

    struct Discovery {
        var groups: [DupGroup]
        var limited: Bool
    }
    nonisolated static func findDuplicates(
        roots: [URL],
        minSize: Int64,
        cap: Int,
        skipDirNames: Set<String>,
        onProgress: @escaping (_ hashed: Int, _ candidates: Int) -> Void
    ) async -> Discovery {

        // Pass 1 — bounded walk, bucket candidates by exact byte size.
        struct Candidate { let url: URL; let size: Int64; let modified: Date; let volume: URL? }
        var bySize: [Int64: [Candidate]] = [:]
        // Cap Pass-1 retention so a media-heavy home can't balloon `bySize`.
        let walkCap = cap
        var appended = 0
        var examined = 0
        var limited = false
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey,
                                         .isUbiquitousItemKey, .fileSizeKey, .totalFileAllocatedSizeKey,
                                         .contentModificationDateKey, .volumeURLKey, .isPackageKey]

        outer: for root in roots {
            if Task.isCancelled { return Discovery(groups: [], limited: true) }
            guard let en = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys),
                                         options: [], errorHandler: { _, _ in true }) else { continue }
            while true {
                if Task.isCancelled { return Discovery(groups: [], limited: true) }
                var stop = false
                var ended = false
                autoreleasepool {   // keep RAM flat while walking huge media folders
                    guard let url = en.nextObject() as? URL else { ended = true; return }
                    examined += 1
                    if examined > 300_000 { stop = true; limited = true; return }
                    guard let v = try? url.resourceValues(forKeys: keys) else { return }
                    if v.isSymbolicLink == true { en.skipDescendants(); return }
                    if v.isUbiquitousItem == true { en.skipDescendants(); return }   // iCloud stub
                    // Skip opaque bundles (.app / .photoslibrary / packages) and noise dirs.
                    if v.isDirectory == true {
                        let n = url.lastPathComponent
                        if v.isPackage == true || n.hasSuffix(".app") || n.contains(".photoslibrary")
                            || n.contains(".photolibrary") || skipDirNames.contains(n) {
                            en.skipDescendants()
                        }
                        return
                    }
                    guard v.isRegularFile == true else { return }
                    let size = Int64(v.fileSize ?? 0)
                    guard size >= minSize else { return }
                    // Defer resolvingSymlinksInPath() to Pass-2 — only the handful of
                    // files that land in a duplicate group need a resolved URL.
                    bySize[size, default: []].append(Candidate(
                        url: url, size: size,
                        modified: v.contentModificationDate ?? .distantPast, volume: v.volume))
                    appended += 1
                    if appended >= walkCap { stop = true; limited = true }
                }
                if ended { break }
                if stop { break outer }   // retention cap hit — verify what we have
            }
        }

        // Only size-clusters with >1 file are duplicate candidates. Cap the work.
        var clusters = bySize.values.filter { $0.count > 1 }
        // Sort biggest-first. Uses optional access: force-unwrapping `first!` would
        // trap if a cluster were ever empty.
        clusters.sort { ($0.first?.size ?? 0) > ($1.first?.size ?? 0) }
        let totalCandidates = min(cap, clusters.reduce(0) { $0 + $1.count })
        onProgress(0, totalCandidates)

        // Pass 2 — SHA-256 verify, group by digest.
        var groups: [DupGroup] = []
        var hashed = 0
        for cluster in clusters {
            if Task.isCancelled { return Discovery(groups: groups, limited: true) }
            if hashed >= cap { break }
            var byHash: [String: [Candidate]] = [:]
            for cand in cluster {
                if Task.isCancelled { return Discovery(groups: groups, limited: true) }
                if hashed >= cap { break }
                guard let h = DupHash.fingerprint(cand.url) else { continue }
                hashed += 1
                if hashed % 64 == 0 { onProgress(hashed, totalCandidates) }
                byHash[h.digest, default: []].append(cand)
            }
            for (hash, members) in byHash where members.count > 1 {
                var files = members.map {
                    DupFile(url: $0.url, resolvedURL: $0.url.resolvingSymlinksInPath(), size: $0.size,
                            modified: $0.modified, volumeURL: $0.volume)
                }
                if let keeperID = recommendedKeeperID(files) {
                    for i in files.indices {
                        files[i].isKeeper = (files[i].id == keeperID)
                        files[i].selected = false   // never pre-select; user opts in
                    }
                }
                files.sort { a, b in
                    if a.isKeeper != b.isKeeper { return a.isKeeper }   // keeper first
                    return a.modified > b.modified
                }
                groups.append(DupGroup(name: files.first?.name ?? "File",
                                       hash: hash, files: files))
            }
        }
        onProgress(hashed, totalCandidates)
        return Discovery(groups: groups, limited: limited)
    }
}
