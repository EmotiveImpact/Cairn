import Foundation
import Observation

/// The app's central state. Runs scanners concurrently, streams items in for the
/// live "items appear as found" animation, aggregates per-category + grand
/// totals, and performs cleans through the safety chokepoint.
@MainActor
@Observable
final class ScanStore {
    private let customRemovalLogURL: URL?
    private let recoveryJournal: ActionJournal
    private let restoreFile: @Sendable (URL, URL) -> Bool
    private let recordRestoredBytes: (Int64) -> Void
    private let fixtureScanners: [CairnScanner]?
    private let lifecycleCheckpoint: @Sendable (String) -> Void
    private let cleanFile: @Sendable (ScanItem, [URL], Bool, ReviewedSource?) -> Cleaner.Outcome
    init(removalLogURL: URL? = nil,
         actionJournal: ActionJournal? = nil,
         restoreFile: @escaping @Sendable (URL, URL) -> Bool = { Cleaner.restore(from: $0, to: $1) },
         recordRestoredBytes: ((Int64) -> Void)? = nil,
         fixtureScanners: [CairnScanner]? = nil,
         lifecycleCheckpoint: @escaping @Sendable (String) -> Void = { _ in },
         cleanFile: @escaping @Sendable (ScanItem, [URL], Bool, ReviewedSource?) -> Cleaner.Outcome = { Cleaner.clean($0, allowedRoots: $1, proEnabled: $2, reviewedSource: $3) }) {
        self.fixtureScanners = fixtureScanners; self.cleanFile = cleanFile; self.lifecycleCheckpoint = lifecycleCheckpoint
        recoveryJournal = actionJournal ?? (removalLogURL.map { ActionJournal(url: $0.appendingPathExtension("actions")) } ?? .shared)
        customRemovalLogURL = removalLogURL; self.restoreFile = restoreFile; self.recordRestoredBytes = recordRestoredBytes ?? { if removalLogURL == nil { ReclaimStats.shared.recordRestore(bytes: $0) } }
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
        /// The part of the total that is ready to free (safe and rebuildable),
        /// kept the same way so the live scan can show the same number as the result.
        private var runningReady: Int64 = 0
        var readySize: Int64 { runningReady }
        private static func readyBytes(_ item: ScanItem) -> Int64 {
            item.severity == .safe && item.isRegenerable && item.isActionable ? item.allocatedSize : 0
        }

        init(info: CategoryInfo) { self.info = info }

        /// Selection only — never changes the byte total.
        mutating func setSelected(at index: Int, _ value: Bool) {
            items[index].selected = value
        }
        mutating func toggleSelected(at index: Int) {
            items[index].selected.toggle()
        }

        mutating func append(_ incoming: ScanItem) {
            var item = incoming
            if !item.isActionable || item.severity == .risky { item.selected = false }
            items.append(item)
            if item.isActionable { runningTotal += item.allocatedSize }
            runningReady += Self.readyBytes(item)
        }
        mutating func removeItems(where shouldRemove: (ScanItem) -> Bool) {
            items.removeAll(where: shouldRemove)
            runningTotal = items.reduce(0) { $0 + ($1.isActionable ? $1.allocatedSize : 0) }
            runningReady = items.reduce(0) { $0 + Self.readyBytes($1) }
        }
        mutating func sortBySizeDescending() {
            items.sort { $0.allocatedSize > $1.allocatedSize }
        }
        /// Mutate one item in place (selection), keeping the total correct.
        mutating func updateItem(at index: Int, _ transform: (inout ScanItem) -> Void) {
            let before = items[index].isActionable ? items[index].allocatedSize : 0
            let readyBefore = Self.readyBytes(items[index])
            transform(&items[index])
            runningTotal += (items[index].isActionable ? items[index].allocatedSize : 0) - before
            runningReady += Self.readyBytes(items[index]) - readyBefore
        }
        var selectedSize: Int64 { items.lazy.filter { $0.selected && $0.isActionable && $0.severity != .risky }.reduce(0) { $0 + $1.allocatedSize } }
        var selectedCount: Int { items.lazy.filter { $0.selected && $0.isActionable && $0.severity != .risky }.count }
        var actionableCount: Int { items.lazy.filter { $0.isActionable }.count }
        var permissionGap: Bool { items.contains { $0.permissionDenied } }
    }

