import Foundation

/// Explicitly invoked real-machine diagnostics. Only scanner read paths run;
/// no ScanStore persistence, cleanup, license, configuration or recovery action.
@MainActor enum ReadOnlyScanCheck {
    static func run() async {
        let baseline = MemoryWatch.residentBytes()
        var peak = baseline
        var maximumGap: TimeInterval = 0
        var failed = false
        let gate = ScanGate()
        print("Read-only scanner check: internal storage only; paths and file contents are not logged.")
        for (pass, duration) in [5.0, 90.0, 5.0].enumerated() {
            var count = 0, completedCategories = 0, gaps = 0, done = false
            var reachedLimit = false
            let start = Date()
            let operation = Task {
                guard await gate.acquire() else { return }
                defer { gate.release() }
                let pipeline = ScanEventPipeline(scanners: ScannerRegistry.all(), fdaGranted: FullDiskAccess.isGranted(), includeExternal: false, minSize: 5 * 1024 * 1024)
                for await event in pipeline.stream {
                    if Task.isCancelled { break }
                    switch event {
                    case .item(let item): count += 1; if item.permissionDenied || item.note.localizedCaseInsensitiveContains("partial") { gaps += 1 }
                    case .finishedCategory: completedCategories += 1
                    case .done: done = true
                    default: break
                    }
                    if count >= 20_000 { reachedLimit = true; break }
                }
                reachedLimit = reachedLimit || pipeline.overflow.isCancelled
                await pipeline.stopAndWait()
            }
            let monitor = Task { @MainActor in
                var previous = Date(), lastReport = Date()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    guard !Task.isCancelled else { break }
                    let now = Date(), bytes = MemoryWatch.residentBytes()
                    maximumGap = max(maximumGap, now.timeIntervalSince(previous)); previous = now
                    peak = max(peak, bytes)
                    if bytes > baseline + 512 * 1_048_576 { failed = true; operation.cancel() }
                    if now.timeIntervalSince(lastReport) > 10 {
                        let line = "Pass \(pass + 1): \(count) items, \(completedCategories) categories, RSS \(bytes / 1_048_576) MiB\n"
                        FileHandle.standardError.write(Data(line.utf8)); lastReport = now
                    }
                }
            }
            let deadline = Task {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                if !Task.isCancelled { operation.cancel() }
            }
            await operation.value
            deadline.cancel(); monitor.cancel(); await monitor.value
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > duration + 20 { failed = true }
            print(String(format: "PASS %d: %.2fs, %d items, %d/%d finished categories, %d reported access/partial gaps; %@", pass + 1, elapsed, count, completedCategories, ScannerRegistry.all().count, gaps, done && !reachedLimit ? "engine finished" : reachedLimit ? "bounded result limit" : "cancelled and workers stopped"))
        }
        let available = await gate.acquire()
        if available { gate.release() } else { failed = true }
        if maximumGap > 2 { failed = true }
        print(String(format: "MEMORY: baseline %.1f MiB; sampled peak %.1f MiB; final %.1f MiB", Double(baseline)/1_048_576, Double(peak)/1_048_576, Double(MemoryWatch.residentBytes())/1_048_576))
        print(String(format: "Largest main-actor heartbeat gap %.3fs. No cleanup or persistent scan results written.", maximumGap))
        print(failed ? "READ-ONLY STABILITY CHECK FAILED" : "READ-ONLY STABILITY CHECK PASSED; limited to accessible paths and the durations above")
        exit(failed ? 1 : 0)
    }
}
