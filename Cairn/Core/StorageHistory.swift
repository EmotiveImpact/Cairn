import Foundation

/// Records free space over time and projects when the disk runs out.
///
/// A cleaner that only reports the present tense makes the user do the
/// forecasting themselves. One sample a day for 90 days is enough to answer the
/// question they actually care about — "how long have I got?" — and it costs a
/// single `statfs` per launch.
///
/// Local only, stored beside the scan snapshot.
enum StorageHistory {
    struct Sample: Codable {
        let date: Date
        let freeBytes: Int64
    }

    /// Which way the disk is heading, and how long until it bites.
    struct Forecast {
        /// Bytes consumed per day. Negative means space is being freed.
        let bytesPerDay: Double
        /// Days until free space hits the danger floor, if it's filling.
        let daysUntilFull: Int?
        /// Days of history the fit is based on — the honesty caveat.
        let sampleDays: Int

        var isFilling: Bool { bytesPerDay > 0 }
    }

    /// Below this, macOS starts thrashing (no room for swap or caches).
    private static let dangerFloor: Int64 = 5_000_000_000   // 5 GB
    private static let maxSamples = 90
    /// A fit on two or three points is noise, not a trend.
    private static let minSamplesForForecast = 4

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileScan.home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base.appendingPathComponent("Cairn", isDirectory: true)
        return dir.appendingPathComponent("storage-history.json")
    }

    static func load() -> [Sample] {
        guard let data = try? Data(contentsOf: fileURL),
              let samples = try? JSONDecoder().decode([Sample].self, from: data) else { return [] }
        return samples
    }

    /// Records today's free space. Safe to call on every launch — it keeps one
    /// sample per calendar day, so a user who opens Cairn ten times a day doesn't
    /// skew the fit toward today.
    static func record(freeBytes: Int64 = Volumes.homeFree()) {
        var samples = load()
        let now = Date()
        if let last = samples.last, Calendar.current.isDate(last.date, inSameDayAs: now) {
            samples[samples.count - 1] = Sample(date: now, freeBytes: freeBytes)
        } else {
            samples.append(Sample(date: now, freeBytes: freeBytes))
        }
        if samples.count > maxSamples { samples = Array(samples.suffix(maxSamples)) }
        if let data = try? JSONEncoder().encode(samples) {
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Least-squares fit of free space against time. Returns nil until there's
    /// enough history to say anything honest.
    static func forecast(currentFree: Int64 = Volumes.homeFree()) -> Forecast? {
        let samples = load()
        guard samples.count >= minSamplesForForecast, let first = samples.first else { return nil }

        // x = days since the first sample, y = free bytes.
        let points: [(x: Double, y: Double)] = samples.map {
            ($0.date.timeIntervalSince(first.date) / 86_400, Double($0.freeBytes))
        }
        let n = Double(points.count)
        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }
        let sumXY = points.reduce(0) { $0 + $1.x * $1.y }
        let sumXX = points.reduce(0) { $0 + $1.x * $1.x }

        let denominator = n * sumXX - sumX * sumX
        guard abs(denominator) > .ulpOfOne else { return nil }   // all samples same day
        let slope = (n * sumXY - sumX * sumY) / denominator      // bytes of free space per day

        let bytesPerDay = -slope                                  // positive = filling up
        let spanDays = Int(points.last!.x.rounded()) + 1

        guard bytesPerDay > 0 else {
            return Forecast(bytesPerDay: bytesPerDay, daysUntilFull: nil, sampleDays: spanDays)
        }
        let headroom = Double(currentFree - dangerFloor)
        guard headroom > 0 else {
            return Forecast(bytesPerDay: bytesPerDay, daysUntilFull: 0, sampleDays: spanDays)
        }
        let days = headroom / bytesPerDay
        // Beyond a year the projection is meaningless; report it as "not soon".
        return Forecast(bytesPerDay: bytesPerDay,
                        daysUntilFull: days > 365 ? nil : Int(days.rounded()),
                        sampleDays: spanDays)
    }

    /// Human phrasing for the System Status row.
    static func summary(currentFree: Int64 = Volumes.homeFree()) -> (text: String, urgent: Bool) {
        guard let f = forecast(currentFree: currentFree) else {
            return ("Learning your usage", false)
        }
        guard let days = f.daysUntilFull else {
            return (f.isFilling ? "No risk in the next year" : "Freeing up space", false)
        }
        switch days {
        case 0:          return ("Out of space now", true)
        case 1...14:     return ("Full in ~\(days) days", true)
        case 15...60:    return ("Full in ~\(days / 7) weeks", true)
        default:         return ("Full in ~\(max(2, days / 30)) months", false)
        }
    }
}
