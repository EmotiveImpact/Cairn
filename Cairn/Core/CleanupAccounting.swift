import Foundation

/// File sizes are estimates from a scan, never evidence of released capacity.
struct CleanupAccounting {
    private(set) var trashCount = 0
    private(set) var trashBytes: Int64 = 0
    private(set) var recordedRecoveryCount = 0
    private(set) var toolCount = 0
    private(set) var toolBytes: Int64 = 0
    var completedCount: Int { trashCount + toolCount }
    var estimatedAffectedBytes: Int64 { trashBytes + toolBytes }
    var missingRecoveryCount: Int { trashCount - recordedRecoveryCount }

    mutating func record(_ outcome: Cleaner.Outcome, recoveryRecorded: Bool = false) {
        guard outcome.ok else { return }
        let bytes = max(0, outcome.bytesAffected)
        if outcome.usedTool { toolCount += 1; toolBytes += bytes }
        else {
            trashCount += 1; trashBytes += bytes
            if outcome.movedToTrashURL != nil && recoveryRecorded { recordedRecoveryCount += 1 }
        }
    }
}

/// A before/after observation of macOS available capacity. Other apps, snapshots
/// and purgeable data can change it too: do not attribute its delta to Cairn.
struct CleanupCapacityChange: Identifiable {
    struct Reading {
        var volumeID: String
        var name: String
        var available: Int64
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
