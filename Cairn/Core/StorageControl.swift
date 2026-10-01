import Foundation
import Observation
import AppKit
import UserNotifications

/// One small, local evidence store for the control-panel journey. It does not
/// infer a writing process, or turn observed bytes into cleanup permission.
struct CapacityReading: Codable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let volumeID: String
    let available: Int64
    let total: Int64
    init(date: Date = Date(), volumeID: String, available: Int64, total: Int64) {
        self.id = UUID(); self.date = date; self.volumeID = volumeID
        self.available = available; self.total = total
    }
}

enum CapacityProbe {
    static func read() -> CapacityReading? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let values = try? home.resourceValues(forKeys: [
            .volumeUUIDStringKey, .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey, .volumeIsInternalKey
        ]), values.volumeIsInternal == true,
              let id = values.volumeUUIDString, !id.isEmpty,
              let available = values.volumeAvailableCapacityForImportantUsage, available >= 0,
              let total = values.volumeTotalCapacity, total > 0 else { return nil }
        return CapacityReading(volumeID: id, available: available, total: Int64(total))
    }
}

/// A category reading is an observation of *cleanup candidates*, never a
/// measurement of all data owned by an app or of total occupied capacity.
struct CandidateReading: Codable, Identifiable, Sendable {
    struct Category: Codable, Identifiable, Sendable {
        let id: String
        let title: String
        let icon: String
        let group: CategoryGroup
        let bytes: Int64
        let complete: Bool
    }
    let id: UUID
    let date: Date
    let volumeID: String
    let scope: ScanComparison.Scope
    let categories: [Category]
    init(date: Date = Date(), volumeID: String, scope: ScanComparison.Scope, categories: [Category]) {
        id = UUID(); self.date = date; self.volumeID = volumeID
        self.scope = scope; self.categories = categories
    }
}

struct CandidateChange: Identifiable {
    let category: CandidateReading.Category
    let delta: Int64
    let before: Date
    let after: Date
    var id: String { category.id }
}

/// Display the latest live capacity check even if the five-minute persistence
/// interval has not elapsed. A manual Finder change should update the chart
/// immediately without writing an extra history file on every activation.
enum CapacitySeries {
    static func visible(stored: [CapacityReading], current: CapacityReading?) -> [CapacityReading] {
        guard let volumeID = current?.volumeID ?? stored.last?.volumeID else { return [] }
        var result = stored.filter { $0.volumeID == volumeID }
        if let current, let last = result.last {
            if current.date > last.date && current.available != last.available { result.append(current) }
        } else if let current {
            result.append(current)
        }
        return result
    }
}

/// Shared chart coverage. A pointer over a missing interval must not select a
/// distant endpoint and make it look as though that interval was measured.
struct CapacityPlot {
    struct Point: Identifiable {
        let reading: CapacityReading
        let segment: Int
        var id: UUID { reading.id }
    }
    struct Gap: Identifiable {
        let before: CapacityReading
        let after: CapacityReading
        var id: UUID { after.id }
        var start: Date { before.date }
        var end: Date { after.date }
        var detail: String {
            "No saved readings · \(start.formatted(date: .abbreviated, time: .shortened)) – \(end.formatted(date: .abbreviated, time: .shortened))"
        }
    }
    let points: [Point]
    let gaps: [Gap]

    init(readings: [CapacityReading], maximumInterval: TimeInterval) {
        var points: [Point] = [], gaps: [Gap] = []
        var previous: CapacityReading?, segment = 0
        for reading in readings.sorted(by: { $0.date < $1.date }) {
            if let previous {
                if reading.volumeID != previous.volumeID { segment += 1 }
                else if reading.date.timeIntervalSince(previous.date) > maximumInterval {
                    segment += 1
                    gaps.append(Gap(before: previous, after: reading))
                }
            }
            points.append(Point(reading: reading, segment: segment))
            previous = reading
        }
        self.points = points; self.gaps = gaps
    }
    func gap(at date: Date) -> Gap? {
        gaps.first { date > $0.start && date < $0.end }
    }
    func reading(near date: Date) -> CapacityReading? {
        guard gap(at: date) == nil else { return nil }
        return points.min { abs($0.reading.date.timeIntervalSince(date)) < abs($1.reading.date.timeIntervalSince(date)) }?.reading
    }
}

