import Foundation
import Observation

/// The app's central state. Runs scanners concurrently, streams items in for the
/// live "items appear as found" animation, aggregates per-category + grand
/// totals, and performs cleans through the safety chokepoint.
@MainActor
@Observable
final class ScanStore {
    private let customRemovalLogURL: URL?
    private let restoreFile: @Sendable (URL, URL) -> Bool
    private let recordRestoredBytes: (Int64) -> Void
    init(removalLogURL: URL? = nil,
         restoreFile: @escaping @Sendable (URL, URL) -> Bool = { Cleaner.restore(from: $0, to: $1) },
         recordRestoredBytes: ((Int64) -> Void)? = nil) {
        customRemovalLogURL = removalLogURL; self.restoreFile = restoreFile; self.recordRestoredBytes = recordRestoredBytes ?? { ReclaimStats.shared.recordRestore(bytes: $0) }
    }

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
            if item.isActionable { runningTotal += item.allocatedSize }
        }
        mutating func removeItems(where shouldRemove: (ScanItem) -> Bool) {
            items.removeAll(where: shouldRemove)
            runningTotal = items.reduce(0) { $0 + ($1.isActionable ? $1.allocatedSize : 0) }
        }
        mutating func sortBySizeDescending() {
            items.sort { $0.allocatedSize > $1.allocatedSize }
        }
        /// Mutate one item in place (selection), keeping the total correct.
        mutating func updateItem(at index: Int, _ transform: (inout ScanItem) -> Void) {
            let before = items[index].isActionable ? items[index].allocatedSize : 0
            transform(&items[index])
            runningTotal += (items[index].isActionable ? items[index].allocatedSize : 0) - before
        }
        var selectedSize: Int64 { items.lazy.filter { $0.selected }.reduce(0) { $0 + $1.allocatedSize } }
        var selectedCount: Int { items.lazy.filter { $0.selected }.count }
        var actionableCount: Int { items.lazy.filter { $0.isActionable }.count }
        var permissionGap: Bool { items.contains { $0.permissionDenied } }
    }

    struct CleanSummary {
        var failed = 0
        var errors: [String] = []
        var restorable: [(original: URL, trash: URL)] = []
        var accounting = CleanupAccounting()
        var capacityChanges: [CleanupCapacityChange] = []
        var interrupted = false
        var trashed: Int { accounting.completedCount } // legacy view name: all completed actions
        var bytes: Int64 { accounting.estimatedAffectedBytes }
        var recoverableCount: Int { accounting.recordedRecoveryCount }
        var toolCount: Int { accounting.toolCount }
    }

    // Observable state
    private(set) var isCleaning = false
    private(set) var phase: Phase = .idle
    private(set) var buckets: [Bucket] = []
    private(set) var progressText: String = ""
    private(set) var fdaGranted: Bool = true
    private(set) var includeExternalVolumes: Bool = false
    private(set) var freeSpaceAtStart: Int64 = 0
    private(set) var scanStartedAt: Date?
    private(set) var movedToTrashBytes: Int64 = 0
    private(set) var lastCleanSummary: CleanSummary?
    private(set) var lastCleanRunID: UUID?

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
    private(set) var comparisonReadings: [ScanComparison.Reading] = []
    private(set) var comparisonError: String?
    private var activeComparisonScope: ScanComparison.Scope?
    /// Invoked only after a completed scan's snapshot and comparison are saved.
    var onCompletedScan: (() -> Void)?
    var scanComparison: ScanComparison.Result { ScanComparison.compare(comparisonReadings) }
    var comparisonScopeStable: Bool { activeComparisonScope == comparisonScope() }
    private static var comparisonURL: URL { supportDirectory.appendingPathComponent("scan-comparison.json") }
    private func comparisonScope() -> ScanComparison.Scope {
        let settings = AppSettings.shared
        return .init(categories: buckets.map(\.id).sorted(), exclusions: settings.excludedPaths.sorted(),
                     developerCaches: settings.includeDeveloperCaches, simulators: settings.includeSimulators,
                     fullDiskAccess: fdaGranted, externalVolumes: includeExternalVolumes)
    }
    private func recordComparison() {
        guard phase == .finished, comparisonError == nil, let scope = activeComparisonScope else { return }
        let reading = ScanComparison.Reading(date: Date(), scope: scope,
            complete: scope == comparisonScope() && buckets.allSatisfy { $0.complete && !$0.permissionGap },
            buckets: buckets.map { .init(id: $0.id, title: $0.info.title, icon: $0.info.systemImage, group: $0.info.group, bytes: $0.totalSize) })
        comparisonReadings = Array((comparisonReadings + [reading]).suffix(2))
        do { try JSONEncoder().encode(comparisonReadings).write(to: Self.comparisonURL, options: .atomic) }
        catch { comparisonError = "Comparison history could not be saved. Existing history was retained." }
    }


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
        if comparisonReadings.isEmpty, comparisonError == nil, FileManager.default.fileExists(atPath: Self.comparisonURL.path) {
            do { comparisonReadings = Array(try JSONDecoder().decode([ScanComparison.Reading].self, from: Data(contentsOf: Self.comparisonURL)).suffix(2)) }
            catch { comparisonError = "Comparison history could not be read; it will not be overwritten." }
        }
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

    /// One recorded action, persisted so Settings can show a real Restore Bin and
    /// Put Back recoverable items long after the celebration toast is gone.
    struct RemovalLogEntry: Codable, Identifiable {
        var id = UUID()
        let name: String
        let originalPath: String
        let trashPath: String?     // nil means no recorded recovery path; never proves deletion
        let bytes: Int64
        let date: Date
        let category: String
        var actionKind: String? = nil   // "trash" or "tool"; older records may be unknown
        var restoredAt: Date? = nil
        var recoverable: Bool { trashPath != nil && restoredAt == nil }
    }
    private(set) var removalLog: [RemovalLogEntry] = []

    private(set) var removalLogError: String?
    private(set) var isRestoring = false
    private var removalLogLoaded = false
    private var removalLogRevision: Data?
    private var removalLogURL: URL { customRemovalLogURL ?? Self.supportDirectory.appendingPathComponent("removal-log.json") }

    func loadRemovalLog() {
        guard !removalLogLoaded else { return }
        removalLogLoaded = true
        guard FileManager.default.fileExists(atPath: removalLogURL.path) else { return }
        do {
            let size = try removalLogURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 20 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            let data = try Data(contentsOf: removalLogURL)
            let log = try JSONDecoder().decode([RemovalLogEntry].self, from: data)
            guard Set(log.map(\.id)).count == log.count else { throw CocoaError(.fileReadCorruptFile) }
            removalLog = log
            removalLogRevision = data
        } catch { removalLogError = "Recovery history could not be read. It was preserved; cleanup is blocked until it can be recovered." }
    }
    @discardableResult private func saveRemovalLog() -> Bool {
        guard removalLogError == nil else { return false }
        do {
            if FileManager.default.fileExists(atPath: removalLogURL.path) {
                guard try Data(contentsOf: removalLogURL) == removalLogRevision else {
                    throw CocoaError(.fileWriteFileExists)
                }
            } else if removalLogRevision != nil { throw CocoaError(.fileNoSuchFile) }
            try FileManager.default.createDirectory(at: removalLogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(removalLog)
            try data.write(to: removalLogURL, options: .atomic)
            removalLogRevision = data
            return true
        } catch { removalLogError = "Recovery history could not be saved. Further cleanup is blocked. Existing files and in-memory records are retained."; return false }
    }
    func prepareRemovalLog() -> Bool {
        loadRemovalLog()
        return saveRemovalLog()
    }
    @discardableResult func appendRemovals(_ entries: [RemovalLogEntry]) -> Bool {
        loadRemovalLog()
        guard removalLogError == nil else { return false }
        guard !entries.isEmpty else { return true }
        let known = Set(removalLog.map(\.id))
        removalLog.insert(contentsOf: entries.filter { !known.contains($0.id) }, at: 0)
        return saveRemovalLog()
    }
    func pruneRemovalLog() {
        let keepDays = AppSettings.shared.restoreBinKeepDays
        let cutoff = Date().addingTimeInterval(-Double(max(1, keepDays)) * 86_400)
        let before = removalLog.count
        removalLog.removeAll { $0.date < cutoff }
        if removalLog.count != before { saveRemovalLog() }
    }
    /// Put a logged item back from the Trash. Returns success. Keep the audit
    /// record if the Trash entry has disappeared; it can still explain a past
    /// removal and should not be silently erased by a failed restore attempt.
    @discardableResult
    func restoreFromLog(_ entry: RemovalLogEntry) async -> Bool {
        guard !isRestoring, !isCleaning, !isScanning, prepareRemovalLog(),
              let recorded = removalLog.first(where: { $0.id == entry.id }), recorded.recoverable,
              let trash = recorded.trashPath else { return false }
        isRestoring = true
        defer { isRestoring = false }
        guard await ScanGate.shared.acquire() else { return false }
        defer { ScanGate.shared.release() }
        let restore = restoreFile
        let ok = await Task.detached(priority: .utility) {
            restore(URL(fileURLWithPath: trash), URL(fileURLWithPath: recorded.originalPath))
        }.value
        if ok, let index = removalLog.firstIndex(where: { $0.id == recorded.id }) {
            removalLog[index].restoredAt = Date()
            recordRestoredBytes(recorded.bytes)
            saveRemovalLog()
        }
        return ok
    }

    // MARK: - Scan lifecycle

    func startScan(includeExternalVolumes external: Bool = false) {
        guard !isCleaning, !isRestoring else { return }
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
        activeComparisonScope = comparisonScope()
        phase = .scanning
        progressText = "Waiting for other disk work to finish…"

        let external = includeExternalVolumes
        let granted = fdaGranted
        scanTask = Task { [weak self] in
            guard await ScanGate.shared.acquire() else { return }
            defer { ScanGate.shared.release() }
            guard !Task.isCancelled else { return }
            await self?.run(scanners: scanners, includeExternal: external, fdaGranted: granted)
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        if phase == .scanning { phase = .cancelled }
    }

    func cancelAndWait() async {
        let worker = scanTask
        cancel()
        await worker?.value
    }

    func rescan() { startScan(includeExternalVolumes: includeExternalVolumes) }

    private func run(scanners: [CairnScanner], includeExternal: Bool, fdaGranted: Bool) async {
        let minSize: Int64 = 5 * 1024 * 1024 // default 5 MB floor; scanners can override per item

        let pipeline = ScanEventPipeline(scanners: scanners, fdaGranted: fdaGranted,
                                         includeExternal: includeExternal, minSize: minSize)

        // Scanners emit thousands of items per scan. Applying each one immediately
        // published an @Observable change per item, so SwiftUI re-rendered the whole
        // dashboard hundreds of times a second — that was the scan-time lag/beachball.
        // Items are batched and flushed at ~12 fps instead; lifecycle events (started
        // / finishedCategory / done) flush first so ordering is preserved exactly.
        var receivedItems = 0
        var pending: [ScanItem] = []
        var lastFlush = Date.timeIntervalSinceReferenceDate
        let flushInterval: TimeInterval = 0.08

        func flush() {
            guard !pending.isEmpty else { return }
            for item in pending { applyItem(item) }
            pending.removeAll(keepingCapacity: true)
            lastFlush = Date.timeIntervalSinceReferenceDate
        }

        scanEvents: for await event in pipeline.stream {
            if Task.isCancelled { break }
            switch event {
            case .item(let item):
                receivedItems += 1
                if receivedItems > 20_000 { pipeline.overflow.cancel(); break scanEvents }
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
        // Keep the shared gate until detached producers really have exited.
        await pipeline.stopAndWait()
        guard !Task.isCancelled else { return }
        flush()
        if pipeline.overflow.isCancelled {
            phase = .cancelled
            progressText = "Scan stopped at the result limit. Partial results retained; scan a smaller scope."
            return
        }
        if phase == .scanning { phase = .finished; progressText = "Scan complete." }
        if phase == .finished {
            saveSnapshot()   // single, canonical scan-completion save
            recordComparison()
            onCompletedScan?()
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
    /// estimated affected file sizes. Everything flows through `clean`, so the removal
    /// log, Restore Bin and lifetime total stay correct.
    func autoClean(categoryID: String) async -> Int64 {
        guard let scanner = ScannerRegistry.all().first(where: { $0.info.id == categoryID }) else { return 0 }

        guard await ScanGate.shared.acquire() else { return 0 }
        let found = Collector()
        let ctx = ScanContext(
            fdaGranted: FullDiskAccess.isGranted(),
            includeExternalVolumes: false,
            minSizeBytes: 5 * 1024 * 1024,
            emit: { found.add($0) },
            progress: { _ in },
            isCancelled: { Task.isCancelled }
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
    /// removes succeeded items from their buckets and records affected sizes.
    func clean(_ items: [ScanItem], proEnabled: Bool) async -> CleanSummary {
        guard !isCleaning, !isScanning, !isRestoring, prepareRemovalLog() else { return CleanSummary(failed: items.count, errors: ["Finish the current operation before cleanup."]) }
        guard await Task.detached(priority: .utility, operation: { ActionJournal.shared.prepare() }).value else {
            return CleanSummary(failed: items.count, errors: [ActionJournal.shared.error ?? "Action journal unavailable; no cleanup ran."])
        }
        isCleaning = true
        defer { isCleaning = false }
        guard await ScanGate.shared.acquire() else { return CleanSummary(failed: items.count, errors: ["Cleanup cancelled before starting."]) }
        defer { ScanGate.shared.release() }

        let rootsByCategory = Dictionary(
            ScannerRegistry.all().map { ($0.info.id, $0.allowedRoots) },
            uniquingKeysWith: { a, _ in a }
        )
        var summary = CleanSummary()
        let volumes = Array(Set(items.compactMap { $0.volumeURL ?? FileScan.volumeURL(of: $0.resolvedURL) })).sorted { $0.path < $1.path }
        let capacityBefore = await Task.detached(priority: .utility) { volumes.map(CleanupCapacityChange.read) }.value
        var cleanedIDs = Set<UUID>()

        // Do not shut down an app behind the user's back. A live cache can hold
        // unsaved state, so re-check its owner immediately before each action.

        // Optional APFS snapshot before tool actions. This is a local recovery
        // point, not a backup, and must finish successfully before acting.
        let hasPermanent = items.contains {
            switch $0.cleanMethod { case .emptyTrash, .tool: return true; default: return false }
        }
        if AppSettings.shared.createRestoreSnapshot && hasPermanent {
            progressText = "Creating a restore snapshot…"
            let snapshotOK = await Task.detached(priority: .userInitiated) {
                (try? ToolRunner.run("tmutil", ["localsnapshot"], timeout: 45).ok) ?? false
            }.value
            guard snapshotOK else {
                summary.failed = items.count
                summary.errors.append("The local snapshot failed or timed out; no cleanup ran. Turn off the snapshot option only if you want to proceed without it.")
                return summary
            }
        }

        for item in items {
            var logEntry: RemovalLogEntry?
            if Task.isCancelled { summary.interrupted = true; break }
            let runningOwners = RunningApps.runningNow(amongst: item.requiresQuitBundleIDs)
            if !runningOwners.isEmpty {
                summary.failed += 1
                summary.errors.append("\(item.url.lastPathComponent): close \(RunningApps.displayNames(for: runningOwners).joined(separator: ", ")) before cleaning")
                continue
            }
            let roots = rootsByCategory[item.categoryID] ?? [FileScan.home]
            guard let actionID = await Task.detached(priority: .utility, operation: {
                ActionJournal.shared.begin(path: item.resolvedURL.path, category: item.categoryID)
            }).value else {
                summary.interrupted = true
                summary.errors.append(ActionJournal.shared.error ?? "Action intent could not be recorded; further cleanup stopped.")
                break
            }
            let outcome = await Task.detached(priority: .userInitiated) {
                Cleaner.clean(item, allowedRoots: roots, proEnabled: proEnabled)
            }.value
            let journalSaved = await Task.detached(priority: .utility) {
                ActionJournal.shared.finish(actionID, succeeded: outcome.ok,
                                            trashPath: outcome.movedToTrashURL?.path, detail: outcome.error)
            }.value

            if let err = outcome.error {
                summary.failed += 1
                summary.errors.append("\(item.url.lastPathComponent): \(err)")
            } else {
                cleanedIDs.insert(item.id)
                if let trashURL = outcome.movedToTrashURL {
                    summary.restorable.append((original: item.resolvedURL, trash: trashURL))
                    logEntry = RemovalLogEntry(name: item.url.lastPathComponent, originalPath: item.resolvedURL.path,
                                                      trashPath: trashURL.path, bytes: outcome.bytesAffected, date: Date(), category: item.categoryID)
                } else {
                    logEntry = RemovalLogEntry(name: item.url.lastPathComponent, originalPath: item.resolvedURL.path,
                                                      trashPath: nil, bytes: outcome.bytesAffected, date: Date(), category: item.categoryID)
                }
            }
            logEntry?.actionKind = outcome.usedTool ? "tool" : "trash"
            if let entry = logEntry, !appendRemovals([entry]) {
                summary.accounting.record(outcome, recoveryRecorded: false)
                summary.interrupted = true
                summary.errors.append("Recovery history could not be saved; further cleanup stopped.")
                break
            }
            summary.accounting.record(outcome, recoveryRecorded: logEntry != nil)
            if !journalSaved {
                summary.interrupted = true
                summary.errors.append(ActionJournal.shared.error ?? "Action outcome could not be recorded; further cleanup stopped.")
                break
            }
        }

        // Remove cleaned items from buckets.
        for b in buckets.indices {
            buckets[b].removeItems { cleanedIDs.contains($0.id) }
        }
        let capacityAfter = await Task.detached(priority: .utility) { volumes.map(CleanupCapacityChange.read) }.value
        summary.capacityChanges = volumes.indices.map { CleanupCapacityChange(id: volumes[$0].path, before: capacityBefore[$0], after: capacityAfter[$0]) }
        movedToTrashBytes += summary.accounting.trashBytes
        ReclaimStats.shared.recordClean(bytes: summary.bytes)   // affected-size estimate, not free capacity
        lastCleanSummary = summary
        lastCleanRunID = UUID()
        // Re-save the snapshot so the cached dashboard reflects post-clean totals
        // (otherwise the next launch over-reports the reclaimable space).
        if hasScanned { saveSnapshot() }
        return summary
    }

    /// Undo the last clean by restoring trashed items. Restored items are also
    /// marked restored in the removal log so Put Back is not offered twice.
    func undoLast() async {
        guard let restorable = lastCleanSummary?.restorable else { return }
        let paths = Set(restorable.map { $0.trash.path })
        let entries = removalLog.filter { $0.recoverable && $0.trashPath.map(paths.contains) == true }
        for entry in entries { _ = await restoreFromLog(entry) }
        lastCleanSummary = nil
        lastCleanRunID = nil
    }
}
