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

    private static let now = Date()
    private static func daysAgo(_ days: Int) -> Date { now.addingTimeInterval(-Double(days) * 86_400) }

    /// The two sample cleans, the same ones Activity lists as receipts. Each one
    /// is a step up in the free-space history below, on the day it ran.
    static let cleans: [(date: Date, freed: Int64)] = [(daysAgo(21), 17_100_000_000), (daysAgo(11), 14_000_000_000)]

    /// Thirty daily readings: free space falling about 3 GB a day, which is what
    /// the sample "full in about 12 days" forecast says, lifted by the two cleans.
    static let capacityHistory: [CapacityReading] =
        [98.2, 94.9, 92.5, 88.9, 86.2, 83.2, 79.3, 77.2, 91.3, 88.6,
         85.0, 82.0, 79.6, 76.3, 73.3, 70.6, 67.0, 64.6, 75.6, 72.3,
         69.6, 66.6, 63.0, 60.6, 57.6, 54.3, 51.6, 48.6, 45.3, 42.6]
            .enumerated().map { index, gigabytes in
                CapacityReading(date: daysAgo(29 - index),
                                volumeID: volumeID,
                                available: Int64(gigabytes * 1_000_000_000),
                                total: totalBytes)
            }
    static var current: CapacityReading {
        CapacityReading(volumeID: volumeID, available: availableBytes, total: totalBytes)
    }
}

/// `--preview-ui --showcase`: the sample Mac dressed for the website's
/// screenshots. The "sample" labels and hover marks are left out and the main
/// buttons look ready, but every action stays switched off by preview mode.
enum Showcase {
    static let active = CommandLine.arguments.contains("--preview-ui") && CommandLine.arguments.contains("--showcase")
    /// When the sample scan ran, for the "scanned 4 minutes ago" lines.
    static let scanDate = Date().addingTimeInterval(-4 * 60)
}
