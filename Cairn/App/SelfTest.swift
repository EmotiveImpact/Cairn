import Foundation

/// Headless engine check: `Cairn --selftest`. Runs every scanner directly (no
/// UI), prints found items + the reclaimable total. Proves the scan engine works
/// on a real Mac without launching the window server.
enum SelfTest {
    final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var items: [ScanItem] = []
        func add(_ item: ScanItem) { lock.lock(); items.append(item); lock.unlock() }
    }

    static func run() {
        let sem = DispatchSemaphore(value: 0)
        let collector = Collector()
        Task {
            await scan(into: collector)
            sem.signal()
        }
        sem.wait()
        report(collector.items)
    }

    private static func scan(into collector: Collector) async {
        let scanners = ScannerRegistry.all()
        // Sequential + timed so we can see which scanner is the long pole.
        for s in scanners {
            let local = Collector()
            let ctx = ScanContext(
                fdaGranted: FullDiskAccess.isGranted(),
                includeExternalVolumes: false,
                minSizeBytes: 5 * 1024 * 1024,
                emit: { collector.add($0); local.add($0) },
                progress: { _ in },
                isCancelled: { false }
            )
            let start = Date()
            await s.scan(ctx)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let total = local.items.reduce(Int64(0)) { $0 + $1.allocatedSize }
            FileHandle.standardError.write(
                "  [\(s.info.id)] \(local.items.count) items · \(Fmt.size(total)) · \(ms) ms\n".data(using: .utf8)!
            )
        }
    }

    private static func report(_ items: [ScanItem]) {
        print("\n========== Cairn self-test ==========")
        print("Full Disk Access: \(FullDiskAccess.isGranted() ? "granted (or N/A)" : "NOT granted")")
        print("Home free space:  \(Fmt.size(Volumes.homeFree()))")
        let byCat = Dictionary(grouping: items, by: { $0.categoryID })
        var grand: Int64 = 0
        for (cat, catItems) in byCat.sorted(by: { $0.key < $1.key }) {
            let total = catItems.reduce(Int64(0)) { $0 + $1.allocatedSize }
            grand += total
            print("\n▸ \(cat) — \(Fmt.size(total)) across \(catItems.count) item(s)")
            for it in catItems.sorted(by: { $0.allocatedSize > $1.allocatedSize }).prefix(12) {
                let tier = it.severity.label.uppercased().padding(toLength: 6, withPad: " ", startingAt: 0)
                let paid = it.cleanMethod.isPaid ? " [tool]" : ""
                print("   \(tier) \(Fmt.size(it.allocatedSize).padding(toLength: 9, withPad: " ", startingAt: 0)) \(it.url.lastPathComponent)\(paid)")
            }
        }
        print("\n====================================")
        print("RECLAIMABLE TOTAL (2 scanners): \(Fmt.size(grand))")
        print("====================================\n")
    }
}
