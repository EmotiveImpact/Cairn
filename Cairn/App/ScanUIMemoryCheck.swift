import Foundation

/// Explicit developer diagnostic using real stores and rendered workspaces.
/// Reads internal files; never invokes cleanup. Reports aggregate metrics only.
@MainActor enum ScanUIMemoryCheck {
    static func run(store: ScanStore, duplicates: DuplicateStore,
                    route: (NavSection) -> Void, report: URL) async {
        var lines = ["FULL UI READ-ONLY SCAN CHECK"]
        let baseline = MemoryWatch.footprintBytes()
        var peak = baseline
        var failed = false
        func record(_ line: String) {
            lines.append(line)
            try? lines.joined(separator: "\n").write(to: report, atomically: true, encoding: .utf8)
        }
        func observe(_ label: String, limit: TimeInterval, running: () -> Bool) async -> Bool {
            let start = Date()
            var last = start
            var lastReport = start
            var gap: TimeInterval = 0
            while running() {
                try? await Task.sleep(nanoseconds: 100_000_000)
                let now = Date()
                gap = max(gap, now.timeIntervalSince(last)); last = now
                let footprint = MemoryWatch.footprintBytes()
                peak = max(peak, footprint)
                if now.timeIntervalSince(lastReport) >= 10 {
                    record("\(label): footprint \(footprint/1_048_576) MiB; RSS \(MemoryWatch.residentBytes()/1_048_576) MiB; groups \(duplicates.groups.count); hashed \(duplicates.hashedCount); items \(store.buckets.reduce(0) { $0 + $1.items.count })")
                    lastReport = now
                }
                if footprint > baseline + 384 * 1_048_576 { failed = true; break }
                if now.timeIntervalSince(start) >= limit { break }
            }
            if gap > 2 { failed = true }
            record("\(label): elapsed \(String(format: "%.2f", Date().timeIntervalSince(start)))s; main-actor max gap \(String(format: "%.3f", gap))s; \(running() ? "bounded stop requested" : "finished")")
            return !running()
        }
        record("Baseline footprint \(baseline/1_048_576) MiB")
        route(.duplicates)
        duplicates.startIfNeeded()
        let duplicateFinished = await observe("Duplicates", limit: 120, running: { duplicates.isScanning })
        if !duplicateFinished { await duplicates.cancelAndWait() }
        record("Duplicates settled: \(duplicates.phase), \(duplicates.groups.count) groups; limited \(duplicates.wasLimited)")
        if !failed {
            route(.smartScan)
            store.startScan()
            let smartFinished = await observe("Smart Scan", limit: 150, running: { store.isScanning })
            if !smartFinished { await store.cancelAndWait() }
            record("Smart Scan settled: \(store.phase); \(store.completedCount)/\(store.totalCount) categories; \(store.buckets.reduce(0) { $0 + $1.items.count }) items")
        }
        record("Footprint peak \(peak/1_048_576) MiB; final \(MemoryWatch.footprintBytes()/1_048_576) MiB")
        record(failed ? "UI MEMORY CHECK FAILED" : "UI MEMORY CHECK PASSED within the reported scopes and durations")
    }
}
