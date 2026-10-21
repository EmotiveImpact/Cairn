import Foundation

/// File sizes are estimates from a scan, never evidence of released capacity.
struct CleanupAccounting: Codable, Sendable {
    private(set) var trashCount = 0
    private(set) var trashBytes: Int64 = 0
    private(set) var recordedRecoveryCount = 0
    private(set) var toolCount = 0
    private(set) var toolBytes: Int64 = 0
    /// Optional so receipts written before deletion existed still decode.
    private var deletedStored: Int64?
    /// Space released now: deleted files, emptied Trash and tool cleans.
    var freedBytes: Int64 { deletedStored ?? 0 }
    var completedCount: Int { trashCount + toolCount }
    var estimatedAffectedBytes: Int64 { trashBytes + toolBytes }
    var missingRecoveryCount: Int { trashCount - recordedRecoveryCount }

    mutating func record(_ outcome: Cleaner.Outcome, recoveryRecorded: Bool = false) {
        guard outcome.ok else { return }
        let bytes = max(0, outcome.bytesAffected)
        if outcome.deleted { deletedStored = (deletedStored ?? 0) + bytes }
        if outcome.usedTool { toolCount += 1; toolBytes += bytes }
        else {
            trashCount += 1; trashBytes += bytes
            if outcome.movedToTrashURL != nil && recoveryRecorded { recordedRecoveryCount += 1 }
        }
    }
}

/// A before/after observation of macOS available capacity. Other apps, snapshots
/// and purgeable data can change it too: do not attribute its delta to Cairn.
struct CleanupCapacityChange: Identifiable, Codable, Sendable {
    struct Reading: Codable, Sendable {
        var volumeID: String
        var name: String
        var available: Int64
        var date = Date()
    }
    let id: String
    let before: Reading?
    let after: Reading?
    var name: String { before?.name ?? after?.name ?? "Volume" }
    var delta: Int64? {
        guard let before, let after, !before.volumeID.isEmpty,
              before.volumeID == after.volumeID, before.available >= 0, after.available >= 0 else { return nil }
        return after.available - before.available
    }
    var changeText: String {
        guard let delta else { return "Change unavailable" }
        if delta == 0 { return "No measured change" }
        return "\(Fmt.size(abs(delta))) \(delta > 0 ? "more" : "less") available"
    }
    static func read(_ url: URL) -> Reading? {
        let fresh = URL(fileURLWithPath: url.path)
        guard let values = try? fresh.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeNameKey, .volumeAvailableCapacityForImportantUsageKey]),
              let id = values.volumeUUIDString, !id.isEmpty,
              let available = values.volumeAvailableCapacityForImportantUsage, available >= 0 else { return nil }
        return Reading(volumeID: id, name: values.volumeName ?? "Volume", available: available)
    }
}

/// Shared before/after volume observations for specialist receipts. The source
/// volume URLs survive a move to Trash; a missing/replaced drive yields unknown.
struct CleanupCapacityWindow {
    let volumes: [URL]
    let before: [CleanupCapacityChange.Reading?]
    static func begin(urls: [URL]) async -> CleanupCapacityWindow {
        await Task.detached(priority: .utility) {
            var devices = Set<UInt64>()
            var volumes: [URL] = []
            for url in urls {
                guard let identity = SourceIdentity.read(url), devices.insert(identity.device).inserted,
                      let volume = FileScan.volumeURL(of: url) else { continue }
                volumes.append(volume)
            }
            return CleanupCapacityWindow(volumes: volumes, before: volumes.map(CleanupCapacityChange.read))
        }.value
    }
    func finish() async -> [CleanupCapacityChange] {
        let after = await Task.detached(priority: .utility) { volumes.map(CleanupCapacityChange.read) }.value
        return volumes.indices.map { CleanupCapacityChange(id: volumes[$0].path, before: before[$0], after: after[$0]) }
    }
}
