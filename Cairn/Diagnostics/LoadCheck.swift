import Foundation

/// Exercises the production scan pipeline and gate against disposable files.
/// Never enumerates a user directory, loads preferences or touches Keychain.
@MainActor enum LoadCheck {
    static func run() async {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("cairn-load-fixture-\(UUID().uuidString)")
        let probe = LoadProbe()
        var failures = 0
        func check(_ good: Bool, _ label: String) {
            print("\(good ? "PASS" : "FAIL") \(label)"); if !good { failures += 1 }
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }
            let payload = Data(repeating: 0x35, count: 512)
            for directory in 0..<20 {
                let folder = root.appendingPathComponent("batch-\(directory)")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                for file in 0..<50 { try payload.write(to: folder.appendingPathComponent("fixture-\(file).bin")) }
            }
            let baseline = MemoryWatch.residentBytes()
            var peak = baseline
            var heartbeats = 0
            var largestGap: TimeInterval = 0
            let monitor = Task { @MainActor in
                var previous = Date()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 25_000_000)
                    let now = Date()
                    largestGap = max(largestGap, now.timeIntervalSince(previous)); previous = now
                    heartbeats += 1
                    peak = max(peak, MemoryWatch.residentBytes())
                }
            }
            let started = Date()
            let gate = ScanGate()
            var completed = 0
            var interrupted = 0
            var overflowed = 0
            // Twelve rounds of overlapping requests, cancellations and fast producers.
            for round in 0..<12 {
                var requests: [Task<Int, Never>] = []
                for job in 0..<6 {
                    let index = round * 6 + job
                    requests.append(Task {
                        guard await gate.acquire() else { return 0 }
                        defer { gate.release() }
                        probe.enterOperation()
                        defer { probe.leaveOperation() }
                        let scanners = (0..<18).map { LoadScanner(root: root, index: $0, emissionCount: index % 3 == 1 ? 60 : 5_000, probe: probe) }
                        let pipeline = ScanEventPipeline(scanners: scanners, fdaGranted: false,
                            includeExternal: false, minSize: 0)
                        if index.isMultiple(of: 2) {
                            // A deliberately slow consumer must never grow its queue unbounded.
                            try? await Task.sleep(nanoseconds: 100_000_000)
                        }
                        var consumed = 0
                        for await _ in pipeline.stream {
                            if Task.isCancelled { break }
                            consumed += 1
                            if consumed.isMultiple(of: 64) { await Task.yield() }
                            if consumed >= 20_000 { break }
                        }
                        await pipeline.stopAndWait()
                        check(probe.activeScanners == 0, "Round \(round + 1), request \(job + 1): workers exited before gate release")
                        return Task.isCancelled ? 0 : pipeline.overflow.isCancelled ? 2 : 1
                    })
                }
                try? await Task.sleep(nanoseconds: 30_000_000)
                // Cancel both active/queued requests while the others await their slot.
                requests[0].cancel(); requests[2].cancel(); requests[4].cancel()
                for request in requests {
                    switch await request.value {
                    case 0: interrupted += 1
                    case 2: overflowed += 1
                    default: completed += 1
                    }
                }
            }
            monitor.cancel(); await monitor.value
            let reacquired = await gate.acquire()
            check(reacquired, "Gate remains usable after sustained mixed workload")
            if reacquired { gate.release() }
            check(probe.peakOperations == 1, "Only one heavy operation runs at once")
            check(probe.peakScanners <= 4 && probe.activeScanners == 0, "Scanner concurrency stays within four and returns to zero")
            check(interrupted >= 36 && completed > 0 && overflowed > 0, "Queued cancellation, successful completion and bounded overflow all exercised")
            check(peak - min(peak, baseline) < 256 * 1_048_576, "Synthetic workload adds less than 256 MiB resident memory")
            check(heartbeats > 5 && largestGap < 2, "Main actor stays responsive during load")
            check(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 20, "Workload leaves fixture data in place")
            print(String(format: "LOAD: 72 requests, %d completed, %d interrupted, %d bounded-overflow; %.2fs elapsed", completed, interrupted, overflowed, Date().timeIntervalSince(started)))
            print(String(format: "MEMORY: baseline %.1f MiB; sampled peak %.1f MiB; end %.1f MiB", Double(baseline) / 1_048_576, Double(peak) / 1_048_576, Double(MemoryWatch.residentBytes()) / 1_048_576))
            print(String(format: "RESPONSIVENESS: %d heartbeats; largest main-actor gap %.3fs", heartbeats, largestGap))
        } catch { check(false, "Load fixture failure: \(error.localizedDescription)") }
        print("Load checks: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}

private final class LoadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var operations = 0, scanners = 0, maxOperations = 0, maxScanners = 0
    var activeScanners: Int { lock.withLock { scanners } }
    var peakOperations: Int { lock.withLock { maxOperations } }
    var peakScanners: Int { lock.withLock { maxScanners } }
    func enterOperation() { lock.withLock { operations += 1; maxOperations = max(maxOperations, operations) } }
    func leaveOperation() { lock.withLock { operations -= 1 } }
    func enterScanner() { lock.withLock { scanners += 1; maxScanners = max(maxScanners, scanners) } }
    func leaveScanner() { lock.withLock { scanners -= 1 } }
}

private struct LoadScanner: CairnScanner {
    let root: URL
    let index: Int
    let emissionCount: Int
    let probe: LoadProbe
    var info: CategoryInfo { CategoryInfo(id: "load-\(index)", title: "Fixture", subtitle: "", systemImage: "folder", group: .general, requiresFDA: false) }
    func scan(_ context: ScanContext) async {
        probe.enterScanner()
        defer { probe.leaveScanner() }
        guard !context.isCancelled() else { return }
        let measurement = FileScan.measure(root)
        let url = root.appendingPathComponent("batch-0/fixture-0.bin")
        for item in 0..<emissionCount {
            guard !context.isCancelled() else { return }
            context.emit(ScanItem(url: url, resolvedURL: url, allocatedSize: measurement.allocatedSize,
                                 categoryID: info.id, severity: .review, note: "Synthetic item \(item)"))
            context.progress("Synthetic \(item)")
        }
    }
}
