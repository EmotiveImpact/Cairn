import Foundation
import Observation
import CryptoKit
import AppKit

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
    /// Size of a single copy (all copies are identical) — what one extra copy costs.
    var copySize: Int64 { files.first?.size ?? 0 }
    /// Space freed if every non-keeper is removed.
    var reclaimableSize: Int64 { Int64(max(0, count - 1)) * copySize }
    var keeper: DupFile? { files.first { $0.isKeeper } }
    /// Representative file for the thumbnail (the keeper, else the first copy).
    var representativeURL: URL? { (keeper ?? files.first)?.url }
}

// MARK: - Hashing helper

/// Streamed content fingerprinting. Reads in 1 MB chunks so multi-GB files never
/// load whole into memory. Very large files (> 200 MB) are fingerprinted by their
/// size + first 4 MB + last 4 MB (a fast, collision-safe-enough heuristic for the
/// purpose of *candidate* matching — a full byte-compare could be layered later).
enum DupHash {
    static let chunk = 1 << 20            // 1 MB
    static let bigFileThreshold: Int64 = 200 << 20   // 200 MB
    static let edgeBytes = 4 << 20         // 4 MB head + 4 MB tail

    /// SHA-256 hex digest, or `nil` if the file can't be opened / the task is cancelled.
    static func fingerprint(_ url: URL, size: Int64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()

        if size > bigFileThreshold {
            // Fast path: size + head + tail.
            withUnsafeBytes(of: size.littleEndian) { hasher.update(bufferPointer: $0) }
            if let head = try? handle.read(upToCount: edgeBytes) { hasher.update(data: head) }
            if (try? handle.seek(toOffset: UInt64(max(0, size - Int64(edgeBytes))))) != nil,
               let tail = try? handle.read(upToCount: edgeBytes) {
                hasher.update(data: tail)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }

        // Full streamed digest.
        while !Task.isCancelled {
            guard let data = try? handle.read(upToCount: chunk), !data.isEmpty else { break }
            hasher.update(data: data)
        }
        if Task.isCancelled { return nil }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
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
    var sortOrder: SortOrder = .size
    var searchQuery: String = ""

    // Tuning / bounds
    private let minSize: Int64 = 1 << 20          // 1 MB floor
    private let candidateCap = 20_000             // never hash more than this many files
    private let skipDirNames: Set<String> = ["node_modules", "Library", ".git", ".Trash"]

    nonisolated(unsafe) private var scanTask: Task<Void, Never>?

    deinit { scanTask?.cancel() }

    var isScanning: Bool { phase == .scanning }
    var hasScanned: Bool { phase == .finished || phase == .cancelled }

    // MARK: Derived stats
    var groupCount: Int { groups.count }
    /// Mockup "duplicate files" = every redundant copy (all copies minus one keeper per group).
    var duplicateFileCount: Int { groups.reduce(0) { $0 + max(0, $1.count - 1) } }
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
        cancel()
        groups = []
        hashedCount = 0
        candidateCount = 0
        phase = .idle
        start()
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        if phase == .scanning { phase = .cancelled }
    }

    private func start() {
        phase = .scanning
        progressText = "Scanning folders…"
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
            let result = await Self.findDuplicates(
                roots: roots, minSize: minSize, cap: cap, skipDirNames: skip,
                onProgress: { hashed, candidates in
                    guard throttle.shouldPublish() else { return }
                    Task { @MainActor [weak self] in
                        self?.hashedCount = hashed
                        self?.candidateCount = candidates
                        self?.progressText = "Hashing \(hashed) of \(candidates) candidate files…"
                    }
                }
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                if Task.isCancelled { self.phase = .cancelled; return }
                self.groups = result
                self.phase = .finished
                self.progressText = ""
            }
        }
    }

    // MARK: Selection

    func toggle(_ copyID: UUID) {
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
        guard let gi = groups.firstIndex(where: { $0.id == groupID }) else { return }
        for fi in groups[gi].files.indices {
            let isNew = groups[gi].files[fi].id == copyID
            groups[gi].files[fi].isKeeper = isNew
            if isNew { groups[gi].files[fi].selected = false }
        }
    }

    /// Keep the recommended (canonical/oldest) copy, stage all others for removal.
    func keepBest(_ groupID: UUID) {
        guard let gi = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let keeperID = Self.recommendedKeeperID(groups[gi].files)
        for fi in groups[gi].files.indices {
            let keep = groups[gi].files[fi].id == keeperID
            groups[gi].files[fi].isKeeper = keep
            groups[gi].files[fi].selected = !keep
        }
    }

    /// Select every non-keeper copy across all groups.
    func autoSelectRecommended() {
        for gi in groups.indices {
            for fi in groups[gi].files.indices {
                groups[gi].files[fi].selected = !groups[gi].files[fi].isKeeper
            }
        }
    }