    struct CleanSummary: Codable, Sendable {
        struct Restorable: Codable, Sendable { let original: URL; let trash: URL }
        var failed = 0
        var errors: [String] = []
        var restorable: [Restorable] = []
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
    private(set) var cleanupRuns: [CleanupRun] = []
    private(set) var receiptError: String?
    private var activeRunIDs: Set<UUID> = []
    private var receiptRevision: UInt64 = 0
    func isRunActive(_ id: UUID) -> Bool { activeRunIDs.contains(id) }
    @ObservationIgnored private lazy var runHistory = CleanupRunHistory(url: removalLogURL.appendingPathExtension("runs"))
    func loadCleanupRuns() async {
        guard !isCleaning else { return }
        let snapshot = await runHistory.load()
        guard !isCleaning, snapshot.revision >= receiptRevision else { return }
        receiptRevision = snapshot.revision
        receiptError = snapshot.error
        cleanupRuns = snapshot.runs.map { run in
            var run = run
            if run.finished == nil && !activeRunIDs.contains(run.id) {
                run.summary.interrupted = true
                run.summary.errors.append("This run did not finish. Counts reflect its last saved checkpoint. Review recorded actions for any later or uncertain outcomes; nothing will be replayed.")
            }
            return run
        }
        if let latest = cleanupRuns.first { lastCleanSummary = latest.summary; lastCleanRunID = latest.id }
    }
    func beginSpecialistRun(_ kind: String) async -> CleanupRun? {
        let run = CleanupRun(id: UUID(), started: Date(), finished: nil, summary: .init(), kind: kind)
        guard await saveRun(run) else { return nil }
        activeRunIDs.insert(run.id)
        return run
    }
    func finishSpecialistRun(_ run: CleanupRun, summary: CleanSummary) async -> Bool {
        defer { activeRunIDs.remove(run.id) }
        var run = run; run.summary = summary; run.finished = Date()
        let saved = await saveRun(run)
        var shown = summary
        if !saved { shown.interrupted = true; shown.errors.append(receiptError ?? "Receipt could not be saved.") }
        lastCleanSummary = shown; lastCleanRunID = run.id
        return saved
    }
    private func saveRun(_ run: CleanupRun) async -> Bool {
        receiptError = await runHistory.save(run)
        guard receiptError == nil else { return false }
        let snapshot = await runHistory.load()
        receiptRevision = max(receiptRevision, snapshot.revision)
        if let index = cleanupRuns.firstIndex(where: { $0.id == run.id }) { cleanupRuns[index] = run }
        else { cleanupRuns.insert(run, at: 0) }
        return true
    }

