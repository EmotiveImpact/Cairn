import Foundation
import Observation

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
struct CandidateReading: Codable, Identifiable {
    struct Category: Codable, Identifiable {
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
                       alreadyAlerted: Bool, minimumInterval: TimeInterval = 5 * 60) -> Decision {
        guard target > 0 else { return .unchanged }
        if current.available >= target + 2_000_000_000 { return .clear }
        guard !alreadyAlerted, current.available < target,
              let previous, previous.volumeID == current.volumeID,
              current.date.timeIntervalSince(previous.date) >= minimumInterval,
              previous.available < target else { return .unchanged }
        return .alert
    }
}

@MainActor @Observable final class StorageControl {
    static let shared = StorageControl()
    private struct Archive: Codable {
        var version: Int
        var capacity: [CapacityReading]
        var candidates: [CandidateReading]
    }
    private static let minimumSampleInterval: TimeInterval = 5 * 60
    private static let maxArchiveBytes = 2 * 1024 * 1024
    private static var archiveURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Cairn", isDirectory: true)
            .appendingPathComponent("storage-control-v1.json")
    }

    private(set) var capacity: [CapacityReading] = []
    private(set) var candidates: [CandidateReading] = []
    private(set) var current: CapacityReading?
    private(set) var error: String?
    private(set) var lastChecked: Date?
    private var loaded = false
    private var revision: Data?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    private init() {}

    var changes: [CandidateChange] { CandidateComparison.changes(candidates) }
    var latestCapacity: [CapacityReading] {
        CapacitySeries.visible(stored: capacity, current: current)
    }
    var currentAvailable: Int64? { current?.available }
    var reserveBytes: Int64 { Int64(AppSettings.shared.reserveGB) * 1_000_000_000 }
    var reserveShortfall: Int64? {
        guard AppSettings.shared.reserveEnabled, let free = currentAvailable else { return nil }
        return max(0, reserveBytes - free)
    }

    func load() {
        guard !loaded else { return }
        loaded = true
        let url = Self.archiveURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= Self.maxArchiveBytes else {
                throw CocoaError(.fileReadTooLarge)
            }
            let data = try Data(contentsOf: url)
            guard data.count <= Self.maxArchiveBytes else { throw CocoaError(.fileReadTooLarge) }
            let archive = try JSONDecoder().decode(Archive.self, from: data)
            guard archive.version == 1, archive.capacity.allSatisfy({ $0.available >= 0 && $0.total > 0 && !$0.volumeID.isEmpty }),
                  archive.candidates.allSatisfy({ !$0.volumeID.isEmpty && Set($0.categories.map(\.id)).count == $0.categories.count }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            capacity = archive.capacity.sorted { $0.date < $1.date }
            candidates = archive.candidates.sorted { $0.date < $1.date }
            revision = data
        } catch {
            self.error = "Storage history could not be read. The existing file was preserved; new history is paused."
        }
    }

    func start() {
        load()
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            await self?.refreshCapacity()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(300)) } catch { break }
                guard let self else { break }
                if AppSettings.shared.reserveEnabled && !AppSettings.shared.reservePaused { await self.refreshCapacity() }
            }
        }
    }

    func refreshCapacity(force: Bool = false) async {
        load()
        let reading = await Task.detached(priority: .utility) { CapacityProbe.read() }.value
        lastChecked = Date()
        guard let reading else {
            current = nil
            if error == nil { error = "Internal storage is unavailable. No capacity change was recorded." }
            return
        }
        // Concurrent activation/manual refreshes can finish out of order.
        // Keep the newest observation rather than reverting the visible number.
        if let current, current.date > reading.date { return }
        current = reading
        if error?.hasPrefix("Internal storage is unavailable") == true { error = nil }
        guard error == nil else { return }
        if !force, let last = capacity.last, last.volumeID == reading.volumeID,
           reading.date.timeIntervalSince(last.date) < Self.minimumSampleInterval { return }
        capacity.append(reading)
        pruneAndSave()
        considerReserveAlert(reading)
    }

    func recordCompletedScan(_ store: ScanStore) {
        load()
        guard error == nil, store.comparisonError == nil, store.phase == .finished,
              store.comparisonScopeStable, !store.includeExternalVolumes,
              let volumeID = current?.volumeID,
              let lastComparison = store.comparisonReadings.last,
              let started = store.scanStartedAt, lastComparison.date >= started else { return }
        let scope = lastComparison.scope
        let readings = store.buckets.map { bucket in
            CandidateReading.Category(id: bucket.id, title: bucket.info.title,
                icon: bucket.info.systemImage, group: bucket.info.group,
                bytes: bucket.totalSize, complete: bucket.complete && !bucket.permissionGap)
        }
        guard !readings.isEmpty else { return }
        candidates.append(CandidateReading(volumeID: volumeID, scope: scope, categories: readings))
        pruneAndSave()
    }

    private func pruneAndSave() {
        let now = Date()
        let fineCutoff = now.addingTimeInterval(-7 * 86_400)
        let oldest = now.addingTimeInterval(-90 * 86_400)
        // Preserve five-minute samples for a week, then one sample per day.
        var olderDays = Set<String>()
        var older: [CapacityReading] = []
        for reading in capacity.reversed() where reading.date >= oldest && reading.date < fineCutoff {
            let key = reading.volumeID + ":" + String(Int(reading.date.timeIntervalSince1970 / 86_400))
            if olderDays.insert(key).inserted { older.append(reading) }
        }
        capacity = Array((Array(older.reversed()) + capacity.filter { $0.date >= fineCutoff }).suffix(2_300))
            .sorted { $0.date < $1.date }
        candidates = Array(candidates.filter { $0.date >= oldest }.suffix(32))
        save()
    }

    private func save() {
        guard error == nil else { return }
        do {
            let url = Self.archiveURL
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path) {
                guard let revision, try Data(contentsOf: url) == revision else { throw CocoaError(.fileWriteFileExists) }
            } else if revision != nil { throw CocoaError(.fileNoSuchFile) }
            let data = try JSONEncoder().encode(Archive(version: 1, capacity: capacity, candidates: candidates))
            guard data.count <= Self.maxArchiveBytes else { throw CocoaError(.fileWriteOutOfSpace) }
            let directory = url.deletingLastPathComponent()
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            revision = data
        } catch {
            self.error = "Storage history could not be saved. The existing record was preserved; new history is paused."
        }
    }

    private func considerReserveAlert(_ reading: CapacityReading) {
        guard AppSettings.shared.reserveEnabled && !AppSettings.shared.reservePaused else { return }
        let target = reserveBytes
        if (defaults.object(forKey: "cairn.reserveAlertTarget") as? NSNumber)?.int64Value != target {
            defaults.set(target, forKey: "cairn.reserveAlertTarget")
            defaults.set(false, forKey: "cairn.reserveAlerted")
        }
        switch ReserveAlertPolicy.decide(current: reading, previous: capacity.dropLast().last,
                                         target: target, alreadyAlerted: defaults.bool(forKey: "cairn.reserveAlerted")) {
        case .clear: defaults.set(false, forKey: "cairn.reserveAlerted")
        case .unchanged: break
        case .alert:
            defaults.set(true, forKey: "cairn.reserveAlerted")
            Notify.send(title: "Cairn · Space reserve is low",
                        body: "\(Fmt.size(reading.available)) available on your Mac; your chosen reserve is \(Fmt.size(target)). Open Cairn to review options.")
        }
    }
}
