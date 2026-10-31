import Foundation
import Darwin

/// Read-only figures macOS reports directly, cheap enough to take every few
/// minutes. They explain a change and never permit one: swap belongs to macOS
/// and local snapshots to Time Machine, so neither becomes a cleanup candidate.
struct SystemSignals: Codable, Sendable, Equatable {
    let date: Date
    /// Total size of macOS's swap files (`vm.swapusage`). Nil when unreadable.
    let swapBytes: Int64?
    /// Local Time Machine snapshots on the startup disk. Nil when tmutil did not answer.
    let snapshotCount: Int?

    static func read(now: Date = Date()) -> SystemSignals {
        SystemSignals(date: now, swapBytes: swapTotal(), snapshotCount: localSnapshotCount())
    }

    /// Swap lives on its own volume in the same container as your files, so
    /// when it grows, free space shrinks. macOS gives it back by itself.
    static func swapTotal() -> Int64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return Int64(clamping: usage.xsu_total)
    }

    /// A count only: macOS does not report what each local snapshot holds.
    static func localSnapshotCount() -> Int? {
        guard let result = try? ToolRunner.run("tmutil", ["listlocalsnapshots", "/"], timeout: 5), result.ok else { return nil }
        return TimeMachineSnapshotsScanner.parseSnapshotTokens(result.stdout).count
    }
}

/// When free space falls fast, before it reaches the reserve. Alert only: the
/// policy reads capacity readings and decides whether to look, nothing more.
enum FastDropPolicy {
    /// How far back a drop is measured.
    static let window: TimeInterval = 30 * 60
    /// This much gone inside the window always counts as fast.
    static let dropThreshold: Int64 = 5_000_000_000
    /// A smaller drop counts when, at its rate, the reserve is this close.
    static let projectionMinimum: Int64 = 2_000_000_000
    static let projectionHorizon: TimeInterval = 2 * 3_600
    /// At most one alert in this time, however long the drop goes on.
    static let cooldown: TimeInterval = 60 * 60

    struct Drop: Sendable {
        let from: CapacityReading
        let to: CapacityReading
        /// Seconds until the reserve at this rate. Nil without a reserve, when
        /// already below it, or over too short a span to project from.
        let secondsToReserve: TimeInterval?
        var bytes: Int64 { from.available - to.available }
        var interval: TimeInterval { to.date.timeIntervalSince(from.date) }
    }

    static func detect(current: CapacityReading, recent: [CapacityReading], reserve: Int64?,
                       lastAlert: Date?) -> Drop? {
        if let lastAlert, current.date.timeIntervalSince(lastAlert) < cooldown { return nil }
        // Same disk, inside the window, at least a minute apart, and taken after
        // the last alert so one drop is never reported twice.
        let candidates = recent.filter { reading -> Bool in
            guard reading.volumeID == current.volumeID, reading.date < current.date else { return false }
            let age = current.date.timeIntervalSince(reading.date)
            guard age >= 60, age <= window else { return false }
            if let lastAlert, reading.date <= lastAlert { return false }
            return true
        }
        guard let from = candidates.max(by: { $0.available == $1.available ? $0.date > $1.date : $0.available < $1.available }) else { return nil }
        let bytes = from.available - current.available
        guard bytes > 0 else { return nil }
        let span = current.date.timeIntervalSince(from.date)
        var secondsToReserve: TimeInterval?
        if let reserve, reserve > 0, current.available > reserve, span >= 10 * 60 {
            secondsToReserve = Double(current.available - reserve) / (Double(bytes) / span)
        }
        if bytes >= dropThreshold {
            return Drop(from: from, to: current, secondsToReserve: secondsToReserve)
        }
        if bytes >= projectionMinimum, let seconds = secondsToReserve, seconds <= projectionHorizon {
            return Drop(from: from, to: current, secondsToReserve: secondsToReserve)
        }
        return nil
    }

    /// Cheap places first, so the time limit is spent where answers come
    /// quickly: a disk image is one file, a worktree can be a million.
    static let measureOrder = [
        "docker-disk", "orbstack-disk", "colima-disk", "ollama-models", "lmstudio-models", "huggingface",
        "xcode-build", "simulators", "npm-cache", "claude-data", "cursor-worktrees", "conductor-workspaces",
        "codex-state", "downloads", "chrome-cache", "safari-cache",
    ]
    static func ordered(_ roots: [ObservedRoot]) -> [ObservedRoot] {
        func rank(_ id: String) -> Int { measureOrder.firstIndex(of: id) ?? measureOrder.count }
        return roots.sorted { rank($0.id) == rank($1.id) ? $0.id < $1.id : rank($0.id) < rank($1.id) }
    }
    /// The whole check stops after this long; one folder gets at most `perRoot`.
    static let totalSeconds: TimeInterval = 30
    static let perRoot: TimeInterval = 8
}

