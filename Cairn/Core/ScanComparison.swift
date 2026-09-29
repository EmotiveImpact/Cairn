import Foundation

/// Immutable measurements, separate from the mutable post-cleanup snapshot.
/// This compares observed cleanup candidates, not all bytes used on a volume.
enum ScanComparison {
    struct Scope: Codable, Equatable {
        var version = 1
        var categories: [String]
        var exclusions: [String]
        var developerCaches: Bool
        var simulators: Bool
        var fullDiskAccess: Bool
        var externalVolumes: Bool
    }
    struct Reading: Codable {
        var date: Date
        var scope: Scope
        var complete: Bool
        var buckets: [Bucket]
    }
    struct Bucket: Codable, Identifiable {
        var id: String
        var title: String
        var icon: String
        var group: CategoryGroup
        var bytes: Int64
    }
    struct Change: Identifiable {
        var bucket: Bucket
        var delta: Int64
        var id: String { bucket.id }
    }
    struct Result {
        var changes: [Change]
        var reason: String?
        var previousDate: Date?
        var latestDate: Date?
        var comparable: Bool { reason == nil }
    }
    static func compare(_ readings: [Reading]) -> Result {
        func unavailable(_ reason: String) -> Result {
            Result(changes: [], reason: reason, previousDate: readings.dropLast().last?.date, latestDate: readings.last?.date)
        }
        guard readings.count >= 2 else { return unavailable("Complete two scans with the same settings to see category changes.") }
        let before = readings[readings.count - 2], after = readings[readings.count - 1]
        guard before.complete && after.complete else { return unavailable("A scan was incomplete or reported access gaps. Run another complete scan to compare.") }
        guard before.scope == after.scope else { return unavailable("Scan settings or permissions changed. Complete another scan with the same settings to compare.") }
        guard !after.scope.externalVolumes else { return unavailable("Change comparisons currently support internal-storage scans only.") }
        guard after.scope.fullDiskAccess else { return unavailable("These scans have limited access. Category changes are withheld to avoid misleading totals.") }
        guard after.date > before.date else { return unavailable("The saved measurement dates cannot be compared.") }
        let beforeIDs = Set(before.buckets.map(\.id)), afterIDs = Set(after.buckets.map(\.id))
        guard beforeIDs == afterIDs, beforeIDs.count == before.buckets.count,
              afterIDs.count == after.buckets.count, afterIDs == Set(after.scope.categories),
              before.buckets.allSatisfy({ $0.bytes >= 0 }), after.buckets.allSatisfy({ $0.bytes >= 0 }) else {
            return unavailable("Category coverage changed. Missing results are not treated as zero.")
        }
        let old = Dictionary(uniqueKeysWithValues: before.buckets.map { ($0.id, $0.bytes) })
        let changes = after.buckets.compactMap { bucket -> Change? in
            guard let bytes = old[bucket.id], bytes != bucket.bytes else { return nil }
            return Change(bucket: bucket, delta: bucket.bytes - bytes)
        }.sorted { abs($0.delta) > abs($1.delta) }
        return Result(changes: changes, reason: nil, previousDate: before.date, latestDate: after.date)
    }
}