    func clearSelection() {
        for gi in groups.indices {
            for fi in groups[gi].files.indices { groups[gi].files[fi].selected = false }
        }
    }

    func revealSelectedInFinder() {
        let urls = groups.flatMap { $0.files }.filter { $0.selected }.map { $0.resolvedURL }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    // MARK: Removal (recoverable — Trash only)

    struct RemovalResult { var trashed = 0; var failed = 0; var bytes: Int64 = 0; var errors: [String] = [] }

    /// Trash every selected (non-keeper) copy via `FileManager.trashItem` (recoverable),
    /// then drop emptied groups and groups that fall below 2 copies.
    @discardableResult
    func removeSelected() -> RemovalResult {
        var result = RemovalResult()
        let fm = FileManager.default

        for gi in groups.indices {
            let group = groups[gi]
            let toRemove = group.files.filter { $0.selected && !$0.isKeeper }
            let toKeep = group.files.filter { !($0.selected && !$0.isKeeper) }
            guard !toRemove.isEmpty else { continue }

            // CRITICAL SAFETY: never trash every copy — at least one must remain on
            // disk. Guards the case where no keeper is set or the keeper is gone.
            guard toKeep.contains(where: { FileScan.exists($0.resolvedURL) }) else {
                result.failed += toRemove.count
                result.errors.append("\(group.name): kept — removing these would leave no surviving copy")
                continue
            }

            var survivors = toKeep
            for file in toRemove {
                guard FileScan.exists(file.resolvedURL) else { result.bytes += file.size; continue } // already gone
                // Defense-in-depth: never trash a system path or anything inside a
                // photo library, even if it somehow matched. (We deliberately DON'T
                // apply the cleaner's Documents denylist here — deduping the user's
                // own Documents/Pictures is exactly what they asked for.)
                let p = file.resolvedURL.resolvingSymlinksInPath().standardizedFileURL.path
                let systemProtected = SafePaths.denyAbsolutePrefixes.contains { p == $0 || p.hasPrefix($0 + "/") }
                    || SafePaths.denyComponents.contains { p.contains($0) }
                guard !systemProtected else {
                    result.failed += 1
                    result.errors.append("\(file.name): blocked by safety policy")
                    survivors.append(file)
                    continue
                }
                do {
                    try fm.trashItem(at: file.resolvedURL, resultingItemURL: nil)
                    result.trashed += 1
                    result.bytes += file.size
                } catch {
                    result.failed += 1
                    result.errors.append("\(file.name): \((error as NSError).localizedDescription)")
                    survivors.append(file)
                }
            }
            groups[gi].files = survivors
        }
        // Drop groups that no longer have at least 2 copies.
        groups.removeAll { $0.count < 2 }
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

    private nonisolated static func findDuplicates(
        roots: [URL],
        minSize: Int64,
        cap: Int,
        skipDirNames: Set<String>,
        onProgress: @escaping (_ hashed: Int, _ candidates: Int) -> Void
    ) async -> [DupGroup] {

        // Pass 1 — bounded walk, bucket candidates by exact byte size.
        struct Candidate { let url: URL; let size: Int64; let modified: Date; let volume: URL? }
        var bySize: [Int64: [Candidate]] = [:]
        // Cap Pass-1 retention so a media-heavy home can't balloon `bySize`.
        let walkCap = 300_000
        var appended = 0
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey,
                                         .isUbiquitousItemKey, .fileSizeKey, .totalFileAllocatedSizeKey,
                                         .contentModificationDateKey, .volumeURLKey, .isPackageKey]

        outer: for root in roots {
            if Task.isCancelled { return [] }
            guard let en = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys),
                                         options: [], errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in en {
                if Task.isCancelled { return [] }
                var stop = false
                autoreleasepool {   // keep RAM flat while walking huge media folders
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
                    let size = Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
                    guard size >= minSize else { return }
                    // Defer resolvingSymlinksInPath() to Pass-2 — only the handful of
                    // files that land in a duplicate group need a resolved URL.
                    bySize[size, default: []].append(Candidate(
                        url: url, size: size,
                        modified: v.contentModificationDate ?? .distantPast, volume: v.volume))
                    appended += 1
                    if appended >= walkCap { stop = true }
                }
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
            if Task.isCancelled { return groups }
            if hashed >= cap { break }
            var byHash: [String: [Candidate]] = [:]
            for cand in cluster {
                if Task.isCancelled { return groups }
                if hashed >= cap { break }
                guard let h = DupHash.fingerprint(cand.url, size: cand.size) else { continue }
                hashed += 1
                if hashed % 64 == 0 { onProgress(hashed, totalCandidates) }
                byHash[h, default: []].append(cand)
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
        return groups
    }
}