/// What Cairn found after a fast drop: the notification and the card on
/// Changes. Every figure is a measured change in one place over its own dated
/// interval. They are never added up to explain the whole drop.
struct FastDropReport: Codable, Sendable, Identifiable, Equatable {
    struct Grower: Codable, Sendable, Identifiable, Equatable {
        let id: String
        let title: String
        let icon: String
        /// Growth in bytes, or nil for something counted rather than sized.
        let bytes: Int64?
        /// How many new local snapshots, when this is the snapshot line.
        let count: Int?
        /// Start of the interval this growth was measured over.
        let since: Date?

        var phrase: String {
            if let bytes { return "\(title) grew by \(Fmt.size(bytes))" }
            let n = count ?? 0
            return n == 1 ? "1 new local Time Machine snapshot appeared" : "\(n) new local Time Machine snapshots appeared"
        }
    }

    /// Smaller growth than this is not worth naming.
    static let minimumGrowth: Int64 = 500_000_000
    static let swapTitle = "Swap (memory kept on disk)"

    let id: UUID
    let date: Date
    let dropBytes: Int64
    let interval: TimeInterval
    let reserve: Int64?
    let secondsToReserve: TimeInterval?
    let growers: [Grower]
    /// Why the folder check did not run, when it did not.
    let note: String?
    /// Places with an earlier size that could not be measured in time.
    var unfinished: [String] = []

    var title: String { "Cairn · Space is going fast" }
    var headline: String { "\(Fmt.size(dropBytes)) less free space in \(Self.spoken(interval))" }
    var reserveLine: String? {
        guard let reserve, let seconds = secondsToReserve, seconds <= 3 * 3_600 else { return nil }
        return "At this rate you'll reach your \(Fmt.size(reserve)) reserve in about \(Self.spoken(seconds))."
    }
    var findingLine: String {
        if !growers.isEmpty { return Self.list(growers.prefix(3).map(\.phrase)) + "." }
        if note != nil { return "Swap and snapshots didn't grow much." }
        return "None of the places Cairn checks grew much, so the space went somewhere Cairn doesn't watch."
    }
    var body: String {
        ([headline + ".", findingLine] + [reserveLine, note].compactMap { $0 }).joined(separator: " ")
    }

    static func make(drop: FastDropPolicy.Drop, before: SystemSignals?, after: SystemSignals?,
                     changes: [LocationChange], reserve: Int64?, note: String?, unfinished: [String] = [],
                     now: Date = Date()) -> FastDropReport {
        var sized: [Grower] = []
        if let old = before?.swapBytes, let new = after?.swapBytes, new - old >= minimumGrowth {
            sized.append(Grower(id: "swap", title: swapTitle, icon: "memorychip", bytes: new - old, count: nil, since: before?.date))
        }
        for change in changes where change.delta >= minimumGrowth {
            let root = change.after.root
            sized.append(Grower(id: root.id, title: root.title, icon: root.icon, bytes: change.delta, count: nil, since: change.before.ended))
        }
        sized.sort { ($0.bytes ?? 0) == ($1.bytes ?? 0) ? $0.id < $1.id : ($0.bytes ?? 0) > ($1.bytes ?? 0) }
        if let old = before?.snapshotCount, let new = after?.snapshotCount, new > old {
            sized.append(Grower(id: "snapshots", title: "Local Time Machine snapshots", icon: "clock.arrow.circlepath",
                                bytes: nil, count: new - old, since: before?.date))
        }
        return FastDropReport(id: UUID(), date: now, dropBytes: drop.bytes, interval: drop.interval,
                              reserve: reserve, secondsToReserve: drop.secondsToReserve,
                              growers: Array(sized.prefix(5)), note: note, unfinished: unfinished)
    }

    static func spoken(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 90 { return minutes == 1 ? "1 minute" : "\(minutes) minutes" }
        return "\(max(2, Int((Double(minutes) / 60).rounded()))) hours"
    }
    static func list(_ parts: [String]) -> String {
        guard let last = parts.last else { return "" }
        return parts.count == 1 ? last : parts.dropLast().joined(separator: ", ") + " and " + last
    }
}