    private var scanTask: Task<Void, Never>?
    private var bucketIndex: [String: Int] = [:]
    /// Every path already listed in this scan. Scanners overlap (an installer is also an
    /// old download; a Chrome cache sits inside the Google cache), so each byte is counted once.
    private var listedPaths: Set<String> = []

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
        /// Safe, rebuildable and actionable: the same rule as Home's number.
        /// Optional so snapshots saved before it existed still decode.
        var readyBytes: Int64? = nil
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
        /// Safe, rebuildable and actionable: the same rule as Home's number.
        /// Optional so snapshots saved before it existed still decode.
        var readyBytes: Int64? = nil
    }
    var hasLiveResults: Bool { hasScanned && !buckets.isEmpty }
    var displayBuckets: [DisplayBucket] {
        if hasLiveResults {
            return buckets.map { DisplayBucket(id: $0.id, title: $0.info.title, systemImage: $0.info.systemImage,
                                               group: $0.info.group, bytes: $0.totalSize, count: $0.items.count,
                           readyBytes: $0.items.filter(CLI.isReady).reduce(Int64(0)) { $0 + $1.allocatedSize }) }
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
    nonisolated private static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileScan.home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base.appendingPathComponent("Cairn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Where cleanup receipts live. Read-only callers (the CLI and agents) use
    /// this to report what was freed from the same records Activity shows.
    nonisolated static var receiptsURL: URL {
        supportDirectory.appendingPathComponent("removal-log.json").appendingPathExtension("runs")
    }

    nonisolated private static var snapshotURL: URL {
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

    /// The app's last completed scan, read without scanning. For the CLI and MCP.
    nonisolated static func savedSnapshot() -> Snapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private func saveSnapshot() {
        let snaps = buckets.map {
            BucketSnapshot(id: $0.id, title: $0.info.title, systemImage: $0.info.systemImage,
                           group: $0.info.group, bytes: $0.totalSize, count: $0.items.count,
                           readyBytes: $0.items.filter(CLI.isReady).reduce(Int64(0)) { $0 + $1.allocatedSize })
        }
        let snap = Snapshot(date: Date(), buckets: snaps)
        lastSnapshot = snap
        ReclaimStats.shared.reclaimableBytes = snaps.reduce(Int64(0)) { $0 + $1.bytes }
        if let data = try? JSONEncoder().encode(snap) { try? data.write(to: Self.snapshotURL, options: .atomic) }
    }

    // MARK: - Removal log (persistent Restore Bin)

    /// One recorded action, persisted so Settings can show a real Restore Bin and
    /// Put Back recoverable items long after the celebration toast is gone.
    struct RemovalLogEntry: Codable, Identifiable, Sendable {
        var id = UUID()
        let name: String
        let originalPath: String
        let trashPath: String?     // nil means no recorded recovery path; never proves deletion
        let bytes: Int64
        let date: Date
        let category: String
        var trashIdentity: SourceIdentity? = nil
        var actionKind: String? = nil   // "trash" or "tool"; older records may be unknown
        var restoredAt: Date? = nil
        var recoverable: Bool { trashPath != nil && restoredAt == nil }
    }
    private(set) var removalLog: [RemovalLogEntry] = []

    private(set) var removalLogError: String?
    private(set) var isRestoring = false
    private(set) var restoreMessage: String?
    private var removalLogURL: URL { customRemovalLogURL ?? Self.supportDirectory.appendingPathComponent("removal-log.json") }
    @ObservationIgnored private lazy var recoveryHistory = RecoveryHistory(url: removalLogURL)
    private var recoveryRevision: UInt64 = 0
    private func applyRecovery(_ snapshot: RecoveryHistory.Snapshot) {
        guard snapshot.revision >= recoveryRevision else { return }
        recoveryRevision = snapshot.revision
        removalLog = snapshot.entries; removalLogError = snapshot.error
    }
    func loadRemovalLog() async { applyRecovery(await recoveryHistory.load()) }
    func prepareRemovalLog() async -> Bool {
        let snapshot = await recoveryHistory.prepare(); applyRecovery(snapshot)
        return snapshot.error == nil
    }
    @discardableResult func appendRemovals(_ entries: [RemovalLogEntry]) async -> Bool {
        let enriched = await Task.detached(priority: .utility) { [recoveryJournal] in
            let actions = Dictionary(uniqueKeysWithValues: recoveryJournal.recent.map { ($0.id, $0) })
            return entries.map { entry -> RemovalLogEntry in
                var entry = entry
                if let action = actions[entry.id], action.path == entry.originalPath, action.trashPath == entry.trashPath {
                    entry.trashIdentity = action.trashIdentity; entry.actionKind = action.actionKind
                }
                return entry
            }
        }.value
        let snapshot = await recoveryHistory.append(enriched); applyRecovery(snapshot)
        guard snapshot.error == nil else { return false }
        return await Task.detached(priority: .utility) { [recoveryJournal] in
            recoveryJournal.acknowledgeRecovery(Set(entries.map(\.id)))
        }.value
    }
    func pruneRemovalLog() {} // Never silently expire Put Back records.
    func reconcileActionJournal() async -> Bool {
        let actions = await Task.detached(priority: .utility) { [recoveryJournal] in recoveryJournal.recent }.value
        let snapshot = await recoveryHistory.reconcile(actions); applyRecovery(snapshot)
        guard snapshot.error == nil else { return false }
        return await Task.detached(priority: .utility) { [recoveryJournal] in
            recoveryJournal.acknowledgeRecovery(snapshot.acknowledged)
        }.value
    }
    /// Put a logged item back from the Trash. Returns success. Keep the audit
    /// record if the Trash entry has disappeared; it can still explain a past
    /// removal and should not be silently erased by a failed restore attempt.
    @discardableResult
    func restoreFromLog(_ entry: RemovalLogEntry) async -> Bool {
        restoreMessage = nil
        guard !isRestoring, !isCleaning, !isScanning else { return false }
        isRestoring = true
        defer { isRestoring = false }
        guard await prepareRemovalLog(),
              let recorded = removalLog.first(where: { $0.id == entry.id }), recorded.recoverable,
              let trash = recorded.trashPath else { return false }
        guard await ScanGate.shared.acquire(.restore) else { return false }
        defer { ScanGate.shared.release() }
        let restore = restoreFile
        let journal = recoveryJournal
        let actionID = await Task.detached(priority: .utility) {
            guard journal.prepare(), recorded.trashIdentity == nil || SourceIdentity.read(URL(fileURLWithPath: trash)) == recorded.trashIdentity else { return nil as UUID? }
            return journal.begin(path: trash, category: "restore", affectedBytes: recorded.bytes,
                actionKind: "restore", relatedRecoveryID: recorded.id, destinationPath: recorded.originalPath)
        }.value
        guard let actionID else { restoreMessage = journal.error ?? "The recorded Trash item is unavailable or changed. No restore ran."; return false }
        let ok = await Task.detached(priority: .utility) {
            guard recorded.trashIdentity == nil || SourceIdentity.read(URL(fileURLWithPath: trash)) == recorded.trashIdentity else { return false }
            return restore(URL(fileURLWithPath: trash), URL(fileURLWithPath: recorded.originalPath))
        }.value
        let journalSaved = await Task.detached(priority: .utility) {
            journal.finish(actionID, succeeded: ok, trashPath: nil, detail: ok ? "Restored to the recorded location" : "Restore refused or failed")
        }.value
        if ok {
            let snapshot = await recoveryHistory.markRestored(recorded.id)
            applyRecovery(snapshot)
            recordRestoredBytes(recorded.bytes)
            guard snapshot.error == nil, journalSaved else {
                restoreMessage = "The item was moved back, but its recovery record could not be fully saved. Review the original location and action journal before retrying."
                return false
            }
            let linked = await Task.detached(priority: .utility) { journal.acknowledgeRecovery([actionID]) }.value
            if !linked { restoreMessage = "The item was restored and its recovery history saved, but the action journal still needs reconciliation." }
            return linked
        }
        restoreMessage = journalSaved ? "Restore was refused or failed. The original was not overwritten; the history was retained." : "Restore outcome could not be recorded. Review both locations before retrying."
        return false
    }

    // MARK: - Scan lifecycle

    func startScan(includeExternalVolumes external: Bool = false) {
        guard !isCleaning, !isRestoring else { return }
        cancel()
        let scanners = fixtureScanners ?? ScannerRegistry.all()
        includeExternalVolumes = external
        fdaGranted = FullDiskAccess.isGranted()
        freeSpaceAtStart = Volumes.homeFree()
        scanStartedAt = Date()
        movedToTrashBytes = 0
        // Keep completed receipts available while a new scan runs.

        // Seed buckets in registry order so the sidebar is stable while scanning.
        buckets = scanners.map { Bucket(info: $0.info) }
        bucketIndex = Dictionary(uniqueKeysWithValues: buckets.enumerated().map { ($1.id, $0) })
        listedPaths = []
        activeComparisonScope = comparisonScope()
        phase = .scanning
        progressText = "Waiting for other disk work to finish…"

        let external = includeExternalVolumes
        let granted = fdaGranted
        scanTask = Task { [weak self] in
            guard await ScanGate.shared.acquire(.scan) else { return }
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
        if phase == .finished, customRemovalLogURL == nil {
            saveSnapshot()   // single, canonical scan-completion save
            recordComparison()
            onCompletedScan?()
            if AppSettings.shared.scanNotifications {
                Notify.scanComplete(readyBytes: recommendedBytes, foundBytes: grandTotal)
            }
        }
    }

    /// Filter + file one found item into its bucket (the single item chokepoint).
    private func applyItem(_ item: ScanItem) {
        if AppSettings.shared.isExcluded(item.resolvedURL) { return }
        // Honor the Developer Tools settings here too.
        if !AppSettings.shared.includeDeveloperCaches && item.categoryID == "dev-caches" { return }
        if !AppSettings.shared.includeSimulators && item.resolvedURL.path.contains("/CoreSimulator/") { return }
        guard let i = bucketIndex[item.categoryID] else { return }
        let path = item.resolvedURL.standardizedFileURL.path
        // Already listed, or inside a folder that is: the first listing keeps it.
        var parent = path
        while !parent.isEmpty, parent != "/" {
            if listedPaths.contains(parent) { return }
            parent = (parent as NSString).deletingLastPathComponent
        }
        // A folder arriving after things inside it replaces them, so they are not counted twice.
        let prefix = path + "/"
        let inside = listedPaths.filter { $0.hasPrefix(prefix) }
        if !inside.isEmpty {
            for b in buckets.indices {
                buckets[b].removeItems { inside.contains($0.resolvedURL.standardizedFileURL.path) }
            }
            listedPaths.subtract(inside)
        }
        listedPaths.insert(path)
        buckets[i].append(item)
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
        buckets.flatMap { $0.items.filter { $0.selected && $0.isActionable && $0.severity != .risky } }
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

    /// Safe, rebuildable findings: what "Clean recommended" removes.
    var recommendedItems: [ScanItem] {
        buckets.flatMap { $0.items.filter { $0.severity == .safe && $0.isRegenerable && $0.isActionable } }
    }
    var recommendedBytes: Int64 { buckets.reduce(0) { $0 + $1.readySize } }

    /// Replace the selection with every recommended finding.
    func selectRecommended() {
        clearSelection()
        select { item, _ in item.severity == .safe && item.isRegenerable }
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

    /// Kept as a closed compatibility entry point. Old preferences cannot grant
    /// consent to remove data. Future rules require their own reviewed contract.
    func autoClean(categoryID: String) async -> Int64 { 0 }

    /// Clean the given items through the safety chokepoint. Runs off-main, then
    /// removes succeeded items from their buckets and records affected sizes.
    func clean(_ items: [ScanItem], proEnabled: Bool, reviewedPlan: ReviewedSpacePlan? = nil,
               removal: RemovalMode? = nil) async -> CleanSummary {
        // Advice and risky findings never execute. Drop them and run the rest
        // rather than refusing the whole reviewed selection.
        let mode = removal ?? AppSettings.shared.removalMode
        let skipped = items.filter { !$0.isActionable || $0.severity == .risky }
        let items = items.filter { $0.isActionable && $0.severity != .risky }.map { item -> ScanItem in
            var item = item
            item.deleteImmediately = mode.deletesImmediately(item)
            return item
        }
        guard !items.isEmpty else {
            return CleanSummary(failed: skipped.count, errors: ["Nothing selected has a cleanup action. Advice items are for review only."])
        }
        guard !isCleaning, !isScanning, !isRestoring else { return CleanSummary(failed: items.count, errors: ["Finish the current operation before cleanup."]) }
        isCleaning = true
        defer { isCleaning = false }
        guard await prepareRemovalLog() else { return CleanSummary(failed: items.count, errors: [removalLogError ?? "Recovery history unavailable."]) }
        let journal = recoveryJournal
        guard await Task.detached(priority: .utility, operation: { journal.prepare() }).value else {
            return CleanSummary(failed: items.count, errors: [journal.error ?? "Action journal unavailable; no cleanup ran."])
        }
        guard await ScanGate.shared.acquire(.cleanup) else { return CleanSummary(failed: items.count, errors: ["Cleanup cancelled before starting."]) }
        defer { ScanGate.shared.release() }

        let goalCapacity: CapacityReading?
        if reviewedPlan != nil {
            goalCapacity = await Task.detached(priority: .utility) { CapacityProbe.read() }.value
        } else { goalCapacity = nil }
        if let reviewedPlan {
            guard comparisonScopeStable, !includeExternalVolumes,
                  Int64(AppSettings.shared.goalGB) * 1_000_000_000 == reviewedPlan.target else {
                return CleanSummary(failed: items.count, errors: ["The scan settings or target changed. Review a fresh plan."])
            }
            if let reason = reviewedPlan.invalidReason(itemIDs: Set(items.map(\.id)), scanStarted: scanStartedAt,
                exclusions: AppSettings.shared.excludedPaths, fullDiskAccess: FullDiskAccess.isGranted(),
                developerCaches: AppSettings.shared.includeDeveloperCaches, simulators: AppSettings.shared.includeSimulators, capacity: goalCapacity) {
                return CleanSummary(failed: items.count, errors: [reason])
            }
            if SpaceGoalState.evaluate(current: goalCapacity, target: reviewedPlan.target) == .met {
                return CleanSummary(errors: ["Your target is already met. No plan actions ran."])
            }
        }

        let rootsByCategory = Dictionary(
            (fixtureScanners ?? ScannerRegistry.all()).map { ($0.info.id, $0.allowedRoots) },
            uniquingKeysWith: { a, _ in a }
        )
        var summary = CleanSummary()
        if !skipped.isEmpty {
            summary.failed += skipped.count
            summary.errors.append("\(skipped.count) advice-only item\(skipped.count == 1 ? " was" : "s were") skipped.")
        }
        var run = CleanupRun(id: UUID(), started: Date(), finished: nil, summary: summary)
        guard await saveRun(run) else { return CleanSummary(failed: items.count, errors: [receiptError ?? "Receipt history unavailable."]) }
        activeRunIDs.insert(run.id)
        defer { activeRunIDs.remove(run.id) }
        let volumes = Array(Set(items.compactMap { $0.volumeURL ?? FileScan.volumeURL(of: $0.resolvedURL) })).sorted { $0.path < $1.path }
        let capacityBefore = await Task.detached(priority: .utility) { volumes.map(CleanupCapacityChange.read) }.value
        let runID = run.id
        let execute = cleanFile
        var cleanedIDs = Set<UUID>()

        // Do not shut down an app behind the user's back. A live cache can hold
        // unsaved state, so re-check its owner immediately before each action.

        for item in items {
            run.summary = summary
            guard await saveRun(run) else {
                summary.interrupted = true; summary.errors.append(receiptError ?? "Receipt checkpoint unavailable."); break
            }
            var logEntry: RemovalLogEntry?
            if Task.isCancelled { summary.interrupted = true; break }
            if let reviewedPlan {
                if let reason = reviewedPlan.invalidReason(itemIDs: Set(items.map(\.id)), scanStarted: scanStartedAt,
                    exclusions: AppSettings.shared.excludedPaths, fullDiskAccess: FullDiskAccess.isGranted(),
                    developerCaches: AppSettings.shared.includeDeveloperCaches, simulators: AppSettings.shared.includeSimulators, capacity: goalCapacity) {
                    summary.interrupted = true; summary.errors.append(reason); break
                }
                let matches = await Task.detached(priority: .utility) { reviewedPlan.matchesSource(item) }.value
                if !matches {
                    summary.failed += 1; summary.errors.append("\(item.url.lastPathComponent): changed since goal review. Review again."); continue
                }
            }
            let runningOwners = RunningApps.runningNow(amongst: item.requiresQuitBundleIDs)
            if !runningOwners.isEmpty {
                summary.failed += 1
                summary.errors.append("\(item.url.lastPathComponent): close \(RunningApps.displayNames(for: runningOwners).joined(separator: ", ")) before cleaning")
                continue
            }
            let roots = rootsByCategory[item.categoryID] ?? [FileScan.home]
            guard let actionID = await Task.detached(priority: .utility, operation: {
                journal.begin(path: item.resolvedURL.path, category: item.categoryID, affectedBytes: item.allocatedSize,
                              actionKind: Self.actionKind(item), runID: runID)
            }).value else {
                summary.interrupted = true
                summary.errors.append(journal.error ?? "Action intent could not be recorded; further cleanup stopped.")
                break
            }
            lifecycleCheckpoint("intent")
            let outcome = await Task.detached(priority: .userInitiated) {
                execute(item, roots, proEnabled, reviewedPlan?.sources[item.id])
            }.value
            let journalSaved = await Task.detached(priority: .utility) {
                journal.finish(actionID, succeeded: outcome.ok,
                                            trashPath: outcome.movedToTrashURL?.path, detail: outcome.error)
            }.value

            lifecycleCheckpoint("outcome")
            if let err = outcome.error {
                summary.failed += 1
                summary.errors.append("\(item.url.lastPathComponent): \(err)")
            } else {
                cleanedIDs.insert(item.id)
                if let trashURL = outcome.movedToTrashURL {
                    summary.restorable.append(.init(original: item.resolvedURL, trash: trashURL))
                    logEntry = RemovalLogEntry(id: actionID, name: item.url.lastPathComponent, originalPath: item.resolvedURL.path,
                                                      trashPath: trashURL.path, bytes: outcome.bytesAffected, date: Date(), category: item.categoryID)
                } else {
                    logEntry = RemovalLogEntry(id: actionID, name: item.url.lastPathComponent, originalPath: item.resolvedURL.path,
                                                      trashPath: nil, bytes: outcome.bytesAffected, date: Date(), category: item.categoryID)
                }
            }
            logEntry?.actionKind = outcome.usedTool ? "tool" : outcome.deleted ? "delete" : "trash"
            if let entry = logEntry, !(await appendRemovals([entry])) {
                summary.accounting.record(outcome, recoveryRecorded: false)
                summary.interrupted = true
                summary.errors.append("Recovery history could not be saved; further cleanup stopped.")
                break
            }
            lifecycleCheckpoint("recovery")
            summary.accounting.record(outcome, recoveryRecorded: logEntry != nil)
            if !journalSaved {
                summary.interrupted = true
                summary.errors.append(journal.error ?? "Action outcome could not be recorded; further cleanup stopped.")
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
        if customRemovalLogURL == nil { ReclaimStats.shared.recordClean(bytes: summary.bytes) }   // affected-size estimate, not free capacity
        run.summary = summary; run.finished = Date()
        if !(await saveRun(run)) {
            summary.interrupted = true; summary.errors.append(receiptError ?? "Final receipt could not be saved.")
        }
        lifecycleCheckpoint("receipt")
        lastCleanSummary = summary
        lastCleanRunID = run.id
        // Re-save the snapshot so the cached dashboard reflects post-clean totals
        // (otherwise the next launch over-reports the reclaimable space).
        if hasScanned, customRemovalLogURL == nil { saveSnapshot() }
        return summary
    }

    /// Permanently delete recorded Trash items so their space is released now.
    /// Only the exact recorded Trash object (same identity) is removed.
    func deleteFromTrash(_ ids: Set<UUID>) async -> (count: Int, bytes: Int64) {
        guard !isCleaning, !isRestoring else { return (0, 0) }
        let entries = removalLog.filter { ids.contains($0.id) && $0.recoverable && $0.trashPath != nil }
        guard !entries.isEmpty else { return (0, 0) }
        isCleaning = true
        defer { isCleaning = false }
        let result = await Task.detached(priority: .userInitiated) { () -> (Int, Int64) in
            var count = 0, bytes: Int64 = 0
            for entry in entries {
                guard let path = entry.trashPath else { continue }
                if Cleaner.deleteTrashedCopy(at: URL(fileURLWithPath: path), identity: entry.trashIdentity) {
                    count += 1; bytes += entry.bytes
                }
            }
            return (count, bytes)
        }.value
        return result
    }

    nonisolated static func actionKind(_ item: ScanItem) -> String {
        switch item.cleanMethod {
        case .tool: return "tool"
        case .emptyTrash: return "delete"
        default: return item.deleteImmediately ? "delete" : "trash"
        }
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
