import Foundation
import Observation

/// The app's central state. Runs scanners concurrently, streams items in for the
/// live "items appear as found" animation, aggregates per-category + grand
/// totals, and performs cleans through the safety chokepoint.
@MainActor
@Observable
final class ScanStore {
    enum Phase: Equatable { case idle, scanning, finished, cancelled }

    struct Bucket: Identifiable {
        let info: CategoryInfo
        private(set) var items: [ScanItem] = []
        var complete: Bool = false
        var progress: String = ""
        var id: String { info.id }

        /// Running byte total. `totalSize` is read from dozens of view sites on
        /// every redraw; summing all items each time made live scans crawl, so the
        /// total is maintained incrementally as items are added/removed.
        private var runningTotal: Int64 = 0
        var totalSize: Int64 { runningTotal }

        init(info: CategoryInfo) { self.info = info }

        /// Selection only — never changes the byte total.
        mutating func setSelected(at index: Int, _ value: Bool) {
            items[index].selected = value
        }
        mutating func toggleSelected(at index: Int) {
            items[index].selected.toggle()
        }

        mutating func append(_ item: ScanItem) {
            items.append(item)
            runningTotal += item.allocatedSize
        }
        mutating func removeItems(where shouldRemove: (ScanItem) -> Bool) {
            items.removeAll(where: shouldRemove)
            runningTotal = items.reduce(0) { $0 + $1.allocatedSize }
        }
        mutating func sortBySizeDescending() {
            items.sort { $0.allocatedSize > $1.allocatedSize }
        }
        /// Mutate one item in place (selection), keeping the total correct.
        mutating func updateItem(at index: Int, _ transform: (inout ScanItem) -> Void) {
            let before = items[index].allocatedSize
            transform(&items[index])
            runningTotal += items[index].allocatedSize - before
        }
        var selectedSize: Int64 { items.lazy.filter { $0.selected }.reduce(0) { $0 + $1.allocatedSize } }
        var selectedCount: Int { items.lazy.filter { $0.selected }.count }
        var actionableCount: Int { items.lazy.filter { $0.isActionable }.count }
        var permissionGap: Bool { items.contains { $0.permissionDenied } }
    }

    struct CleanSummary {
        var trashed = 0
        var failed = 0
        var bytes: Int64 = 0
        var errors: [String] = []
        var restorable: [(original: URL, trash: URL)] = []
        var recoverableCount = 0   // moved to Trash (Put-Back-able)
        var permanentCount = 0     // emptied Trash / tool cleans (gone)
    }

    // Observable state
    private(set) var phase: Phase = .idle
    private(set) var buckets: [Bucket] = []
    private(set) var progressText: String = ""
    private(set) var fdaGranted: Bool = true
    private(set) var includeExternalVolumes: Bool = false
    private(set) var freeSpaceAtStart: Int64 = 0
    private(set) var scanStartedAt: Date?
    private(set) var movedToTrashBytes: Int64 = 0
    private(set) var lastCleanSummary: CleanSummary?

    private var scanTask: Task<Void, Never>?
    private var bucketIndex: [String: Int] = [:]