enum CandidateComparison {
    static func changes(_ readings: [CandidateReading]) -> [CandidateChange] {
        guard readings.count >= 2 else { return [] }
        let before = readings[readings.count - 2], after = readings[readings.count - 1]
        guard before.date < after.date, before.volumeID == after.volumeID,
              !before.scope.externalVolumes, !after.scope.externalVolumes,
              before.scope.categories == after.scope.categories,
              before.scope.fullDiskAccess == after.scope.fullDiskAccess,
              before.scope.exclusions == after.scope.exclusions,
              before.scope.developerCaches == after.scope.developerCaches,
              before.scope.simulators == after.scope.simulators else { return [] }
        let old = Dictionary(uniqueKeysWithValues: before.categories.map { ($0.id, $0) })
        return after.categories.compactMap { current -> CandidateChange? in
            guard let previous = old[current.id], previous.complete, current.complete,
                  previous.bytes >= 0, current.bytes >= 0,
                  previous.bytes != current.bytes else { return nil }
            return CandidateChange(category: current, delta: current.bytes - previous.bytes,
                                   before: before.date, after: after.date)
        }.sorted { abs($0.delta) > abs($1.delta) }
    }
}

/// A goal is satisfied only by a fresh capacity reading from the same internal
/// volume. Candidate sizes, Trash moves and retained-source copies do not enter
/// this calculation.
enum SpaceGoal {
    static func shortfall(available: Int64?, target: Int64) -> Int64? {
        guard let available, available >= 0, target > 0 else { return nil }
        return max(0, target - available)
    }
    static func reached(available: Int64?, target: Int64) -> Bool {
        shortfall(available: available, target: target) == 0
    }
    /// A signed change in available space, never attributed to a particular
    /// deletion. Only readings from the same internal volume can be compared.
    static func observedChange(from start: CapacityReading?, to current: CapacityReading?) -> Int64? {
        guard let start, let current, start.volumeID == current.volumeID,
              start.date < current.date else { return nil }
        return current.available - start.available
    }
}

enum ReserveAlertPolicy {
    enum Decision: Equatable { case alert, clear, unchanged }
    static func decide(current: CapacityReading, previous: CapacityReading?, target: Int64,
                       alreadyAlerted: Bool, urgentAlreadyAlerted: Bool = true, minimumInterval: TimeInterval = 5 * 60) -> Decision {
        guard target > 0 else { return .unchanged }
        if current.available >= target + 2_000_000_000 { return .clear }
        if current.available < min(target, 2_000_000_000), !urgentAlreadyAlerted { return .alert }
        guard !alreadyAlerted, current.available < target,
              let previous, previous.volumeID == current.volumeID,
              current.date.timeIntervalSince(previous.date) >= minimumInterval,
              current.date.timeIntervalSince(previous.date) <= 30 * 60,
              previous.available < target else { return .unchanged }
        return .alert
    }
}

@MainActor @Observable final class StorageControl {
    static let shared = StorageControl()
    private static let minimumSampleInterval: TimeInterval = 5 * 60
    private(set) var capacity: [CapacityReading] = []
    private(set) var candidates: [CandidateReading] = []
    private(set) var locations: [LocationReading] = []
    private(set) var current: CapacityReading?
    @ObservationIgnored private var reserveObservation: CapacityReading?
    private(set) var error: String?
    private(set) var lastChecked: Date?
    private(set) var measuringLocations = false
    private(set) var measurementStatus = ""
    private(set) var monitoringStatus = "Monitoring is off"
    private(set) var pendingLocationCount = 0
    private(set) var notificationStatus = "Notification permission not checked"
    @ObservationIgnored private var watcher: LocationEventWatcher?
    @ObservationIgnored private var dirty = DirtyLocationSchedule(rootIDs: Set(ObservedRoot.catalogue().map(\.id)))
    @ObservationIgnored private var workspaceTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var pressureSource: DispatchSourceMemoryPressure?
    private var sleeping = false
    private var memoryPressure = false
    private var backgroundMeasurement = false
    private var nextCapacityCheck = Date.distantPast
    private var loaded = false
    private var sequence: UInt64 = 0
    @ObservationIgnored private var loadTask: Task<StorageEvidenceSnapshot, Error>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var measurementTask: Task<Void, Never>?
    @ObservationIgnored private var measurementCancellation: CancelBox?
    @ObservationIgnored private let evidence: StorageEvidenceStore
    @ObservationIgnored private let probe: @Sendable () -> CapacityReading?
    private let defaults = UserDefaults.standard

