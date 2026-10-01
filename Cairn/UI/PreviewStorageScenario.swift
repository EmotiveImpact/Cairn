import Foundation

/// One fictional Mac for every sample-only screen. Keeping the volume, current
/// reading, reserve and planner target together prevents contradictory claims
/// when a preview navigates between Overview, Changes, Activity and Storage.
enum PreviewStorageScenario {
    static let volumeID = "SAMPLE-INTERNAL"
    static let totalBytes: Int64 = 494_000_000_000
    static let availableBytes: Int64 = 42_600_000_000
    static let reserveBytes: Int64 = 30_000_000_000
    static let goalGB = 60

    static let capacityHistory: [CapacityReading] =
        [108.0, 101.0, 81.0, 62.0, 49.0, 39.1, 42.6]
            .enumerated().map { index, gigabytes in
                CapacityReading(date: Date().addingTimeInterval(Double(index - 6) * 86_400),
                                volumeID: volumeID,
                                available: Int64(gigabytes * 1_000_000_000),
                                total: totalBytes)
            }
    static var current: CapacityReading {
        CapacityReading(volumeID: volumeID, available: availableBytes, total: totalBytes)
    }
}