    // Derived
    var grandTotal: Int64 { buckets.reduce(0) { $0 + $1.totalSize } }
    var selectedTotal: Int64 { buckets.reduce(0) { $0 + $1.selectedSize } }
    var selectedCount: Int { buckets.reduce(0) { $0 + $1.selectedCount } }
    var isScanning: Bool { phase == .scanning }
    var completedCount: Int { buckets.filter { $0.complete }.count }
    var totalCount: Int { buckets.count }
    /// Coarse progress = scanners finished / total (the streaming scan has no
    /// known byte-total upfront, so we progress by category completion).
    var scanProgress: Double { totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount) }
    var hasScanned: Bool { phase == .finished || phase == .cancelled }
    var developerBuckets: [Bucket] { buckets.filter { $0.info.group == .developer } }
    var aiBuckets: [Bucket] { buckets.filter { $0.info.group == .ai } }
    var creativeBuckets: [Bucket] { buckets.filter { $0.info.group == .creative } }
    var generalBuckets: [Bucket] { buckets.filter { $0.info.group == .general } }

    // MARK: - Snapshot (display-only cache → instant, calm dashboard on launch)

    /// One bucket's headline numbers, persisted so the Dashboard can show the last
    /// scan's results immediately on launch WITHOUT re-walking the disk. Display
    /// only — cleaning always requires a fresh scan (we never act on stale data).
    struct BucketSnapshot: Codable {
        let id: String; let title: String; let systemImage: String
        let group: CategoryGroup; let bytes: Int64; let count: Int
    }
    struct Snapshot: Codable { let date: Date; let buckets: [BucketSnapshot] }
    private(set) var lastSnapshot: Snapshot?

    /// A flattened bucket for the Dashboard: live results if a scan ran this
    /// session, otherwise the cached snapshot.
    struct DisplayBucket: Identifiable {
        let id: String; let title: String; let systemImage: String
        let group: CategoryGroup; let bytes: Int64; let count: Int
    }
    var hasLiveResults: Bool { hasScanned && !buckets.isEmpty }
    var displayBuckets: [DisplayBucket] {
        if hasLiveResults {
            return buckets.map { DisplayBucket(id: $0.id, title: $0.info.title, systemImage: $0.info.systemImage,
                                               group: $0.info.group, bytes: $0.totalSize, count: $0.items.count) }
        }
        return (lastSnapshot?.buckets ?? []).map {
            DisplayBucket(id: $0.id, title: $0.title, systemImage: $0.systemImage,
                          group: $0.group, bytes: $0.bytes, count: $0.count)
        }
    }
    var displayGrandTotal: Int64 { displayBuckets.reduce(0) { $0 + $1.bytes } }
    func displayBuckets(in group: CategoryGroup) -> [DisplayBucket] { displayBuckets.filter { $0.group == group } }
    /// True when the shown numbers come from cache (no fresh scan this session).
    var showingCachedResults: Bool { !hasLiveResults && lastSnapshot != nil }
    var lastScanDate: Date? { hasLiveResults ? scanStartedAt : lastSnapshot?.date }

    /// Our Application Support directory. Never force-unwraps `urls(for:)` — that
    /// would trap in a sandboxed/odd environment; falls back to ~/Library.
    private static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileScan.home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base.appendingPathComponent("Cairn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var snapshotURL: URL {
        supportDirectory.appendingPathComponent("last-scan.json")
    }

    /// Load the cached snapshot for display. Call once on launch; never scans.
    func loadSnapshot() {
        guard lastSnapshot == nil,
              let data = try? Data(contentsOf: Self.snapshotURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        lastSnapshot = snap
        ReclaimStats.shared.reclaimableBytes = snap.buckets.reduce(Int64(0)) { $0 + $1.bytes }
    }

    private func saveSnapshot() {
        let snaps = buckets.map {
            BucketSnapshot(id: $0.id, title: $0.info.title, systemImage: $0.info.systemImage,
                           group: $0.info.group, bytes: $0.totalSize, count: $0.items.count)
        }
        let snap = Snapshot(date: Date(), buckets: snaps)
        lastSnapshot = snap
        ReclaimStats.shared.reclaimableBytes = snaps.reduce(Int64(0)) { $0 + $1.bytes }
        if let data = try? JSONEncoder().encode(snap) { try? data.write(to: Self.snapshotURL, options: .atomic) }
    }

    // MARK: - Removal log (persistent Restore Bin)

    /// One reclaimed item, persisted so Settings can show a real Restore Bin and
    /// Put Back recoverable items long after the celebration toast is gone.
    struct RemovalLogEntry: Codable, Identifiable {
        var id = UUID()
        let name: String
        let originalPath: String
        let trashPath: String?     // nil = permanent (emptied Trash / tool) — not restorable
        let bytes: Int64
        let date: Date
        let category: String
        var recoverable: Bool { trashPath != nil }
    }
    private(set) var removalLog: [RemovalLogEntry] = []

    private static var removalLogURL: URL {
        supportDirectory.appendingPathComponent("removal-log.json")
    }

    func loadRemovalLog() {
        guard removalLog.isEmpty,
              let data = try? Data(contentsOf: Self.removalLogURL),
              let log = try? JSONDecoder().decode([RemovalLogEntry].self, from: data) else { return }
        removalLog = log
        pruneRemovalLog()
    }
    private func saveRemovalLog() {
        if let data = try? JSONEncoder().encode(removalLog) { try? data.write(to: Self.removalLogURL, options: .atomic) }
    }
    private func appendRemovals(_ entries: [RemovalLogEntry]) {
        guard !entries.isEmpty else { return }
        removalLog.insert(contentsOf: entries, at: 0)
        if removalLog.count > 500 { removalLog = Array(removalLog.prefix(500)) }
        saveRemovalLog()
    }
    func pruneRemovalLog() {
        let keepDays = AppSettings.shared.restoreBinKeepDays
        let cutoff = Date().addingTimeInterval(-Double(max(1, keepDays)) * 86_400)
        let before = removalLog.count
        removalLog.removeAll { $0.date < cutoff }
        if removalLog.count != before { saveRemovalLog() }
    }
    /// Put a logged item back from the Trash. Returns success. If the item is no
    /// longer in the Trash (user emptied it / restored it elsewhere), the stale
    /// entry is dropped so the Restore Bin never lists dead rows.
    @discardableResult
    func restoreFromLog(_ entry: RemovalLogEntry) -> Bool {
        guard let trash = entry.trashPath else { return false }
        let trashURL = URL(fileURLWithPath: trash)
        guard FileScan.exists(trashURL) else {
            removalLog.removeAll { $0.id == entry.id }
            saveRemovalLog()
            return false
        }
        let ok = Cleaner.restore(from: trashURL, to: URL(fileURLWithPath: entry.originalPath))
        if ok { removalLog.removeAll { $0.id == entry.id }; saveRemovalLog() }
        return ok
    }

    // MARK: - Scan lifecycle

    func startScan(includeExternalVolumes external: Bool = false) {
        cancel()
        let scanners = ScannerRegistry.all()
        includeExternalVolumes = external
        fdaGranted = FullDiskAccess.isGranted()
        freeSpaceAtStart = Volumes.homeFree()
        scanStartedAt = Date()
        movedToTrashBytes = 0
        lastCleanSummary = nil

        // Seed buckets in registry order so the sidebar is stable while scanning.
        buckets = scanners.map { Bucket(info: $0.info) }
        bucketIndex = Dictionary(uniqueKeysWithValues: buckets.enumerated().map { ($1.id, $0) })
        phase = .scanning
        progressText = "Starting scan…"

        let external = includeExternalVolumes
        let granted = fdaGranted
        scanTask = Task { [weak self] in
            await ScanGate.shared.acquire()          // see ScanGate: one heavy scan at a time
            defer { ScanGate.shared.release() }
            await self?.run(scanners: scanners, includeExternal: external, fdaGranted: granted)
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        if phase == .scanning { phase = .cancelled }
    }

    func rescan() { startScan(includeExternalVolumes: includeExternalVolumes) }

    private func run(scanners: [CairnScanner], includeExternal: Bool, fdaGranted: Bool) async {
        let minSize: Int64 = 5 * 1024 * 1024 // default 5 MB floor; scanners can override per item

        let stream = AsyncStream<ScanEvent> { continuation in
            let work = Task.detached(priority: .userInitiated) {
                await withTaskGroup(of: Void.self) { group in
                    // Bounded concurrency: run a few scanners at a time instead of
                    // all 19 at once, so concurrent tree-walks don't stack memory.
                    let limit = max(2, min(4, ProcessInfo.processInfo.activeProcessorCount - 2))
                    var iterator = scanners.makeIterator()
                    func schedule() {
                        guard let scanner = iterator.next() else { return }
                        group.addTask {
                            if Task.isCancelled { return }
                            continuation.yield(.started(scanner.info.id))
                            let ctx = ScanContext(
                                fdaGranted: fdaGranted,
                                includeExternalVolumes: includeExternal,
                                minSizeBytes: minSize,
                                emit: { continuation.yield(.item($0)) },
                                progress: { continuation.yield(.progress(scanner.info.id, $0)) },
                                isCancelled: { Task.isCancelled }
                            )
                            await scanner.scan(ctx)
                            continuation.yield(.finishedCategory(scanner.info.id))
                        }
                    }
                    for _ in 0..<limit { schedule() }
                    while await group.next() != nil { schedule() }
                }
                continuation.yield(.done)
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }

        // Scanners emit thousands of items per scan. Applying each one immediately
        // published an @Observable change per item, so SwiftUI re-rendered the whole
        // dashboard hundreds of times a second — that was the scan-time lag/beachball.
        // Items are batched and flushed at ~12 fps instead; lifecycle events (started
        // / finishedCategory / done) flush first so ordering is preserved exactly.
        var pending: [ScanItem] = []
        var lastFlush = Date.timeIntervalSinceReferenceDate
        let flushInterval: TimeInterval = 0.08

        func flush() {
            guard !pending.isEmpty else { return }
            for item in pending { applyItem(item) }
            pending.removeAll(keepingCapacity: true)
            lastFlush = Date.timeIntervalSinceReferenceDate
        }

        for await event in stream {
            if Task.isCancelled { break }
            switch event {
            case .item(let item):
                pending.append(item)
                if Date.timeIntervalSinceReferenceDate - lastFlush >= flushInterval { flush() }
            case .progress(let id, let msg):
                // Progress text is cosmetic; only surface it on a flush tick so a
                // fast-moving path string can't drive a redraw per file.
                if Date.timeIntervalSinceReferenceDate - lastFlush >= flushInterval {
                    flush()
                    apply(.progress(id, msg))
                }
            default:
                flush()
                apply(event)
            }
        }
        flush()
        if phase == .scanning { phase = .finished; progressText = "Scan complete." }
        if phase == .finished {
            saveSnapshot()   // single, canonical scan-completion save
            if AppSettings.shared.scanNotifications {
                Notify.scanComplete(totalBytes: grandTotal,
                                    items: buckets.reduce(0) { $0 + $1.items.count })
            }
        }
    }

    /// Filter + file one found item into its bucket (the single item chokepoint).
    private func applyItem(_ item: ScanItem) {
        if AppSettings.shared.isExcluded(item.resolvedURL) { return }
        // Honor the Developer Tools settings here too.
        if !AppSettings.shared.includeDeveloperCaches && item.categoryID == "dev-caches" { return }
        if !AppSettings.shared.includeSimulators && item.resolvedURL.path.contains("/CoreSimulator/") { return }
        if let i = bucketIndex[item.categoryID] {
            buckets[i].append(item)
        }
    }

    private func apply(_ event: ScanEvent) {
        switch event {
        case .started(let id):
            if let i = bucketIndex[id] { buckets[i].progress = "Scanning…" }
        case .item(let item):
            applyItem(item)
        case .progress(let id, let msg):
            if let i = bucketIndex[id] { buckets[i].progress = msg }
            progressText = msg
        case .finishedCategory(let id):
            if let i = bucketIndex[id] {
                buckets[i].complete = true
                buckets[i].progress = ""
                buckets[i].sortBySizeDescending()
            }
        case .done:
            phase = .finished
            progressText = "Scan complete."
        }
    }

    // MARK: - Selection

    func toggle(_ itemID: UUID) {
        for b in buckets.indices {
            if let i = buckets[b].items.firstIndex(where: { $0.id == itemID }) {
                let it = buckets[b].items[i]
                guard it.severity != .risky, it.isActionable else { return } // RISKY never selectable here
                buckets[b].toggleSelected(at: i)
                return
            }
        }
    }

    func selectAllSafe(in bucketID: String) {
        guard let b = bucketIndex[bucketID] else { return }
        for i in buckets[b].items.indices where
            buckets[b].items[i].severity == .safe &&
            buckets[b].items[i].isRegenerable &&
            buckets[b].items[i].isActionable {
            buckets[b].setSelected(at: i, true)
        }
    }

    func selectNone(in bucketID: String) {
        guard let b = bucketIndex[bucketID] else { return }
        for i in buckets[b].items.indices { buckets[b].setSelected(at: i, false) }
    }

    func selectedItems() -> [ScanItem] {
        buckets.flatMap { $0.items.filter { $0.selected } }
    }

    // MARK: - Space Missions selection

    func clearSelection() {
        for b in buckets.indices {
            for i in buckets[b].items.indices { buckets[b].setSelected(at: i, false) }
        }
    }

    /// Select every item matching `predicate` that is safe to select
    /// (never RISKY, never advice). Does not clear existing selection.
    func select(where predicate: (ScanItem, CategoryGroup) -> Bool) {
        for b in buckets.indices {
            let group = buckets[b].info.group
            for i in buckets[b].items.indices {
                let it = buckets[b].items[i]
                if it.severity != .risky, it.isActionable, predicate(it, group) {
                    buckets[b].setSelected(at: i, true)
                }
            }
        }
    }

    /// Greedily select the largest SAFE+regenerable items until the running total
    /// reaches `target` bytes (the "Free N GB fast" missions).
    func selectSafeUpTo(bytes target: Int64) {
        clearSelection()
        var refs: [(b: Int, i: Int, size: Int64)] = []
        for b in buckets.indices {
            for i in buckets[b].items.indices {
                let it = buckets[b].items[i]
                if it.severity == .safe, it.isRegenerable, it.isActionable {
                    refs.append((b, i, it.allocatedSize))
                }
            }
        }
        refs.sort { $0.size > $1.size }
        var acc: Int64 = 0
        for r in refs {
            if acc >= target { break }
            buckets[r.b].setSelected(at: r.i, true)
            acc += r.size
        }
    }

    // MARK: - Cleaning

    /// Smart Triggers entry point: scan ONE category and clean only what is
    /// unambiguously safe to remove without asking.
    ///
    /// Deliberately far stricter than a user-driven clean. Automatic removal has
    /// no human in the loop, so it takes only items that are SAFE, regenerable,
    /// and go to the Trash — never `.tool` (which shells out) or `.emptyTrash`
    /// (which is permanent), and never anything needing a running daemon. Returns
    /// bytes reclaimed. Everything still flows through `clean`, so the removal
    /// log, Restore Bin and lifetime total stay correct.
    func autoClean(categoryID: String) async -> Int64 {
        guard let scanner = ScannerRegistry.all().first(where: { $0.info.id == categoryID }) else { return 0 }

        await ScanGate.shared.acquire()
        let found = Collector()
        let ctx = ScanContext(
            fdaGranted: FullDiskAccess.isGranted(),
            includeExternalVolumes: false,
            minSizeBytes: 5 * 1024 * 1024,
            emit: { found.add($0) },
            progress: { _ in },
            isCancelled: { false }
        )
        await scanner.scan(ctx)
        ScanGate.shared.release()

        let candidates = found.items.filter { item in
            guard item.severity == .safe, item.isRegenerable, !item.requiresRunning else { return false }
            if case .trash = item.cleanMethod { return true }
            return false
        }
        guard !candidates.isEmpty else { return 0 }
        return await clean(candidates, proEnabled: true).bytes
    }

    /// Thread-safe sink for a one-off scanner run.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var items: [ScanItem] = []
        func add(_ item: ScanItem) { lock.lock(); items.append(item); lock.unlock() }
    }

    /// Clean the given items through the safety chokepoint. Runs off-main, then
    /// removes succeeded items from their buckets and accumulates reclaimed bytes.
    func clean(_ items: [ScanItem], proEnabled: Bool) async -> CleanSummary {
        let rootsByCategory = Dictionary(
            ScannerRegistry.all().map { ($0.info.id, $0.allowedRoots) },
            uniquingKeysWith: { a, _ in a }
        )
        var summary = CleanSummary()
        var cleanedIDs = Set<UUID>()
        var logEntries: [RemovalLogEntry] = []

        // Quit any apps that own the caches we're about to clean (cleaning a live
        // cache can corrupt app state), mirroring the uninstaller. The ReviewSheet
        // already warned the user which apps these are.
        let quitIDs = Array(Set(items.flatMap { $0.requiresQuitBundleIDs })).filter { !$0.isEmpty }
        let running = RunningApps.runningNow(amongst: quitIDs)
        if !running.isEmpty {
            progressText = "Quitting \(RunningApps.displayNames(for: running).joined(separator: ", "))…"
            RunningApps.requestQuit(running)
            try? await Task.sleep(nanoseconds: 600_000_000)
        }

        // Safety net: before any PERMANENT removal (empty-Trash / tool cleans, which
        // are not Put-Back-able), take an APFS local snapshot when the user has it on.
        let hasPermanent = items.contains {
            switch $0.cleanMethod { case .emptyTrash, .tool: return true; default: return false }
        }
        if AppSettings.shared.createRestoreSnapshot && hasPermanent {
            progressText = "Creating a restore snapshot…"
            await Task.detached(priority: .userInitiated) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
                p.arguments = ["localsnapshot"]
                p.standardOutput = nil; p.standardError = nil
                try? p.run(); p.waitUntilExit()
            }.value
        }

        for item in items {
            if Task.isCancelled { break }
            let roots = rootsByCategory[item.categoryID] ?? [FileScan.home]
            let outcome = await Task.detached(priority: .userInitiated) {
                Cleaner.clean(item, allowedRoots: roots, proEnabled: proEnabled)
            }.value

            if let err = outcome.error {
                summary.failed += 1
                summary.errors.append("\(item.url.lastPathComponent): \(err)")
            } else {
                summary.trashed += 1
                summary.bytes += outcome.bytesAffected
                cleanedIDs.insert(item.id)
                if let trashURL = outcome.movedToTrashURL {
                    summary.restorable.append((original: item.resolvedURL, trash: trashURL))
                    summary.recoverableCount += 1
                    logEntries.append(RemovalLogEntry(name: item.url.lastPathComponent, originalPath: item.resolvedURL.path,
                                                      trashPath: trashURL.path, bytes: outcome.bytesAffected, date: Date(), category: item.categoryID))
                } else {
                    summary.permanentCount += 1   // emptied Trash / tool clean — gone for good
                    logEntries.append(RemovalLogEntry(name: item.url.lastPathComponent, originalPath: item.resolvedURL.path,
                                                      trashPath: nil, bytes: outcome.bytesAffected, date: Date(), category: item.categoryID))
                }
            }
        }

        // Remove cleaned items from buckets.
        for b in buckets.indices {
            buckets[b].removeItems { cleanedIDs.contains($0.id) }
        }
        movedToTrashBytes += summary.bytes
        ReclaimStats.shared.recordClean(bytes: summary.bytes)   // lifetime total
        lastCleanSummary = summary
        appendRemovals(logEntries)
        // Re-save the snapshot so the cached dashboard reflects post-clean totals
        // (otherwise the next launch over-reports the reclaimable space).
        if hasScanned { saveSnapshot() }
        return summary
    }

    /// Undo the last clean by restoring trashed items. Restored items are also
    /// dropped from the removal log so the Restore Bin never offers a Put Back
    /// for something that's already back.
    func undoLast() {
        guard let restorable = lastCleanSummary?.restorable else { return }
        var restored: Set<String> = []
        for entry in restorable where Cleaner.restore(from: entry.trash, to: entry.original) {
            restored.insert(entry.trash.path)
        }
        if !restored.isEmpty {
            // Take the bytes back off the lifetime total before dropping the
            // entries, so the headline number only counts space actually kept.
            let restoredBytes = removalLog
                .filter { $0.trashPath.map(restored.contains) ?? false }
                .reduce(Int64(0)) { $0 + $1.bytes }
            ReclaimStats.shared.recordRestore(bytes: restoredBytes)
            removalLog.removeAll { $0.trashPath.map(restored.contains) ?? false }
            saveRemovalLog()
        }
        lastCleanSummary = nil
    }
}