    init(evidence: StorageEvidenceStore = StorageEvidenceStore(),
         probe: @escaping @Sendable () -> CapacityReading? = { CapacityProbe.read() }) {
        self.evidence = evidence; self.probe = probe
    }
    var changes: [CandidateChange] { CandidateComparison.changes(candidates) }
    var locationChanges: [LocationChange] { LocationComparison.changes(locations) }
    var latestLocations: [LocationReading] { LocationComparison.latest(locations) }
    var latestCapacity: [CapacityReading] { CapacitySeries.visible(stored: capacity, current: current) }
    var currentAvailable: Int64? { current?.available }
    var reserveBytes: Int64 { Int64(AppSettings.shared.reserveGB) * 1_000_000_000 }
    var reserveShortfall: Int64? {
        guard AppSettings.shared.reserveEnabled, let free = currentAvailable else { return nil }
        return max(0, reserveBytes - free)
    }
    private func apply(_ snapshot: StorageEvidenceSnapshot) {
        guard snapshot.sequence >= sequence else { return }
        sequence = snapshot.sequence
        capacity = snapshot.capacity; candidates = snapshot.candidates; locations = snapshot.locations
    }
    func load() async {
        guard !loaded else { return }
        if loadTask == nil { loadTask = Task { try await evidence.load() } }
        do { if let snapshot = try await loadTask?.value { apply(snapshot) } }
        catch { self.error = "Storage history could not be read. Existing records are preserved; new history is paused." }
        loaded = true; loadTask = nil
    }
    func start() {
        guard monitorTask == nil else { return }
        installLifecycleObservers()
        configureMonitoring()
        monitorTask = Task { [weak self] in
            await self?.refreshNotificationStatus()
            await self?.refreshCapacity()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { break }
                guard let self else { break }
                configureMonitoring()
                guard monitoringEnabled, !sleeping else { continue }
                if Date() >= nextCapacityCheck {
                    nextCapacityCheck = Date().addingTimeInterval(300)
                    await refreshCapacity()
                }
                scheduleBackgroundMeasurement()
            }
        }
    }
    private var monitoringEnabled: Bool {
        AppSettings.shared.reserveEnabled && !AppSettings.shared.reservePaused
    }
    func configureMonitoring() {
        let settings = AppSettings.shared
        if settings.reservePaused, let until = settings.reservePauseUntil, until <= Date() {
            settings.reservePaused = false; settings.reservePauseUntil = nil
        }
        guard monitoringEnabled, !sleeping else {
            watcher?.stop(); watcher = nil
            if backgroundMeasurement { cancelLocationMeasurement() }
            monitoringStatus = sleeping ? "Paused while your Mac sleeps" : settings.reservePaused ? "Monitoring paused" : "Monitoring is off"
            return
        }
        guard settings.locationMonitoringEnabled else {
            watcher?.stop(); watcher = nil
            if backgroundMeasurement { cancelLocationMeasurement() }
            monitoringStatus = "Capacity alerts active · folder monitoring is off"
            return
        }
        if watcher == nil {
            let roots = ObservedRoot.nonOverlapping(ObservedRoot.catalogue())
            watcher = LocationEventWatcher(roots: roots) { [weak self] ids, gap in
                Task { @MainActor [weak self] in
                    guard let self, self.monitoringEnabled, AppSettings.shared.locationMonitoringEnabled, !self.sleeping else { return }
                    if gap { self.dirty.reconcile(at: Date()) }
                    else { self.dirty.mark(ids, at: Date()) }
                    self.pendingLocationCount = self.dirty.pending.count
                }
            }
            dirty.reconcile(at: Date())
            pendingLocationCount = dirty.pending.count

        }
        monitoringStatus = watcher == nil ? "Folder events unavailable; capacity alerts remain active" : traversalPauseReason ?? (pendingLocationCount > 0 ? "\(pendingLocationCount) locations waiting for a quiet measurement" : "Watching known locations · no cleanup")
    }
    func refreshNotificationStatus() async {
        guard let center = Notify.center else {
            notificationStatus = "Notifications unavailable from an unbundled build. Open Cairn.app to enable them."
            return
        }
        let settings = await center.notificationSettings()
        notificationStatus = settings.authorizationStatus == .denied ? "Notifications denied · reserve status remains visible in Cairn" : settings.authorizationStatus == .notDetermined ? "Notifications not enabled · reserve status remains visible in Cairn" : "Notifications allowed; macOS Focus may silence delivery"
    }
    func pauseMonitoring(until: Date?) {
        AppSettings.shared.reservePaused = true
        AppSettings.shared.reservePauseUntil = until
        configureMonitoring()
    }
    func resumeMonitoring() {
        AppSettings.shared.reservePauseUntil = nil
        AppSettings.shared.reservePaused = false
        nextCapacityCheck = .distantPast
        configureMonitoring()
    }
    private var traversalPauseReason: String? {
        if memoryPressure { return "Folder measurements paused for memory pressure" }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return "Folder measurements paused in Low Power Mode" }
        if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical { return "Folder measurements paused while your Mac is hot" }
        guard let current, Date().timeIntervalSince(current.date) < 600 else { return "Waiting for a recent capacity reading" }
        if current.available < 2_000_000_000 { return "Folder measurements paused below 2 GB available" }
        if error != nil { return "Folder history paused; review the storage-history message" }
        return nil
    }
    private func scheduleBackgroundMeasurement() {
        guard watcher != nil, traversalPauseReason == nil, measurementTask == nil else {
            if backgroundMeasurement && traversalPauseReason != nil { cancelLocationMeasurement() }
            return
        }
        guard let id = dirty.ready(at: Date(), suspended: false).first,
              let root = ObservedRoot.catalogue().first(where: { $0.id == id }),
              ScanGate.shared.tryAcquireForMonitoring() else { return }
        let revision = dirty.begin(id, at: Date())!
        launchLocationMeasurement(roots: [root], source: "monitor", gateAlreadyHeld: true, revision: revision)
    }
    private func installLifecycleObservers() {
        guard workspaceTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = true; self?.configureMonitoring() }
        })
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.sleeping = false; self.watcher?.stop(); self.watcher = nil
                    self.nextCapacityCheck = .distantPast; self.configureMonitoring()
                    await self.refreshCapacity()
                }
            })
        }
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        pressure.setEventHandler { [weak self] in
            guard let self, let pressure = self.pressureSource else { return }
            self.memoryPressure = !pressure.data.contains(.normal)
            if self.memoryPressure { self.cancelLocationMeasurement() }
            self.configureMonitoring()
        }
        pressure.resume(); pressureSource = pressure
    }
    func refreshCapacity(force: Bool = false) async {
        await load()
        // Await the complete refresh, including publication of the result. A
        // second caller must not resume with old capacity just because the probe
        // finished before its first caller returned to the main actor.
        if let refreshTask { await refreshTask.value; return }
        let task = Task { await performCapacityRefresh(force: force) }
        refreshTask = task
        await task.value
        refreshTask = nil
    }
    private func performCapacityRefresh(force: Bool) async {
        let reading = await Task.detached(priority: .utility) { [probe] in probe() }.value
        lastChecked = Date()
        guard let reading else {
            current = nil
            if error == nil { error = "Internal storage is unavailable. No capacity change was recorded." }
            return
        }
        if let current, current.date > reading.date { return }
        current = reading
        // Alert observations remain useful even if a full disk prevents history
        // writes. Keep one confirming sample; rapid activation reads cannot
        // continually reset the five-minute confirmation window.
        let previous = reserveObservation ?? capacity.last
        considerReserveAlert(reading, previous: previous)
        if previous == nil || previous?.volumeID != reading.volumeID ||
            reading.date.timeIntervalSince(previous!.date) >= Self.minimumSampleInterval {
            reserveObservation = reading
        }
        if error?.hasPrefix("Internal storage is unavailable") == true { error = nil }
        guard error == nil else { return }
        if !force, let last = capacity.last, last.volumeID == reading.volumeID,
           reading.date.timeIntervalSince(last.date) < Self.minimumSampleInterval { return }
        do {
            apply(try await evidence.append(capacity: reading))
        } catch { historyWriteFailed() }
    }
    func recordCompletedScan(_ store: ScanStore) async {
        guard store.comparisonError == nil, store.phase == .finished,
              store.comparisonScopeStable, !store.includeExternalVolumes,
              let volumeID = current?.volumeID,
              let lastComparison = store.comparisonReadings.last,
              let started = store.scanStartedAt, lastComparison.date >= started else { return }
        let readings = store.buckets.map { bucket in
            CandidateReading.Category(id: bucket.id, title: bucket.info.title,
                icon: bucket.info.systemImage, group: bucket.info.group,
                bytes: bucket.totalSize, complete: bucket.complete && !bucket.permissionGap)
        }
        guard !readings.isEmpty else { return }
        let reading = CandidateReading(volumeID: volumeID, scope: lastComparison.scope, categories: readings)
        await load()
        guard error == nil else { return }
        do { apply(try await evidence.append(candidates: reading)) }
        catch { historyWriteFailed() }
    }
    /// Explicit scan/re-measure only. Merely visiting a view cannot traverse files.
    func measureLocations() {
        guard measurementTask == nil else { return }
        launchLocationMeasurement(roots: ObservedRoot.nonOverlapping(ObservedRoot.catalogue()), source: "manual")
    }
    private func launchLocationMeasurement(roots: [ObservedRoot], source: String, gateAlreadyHeld: Bool = false, revision: UInt64? = nil) {
        let exclusions = AppSettings.shared.excludedPaths
        let cancellation = CancelBox()
        measurementCancellation = cancellation; backgroundMeasurement = source == "monitor"
        measuringLocations = true; measurementStatus = gateAlreadyHeld ? "Measuring changed location…" : "Waiting to measure known locations…"
        measurementTask = Task {
            defer {
                measuringLocations = false; measurementStatus = ""; measurementTask = nil
                measurementCancellation = nil; backgroundMeasurement = false
                pendingLocationCount = dirty.pending.count
            }
            if !gateAlreadyHeld { guard await ScanGate.shared.acquire(.locations) else { return } }
            defer { ScanGate.shared.release() }
            guard !cancellation.isCancelled else { return }
            measurementStatus = "Measuring known locations…"
            let worker = Task.detached(priority: .utility) {
                let deadline = ProcessInfo.processInfo.systemUptime + 30
                return roots.map { root in
                    var probe = LocationProbe()
                    probe.seconds = max(0, deadline - ProcessInfo.processInfo.systemUptime)
                    return autoreleasepool { probe.measure(root, exclusions: exclusions, source: source, cancelled: { cancellation.isCancelled || (source == "monitor" && ScanGate.shared.snapshot.queued > 0) }) }
                }
            }
            let readings = await worker.value
            if let revision, let reading = readings.first {
                dirty.finish(reading.root.id, revision: revision, complete: reading.coverage.comparable)
            }
            await load()
            guard error == nil else { return }
            do { apply(try await evidence.append(locations: readings)) }
            catch { historyWriteFailed() }
        }
    }
    func cancelLocationMeasurement() {
        guard measurementTask != nil else { return }
        measurementStatus = "Stopping location measurement…"
        measurementCancellation?.cancel(); measurementTask?.cancel()
    }
    private func historyWriteFailed() {
        error = "Storage history could not be saved. Existing records are preserved; new history is paused."
    }
    private func considerReserveAlert(_ reading: CapacityReading, previous: CapacityReading?) {
        guard AppSettings.shared.reserveEnabled && !AppSettings.shared.reservePaused else { return }
        // A bare SwiftPM launch cannot post notifications. Keep the in-app
        // reserve state, but do not consume the alert's persisted suppression
        // flags until the packaged app can actually attempt delivery.
        guard Notify.isAvailable else { return }
        if AppSettings.shared.reserveQuietHours {
            let hour = Calendar.current.component(.hour, from: reading.date)
            if hour >= 22 || hour < 8 { return }
        }
        let target = reserveBytes
        let key = reading.volumeID + ":" + String(target)
        if defaults.string(forKey: "cairn.reserveAlertScope") != key {
            defaults.set(key, forKey: "cairn.reserveAlertScope")
            defaults.set(false, forKey: "cairn.reserveAlerted")
            defaults.set(false, forKey: "cairn.reserveUrgentAlerted")
        }
        switch ReserveAlertPolicy.decide(current: reading, previous: previous,
                                         target: target, alreadyAlerted: defaults.bool(forKey: "cairn.reserveAlerted"),
                                         urgentAlreadyAlerted: defaults.bool(forKey: "cairn.reserveUrgentAlerted")) {
        case .clear:
            defaults.set(false, forKey: "cairn.reserveAlerted")
            defaults.set(false, forKey: "cairn.reserveUrgentAlerted")
        case .unchanged: break
        case .alert:
            defaults.set(true, forKey: "cairn.reserveAlerted")
            if reading.available < 2_000_000_000 { defaults.set(true, forKey: "cairn.reserveUrgentAlerted") }
            Notify.send(title: "Cairn · Space reserve is low",
                        body: "\(Fmt.size(reading.available)) available on your Mac; your chosen reserve is \(Fmt.size(target)). Open Cairn to review options.")
        }
    }
}
